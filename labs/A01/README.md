# A01：模块生命周期与失败路径

本实验对应第一课，目标是把 `module_init/module_exit`、模块装载路径、
日志证据和 GDB 断点串成一条可复现链路。详细理论问题、验收标准和报告模板
保存在 Notion 的 `A01｜认识实验台` 页面。

## 1. 主机侧构建

```bash
make -C labs/A01
file labs/A01/hello_lab.ko
```

## 2. 启动调试

```bash
./main.sh debug
```

QEMU 在第一条指令前等待 GDB。GDB 已预设 `start_kernel` 断点。另开终端可查看
串口：

```bash
tmux attach -t qemu-session
```

## 3. Guest 中验证模块生命周期

`labs/` 通过只读学习边界清晰的 9P 共享出现在 `/mnt/labs`：

```sh
insmod /mnt/labs/A01/hello_lab.ko
dmesg | tail
cat /sys/module/hello_lab/parameters/fail_init
rmmod hello_lab
dmesg | tail
```

验证失败路径：

```sh
insmod /mnt/labs/A01/hello_lab.ko fail_init=1
echo $?
dmesg | tail
```

## 4. 建议断点

```gdb
b do_init_module
b free_module
c
```

记录调用栈、模块参数、返回值和 `dmesg` 时间顺序。不要只截结果图：报告中需要
说明“现象如何证明理论判断”。
