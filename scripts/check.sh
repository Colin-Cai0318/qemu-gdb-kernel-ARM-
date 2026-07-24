#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

mapfile -t shell_files < <(
    find "$REPO_ROOT" \
        -path "$REPO_ROOT/kernel/sourceCode" -prune -o \
        -path "$REPO_ROOT/busybox/busybox-*" -prune -o \
        -name '*.sh' -type f -print
)

for shell_file in "${shell_files[@]}"; do
    bash -n "$shell_file"
done

python3 -m json.tool "$REPO_ROOT/qemu/launch.json" >/dev/null
python3 -m json.tool "$REPO_ROOT/qemu/tasks.json" >/dev/null

echo "静态检查通过: ${#shell_files[@]} 个 shell 脚本，2 个 JSON 文件"
