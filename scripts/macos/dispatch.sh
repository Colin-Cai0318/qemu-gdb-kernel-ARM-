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
CODE_APP_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

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
source "$repo_root/scripts/macos/guest-env.sh"
kernel_lab_prepare_guest_env "$repo_root"
cd "$repo_root"
printf "已进入 Ubuntu ARM64 项目 VM（输入 exit 返回 macOS）\n"
printf "项目目录: %s\n内核目录: %s -> %s\n" \
    "$repo_root" "$KERNEL_LOGICAL_DIR" "$KERNEL_DIR"
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
        run_lima start -y "$INSTANCE_NAME" >/dev/null
        code_bin="$(command -v code 2>/dev/null || true)"
        [[ -n "$code_bin" ]] || code_bin="$CODE_APP_BIN"
        [[ -x "$code_bin" ]] || {
            echo "未找到 Visual Studio Code" >&2
            exit 1
        }

        run_lima shell "$INSTANCE_NAME" -- \
            "${env_args[@]}" env VSCODE_PREPARE_ONLY=1 bash -lc '
repo_root="$1"
source "$repo_root/scripts/macos/guest-env.sh"
kernel_lab_prepare_guest_env "$repo_root"
cd "$repo_root"
exec "$repo_root/main.sh" vscode
' kernel-lab "$REPO_ROOT"

        vscode_data="$TOOLS_DIR/vscode-user-data"
        vscode_extensions="$TOOLS_DIR/vscode-extensions"
        vscode_settings="$vscode_data/User/settings.json"
        ssh_config="$LIMA_HOME_DIR/$INSTANCE_NAME/ssh.config"
        run_code_without_proxy() {
            env -u ALL_PROXY -u HTTPS_PROXY -u HTTP_PROXY \
                -u all_proxy -u https_proxy -u http_proxy \
                "$code_bin" --no-proxy-server "$@"
        }
        mkdir -p "$(dirname -- "$vscode_settings")" "$vscode_extensions"
        printf '%s\n' \
            '{' \
            "  \"remote.SSH.configFile\": \"$ssh_config\"," \
            '  "remote.SSH.remotePlatform": {"lima-kernel-lab": "linux"}' \
            '}' >"$vscode_settings"

        if ! "$code_bin" --user-data-dir "$vscode_data" \
            --extensions-dir "$vscode_extensions" --list-extensions 2>/dev/null |
            grep -qx 'ms-vscode-remote.remote-ssh'; then
            echo "安装项目私有 VS Code Remote SSH 扩展..."
            run_code_without_proxy --user-data-dir "$vscode_data" \
                --extensions-dir "$vscode_extensions" \
                --install-extension ms-vscode-remote.remote-ssh
        fi

        echo "通过 Remote SSH 打开 VM 内核源码..."
        "$code_bin" --user-data-dir "$vscode_data" \
            --extensions-dir "$vscode_extensions" --new-window \
            --remote ssh-remote+lima-kernel-lab \
            /home/caizhipeng.guest/kernel-lab-data/kernel/sourceCode

        echo "检查 VM 中的 C/C++ 调试扩展..."
        run_lima shell "$INSTANCE_NAME" -- bash -lc '
server=""
for _ in $(seq 1 120); do
    server=$(find "$HOME/.vscode-server/cli/servers" \
        -path "*/server/bin/code-server" -type f 2>/dev/null | head -n 1)
    [[ -n "$server" ]] && break
    sleep 0.5
done
[[ -n "$server" ]] || {
    echo "VS Code Server 未能在 VM 中就绪" >&2
    exit 1
}
extensions_dir="$HOME/.vscode-server/extensions"
if ! "$server" --extensions-dir "$extensions_dir" --list-extensions |
    grep -qx "ms-vscode.cpptools"; then
    echo "在 VM 中安装 C/C++ 调试扩展..."
    env -u ALL_PROXY -u HTTPS_PROXY -u HTTP_PROXY \
        -u all_proxy -u https_proxy -u http_proxy \
        "$server" --extensions-dir "$extensions_dir" \
        --install-extension ms-vscode.cpptools
fi
'
        exit 0
        ;;
esac

run_lima start -y "$INSTANCE_NAME" >/dev/null
echo "macOS -> ARM64 Linux VM: $*"

guest_command='
repo_root="$1"
shift
source "$repo_root/scripts/macos/guest-env.sh"
kernel_lab_prepare_guest_env "$repo_root"
cd "$repo_root"
exec "$repo_root/main.sh" "$@"
'

exec env HOME="$LOCAL_HOME" TMPDIR="$LOCAL_TMP" \
    LIMA_HOME="$LIMA_HOME_DIR" \
    "$LIMACTL" shell "$INSTANCE_NAME" -- \
    "${env_args[@]}" bash -lc "$guest_command" kernel-lab "$REPO_ROOT" "$@"
