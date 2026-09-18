#!/usr/bin/env bash

# Shared host helpers. Keep this file compatible with the Bash 3.2 shipped by
# macOS; project scripts source it before a newer Linux-side Bash is available.

kernel_lab_job_count() {
    local jobs

    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi

    if command -v sysctl >/dev/null 2>&1; then
        jobs="$(sysctl -n hw.ncpu 2>/dev/null || true)"
        if [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
            printf '%s\n' "$jobs"
            return
        fi
    fi

    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    if [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' "$jobs"
    else
        printf '1\n'
    fi
}

kernel_lab_make_command() {
    if [[ "$(uname -s)" == "Darwin" ]] && command -v gmake >/dev/null 2>&1; then
        command -v gmake
    else
        command -v make 2>/dev/null || printf 'make\n'
    fi
}

kernel_lab_default_cross_compile() {
    case "$(uname -s):$(uname -m)" in
        Linux:aarch64|Linux:arm64) printf '%s' "" ;;
        *) printf '%s' "aarch64-linux-gnu-" ;;
    esac
}

kernel_lab_gdb_command() {
    if [[ -n "${GDB_BIN:-}" ]] && command -v "$GDB_BIN" >/dev/null 2>&1; then
        command -v "$GDB_BIN"
    elif command -v gdb-multiarch >/dev/null 2>&1; then
        command -v gdb-multiarch
    elif command -v gdb >/dev/null 2>&1; then
        command -v gdb
    else
        return 1
    fi
}

kernel_lab_port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -ltnH | awk '{print $4}' | grep -Eq "[:.]${port}$"
    elif command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    else
        return 1
    fi
}

kernel_lab_require_case_sensitive_dir() {
    local directory="$1"
    local lower="$directory/.kernel-lab-case-check-$$-a"
    local upper="$directory/.kernel-lab-case-check-$$-A"

    : >"$lower"
    if [[ -e "$upper" ]]; then
        rm -f -- "$lower"
        echo "错误: 目标目录所在文件系统不区分大小写: $directory" >&2
        echo "Linux 源码包含仅大小写不同的文件；请使用 Linux VM 或大小写敏感卷" >&2
        return 1
    fi
    rm -f -- "$lower"
}

kernel_lab_download_once() {
    local mode="$1"
    local url="$2"
    local destination="$3"
    local retries="${4:-3}"
    local curl_args
    local wget_args

    if command -v curl >/dev/null 2>&1; then
        curl_args=(--fail --location --retry "$retries" --connect-timeout 15)
        [[ -s "$destination" ]] && curl_args+=(--continue-at -)
        [[ "$mode" == "direct" ]] && curl_args+=(--noproxy '*')
        curl "${curl_args[@]}" --output "$destination" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget_args=(--tries="$retries" --continue)
        [[ "$mode" == "direct" ]] && wget_args+=(--no-proxy)
        wget "${wget_args[@]}" --output-document="$destination" "$url"
    else
        echo "需要 curl 或 wget 下载文件" >&2
        return 1
    fi
}

kernel_lab_download() {
    local url="$1"
    local destination="$2"
    local retries="${3:-3}"
    local mode="${KERNEL_LAB_DOWNLOAD_MODE:-auto}"

    case "$mode" in
        direct|proxy)
            kernel_lab_download_once "$mode" "$url" "$destination" "$retries"
            ;;
        auto)
            if kernel_lab_download_once direct "$url" "$destination" "$retries"; then
                return 0
            fi
            echo "直连下载失败，自动回退到系统代理: $url" >&2
            kernel_lab_download_once proxy "$url" "$destination" "$retries"
            ;;
        *)
            echo "KERNEL_LAB_DOWNLOAD_MODE 仅支持 auto、direct 或 proxy" >&2
            return 2
            ;;
    esac
}
