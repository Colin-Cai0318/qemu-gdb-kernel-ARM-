#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$REPO_ROOT/kernel/sourceCode}"
ROOTFS_DIR="${ROOTFS_DIR:-$REPO_ROOT/busybox/root}"
GDB_PORT="${GDB_PORT:-1234}"

errors=0
warnings=0

ok() {
    printf '[ OK ] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*"
    warnings=$((warnings + 1))
}

fail() {
    printf '[FAIL] %s\n' "$*"
    errors=$((errors + 1))
}

check_command() {
    local command_name="$1"
    local required="${2:-yes}"

    if command -v "$command_name" >/dev/null 2>&1; then
        ok "$command_name: $(command -v "$command_name")"
    elif [[ "$required" == "yes" ]]; then
        fail "缺少命令: $command_name"
    else
        warn "可选命令未安装: $command_name"
    fi
}

echo "ARM64 Linux 内核实验环境检查"
echo "仓库: $REPO_ROOT"
echo

for command_name in git make tar xz aarch64-linux-gnu-gcc qemu-system-aarch64 gdb-multiarch tmux; do
    check_command "$command_name"
done
check_command cscope no
check_command rg no
check_command clangd no

if [[ -f "$KERNEL_DIR/Makefile" ]]; then
    kernel_version="$(
        make -s -C "$KERNEL_DIR" kernelversion 2>/dev/null || true
    )"
    ok "内核源码完整: ${kernel_version:-版本未知}"
else
    fail "内核源码不完整: $KERNEL_DIR/Makefile 不存在；运行 ./main.sh fetch"
fi

if [[ -x "$ROOTFS_DIR/linuxrc" ]]; then
    ok "BusyBox rootfs 已准备: $ROOTFS_DIR"
else
    fail "BusyBox rootfs 未准备；运行 ./main.sh rootfs"
fi

if [[ -f "$KERNEL_DIR/arch/arm64/boot/Image" && -f "$KERNEL_DIR/vmlinux" ]]; then
    ok "Image 与 vmlinux 已生成"
else
    warn "尚未生成 Image/vmlinux；运行 ./main.sh build"
fi

if command -v ss >/dev/null 2>&1 &&
    ss -ltnH | awk '{print $4}' | grep -Eq "[:.]${GDB_PORT}$"; then
    warn "TCP $GDB_PORT 已被占用；现有 QEMU 可能正在运行"
else
    ok "GDB 端口 $GDB_PORT 可用"
fi

echo
printf '结果: %d 个错误, %d 个警告\n' "$errors" "$warnings"
((errors == 0))
