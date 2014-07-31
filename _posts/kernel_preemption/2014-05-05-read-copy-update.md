---
layout:    post
title:     读-拷贝-更新
category:  内核同步
description: 读-拷贝-更新 RCU...
tags: RCU 读-拷贝-更新
---
读-拷贝-更新（*RCU*）是为了保护在多数情况下被多个CPU读的数据结构而设计的一种同步技术，RCU允许多个读者和写者并发执行，相对于值允许一个写者执行的顺序锁，RCU有了本质上的改进。

简单的说RCU的逻辑是，当读者指向共享数据结构时，一旦有写者需要对共享数据结构进行写操作，那么写者就创建一个共享数据结构的副本，当完成写操作之后，将所有的读者指向新的数据结构，然后释放旧的数据结构即可。

RCU是不使用锁的，也就是说，它不使用被所用CPU共享的锁或计数器，在这一点上和读/写自旋锁和顺序锁相比，RCU具有更大的优势。RCU可以不使用共享数据机构而实现多个CPU同步，因为：

1. RCU只保护被动态分配并通过指针引用的数据结构。
2. 在被RCU保护的临界区中，任何内核控制路径都不能睡眠。

当内核控制路径要读取被RCU保护的数据结构是，执行宏*rcu_read_lock()*，该宏等同于*preempt_disable()*函数。同样，也可以执行*rcu_read_unlock()*，这个宏等同于*preempt_enable()*，代码如下：

#### <include/linux/rcutree.h> ####

{% highlight c++ %}
static inline void __rcu_read_lock(void)
{
    preempt_disable();
}

static inline void __rcu_read_unlock(void)
{
    preempt_enable();
}
{% endhighlight %}

接下来，读者间接引用该数据结构指针锁对应的内存单元并开始读这个数据结构，读者在完成对数据结构的读操作之前，是不能睡眠的，用*rec_read_unlock()*宏标记临界区的结束。

由于读者几乎不会做任何事情，所以也不会有任何竞争条件出现，所以写者不得不做得更多一些。实际上，当写者要更新数据结构的时候，它间接引用指针并生成整个数据结构的副本，然后，写者修改这个副本，一旦修改完毕，写者改变指向数据结构的指针，以便使它指向被修改后的副本。

由于修改指针值的操作是一个原子操作，所以旧副本和新副本对每个读者或写者都是可见的，在数据结构中并不会出现数据崩溃。尽管如此，还需要内存屏障来保证只有在数据结构被修改后，已更新的指针对其他CPU才是可见的，如果把自旋锁与RCU结合起来以禁止写者的并发执行，就隐含地引入了这样的内存屏障。

然而，使用RCU技术的真正困难在于，写者修改指针时不能立即释放数据结构的旧副本。实际上，写者开始修改时，正在访问数据结构的读者可能还在读旧副本，只有在CPU上的所有的读者都执行完*rcu_read_unlock()*之后，才可以释放旧的副本，内核要求每个潜在的读者在下面的操作之前执行*rcu_read_unlock()*宏。

1. CPU执行进程切换。
2. CPU开始在用户态执行。
3. CPU执行空循环。

对于上述的每种情况，我们都说CPU已经经过了静止状态（*quiescent state*）。

写者调用函数*call_rcu()*来释放数据结构的旧副本，该函数定义如下。

#### <include/linux/rcupdate.h> ####

{% highlight c++ %}
extern void call_rcu(
    struct rcu_head *head,
    void (*func)(struct rcu_head *head));
{% endhighlight %}

当所有的CPU都通过静止状态之后，*call_rcu()*接收*rcu_head*描述符[^1]的地址和将要调用的回调函数的地址作为参数，一旦回调函数被执行，它同城释放数据结构的旧副本。

[^1]: 这个描述符通常嵌在要被释放的数据结构中。

函数*call_rcu()*把回调函数和其他参数的地址存放在*rcu_head*描述符中，代码如下：

#### <include/linux/rcupdate.h> ####

{% highlight c++ %}
struct rcu_head {
    struct rcu_head *next;
    void (*func)(struct rcu_head *head);
};
{% endhighlight %}

然后把描述符插入到回调函数的per-CPU链表中，内核每经过一个时钟抵达旧周期性地检查本地CPU是否经过了一个静止状态，如果所有的CPU都经过了静止状态，本地tasklet旧执行链表中的所有回调函数。

RCU最常用的场景是Linux中的网络层和虚拟文件系统。
