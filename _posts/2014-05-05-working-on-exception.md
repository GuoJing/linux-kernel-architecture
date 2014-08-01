---
layout:    post
title:     异常处理
category:  中断和异常
description: 异常处理...
tags: 异常
---
CPU产生的大部分异常都由Linux解释为出错条件，当其中一个异常发生时，内核就向引起异常的进程发送一个信号通知进程系统出现了一个反常条件。例如，如果进程执行了一个被0除的操作，CPU就产生一个『Divide error』异常，并由相应的异常处理程序向当前进程发送一个SIGFPE信号，这个进程必须采取一些特定的步骤恢复或者中止运行。

异常处理程序有一个标准结构，由以下三部组成：

1. 用汇编语言在内核堆栈中保存大多数寄存器内容。
2. 用C语言便携的函数处理异常。
3. 通过ret\_from\_exception()函数从异常处理程序退出。

为了利用异常，必须对IDT进行适当的初始化，使得每个被确认的异常都有一个异常处理程序。*trap_init()*函数的工作是将一些异常处理的函数插入到IDT的非屏蔽中断及异常表项中。这些函数包括：

#### <arch/x86/include/asm/desc.h> ####

{% highlight c++ %}
static
inline void set_system_intr_gate(
    unsigned int n, void *addr)
{
    BUG_ON((unsigned)n > 0xFF);
    _set_gate(n, GATE_INTERRUPT, addr, 0x3, 0, __KERNEL_CS);
}

static
inline void set_system_trap_gate(
    unsigned int n, void *addr)
{
    BUG_ON((unsigned)n > 0xFF);
    _set_gate(n, GATE_TRAP, addr, 0x3, 0, __KERNEL_CS);
}

static
inline void set_trap_gate(
    unsigned int n, void *addr)
{
    BUG_ON((unsigned)n > 0xFF);
    _set_gate(n, GATE_TRAP, addr, 0, 0, __KERNEL_CS);
}

static
inline void set_task_gate(
    unsigned int n, unsigned int gdt_entry)
{
    BUG_ON((unsigned)n > 0xFF);
    _set_gate(n, GATE_TASK, (void *)0, 0, 0, (gdt_entry<<3));
}

static
inline void set_intr_gate_ist(
    int n, void *addr, unsigned ist)
{
    BUG_ON((unsigned)n > 0xFF);
    _set_gate(n, GATE_INTERRUPT, addr, 0, ist, __KERNEL_CS);
}

static
inline void set_system_intr_gate_ist(
    int n, void *addr, unsigned ist
    )
{
    BUG_ON((unsigned)n > 0xFF);
    _set_gate(n, GATE_INTERRUPT, addr, 0x3, ist, __KERNEL_CS);
}
{% endhighlight %}

上面的函数我们先要了解中断门、陷阱门以及系统门。

**中断门（*interrupt gate*）**

用户态的进程不能访问一个Intel中断门，门的DPL字段为0，所有的Linux中断处理程序都通过中断门激活，并全部限制在内核态。

**系统门（*system gate*）**

用户态的进程可以访问的一个Intel陷阱门，门的DPL字段为3。通过系统门来激活三个Linux异常处理程序，它们的向量是4，5以及128。

**系统中断门（*system interrupt gate*）**

能够被用户态进程访问的Intel中断门，门的DPL字段为3。与向量3相关的异常处理程序是由系统中断门激活的，因此，在用户态可以使用汇编语言指令int3。

**陷阱门（*tarp gate*）**

用户态的进程不能访问一个Intel陷阱门，门的字段为0，大部分Linux异常处理程序都通过陷阱门来激活。

**任务门（*task gate*）**

不能被用户态进程访问的Intel任务门，门的DPL字段为0。Linux对『Double fault』异常的处理程序是由任务门激活的。由于『Double fault』异常表示内核有严重的非法操作，其处理程序是通过任务门而不是陷阱门或系统门完成的。

产生这种异常的时候，CPU取出存放在IDT的第8项中的任务门描述符，该描述符指向存放在GDT表第32项中的TSS段描述符，然后CPU利用TSS段中的相关值装载*eip*和*esp*，结果是，处理器在自己的私有栈上执行*doubleefault_fn()*异常处理函数。

如果我们继续看\_\_set\_gate函数：

#### <arch/x86/include/asm/desc.h> ####

{% highlight c++ %}
static inline void _set_gate(
    int gate, unsigned type, void *addr,
    unsigned dpl, unsigned ist, unsigned seg)
{
    gate_desc s;
    pack_gate(&s, type, (unsigned long)addr, dpl, ist, seg);
    /*        
     * 不需要原子化操作因为在初始化时只执行一遍
     */
    write_idt_entry(idt_table, gate, &s);
}
{% endhighlight %}

可以看到最终会将初始化需要的IDT信息写入到IDT中。

----

执行异常处理程序的C函数总是由do_前缀和处理程序名组成，其中大部分函数把硬件出错码和异常向量保存在当前的进程描述符中，然后项当前进程发送一个适当的信号。

异常处理程序中止后，当前进程就立即关注这个信号，这个信号要么由用户态进程自己处理，那么就由内核来处理，如果由内核处理，那么一般内核都会杀死当前进程。
