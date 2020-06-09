---
layout:    post
title:     软中断守护进程
category:  中断和异常
description: 软中断守护进程...
tags: 软中断 ksoftirqd
---
我们知道如果不在中断上下文中调用*raise_softirq*方法，则调用*wakeup_softirq*来唤醒软中断守护进程，这个守护进程会执行软中断。软中断的守护进程的任务是，与其余内核代码异步执行软中断，为此，系统中每个处理分配器都有自己的守护进程，名为*ksoftirqd*。

内核中有两处调用了*wakeup_softirq*唤醒了该守护进程。

1. do_softirq中。
2. 在raise\_softirq\_irqoff末尾。

*raise\_softirq\_irqoff*函数由*raise_softirq*在内部调用，如果内核当前停用了中断，也可以直接使用。唤醒函数本身只需要几行代码，首先，借助于一些宏，从一个per-CPU变量读取指向当前CPU软中断守护进程的*task_struct*的指针。如果该进程当前的状态不是*TASK_RUNNING*的话，则通过*wake_up_process*将其置放到就绪进程列表的末尾。

尽管这并不会立即开始处理所有待决的软中断。但只要调度器没有更好的选择，就会选择用该守护进来执行。在系统启动时用*initcall*机制调用*init*不就，就创建了系统的软中断守护进程。代码如下：

#### <kernel/softirq.h> ####

{% highlight c++ %}
static int ksoftirqd(void * __bind_cpu)
{
    set_current_state(TASK_INTERRUPTIBLE);

    current->flags |= PF_KSOFTIRQD;
    while (!kthread_should_stop()) {
        // 禁止抢占
        preempt_disable();
        if (!local_softirq_pending()) {
            preempt_enable_no_resched();
            schedule();
            preempt_disable();
        }

        __set_current_state(TASK_RUNNING);

        while (local_softirq_pending()) {
            /*
               禁止抢占会停止让CPU下线，如果已经下线，那么就
               正在一个错误的CPU上，那么就不要执行
               goto wait_to_die
            */
            if (cpu_is_offline((long)__bind_cpu))
                goto wait_to_die;
            // 执行软中断
            do_softirq();
            // 可以抢占
            preempt_enable_no_resched();
            // 确保对当前进程设置了TIE_NEED_RESCHED
            // 因为所有这些函数执行时都启用了硬件中断
            cond_resched();
            // 禁止抢占
            preempt_disable();
            rcu_sched_qs((long)__bind_cpu);
        }
        preempt_enable();
        set_current_state(TASK_INTERRUPTIBLE);
    }
    __set_current_state(TASK_RUNNING);
    return 0;

wait_to_die:
    preempt_enable();
    /* 等待kthread_stop停止 */
    set_current_state(TASK_INTERRUPTIBLE);
    while (!kthread_should_stop()) {
        schedule();
        set_current_state(TASK_INTERRUPTIBLE);
    }
    __set_current_state(TASK_RUNNING);
    return 0;
}
{% endhighlight %}

每次被唤醒时，守护进程首先检查是否有标记出的待决软中断，否则明确地调用调度器，将控制软中断交给其他进程。如果有标记出的软中断，那么守护进程接下来将处理软中断。

进程在一个*while*循环中重复调用*do_softirq*和*cond_resched*，直至没有标记出的软中断位置。*con_resched*确保在对当前进程设置了*TIE_NEED_RESCHED*标志的情况下调用调度器，这是可能的，因为所有这些函数执行时都启用了硬件中断。
