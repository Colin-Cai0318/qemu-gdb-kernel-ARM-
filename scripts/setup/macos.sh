#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
LIMA_VERSION="2.2.0"
LIMA_SHA256="bbdef91774885a0d05f7b048c4eb89ae2bcf3a0c252ae7ca7934e63df76d93c3"
LIMA_ARCHIVE="$TOOLS_DIR/cache/lima-$LIMA_VERSION-Darwin-arm64.tar.gz"
LIMA_URL="https://github.com/lima-vm/lima/releases/download/v$LIMA_VERSION/lima-$LIMA_VERSION-Darwin-arm64.tar.gz"
LIMA_INSTALL="$TOOLS_DIR/lima-$LIMA_VERSION"
LIMACTL="$LIMA_INSTALL/bin/limactl"
LIMA_HOME_DIR="$TOOLS_DIR/lima-home"
LOCAL_HOME="$TOOLS_DIR/host-home"
LOCAL_TMP="$TOOLS_DIR/tmp"
INSTANCE_NAME="kernel-lab"
WORKSPACE_ROOT="${KERNEL_LAB_WORKSPACE_ROOT:-$(cd -- "$REPO_ROOT/.." && pwd)}"
FULL_SETUP=0

source "$REPO_ROOT/scripts/lib/host.sh"

if [[ "${1:-}" == "--full" ]]; then
    FULL_SETUP=1
    shift
fi
if (($# > 0)); then
    echo "未知参数: $1（支持: --full）" >&2
    exit 2
fi

[[ "$(uname -s)" == "Darwin" ]] || {
    echo "此脚本仅用于 macOS" >&2
    exit 1
}
[[ "$(uname -m)" == "arm64" ]] || {
    echo "仅支持 Apple Silicon Mac；不支持 Intel Mac" >&2
    exit 1
}

case "$REPO_ROOT" in
    /Users/caizhipeng/workspace/*) ;;
    *)
        echo "仓库必须位于 /Users/caizhipeng/workspace 内，当前为: $REPO_ROOT" >&2
        exit 1
        ;;
esac

mkdir -p "$TOOLS_DIR/cache" "$LOCAL_HOME" "$LOCAL_TMP" "$LIMA_HOME_DIR"

run_lima() {
    HOME="$LOCAL_HOME" \
    TMPDIR="$LOCAL_TMP" \
    LIMA_HOME="$LIMA_HOME_DIR" \
    "$LIMACTL" "$@"
}

if [[ ! -x "$LIMACTL" ]]; then
    if [[ ! -f "$LIMA_ARCHIVE" ]]; then
        echo "下载 Lima $LIMA_VERSION 到 tools/cache..."
        curl --fail --location --retry 3 --output "$LIMA_ARCHIVE.part" "$LIMA_URL"
        mv -- "$LIMA_ARCHIVE.part" "$LIMA_ARCHIVE"
    fi

    actual_sha="$(shasum -a 256 "$LIMA_ARCHIVE" | awk '{print $1}')"
    [[ "$actual_sha" == "$LIMA_SHA256" ]] || {
        echo "Lima 压缩包 SHA-256 不匹配" >&2
        exit 1
    }

    mkdir -p "$LIMA_INSTALL"
    tar -xzf "$LIMA_ARCHIVE" -C "$LIMA_INSTALL"
fi

[[ -x "$LIMACTL" ]] || {
    echo "Lima 安装不完整: $LIMACTL" >&2
    exit 1
}

host_cpus="$(kernel_lab_job_count)"
vm_cpus="$host_cpus"
((vm_cpus > 6)) && vm_cpus=6
((vm_cpus < 2)) && vm_cpus=2

host_memory_bytes="$(sysctl -n hw.memsize)"
if ((host_memory_bytes >= 16 * 1024 * 1024 * 1024)); then
    vm_memory="8"
else
    vm_memory="4"
fi

if [[ ! -f "$LIMA_HOME_DIR/$INSTANCE_NAME/lima.yaml" ]]; then
    echo "创建 Apple Silicon ARM64 Linux VM..."
    run_lima start -y \
        --name="$INSTANCE_NAME" \
        --vm-type=vz \
        --arch=aarch64 \
        --cpus="${KERNEL_LAB_VM_CPUS:-$vm_cpus}" \
        --memory="${KERNEL_LAB_VM_MEMORY:-$vm_memory}" \
        --disk="${KERNEL_LAB_VM_DISK:-80}" \
        --containerd=none \
        --mount="$WORKSPACE_ROOT" \
        --mount-writable \
        template:ubuntu-24.04
else
    echo "启动已有 Linux VM..."
    run_lima start -y "$INSTANCE_NAME"
fi

echo "在 Linux VM 中安装内核实验依赖..."
run_lima shell "$INSTANCE_NAME" -- bash -lc '
set -Eeuo pipefail
marker="$HOME/.kernel-lab-provision-v2"
if [[ ! -f "$marker" ]]; then
    for attempt in 1 2 3; do
        if sudo apt-get -o Acquire::Retries=3 update; then
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
        if sudo env DEBIAN_FRONTEND=noninteractive apt-get \
            -o Acquire::Retries=3 install -y \
            --no-install-recommends \
            build-essential bc bison flex libssl-dev libelf-dev pkg-config \
            gdb qemu-system-arm ipxe-qemu tmux python3 xz-utils bzip2 cpio gzip file \
            kmod iproute2 curl ca-certificates git rsync dwarves; then
            break
        fi
        if ((attempt == 3)); then
            echo "APT 依赖安装连续失败 3 次" >&2
            exit 1
        fi
        echo "APT 依赖安装失败，准备重试（$attempt/3）..." >&2
        sleep 2
    done
    touch "$marker"
fi
mkdir -p "$HOME/kernel-lab-data/kernel" \
    "$HOME/kernel-lab-data/busybox" \
    "$HOME/kernel-lab-data/cache"
'

"$REPO_ROOT/scripts/check.sh"

if ((FULL_SETUP == 1)); then
    "$REPO_ROOT/main.sh" fetch
    "$REPO_ROOT/main.sh" rootfs
    "$REPO_ROOT/main.sh" build
fi

echo
echo "Apple Silicon macOS 环境已准备。"
echo "工具与 VM 数据: $TOOLS_DIR"
if ((FULL_SETUP == 0)); then
    echo "下一步: ./main.sh fetch && ./main.sh rootfs && ./main.sh build"
else
    echo "完整构建已完成；运行 ./main.sh debug 开始调试"
fi
