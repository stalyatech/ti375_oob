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
 *
 * The FCU comes out of reset held and the FSBL leaves it so: Linux starts it.
 * With "stalya,auto-boot" in the device tree the driver loads firmware-name
 * and starts it as soon as it probes; otherwise it waits for
 * "echo start > /sys/class/remoteproc/remoteproc0/state". An FCU that is
 * already running when the driver probes (started by an earlier Linux that
 * went away without a system reset) is attached to, not restarted.
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
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/poll.h>
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
struct resource_table *rproc_elf_find_loaded_rsc_table(struct rproc *rproc,
						       const struct firmware *fw);
irqreturn_t rproc_vq_interrupt(struct rproc *rproc, int vq_id);

#define FCU_PARK_TIMEOUT_MS	500
#define FCU_BOOT_TIMEOUT_MS	100

struct fcu_rproc {
	struct device *dev;
	struct rproc *rproc;
	void __iomem *amp;
	struct reserved_mem *rmem;
	struct completion parked;

	/* console shared with the FCU firmware, /dev/fcucon */
	void __iomem *con;
	struct miscdevice con_dev;
	wait_queue_head_t con_wait;
	struct delayed_work con_poll;
	int con_open;
	struct mutex con_lock;
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

/*
 * The region is no-map reserved memory, so it has to be mapped here, and it
 * is mapped uncached: the FCU does not snoop this CPU's caches, so the vrings
 * and the firmware image have to reach DDR without a writeback in between.
 */
static int fcu_mem_alloc(struct rproc *rproc, struct rproc_mem_entry *mem)
{
	void __iomem *va = ioremap(mem->dma, mem->len);

	if (!va)
		return -ENOMEM;
	mem->va = (__force void *)va;
	return 0;
}

static int fcu_mem_release(struct rproc *rproc, struct rproc_mem_entry *mem)
{
	iounmap((__force void __iomem *)mem->va);
	return 0;
}

/*
 * Hand remoteproc the memory it may use. Beside the whole region, which the
 * firmware image is loaded into, the vrings and the buffer pool are
 * registered under the names remoteproc looks for, so that they land where
 * the firmware's resource table says they are instead of somewhere the FCU
 * cannot reach.
 */
static int fcu_carveout(struct rproc *rproc, u64 base, size_t len,
			const char *name)
{
	struct fcu_rproc *fr = rproc->priv;
	struct rproc_mem_entry *mem;

	if (!in_region(fr, base, len))
		return dev_err_probe(fr->dev, -EINVAL,
				     "%s at %#llx is outside the FCU region\n", name, base);

	mem = rproc_mem_entry_init(fr->dev, NULL, base, len, base,
				   fcu_mem_alloc, fcu_mem_release, "%s", name);
	if (!mem)
		return -ENOMEM;
	rproc_add_carveout(rproc, mem);
	return 0;
}

static int fcu_prepare(struct rproc *rproc)
{
	struct fcu_rproc *fr = rproc->priv;
	int ret;

	ret = fcu_carveout(rproc, fr->rmem->base, fr->rmem->size, "fcu-mem");
	if (ret)
		return ret;

	ret = fcu_carveout(rproc, AMP_RPMSG_VRING0, AMP_RPMSG_VRING_SIZE,
			   "vdev0vring0");
	if (ret)
		return ret;

	ret = fcu_carveout(rproc, AMP_RPMSG_VRING1, AMP_RPMSG_VRING_SIZE,
			   "vdev0vring1");
	if (ret)
		return ret;

	return fcu_carveout(rproc, AMP_RPMSG_BUF_BASE, AMP_RPMSG_BUF_SIZE,
			    "vdev0buffer");
}

/*
 * An image without a resource table is fine (the LED test has none); one with
 * a table gets its vdev, and with it the rpmsg link.
 */
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
/* Tell the FCU that a vring has something in it. */
static void fcu_kick(struct rproc *rproc, int vqid)
{
	struct fcu_rproc *fr = rproc->priv;

	amp_wr(fr, AMP_REG_DB_SEND, AMP_DB_RPMSG);
}

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
	/*
	 * Without this the core would keep writing the vdev status into its own
	 * cached copy of the table, and the FCU would wait forever for DRIVER_OK.
	 */
	.find_loaded_rsc_table = rproc_elf_find_loaded_rsc_table,
	.kick		= fcu_kick,
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

	/*
	 * The vrings are handled in thread context: a first message announces a
	 * new channel, and registering its device sleeps.
	 */
	return (pending & AMP_DB_RPMSG) ? IRQ_WAKE_THREAD : IRQ_HANDLED;
}

static irqreturn_t fcu_irq_thread(int irq, void *data)
{
	struct fcu_rproc *fr = data;

	/* The doorbell carries no queue number: look at both vrings. */
	rproc_vq_interrupt(fr->rproc, 0);
	rproc_vq_interrupt(fr->rproc, 1);
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

/*
 * Console
 *
 * The FCU has no UART pin of its own on this board, so its firmware puts the
 * console in two ring buffers in the reserved region (struct amp_con, see
 * amp_ctrl.h, and the NuttX side in sapphire_ramcon.c). Here they show up as
 * /dev/fcucon: what is read comes from the FCU, what is written goes to it.
 *
 * The mapping is uncached, so nothing of this CPU's caches gets in the way;
 * the FCU writes its cache back before it moves an index. Each side owns one
 * index of each ring, which is what keeps this lock free against the FCU.
 * The local mutex only serialises readers and writers here.
 */

#define FCU_CON_POLL_MS		10

static u32 con_rd(struct fcu_rproc *fr, unsigned int off)
{
	return readl(fr->con + off);
}

static void con_wr(struct fcu_rproc *fr, unsigned int off, u32 val)
{
	writel(val, fr->con + off);
}

/* Field offsets of struct amp_con */
#define CON_MAGIC	0x00
#define CON_TX_SIZE	0x04
#define CON_RX_SIZE	0x08
#define CON_TX_HEAD	0x0c
#define CON_TX_TAIL	0x10
#define CON_RX_HEAD	0x14
#define CON_RX_TAIL	0x18
#define CON_OVERRUN	0x1c
#define CON_TX_DATA	AMP_CON_HDR_SIZE
#define CON_RX_DATA	(AMP_CON_HDR_SIZE + AMP_CON_TX_SIZE)

static bool con_ready(struct fcu_rproc *fr)
{
	return fr->con && con_rd(fr, CON_MAGIC) == AMP_CON_MAGIC;
}

static u32 con_pending(struct fcu_rproc *fr)
{
	if (!con_ready(fr))
		return 0;
	return con_rd(fr, CON_TX_HEAD) - con_rd(fr, CON_TX_TAIL);
}

/* Wake anyone waiting for FCU output while the device is open. */
static void fcu_con_poll(struct work_struct *work)
{
	struct fcu_rproc *fr = container_of(to_delayed_work(work), struct fcu_rproc, con_poll);

	if (con_pending(fr))
		wake_up_interruptible(&fr->con_wait);
	if (READ_ONCE(fr->con_open))
		schedule_delayed_work(&fr->con_poll, msecs_to_jiffies(FCU_CON_POLL_MS));
}

static int fcu_con_open(struct inode *inode, struct file *filp)
{
	struct fcu_rproc *fr = container_of(filp->private_data, struct fcu_rproc, con_dev);

	filp->private_data = fr;
	mutex_lock(&fr->con_lock);
	if (fr->con_open++ == 0)
		schedule_delayed_work(&fr->con_poll, msecs_to_jiffies(FCU_CON_POLL_MS));
	mutex_unlock(&fr->con_lock);
	return 0;
}

static int fcu_con_release(struct inode *inode, struct file *filp)
{
	struct fcu_rproc *fr = filp->private_data;

	mutex_lock(&fr->con_lock);
	if (--fr->con_open == 0)
		cancel_delayed_work(&fr->con_poll);
	mutex_unlock(&fr->con_lock);
	return 0;
}

static ssize_t fcu_con_read(struct file *filp, char __user *buf, size_t len, loff_t *ppos)
{
	struct fcu_rproc *fr = filp->private_data;
	u32 head, tail, avail;
	size_t done = 0;
	int ret;

	if (!con_ready(fr))
		return 0;

	while (!(avail = con_pending(fr))) {
		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;
		ret = wait_event_interruptible_timeout(fr->con_wait, con_pending(fr),
						       msecs_to_jiffies(FCU_CON_POLL_MS));
		if (ret < 0)
			return ret;
	}

	mutex_lock(&fr->con_lock);
	head = con_rd(fr, CON_TX_HEAD);
	tail = con_rd(fr, CON_TX_TAIL);
	avail = head - tail;

	/* The FCU wrote faster than this side read: start from what is left. */
	if (avail > AMP_CON_TX_SIZE) {
		tail = head - AMP_CON_TX_SIZE;
		avail = AMP_CON_TX_SIZE;
	}
	if (avail > len)
		avail = len;

	while (done < avail) {
		u8 ch = readb(fr->con + CON_TX_DATA + ((tail + done) % AMP_CON_TX_SIZE));

		if (put_user(ch, buf + done)) {
			done = done ? done : -EFAULT;
			goto out;
		}
		done++;
	}

	con_wr(fr, CON_TX_TAIL, tail + done);
out:
	mutex_unlock(&fr->con_lock);
	return done;
}

static ssize_t fcu_con_write(struct file *filp, const char __user *buf, size_t len, loff_t *ppos)
{
	struct fcu_rproc *fr = filp->private_data;
	u32 head, tail, room;
	size_t done = 0;

	if (!con_ready(fr))
		return -ENODEV;

	mutex_lock(&fr->con_lock);
	head = con_rd(fr, CON_RX_HEAD);
	tail = con_rd(fr, CON_RX_TAIL);
	room = AMP_CON_RX_SIZE - (head - tail);
	if (room > len)
		room = len;

	while (done < room) {
		u8 ch;

		if (get_user(ch, buf + done)) {
			done = done ? done : -EFAULT;
			goto out;
		}
		writeb(ch, fr->con + CON_RX_DATA + ((head + done) % AMP_CON_RX_SIZE));
		done++;
	}

	con_wr(fr, CON_RX_HEAD, head + done);
out:
	mutex_unlock(&fr->con_lock);
	if (done == 0 && !(filp->f_flags & O_NONBLOCK))
		return -ENOSPC;
	return done;
}

static __poll_t fcu_con_poll_file(struct file *filp, struct poll_table_struct *wait)
{
	struct fcu_rproc *fr = filp->private_data;

	poll_wait(filp, &fr->con_wait, wait);
	return EPOLLOUT | EPOLLWRNORM | (con_pending(fr) ? EPOLLIN | EPOLLRDNORM : 0);
}

static const struct file_operations fcu_con_fops = {
	.owner		= THIS_MODULE,
	.open		= fcu_con_open,
	.release	= fcu_con_release,
	.read		= fcu_con_read,
	.write		= fcu_con_write,
	.poll		= fcu_con_poll_file,
	.llseek		= no_llseek,
};

static int fcu_con_init(struct fcu_rproc *fr)
{
	int ret;

	if (!in_region(fr, AMP_CON_BASE, AMP_CON_SIZE))
		return dev_err_probe(fr->dev, -EINVAL,
				     "console at %#x is outside the FCU region\n", AMP_CON_BASE);

	/* Uncached: the FCU writes this through its own cache. */
	fr->con = devm_ioremap(fr->dev, AMP_CON_BASE, AMP_CON_SIZE);
	if (!fr->con)
		return -ENOMEM;

	init_waitqueue_head(&fr->con_wait);
	mutex_init(&fr->con_lock);
	INIT_DELAYED_WORK(&fr->con_poll, fcu_con_poll);

	fr->con_dev.minor = MISC_DYNAMIC_MINOR;
	fr->con_dev.name = "fcucon";
	fr->con_dev.fops = &fcu_con_fops;
	fr->con_dev.parent = fr->dev;
	ret = misc_register(&fr->con_dev);
	if (ret)
		return ret;

	dev_info(fr->dev, "console at %#x, /dev/%s\n", AMP_CON_BASE, fr->con_dev.name);
	return 0;
}

static void fcu_con_exit(struct fcu_rproc *fr)
{
	if (!fr->con)
		return;
	misc_deregister(&fr->con_dev);
	cancel_delayed_work_sync(&fr->con_poll);
}

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
	fr->rproc = rproc;
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
	ret = devm_request_threaded_irq(dev, irq, fcu_irq, fcu_irq_thread, 0,
					dev_name(dev), fr);
	if (ret)
		return ret;
	amp_wr(fr, AMP_REG_DB_MASK, AMP_DB_USER | AMP_DB_PARK | AMP_DB_RPMSG);

	if (!fcu_held(fr)) {
		/* Started by a previous Linux: take it over as it is. */
		rproc->state = RPROC_DETACHED;
		rproc->auto_boot = true;
	} else {
		/* Held since reset: start it now if the board asks for that. */
		rproc->auto_boot = of_property_read_bool(dev->of_node, "stalya,auto-boot");
	}

	ret = fcu_con_init(fr);
	if (ret)
		return ret;

	platform_set_drvdata(pdev, rproc);
	ret = rproc_add(rproc);
	if (ret) {
		fcu_con_exit(fr);
		return ret;
	}

	dev_info(dev, "FCU region %pa+%#llx, FCU %s\n", &fr->rmem->base, (u64)fr->rmem->size,
		 !fcu_held(fr) ? "running, attached" :
		 rproc->auto_boot ? "held, starting it" : "held");
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
	fcu_con_exit(rproc->priv);
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
