# A02：内核线程、等待队列与调度观测

本实验把“进程上下文可以睡眠”变成可观测的运行时证据。模块创建 `a02_worker`
内核线程；线程在等待队列上睡眠，向 `/proc/a02_wakeup` 写入一次会排队一个事件并
唤醒它。通过日志和调度 tracepoint 观察生产者、等待者、唤醒与切换。

## 学习目标

- 区分用户进程进入内核的进程上下文、内核线程和中断上下文。
- 解释 `kthread_run()`、`kthread_should_stop()`、`kthread_stop()` 的生命周期。
- 解释 `wait_event_interruptible()` 为什么必须带条件，以及条件与 `wake_up_interruptible()` 的关系。
- 通过 `sched_waking`、`sched_wakeup`、`sched_switch` 还原一次睡眠/唤醒链。
- 说明卸载时为什么必须先阻止新生产者，再同步停止线程。

## 理论与源码导航

阅读 Linux Kernel Labs 的 deferred work/kernel threads 内容，并在当前内核源码中定位：

```bash
cd "$KDIR"
rg -n 'kthread_run|kthread_stop|kthread_should_stop' include/linux/kthread.h kernel/kthread.c
rg -n '#define wait_event_interruptible|___wait_event' include/linux/wait.h
rg -n '__wake_up\(' kernel/sched/wait.c
rg -n 'trace_sched_(waking|wakeup|switch)' kernel/sched
```

回答以下问题时，每题至少引用一个源码符号或动态证据：

1. `insmod` 的模块 init 与 `a02_worker` 都在进程上下文，它们的 `current` 为什么不同？
2. 为什么只调用 `wake_up_interruptible()` 不能替代等待条件？
3. `atomic_xchg(&pending, 0)` 如何避免一次唤醒只处理一个事件时的丢失或重复？
4. `kthread_stop()` 返回前保证了什么？为什么这关系到模块代码的生命周期？
5. `wait_event_interruptible_timeout()` 在这里可以睡眠，而在硬中断处理函数中通常不合法，依据是什么？

## 构建

```bash
export LAB_REPO=$PWD
export KDIR=$LAB_REPO/kernel/sourceCode
make -C labs/A02
file labs/A02/sched_lab.ko
modinfo labs/A02/sched_lab.ko
```

确认模块为 AArch64，且 `vermagic` 与本次运行内核一致。

## Guest 正常路径

```sh
insmod /mnt/labs/A02/sched_lab.ko sleep_ms=20
cat /proc/a02_wakeup
echo one > /proc/a02_wakeup
echo two > /proc/a02_wakeup
sleep 1
cat /proc/a02_wakeup
dmesg | grep sched_lab
```

应看到写入者通常是 `sh`，处理者始终是 `a02_worker`，并且 `handled` 增加。

## 调度 tracepoint

```sh
mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true
cd /sys/kernel/tracing
echo 0 > tracing_on
echo global > trace_clock
echo > trace
echo 1 > events/sched/sched_waking/enable
echo 1 > events/sched/sched_wakeup/enable
echo 1 > events/sched/sched_switch/enable
echo 1 > tracing_on
echo trace > /proc/a02_wakeup
sleep 1
echo 0 > tracing_on
grep -E 'a02_worker|sched_lab' trace
```

报告中按时间顺序标注：谁写入、谁唤醒 `a02_worker`、线程何时切换到运行态、何时
再次睡眠。若 tracefs 未启用，记录错误和当前内核配置，不要伪造结果。

## 清理与卸载路径

```sh
cd /sys/kernel/tracing
echo 0 > events/sched/sched_waking/enable
echo 0 > events/sched/sched_wakeup/enable
echo 0 > events/sched/sched_switch/enable
cd /
rmmod sched_lab
test ! -e /proc/a02_wakeup
dmesg | grep sched_lab | tail -20
```

使用较长工作时间再卸载，验证 `kthread_stop()` 会同步等待线程退出：

```sh
insmod /mnt/labs/A02/sched_lab.ko sleep_ms=1000
echo slow > /proc/a02_wakeup
time rmmod sched_lab
dmesg | grep sched_lab | tail -20
```

`sleep_ms` 在初始化时限制为最多 1000 ms，运行期间只读，proc 与 sysfs 展示相同的
有效值。线程处理每个事件前检查停止请求，等待中也以停止标志为条件。
卸载采用取消语义：未处理的 pending/batch 事件可以丢弃；`handled` 表示已经开始处理
的事件数，并不承诺退出时等于写入次数。

Linux 6.12 的 `kthread_stop()` 会设置 `TIF_NOTIFY_SIGNAL` 并唤醒目标，因此不要把
`time rmmod` 的耗时预设为 `sleep_ms`。应同时观察停止前后的计数与调用顺序。

## 验收证据

- [ ] 内核 release、Git commit、`.config` 与模块 `vermagic` 属于同一构建链。
- [ ] 给出五个理论问题的源码/运行时证据。
- [ ] 正常路径中 `pending`、`handled` 与日志顺序一致。
- [ ] trace 中能解释至少一次 waking/wakeup/switch 链。
- [ ] 卸载日志显示 `worker-stop` 发生在 `unloaded` 前，proc 节点已移除。
- [ ] tracing 开关被恢复，模块已卸载。

`validate-init.sh` 在临时 initramfs 中验证正常 3 个事件、实际目标 PID 的调度链、
33 个积压事件的取消、5 秒内卸载、空闲卸载、参数上限和 proc/线程清理。
宿主机 `check-output.py` 再检查原始 trace、3 轮生命周期、计数和内核警告。
只有客户机证据完整且 QEMU 正常退出才输出 `A02_QEMU_VALIDATION=PASS`；超时总是失败。

仓库提供对应的宿主机入口，参数必须指向同一次 Linux 6.12 ARM64 构建和一个可用的
BusyBox rootfs staging 目录：

```bash
KDIR=/path/to/kernel/source \
ROOTFS_STAGING=/path/to/rootfs/staging \
./labs/A02/validate-qemu.sh
```

每次运行的 `manifest.txt` 和 `qemu.log` 保存在 `artifacts/A02/run.*`，包含源码、模块、
Image、配置和 BusyBox 哈希。这些本地证据不上传 GitHub。版本字符串相同不代表构建
相同，复盘时还需对照指纹与启动日志。失败时也保留结果，临时 rootfs 会自动清理。

仅检查验收器本身（包含伪造 PASS、缺事件、错误 PID、超时和版本不匹配反例）：

```bash
python3 -m unittest discover -s tests -v
```

CI 只运行静态检查与反例测试，真实内核运行仍需以上 QEMU 回归。
源码依据：[Linux 6.12 kthread/wait 文档](https://docs.kernel.org/6.12/driver-api/basics.html)。
