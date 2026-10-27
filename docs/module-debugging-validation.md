# 自定义模块断点验证记录（2026-10-27）

结论：本次修改在 Apple Silicon macOS 的项目 Ubuntu ARM64 VM 内完成全量构建与
运行验证，GDB 和 VS Code cppdbg 模块断点链路均 PASS。

## 同源构建

- 仓库基线：`ce90746`；内核为未修改的 Linux 6.12 归档源码。
- GCC 13.3.0，QEMU 8.2.2，GDB 15.1，远程 C/C++ 扩展 1.34.4（linux-arm64）。
- `./main.sh build --full` 清理后构建 Image、vmlinux 和全部已启用模块，用时 9 分 48 秒；
  生成 1309 个内核模块。随后增量构建补齐 `scripts_gdb`；最终同一树执行
  `make ARCH=arm64 CROSS_COMPILE= -j6 Image vmlinux modules scripts_gdb` 成功。
- `CONFIG_DEBUG_INFO_DWARF4=y`、`CONFIG_GDB_SCRIPTS=y`、
  `# CONFIG_DEBUG_INFO_REDUCED is not set`。
- `customized/main.ko`、A01、A02 均在该构建树编译；自定义模块 vermagic 为
  `6.12.0 SMP preempt mod_unload aarch64`。

构建标识（SHA-256）：

| 产物 | SHA-256 |
| --- | --- |
| .config | `8c01bc2004d87c6e4d368d17d73d5b5fbec27f719f2b95156cfd155f3b6a65ee` |
| vmlinux | `0e0eda8a35064a5adf092bd92ad2e124339aaf667882f1c313dc46584df18a15` |
| Image | `7cd8128e1242b09950ab961988dd26a3db03f6c71872fe46d1d982fe4296d3d0` |
| customized/main.ko | `3490cb7f4b871c9adfd8fd7d5a503fe5130b93397ac053bf30912b8a978633dc` |

## 验证范围

| 检查 | 结果与证据 |
| --- | --- |
| 静态检查 | 18 个 Shell、2 个 JSON、Python AST 全部 PASS |
| doctor | 0 错误；cscope、clangd 两项可选依赖未安装 |
| 旧产物拒绝 | `CONFIG_DEBUG_INFO_REDUCED=y` 明确失败，提示重新构建 |
| 终端模块断点 | hello_start、hello_end 两轮加载/卸载，bt、源码定位、next 全部通过 |
| 普通 .text | A02 a02_wakeup_write 命中，读取 count=5，处理 handled=1 并卸载 |
| 已有模块符号 | kernel-lab-refresh 在暂停状态保留正确符号 |
| 初始化失败与恢复 | A01 fail_init=1 返回失败；随后正常加载/卸载成功 |
| cppdbg | DAP 源码行 19/26 两轮命中，调用栈源文件匹配，Watch 读取 PC，next 返回 step |
| 同名源码排除 | MI -break-insert 使用 customized/main.c 完整绝对路径，避免内核 main.c 误绑定 |
| VS Code Start QEMU | 使用实际生成的 .vscode 脚本，端口 12450，start_kernel 命中，正常退出测试会话 |
| 终端入口 | ./main.sh debug，端口 12451，start_kernel 命中 |
| 直接启动/关机 | ./main.sh qemu，Guest exit 后 QEMU 返回 0 |
| A02 原有回归 | A02_RUNTIME_PASS、A02_TRACEPOINT_PASS、A02_QEMU_VALIDATION=PASS |

运行验证器最终输出：

```text
CLI_KO_DEBUG=PASS
VSCODE_CPPDBG_KO_DEBUG=PASS
DIRECT_QEMU_BOOT_EXIT=PASS
KO_DEBUG_VALIDATION=PASS
```

cppdbg 验证直接使用 VM 中安装的 OpenDebugAD7 和真实 QEMU，不模拟编辑器鼠标操作。
F5 默认停在 QEMU 初始指令；需要停在 start_kernel 时在 VS Code 添加对应函数断点。
GDB 对内核到用户态边界的回溯仍可能给出展开终止提示；本次核验范围是模块及内核调用栈。
原始日志、源码、配置、ELF 与模块保存在本机验证目录，未提交到公共仓库。
本记录证明平台行为，不替代 A01/A02 的用户学习报告或改变学习验收结论。

复现步骤见 [模块调试操作说明](module-debugging.md)。
