---
layout:    post
title:     处理器间中断处理
category:  中断和异常
description: 处理器间中断处理...
tags: 中断处理
---
处理器间中断允许一个CPU向系统其他的CPU发送中断信号，处理器间中断（IPI）不是通过IRQ线传输的，而是作为信号直接放在连接所有CPU本地APIC的总线上。在多处理器系统上，Linux定义了下列三种处理器间中断：

**CALL\_FUNCTION\_VECTOR** （*向量0xfb*）

发往所有的CPU，但不包括发送者，强制这些CPU运行发送者传递过来的函数，相应的中断处理程序叫做*call_function_interrupt()*，例如，地址存放在群居变量*call_data*中来传递的函数，可能强制其他所有的CPU都停止，也可能强制它们设置内存类型范围寄存器的内容。通常，这种中断发往所有的CPU，但通过*smp_call_function()*执行调用函数的CPU除外。

**RESCHEDULE\_VECTOR** （*向量0xfc*）

当一个CPU接收这种类型的中断时，相应的处理程序限定自己来应答中断，当从中断返回时，所有的重新调度都自动运行。

**INVALIDATE\_TLB\_VECTOR** （*向量0xfd*）

发往所有的CPU，但不包括发送者，强制它们的转换后援缓冲器TLB变为无效。相应的处理程序刷新处理器的某些TLB表项。

----

处理器间中断处理程序的汇编语言代码是由*BUILD_INTERRUPT*宏产生的，它保存寄存器，从栈顶押入向量号减256的值，然后调用高级C函数，其名字就是第几处理程序的名字加前缀*smp_*，例如*CALL_FUNCTION_VECTOR*类型的处理器间中断的低级处理程序时*call_function_interrupt()*，它调用名为*smp_call_function_interrupt()*的高级处理程序，每个高级处理程序应答本地APIC上的处理器间中断，然后执行由中断触发的特定操作。

Linux有一组函数使得发生处理器间中断变为一件容易的事：

函数                  | 说明
------------          | -------------
send\_IPI\_all()        | 发送一个IPI到所有CPU，包括发送者
send\_IPI\_allbutself() | 发送一个IPI到所有CPU，不包括发送者
send\_IPI\_self()       | 发送一个IPI到发送者的CPU
send\_IPI\_mask()       | 发送一个IPI到位掩码指定的一组CPU
