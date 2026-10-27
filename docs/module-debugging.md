# 自定义 .ko 的 GDB / VS Code 断点

QEMU 的 GDB stub 可以调试 Guest 内核和动态加载模块。模块必须使用当前运行内核的
构建树编译，保留 DWARF，且 GDB 必须知道每个 ELF section 的运行地址。
仅打开 `main.c` 或只加载 `vmlinux` 不会自动获得模块地址。

## 准备

```bash
./main.sh build
./main.sh modules
./main.sh debug
```

macOS 命令会在项目 Linux VM 中执行。`build` 的 debug 配置关闭
`CONFIG_DEBUG_INFO_REDUCED`，避免 Linux GDB 脚本因类型不完整拒绝加载。
已有旧产物需要重新构建一次；`doctor` 和调试启动会明确提示不兼容的旧配置。
`modules` 构建 `customized/main.ko`，原生 Linux 也可使用
`make -C customized KDIR=/path/to/kernel`。不要 strip `.ko`，不要加载上次构建的副本。

## 终端 GDB

启动后，GDB 已安装自动模块符号加载钩子，停留在尚未启动的 QEMU：

```text
(gdb) break hello_start
(gdb) break hello_end
(gdb) continue
# 在 start_kernel 停下；再次 continue，让 Guest 启动
(gdb) continue
```

另一个终端在 macOS 执行 `./main.sh console`，Linux 执行
`tmux attach -t qemu-session`。在 QEMU Guest 串口里执行：

```sh
insmod /mnt/customized/main.ko
# GDB 在 hello_start 停下：bt、list、next、print $pc；continue 后 insmod 返回
rmmod main
# GDB 在 hello_end 停下；continue 完成卸载
```

未加载模块时，断点显示 pending 属正常现象。`kernel-lab-symbols` 在
`do_init_module(mod)`、调用模块初始化函数之前读取 `mod->sect_attrs`，为全部已分配
section 建立地址映射，包含 Linux 6.12 自带 `lx-symbols` 未覆盖的
`.init.text` 和 `.exit.text`。当前 GDB 15.1 对链接地址同为零的 ET_REL section
存在源码行定位歧义；辅助脚本用 ARM64 `objcopy --change-section-vma` 生成临时
`.ko.debug` 符号副本，再 `add-symbol-file -readnow`，让 BFD 同时正确重定位函数与
DWARF 行表。原 `.ko` 不变，卸载时删除临时符号。在 `free_module(mod)` 删除旧符号，重载时重新计算地址。
钩子出错会停止并报告，避免无提示地错过初始化断点。

初始化完成后 `__init` 代码会被内核回收；只在加载期间检查或单步这些函数。
普通模块函数和 `__exit` 函数可在模块存活期间调试。编译器优化仍可能让部分局部变量
显示 optimized out；保留 DWARF 并不等于关闭全部优化。

## VS Code

macOS 宿主执行 `./main.sh vscode`，Linux 执行相同命令。
打开的多目录工作区包含 `Linux`、`customized`、`labs`：

1. 在 `customized/main.c` 的两条 `printk` 行点击设置断点。
2. 选择 Linux 文件夹的 `kernel debug` 并按 F5，先停在 QEMU 初始指令。
   如需观察启动，可在 VS Code 的断点面板添加 `start_kernel` 函数断点。
3. 继续运行，进入 Guest 串口执行 `insmod /mnt/customized/main.ko`。
4. 初始化行命中后可查看调用栈、寄存器、Watch 并单步；继续后执行 `rmmod main` 命中卸载行。

`cppdbg` 会在辅助脚本读取类型前显式加载 `vmlinux`，并使用完整路径绑定源码断点，
避免 `customized/main.c` 与内核里的多个 `main.c` 混淆。它和终端 GDB 使用同一份生成的 `.vscode/kernel-lab.gdb`，模块地址逻辑一致。
`GDB_PORT=1235 ./main.sh vscode` 会同时配置调试器和 QEMU 任务端口。
macOS 的 C/C++ 扩展需安装在 Remote SSH 的 Linux VM 端，入口脚本会检查并安装。

调试控制台的 GDB 命令加 `-exec`，例如 `-exec bt`。
连接已启动且已有模块的 QEMU 后，可暂停并执行 `-exec kernel-lab-refresh`。
不要同时运行 `lx-symbols`，以免两个符号加载钩子互相覆盖。

## 自动运行验证

在 Linux 环境中准备同一个内核的三个模块以及 VS Code C/C++ 调试适配器：

```bash
./scripts/check.sh
./main.sh doctor
./main.sh modules
make -C labs/A01 KDIR="$KERNEL_DIR"
make -C labs/A02 KDIR="$KERNEL_DIR"
VSCODE_PREPARE_ONLY=1 ./main.sh vscode
python3 scripts/validate-ko-debug.py \
  --kernel "$KERNEL_DIR" \
  --adapter "$CPPDBG_ADAPTER" \
  --output /tmp/ko-debug-evidence
KDIR="$KERNEL_DIR" ROOTFS_STAGING="$ROOTFS_DIR" labs/A02/validate-qemu.sh
```

`CPPDBG_ADAPTER` 是远程 C/C++ 扩展内 `debugAdapters/bin/OpenDebugAD7` 的绝对路径。
验证器还覆盖直接启动 QEMU 后 `exit` 关机。它直接驱动真实 QEMU、GDB 和已安装的 cppdbg DAP 适配器；它验证 VS Code 使用的
调试协议链路，不模拟 VS Code 编辑器鼠标操作。验证失败退出非零；日志留在 output
目录，不能把仅生成配置当作断点已命中。

源码依据：Linux 6.12 `kernel/module/main.c:do_init_module/free_module`、
`kernel/module/sysfs.c:add_sect_attrs`、`scripts/gdb/linux/symbols.py`。
官方背景：[Linux GDB 调试说明](https://www.kernel.org/doc/html/v6.12/dev-tools/gdb-kernel-debugging.html)。
