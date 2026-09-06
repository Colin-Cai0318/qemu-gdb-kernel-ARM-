// SPDX-License-Identifier: GPL-2.0
#include <linux/atomic.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/sched.h>
#include <linux/seq_file.h>
#include <linux/wait.h>

#define A02_PROC_NAME "a02_wakeup"

static DECLARE_WAIT_QUEUE_HEAD(event_wq);
static atomic_t pending = ATOMIC_INIT(0);
static atomic64_t handled = ATOMIC64_INIT(0);
static struct task_struct *worker;
static struct proc_dir_entry *proc_entry;

static unsigned int sleep_ms = 20;
module_param(sleep_ms, uint, 0444);
MODULE_PARM_DESC(sleep_ms, "Per-event sleep in the worker (0..1000 ms)");

static int a02_worker(void *unused)
{
	pr_info("sched_lab: worker-start pid=%d comm=%s\n",
		current->pid, current->comm);

	while (!kthread_should_stop()) {
		int batch;
		int ret;

		ret = wait_event_interruptible(event_wq,
					       kthread_should_stop() ||
					       atomic_read(&pending) > 0);
		if (ret)
			continue;
		if (kthread_should_stop())
			break;

		batch = atomic_xchg(&pending, 0);
		while (batch-- > 0) {
			/* Unload cancels the remaining batch; it does not drain it. */
			if (kthread_should_stop())
				break;
			atomic64_inc(&handled);
			pr_info("sched_lab: handle seq=%lld pid=%d comm=%s\n",
				(long long)atomic64_read(&handled),
				current->pid, current->comm);
			if (sleep_ms)
				wait_event_interruptible_timeout(event_wq,
								 kthread_should_stop(),
								 msecs_to_jiffies(sleep_ms));
			cond_resched();
		}
	}

	pr_info("sched_lab: worker-stop handled=%lld pid=%d comm=%s\n",
		(long long)atomic64_read(&handled), current->pid, current->comm);
	return 0;
}

static int a02_status_show(struct seq_file *m, void *v)
{
	char comm[TASK_COMM_LEN] = "stopped";
	int pid = -1;

	if (worker) {
		get_task_comm(comm, worker);
		pid = task_pid_nr(worker);
	}

	seq_printf(m, "worker_pid=%d\n", pid);
	seq_printf(m, "worker_comm=%s\n", comm);
	seq_printf(m, "pending=%d\n", atomic_read(&pending));
	seq_printf(m, "handled=%lld\n", (long long)atomic64_read(&handled));
	seq_printf(m, "sleep_ms=%u\n", sleep_ms);
	return 0;
}

static int a02_status_open(struct inode *inode, struct file *file)
{
	return single_open(file, a02_status_show, NULL);
}

static ssize_t a02_wakeup_write(struct file *file, const char __user *buf,
				size_t count, loff_t *ppos)
{
	int queued;

	if (!count)
		return 0;

	queued = atomic_inc_return(&pending);
	pr_info("sched_lab: queue producer_pid=%d producer_comm=%s pending=%d\n",
		current->pid, current->comm, queued);
	wake_up_interruptible(&event_wq);
	return count;
}

static const struct proc_ops a02_proc_ops = {
	.proc_open = a02_status_open,
	.proc_read = seq_read,
	.proc_write = a02_wakeup_write,
	.proc_lseek = seq_lseek,
	.proc_release = single_release,
};

static int __init sched_lab_init(void)
{
	sleep_ms = min(sleep_ms, 1000U);
	worker = kthread_run(a02_worker, NULL, "a02_worker");
	if (IS_ERR(worker)) {
		int ret = PTR_ERR(worker);

		worker = NULL;
		return ret;
	}

	/* Publish the reader-visible task pointer only after creation succeeds. */
	proc_entry = proc_create(A02_PROC_NAME, 0600, NULL, &a02_proc_ops);
	if (!proc_entry) {
		kthread_stop(worker);
		worker = NULL;
		return -ENOMEM;
	}

	pr_info("sched_lab: loaded producer_pid=%d producer_comm=%s\n",
		current->pid, current->comm);
	return 0;
}

static void __exit sched_lab_exit(void)
{
	proc_remove(proc_entry);
	proc_entry = NULL;

	if (worker) {
		kthread_stop(worker);
		worker = NULL;
	}

	pr_info("sched_lab: unloaded pid=%d comm=%s\n",
		current->pid, current->comm);
}

module_init(sched_lab_init);
module_exit(sched_lab_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("ARM64 kernel lab");
MODULE_DESCRIPTION("A02 kthread, wait queue, wakeup and scheduling lab");
