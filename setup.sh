#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) exec "$SCRIPT_DIR/scripts/setup/macos.sh" "$@" ;;
    Linux) exec "$SCRIPT_DIR/scripts/setup/linux.sh" "$@" ;;
    *)
        echo "不支持的宿主系统: $(uname -s)" >&2
        exit 1
        ;;
esac
