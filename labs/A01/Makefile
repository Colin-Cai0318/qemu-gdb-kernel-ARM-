KDIR ?= ../../kernel/sourceCode
ARCH ?= arm64
ifeq ($(shell uname -m),aarch64)
CROSS_COMPILE ?=
else
CROSS_COMPILE ?= aarch64-linux-gnu-
endif

obj-m := hello_lab.o

.PHONY: all prepare clean

all: prepare
	$(MAKE) -C $(KDIR) M=$(CURDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

prepare:
	$(MAKE) -C $(KDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules_prepare

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
