#!/usr/bin/env bash
# Source this file, then call kernel_lab_gdb_setup KERNEL_DIR REPO_ROOT OUTPUT.
# Both CLI and cppdbg consume this exact command file.
kernel_lab_gdb_setup() {
    local kernel_dir="$1" repo_root="$2" output="$3"
    python3 - "$kernel_dir" "$repo_root" "$output" <<'PY'
import pathlib
import sys
kernel, repo, output = map(pathlib.Path, sys.argv[1:])
def quote(path):
    return '"' + str(path.resolve()).replace('\\', '\\\\').replace('"', '\\"') + '"'
config = (kernel / '.config').read_text()
if 'CONFIG_DEBUG_INFO_REDUCED=y' in config:
    sys.exit('CONFIG_DEBUG_INFO_REDUCED=y prevents Linux GDB helpers; run ./main.sh build')
helper = kernel / 'vmlinux-gdb.py'
if not helper.is_file():
    sys.exit('Missing vmlinux-gdb.py; run ./main.sh build (includes scripts_gdb)')
commands = [
    'set architecture aarch64',
    'set pagination off',
    'set breakpoint pending on',
    'directory ' + str(kernel.absolute()),
    # GDB's source command treats quotes as part of the filename.
    # Preserve the vmlinux-gdb.py symlink path: its __file__ locates scripts/gdb.
    'source ' + str(helper.absolute()),
    'source ' + str((repo / 'scripts/gdb/modules.py').resolve()),
    'kernel-lab-symbols ' + quote(repo / 'customized') + ' ' + quote(repo / 'labs'),
]
pathlib.Path(output).write_text('\n'.join(commands) + '\n')
PY
}
