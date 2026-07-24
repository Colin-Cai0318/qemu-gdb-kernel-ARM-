// SPDX-License-Identifier: GPL-2.0
#include <linux/init.h>
#include <linux/jiffies.h>
#include <linux/module.h>
#include <linux/sched.h>

static bool fail_init;
module_param(fail_init, bool, 0644);
MODULE_PARM_DESC(fail_init, "Return -EINVAL from module_init when true");

static int __init hello_lab_init(void)
{
	pr_info("hello_lab: init comm=%s pid=%d jiffies=%lu fail_init=%d\n",
		current->comm, current->pid, jiffies, fail_init);

	if (fail_init)
		return -EINVAL;

	return 0;
}

static void __exit hello_lab_exit(void)
{
	pr_info("hello_lab: exit comm=%s pid=%d jiffies=%lu\n",
		current->comm, current->pid, jiffies);
}

module_init(hello_lab_init);
module_exit(hello_lab_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("ARM64 kernel lab");
MODULE_DESCRIPTION("A01 module lifecycle and failure-path experiment");
