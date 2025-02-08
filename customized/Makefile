KERNELDIR = $(shell pwd)/../kernel/sourceCode
PWD := $(shell pwd)
CC  = $(CROSS_COMPILE)gcc

obj-m := main.o

modules:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions

.PHONY: modules clean
