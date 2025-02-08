#!/bin/bash
set -e

LOGFILE="build.log"

selectVersion(){
    echo "当前kernel版本如下"
    git describe --tags
    echo "是否要选择kernel版本?(y/n)"
    read selection
    if [ $selection == y ] || [ $selection == yes ];then
        git tag
        echo "请选择kernel版本"
        read version
        git checkout $version
    elif [ $selection != n ] && [ $selection == no ];then
        echo "输入有误,默认不切换版本"
    fi
}

buildKernel() {
    > "$LOGFILE"
    start_time=$SECONDS
    echo "======================================"
    echo "============开始编译内核=============="
    echo "======================================"
    make distclean
    cp ../../customized/*.ko ./root/lib/modules/
    make defconfig ARCH=arm64
    echo "CONFIG_DEBUG_INFO=y" >> .config
    echo "CONFIG_INITRAMFS_SOURCE=\"./root\"" >> .config
    echo "CONFIG_INITRAMFS_ROOT_UID=0" >> .config
    echo "CONFIG_INITRAMFS_ROOT_GID=0" >> .config
    make ARCH=arm64 -j8 CROSS_COMPILE=aarch64-linux-gnu- | tee "$LOGFILE"
    elapsed_time=$(($SECONDS - $start_time))
    hours=$((elapsed_time / 3600))
    minutes=$(( (elapsed_time % 3600) / 60 ))
    seconds=$((elapsed_time % 60))
    echo "======================================"
    printf "编译完成总用时 : %02d:%02d:%02d \n" $hours $minutes $seconds
    echo "======================================"
}

if [ -d "./sourceCode" ]; then
    cd ./sourceCode
    selectVersion
    if [ -d "./root" ]; then
        buildKernel
    elif [ -d "../../busybox/root" ]; then
        cp -nr ../../busybox/root ./
        buildKernel
    else
        echo "busybox定制文件系统不存在,请先定制文件系统"
    fi
    cd ..
else
    echo "sourceCode不存在,请先拉取kernel"
fi
    
