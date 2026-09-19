#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib/host.sh"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.33.1}"
BUSYBOX_SHA256="${BUSYBOX_SHA256:-}"
WORK_DIR="${BUSYBOX_WORK_DIR:-$SCRIPT_DIR}"
ARCHIVE="$WORK_DIR/busybox-$BUSYBOX_VERSION.tar.bz2"
SOURCE_DIR="$WORK_DIR/busybox-$BUSYBOX_VERSION"
BUILD_DIR="$WORK_DIR/build"
ROOTFS_DIR="${ROOTFS_DIR:-$WORK_DIR/root}"
STAGING_DIR="$WORK_DIR/.root.staging"
JOBS="${JOBS:-$(kernel_lab_job_count)}"
ARCH="${ARCH:-arm64}"
if [[ -z "${CROSS_COMPILE+x}" ]]; then
    CROSS_COMPILE="$(kernel_lab_default_cross_compile)"
fi
MAKE_BIN="${MAKE_BIN:-$(kernel_lab_make_command)}"

die() {
    echo "错误: $*" >&2
    exit 1
}

download() {
    local destination="$1"
    shift
    local url

    for url in "$@"; do
        echo "下载 BusyBox: $url"
        kernel_lab_download "$url" "$destination" 2 && return 0
        rm -f -- "$destination"
    done

    die "所有 BusyBox 下载源均失败"
}

for command_name in "$MAKE_BIN" tar bzip2 sha256sum "${CROSS_COMPILE}gcc"; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "缺少命令: $command_name"
done

[[ "$BUSYBOX_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    die "无效 BusyBox 版本: $BUSYBOX_VERSION"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] ||
    die "JOBS 必须是正整数"

mkdir -p "$WORK_DIR" "$(dirname -- "$ROOTFS_DIR")"

if [[ "$BUSYBOX_VERSION" == "1.33.1" && -z "$BUSYBOX_SHA256" ]]; then
    BUSYBOX_SHA256="12cec6bd2b16d8a9446dd16130f2b92982f1819f6e1c5f5887b6db03f5660d28"
fi

if [[ ! -f "$ARCHIVE" ]]; then
    download \
        "$ARCHIVE.part" \
        "https://sources.buildroot.net/busybox/busybox-$BUSYBOX_VERSION.tar.bz2" \
        "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2"
    mv -- "$ARCHIVE.part" "$ARCHIVE"
fi

if [[ -n "$BUSYBOX_SHA256" ]]; then
    printf '%s  %s\n' "$BUSYBOX_SHA256" "$ARCHIVE" | sha256sum --check -
else
    echo "警告: BusyBox $BUSYBOX_VERSION 未配置 SHA-256，仅检查归档结构" >&2
fi
tar -tjf "$ARCHIVE" >/dev/null || die "BusyBox 归档损坏: $ARCHIVE"

if [[ ! -f "$SOURCE_DIR/Makefile" ]]; then
    mkdir -p "$WORK_DIR"
    tar -xjf "$ARCHIVE" -C "$WORK_DIR"
fi

echo "配置并编译 BusyBox $BUSYBOX_VERSION（jobs=$JOBS）"
mkdir -p "$BUILD_DIR"
make_args=(O="$BUILD_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE")
"$MAKE_BIN" -C "$SOURCE_DIR" "${make_args[@]}" distclean
"$MAKE_BIN" -C "$SOURCE_DIR" "${make_args[@]}" defconfig
sed \
    -e 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
    -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
    "$BUILD_DIR/.config" \
    >"$BUILD_DIR/.config.new"
mv -- "$BUILD_DIR/.config.new" "$BUILD_DIR/.config"
"$MAKE_BIN" -C "$SOURCE_DIR" "${make_args[@]}" -j"$JOBS"

case "$STAGING_DIR" in
    "$WORK_DIR"/.root.staging) rm -rf -- "$STAGING_DIR" ;;
    *) die "拒绝清理意外路径: $STAGING_DIR" ;;
esac
mkdir -p "$STAGING_DIR"
"$MAKE_BIN" -C "$SOURCE_DIR" "${make_args[@]}" \
    CONFIG_PREFIX="$STAGING_DIR" install

mkdir -p \
    "$STAGING_DIR/etc/init.d" \
    "$STAGING_DIR/dev" \
    "$STAGING_DIR/proc" \
    "$STAGING_DIR/sys" \
    "$STAGING_DIR/tmp" \
    "$STAGING_DIR/mnt/customized" \
    "$STAGING_DIR/mnt/labs"
cp -a "$SCRIPT_DIR/tools/." "$STAGING_DIR/etc/"
chmod 0755 \
    "$STAGING_DIR/etc/init.d/rcS" \
    "$STAGING_DIR/etc/init.d/console"

if [[ -e "$ROOTFS_DIR" ]]; then
    backup_dir="$ROOTFS_DIR.backup.$(date +%Y%m%d-%H%M%S)"
    echo "保留旧 rootfs 到: $backup_dir"
    mv -- "$ROOTFS_DIR" "$backup_dir"
fi
mv -- "$STAGING_DIR" "$ROOTFS_DIR"

echo "BusyBox rootfs 已准备: $ROOTFS_DIR"
