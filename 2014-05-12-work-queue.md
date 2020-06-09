---
layout:    post
title:     工作队列
category:  中断和异常
description: 工作队列...
tags: 工作队列
---
在Linux2.6中引入了工作队列，用来代替早期的任务队列，它们允许内核函数被激活，而且稍后由一种叫做工作者线程（*worker thread*）的特殊内核线程来执行。

尽管可延迟函数和工作队列非常相似，但是它们的区别还是很大，主要的区别在于，可延迟函数运行在中断上下文中，而工作队列中的函数运行在进程上下文中。执行可租色函数的唯一方式是在进程上下文中运行，因为，正如[处理程序的嵌套执行](/linux-kernel-architecture/posts/loop-interrupt/)中提到的，在中断上下文中不可能发生进程切换。

可延迟函数和工作队列中的函数都不能访问进程的用户空间态的地址，实际上，可延迟函数执行时不能确定哪个进程正在运行，另一方面，工作队列中的函数是由内核线程来执行的，所以根本不存在它要访问的用户态地址空间。

### 数据结构 ###

与工作队列相关的主要数据结构是*workqueue_struct*，代码如下：

#### <kernel/workqueue.c> ####

{% highlight c++ %}
struct workqueue_struct {
    struct cpu_workqueue_struct *cpu_wq;
    struct list_head list;
    const char *name;
    int singlethread;
    int freezeable;     /* 检查挂起的时候是否能冻结进程 */
    int rt;
#ifdef CONFIG_LOCKDEP
    struct lockdep_map lockdep_map;
#endif
};
{% endhighlight %}

其中的*cpu_wq*是一个*cpu_workqueue_struct*结构体，代码如下：

#### <kernel/workqueue.c> ####

{% highlight c++ %}
struct cpu_workqueue_struct {

    spinlock_t lock;

    struct list_head worklist;
    wait_queue_head_t more_work;
    struct work_struct *current_work;

    struct workqueue_struct *wq;
    struct task_struct *thread;
} ____cacheline_aligned;
{% endhighlight %}

其中字段及其意义如下：

字段                  | 说明
------------          | -------------
lock                  | 保护该数据结构的自旋锁
worklist              | 挂起的链表的头结点
more_work             | 等待队列，其中的工作者线程因等待更多的工作而处于睡眠的状态
current_work          | 当前工作
wq                    | 指向*workqueue_struct*结构的指针，其中包含该描述符
thread                | 指向结构中工作者线程的进程描述符指针

*cpu_workqueue_struct*结构的*worklist*字段是一个双向链表的头，链表集中了工作队列中所有挂起函数。

#### <linux/include/workqueue.h> ####

{% highlight c++ %}
struct work_struct {
    atomic_long_t data;
#define WORK_STRUCT_PENDING 0
#define WORK_STRUCT_FLAG_MASK (3UL)
#define WORK_STRUCT_WQ_DATA_MASK (~WORK_STRUCT_FLAG_MASK)
    struct list_head entry;
    work_func_t func;
#ifdef CONFIG_LOCKDEP
    struct lockdep_map lockdep_map;
#endif
};
{% endhighlight %}

其中字段及其意义如下：

字段           | 说明
------------   | -------------
data           | 传递给挂起函数的参数，是一个指针
entry          | 指向挂起函数链表前一个或后一个元素的指针
func           | 挂起函数的地址

可以看到无论是*workqueue_struct*还是*work_struct*都有一个*lockdep_map*，*lockdep_map*用于映射被锁的对象的实例到锁的类。我们可以看看这个*lockdep_map*的代码：

#### <linux/include/lockdep.h> ####

{% highlight c++ %}
struct lockdep_map {
    struct lock_class_key   *key;
    struct lock_class       *class_cache;
    const char              *name;
#ifdef CONFIG_LOCK_STAT
    int                     cpu;
    unsigned long           ip;
#endif
};
{% endhighlight %}

### 创建工作队列 ###

创建工作队列使用宏*create_workqueue*，但*create_workqueue*宏只是另一个函数的快捷调用，初始化了一些参数而已，最终会使用*__create_workqueue*。

#### <linux/include/workqueue.h> ####

{% highlight c++ %}

#define create_workqueue(name) \
    __create_workqueue((name), 0, 0, 0)

#define create_rt_workqueue(name) \
    __create_workqueue((name), 0, 0, 1)

#define create_freezeable_workqueue(name) \
    __create_workqueue((name), 1, 1, 0)

#define create_singlethread_workqueue(name) \
    __create_workqueue((name), 1, 0, 0)
{% endhighlight %}

我们可以看到大多数的创建工作队列的函数最终都是使用同一个函数，只是参数不同而已。创建工作队列的函数接收一个字符串作为参数，返回新创建工作队列的*workqueue_struct*描述符地址。函数还创建*n*个工作者线程，并根据传递给函数的字符串为工作者线程命名，其中*n*是当前系统上正在运行的CPU的数量。

*create_singlethread_workqueue*只创建一个工作者线程，内核调用*destroy_workqueue()*函数撤销工作队列。

对于创建工作队列的核心代码逻辑，我们可以看如下代码：

#### <kernel/workqueue.c> ####

{% highlight c++ %}
struct workqueue_struct *__create_workqueue_key(
    const char *name,
    int singlethread,
    int freezeable,
    int rt,
    struct lock_class_key *key,
    const char *lock_name)
{
    struct workqueue_struct *wq;
    struct cpu_workqueue_struct *cwq;
    int err = 0, cpu;
    // 初始化申请工作队列内存（页框）
    wq = kzalloc(sizeof(*wq), GFP_KERNEL);
    if (!wq)
        return NULL;

    wq->cpu_wq = alloc_percpu(struct cpu_workqueue_struct);
    if (!wq->cpu_wq) {
        kfree(wq);
        return NULL;
    }
    // 通过name把工作队列的名字命名并初始化工作队列
    wq->name = name;
    lockdep_init_map(&wq->lockdep_map, lock_name, key, 0);
    wq->singlethread = singlethread;
    wq->freezeable = freezeable;
    wq->rt = rt;
    // 初始化链表头
    INIT_LIST_HEAD(&wq->list);

    // 如果只创建一个工作者线程
    // static int singlethread_cpu __read_mostly;
    if (singlethread) {
        cwq = init_cpu_workqueue(wq, singlethread_cpu);
        err = create_workqueue_thread(cwq, singlethread_cpu);
        start_workqueue_thread(cwq, -1);
    } else {
        cpu_maps_update_begin();
        spin_lock(&workqueue_lock);
        // 将队列插入到链表头
        list_add(&wq->list, &workqueues);
        spin_unlock(&workqueue_lock);
        // 为每个CPU创建一个工作者线程
        for_each_possible_cpu(cpu) {
            cwq = init_cpu_workqueue(wq, cpu);
            if (err || !cpu_online(cpu))
                continue;
            err = create_workqueue_thread(cwq, cpu);
            start_workqueue_thread(cwq, cpu);
        }
        cpu_maps_update_done();
    }

    if (err) {
        destroy_workqueue(wq);
        wq = NULL;
    }
    return wq;
}
EXPORT_SYMBOL_GPL(__create_workqueue_key);
{% endhighlight %}

*queue_work()*函数把函数插入到工作队列，它接收*wq*和*work*两个指针，*wq*指向*workqueue_struct*结构，*work*指向*work_struct*结构体。

#### <linux/include/workqueue.h> ####

{% highlight c++ %}
extern int queue_work(
    struct workqueue_struct *wq,
    struct work_struct *work);
{% endhighlight %}

这个函数主要执行下列步骤：

1. 检查要插入的函数是否已经在工作队列中，通过*work->pending*字段是否等于1判断，如果已经存在就结束。
2. 把*work_struct*描述符加到工作队列链表中，然后把*work->pending*设置为1。
3. 如果工作者线程在本地的CPU的*cpu_workqueue_struct*描述符的*more_work*等待队列上睡眠，那么就唤醒这个线程。

*queue_delayed_work()*函数和*queue_work()*几乎相同，只是*queue_delayed_work()*函数多一个以系统滴答数*delay*来表示时间延迟的参数。

#### <kernel/workqueue.c> ####

{% highlight c++ %}
int queue_delayed_work(
    struct workqueue_struct *wq,
    struct delayed_work *dwork,
    unsigned long delay)
{
    if (delay == 0)
        return queue_work(wq, &dwork->work);

    return queue_delayed_work_on(-1, wq, dwork, delay);
}
EXPORT_SYMBOL_GPL(queue_delayed_work);
{% endhighlight %}

*delay*用于确保挂起的函数在执行前的等待时间尽可能的短，实际上*queue_delayed_work*依靠软定时器把*work_struct*描述符插入工作队列链表的实际操作向后推迟了。如果相应的*work_struct*描述符还没有插入工作队列链表，*cancel_delayed_work()*就删除曾被调度过的工作队列函数。

可以看到，如果*delay*为0，那么就执行*queue_work()*函数，否则就执行*queue_delayed_work_on()*函数。

#### <kernel/workqueue.c> ####

{% highlight c++ %}
// cpu表示要执行work的CPU的数量
int queue_delayed_work_on(
    int cpu, struct workqueue_struct *wq,
    struct delayed_work *dwork, unsigned long delay)
{
    int ret = 0;
    struct timer_list *timer = &dwork->timer;
    struct work_struct *work = &dwork->work;
    // 将work设置为WORK_STRUCT_PENDING
    if (!test_and_set_bit(WORK_STRUCT_PENDING, work_data_bits(work))) {
        BUG_ON(timer_pending(timer));
        BUG_ON(!list_empty(&work->entry));

        timer_stats_timer_set_start_info(&dwork->timer);
        // worker增加计时器
        set_wq_data(work, wq_per_cpu(wq, raw_smp_processor_id()));
        timer->expires = jiffies + delay;
        timer->data = (unsigned long)dwork;
        timer->function = delayed_work_timer_fn;

        // 如果CPU的数量大于0
        if (unlikely(cpu >= 0))
            // 每个都增加一个timer计时器
            add_timer_on(timer, cpu);
        else
            add_timer(timer);
        ret = 1;
    }
    return ret;
}
EXPORT_SYMBOL_GPL(queue_delayed_work_on);
{% endhighlight %}

每个工作者线程在*worker_thread()*函数内部不断地执行循环操作，因而，线程在绝大多数时间里处于睡眠状态并等待某些工作被插入队列。工作线程一旦被唤醒就调用*run_workqueue()*函数，这个函数从工作者线程的工作队列链表中删除所有*work_struct*描述符并执行相应的挂起函数。

#### <kernel/workqueue.c> ####

{% highlight c++ %}
static int worker_thread(void *__cwq)
{
    struct cpu_workqueue_struct *cwq = __cwq;
    DEFINE_WAIT(wait);

    if (cwq->wq->freezeable)
        set_freezable();

    // 执行循环操作
    for (;;) {
        prepare_to_wait(&cwq->more_work,
            &wait,
            TASK_INTERRUPTIBLE);
        if (!freezing(current) &&
            !kthread_should_stop() &&
            list_empty(&cwq->worklist))
            schedule();
        finish_wait(&cwq->more_work, &wait);

        try_to_freeze();

        if (kthread_should_stop())
            break;
        // 执行相应的挂起函数
        run_workqueue(cwq);
    }

    return 0;
}
{% endhighlight %}

由于工作队列函数可以阻塞，因此，可以让工作者线程睡眠，甚至可以让它迁入到另一个CPU上恢复执行[^1]。有时候，内核必须等待工作低劣中所有的挂起函数执行完毕。*flush_workqueue()*函数接收一个*workqueue_struct*描述符的地址，并且在工作队列中的所有挂起函数结束之前使调用进程一直处于阻塞状态。但是这个函数不会等待在调用这个函数之后新加入工作队列的挂起函数。

[^1]: 虽然一个工作者线程以及函数会被插入到本地CPU队列中，但系统所有的CPU都可以执行这个函数。

会过来看*run_workqueue*函数，我们可以看到这个函数从工作者线程的工作队列链表中删除所有*work_struct*描述符并执行相应的挂起函数。

#### <kernel/workqueue.c> ####

{% highlight c++ %}
static void run_workqueue(struct cpu_workqueue_struct *cwq)
{
    // 给cpu_workqueue_struct实例上上自旋锁
    spin_lock_irq(&cwq->lock);
    // 当CPU上工作队列的列表不为空时执行循环
    while (!list_empty(&cwq->worklist)) {
        struct work_struct *work = list_entry(cwq->worklist.next,
                        struct work_struct, entry);
        // 通过 work->func 获取到执行函数
        work_func_t f = work->func;
#ifdef CONFIG_LOCKDEP
        struct lockdep_map lockdep_map = work->lockdep_map;
#endif
        trace_workqueue_execution(cwq->thread, work);
        // 设置当前的工作
        cwq->current_work = work;
        // 删除链表中的元素
        list_del_init(cwq->worklist.next);
        // 解锁自旋锁
        spin_unlock_irq(&cwq->lock);

        BUG_ON(get_wq_data(work) != cwq);
        // 移除pending
        work_clear_pending(work);
        lock_map_acquire(&cwq->wq->lockdep_map);
        lock_map_acquire(&lockdep_map);
        // 执行相应的work的函数
        f(work);
        lock_map_release(&lockdep_map);
        lock_map_release(&cwq->wq->lockdep_map);

        if (unlikely(in_atomic() || lockdep_depth(current) > 0)) {
            // ... 调试信息 ...
        }
        // 上自旋锁
        spin_lock_irq(&cwq->lock);
        // 把当前任务设置为NULL
        cwq->current_work = NULL;
    }
    // 解锁自旋锁
    spin_unlock_irq(&cwq->lock);
}
{% endhighlight %}

### 删除工作队列 ###

删除工作队列比较简单，删除工作队列使用*destory_workqueue()*函数，其中会遍历CPU并且删除相应的工作队列信息。

#### <kernel/workqueue.c> ####

{% highlight c++ %}
void destroy_workqueue(struct workqueue_struct *wq)
{
    const struct cpumask *cpu_map = wq_cpu_map(wq);
    int cpu;

    cpu_maps_update_begin();
    spin_lock(&workqueue_lock);
    list_del(&wq->list);
    spin_unlock(&workqueue_lock);

    for_each_cpu(cpu, cpu_map)
        // 删除工作者线程
        cleanup_workqueue_thread(per_cpu_ptr(wq->cpu_wq, cpu));
    cpu_maps_update_done();

    free_percpu(wq->cpu_wq);
    kfree(wq);
}
EXPORT_SYMBOL_GPL(destroy_workqueue);
{% endhighlight %}

### 预定义工作队列 ###

在绝大多数情况下，为了运行一个函数而创建整个工作者线程开销过大，所以，内核引入了一个叫做*events*的预定义工作队列，所以的内核开发者都可以随意使用。预定义工作队列只是一个包括不同内核曾函数和I/O驱动程序的标准工作队列，它的*workqueue_struct*描述符存放在*keventd_wq*数组中。

内核提供了如下函数操作工作队列：

#### <kernel/workqueue.c> ####

{% highlight c++ %}
// 等价于queue_work(keventd_wq, w)
int schedule_work(struct work_struct *work)
{
    return queue_work(keventd_wq, work);
}
EXPORT_SYMBOL(schedule_work);

// 等价于queue_delayed_work(keventd_wq, w,d)
// 并且在任何CPU上都可以
int schedule_delayed_work_on(int cpu,
            struct delayed_work *dwork, unsigned long delay)
{
    return queue_delayed_work_on(cpu, keventd_wq, dwork, delay);
}
EXPORT_SYMBOL(schedule_delayed_work_on);

// 等价于queue_delayed_work(keventd_wq, w,d)
// 但是只能在指定的CPU上
int schedule_delayed_work(struct delayed_work *dwork,
                    unsigned long delay)
{
    return queue_delayed_work(keventd_wq, dwork, delay);
}
EXPORT_SYMBOL(schedule_delayed_work);

// 等价于flush_workqueue(keventd_wq)
void flush_scheduled_work(void)
{
    flush_workqueue(keventd_wq);
}
EXPORT_SYMBOL(flush_scheduled_work);
{% endhighlight %}

当函数很少被调用时，预定义工作队列节省了很多重要的系统资源。另一方面，不应该使在预定义工作队列中执行的函数长时间的处于阻塞状态，因为工作队列链表中的挂起函数是在每个CPU上以串行的方式执行的，而太长的延迟对预定义工作队列的其他用户会产生不好的影响。

除了*events*队列，Linux中还会有一些其他的专用的工作队列，例如*kblockd*。