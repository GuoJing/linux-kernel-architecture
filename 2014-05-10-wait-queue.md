---
layout:    post
title:     等待队列
category:  进程
description: 等待队列
tags: 等待队列
---
等待队列（*wait queue*）用于使进程等待某一特定的事件发生而无需频繁的轮询，进程在等待期间睡眠，在某件事发生时由内核自动唤醒。

### 数据结构 ###

每个等待队列都有一个队列的头，我们可以看看等待队列的代码：

#### <linux/wait.h> ####

{% highlight c++ %}
struct __wait_queue_head {
    spinlock_t lock;
    struct list_head task_list;
};
typedef struct __wait_queue_head wait_queue_head_t;
{% endhighlight %}

因为等待队列也可以在中断的时候修改，在操作队列之前必须获得一个自旋锁，*task_list*是一个双链表，用于实现双联表最擅长表示的结构，就是队列：

#### <linux/wait.h> ####

{% highlight c++ %}
struct __wait_queue {
    unsigned int flags;
#define WQ_FLAG_EXCLUSIVE   0x01
    void *private;
    wait_queue_func_t func;
    struct list_head task_list;
};
{% endhighlight %}

我们可以看到链表*__wait_queue*中的各个字段，其字段意义如下：

字段                  | 说明
------------          | -------------
flags                 | 为WQ\_FLAG\_EXCUSIVE或为0，WQ\_FLAG\_EXCUSIVE表示等待进程想要被独占地唤醒
private               | 是一个指针，指向等待进程的task\_struct实例，这个变量本质上可以指向任意的私有数据
func                  | 等待唤醒进程
task_list             | 用作一个链表元素，用于将wait\_queue\_t实例防止到等待队列中

为了使当前进程在一个等待队列中睡眠，需要调用*wait_event*函数。进程进入睡眠，将控制权释放给调度器。内核通常会在向块设备发出传输数据的请求后调用这个函数，因为传输不会立即发送，而在此期间又没有其他事情可做，所以进程就可以进入睡眠，将CPU时间交给系统中的其他进程。

在内核中的另一处，例如，来自块设备的数据到达后，必须调用*wake_up*函数来唤醒等待队列中的睡眠进程。在使用*wait_event*让进程睡眠后，必须确保在内核的另一块一定有一个对应的*wake_up*调用，这是必须的，否则睡眠的进程永远无法醒来。

### 进程睡眠 ###

*add_wait_queue*函数用于将一个进程增加到等待队列，这个函数必须要获得自旋锁，在获得自旋锁之后，将工作委托给*__add_wait_queue*。

#### <linux/wait.h> ####

{% highlight c++ %}
static inline void __add_wait_queue(
    wait_queue_head_t *head,
    wait_queue_t *new)
{
    list_add(&new->task_list, &head->task_list);
}
{% endhighlight %}

在将新进程统计到等待队列的时候，除了使用*list_add*函数并没有其他的工作要做，内核还提供了*add_wait_queue_exclusive*函数，它的工作方式和这个函数相同，但是将进程插入到链表的尾部，并将其设置为*WQ_EXCLUSIVE*标志。

让进程在等待队列上进入睡眠的另一种方法是*prepare_to_wait*，在这个函数中还需要进程的状态，代码如下：

#### <kernel/wait.c> ####

{% highlight c++ %}
void
prepare_to_wait(wait_queue_head_t *q, wait_queue_t *wait, int state)
{
    unsigned long flags;
    /* 将进程添加到等待队列的尾部
     * 这种实现确保在混合访问类型的队列中
     * 首先唤醒所有的普通进程
     * 然后才考虑到对内核堆栈进程的限制
     */
    wait->flags &= ~WQ_FLAG_EXCLUSIVE;
    // 创建一个自旋锁
    spin_lock_irqsave(&q->lock, flags);
    if (list_empty(&wait->task_list))
        // 添加到链表中
        __add_wait_queue(q, wait);
    set_current_state(state);
    // 解锁一个自旋锁
    spin_unlock_irqrestore(&q->lock, flags);
}
EXPORT_SYMBOL(prepare_to_wait);
{% endhighlight %}

除了将进程休眠添加到队列里中，内核提供了两个标准方法可用于初始化一个动态分配的*wait_queue_t*实例，分别为*init_waitqueue_entry*和宏*DEFINE_WAIT*。

#### <linux/wait.h> ####

{% highlight c++ %}
static inline void init_waitqueue_entry(
    wait_queue_t *q,
    struct task_struct *p)
{
    q->flags = 0;
    q->private = p;
    q->func = default_wake_function;
}
{% endhighlight %}

*default_wake_function*只是一个进行参数转换的前端，然后使用*try_to_wake_up*函数来唤醒进程。

宏*DEFINE_WAIT*创建*wait_queue_t*的静态实例：

#### <linux/wait.h> ####

{% highlight c++ %}
#define DEFINE_WAIT_FUNC(name, function)
    wait_queue_t name = {
        .private    = current,
        .func       = function,
        .task_list  = LIST_HEAD_INIT((name).task_list),
    }

#define DEFINE_WAIT(name) \
    DEFINE_WAIT_FUNC(name, autoremove_wake_function)
{% endhighlight %}

这里用*autoremove_wake_function*来唤醒进程，这个函数不仅调用*default_waike_function*将所述等待队列从等待队列删除。*add_wait_queue*通常不直接使用，我们更经常使用*wait_event*，这是一个宏，代码如下：

#### <linux/wait.h> ####

{% highlight c++ %}
#define wait_event(wq, condition)
do {
    if (condition)
        break;
    __wait_event(wq, condition);
} while (0)
{% endhighlight %}

这个宏等待一个条件，会确认这个条件是否满足，如果条件已经满足，就可以立即停止处理，因为没有什么可以继续等待的了，然后将工作交给*__wait_event*。

#### <linux/wait.h> ####

{% highlight c++ %}
#define __wait_event(wq, condition)
do {
    DEFINE_WAIT(__wait);
    for (;;) {
        prepare_to_wait(&wq, &__wait, TASK_UNINTERRUPTIBLE);
        if (condition)
            break;
        schedule();
    }
    finish_wait(&wq, &__wait);
} while (0)
{% endhighlight %}

使用*DEFINE_WAIT*建立等待队列的成员之后，这个宏产生一个无限循环。使用*prepare_to_wait*使进程在等待队列上睡眠。每次进程被唤醒时，内核都会检查指定的条件是否满足，如果条件满足，就退出无线循环，否则将控制权交给调度器，进程再次睡眠。

在条件满足时，*finish_wait*将进程状态设置回*TASK_RUNNING*，并从等待队列的链表移除对应项。

除了*wait_event*之外，内核还定义了其他几个函数，可以将当前进程置于等待队列中，实现等同于*sleep_on*。

#### <linux/wait.h> ####

{% highlight c++ %}
#define wait_event_interruptible(
    wq, condition)
({
    int __ret = 0;
    if (!(condition))
        __wait_event_interruptible(
            wq, condition, __ret
        );
    __ret;
})
{% endhighlight %}

*wait_event_interruptible*使用的进程状态为*TASK_INTERRUPTIBLE*，因而睡眠进程可以通过接收信号而唤醒。

#### <linux/wait.h> ####

{% highlight c++ %}
#define wait_event_interruptible_timeout(
    wq, condition, timeout)
({
    long __ret = timeout;
    if (!(condition))
        __wait_event_interruptible_timeout(
            wq, condition, __ret
        );
    __ret;
})
{% endhighlight %}

*wait_event_interruptible_timeout*让进程睡眠，但可以通过接受信号唤醒，它注册了一个超时限制。

#### <linux/wait.h> ####

{% highlight c++ %}
#define wait_event_timeout(wq, condition, timeout)
({
    long __ret = timeout;
    if (!(condition))
        __wait_event_timeout(
            wq, condition, __ret
        );
    __ret;
})
{% endhighlight %}

*wait_event_timeout*等待满足指定的条件，但如果等待时间超过了指定的超时限制，那么就停止，这防止了永远睡眠的情况。

### 唤醒进程 ###

唤醒进程的过程比较简单，内核定义了一些列的宏用户唤醒进程。

#### <linux/wait.h> ####

{% highlight c++ %}
#define wake_up_poll(x, m)
    __wake_up(x, TASK_NORMAL, 1, (void *) (m))

#define wake_up_locked_poll(x, m)
    __wake_up_locked_key((x), TASK_NORMAL, (void *) (m))

#define wake_up_interruptible_poll(x, m)
    __wake_up(x, TASK_INTERRUPTIBLE, 1, (void *) (m))

#define wake_up_interruptible_sync_poll(x, m)
    __wake_up_sync_key((x), TASK_INTERRUPTIBLE, 1, (void *) (m))
{% endhighlight %}

在获得了用户保护等待队列首部的锁之后，*_wake_up*将工作委托给*_wake_up_common*，代码如下：

#### <linux/wait.h> ####

{% highlight c++ %}
static void __wake_up_common(
    wait_queue_head_t *q, unsigned int mode,
    int nr_exclusive, int wake_flags, void *key)
{
    wait_queue_t *curr, *next;
    // 反复扫描链表，直到没有更多需要唤醒的进程
    list_for_each_entry_safe(curr, next, &q->task_list, task_list) {
        unsigned flags = curr->flags;

        if (curr->func(curr, mode, wake_flags, key) &&
                (flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
                /* 检查唤醒进程的数目是否达到了nr_exclusive
                 * 避免所谓的惊群问题
                 * 如果几个进程在等待独占访问某一资源
                 * 那么同时唤醒所有的等进程时没有意义的
                 * 因为除了其中的一个进程之外
                 * 其他的进程都会再次进入睡眠
                 */
            break;
    }
}
{% endhighlight %}

*q*用于选定等待队列，而*mode*指定进程的状态，用于控制唤醒进程的条件，*nr_exclusive*表示将要唤醒的设置了*WQ_FLAG_EXCLUSIVE*标志的进程的数目。从上面的注释可以看出*nr_exclusive*是非常有用的，这个数字表示检查唤醒进程的数目是否达到了nr_exclusive，从而避免所谓的惊群的问题。

惊群问题是，当需要唤醒进程的时候，不需要将所有等待某一资源的进程全部唤醒，因为即便全部唤醒，也只能有一个进程需要唤醒，而其他的进程都要再次进入睡眠，这是非常浪费资源的，更不要说每次进程唤醒都会出现这样的问题。

但并不是说所有的进程都不能同时被唤醒，如果进程在等待的数据传输结束，那么唤醒等待队列中的所有进程是可行的，因为这几个进程的数据可以同时读取而不会被干扰。
