# 一键式部署qemu+gdb调试kernel内核
## 一.前言
本开源项目拟在通过shell脚本一键式完成环境的搭建帮助Linux arm内核学习者更方便的调试学习内核。本项目使用的环境如下：
```shell
$ qemu-system-aarch64 --version
QEMU emulator version 6.1.1 (v6.1.1)
Copyright (c) 2003-2021 Fabrice Bellard and the QEMU Project developers

$ gdb --version
GNU gdb (Ubuntu 12.1-0ubuntu1~22.04.2) 12.1
Copyright (C) 2022 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
```
以上环境版本仅供参考，若使用过程中发生报错，大概率由于缺少某些环境，根据报错信息安装对应的环境重新运行即可解决。
## 二.拉取项目
运行命令拉取当前项目脚本
```shell
git clone git@gitee.com:cai0318/qemu-gdb-kernel-arm.git
```
## 三.运行脚本
运行main.sh
```shell
~/ArmLinux$ ./main.sh 
======================================
==============欢迎使用================
请输入你进行的操作的数字：
0.拉取kernel
1.busybox定制文件系统
2.编译内核
3.启动调试内核
======================================
======================================
```
初次执行按照数字从小到大依次执行，注意文件系统定制一定要在内核编译之前否则编译出来的内核无文件系统。完成所有步骤输入3进行调试。支持终端调试和vscode可视化调试，推荐使用VSCode调试，请自行安装GDB-debug插件，运行过脚本之后可以直接使用vscode打开sourceCode进行调试，无需每次运行脚本。
```shell
======================================
======================================
3
请选择启动调试方式:
1.终端调试
2.VSCode调试
```
## 四.效果展示
以VScode方式调试，使用脚本按照顺序依次执行，自动打开VScode，在init\main.c的start_kernel函数处添加断点。
![alt text](/mdImage/image1.png)
如下可以看到执行到断点并且可视化当前的栈信息和寄存器信息。非常方便。
![alt text](/mdImage/image2.png)
在终端中输入一下命令，进入qemu终端可以查看log输出
```shell
tmux attach -t qemu-session
```
点击continue按键继续执行观察到log从qemu终端打印
![alt text](/mdImage/image3.png)
终端中按任意键进入内核的文件系统
![alt text](/mdImage/image4.png)
## 五.注意
1. 在使用脚本编译内核代码时候会有选择内核版本的步骤，以上测试环境使用v4.19，输入y确认切换版本后会弹出可用版本，按q退出后输入存在的版本。
2. 若需要重新给内核定制文件系统或者客制化自己的文件系统，最终生效文件目录为kernel/sourceCode/root，修改busybox/root若想要生效需要删除kernel/sourceCode/root，建议直接修改kernel/sourceCode/root