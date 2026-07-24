#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$REPO_ROOT/kernel/sourceCode}"
GDB_PORT="${GDB_PORT:-1234}"
VMLINUX="$KERNEL_DIR/vmlinux"

[[ -f "$VMLINUX" ]] || {
    echo "vmlinux 不存在: $VMLINUX；请先运行 ./main.sh build" >&2
    exit 1
}

"$SCRIPT_DIR/vsStartQemu.sh"

gdb_args=(
    "$VMLINUX"
    -ex "set architecture aarch64"
    -ex "set pagination off"
)

if [[ -f "$KERNEL_DIR/scripts/gdb/vmlinux-gdb.py" ]]; then
    gdb_args+=(-ex "source $KERNEL_DIR/scripts/gdb/vmlinux-gdb.py")
fi

gdb_args+=(
    -ex "target remote localhost:$GDB_PORT"
    -ex "break start_kernel"
)

exec gdb-multiarch "${gdb_args[@]}"
