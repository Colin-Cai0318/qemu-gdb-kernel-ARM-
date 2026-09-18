# ARM64 内核学习实验台说明

## 下载模式

部署和源码下载默认使用 `KERNEL_LAB_DOWNLOAD_MODE=auto`：先直连并断点续传，失败后
自动回退到系统代理。Linux 与 Apple Silicon macOS 都支持以下覆盖：

```bash
KERNEL_LAB_DOWNLOAD_MODE=direct ./setup.sh
KERNEL_LAB_DOWNLOAD_MODE=proxy ./setup.sh
```

## 设计目标

- 使用固定的 Linux 6.12 与 BusyBox 1.33.1 起步，减少变量。
- 默认 `debug` 配置只开启源码调试、符号、ftrace、dynamic debug 和 9P。
- `stability` 配置额外开启 KASAN、lockdep 等重型检查，供后续稳定性专题使用。
- QEMU 遇到端口或 tmux 会话冲突时直接报错，不终止未知进程。
- 所有生成物都留在本地且被 `.gitignore` 排除，源码和学习报告保持可审查。

## 推荐首次部署

```bash
./setup.sh --full
```

或者分步执行：

```bash
./setup.sh
./main.sh doctor
./main.sh fetch
./main.sh rootfs
./main.sh build
./main.sh debug
```

如果已有 `kernel/sourceCode` 但缺少 `Makefile`，`fetch` 会先将它改名为带时间戳的
`sourceCode.incomplete.*`，再从已校验的压缩包恢复，不会直接删除现场。

## 构建配置

普通学习：

```bash
KERNEL_PROFILE=debug JOBS="$(nproc)" ./main.sh build
```

macOS 不需要 `nproc`，直接省略 `JOBS` 或显式设置数字；命令会进入项目 ARM64
Linux VM。详见 [`macos.md`](macos.md)。

BusyBox 1.33.1 的 `tc` applet 依赖已从新 Linux UAPI 头文件移除的 CBQ 定义；rootfs
构建会关闭这个实验未使用的 applet，其他默认功能保持不变。

默认目标是 `Image + vmlinux`。只有在研究某个内核自带模块时才需要：

```bash
BUILD_IN_TREE_MODULES=1 ./main.sh build
```

精简构建会将 `vmlinux.symvers` 复制为外部模块构建所需的 `Module.symvers`；
这份符号表包含核心内核的导出符号，不需要为了 A01 编译所有无关的内核模块。

稳定性诊断专题：

```bash
KERNEL_PROFILE=stability JOBS="$(nproc)" ./main.sh build
```

`stability` 会显著增加内存和运行时间，第一课无需启用。

## 常见检查

```bash
./scripts/check.sh
./main.sh doctor
ss -ltnp | grep :1234
tmux ls
```

停止由本项目启动的 QEMU：

```bash
tmux kill-session -t qemu-session
```

该命令只针对明确命名的实验会话，不会根据端口执行 `kill -9`。
