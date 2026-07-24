#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/../Makefile" && -d "$SCRIPT_DIR/../arch/arm64" ]]; then
    # Copied into kernel/sourceCode/.vscode by ./main.sh vscode.
    KERNEL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
    REPO_ROOT="$(cd -- "$KERNEL_DIR/../.." && pwd)"
else
    REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
    KERNEL_DIR="${KERNEL_DIR:-$REPO_ROOT/kernel/sourceCode}"
fi

IMAGE="$KERNEL_DIR/arch/arm64/boot/Image"
GDB_PORT="${GDB_PORT:-1234}"
WAIT_GDB=0

[[ "$GDB_PORT" =~ ^[0-9]+$ ]] && ((GDB_PORT >= 1 && GDB_PORT <= 65535)) || {
    echo "GDB_PORT 必须是 1-65535 的整数" >&2
    exit 2
}

if [[ "${1:-}" == "--wait-gdb" ]]; then
    WAIT_GDB=1
elif (($# > 0)); then
    echo "未知参数: $1" >&2
    exit 2
fi

[[ -f "$IMAGE" ]] || {
    echo "Image 不存在: $IMAGE；请先运行 ./main.sh build" >&2
    exit 1
}

if command -v ss >/dev/null 2>&1 &&
    ss -ltnH | awk '{print $4}' | grep -Eq "[:.]${GDB_PORT}$"; then
    echo "GDB 端口 $GDB_PORT 已被占用；不会终止未知进程" >&2
    echo "可检查: ss -ltnp | grep :$GDB_PORT" >&2
    exit 1
fi

qemu_args=(
    -machine virt
    -cpu cortex-a57
    -m 1024M
    -smp 4
    -kernel "$IMAGE"
    -append "rdinit=/linuxrc nokaslr console=ttyAMA0 loglevel=8"
    -virtfs "local,path=$REPO_ROOT/customized,mount_tag=customized,security_model=none,id=customized"
    -virtfs "local,path=$REPO_ROOT/labs,mount_tag=labs,security_model=none,id=labs,readonly=on"
    -gdb "tcp::$GDB_PORT"
    -nographic
)

if ((WAIT_GDB == 1)); then
    qemu_args+=(-S)
    echo "QEMU 将在第一条指令前等待 GDB（端口 $GDB_PORT）"
fi

exec qemu-system-aarch64 "${qemu_args[@]}"
