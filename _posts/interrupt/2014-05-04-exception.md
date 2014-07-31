---
layout:    post
title:     异常定义
category:  中断和异常
description: 异常定义...
tags: 异常
---
80x86处理器发布了许多种异常，内核必须为每一种异常提供一个专门地异常处理程序，对于某些异常，CPU控制单元在开始执行异常处理程序前会产生一个硬件出错码，并押入内核态堆栈。

下面列举了一些常用的异常：

异常         | 说明
------------ | -------------
0            | 当一个程序试图执行整数被0除操作时产生
1            | 设置eflags的TF标志或者一条指令或操作数地地址落在一个活动debug寄存器范围内
2            | 为非屏蔽中断保留，但没有使用
3            | 由int3（断点）指令引起，通常由debugger插入
4            | 当eflags地OF标志被设置时，into检查溢出指令被执行
5            | 对于有效地址范围之外地操作数，检查地址边界指令被执行
6            | CPU执行单元监测到一个无效地操作码
7            | 随着cr0地TS标志被设置，ESCAPE、MMX或XMM指令被执行
8            | 正常情况下，当CPU正试图为前一个异常调用处理程序时，同时又检测到一个异常，两个异常能被串行地处理，然而，在少数情况下，处理器不能串行地处理它们，因而产生这个异常。
9            | 因外部地数字协处理器引起地问题
10           | CPU试图让一个上下文切换到无效的TSS进程 
11           | 引用一个不存在的内容段
12           | 试图超过栈段界限地指令，或者由ss标识地段不在内存
13           | 违反了80x86保护模式下的保护规则
14           |寻址地页不在内存，相应的页表项为空，或者违反了一种分页保护机制
15           | 由Intel保留
16           | 集成到CPU芯片中地浮点单元用信号通知一个错误情形，如数字溢出
17           | 操作地地址没有被正确地对齐
18           | 机器检查机制检测到一个CPU错误或总线错误
19           | 集成到CPU芯片中地SSE或SSE2单元对浮点操作用信号通知一个错误情形
20-31        | 这些值由Intel留作将来开发

下面列举了一些常用地异常处理程序和信号：


异常         | 处理程序                         | 信号
------------ | -------------                  | ------------
0            | divide_error()                 | SIGFPE
1            | debug()                        | SIGTRAP
2            | nmi()                          | None
3            | int3()                         | SIGTRAP
4            | overflow()                     | SIGSEGV
5            | bounds()                       | SIGSEGV
6            | invalid_op()                   | SIGILL
7            | device\_not\_available()       | None
8            | doublefault_fn()               | None
9            | coprocessor\_segment\_overrun()| SIGFPE
10           | invalid_tss()                  | SIGSEGV
11           | segment\_not\_present()        | SIGBUS
12           | stack_segment()                | SIGBUS
13           | general_protection()           | SIGSEGV
14           | page_fault()                   | SIGSEGV
15           | None                           | None
16           | coprocessor_error()            | SIGFPE
17           | alignment_check()              | SIGSEGV
18           | machine_check()                | None
19           | simd\_coprocessor\_error()     | SIGFPE
