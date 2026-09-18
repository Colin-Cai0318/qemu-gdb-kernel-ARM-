#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib/host.sh"
KERNEL_VERSION="${1:-${KERNEL_VERSION:-6.12}}"
SOURCE_DIR="${KERNEL_DIR:-$SCRIPT_DIR/sourceCode}"
SOURCE_PARENT="$(dirname -- "$SOURCE_DIR")"
ARCHIVE_DIR="${KERNEL_CACHE_DIR:-$SCRIPT_DIR}"
ARCHIVE="$ARCHIVE_DIR/linux-$KERNEL_VERSION.tar.xz"
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
DOWNLOAD_URL="${KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-$KERNEL_VERSION.tar.xz}"

die() {
    echo "错误: $*" >&2
    exit 1
}

download() {
    local url="$1"
    local destination="$2"
    kernel_lab_download "$url" "$destination" 3 ||
        die "内核源码下载失败: $url"
}

[[ "$KERNEL_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    die "无效内核版本: $KERNEL_VERSION"

mkdir -p "$SOURCE_PARENT" "$ARCHIVE_DIR"
kernel_lab_require_case_sensitive_dir "$SOURCE_PARENT" || exit 1

if [[ -f "$SOURCE_DIR/Makefile" && "${FORCE_FETCH:-0}" != "1" ]]; then
    echo "内核源码已存在: $SOURCE_DIR"
    echo "如需重新展开，使用 FORCE_FETCH=1 ./main.sh fetch $KERNEL_VERSION"
    exit 0
fi

if [[ ! -f "$ARCHIVE" ]]; then
    echo "下载 $DOWNLOAD_URL"
    download "$DOWNLOAD_URL" "$ARCHIVE.part"
    mv -- "$ARCHIVE.part" "$ARCHIVE"
fi

echo "校验压缩包完整性..."
xz -t "$ARCHIVE"

if [[ -e "$SOURCE_DIR" ]]; then
    backup_dir="$SOURCE_DIR.incomplete.$(date +%Y%m%d-%H%M%S)"
    echo "保留现有不完整源码到: $backup_dir"
    mv -- "$SOURCE_DIR" "$backup_dir"
fi

extract_dir="$(mktemp -d "$SOURCE_PARENT/.extract.XXXXXX")"
cleanup() {
    case "$extract_dir" in
        "$SOURCE_PARENT"/.extract.*) rm -rf -- "$extract_dir" ;;
    esac
}
trap cleanup EXIT

echo "展开 linux-$KERNEL_VERSION..."
tar -xJf "$ARCHIVE" -C "$extract_dir"
[[ -f "$extract_dir/linux-$KERNEL_VERSION/Makefile" ]] ||
    die "压缩包中未找到预期的 linux-$KERNEL_VERSION/Makefile"
mv -- "$extract_dir/linux-$KERNEL_VERSION" "$SOURCE_DIR"

echo "内核源码已准备: $SOURCE_DIR"
