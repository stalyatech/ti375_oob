"""Placement of activation tensors in the DDR scratch region.

Every tensor gets a (buffer, plane offset) placement. Zero copy rules:

* CONCAT: the output is one buffer; a CONV or MAXPOOL5 input is written
  straight into it at its plane offset; SPLIT outputs that appear in order
  place the split source inside the concat buffer as well.
* SPLIT: outputs are plane sub ranges of the input placement.
* UPSAMPLE2: a view of its input, read with the UPS flag by the consumer.
* A CONCAT that has a view as input (an upsample) is virtual: consumers read
  its inputs as separate sources.

Buffers get lifetimes [first producer index, last consumer index] and a
first fit allocation with 4 KB alignment. The graph input and outputs are
pinned at the start of the scratch region.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from ..frontend.graph import NpuGraph
from . import layout

ALIGN = 4096


@dataclass
class Buffer:
    name: str
    planes: int
    h: int
    w: int
    pinned: bool = False
    first_use: int = 0
    last_use: int = 0
    offset: int = -1

    @property
    def plane_stride(self) -> int:
        return layout.plane_bytes(self.h, self.w)

    @property
    def row_stride(self) -> int:
        return self.w * layout.CH_GROUP

    @property
    def size(self) -> int:
        return self.planes * self.plane_stride


@dataclass
class Placement:
    buffer: Buffer
    plane: int          # first plane of the tensor inside the buffer
    planes: int

    @property
    def base_offset(self) -> int:
        return self.buffer.offset + self.plane * self.buffer.plane_stride


@dataclass
class Source:
    """One input source of a descriptor."""
    placement: Placement
    upsample: bool = False


@dataclass
class Allocation:
    buffers: list = field(default_factory=list)
    place: dict = field(default_factory=dict)        # tensor -> Placement
    virtual_concat: set = field(default_factory=set) # concat outputs read as multiple sources
    scratch_size: int = 0

    def sources(self, tensor: str) -> list:
        """Sources a consumer reads for ``tensor``."""
        if tensor in self.virtual_concat:
            return self._virtual[tensor]
        if tensor in self.views:
            src, ups = self.views[tensor]
            base = self.sources(src)
            assert len(base) == 1, "upsample of a multi source tensor"
            return [Source(base[0].placement, ups or base[0].upsample)]
        return [Source(self.place[tensor])]

    views: dict = field(default_factory=dict)        # tensor -> (source tensor, upsample flag)
    _virtual: dict = field(default_factory=dict)


def _align(x: int) -> int:
    return (x + ALIGN - 1) // ALIGN * ALIGN


def allocate(g: NpuGraph) -> Allocation:
    a = Allocation()
    order = {op.name: i for i, op in enumerate(g.ops)}
    producer = {}
    for i, op in enumerate(g.ops):
        for o in op.outputs:
            producer[o] = (op, i)

    def shape(name):
        t = g.tensors[name]
        return t.c, t.h, t.w

    def new_buffer(name, c, h, w, pinned=False):
        b = Buffer(name, layout.n_planes(c), h, w, pinned)
        a.buffers.append(b)
        return b

    # Graph inputs and outputs first, pinned.
    for name in g.inputs:
        c, h, w = shape(name)
        a.place[name] = Placement(new_buffer(name, c, h, w, pinned=True), 0, layout.n_planes(c))
    for name in g.outputs:
        c, h, w = shape(name)
        a.place[name] = Placement(new_buffer(name, c, h, w, pinned=True), 0, layout.n_planes(c))

    # Views first so concat placement can see through splits and upsamples.
    for op in g.ops:
        if op.kind == "UPSAMPLE2":
            a.views[op.outputs[0]] = (op.inputs[0], True)

    # Concats: one buffer, inputs placed inside when possible.
    for op in g.ops:
        if op.kind != "CONCAT":
            continue
        out = op.outputs[0]
        c, h, w = shape(out)
        inputs = op.inputs
        if any(i in a.views for i in inputs) or any(i in a.place and a.place[i].buffer.pinned for i in inputs):
            a.virtual_concat.add(out)
            continue
        buf = a.place[out].buffer if out in a.place else new_buffer(out, c, h, w)
        if out not in a.place:
            a.place[out] = Placement(buf, 0, layout.n_planes(c))
        plane = 0
        i = 0
        while i < len(inputs):
            name = inputs[i]
            ic = shape(name)[0]
            prod, _ = producer[name]
            if prod.kind == "SPLIT":
                # Consecutive outputs of the same split, in order, place the split source.
                outs = prod.outputs
                j = outs.index(name)
                run = 0
                while i + run < len(inputs) and j + run < len(outs) and inputs[i + run] == outs[j + run]:
                    run += 1
                src = prod.inputs[0]
                before = sum(prod.attrs["sizes"][:j]) // layout.CH_GROUP
                src_planes = layout.n_planes(shape(src)[0])
                if src not in a.place and j == 0 and run == len(outs):
                    a.place[src] = Placement(buf, plane, src_planes)
                    for q, o in enumerate(outs):
                        po = sum(prod.attrs["sizes"][:q]) // layout.CH_GROUP
                        a.place[o] = Placement(buf, plane + po, layout.n_planes(shape(o)[0]))
                    plane += src_planes
                    i += run
                    continue
                # Fallback: the split source has its own buffer, so the concat
                # cannot be built in place; make it virtual.
                a.virtual_concat.add(out)
                break
            if name in a.place:
                a.virtual_concat.add(out)
                break
            a.place[name] = Placement(buf, plane, layout.n_planes(ic))
            plane += layout.n_planes(ic)
            i += 1
        if out in a.virtual_concat:
            # Undo partial placement into this buffer.
            for n in list(a.place):
                if a.place[n].buffer is buf and n != out:
                    del a.place[n]
            if out in a.place and not buf.pinned:
                del a.place[out]
                a.buffers.remove(buf)

    # Remaining tensors: own buffers; split outputs as sub ranges.
    for op in g.ops:
        for o in op.outputs:
            if o in a.place or o in a.views or o in a.virtual_concat:
                continue
            if op.kind == "SPLIT":
                src = op.inputs[0]
                if src not in a.place:
                    c, h, w = shape(src)
                    a.place[src] = Placement(new_buffer(src, c, h, w), 0, layout.n_planes(c))
                j = op.outputs.index(o)
                po = sum(op.attrs["sizes"][:j]) // layout.CH_GROUP
                p = a.place[src]
                a.place[o] = Placement(p.buffer, p.plane + po, layout.n_planes(shape(o)[0]))
            elif op.kind == "CONCAT":
                continue
            else:
                c, h, w = shape(o)
                a.place[o] = Placement(new_buffer(o, c, h, w), 0, layout.n_planes(c))
    for op in g.ops:
        if op.kind == "SPLIT" and op.inputs[0] not in a.place:
            raise RuntimeError(f"split source {op.inputs[0]} not placed")

    # Sources of virtual concats.
    for op in g.ops:
        if op.kind == "CONCAT" and op.outputs[0] in a.virtual_concat:
            srcs = []
            for i in op.inputs:
                srcs += a.sources(i)
            a._virtual[op.outputs[0]] = srcs

    # Lifetimes.
    for b in a.buffers:
        b.first_use = len(g.ops)
        b.last_use = -1
    def touch(name, idx):
        for s in a.sources(name):
            b = s.placement.buffer
            b.first_use = min(b.first_use, idx)
            b.last_use = max(b.last_use, idx)
    for idx, op in enumerate(g.ops):
        for name in op.inputs + op.outputs + ([op.attrs["residual"]] if op.attrs.get("residual") else []):
            if name in a.place or name in a.views or name in a.virtual_concat:
                touch(name, idx)
    for name in g.inputs:
        a.place[name].buffer.first_use = -1
    for name in g.outputs:
        a.place[name].buffer.last_use = len(g.ops)

    # First fit allocation. Pinned buffers first at fixed offsets.
    cursor = 0
    for b in a.buffers:
        if b.pinned:
            b.offset = cursor
            cursor = _align(cursor + b.size)
    live = []   # (offset, size, last_use)
    for b in sorted([b for b in a.buffers if not b.pinned], key=lambda b: b.first_use):
        live = [x for x in live if x[2] >= b.first_use]
        candidates = sorted(live)
        pos = cursor
        for off, size, _ in candidates:
            if pos + b.size <= off:
                break
            pos = max(pos, _align(off + size))
        b.offset = pos
        live.append((pos, b.size, b.last_use))
    a.scratch_size = max(_align(b.offset + b.size) for b in a.buffers)
    return a
