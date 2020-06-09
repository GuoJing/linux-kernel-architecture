---
layout:    post
title:     分区页框分配器
category:  内存管理
description: 分区页框分配器...
tags: 分区 页框 页框分配器
---
内核有一个子系统，称之为分区页框分配器（*zoned page frame allocator*），这个子系统处理对连续页框组的内存分配请求，其主要组成如下。

![numa](images/page_frame_alloc.png)
内存管理区分配器示意图

其中，管理区分配器接受动态内存分配与释放的请求，再请求分配的情况下，该部分搜索一个能满足所有请求的一组连续页框内存的管理区。在每个管理区内，页框被名为『伙伴系统』的部分来处理，为大刀更好的系统性能，一小部分页框保留在高速缓存中用于快速地满足对单个页框分配的请求。

请求和释放页框的几个重要函数如下，如果分配成功，则返回一个分配页的线性地址，如果分配失败，则返回NULL。

### 分配页框 ###

分配页框一般使用*alloc_pages*，如果分配失败则返回NULL，可以通过参数*gfp_mask*指定寻找的方法。

函数名                  | 说明
------------           | -------------
alloc_pages            | 申请一个连续的页框，返回第一个所分配的页框描述符的地址
alloc_page             | 用于获得一个页框的宏
\_\_get_\_free\_pages  | 类似于alloc\_pages，但返回第一个所分配页的线性地址
\_\_get_free\_page     | 用于获得一个单独的页框的宏
get\_zeroed\_page      | 用来获取填满0页框的宏，返回所获取页框的线性地址
\_\_get\_dma\_pages    | 用这个宏获得适用于DMA的页框

alloc\_pages函数的完整带参数是alloc\_pages(gfp\_mask, order)，其中order是次方，用于请求2^order个连续的页框。gfp\_mask是一组标志，它指明了如何寻找空闲的页框，gfp\_mask标志如下。

标志名                  | 说明
------------           | -------------
\_\_GFP\_DMA           | 所请求的页框必须处于ZONE\_DMA管理区
\_\_GFP\_HIGHMEM       | 所请求的页框必须处于ZONE\_HIGHMEM管理区
\_\_GFP\_WAIT          | 允许内核对等待空闲页框的当前进程进行阻塞
\_\_GFP\_HIGH          | 允许内核访问保留的页框池
\_\_GFP\_IO            | 允许内核再地段内存页上执行I/O传输以释放页框
\_\_GFP\_FS            | 如果为0，则不允许内核执行依赖于文件系统的操作
\_\_GFP\_COLD          | 所请求的页框可能为冷页
\_\_GFP\_NOWARN        | 一次内存分配失败将不产生警告信息
\_\_GFP\_REPEAT        | 内核重试内存分配直到成功
\_\_GFP\_NOFAIL        | 与\_\_GFP\_REPEAT相同
\_\_GFP\_NORETRY       | 一次内存分配失败后不再重试
\_\_GFP\_NO\_GROW      | slab分配器不允许增大slab高速缓存
\_\_GFP\_COMP          | 属于扩展页的页框
\_\_GFP\_ZERO          | 返回任何的页框必须被填满0

实际上，Linux大多数都是用的组合值，而不是单独的某一个值。所以gfp\_mask参数如下：

标志名                  | 说明
------------           | -------------
GFP_ATOMIC             | \_\_GFP\_HIGH
GFP_NOIO               | \_\_GFP\_WAIT
GFP_NOFS               | \_\_GFP\_WAIT \| \_\_GFP\_IO
GFP_KERNEL             | \_\_GFP\_WAIT \| \_\_GFP\_IO \| \_\_GFP\_FS
GFP_USER               | \_\_GFP\_WAIT \| \_\_GFP\_IO \| \_\_GFP\_FS
GFP_HIGHUSER           | \_\_GFP\_WAIT \| \_\_GFP\_IO \| \_\_GFP\_FS \| \_\_GFP\_HIGHMEM

### 释放页框 ###

下面几个函数中的任何一个宏都可以释放页框，但是有细微的差别：

函数名                  | 说明
------------           | -------------
\_\_free\_pages        | 该函数首先检查page指向的页描述符（*page*），如果该页框未被保留，就把描述符的count字段减1，如果count变为0，就假定从page对应的页框开始的一段连续的页框不再被使用。在这种情况下，该函数释放页框。
free_pages             | 释放页框
\_\_free\_page         | 释放单个页框
free_page              | 释放单个页框
