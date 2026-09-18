# ARM64 Linux 内核 QEMU + GDB 学习实验台

这个项目提供一个可重复的 ARM64 Linux 内核学习环境：支持 Ubuntu/Debian Linux
原生运行，也支持 Apple Silicon macOS。macOS 使用仓库私有的 ARM64 Linux VM，
内核、BusyBox、QEMU 与 GDB 始终在 Linux 环境中运行，避开 APFS 大小写、旧版
Bash/Make 和宿主交叉工具链差异。

默认学习基线为 Linux 6.12、BusyBox 1.33.1。环境变量可以覆盖版本、并行度和调试
配置。BusyBox 下载默认先使用 Buildroot 源镜像，再回退到上游站点；1.33.1 归档会
校验固定的 SHA-256。

## 环境要求

支持范围：

- Ubuntu 22.04/24.04（x86_64 或 ARM64）
- Apple Silicon macOS 13 或更高版本
- QEMU 6.1.1
- GDB 12.1
- `aarch64-linux-gnu-gcc` 11.4

不支持 Intel Mac。

## 傻瓜式部署

```bash
git clone https://github.com/Colin-Cai0318/qemu-gdb-kernel-ARM-.git
cd qemu-gdb-kernel-ARM-
./setup.sh --full
./main.sh debug
```

`--full` 会安装依赖、下载源码、构建 rootfs 和内核。不带 `--full` 时只安装依赖。
macOS 下载的 Lima、镜像缓存、VM 磁盘、Linux 源码和构建目录全部位于仓库的
`tools/` 下，不使用 Homebrew，也不会把持久化工具数据写出项目工作区。

macOS 查看 QEMU 串口或进入 Linux VM：

```bash
./main.sh console
./main.sh shell
./main.sh stop
```

详细设计和故障恢复见 [`docs/macos.md`](docs/macos.md)。

## 首次部署

```bash
git clone https://github.com/Colin-Cai0318/qemu-gdb-kernel-ARM-.git
cd qemu-gdb-kernel-ARM-

./main.sh fetch
./main.sh rootfs
./main.sh build
./main.sh debug
```

`debug` 会在 tmux 中启动 QEMU，并用 `-S` 在第一条指令前等待 GDB，避免错过
`start_kernel`。GDB 退出后可查看串口：

```bash
tmux attach -t qemu-session
```

macOS 宿主应使用 `./main.sh console`，因为 tmux 位于项目 Linux VM 内。
`./main.sh vscode` 也应从 macOS 终端运行；`./main.sh shell` 进入的 VM 终端用于
`fetch`、`rootfs`、`build` 和实验命令。

脚本遇到 1234 端口或同名 tmux 会话冲突时会报错，不会执行 `kill -9`。

## 命令入口

```text
./main.sh doctor                 检查依赖与产物
./main.sh setup [--full]         安装依赖，可选完成完整首次构建
./main.sh fetch [版本]           下载/恢复内核源码
./main.sh rootfs                 构建静态 BusyBox rootfs
./main.sh build                  构建 ARM64 Image 和 vmlinux
./main.sh qemu                   不等待 GDB，直接启动
./main.sh debug                  终端 GDB 调试
./main.sh vscode                 准备 VS Code 配置并打开源码
./main.sh shell                  macOS: 进入项目 Linux VM
./main.sh console                macOS: 查看 QEMU 串口
./main.sh stop                   macOS: 停止项目 Linux VM
```

常用覆盖参数：

```bash
JOBS=8 ./main.sh build
KERNEL_PROFILE=stability ./main.sh build
BUILD_IN_TREE_MODULES=1 ./main.sh build
GDB_PORT=1235 ./main.sh debug
```

默认 `debug` 档适合源码学习；`stability` 档额外启用 KASAN、lockdep、
`DEBUG_ATOMIC_SLEEP` 等重型检查。默认只构建实验必需的 `Image` 和 `vmlinux`；
设置 `BUILD_IN_TREE_MODULES=1` 才会构建 `defconfig` 中的全部模块。第一课建议先用
`debug` 默认值。

## 分阶段实验

`labs/A01` 提供模块生命周期与失败路径实验：

```bash
make -C labs/A01
./main.sh debug
```

Guest 启动后：

```sh
insmod /mnt/labs/A01/hello_lab.ko
dmesg | tail
rmmod hello_lab
insmod /mnt/labs/A01/hello_lab.ko fail_init=1
```

详细步骤见 [`labs/A01/README.md`](labs/A01/README.md)。环境设计与故障恢复说明见
[`docs/environment.md`](docs/environment.md)。

完成 A01 的证据复核后，`labs/A02` 进入内核线程、等待队列与调度 tracepoint：

```bash
make -C labs/A02
./main.sh qemu
```

详细步骤见 [`labs/A02/README.md`](labs/A02/README.md)。仓库内的
`.codex/skills/linux-kernel-learning` 定义了后续行动项目、学习报告批阅和实验验收的
持续工作流。

## 目录

```text
busybox/       BusyBox rootfs 构建与启动配置
kernel/        源码恢复、内核构建和调试配置片段
qemu/          QEMU、GDB、VS Code 启动脚本
labs/          按课程编号组织的可复现实验
scripts/       环境自检与静态检查
customized/    原有自定义模块共享目录
```

下载的源码、rootfs、编译对象、日志和模块二进制均被 `.gitignore` 排除，避免把
本机生成物提交到仓库。
