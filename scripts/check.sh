#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

shell_count=0
while IFS= read -r shell_file; do
    bash -n "$shell_file"
    shell_count=$((shell_count + 1))
done < <(
    find "$REPO_ROOT" \
        -path "$REPO_ROOT/kernel/sourceCode" -prune -o \
        -path "$REPO_ROOT/busybox/busybox-*" -prune -o \
        -path "$REPO_ROOT/tools" -prune -o \
        -name '*.sh' -type f -print
)

python3 -m json.tool "$REPO_ROOT/qemu/launch.json" >/dev/null
python3 -m json.tool "$REPO_ROOT/qemu/tasks.json" >/dev/null

echo "静态检查通过: $shell_count 个 shell 脚本，2 个 JSON 文件"
