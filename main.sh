#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/host.sh"

usage() {
    cat <<'EOF'
用法:
  ./main.sh doctor                 检查依赖和实验产物
  ./main.sh setup [--full]         一键安装依赖（--full 同时完成首次构建）
  ./main.sh fetch [版本]           下载/展开内核源码（默认 6.12）
  ./main.sh rootfs                 构建静态 BusyBox initramfs
  ./main.sh build [--full]         构建 Image/vmlinux；--full 同时构建内核模块
  ./main.sh qemu                   直接启动 QEMU
  ./main.sh debug                  启动等待 GDB 的 QEMU 并进入 GDB
  ./main.sh vscode                 准备 VS Code 配置并打开源码
  ./main.sh shell                  macOS: 进入项目 Linux VM
  ./main.sh console                macOS: 查看 QEMU 串口
  ./main.sh stop                   macOS: 停止项目 Linux VM

常用环境变量:
  JOBS=8                         并行编译数
  KERNEL_PROFILE=debug|stability 调试配置档
  BUILD_IN_TREE_MODULES=1       额外构建全部内核模块
  GDB_PORT=1234                  GDB 端口
  KERNEL_LAB_DOWNLOAD_MODE=auto  下载模式: auto|direct|proxy
EOF
}

run_action() {
    local action="$1"
    shift || true

    if [[ "$(uname -s)" == "Darwin" && "${KERNEL_LAB_GUEST:-0}" != "1" ]]; then
        case "$action" in
            setup) exec "$SCRIPT_DIR/setup.sh" "$@" ;;
            help|-h|--help) usage; return ;;
            *) exec "$SCRIPT_DIR/scripts/macos/dispatch.sh" "$action" "$@" ;;
        esac
    fi

    case "$action" in
        setup) "$SCRIPT_DIR/setup.sh" "$@" ;;
        doctor) "$SCRIPT_DIR/scripts/doctor.sh" "$@" ;;
        fetch) "$SCRIPT_DIR/kernel/fetch.sh" "$@" ;;
        rootfs) "$SCRIPT_DIR/busybox/BuildFS.sh" "$@" ;;
        build) "$SCRIPT_DIR/kernel/build.sh" "$@" ;;
        qemu) "$SCRIPT_DIR/qemu/runQemu.sh" "$@" ;;
        debug) "$SCRIPT_DIR/qemu/consoleStartQemu.sh" "$@" ;;
        vscode)
            kernel_dir="${KERNEL_DIR:-$SCRIPT_DIR/kernel/sourceCode}"
            workspace_dir="${KERNEL_LOGICAL_DIR:-$kernel_dir}"
            [[ -f "$kernel_dir/Makefile" ]] || {
                echo "内核源码不存在，请先运行 ./main.sh fetch" >&2
                exit 1
            }
            mkdir -p "$kernel_dir/.vscode"
            gdb_bin="$(kernel_lab_gdb_command)" || {
                echo "未找到支持 ARM64 的 GDB" >&2
                exit 1
            }
            sed "s|__KERNEL_GDB__|$gdb_bin|g" \
                "$SCRIPT_DIR/qemu/launch.json" >"$kernel_dir/.vscode/launch.json"
            cp "$SCRIPT_DIR/qemu/tasks.json" "$kernel_dir/.vscode/"
            cp "$SCRIPT_DIR/qemu/runQemu.sh" "$SCRIPT_DIR/qemu/vsStartQemu.sh" \
                "$kernel_dir/.vscode/"
            printf '%s\n' "$SCRIPT_DIR" > \
                "$kernel_dir/.vscode/kernel-lab-repo-root"
            if [[ "${VSCODE_PREPARE_ONLY:-0}" == "1" ]]; then
                echo "VS Code 配置已准备: $workspace_dir"
                return
            fi
            command -v code >/dev/null 2>&1 || {
                if [[ "${KERNEL_LAB_GUEST:-0}" == "1" ]]; then
                    echo "请输入 exit 返回 macOS，再运行 ./main.sh vscode" >&2
                    exit 2
                fi
                echo "未找到 code 命令" >&2
                exit 1
            }
            code "$workspace_dir"
            ;;
        shell|console|stop)
            echo "$action 仅用于 macOS 宿主" >&2
            exit 2
            ;;
        help|-h|--help) usage ;;
        *)
            echo "未知操作: $action" >&2
            usage >&2
            exit 2
            ;;
    esac
}

if (($# > 0)); then
    run_action "$@"
    exit
fi

cat <<'EOF'
======================================
        ARM64 Linux 内核实验台
0. 环境自检
1. 一键安装依赖
2. 准备 Linux 6.12 源码
3. 构建 BusyBox rootfs
4. 编译内核（Image + vmlinux）
5. 启动终端 GDB 调试
6. 启动 VS Code 调试
7. 全量编译内核（含全部已启用模块）
======================================
EOF
read -r -p "请选择: " operation

case "$operation" in
    0) run_action doctor ;;
    1) run_action setup ;;
    2) run_action fetch ;;
    3) run_action rootfs ;;
    4) run_action build ;;
    5) run_action debug ;;
    6) run_action vscode ;;
    7) run_action build --full ;;
    *) echo "无效输入" >&2; exit 2 ;;
esac
