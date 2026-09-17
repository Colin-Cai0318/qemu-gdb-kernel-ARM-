# Apple Silicon macOS 适配说明

## 支持边界

- 仅支持 Apple Silicon（`arm64`），不支持 Intel Mac。
- macOS 13 或更高版本，使用 Virtualization.framework（Lima `vz`）。
- 仓库必须位于 `/Users/caizhipeng/workspace` 内。
- 不依赖 Homebrew、Docker Desktop 或全局 QEMU/GDB。

## 为什么使用 Linux VM

macOS 自带 Bash 3.2 和 GNU Make 3.81，低于 Linux 6.12 要求；默认 APFS 通常不区分
文件名大小写，而 Linux 源码包含仅大小写不同的文件。项目因此只在 macOS 上运行一个
轻量 ARM64 Linux VM，所有内核实验仍使用标准 Linux 工具链。

持久化文件布局：

```text
tools/
├── cache/          Lima 安装包
├── lima-2.2.0/     项目私有 Lima
├── lima-home/      VM 配置、密钥和虚拟磁盘
├── host-home/      隔离的工具 HOME 和镜像缓存
└── tmp/            项目私有临时目录
```

VM 内的 Linux 源码、BusyBox 构建目录和 rootfs 位于虚拟磁盘中的
`$HOME/kernel-lab-data`。虚拟磁盘本身仍在 `tools/lima-home/`，因此不会在
`/Users/caizhipeng/workspace` 外留下持久化工具或构建数据。

## 一键部署

```bash
./setup.sh --full
./main.sh debug
```

只准备工具，不立即编译：

```bash
./setup.sh
./main.sh fetch
./main.sh rootfs
./main.sh build
```

可以覆盖 VM 资源：

```bash
KERNEL_LAB_VM_CPUS=4 \
KERNEL_LAB_VM_MEMORY=6 \
KERNEL_LAB_VM_DISK=100 \
./setup.sh
```

内存和磁盘覆盖值的单位均为 GiB。

## 日常命令

```bash
./main.sh doctor
./main.sh qemu
./main.sh debug
./main.sh console
./main.sh shell
./main.sh stop
```

`JOBS`、`KERNEL_PROFILE`、`BUILD_IN_TREE_MODULES`、`GDB_PORT` 等原有环境变量会被
传入 VM。例如：

```bash
JOBS=6 KERNEL_PROFILE=stability ./main.sh build
```

macOS 当前支持终端 GDB 调试；VS Code 本地 MI 调试没有跨 VM 自动配置，调用
`./main.sh vscode` 会给出明确提示。

## 故障恢复

先检查：

```bash
./scripts/check.sh
./main.sh doctor
```

停止并重新启动 VM：

```bash
./main.sh stop
./main.sh shell
```

不要手工删除运行中的 `tools/lima-home/kernel-lab`。如果确实需要重建 VM，应先运行
`./main.sh stop`，备份需要的实验结果，再删除对应 VM 数据。
