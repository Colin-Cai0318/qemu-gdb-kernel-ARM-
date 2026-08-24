KDIR ?= ../../kernel/sourceCode
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-

obj-m := hello_lab.o

.PHONY: all clean

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
