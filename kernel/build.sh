#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib/host.sh"
KERNEL_DIR="${KERNEL_DIR:-$SCRIPT_DIR/sourceCode}"
ROOTFS_DIR="${ROOTFS_DIR:-$REPO_ROOT/busybox/root}"
PROFILE="${KERNEL_PROFILE:-debug}"
JOBS="${JOBS:-$(kernel_lab_job_count)}"
BUILD_IN_TREE_MODULES="${BUILD_IN_TREE_MODULES:-0}"
if [[ -z "${CROSS_COMPILE+x}" ]]; then
    CROSS_COMPILE="$(kernel_lab_default_cross_compile)"
fi
MAKE_BIN="${MAKE_BIN:-$(kernel_lab_make_command)}"
LOGFILE="${LOGFILE:-$SCRIPT_DIR/build.log}"
DEVICE_SPEC="$SCRIPT_DIR/initramfs.devices"

usage() {
    cat <<'EOF'
用法:
  ./main.sh build           构建 Image 和 vmlinux
  ./main.sh build --full    额外构建 defconfig 中全部已启用的内核模块
EOF
}

die() {
    echo "错误: $*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --full)
            BUILD_IN_TREE_MODULES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知编译参数: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

for command_name in "$MAKE_BIN" "${CROSS_COMPILE}gcc" tee; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "缺少命令: $command_name"
done

[[ -f "$KERNEL_DIR/Makefile" ]] ||
    die "内核源码不完整；请先运行 ./main.sh fetch"
[[ -x "$ROOTFS_DIR/linuxrc" ]] ||
    die "BusyBox rootfs 不完整；请先运行 ./main.sh rootfs"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] ||
    die "JOBS 必须是正整数"
[[ "$BUILD_IN_TREE_MODULES" == "0" || "$BUILD_IN_TREE_MODULES" == "1" ]] ||
    die "BUILD_IN_TREE_MODULES 必须是 0 或 1"

config_fragments=("$SCRIPT_DIR/debug.config")
case "$PROFILE" in
    debug) ;;
    stability) config_fragments+=("$SCRIPT_DIR/stability.config") ;;
    *) die "未知 KERNEL_PROFILE: $PROFILE（可选 debug 或 stability）" ;;
esac

start_time=$SECONDS
if [[ "$BUILD_IN_TREE_MODULES" == "1" ]]; then
    build_mode="full"
else
    build_mode="core"
fi
echo "配置 ARM64 内核（profile=$PROFILE, mode=$build_mode, jobs=$JOBS）"
make_args=(ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE")

if [[ "${CLEAN_BUILD:-0}" == "1" ]]; then
    "$MAKE_BIN" -C "$KERNEL_DIR" "${make_args[@]}" mrproper
fi

"$MAKE_BIN" -C "$KERNEL_DIR" "${make_args[@]}" defconfig
"$KERNEL_DIR/scripts/kconfig/merge_config.sh" -m -r -O "$KERNEL_DIR" \
    "$KERNEL_DIR/.config" "${config_fragments[@]}"
"$KERNEL_DIR/scripts/config" --file "$KERNEL_DIR/.config" \
    --set-str INITRAMFS_SOURCE "$ROOTFS_DIR $DEVICE_SPEC"
"$KERNEL_DIR/scripts/config" --file "$KERNEL_DIR/.config" \
    --set-val INITRAMFS_ROOT_UID 0
"$KERNEL_DIR/scripts/config" --file "$KERNEL_DIR/.config" \
    --set-val INITRAMFS_ROOT_GID 0
"$MAKE_BIN" -C "$KERNEL_DIR" "${make_args[@]}" olddefconfig

build_targets=(Image vmlinux)
if [[ "$BUILD_IN_TREE_MODULES" == "1" ]]; then
    build_targets+=(modules)
fi

echo "编译目标: ${build_targets[*]}；完整日志: $LOGFILE"
"$MAKE_BIN" -C "$KERNEL_DIR" \
    "${make_args[@]}" \
    -j"$JOBS" \
    "${build_targets[@]}" 2>&1 | tee "$LOGFILE"

if [[ "$BUILD_IN_TREE_MODULES" == "0" && -f "$KERNEL_DIR/vmlinux.symvers" ]]; then
    # External module builds read Module.symvers. For an Image-only build,
    # vmlinux.symvers contains the exported core-kernel symbols they need.
    cp -- "$KERNEL_DIR/vmlinux.symvers" "$KERNEL_DIR/Module.symvers"
    echo "外部模块符号表: $KERNEL_DIR/Module.symvers"
fi

elapsed_time=$((SECONDS - start_time))
printf '编译完成，用时 %02d:%02d:%02d\n' \
    "$((elapsed_time / 3600))" \
    "$(((elapsed_time % 3600) / 60))" \
    "$((elapsed_time % 60))"
echo "Image:   $KERNEL_DIR/arch/arm64/boot/Image"
echo "vmlinux: $KERNEL_DIR/vmlinux"
