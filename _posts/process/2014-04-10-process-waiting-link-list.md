---
layout:    post
title:     组织进程
category:  进程
description: 组织进程...
tags: 等待队列 互斥进程
---
运行队列链表把处于TASK_RUNNING状态的所有进程组织在一起，当要求把其他状态的进程分组时，不同的状态要求不同的处理，Linux选择了下列方式之。

没有为处于TASK\_STOPPED、EXIT\_ZOMBIE或EXIT\_DEAD状态的进程建立专门的链表。由于对处理暂停、僵死、死亡状态的进程访问比较简单，或者通过PID，或者通过特定父进程的子进程链表，所以不必堆这三种状态进行分组。

根据不同的特殊事件把处于TASK\_INTERRUPTIBLE或TASK\_UNINTERRUPTIBLE状态的进程细分为许多类，每一类都对应某个特殊的事件。在这种情况下，进程状态提供的信息满足不了快速检索进程的需要，所以必须引入另外的进程链表，这些链表被称作等待队列。

### 等待队列 ###

等待队列在内核中有很多用途，尤其用在中断处理、进程同步以及定时。这里并不详细解释，但进程必须经常等待某些事件的发生，例如等待I/O操作中止，等待释放系统资源，或者等待时间经过固定的间隔。等待队列实现了在事件上的条件等待：希望等待特定事件的进程把自己放进和式的等待队列，并放弃控制权。因为，等待队列表示一组睡眠的进程，当某个条件触发，内核会唤醒这些等待队列。

等待队列由双向链表实现[^1]。元素包括指向进程描述符的指针，每个等待队列都有一个等待队列头（*wait queue head*），等待队列头是一个类型为*wait_queue_head_t*的数据结构：

#### <include/linux/wait.h> ####

{% highlight c++ %}
struct __wait_queue_head {
    spinlock_t lock;
    struct list_head task_list;
};
typedef struct __wait_queue_head wait_queue_head_t;
{% endhighlight %}

因为等待队列是由中断处理程序和主要内核函数修改的，因此必须对其双向链表进行保护以免对其进行同时访问，因为同时访问会导致不可预测的后果。同步是通过等待队列头中的*lock*自旋锁实现的。*task_list*字段是等待进程链表的头。

等待进程链表中的元素类型为wait\_queue\_t，定义如下：

#### <include/linux/wait.h> ####

{% highlight c++ %}
struct __wait_queue {
    unsigned int flags;
    struct task_struct * task;
    wait_queue_func_t func;
    struct list_head task_list;
};
typedef struct __wait_queue wait_queue_t;
{% endhighlight %}

等待队列链表中的每个元素代表一个睡眠的进程，该进程等待某一事件的发生，它的描述符地址存放在*task*字段中，*task_list*字段中包含的是指针，由这个指针把一个元素链接到等待相同事件的进程链表中。

有时候，唤醒等待队列中的睡眠的进程有时并不方便，例如，如果两个或多个进程在等待互斥访问某一要释放的资源，仅仅唤醒一个进程才有意义。这个进程占有资源，而其他进程继续睡眠。否则唤醒多个进程只为了竞争一个资源，而这个资源只有一个进程能访问，结果其他进程必须再回到睡眠状态。

因此，有两种睡眠进程：互斥进程[^2]由内核有选择地唤醒，而非互斥进程[^2]总是由内核在事件发生时唤醒。等待访问临界资源的进程就是互斥进程的典型例子。

[^1]: 双向链表真是内核里无所不在的数据结构，树也是。

[^2]: wait\_queue\_t结构提里flag字段为1为互斥进程，为0则为非互斥进程。
