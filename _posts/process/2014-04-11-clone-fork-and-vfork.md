---
layout:    post
title:     进程复制
category:  进程
description: clone()、fork()以及vfork()...
tags: clone fork vfork 写时复制 do_fork copy_process pidhash
---
系统进程复制通常使用clone()、fork()以及vfork()系统调用。

这里只针对这几个函数做了少量的笔记，实际上在原书中有大量的细节讲解。建议打开*<kernel/fork.c>*和原书中的解析一一对比。这里仅仅是笔记，我认为比较有价值的部分。如果不感兴趣，可以跳过，只要知道有这几种创建进程的方式即可。

在Linux中，轻量级进程是由clone()函数创建的，这个函数使用下列参数。

字段名           | 说明
------------    | -------------
fn              | 指定一个由新进程执行的函数，当这个函数返回时，子进程终止。函数返回一个整数，表示子进程的退出代码
arg             | 指向传递给fn()函数的数据
flags           | 低字节指定子进程结束时发送到父进程的信号代码，通常为SIGCHLD信号
child_stack     | 表示把用户态堆栈指针赋给子进程esp寄存器。调用进程应该总时为子进程分配新的堆栈。
tls             | 表示线程局部存储段TLS数据结构的地址，该结构时为新轻量级进程定义的，只有在CLONE_SETTLE标志被设置时才有意义
ptid            | 表示父进程的用户态变量地址，该父进程具有与新轻量级进程相同的PID，只有在CLONE\_PARENT\_SETTID标志被设置时才有意义
ctid            | 表示新轻量级进程的用户态变量地址，该进程具有这一类进程的PID，只有在CLONE\_CHILD\_SETTID标志被设置时才有意义

实际上，clone()是在C语言库中定义的一个封装函数，它负责建立新轻量级进程的堆栈并且调用对编程者隐藏的clone()系统调用。实现clone()系统调用的sys_clone()服务里程没有fn和arg参数。

封装函数把fn指针存放在子进程堆栈的某个位置处，该位置就是该封装函数本身返回地址存放的位置。*arg*指针正好存放在子进程堆栈中*fn*的下面，当封装函数结束时，CPU从堆栈中取出返回地址，然后执行*fn(arg)*函数。

传统的fork()系统调用时在Linux中是用clone()实现的，其中clone()的flags参数指定为SIGCHLD信号及所有清0的clone标志，而它的child_stack参数是父进程当前的堆栈指针。因此，父进程和子进程暂时共享同一个用户堆栈。而由于写时复制技术，当任何一个进程试图改变栈，则立即各自得到用户堆栈的一份拷贝。

### do_fork()函数 ###

do\_fork()函数负责处理clone()、fork()和vfork()系统调用，也就是说，无论是clone()、fork()还是vfork()，都会调用do\_fork()函数。其参数列表如下：

字段名           | 说明
------------    | -------------
clone_flags     | 与clone()函数的flag参数相同
stack_start     | 与clone()函数的child\_stack参数相同
regs            | 指向通用寄存器值的指针，通用寄存器的值是在从用户态切换到内核态时被保存到内核态堆栈中的
stack_size      | 未使用，总是被设置为0

函数的原型如下：

#### <kernel/fork.c> ####

{% highlight c++ %}
long do_fork(unsigned long clone_flags,
          unsigned long stack_start,
          struct pt_regs *regs,
          unsigned long stack_size,
          int __user *parent_tidptr,
          int __user *child_tidptr){
}
{% endhighlight %}

所有的3个fork机制都调用了do_fork这个与体系结构无关的函数，代码流程图如下：

{:.center}
![system](/linux-kernel-architecture/images/do_fork.png){:style="max-width:600px"}

其中执行了下列操作：

通过查找pidmap\_array位图，为子进程分配新的PID。然后检查父进程的ptrace字段，如果它的值不等于0，说明有另外一个进程正在跟踪父进程，因而，do\_fork()检查debugger程序是否自己想跟踪子进程。如果子进程不是内核线程，那么do\_fork()设置CLONE\_PTRACE标志。

调用copy_process()复制进程描述符，需要所有资源都是可用的，并返回进程描述符地址。

如果设置了CLONE\_STOPPED标志，或者必须跟踪子进程，则子进程的状态设置为TASK\_STOPPED，否则，调用*wake_up_new_task()*函数执行。

如果设置了CLONE\_VFORK标志，则把父进程插入等待队列，并挂起父进程直到子进程释放自己的内存地址空间[^1]。

[^1]: vfork设计用于子进程形成后立即执行*execve*系统调用，在子进程退出或开始新程序之前，父进程处于堵塞状态。

其中一个重要的函数是*copy_process*。

#### <kernel/fork.c> ####

{% highlight c++ %}
static struct task_struct *copy_process(
    unsigned long clone_flags,
    unsigned long stack_start,
    struct pt_regs *regs,
    unsigned long stack_size,
    int __user *child_tidptr,
    struct pid *pid,
    int trace){
}
{% endhighlight %}

函数流程图如下：

{:.center}
![system](/linux-kernel-architecture/images/copy_process.png){:style="max-width:300px"}

该函数执行下列操作：

检查参数clone\_flags锁传递的标志的一致性，在某种情况下会返回错误代号。没有问题，通过调用*security_task_create()*以及*security_task_alloc()*执行所有附加的安全检查。完成后调用*dup_task_struct()*为子进程获取进程描述符，检查[资源限制](/linux-kernel-architecture/2014/03/30/process-descriptor/)并递增计数器，更新PID并存入*tsk->pid*字段。复制/共享进程的各个部分代码包括拷贝文件，命名空间。然后初始化进程的亲子关系。

完成后执行SET\_LINK宏，把新进程描述符插入进程链表。调用*attach\_pid()*把新进程描述符的PID插入到pidhash散列表。经过一系列繁琐的检查和线程组操作后返回进程描述符指针。

其中『复制/共享进程的各个部分代码包括拷贝文件，命名空间』相关的处理代码如下：

{% highlight c++ %}
if ((retval = audit_alloc(p)))
    goto bad_fork_cleanup_policy;
/* copy all the process information */
if ((retval = copy_semundo(clone_flags, p)))
    goto bad_fork_cleanup_audit;
if ((retval = copy_files(clone_flags, p)))
    goto bad_fork_cleanup_semundo;
if ((retval = copy_fs(clone_flags, p)))
    goto bad_fork_cleanup_files;
if ((retval = copy_sighand(clone_flags, p)))
    goto bad_fork_cleanup_fs;
if ((retval = copy_signal(clone_flags, p)))
    goto bad_fork_cleanup_sighand;
if ((retval = copy_mm(clone_flags, p)))
    goto bad_fork_cleanup_signal;
if ((retval = copy_namespaces(clone_flags, p)))
    goto bad_fork_cleanup_mm;
if ((retval = copy_io(clone_flags, p)))
    goto bad_fork_cleanup_namespaces;
{% endhighlight %}

其中部分拷贝的意义分别为：

字段名           | 说明
------------    | -------------
copy\_semundo   | 如果COPY\_SYSVSEM置位，则使用父进程的System V信号量
copy\_fs        | 如果CLONE\_FILES置位，则使用父进程的文件描述符，否则创建新的files结构，其中包含的信息与父进程相同。该信息的修改可以独立于原结构
copy\_sighand   | 如果CLONE\_THREAD置位，则使用父进程的信号处理程序
copy\_signal    | 如果CLONE\_THREAD置位，则与父进程共同使用信号处理中不特定于处理程序的部分
copy\_mm        | 如果COPY\_MM置位，则让父进程和子进程共享同一地址空间
copy\_namespace | 有特别的调用语意，建立于子进程的命名空间
copy\_thread    | 这是一个特定于体系结构的函数，用于复制进程中特定于线程的数据

这里的特定于线程并不是指某个CLONE标志，也不是指操作堆线程而非整个进程执行。其语意无非是指复制执行上下午中特定于体系结构的所有数据。

重要的是填充*task_struct->thread*的各个成员，这是一个*thread_struct*类型的结构，其定义是体系结构相关的，需要深入了解各种CPU的相关知识。
