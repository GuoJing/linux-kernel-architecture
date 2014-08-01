---
layout:    post
title:     页及其描述符
category:  内存管理
description: 内存组织...
tags: 内存 UMA NUMA 页描述符 page
---
内存管理是内核中最为复杂的一部分，我之前想要跳过这里了解后面的内容，而且我确实看书看到比较后面，但最后还是得回来看内存管理这一部分，因为不仅仅内存需要进行内存管理，进程调度等算法也涉及到内存管理，所以没办法还得看。内存管理涵盖了许多领域，是一个旷日持久的学习过程。这一部分可能会涉及很多的代码，但我自己不一定能够全部理解。

内存管理涉及的领域有：

1. 内存中的物理内存页的管理。
2. 分配大块内存的伙伴系统。
3. 分配较小内存的slab、slub和slob分配器。
4. 分配非连续内存块的vmalloc机制。
5. 进程的地址空间。

之前的笔记里有[进程的地址空间](/linux-kernel-architecture/posts/task-size/)和[内存管理](/linux-kernel-architecture/posts/mm-management/)的基本知识，需要了解，如果对于细节不感兴趣的话，我觉得可以跳过。不过也没有什么可看的了，基本的内存和进程知识前面的笔记也说的很详细了。

我们知道，Linux内核一般将处理器的虚拟地址空间划分为两个部分，底部比较大的部分用于用户进程，顶部则用于内核。虽然上下文切换期间会修改底部的用户进程部分，但虚拟地址空间的内核部分总是保持不变。地址空间在用户进程和内核之间划分的典型比例为3:1。给出4GB的虚拟地址空间，3GB将用于用户空间而1GB而用于内核。

可用的物理内存将映射到内核的地址空间中。访问内存时，如果所用的虚拟地址与内核区域的起始地址之间的偏移量不超过可用物理内存的长度，那么该虚拟地址会自动关联到物理页帧。不过，还有一个问题，虚拟地址空间的内核部分必然小于CPU理论地址空间的最大长度。如果物理内存比可以映射到内核地址空间的数量要多，那么内核必须借助高端内存方法来管理多的内存。普通的32位80x86系统上，可以直接接管的物理内存数量不超过896MB，超过最大4GB的内存只能通过高端内存寻址[^1]。在64位计算机上，由于可用的地址空间非常巨大，因此不需要高端内存模式[^3]。

[^1]: 具体可以参考内存寻址里的PAE机制。

一般情况下，有两种计算机，分别为UMA和NUMA计算机来管理物理内存，虽然之前的笔记已经提到过，这里再拿出来。

{:.center}
![numa](/linux-kernel-architecture/images/numa.png){:style="max-width:600px"}

{:.center}
UMA和NUMA

（1）：UMA计算机（*一致内存访问，uniform memory access*）将可用内存以连续方式组织起来，系统中的每个处理器访问各个内存都是同样的块。

（2）：NUMA计算机（*非一致内存访问，non uniform memory access*）总是多处理器计算机。系统的各个CPU都有本地内存，可支持特别快的访问，各个处理器之间通过总线连接起来。

在UMA系统上，值使用一个NUMA节点来管理系统内存，所以首先考虑NUMA系统，这样UMA系统就比较好理解了。两种类型的计算机的混合也是可能的，其中使用不连续的内存。在UMA系统中，内存不是连续的，而会有比较大的洞。在这里应用NUMA体系结构的原理会有帮助，可以使内核的内存访问更简单。

实际上内核会区分3种内存管理的配置选项，FLATMEM、DISCOUNTIGMEM和SPARSEMEM[^2]。真正的NUMA会设置配置选项CONFIG_NUMA，相关的内存管理代码也有很大的不同。

[^2]: 实际上这种方式不太稳定，但有一些性能优化。

[^3]: 只有内核自身使用高端内存页的时候才会有问题，在内核使用高端内存页之前，必须使用kmap和kunmap函数将其映射到内核虚拟地址中，对普通内存页这是不必的。对用户空间进程来说，是否是高端内存页没有任何差别，因为用户进程总是通过页表访问内存。

### 页描述符 ###

内核必须记录每个页框当前的状态，例如，内核必须能够区分哪些页框包含的是属于进程的页而哪些页框包含的是内核代码或内核数据。类似的，内核还必须能够确定动态内存中的页框是否空闲。如果动态内存中的页框不包含有用的数据，那么这个页框就是空的。

页框的状态信息保存在一个类型为*page*的页描述符中，虽然在前面的内存寻址里的笔记里有列出，但代码再列出来如下，记录一些详细的字段。

#### <include/linux/mm_types.h> ####

{% highlight c++ %}
struct page {
    unsigned long flags;
    atomic_t _count;
    union {
        /* Count of ptes mapped in mms,
         * to show when page is mapped
         * & limit reverse map searches.
         */
        atomic_t _mapcount;
        /* SLUB */
        struct {
            u16 inuse;
            u16 objects;
        };
    };
    union {
        struct {
        unsigned long private;
        struct address_space *mapping;
        };
#if USE_SPLIT_PTLOCKS
        spinlock_t ptl;
#endif
        struct kmem_cache *slab;
        struct page *first_page;
    };
    union {
        pgoff_t index;
        void *freelist;
    };
    struct list_head lru;
#if defined(WANT_PAGE_VIRTUAL)
    void *virtual;
#endif
#ifdef CONFIG_WANT_PAGE_DEBUG_FLAGS
    unsigned long debug_flags;
#endif

#ifdef CONFIG_KMEMCHECK
    void *shadow;
#endif
};
{% endhighlight %}

其中各个字段的意义如下：

{:.table_center}
字段名             | 说明
------------      | -------------
flags             | 一组标志，对页框所在的管理区进行编号
_count            | 页框的引用计数器
_mapcount         | 页框中的页表项数目，如果没有则为-1
private           | 可用于正在使用页的内核成分
mapping           | 当页被插入页高速缓存中的时候使用
index             | 作为不同的含义被几种内核成分使用
lru               | 包含页的最近最少使用（LRU）双向链表的指针

其中重要的两个字段为*_count*和*flags*。*_count*是页的引用计数器，如果字段为-1，则相应的页框空闲，并可以被分配给任意一个进程甚至内核本身，如果该字段大于或等于-，则说明页框被分配给了一个或多个进程，用于存放一些内核数据结构。*flags*包含多大32个用来描述页框标志的状态，对于每个PG_xxx标志内核都定义了操作其值的一些宏。

{:.table_center}
标志名             | 说明
------------      | -------------
PG_locked         | 页被锁定
PG_error          | 在传输过程中发生I/O错误
PG_referenced     | 刚刚访问过的页
PG_uptodate       | 在完成读操作后置位
PG_dirty          | 页已经被修改
PG_lru            | 页在活动或非活动页链表中
PG_active         | 页在活动页链表中
PG_slab           | 包含在slab中的页框
PG_highmem        | 页框属于ZONE\_HIGHMEM管理区
PG_checked        | 由一些文件系统使用的标识
PG\_arch\_1       | 在80x86体系结构上没有使用
PG_reserved       | 页框留给内核代码或没有使用
PG_private        | 页描述符的private字段存放了有意义的数据
PG_writeback      | 页正在使用writepage方法将页写到磁盘上
PG_nosave         | 系统挂起/唤醒时使用
PG_compound       | 通过扩展分页机制处理页框
PG_swapcache      | 页属于对换高速缓存
PG_mappedtodisk   | 页框中的所有数据对应于磁盘上分配的块
PG_reclaim        | 为回收内存对页已经做了写入磁盘标记
PG\_nosave\_free  | 系统挂起/恢复时使用

所有的页描述符存放在*mem_map*数组中。因为每个描述符的长度为32字节，所以*mem_map*所需要的空间略小于整个RAM的1%。*virt_to_page(addr)*宏产生线性地址*addr*对应的页描述符地址。

#### <include/linux/mmzone.h> ####

{% highlight c++ %}
#ifndef CONFIG_DISCONTIGMEM
extern struct page *mem_map;
#endif{% endhighlight %}