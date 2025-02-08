#!/bin/bash
set -e

echo "======================================"
echo "==============欢迎使用================"
echo "请输入你进行的操作的数字："
echo "0.拉取kernel"
echo "1.busybox定制文件系统"
echo "2.编译内核"
echo "3.启动调试内核"
echo "======================================"
echo "======================================"

read operation

case $operation in
    0)
        cd ./kernel
        echo "======================================"
        echo "如执行失败请自行配置gitee"
        echo "来源：https://gitee.com/mirrors/linux_old1"
        echo "======================================"
        git clone git@gitee.com:mirrors/linux_old1.git
        mv linux_old1 sourceCode
        cd ..
        ;;
    1)
        if [ -f "./busybox/BuildFS.sh" ]; then
            cd ./busybox
            ./BuildFS.sh
            cd ..
        else
            echo "BuildFS.sh不存在请检查仓库完整"
        fi
        ;;
    2)
        if [ -f "./kernel/build.sh" ]; then
            cd ./kernel
            ./build.sh
            cd ..
        else
            echo "build.sh不存在请检查仓库完整"
        fi
        ;;
    3)
        echo "请选择启动调试方式:"
        echo "1.终端调试"
        echo "2.VSCode调试"
        read modem

        if [ "$modem" == "1" ]; then
            ./qemu/consoleStartQemu.sh
        elif [ "$modem" == "2" ]; then
            sudo mkdir -p ./kernel/sourceCode/.vscode
            sudo chmod 755 ./kernel/sourceCode/.vscode
            sudo cp ./qemu/*.json ./kernel/sourceCode/.vscode
            sudo cp ./qemu/vsStartQemu.sh ./kernel/sourceCode/.vscode
            code ./kernel/sourceCode
        else
            echo "无效输入!!!"
        fi
        ;;
    *)
        echo "无效输入!!!"
        ;;
esac
