---
layout:    post
title:     动态分配IRQ线
category:  中断和异常
description: 动态分配IRQ线...
tags: IRQ 动态分配
---
IRQ中除了几个向量留给特定的设备，其余的向量都被动态地分配，因此有一种方式下同一条IRQ线可以让几个硬件设备使用，即使这些设备不允许IRQ共享，技巧就是使这些硬件设备的活动串行化，以便一次只能有一个设备拥有这个IRQ线。

在激活一个准备利用IRQ线的设备之前，其相应的驱动程序调用*request_irq()*，这个函数建立一个新的*irqaction*描述符，并用参数值初始化它。然后调用*setup_irq()*函数把这个描述符插入到合适的IRQ链表。

如果*setuo_irq*返回一个出错码，设备驱动程序中止操作，这意味着IRQ线已由另一个设备所使用，而这个设备不允许中断共享。当设备操作结束后，使用*free_irq()*函数从IRQ连表中删除这个描述符，并释放相应的内存区。

假定一个程序想要访问*/dev/fd0*设备文件，这个设备文件对应于系统中的第一个软盘，程序要做到这点，可以通过直接访问*/dev/fd0*，也可以通过在系统上安装一个文件系统，通常IRQ6分配给软盘控制器，给定这个号，软盘驱动程序发出下列请求：

{% highlight c++ %}
request_irq(6, floppy_interrupt,
            SA_INTERRUPT|SA_SAMPLE_RDANDOM,
            "floppy", NULL)
{% endhighlight %}

可以看到，*floppy_interrupt()*中断服务例程必须以关中断的方式执行，并且不共享这个IRQ，设置SA\_SAMPLE\_RANDOM标志意味着对软盘的访问是内核用于产生随机数的一个较好的随机事件源。当软盘的操作被终止时，要么中止*/dev/fd0*的I/O操作，要么卸载这个文件系统。然后驱动程序就释放IRQ线。

{% highlight c++ %}
free_irq(6, NULL)
{% endhighlight %}

为了把一个*irqaction*描述符插入到适当的连表中，内核调用*setup_irq()*函数，传递给这个函数的参数为*irq_nr*和*new*，*irq_nr*就是IRQ号，*new*为刚刚分配的*irqaction*描述符。*setup_irq()*是体系结构相关的，所以了解一下这个函数做了什么。

1. 检查另一个设备是否已经使用*irq_nr*这个IRQ，如果是，检查两个设备的irqaction描述符中的SA_SHIREQ标志是否都指定了IRQ线能被共享，否则就返回一个错误码。
2. 把*new加到链表中。
3. 如果没有其他设备共享同一个IRQ，清理相关的设置并调用irq_desc->handler PIC对象的*startup*方法以确保IRQ信号被激活。
