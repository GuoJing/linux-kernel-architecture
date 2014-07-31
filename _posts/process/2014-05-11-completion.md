---
layout:    post
title:     完成量
category:  进程
description: 完成量...
tags: 完成量
---
完成量（*completion*）机制基于等待队列，内核利用这个机制等待某一个操作结束，这两种机制使用得都比较频繁，主要用于设备的驱动程序。完成量与信号量有些相似，但完成量是基于等待队列实现的。

我们只感兴趣完成量的接口。在场景中有两个参与者，一个在等待某操作的完成，而另一个在操作完成时发出声明，实际上，这已经被简化过了。实际上，可以有任意数目的进程等待操作完成，为表示进程等待的即将完成的『某操作』，内核使用了*complietion*数据结构，代码如下：

#### <kernel/completion.h> ####

{% highlight c++ %}
struct completion {
    unsigned int done;
    wait_queue_head_t wait;
};
{% endhighlight %}

我们可以看到*wait*变量是一个*wait_queue_head_t*结构体，是等待队列链表的头，*done*是一个计数器。每次调用*completion*时，该计数器就加1，仅当*done*等于0时，*wait_for*系列函数才会使调用进程进入睡眠。实际上，这意味着进程无需等待已经完成的事件。

其中*wait_queue_head_t*已经在等待队列中记录过了，代码如下：

#### <linux/wait.h> ####

{% highlight c++ %}
struct __wait_queue_head {
    spinlock_t lock;
    struct list_head task_list;
};
typedef struct __wait_queue_head wait_queue_head_t;
{% endhighlight %}

*init_completion()*函数用于初始化一个动态分配的*completion*实例，而*DECLARE_COMPLETION*宏用来建立该数据结构的静态实例。*init_completion()*函数代码如下：

#### <kernel/completion.h> ####

{% highlight c++ %}
static inline void init_completion(struct completion *x)
{
    x->done = 0;
    init_waitqueue_head(&x->wait);
}
{% endhighlight %}

从上面代码中可以看到，初始化完成量会将*done*字段初始化为0，并且初始化*wait*链表。进程可以用*wait_for_completion*添加到等待队列，进程在其中等待，并以独占睡眠状态直到请求被内核的某些部分处理，这些函数都需要一个*completion*实例：

#### <kernel/completion.h> ####

{% highlight c++ %}
extern void
wait_for_completion(
    struct completion *);

extern int
wait_for_completion_interruptible(
    struct completion *x);

extern int
wait_for_completion_killable(
    struct completion *x);

extern unsigned long
wait_for_completion_timeout(
    struct completion *x,
    unsigned long timeout);

extern unsigned long
wait_for_completion_interruptible_timeout(
        struct completion *x,
        unsigned long timeout);

extern bool
try_wait_for_completion(
    struct completion *x);

extern bool
completion_done(
    struct completion *x);

extern void
complete(
    struct completion *);

extern void
complete_all(
    struct completion *);
{% endhighlight %}

通常进程在等待事件的完成时处于不可中断状态，但如果使用*wait_for_completion_interruptible*可以改变这一设置，如果进程被中断，则函数返回*-ERESTARTSYS*，否则返回0.

*wait_for_completion_timeout*等待一个完成事件发送，但提供了超时的设置，如果等待时间超过了这一设置，则取消等待。这有助于防止无限等待某一时间，如果在超时之间就已经完成，函数就返回剩余时间，否则就返回0。

*wait_for_completion_interruptible_timeout*是前两种的结合体。

在请求由内核的另一部分处理之后，必须调用*complete*或者*complete_all*来唤醒等待的进程。因为每次调用只能从完成量的等待队列移除一个进程，对*n*个等待进程来说，必须调用函数*n*次。另一方面，*complete_all*会唤醒所有等待该完成的进程。

除此之外，还有*complete_and_exit*方法，该方法是一个小的包装起，首先调用*complete*，然后调用*do_exit*结束内核线程。

#### <kernel/exit.c> ####

{% highlight c++ %}
NORET_TYPE void complete_and_exit(
    struct completion *comp,
    long code)
{
    if (comp)
        complete(comp);

    do_exit(code);
}
{% endhighlight %}

在*completion*结构体中，*done*是一个计数器。*complete_all*的工作方式与之类似，但它会将计数器设置为最大的可能值，这样，在事件完成后调用*wait_for*系列函数的进程将永远不会睡眠。