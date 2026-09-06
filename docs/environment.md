# ARM64 内核学习实验台说明

## 设计目标

- 使用固定的 Linux 6.12 与 BusyBox 1.33.1 起步，减少变量。
- 默认 `debug` 配置只开启源码调试、符号、ftrace、dynamic debug 和 9P。
- `stability` 配置额外开启 KASAN、lockdep 等重型检查，供后续稳定性专题使用。
- QEMU 遇到端口或 tmux 会话冲突时直接报错，不终止未知进程。
- 所有生成物都留在本地且被 `.gitignore` 排除，源码和学习报告保持可审查。

## 推荐首次部署

```bash
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

默认目标是 `Image + vmlinux + modules_prepare`。最后一项补齐 Linux 6.12 外部模块
需要的 `scripts/module.lds`。A01、A02 与 customized 的 Makefile 也会先执行此准备步骤。
只有在研究某个内核自带模块时才需要：

```bash
BUILD_IN_TREE_MODULES=1 ./main.sh build
```

精简构建会将 `vmlinux.symvers` 复制为外部模块构建所需的 `Module.symvers`；
这份符号表包含核心内核的导出符号，不需要为了 A01 编译所有无关的内核模块。

`modules_prepare` 本身不生成完整的 `Module.symvers`，所以仍然需要先完成内核构建。

独立实验检出可以用符号链接复用现有 `kernel/sourceCode` 和 `busybox/root`；这两个
本地产物路径无论是目录还是链接都会被 Git 忽略。重编内核会修改链接指向的构建树。

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

## 调试连接和验收证据

QEMU GDB Stub 默认仅监听 `127.0.0.1`；VM 中的 GDB 和 VS Code Remote SSH 可以直接
连接。从其他机器调试时使用 SSH 端口转发，参见 [QEMU GDB 文档](https://www.qemu.org/docs/master/system/gdb.html)。

`labs/A02/validate-qemu.sh` 将每次运行的串口日志与构建指纹保存到 `artifacts/A02/run.*`。
输出 PASS 后超时、缺调度事件、卸载顺序错误或出现内核诊断都算失败。详见
[A02 验收说明](../labs/A02/README.md)。
