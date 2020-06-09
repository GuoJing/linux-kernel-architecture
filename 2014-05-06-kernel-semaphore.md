---
layout:    post
title:     内核信号量
category:  内核同步
description: 内核信号量...
tags: 内核信号量 信号量
---
内核信号量类似于自旋锁，因为当锁关闭着，它不允许内核控制路径继续执行，然而，当内核控制路径试图获取内核信号量所保护的忙资源时，相应的进程被挂起，只有在资源被释放时，进程才再次变为可运行状态。因此，只有可以睡眠的函数才能获取内核信号量，中断处理程序和可延迟函数都不能使用内核信号量。

内核信号量是*semaphore*类型的对象，代码如下：

#### <include/linux/semaphore.h> ####

{% highlight c++ %}
struct semaphore {
    spinlock_t        lock;
    unsigned int      count;
    struct list_head  wait_list;
};
{% endhighlight %}

其中字段及其意义如下：

字段                  | 说明
------------          | -------------
count                 | 计数器，如果该值大于0，那么资源就是空闲的，也就是说该资源可以被使用，相反，如果count等于0，那么信号量是忙的。如果count的值等于负数，则资源是不可用的
lock                  | 信号量的锁
wait_list             | 存放等待队列链表的地址，当前等待资源的所有睡眠进程都放在这个列表中，如果count大于0，那么等待队列就为空

#### <include/linux/semaphore.h> ####

{% highlight c++ %}
#define init_MUTEX(sem)         sema_init(sem, 1)
#define init_MUTEX_LOCKED(sem)  sema_init(sem, 0)
{% endhighlight %}

可以使用*init_MUTEX()*和*init_MUTEX_LOCKED()*宏来初始化互斥访问所需的信号量，这两个宏分别把*count*的值设置为1和0.其中1表示互斥访问的资源空闲，0表示对信号量进行初始化的进程当前互斥访问的资源忙。宏*DECLARE_MUTEX*用于静态的分配*semaphore*结构的变量。

#### <include/linux/semaphore.h> ####

{% highlight c++ %}
#define DECLARE_MUTEX(name)
    struct semaphore name = __SEMAPHORE_INITIALIZER(name, 1)
{% endhighlight %}