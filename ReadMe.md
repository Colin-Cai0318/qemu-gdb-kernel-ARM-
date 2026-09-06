# ARM64 Linux 内核 QEMU + GDB 学习实验台

这个项目提供一个可重复的 ARM64 Linux 内核学习环境：在 x86_64 Ubuntu 主机上交叉
编译内核与 BusyBox initramfs，通过 QEMU `virt` 机器启动，并使用
`gdb-multiarch` 或 VS Code 调试。

默认学习基线为 Linux 6.12、BusyBox 1.33.1。环境变量可以覆盖版本、并行度和调试
配置。BusyBox 下载默认先使用 Buildroot 源镜像，再回退到上游站点；1.33.1 归档会
校验固定的 SHA-256。

## 环境要求

已验证环境：

- Ubuntu 22.04
- QEMU 6.1.1
- GDB 12.1
- `aarch64-linux-gnu-gcc` 11.4

Ubuntu 可安装的主要依赖：

```bash
sudo apt install \
  build-essential bc bison flex libssl-dev libelf-dev \
  gcc-aarch64-linux-gnu gdb-multiarch qemu-system-arm \
  tmux python3 xz-utils bzip2
```

先运行自检，它只读检查环境，不安装软件：

```bash
./main.sh doctor
```

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

脚本遇到 1234 端口或同名 tmux 会话冲突时会报错，不会执行 `kill -9`。

## 命令入口

```text
./main.sh doctor                 检查依赖与产物
./main.sh fetch [版本]           下载/恢复内核源码
./main.sh rootfs                 构建静态 BusyBox rootfs
./main.sh build                  构建 ARM64 Image 和 vmlinux
./main.sh qemu                   不等待 GDB，直接启动
./main.sh debug                  终端 GDB 调试
./main.sh vscode                 准备 VS Code 配置并打开源码
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

运行 A02 自动验收（Linux 宿主机）：

```bash
KDIR="$PWD/kernel/sourceCode" ROOTFS_STAGING="$PWD/busybox/root" ./labs/A02/validate-qemu.sh
```

构建指纹和串口日志保存在 `artifacts/A02/run.*`。CI 中的反例测试不替代真实 QEMU
运行；每次修改实验后都应重新执行以上命令。

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
