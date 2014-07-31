---
layout:    post
title:     读/写自旋锁
category:  内核同步
description: 读/写自旋锁...
tags: 自旋锁
---
读/写自旋锁的引入是为了增加内核的并发能力，只要没有内核控制路径对数据结构进行修改，读/写自旋锁就允许多个内核控制路径同时读一个数据结构，如果一个内核控制路径想对这个数据结构进行操作，那么它必须首先获取读/写自旋锁的写锁，写锁的授权独占访问这个资源。当然，允许对数据结构的并发可以提高系统性能。

每个读/写自旋锁都是一个*rwlock_t*结构，代码如下：

#### <include/linux/spinlock_types.h> ####

{% highlight c++ %}
typedef struct {
    raw_rwlock_t raw_lock;
#ifdef CONFIG_GENERIC_LOCKBREAK
    unsigned int break_lock;
#endif
#ifdef CONFIG_DEBUG_SPINLOCK
    unsigned int magic, owner_cpu;
    void *owner;
#endif
#ifdef CONFIG_DEBUG_LOCK_ALLOC
    struct lockdep_map dep_map;
#endif
} rwlock_t;
{% endhighlight %}

自旋锁的实现是体系结构相关的，所以我们可以看x86里面自旋锁的结构，从上面的结构体中我们可以看到有一个*raw_rwlock_t*的结构体对象*raw_lock*，我们可以看看在arch/x86中的*raw_rwlock_t*对象。

#### <arch/x86/include/asm/spinlock_types.h> ####

{% highlight c++ %}
typedef struct {
    unsigned int lock;
} raw_rwlock_t;
{% endhighlight %}

我们可以看到，这个结构体里就就只有一个*lock*字段。

*lock*字段是一个32位的字段，分为两个不同的部分：

1. 24位计数器，表示对受保护的数据结构并发地进行读操作和内核控制路径的数目，这个计数器的二进制补码存放在这个字段的0～23位。
2. 『未锁』标志字段，当没有内核控制路径在读或者写时设置这个位，否则就清0。这个『未锁』标志存放在*lock*字段的第24位。

如果自旋锁为空，那么*lock*字段的值位0x010000000，如果一个两个或者多个进程因为读获取了自旋锁，那么*lock*字段的值位0x00ffffff，0x00fffffe等。与*spinlock_t*结构一样，*rwlock_t*结构也包含*break_lock*字段。

*rwlock_init*宏把读/写自旋锁的*lock*字段初始化位未锁的状态，把*break_lock*初始化为0。

### 为读获取和释放一个锁 ###

*read_lock*宏作用于读/写自旋锁的地址*rwlp*，与*spin_lock*宏非常相似，如果编译内核时选择了内核抢占选项，*read_lock*宏执行与*spin_lock()*非常相似的操作，只是有一点不同，该宏执行了*__raw_read_trylock()*函数获得读/写自旋锁。

#### <arch/x86/include/asm/spinlock.h> ####

{% highlight c++ %}
static inline int __raw_read_trylock(raw_rwlock_t *lock)
{
    atomic_t *count = (atomic_t *)lock;

    if (atomic_dec_return(count) >= 0)
        return 1;
    atomic_inc(count);
    return 0;
}
{% endhighlight %}

读/写锁计数器*lock*字段时通过原子操作来访问的，尽管如此，但整个函数对计数器的操作并不是原子性的。例如，在用*if*语句完成对计数器的值的测试之后并返回1之前，计数器的值可能发生变化。不过函数能够正常工作。

实际上，只有在递减之前计数器的值不为0或者负数的情况下，函数才返回1，因为计数器等于0x01000000表示没有任何进程占用锁，等于0x00ffffff表示有一个读者，而等于0x00000000表示有一个写者。

*read_lock*宏原子地把自旋锁的值减去1，以此增加读者的个数，如果函数递减操作产生一个非复制，就获得自旋锁，否则就调用*_\_read_lock_failed()*函数，这个函数原子地增加*lock*字段以取消由*readl_lock*宏执行的递减操作，然后循环，直到*lock*字段变为正数。接下来，*__read_lock_failed()*又试图获得自旋锁。

解锁的过程相当简单，使用*read_unlock*宏只是简单的增加了*lock*字段的计数器以减少读者的计数，然后调用*preempt_enable()*重新启用内核抢占。

### 为写获取和释放一个锁 ###

*write_lock*宏的实现方式与*spin_lock()*和*read_lock()*相似，例如，如果支持内核抢占，则该函数禁用内核抢占并通过*__raw_write_trylock()*立即获得锁，如果该函数返回0，则说明锁已经被占用，然后该宏就重新启用内核抢占并开始等待循环。

#### <arch/x86/include/asm/spinlock.h> ####

{% highlight c++ %}
static inline int __raw_write_trylock(raw_rwlock_t *lock)
{
    atomic_t *count = (atomic_t *)lock;

    if (atomic_sub_and_test(RW_LOCK_BIAS, count))
        return 1;
    atomic_add(RW_LOCK_BIAS, count);
    return 0;
}
{% endhighlight %}

函数*__raw_write_trylock()*从读/写自旋锁中减去0x01000000，从而清除未上锁标志，如果减操作产生0，说明没有读者，则获取锁并返回1，否则，函数原子地在自旋锁上加0x01000000以取消减操作。

释放锁同样就暗淡，使用*write_unlock*宏即可，将相应地位标记为未锁状态，然后再调用*preempt_enable()*重新启用内核抢占。
