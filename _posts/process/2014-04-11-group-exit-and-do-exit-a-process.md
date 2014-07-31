---
layout:    post
title:     进程退出
category:  进程
description: 进程退出
tags: 进程撤销 do_group_exit do_exit
---
很多进程终止了它们需要执行的代码，这些进程就已经结束了，当这种情况发生时，就必须通知内核以便内核释放进程所拥有的资源，包括内存、打开的文件描述符、信号量之类的东西。

进程终止的一般方式时调用exit()库函数，该函数释放C函数库锁分配的资源，执行编程者锁注册的每一个函数，并结束从系统回收进程的那个系统调用。exit()函数可能由编程者显式地插入。另外，C编译程序总是把exit()函数插入到main()函数的最后一条语句。

当进程接收到一个不能处理或忽视的信号时，或者当内核正在代表进程运行时在内核态产生一个不可恢复的CPU异常时，内核可以有选择地强迫整个线程组死掉。

进程终止可以使用两个系统调用：

1. exit_group()系统调用，终止整个线程组。
2. exit()系统调用，终止某个线程。

### do\_group\_exit()函数 ###

该函数代码如下：

#### <kernel/exit.c> ####

{% highlight c++ %}
NORET_TYPE void
do_group_exit(int exit_code)
{
    struct signal_struct *sig = current->signal;

    BUG_ON(exit_code & 0x80); /* core dumps don't get here */

    if (signal_group_exit(sig))
        exit_code = sig->group_exit_code;
    else if (!thread_group_empty(current)) {
        struct sighand_struct *const sighand = current->sighand;
        spin_lock_irq(&sighand->siglock);
        if (signal_group_exit(sig))
            /* Another thread got here before we took the lock.  */
            exit_code = sig->group_exit_code;
        else {
            sig->group_exit_code = exit_code;
            sig->flags = SIGNAL_GROUP_EXIT;
            zap_other_threads(current);
        }
        spin_unlock_irq(&sighand->siglock);
    }

    do_exit(exit_code);
    /* NOTREACHED */
}
{% endhighlight %}

do\_group\_exit()函数杀死属于current线程组的所有进程，它接受进程的终止代码号作为参数，进程终止代码号可能时系统调用exit\_group()指定的一个值，也可以时内核提供的一个代码号。通常情况下exit\_group()说明进程正常中止，而内核提供的代码号通常表示进程异常结束。

代码检查退出进程的SIGNAL\_GROUP\_EXIT标志是否不为0，如果不为0，说明内核已经开始为线程组执行退出过程，exit\_code直接为*current->signal->group_exit_code*。否则，设置进程的SIGNAL\_GROUP\_EXIT标志并把终止代码号存放到*current->signal->group_exit_code*中。

调用*zap_other_threads()*函数杀死*current*线程组中的其他进程，扫描与*current->tgid*对应的PIDTYPE_TGID类型的散列表中的每个PID链表，向表中所有不同于current的进程发送SIGKILL信号，以便每个进程都能执行do\_exit()函数。

最终调用do_exit()函数。

### do\_exit()函数 ###

do\_exit()函数体比较大，并且涉及的知识点过多，所以简单记录一下笔记：

#### <kernel/exit.c> ####

{% highlight c++ %}
/*
 * 实际上do_exit做的比我们想象的要多
 * 虽然是退出一个进程，但要清除进程所
 * 有使用的资源，包括进程自身，还需要
 * 注意读写保护，进程组等多种复杂的结
 * 构。
 */
NORET_TYPE void do_exit(long code){
    struct task_struct *tsk = current;
    int group_dead;

    profile_task_exit(tsk);

    WARN_ON(atomic_read(&tsk->fs_excl));

    if (unlikely(in_interrupt()))
        panic("Aiee, killing interrupt handler!");
    if (unlikely(!tsk->pid))
        panic("Attempted to kill the idle task!");

    set_fs(USER_DS);

    tracehook_report_exit(&code);

    validate_creds_for_do_exit(tsk);

    // 表示进程正在被删除
    if (unlikely(tsk->flags & PF_EXITING)) {
        printk(KERN_ALERT
            "Fixing recursive fault but reboot is needed!\n");
        tsk->flags |= PF_EXITPIDONE;
        set_current_state(TASK_UNINTERRUPTIBLE);
        schedule();
    }

    exit_irq_thread();

    exit_signals(tsk);
    smp_mb();
    spin_unlock_wait(&tsk->pi_lock);

    if (unlikely(in_atomic()))
        printk(KERN_INFO "note: %s[%d] exited " \
                         "with preempt_count %d\n",
                current->comm, task_pid_nr(current),
                preempt_count());

    acct_update_integrals(tsk);

    group_dead = atomic_dec_and_test(&tsk->signal->live);
    if (group_dead) {
        hrtimer_cancel(&tsk->signal->real_timer);
        exit_itimers(tsk->signal);
        if (tsk->mm)
            setmax_mm_hiwater_rss(&tsk->signal->maxrss, tsk->mm);
    }
    acct_collect(code, group_dead);
    if (group_dead)
        tty_audit_exit();
    if (unlikely(tsk->audit_context))
        audit_free(tsk);

    tsk->exit_code = code;
    taskstats_exit(tsk, group_dead);

    exit_mm(tsk);

    if (group_dead)
        acct_process();
    trace_sched_process_exit(tsk);

    exit_sem(tsk);
    exit_files(tsk);
    exit_fs(tsk);
    check_stack_usage();
    exit_thread();
    cgroup_exit(tsk, 1);

    if (group_dead && tsk->signal->leader)
        disassociate_ctty(1);

    module_put(task_thread_info(tsk)->exec_domain->module);

    proc_exit_connector(tsk);
    perf_event_exit_task(tsk);

    exit_notify(tsk, group_dead);
#ifdef CONFIG_NUMA
    mpol_put(tsk->mempolicy);
    tsk->mempolicy = NULL;
#endif
#ifdef CONFIG_FUTEX
    if (unlikely(current->pi_state_cache))
        kfree(current->pi_state_cache);
#endif
    debug_check_no_locks_held(tsk);
    tsk->flags |= PF_EXITPIDONE;

    if (tsk->io_context)
        exit_io_context(tsk);

    if (tsk->splice_pipe)
        __free_pipe_info(tsk->splice_pipe);

    validate_creds_for_do_exit(tsk);

    preempt_disable();
    exit_rcu();
    tsk->state = TASK_DEAD;
    schedule();
    BUG();
    for (;;)
        cpu_relax();
}
{% endhighlight %}

所有的进程的终止都是由do\_exit()函数来处理，这个函数从内核数据结构中删除堆终止进程的大部分引用，同样，do\_exit()函数接受终止代号作为参数执行。

{:.center}
![system](/linux-kernel-architecture/images/exit.png){:style="max-width:600px"}

{:.center}
进程终止流程图

该函数执行了下列操作：

把进程描述符flag字段设置为PF\_EXITING标志，表示进程正在被删除。如果需要，通过函数*del\_timer\_sync()*从动态定时器队列中删除进程描述符。

分别调用exit\_mm()、exit\_sem()、\_\_exit\_files()、\_\_exit\_fs()、exit\_namespace()和exit\_thread()函数从进程描述符中分离出与分页、信号量、文件系统、打开文件描述符、命名空间以及I/O位图相关的数据结构，如果没有其他进程共享这些数据结构，那么这些函数还删除所有这些这些数据结构中的数据。

如果实现了被杀死进程的执行域和可执行格式的内核函数包含在内核模块中，则函数递减计数器。

把进程描述符的exit\_code字段设置成进程的终止戴好。这个值要么是\_exit()或exit\_group()系统调用参数，要么是内核提供的错误代码。

调用exit_notify()函数，如果出问题，则变为僵尸进程[^1]。完成后调用schedule()函数选择一个新进程运行。

[^1]: 僵尸进程最后由内核改变其父进程为init进程，最终由init进程释放资源。