#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.33.1}"
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
    local url="$1"
    local destination="$2"

    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 3 --output "$destination" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=3 --output-document="$destination" "$url"
    else
        die "需要 curl 或 wget 下载 BusyBox"
    fi
}

for command_name in make tar bzip2 "${CROSS_COMPILE}gcc"; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "缺少命令: $command_name"
done

[[ "$BUSYBOX_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    die "无效 BusyBox 版本: $BUSYBOX_VERSION"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] ||
    die "JOBS 必须是正整数"

if [[ ! -f "$ARCHIVE" ]]; then
    download \
        "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" \
        "$ARCHIVE.part"
    mv -- "$ARCHIVE.part" "$ARCHIVE"
fi

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
