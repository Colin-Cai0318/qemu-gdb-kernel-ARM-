#!/bin/bash
set -e

echo "=====busybox定制文件系统开始====="

echo "step 1/3:正在下载解压busybox...."
if [ -f busybox-1.33.1.tar.bz2 ]; then
    echo "busybox-1.33.1.tar.bz2 exists"
    if [ ! -d busybox-1.33.1 ]; then
        tar -xjf busybox-1.33.1.tar.bz2
    fi
else
    wget  https://busybox.net/downloads/busybox-1.33.1.tar.bz2
    tar -xjf busybox-1.33.1.tar.bz2
fi
cd busybox-1.33.1

echo "step 2/3:开始配置并且编译busybox..."

echo "配置环境变量"
make distclean
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

echo "开始编译..."
make
make install

echo "step 3/3:定制文件系统"
mkdir ./_install/etc ./_install/dev ./_install/lib
cp -nr ../tools/* ./_install/etc
sudo mknod ./_install/dev/console c 5 1
cp /usr/aarch64-linux-gnu/lib/*.so*  -a ./_install/lib
mkdir -p ./_install/lib/modules

rm -rf ../root
cp -nr ./_install ../root
cd ..
rm -rf busybox-1.33.1*
echo "=====busybox定制文件系统完成====="
