# Out-of-tree build:  make -C <kernel build dir> M=$(pwd) ARCH=riscv CROSS_COMPILE=...
# Buildroot builds it through br2-efinix kernel_modules/stalya-fcu.
KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
