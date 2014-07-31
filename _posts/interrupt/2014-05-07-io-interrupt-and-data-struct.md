---
layout:    post
title:     I/O中断处理
category:  中断和异常
description: I/O中断处理...
tags: PIC 中断处理
---
一般而言I/O中断处理程序必须足够灵活以给多个设备同时提供服务，例如在PCI总线的体系结构中，几个设备可以共享同一个IRQ线，这就意味着仅仅中断向量并不能说明所有问题。中断处理程序的灵活性是以两种不同的方式实现的：

**IRQ共享**

中断处理程序执行多个中断服务例程（*interrupt service routine，ISR*），每个ISR是一个与单独设备相关的函数，因为不可能预先直到哪个特定的设备产生IRQ，因此，每个ISR都被执行，以验证它的设备是否需要关注，如果是，当设备产生中断时，就执行需要执行的所有操作。

**IRQ动态分配**

一条IRQ线在可能的最后时刻才与一个设备驱动程序关联，例如光驱里的IRQ线只有在用户需要访问的时候才被分配，这样，即使几个硬件设备并不共享IRQ线，同一个IRQ向量页可以由这几个设备在不同时刻使用。

当一个中断发生时，并不是所有的操作都具有相同的紧迫性，所以，把所有的操作都放进中断处理程序本身并不合适，需要时间长的非常重要的操作应该推后，因为当一个中断处理程序正在运行时，相应的IRQ线上发出的信号就暂时被忽略。

更重要的时，中断处理程序时代表进程执行的，它代表的进程的状态总是应该处于TASK_RUNNING的状态，否则就可能出现系统僵死的情况，所以中断处理程序不能执行任何阻塞的操作，例如磁盘I/O操作，因此，Linxu把中断马上要执行的操作分为三类：

1. 紧急的（*Critical*）：这样的操作如PIC应答中断，对PIC或设备控制器重编程或者修改由设备和处理器同时访问的数据结构都应该尽可能快额度执行。紧急操作要在一个中断处理程序内立即执行，而且必须在禁止可屏蔽中断的情况下。
2. 非紧急的（*Noncritical*）：这样的操作如修改那些只有处理才会访问的数据结构，这些操作页要很快地完成，因此它们由中断处理程序立即执行，但必须时在开中断的情况下。
3. 非紧急可延迟的（*Noncritical deferrable*），这样的操作例如把缓冲区的内容拷贝到某个进程的地址空间，例如把键盘缓冲区的内容发送到终端处理程序，这些操作可能被延迟较长的时间间隔而不影响内核操作。非紧急可延迟中断由单独的程序执行。

不管引起中断的种类如何，所有I/O中断处理程序都执行四个相同的步骤：

1. 在内核态堆栈中保存IRQ的值和寄存器的内容。
2. 为正在给IRQ线服务的PIC发送一个应答，这允许PIC进一步发出中断。
3. 执行共享这个IRQ的所有设备的中断服务例程ISR。
4. 跳到*ret_from_intr()*的地址后终止。

如下图：

{:.center}
![I/O IRQ](/linux-kernel-architecture/images/ioirq.png){:style="max-width:600px"}

{:.center}
I/O中断处理

### 中断向量 ###

物理IRQ可以分配给32～238范围内的任何向量，不过Linux使用向量128实现系统调用。由于IBM PC兼容的体系结构要求，一些设备必须被静态地连接到指定的IRQ线，如下：

1. 间隔定时设备必须连到IRQ0线[^io]。
2. 从8259A PIC必须与IRQ2线相连[^2]。
3. 必须把外部数学协处理器连接到IRQ13线，虽然最近的80x86处理器不再使用这样的设备。
4. 一般而言，一个I/O设备可以连接到有限个IRQ线。

[^io]: 我们以后可以看到本地时钟产生的中断的IRQ代码里设定的是irq0。

PIC的概念可以[点此连接](http://zh.wikipedia.org/wiki/PIC微控制器)。Linux中的中断向量如下：

{:.table_center}
向量范围                  | 用途
------------             | -------------
0～19                    | 非屏蔽中断和异常
20～31                   | Intel保留
32～127                  | 外部中断IRQ
128                      | Linux用于系统调用的可编程异常
129～238                 | 外部中断IRQ
239                      | 本地APIC时钟中断
240                      | 本地APIC高温中断
241～250                 | Linux保留
251～253                 | 处理器间中断
254                      | 本地APIC错误中断
255                      | 本地APIC伪中断

其中本地APIC伪中断由CPU屏蔽某个中断时产生。

为IRQ可配置设备选择一条线有三种方式：

1. 设置一些硬件跳线，但只适用于旧式设备卡。
2. 安装设备时执行一个使用程序，这样的程序可以让用户选择一个可用的IRQ号，或者探测系统自身以确定一个可用的IRQ号。
3. 在系统启动时执行一个硬件协议，外设宣布它们准备使用哪些中断线，然后协商一个最终的值以尽可能的减少冲突。

内核必须在启动中断前发现IRQ号与I/O设备之间的对应，否则，内核在不知道哪个向量对应哪个设备的情况下，无法处理来自这个设备的信号。IRQ号与I/O设备之间的对应是在初始化每个设备驱动程序时建立的。

[^2]: 虽然现在有更先进的PIC，但Linux还是支持8259风格的PIC。

### IRQ数据结构 ###

每个中断向量都有自己的*irq_desc*描述符，代码如下：

#### <include/linux/irq.h> ####

{% highlight c++ %}
struct irq_desc {
    unsigned int        irq;
    unsigned int            *kstat_irqs;
#ifdef CONFIG_INTR_REMAP
    struct irq_2_iommu      *irq_2_iommu;
#endif
    irq_flow_handler_t  handle_irq;
    struct irq_chip     *chip;
    struct msi_desc     *msi_desc;
    void            *handler_data;
    void            *chip_data;
    struct irqaction    *action;
    unsigned int        status;

    unsigned int        depth;
    unsigned int        wake_depth;
    unsigned int        irq_count;
    unsigned long       last_unhandled;
    unsigned int        irqs_unhandled;
    spinlock_t      lock;
#ifdef CONFIG_SMP
    cpumask_var_t       affinity;
    unsigned int        node;
#ifdef CONFIG_GENERIC_PENDING_IRQ
    cpumask_var_t       pending_mask;
#endif
#endif
    atomic_t        threads_active;
    wait_queue_head_t       wait_for_threads;
#ifdef CONFIG_PROC_FS
    struct proc_dir_entry   *dir;
#endif
    const char      *name;
} ____cacheline_internodealigned_in_smp;
{% endhighlight %}

其中重要字段的意义如下：

字段                  | 说明
------------          | -------------
irq                   | IRQ线
time\_rand\_state     | timer和state的指针
kstat_irqs            | per-CPU irq状态
handle_irq            | IRQ线上的事件处理，如果为空，则调用\_do\_IRQ()
msi_desc              | MSI描述符
handler_data          | IRQ线上的数据
action                | IRQ线上的动作
status                | 状态信息
depth                 | 如果IRQ线被激活，则显示为0，如果IRQ线被禁止了不止一次，则显示一个正数
wake_depth            | 嵌套IRQ调用
irq_count             | IRQ线上发生的中断数
last_unhandled        | 最后一次没有处理的中断的时间
irqs_unhandled        | 意外中断的总次数
lock                  | SMP系统的锁
node                  | 为了均衡使用的索引

如果一个中断内核没有处理，那么这个中断就是意外中断，也就是说，与某个IRQ线县官的中断处理例程ISR不存在，或者与某个中断线相关的所有例程都识别不出是否时自己硬件发出的中断。通常，内核检查从IRQ线接收以外中断的数量，当这条IRQ线连接的有故障的设备没完没了的发出中断，就禁用这条IRQ线。

由于多个设备会共有一条IRQ线，所以内核不会在每次检测到一个意外中断就立即禁止IRQ线，内核把中断和意外中断的总次数分别放在*irq_desc*描述符的*irq_count*和*irqs_unhandled*字段中，当产生100000次中断时，意外中断超过99900，内核才禁用这条IRQ线。

IRQ的状态标志如下：

字段                  | 说明
------------          | -------------
IRQ\_INPROGRESS       | IRQ的一个处理程序正在执行
IRQ\_DISABLED         | 由一个设备驱动程序故意的禁用IRQ
IRQ\_PENDING          | 一个IRQ已经出现在线上，它的出现页对PIC做出应答
IRQ\_REPLAY           | IRQ线被禁用，但是前一个出现的IRQ还没有对PIC做出应答
IRQ\_AUTODETECT       | 内核在执行硬件设备探测时使用IRQ线
IRQ\_WAITING          | 内核在执行硬件设备探测时使用IRQ线但相应的中断还没有产生
IRQ\_LEVEL            | 80x86结构上未使用
IRQ\_MASKED           | 未使用
IRQ\_PER\_CPU         | 80x86结构上未使用
IRQ\_NOPROBE          | IRQ线无法进行探测
IRQ\_NOREQUEST        | IRQ线无法被请求
IRQ\_NOAUTOEN         | IRQ线无法被激活以请求

多个设备共享一个单独的IRQ，所以内核要维护多个irqaction描述符，也就是上面的action，其中每个描述符涉及一个特定的硬件设备和特定的中断，irqaciton代码如下所示：

#### <include/linux/interrupt.h> ####

{% highlight c++ %}
struct irqaction {
    irq_handler_t handler;
    unsigned long flags;
    const char *name;
    void *dev_id;
    struct irqaction *next;
    int irq;
    struct proc_dir_entry *dir;
    irq_handler_t thread_fn;
    struct task_struct *thread;
    unsigned long thread_flags;
};
{% endhighlight %}

其中重要字段的意义如下：

字段                  | 说明
------------          | -------------
handler               | 指向一个I/O设备的中断服务例程，这是允许多个设备共享同一个IRQ的关键字段
flags                 | 描述IRQ与I/O设备之间的关系
mask                  | 未使用
name                  | I/O设备名
dev_id                | I/O设备私有字段
next                  | 链表的下一个irqaction元素
irq                   | IRQ线
dir                   | 指向与IRQn相关的/proc/irq/n目录的描述符