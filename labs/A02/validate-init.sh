#!/bin/sh
set -eu
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

finish() {
	status=$?
	trap - EXIT
	if test "$status" -ne 0; then
		echo "A02_RUNTIME_FAIL status=$status"
	fi
	sync
	poweroff -f
}
trap finish EXIT

wait_handled() {
	wanted=$1
	tries=0
	while ! grep -q "^handled=$wanted$" /proc/a02_wakeup; do
		tries=$((tries + 1))
		test "$tries" -lt 100 || return 1
		sleep 0.1
	done
}

wait_sleeping() {
	# Ensure this is a real wait-queue wakeup, not just an already-running task.
	tries=0
	while ! grep -q 'State:.*S (sleeping)' "/proc/$worker_pid/status"; do
		tries=$((tries + 1))
		test "$tries" -lt 100 || return 1
		sleep 0.1
	done
}

mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true

echo A02_RUNTIME_BEGIN
uname -r
insmod /sched_lab.ko sleep_ms=0
test -e /proc/a02_wakeup
worker_pid=$(sed -n 's/^worker_pid=//p' /proc/a02_wakeup)
echo "A02_WORKER_PID=$worker_pid"

echo one > /proc/a02_wakeup
echo two > /proc/a02_wakeup
wait_handled 2
wait_sleeping

grep -q '^handled=2$' /proc/a02_wakeup
grep '^worker_' /proc/a02_wakeup
grep '^handled=' /proc/a02_wakeup

if test -d /sys/kernel/tracing/events/sched/sched_switch; then
	echo 0 > /sys/kernel/tracing/tracing_on
	echo global > /sys/kernel/tracing/trace_clock
	echo > /sys/kernel/tracing/trace
	echo 1 > /sys/kernel/tracing/events/sched/sched_waking/enable
	echo 1 > /sys/kernel/tracing/events/sched/sched_wakeup/enable
	echo 1 > /sys/kernel/tracing/events/sched/sched_switch/enable
	echo 1 > /sys/kernel/tracing/tracing_on
	echo trace > /proc/a02_wakeup
	sleep 1
	echo 0 > /sys/kernel/tracing/tracing_on
	wait_handled 3
	echo A02_TRACE_BEGIN
	grep 'a02_worker' /sys/kernel/tracing/trace
	echo A02_TRACE_END
	echo 0 > /sys/kernel/tracing/events/sched/sched_waking/enable
	echo 0 > /sys/kernel/tracing/events/sched/sched_wakeup/enable
	echo 0 > /sys/kernel/tracing/events/sched/sched_switch/enable
	echo A02_TRACEPOINT_PASS
else
	echo A02_TRACEPOINT_UNAVAILABLE
	exit 1
fi

rmmod sched_lab
test ! -e /proc/a02_wakeup
test ! -d "/proc/$worker_pid"
echo A02_CLEANUP_PASS

# Force a multi-event batch while the worker is sleeping. Unload must cancel
# the remaining batch; the timeout also guards against stop/wakeup regressions.
insmod /sched_lab.ko sleep_ms=1000
echo first > /proc/a02_wakeup
wait_handled 1
i=0
while test "$i" -lt 32; do
	echo backlog > /proc/a02_wakeup
	i=$((i + 1))
done
wait_handled 2
cat /proc/a02_wakeup
worker_pid=$(sed -n 's/^worker_pid=//p' /proc/a02_wakeup)
echo A02_STOP_BEGIN
timeout 5 /bin/busybox rmmod sched_lab
test ! -e /proc/a02_wakeup
test ! -d "/proc/$worker_pid"
stopped_count=$(dmesg | sed -n 's/.*worker-stop handled=\([0-9]*\).*/\1/p' | tail -1)
test "$stopped_count" -ge 2
test "$stopped_count" -lt 33
echo A02_BOUNDED_STOP_PASS

# Idle unload and parameter clamping are separate lifecycle cases.
insmod /sched_lab.ko sleep_ms=5000
grep -q '^sleep_ms=1000$' /proc/a02_wakeup
worker_pid=$(sed -n 's/^worker_pid=//p' /proc/a02_wakeup)
wait_sleeping
rmmod sched_lab
test ! -e /proc/a02_wakeup
test ! -d "/proc/$worker_pid"
echo A02_IDLE_STOP_PASS

# Read once at the end: no duplicated lifecycle lines from earlier dmesg reads.
echo A02_DMESG_BEGIN
dmesg
echo A02_DMESG_END
echo A02_RUNTIME_PASS
