#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KDIR="${KDIR:?set KDIR to the built ARM64 kernel tree}"
ROOTFS_STAGING="${ROOTFS_STAGING:?set ROOTFS_STAGING to a BusyBox rootfs directory}"
QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"

[[ -s "$KDIR/arch/arm64/boot/Image" ]]
[[ -x "$ROOTFS_STAGING/bin/busybox" ]]
[[ -s "$SCRIPT_DIR/sched_lab.ko" ]]

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
timeout 45s "$QEMU_BIN" \
	-machine virt \
	-cpu cortex-a57 \
	-smp 2 \
	-m 1024M \
	-kernel "$KDIR/arch/arm64/boot/Image" \
	-initrd "$TEMP_DIR/a02-initramfs.cpio.gz" \
	-append 'console=ttyAMA0 rdinit=/init nokaslr loglevel=8' \
	-nographic \
	-no-reboot < /dev/null 2>&1 | tee "$TEMP_DIR/qemu.log"
qemu_status="${PIPESTATUS[0]}"
set -e

if [[ "$qemu_status" -ne 0 && "$qemu_status" -ne 124 ]]; then
	printf 'unexpected qemu exit status: %s\n' "$qemu_status" >&2
	exit "$qemu_status"
fi

grep -q 'A02_RUNTIME_PASS' "$TEMP_DIR/qemu.log"
grep -q 'A02_TRACEPOINT_PASS' "$TEMP_DIR/qemu.log"
printf 'A02_QEMU_VALIDATION=PASS\n'
