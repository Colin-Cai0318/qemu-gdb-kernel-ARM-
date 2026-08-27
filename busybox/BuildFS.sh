#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.33.1}"
BUSYBOX_SHA256="${BUSYBOX_SHA256:-}"
ARCHIVE="$SCRIPT_DIR/busybox-$BUSYBOX_VERSION.tar.bz2"
SOURCE_DIR="$SCRIPT_DIR/busybox-$BUSYBOX_VERSION"
BUILD_DIR="$SCRIPT_DIR/build"
ROOTFS_DIR="$SCRIPT_DIR/root"
STAGING_DIR="$SCRIPT_DIR/.root.staging"
JOBS="${JOBS:-$(nproc)}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

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
        if command -v curl >/dev/null 2>&1; then
            curl --fail --location --retry 2 \
                --output "$destination" "$url" && return 0
        elif command -v wget >/dev/null 2>&1; then
            wget --tries=2 --output-document="$destination" "$url" &&
                return 0
        else
            die "需要 curl 或 wget 下载 BusyBox"
        fi
        rm -f -- "$destination"
    done

    die "所有 BusyBox 下载源均失败"
}

for command_name in make tar bzip2 sha256sum "${CROSS_COMPILE}gcc"; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "缺少命令: $command_name"
done

[[ "$BUSYBOX_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    die "无效 BusyBox 版本: $BUSYBOX_VERSION"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] ||
    die "JOBS 必须是正整数"

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
    tar -xjf "$ARCHIVE" -C "$SCRIPT_DIR"
fi

echo "配置并编译 BusyBox $BUSYBOX_VERSION（jobs=$JOBS）"
mkdir -p "$BUILD_DIR"
make_args=(O="$BUILD_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE")
make -C "$SOURCE_DIR" "${make_args[@]}" distclean
make -C "$SOURCE_DIR" "${make_args[@]}" defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "$BUILD_DIR/.config"
make -C "$SOURCE_DIR" "${make_args[@]}" -j"$JOBS"

case "$STAGING_DIR" in
    "$SCRIPT_DIR"/.root.staging) rm -rf -- "$STAGING_DIR" ;;
    *) die "拒绝清理意外路径: $STAGING_DIR" ;;
esac
mkdir -p "$STAGING_DIR"
make -C "$SOURCE_DIR" "${make_args[@]}" \
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
chmod 0755 "$STAGING_DIR/etc/init.d/rcS"

if [[ -e "$ROOTFS_DIR" ]]; then
    backup_dir="$SCRIPT_DIR/root.backup.$(date +%Y%m%d-%H%M%S)"
    echo "保留旧 rootfs 到: $backup_dir"
    mv -- "$ROOTFS_DIR" "$backup_dir"
fi
mv -- "$STAGING_DIR" "$ROOTFS_DIR"

echo "BusyBox rootfs 已准备: $ROOTFS_DIR"
