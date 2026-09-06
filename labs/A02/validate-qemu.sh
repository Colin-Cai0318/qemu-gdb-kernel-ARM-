#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KDIR="${KDIR:?set KDIR to the built ARM64 kernel tree}"
ROOTFS_STAGING="${ROOTFS_STAGING:?set ROOTFS_STAGING to a BusyBox rootfs directory}"
QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
QEMU_TIMEOUT="${QEMU_TIMEOUT:-45s}"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

for command_name in "$QEMU_BIN" timeout cpio gzip python3 modinfo sha256sum file; do
	command -v "$command_name" >/dev/null || {
		printf 'missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done

[[ -s "$KDIR/arch/arm64/boot/Image" ]]
[[ -x "$ROOTFS_STAGING/bin/busybox" ]]
[[ -s "$SCRIPT_DIR/sched_lab.ko" ]]
release="$(cat "$KDIR/include/config/kernel.release")"
vermagic="$(modinfo -F vermagic "$SCRIPT_DIR/sched_lab.ko")"
[[ "${vermagic%% *}" == "$release" ]] || {
	printf 'module/kernel release mismatch: %s vs %s\n' "$vermagic" "$release" >&2
	exit 1
}
file "$SCRIPT_DIR/sched_lab.ko" | grep -q 'ARM aarch64'

# Keep each run, including failures; only the disposable rootfs is cleaned up.
mkdir -p "$REPO_ROOT/artifacts/A02"
RESULT_DIR="$(mktemp -d "$REPO_ROOT/artifacts/A02/run.XXXXXX")"
printf 'A02 evidence directory: %s\n' "$RESULT_DIR"
{
	printf 'kernel_release=%s\nmodule_vermagic=%s\n' "$release" "$vermagic"
	git -C "$REPO_ROOT" rev-parse HEAD
	git -C "$REPO_ROOT" status --short
	"$QEMU_BIN" --version | head -1
	sha256sum "$KDIR/arch/arm64/boot/Image" "$KDIR/vmlinux" "$KDIR/.config" \
		"$SCRIPT_DIR/sched_lab.ko" "$SCRIPT_DIR/sched_lab.c" \
		"$SCRIPT_DIR/validate-init.sh" "$SCRIPT_DIR/check-output.py" \
		"$ROOTFS_STAGING/bin/busybox"
} > "$RESULT_DIR/manifest.txt"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/a02-qemu.XXXXXX")"
cleanup() {
	case "$TEMP_DIR" in
		"${TMPDIR:-/tmp}"/a02-qemu.*) rm -rf -- "$TEMP_DIR" ;;
		*) printf 'refusing to remove unexpected path: %s\n' "$TEMP_DIR" >&2 ;;
	esac
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR/rootfs"
cp -a "$ROOTFS_STAGING/." "$TEMP_DIR/rootfs/"
cp "$SCRIPT_DIR/sched_lab.ko" "$TEMP_DIR/rootfs/sched_lab.ko"
cp "$SCRIPT_DIR/validate-init.sh" "$TEMP_DIR/rootfs/init"
chmod 0755 "$TEMP_DIR/rootfs/init"

(
	cd "$TEMP_DIR/rootfs"
	find . -print0 | cpio --null -o --format=newc 2>/dev/null |
		gzip -9 > "$TEMP_DIR/a02-initramfs.cpio.gz"
)

set +e
timeout --kill-after=5s "$QEMU_TIMEOUT" "$QEMU_BIN" \
	-machine virt \
	-cpu cortex-a57 \
	-smp 2 \
	-m 1024M \
	-kernel "$KDIR/arch/arm64/boot/Image" \
	-initrd "$TEMP_DIR/a02-initramfs.cpio.gz" \
	-append 'console=ttyAMA0 rdinit=/init nokaslr loglevel=8' \
	-nographic \
	-no-reboot < /dev/null 2>&1 | tee "$RESULT_DIR/qemu.log"
pipeline_status=("${PIPESTATUS[@]}")
set -e

if [[ "${pipeline_status[0]}" -ne 0 || "${pipeline_status[1]}" -ne 0 ]]; then
	printf 'QEMU/tee failed (timeout is a failure): %s; evidence: %s\n' \
		"${pipeline_status[*]}" "$RESULT_DIR" >&2
	exit 1
fi

python3 "$SCRIPT_DIR/check-output.py" "$RESULT_DIR/qemu.log"
printf 'A02_QEMU_VALIDATION=PASS\n'
