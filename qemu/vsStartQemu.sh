#!/bin/bash

if lsof -i :1234 >/dev/null; then
    echo "qemu已经启动正在杀死qemu"
    lsof -t -i :1234 | xargs -r kill -9
fi

echo "当前路径是: $(pwd)"

if [ -f "./arch/arm64/boot/Image" ]; then
    echo "qemu正在启动...."
    if [ ! -f qemu.log ]; then
        sudo touch qemu.log
    fi
    sudo chmod 777 qemu.log
    > qemu.log
    tmux new-session -d -s qemu-session \
        "qemu-system-aarch64 -m 1024M -smp 4 -cpu cortex-a57 -machine virt \
        -kernel ./arch/arm64/boot/Image \
        -append 'rdinit=/linuxrc nokaslr console=ttyAMA0 loglevel=8' \
        -serial mon:stdio \
        -s -S \
        -nographic 2>&1 | tee qemu.log"
    echo "QEMU 已启动，等待 GDB 连接..."
    echo "输入 'tmux attach -t qemu-session' 进入 QEMU 终端"
    sleep 3  # 等待 QEMU 初始化完成
else
    echo "Image不存在,请先编译内核"
    exit 1
fi