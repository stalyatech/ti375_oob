// SPDX-License-Identifier: GPL-2.0
/*
 * fcu_rproc: remoteproc driver for the soft FCU SoC of the ti375_oob design.
 *
 * The FCU is controlled through amp_ctrl (rtl/amp_ctrl.v, sw/amp/amp_ctrl.h):
 * a reset hold, a boot address, doorbells and scratch registers. The FCU always
 * starts in its on-chip RAM, whose image is a boot stub: it jumps to BOOT_ADDR
 * only when the host has also written AMP_BOOT_MAGIC.
 *
 *   start   BOOT_ADDR = ELF entry, magic, release the hold, check that the
 *           stub took the boot path
 *   stop    ask the FCU to park (no bus traffic), wait for it, then hold it;
 *           a hold in the middle of a DDR burst could wedge the AXI switch
 *           the FCU shares with gDMA, gSDHC and npu1
 *   attach  the FSBL releases the FCU at power-up, so it is usually running
 *           when Linux comes up; the driver attaches instead of restarting it
 *
 * Firmware segments may only land in the FCU reserved-memory region. The FCU
 * is left running when this driver goes away (module unload, unbind): Linux
 * stopping must not stop the flight software.
 */
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/elf.h>
#include <linux/firmware.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_reserved_mem.h>
#include <linux/platform_device.h>
#include <linux/remoteproc.h>

#include "amp_ctrl.h"

/*
 * Exported by remoteproc_elf_loader.c but declared only in the in-tree
 * drivers/remoteproc/remoteproc_internal.h, which an out-of-tree module
 * cannot include.
 */
int rproc_elf_sanity_check(struct rproc *rproc, const struct firmware *fw);
u64 rproc_elf_get_boot_addr(struct rproc *rproc, const struct firmware *fw);
int rproc_elf_load_segments(struct rproc *rproc, const struct firmware *fw);
int rproc_elf_load_rsc_table(struct rproc *rproc, const struct firmware *fw);

#define FCU_PARK_TIMEOUT_MS	500
#define FCU_BOOT_TIMEOUT_MS	100

struct fcu_rproc {
	struct device *dev;
	void __iomem *amp;
	struct reserved_mem *rmem;
	struct completion parked;
};

static u32 amp_rd(struct fcu_rproc *fr, u32 reg)
{
	return readl(fr->amp + reg);
}

static void amp_wr(struct fcu_rproc *fr, u32 reg, u32 val)
{
	writel(val, fr->amp + reg);
}

/*
 * The hard SoC's data caches hold CPU writes back from DDR; the Efinix custom
 * instruction 0x500F writes the local cache back and invalidates it. The FCU
 * reaches DDR through the SoC's coherent fabric port, but the image is written
 * back to DDR anyway before the FCU is let go: it costs nothing and does not
 * depend on the coherency path.
 */
static void fcu_dcache_wbinv_local(void *unused)
{
	asm volatile("fence rw, rw\n\t.word 0x500F\n\tfence rw, rw" ::: "memory");
}

static bool fcu_held(struct fcu_rproc *fr)
{
	return amp_rd(fr, AMP_REG_CTRL) & AMP_CTRL_FCU_HOLD;
}

static bool in_region(struct fcu_rproc *fr, u64 addr, u64 len)
{
	return addr >= fr->rmem->base && len <= fr->rmem->size &&
	       addr - fr->rmem->base <= fr->rmem->size - len;
}

/* The region is no-map reserved memory, so it has to be mapped here. */
static int fcu_mem_alloc(struct rproc *rproc, struct rproc_mem_entry *mem)
{
	void *va = memremap(mem->dma, mem->len, MEMREMAP_WB);

	if (!va)
		return -ENOMEM;
	mem->va = va;
	return 0;
}

static int fcu_mem_release(struct rproc *rproc, struct rproc_mem_entry *mem)
{
	memunmap(mem->va);
	return 0;
}

static int fcu_prepare(struct rproc *rproc)
{
	struct fcu_rproc *fr = rproc->priv;
	struct rproc_mem_entry *mem;

	mem = rproc_mem_entry_init(fr->dev, NULL, fr->rmem->base, fr->rmem->size,
				   fr->rmem->base, fcu_mem_alloc, fcu_mem_release,
				   "fcu-mem");
	if (!mem)
		return -ENOMEM;
	rproc_add_carveout(rproc, mem);
	return 0;
}

/* FCU images need no resource table until rpmsg is added. */
static int fcu_parse_fw(struct rproc *rproc, const struct firmware *fw)
{
	if (rproc_elf_load_rsc_table(rproc, fw))
		dev_dbg(&rproc->dev, "no resource table in the firmware\n");
	return 0;
}

static int fcu_sanity_check(struct rproc *rproc, const struct firmware *fw)
{
	const struct elf32_hdr *ehdr = (const struct elf32_hdr *)fw->data;
	int ret = rproc_elf_sanity_check(rproc, fw);

	if (ret)
		return ret;
	if (ehdr->e_ident[EI_CLASS] != ELFCLASS32 || ehdr->e_machine != EM_RISCV) {
		dev_err(&rproc->dev, "not an RV32 ELF image\n");
		return -EINVAL;
	}
	return 0;
}

/* Every loadable segment has to fit in the FCU region. */
static int fcu_load(struct rproc *rproc, const struct firmware *fw)
{
	struct fcu_rproc *fr = rproc->priv;
	const struct elf32_hdr *ehdr = (const struct elf32_hdr *)fw->data;
	const struct elf32_phdr *phdr = (const struct elf32_phdr *)(fw->data + ehdr->e_phoff);
	int i;

	for (i = 0; i < ehdr->e_phnum; i++) {
		if (phdr[i].p_type != PT_LOAD || !phdr[i].p_memsz)
			continue;
		if (!in_region(fr, phdr[i].p_paddr, phdr[i].p_memsz)) {
			dev_err(&rproc->dev,
				"segment %d at %#x+%#x is outside the FCU region %pa+%#llx\n",
				i, phdr[i].p_paddr, phdr[i].p_memsz, &fr->rmem->base,
				(u64)fr->rmem->size);
			return -EINVAL;
		}
	}
	return rproc_elf_load_segments(rproc, fw);
}

static int fcu_start(struct rproc *rproc)
{
	struct fcu_rproc *fr = rproc->priv;
	u32 entry = rproc->bootaddr;
	unsigned long end;
	u32 state;

	if (!fcu_held(fr)) {
		dev_err(&rproc->dev, "FCU is not held; stop it first\n");
		return -EBUSY;
	}
	if (!in_region(fr, entry, 4) || (entry & 3)) {
		dev_err(&rproc->dev, "entry point %#x is outside the FCU region\n", entry);
		return -EINVAL;
	}

	reinit_completion(&fr->parked);
	amp_wr(fr, AMP_REG_BOOT_ADDR, entry);
	amp_wr(fr, AMP_REG_SCRATCH(AMP_SCR_STATE), 0);
	amp_wr(fr, AMP_REG_SCRATCH(AMP_SCR_BOOT), AMP_BOOT_MAGIC);
	on_each_cpu(fcu_dcache_wbinv_local, NULL, 1);
	amp_wr(fr, AMP_REG_CTRL, 0);

	/* The stub reports which way it went; the image itself may say nothing. */
	end = jiffies + msecs_to_jiffies(FCU_BOOT_TIMEOUT_MS);
	do {
		state = amp_rd(fr, AMP_REG_SCRATCH(AMP_SCR_STATE));
		if (state == AMP_STATE_BOOTING || state == AMP_STATE_RUNNING)
			return 0;
		if (state == AMP_STATE_LED_TEST) {
			dev_err(&rproc->dev, "the on-chip RAM stub refused BOOT_ADDR %#x\n", entry);
			amp_wr(fr, AMP_REG_SCRATCH(AMP_SCR_BOOT), 0);
			return -EIO;
		}
		usleep_range(500, 1000);
	} while (time_before(jiffies, end));

	dev_warn(&rproc->dev,
		 "no answer from the on-chip RAM stub; is the bitstream's FCU image a boot stub?\n");
	return 0;
}

/* Ask the FCU to stop its bus traffic before it is held. */
static void fcu_park(struct fcu_rproc *fr)
{
	u32 state;

	if (fcu_held(fr))
		return;

	reinit_completion(&fr->parked);
	amp_wr(fr, AMP_REG_DB_PENDING, AMP_DB_PARK);
	amp_wr(fr, AMP_REG_DB_SEND, AMP_DB_PARK);

	if (!wait_for_completion_timeout(&fr->parked,
					 msecs_to_jiffies(FCU_PARK_TIMEOUT_MS))) {
		state = amp_rd(fr, AMP_REG_SCRATCH(AMP_SCR_STATE));
		if (state != AMP_STATE_PARKED)
			dev_warn(fr->dev,
				 "FCU did not park within %d ms (state %u); holding it anyway\n",
				 FCU_PARK_TIMEOUT_MS, state);
	}
}

static int fcu_stop(struct rproc *rproc)
{
	struct fcu_rproc *fr = rproc->priv;

	fcu_park(fr);
	amp_wr(fr, AMP_REG_CTRL, AMP_CTRL_FCU_HOLD);
	/* The next release, by the FSBL or anyone else, gets the LED test. */
	amp_wr(fr, AMP_REG_SCRATCH(AMP_SCR_BOOT), 0);
	amp_wr(fr, AMP_REG_SCRATCH(AMP_SCR_STATE), 0);
	/* Doorbells the FCU rang for the old image mean nothing any more. */
	amp_wr(fr, AMP_REG_DB_PENDING, ~0u);
	return 0;
}

/* The FCU was started before Linux; there is nothing to do to take it over. */
static int fcu_attach(struct rproc *rproc)
{
	return 0;
}

static int fcu_detach(struct rproc *rproc)
{
	return 0;
}

static const struct rproc_ops fcu_rproc_ops = {
	.prepare	= fcu_prepare,
	.start		= fcu_start,
	.stop		= fcu_stop,
	.attach		= fcu_attach,
	.detach		= fcu_detach,
	.parse_fw	= fcu_parse_fw,
	.sanity_check	= fcu_sanity_check,
	.load		= fcu_load,
	.get_boot_addr	= rproc_elf_get_boot_addr,
};

static irqreturn_t fcu_irq(int irq, void *data)
{
	struct fcu_rproc *fr = data;
	u32 pending = amp_rd(fr, AMP_REG_DB_PENDING);

	if (!pending)
		return IRQ_NONE;
	amp_wr(fr, AMP_REG_DB_PENDING, pending);
	if (pending & AMP_DB_PARK)
		complete(&fr->parked);
	if (pending & AMP_DB_USER)
		dev_dbg(fr->dev, "FCU image started\n");
	return IRQ_HANDLED;
}

/* Read-only view of amp_ctrl, since /dev/mem cannot reach it. */
static const char *const fcu_state_names[] = {
	[0]			= "unknown",
	[AMP_STATE_LED_TEST]	= "led-test",
	[AMP_STATE_BOOTING]	= "booting",
	[AMP_STATE_RUNNING]	= "running",
	[AMP_STATE_PARKED]	= "parked",
};

static ssize_t fcu_status_show(struct device *dev, struct device_attribute *attr,
			       char *buf)
{
	struct rproc *rproc = dev_get_drvdata(dev);
	struct fcu_rproc *fr = rproc->priv;
	u32 state = amp_rd(fr, AMP_REG_SCRATCH(AMP_SCR_STATE));

	return sysfs_emit(buf,
			  "hold %u\nstate %s\nheartbeat %u\nmagic %#010x\nboot_addr %#010x\n",
			  fcu_held(fr),
			  state < ARRAY_SIZE(fcu_state_names) && fcu_state_names[state] ?
				fcu_state_names[state] : "?",
			  amp_rd(fr, AMP_REG_SCRATCH(AMP_SCR_HEARTBEAT)),
			  amp_rd(fr, AMP_REG_SCRATCH(AMP_SCR_MAGIC)),
			  amp_rd(fr, AMP_REG_BOOT_ADDR));
}
static DEVICE_ATTR_RO(fcu_status);

static struct attribute *fcu_attrs[] = {
	&dev_attr_fcu_status.attr,
	NULL
};
ATTRIBUTE_GROUPS(fcu);

static int fcu_rproc_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct device_node *mem_np;
	const char *fw_name = "fcu.elf";
	struct fcu_rproc *fr;
	struct rproc *rproc;
	int irq, ret;
	u32 id;

	of_property_read_string(dev->of_node, "firmware-name", &fw_name);

	rproc = devm_rproc_alloc(dev, "fcu", &fcu_rproc_ops, fw_name, sizeof(*fr));
	if (!rproc)
		return -ENOMEM;
	fr = rproc->priv;
	fr->dev = dev;
	init_completion(&fr->parked);

	fr->amp = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(fr->amp))
		return PTR_ERR(fr->amp);

	id = amp_rd(fr, AMP_REG_ID);
	if (id != AMP_ID_VALUE)
		return dev_err_probe(dev, -ENODEV, "amp_ctrl ID reads %#x\n", id);

	mem_np = of_parse_phandle(dev->of_node, "memory-region", 0);
	if (!mem_np)
		return dev_err_probe(dev, -EINVAL, "no memory-region\n");
	fr->rmem = of_reserved_mem_lookup(mem_np);
	of_node_put(mem_np);
	if (!fr->rmem)
		return dev_err_probe(dev, -EINVAL, "memory-region is not reserved memory\n");

	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;
	ret = devm_request_irq(dev, irq, fcu_irq, 0, dev_name(dev), fr);
	if (ret)
		return ret;
	amp_wr(fr, AMP_REG_DB_MASK, AMP_DB_USER | AMP_DB_PARK);

	rproc->auto_boot = false;
	if (!fcu_held(fr)) {
		/* Released by the FSBL (or a previous Linux): take it over as is. */
		rproc->state = RPROC_DETACHED;
		rproc->auto_boot = true;
	}

	platform_set_drvdata(pdev, rproc);
	ret = rproc_add(rproc);
	if (ret)
		return ret;

	dev_info(dev, "FCU region %pa+%#llx, FCU %s\n", &fr->rmem->base,
		 (u64)fr->rmem->size, fcu_held(fr) ? "held" : "running, attached");
	return 0;
}

static void fcu_rproc_remove(struct platform_device *pdev)
{
	struct rproc *rproc = platform_get_drvdata(pdev);

	/*
	 * rproc_del() shuts a running processor down. The FCU must outlive
	 * Linux's interest in it, so mark it detached first: rproc_shutdown()
	 * then leaves it alone.
	 */
	mutex_lock(&rproc->lock);
	if (rproc->state == RPROC_RUNNING || rproc->state == RPROC_ATTACHED) {
		rproc->state = RPROC_DETACHED;
		dev_info(&pdev->dev, "leaving the FCU running\n");
	}
	mutex_unlock(&rproc->lock);
	rproc_del(rproc);
}

static const struct of_device_id fcu_rproc_of_match[] = {
	{ .compatible = "stalya,fcu-rproc" },
	{ }
};
MODULE_DEVICE_TABLE(of, fcu_rproc_of_match);

static struct platform_driver fcu_rproc_driver = {
	.probe	= fcu_rproc_probe,
	.remove_new = fcu_rproc_remove,
	.driver = {
		.name		= "fcu-rproc",
		.of_match_table	= fcu_rproc_of_match,
		.dev_groups	= fcu_groups,
	},
};
module_platform_driver(fcu_rproc_driver);

MODULE_DESCRIPTION("remoteproc driver for the ti375_oob FCU");
MODULE_LICENSE("GPL");
