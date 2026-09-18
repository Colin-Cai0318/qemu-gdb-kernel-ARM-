#!/usr/bin/env bash

# Prepare the Linux-side project environment used by the macOS dispatcher.
# This file is sourced inside the Lima guest.

kernel_lab_prepare_guest_env() {
    local repo_root="$1"
    local data_root="$HOME/kernel-lab-data"
    local kernel_target="$data_root/kernel/sourceCode"
    local kernel_link="$repo_root/kernel/sourceCode"
    local current_target

    [[ "$(uname -s)" == "Linux" ]] || {
        echo "guest-env.sh 只能在 Linux VM 内使用" >&2
        return 1
    }

    mkdir -p "$data_root/kernel" "$data_root/cache" \
        "$data_root/busybox" "$(dirname -- "$kernel_link")"

    if [[ -L "$kernel_link" ]]; then
        current_target="$(readlink "$kernel_link")"
        [[ "$current_target" == "$kernel_target" ]] || {
            echo "拒绝覆盖已有源码链接: $kernel_link -> $current_target" >&2
            return 1
        }
    elif [[ -e "$kernel_link" ]]; then
        echo "拒绝覆盖已有路径: $kernel_link" >&2
        echo "请先确认其中是否有需要保留的源码" >&2
        return 1
    else
        ln -s "$kernel_target" "$kernel_link"
    fi

    export KERNEL_LAB_GUEST=1
    export KERNEL_DIR="$kernel_target"
    export KERNEL_LOGICAL_DIR="$kernel_link"
    export KERNEL_CACHE_DIR="$data_root/cache"
    export BUSYBOX_WORK_DIR="$data_root/busybox"
    export ROOTFS_DIR="$data_root/busybox/root"
    export CROSS_COMPILE=""
}
