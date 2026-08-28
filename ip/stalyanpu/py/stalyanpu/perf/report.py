"""Text and markdown reports of a performance estimate."""

from __future__ import annotations

from collections import OrderedDict

from .model import NetEstimate


def _fmt_rows(est: NetEstimate):
    rows = []
    for e in est.layers:
        l = e.layer
        shape = f"{l.k}x{l.k}s{l.s}" if l.kind == "conv" else "pool5"
        rows.append([
            l.name, shape, f"{l.ic}->{l.oc}", f"{l.out_h}x{l.out_w}",
            f"{l.macs / 1e6:.1f}", str(e.n_tiles), str(e.n_pass), str(e.n_oct),
            str(e.cycles), f"{e.cycles / (est.hw.clk_mhz * 1e3):.3f}",
            f"{100 * e.util:.0f}", e.bound,
            f"{(e.bytes_rd + e.bytes_wr) / 1e6:.2f}",
        ])
    return rows


HEADER = ["layer", "kernel", "ch", "out", "MMAC", "tiles", "pass", "oct",
          "cycles", "ms", "util%", "bound", "MB"]


def table(est: NetEstimate, markdown: bool = False) -> str:
    rows = _fmt_rows(est)
    widths = [max(len(h), *(len(r[i]) for r in rows)) for i, h in enumerate(HEADER)]
    out = []
    if markdown:
        out.append("| " + " | ".join(h.ljust(w) for h, w in zip(HEADER, widths)) + " |")
        out.append("|" + "|".join("-" * (w + 2) for w in widths) + "|")
        for r in rows:
            out.append("| " + " | ".join(c.ljust(w) for c, w in zip(r, widths)) + " |")
    else:
        out.append("  ".join(h.ljust(w) for h, w in zip(HEADER, widths)))
        for r in rows:
            out.append("  ".join(c.ljust(w) for c, w in zip(r, widths)))
    return "\n".join(out)


def group_summary(est: NetEstimate) -> str:
    groups: "OrderedDict[str, list]" = OrderedDict()
    for e in est.layers:
        groups.setdefault(e.layer.group or e.layer.name, []).append(e)
    total = est.cycles
    lines = [f"{'group':14s} {'kcycles':>9s} {'share%':>7s} {'MMAC':>9s} {'util%':>6s}"]
    for g, es in groups.items():
        cyc = sum(e.cycles for e in es)
        macs = sum(e.macs for e in es)
        util = macs / (cyc * est.hw.macs_per_cycle) if cyc else 0
        lines.append(f"{g:14s} {cyc / 1e3:9.0f} {100 * cyc / total:7.1f} {macs / 1e6:9.1f} {100 * util:6.0f}")
    return "\n".join(lines)


def summary(est: NetEstimate) -> str:
    hw = est.hw
    ddr_gbps = est.bytes_total * est.fps / 1e9
    return "\n".join([
        f"hwcfg          : {hw.name} ({hw.n_ic} IC x {hw.n_oc} OC = {hw.macs_per_cycle} MAC/cycle, "
        f"{hw.dsp_count} DSP, {hw.clk_mhz:.0f} MHz, peak {hw.peak_gmacs:.0f} GMAC/s)",
        f"network MACs   : {est.macs / 1e9:.2f} GMAC per frame",
        f"NPU cycles     : {est.cycles / 1e6:.3f} M cycles = {est.npu_ms:.2f} ms "
        f"(array utilization {100 * est.util:.1f}%)",
        f"DDR traffic    : {est.bytes_total / 1e6:.1f} MB per frame = {ddr_gbps:.2f} GB/s at "
        f"{est.fps:.1f} fps (budget {hw.ddr_bw_gbps:.2f} GB/s)",
        f"CPU tail       : {est.cpu_ms:.1f} ms (overlapped)",
        f"frame time     : {est.frame_ms:.2f} ms -> {est.fps:.1f} fps",
    ])
