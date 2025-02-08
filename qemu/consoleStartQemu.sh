#!/bin/bash

if [ -f "./kernel/sourceCode/arch/arm64/boot/Image" ]; then
    echo "qemu正在启动...."
    if lsof -i :1234 >/dev/null; then
        lsof -t -i :1234 | xargs -r kill -9
    fi
    gnome-terminal -- bash -c "qemu-system-aarch64 -m 1024M -smp 4 -cpu cortex-a57 -machine virt \
                -kernel ./kernel/sourceCode/arch/arm64/boot/Image \
                -append 'rdinit=/linuxrc nokaslr console=ttyAMA0 loglevel=8' \
                -serial mon:stdio -s; exec bash"
    sleep 5
    gdb-multiarch ./kernel/sourceCode/vmlinux -ex 'target remote localhost:1234'
else
    echo "Image不存在,请先编译内核"
fi