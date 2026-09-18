#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
LIMA_VERSION="2.2.0"
LIMACTL="$TOOLS_DIR/lima-$LIMA_VERSION/bin/limactl"
LIMA_HOME_DIR="$TOOLS_DIR/lima-home"
LOCAL_HOME="$TOOLS_DIR/host-home"
LOCAL_TMP="$TOOLS_DIR/tmp"
INSTANCE_NAME="kernel-lab"

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || {
    echo "macOS 调度器仅支持 Apple Silicon" >&2
    exit 1
}

[[ -x "$LIMACTL" && -f "$LIMA_HOME_DIR/$INSTANCE_NAME/lima.yaml" ]] || {
    echo "macOS 实验环境尚未部署；请先运行 ./setup.sh" >&2
    exit 1
}

run_lima() {
    HOME="$LOCAL_HOME" \
    TMPDIR="$LOCAL_TMP" \
    LIMA_HOME="$LIMA_HOME_DIR" \
    "$LIMACTL" "$@"
}

env_args=(env "QEMU_ACCEL=${QEMU_ACCEL:-tcg,thread=multi}")
for variable_name in JOBS KERNEL_PROFILE BUILD_IN_TREE_MODULES GDB_PORT \
    KERNEL_VERSION BUSYBOX_VERSION CLEAN_BUILD FORCE_FETCH QEMU_SESSION; do
    if variable_value="$(printenv "$variable_name" 2>/dev/null)"; then
        env_args+=("$variable_name=$variable_value")
    fi
done

action="${1:-shell}"
case "$action" in
    shell)
        run_lima start -y "$INSTANCE_NAME" >/dev/null
        exec env HOME="$LOCAL_HOME" TMPDIR="$LOCAL_TMP" \
            LIMA_HOME="$LIMA_HOME_DIR" \
            "$LIMACTL" shell "$INSTANCE_NAME" -- \
            "${env_args[@]}" bash -lc '
repo_root="$1"
data_root="$HOME/kernel-lab-data"
export KERNEL_LAB_GUEST=1
export KERNEL_DIR="$data_root/kernel/sourceCode"
export KERNEL_CACHE_DIR="$data_root/cache"
export BUSYBOX_WORK_DIR="$data_root/busybox"
export ROOTFS_DIR="$data_root/busybox/root"
export CROSS_COMPILE=""
cd "$repo_root"
printf "已进入 Ubuntu ARM64 项目 VM（输入 exit 返回 macOS）\n"
printf "项目目录: %s\n内核目录: %s\n" "$repo_root" "$KERNEL_DIR"
export PS1="(kernel-lab VM) \W\$ "
exec bash --noprofile --norc -i
' kernel-lab "$REPO_ROOT"
        ;;
    stop)
        exec env HOME="$LOCAL_HOME" TMPDIR="$LOCAL_TMP" \
            LIMA_HOME="$LIMA_HOME_DIR" \
            "$LIMACTL" stop "$INSTANCE_NAME"
        ;;
    console)
        run_lima start -y "$INSTANCE_NAME" >/dev/null
        exec env HOME="$LOCAL_HOME" TMPDIR="$LOCAL_TMP" \
            LIMA_HOME="$LIMA_HOME_DIR" \
            "$LIMACTL" shell "$INSTANCE_NAME" -- tmux attach -t "${QEMU_SESSION:-qemu-session}"
        ;;
    vscode)
        echo "macOS 路径当前使用终端 GDB；请运行 ./main.sh debug" >&2
        exit 2
        ;;
esac

run_lima start -y "$INSTANCE_NAME" >/dev/null
echo "macOS -> ARM64 Linux VM: $*"

guest_command='
repo_root="$1"
shift
data_root="$HOME/kernel-lab-data"
export KERNEL_LAB_GUEST=1
export KERNEL_DIR="$data_root/kernel/sourceCode"
export KERNEL_CACHE_DIR="$data_root/cache"
export BUSYBOX_WORK_DIR="$data_root/busybox"
export ROOTFS_DIR="$data_root/busybox/root"
export CROSS_COMPILE=""
cd "$repo_root"
exec "$repo_root/main.sh" "$@"
'

exec env HOME="$LOCAL_HOME" TMPDIR="$LOCAL_TMP" \
    LIMA_HOME="$LIMA_HOME_DIR" \
    "$LIMACTL" shell "$INSTANCE_NAME" -- \
    "${env_args[@]}" bash -lc "$guest_command" kernel-lab "$REPO_ROOT" "$@"
