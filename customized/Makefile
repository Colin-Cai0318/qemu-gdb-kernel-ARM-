KDIR ?= $(if $(KERNELDIR),$(KERNELDIR),$(if $(KERNEL_DIR),$(KERNEL_DIR),$(CURDIR)/../kernel/sourceCode))
ARCH ?= arm64
ifeq ($(shell uname -m),aarch64)
CROSS_COMPILE ?=
else
CROSS_COMPILE ?= aarch64-linux-gnu-
endif

obj-m := main.o

modules:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: modules clean
