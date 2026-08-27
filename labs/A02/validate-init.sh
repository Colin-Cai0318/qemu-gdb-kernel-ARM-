#!/bin/sh
set -eu

mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true

echo A02_RUNTIME_BEGIN
insmod /sched_lab.ko sleep_ms=10
test -e /proc/a02_wakeup

echo one > /proc/a02_wakeup
echo two > /proc/a02_wakeup
sleep 1

grep -q '^handled=2$' /proc/a02_wakeup
grep '^worker_' /proc/a02_wakeup
grep '^handled=' /proc/a02_wakeup

if test -d /sys/kernel/tracing/events/sched/sched_switch; then
	echo 0 > /sys/kernel/tracing/tracing_on
	echo > /sys/kernel/tracing/trace
	echo 1 > /sys/kernel/tracing/events/sched/sched_waking/enable
	echo 1 > /sys/kernel/tracing/events/sched/sched_wakeup/enable
	echo 1 > /sys/kernel/tracing/events/sched/sched_switch/enable
	echo 1 > /sys/kernel/tracing/tracing_on
	echo trace > /proc/a02_wakeup
	sleep 1
	echo 0 > /sys/kernel/tracing/tracing_on
	grep -q 'a02_worker' /sys/kernel/tracing/trace
	echo 0 > /sys/kernel/tracing/events/sched/sched_waking/enable
	echo 0 > /sys/kernel/tracing/events/sched/sched_wakeup/enable
	echo 0 > /sys/kernel/tracing/events/sched/sched_switch/enable
	echo A02_TRACEPOINT_PASS
else
	echo A02_TRACEPOINT_UNAVAILABLE
fi

rmmod sched_lab
test ! -e /proc/a02_wakeup
dmesg | grep sched_lab | tail -20
echo A02_RUNTIME_PASS
sync
poweroff -f
