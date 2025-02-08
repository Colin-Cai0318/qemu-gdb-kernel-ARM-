#include <linux/module.h>   // 所有模块都需要这个头文件
#include <linux/kernel.h>   // KERN_INFO

// 模块的许可证声明
MODULE_LICENSE("GPL");

// 模块的作者
MODULE_AUTHOR("caizhipeng");

// 描述模块
MODULE_DESCRIPTION("A simple Linux module");

// 模块的版本
MODULE_VERSION("0.1");

// 初始化函数
static int __init hello_start(void)
{
    printk(KERN_INFO "Loading hello module...\n");
    return 0;    // 非零返回值将导致模块加载失败
}

// 清理函数
static void __exit hello_end(void)
{
    printk(KERN_INFO "Goodbye, hello module!\n");
}

module_init(hello_start);
module_exit(hello_end);
