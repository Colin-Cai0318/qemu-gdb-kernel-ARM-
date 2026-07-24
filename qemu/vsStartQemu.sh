#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_NAME="${QEMU_SESSION:-qemu-session}"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "tmux 会话 $SESSION_NAME 已存在；不会终止它" >&2
    echo "查看: tmux attach -t $SESSION_NAME" >&2
    echo "停止: tmux kill-session -t $SESSION_NAME" >&2
    exit 1
fi

LOG_FILE="${QEMU_LOG:-$(pwd)/qemu.log}"
: >"$LOG_FILE"

tmux new-session -d -s "$SESSION_NAME" \
    "'$SCRIPT_DIR/runQemu.sh' --wait-gdb 2>&1 | tee '$LOG_FILE'"

ready=0
for _ in $(seq 1 50); do
    if command -v ss >/dev/null 2>&1 &&
        ss -ltnH | awk '{print $4}' | grep -Eq "[:.]${GDB_PORT:-1234}$"; then
        ready=1
        break
    fi
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "QEMU 启动失败，请检查日志: $LOG_FILE" >&2
        exit 1
    fi
    sleep 0.1
done

if ((ready == 0)); then
    echo "QEMU 未在预期时间内监听 GDB 端口，请检查: $LOG_FILE" >&2
    exit 1
fi

echo "QEMU 已启动，等待 GDB 连接..."
echo "查看串口: tmux attach -t $SESSION_NAME"
echo "日志: $LOG_FILE"
