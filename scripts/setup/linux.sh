#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
FULL_SETUP=0

if [[ "${1:-}" == "--full" ]]; then
    FULL_SETUP=1
    shift
fi
if (($# > 0)); then
    echo "未知参数: $1（支持: --full）" >&2
    exit 2
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "当前一键 Linux 部署支持 Ubuntu/Debian（需要 apt-get）" >&2
    exit 1
fi

if ((EUID == 0)); then
    sudo_command=()
elif command -v sudo >/dev/null 2>&1; then
    sudo_command=(sudo)
else
    echo "安装系统依赖需要 root 或 sudo" >&2
    exit 1
fi

packages=(
    build-essential bc bison flex libssl-dev libelf-dev pkg-config
    qemu-system-arm ipxe-qemu tmux python3 xz-utils bzip2 cpio gzip file kmod
    iproute2 curl ca-certificates git rsync dwarves
)

case "$(uname -m)" in
    aarch64|arm64) packages+=(gdb) ;;
    x86_64|amd64)
        packages+=(gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
            binutils-aarch64-linux-gnu gdb-multiarch)
        ;;
    *)
        echo "不支持的 Linux 架构: $(uname -m)" >&2
        exit 1
        ;;
esac

echo "安装 Ubuntu/Debian 实验依赖..."
for attempt in 1 2 3; do
    if "${sudo_command[@]}" apt-get -o Acquire::Retries=3 update; then
        break
    fi
    if ((attempt == 3)); then
        echo "APT 索引更新连续失败 3 次" >&2
        exit 1
    fi
    echo "APT 索引更新失败，准备重试（$attempt/3）..." >&2
    sleep 2
done
for attempt in 1 2 3; do
    if "${sudo_command[@]}" env DEBIAN_FRONTEND=noninteractive \
        apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        "${packages[@]}"; then
        break
    fi
    if ((attempt == 3)); then
        echo "APT 依赖安装连续失败 3 次" >&2
        exit 1
    fi
    echo "APT 依赖安装失败，准备重试（$attempt/3）..." >&2
    sleep 2
done

"$REPO_ROOT/scripts/check.sh"

if ((FULL_SETUP == 1)); then
    "$REPO_ROOT/main.sh" fetch
    "$REPO_ROOT/main.sh" rootfs
    "$REPO_ROOT/main.sh" build
fi

echo
echo "Linux 环境已准备。"
if ((FULL_SETUP == 0)); then
    echo "下一步: ./main.sh fetch && ./main.sh rootfs && ./main.sh build"
else
    echo "完整构建已完成；运行 ./main.sh debug 开始调试"
fi
