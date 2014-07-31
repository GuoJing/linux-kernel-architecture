---
layout:    post
title:     slab数据结构
category:  内存管理
description: slab数据结构...
tags: slab
---
为了实现slab分配器，需要各种数据结构，尽管看上去呢并不困难，相关的代码并不总是容易阅读或理解的，这是因为学多内存区需要使用指针运算和类型转换进行操作，这些可不是C语言中以清晰简明著称的领域。由于slab系统带有大量的调试选项，所以代码中遍布着预处理器语句，其中一些如下列出：

危险区（*Red Zoning*）

在每个对象的开始和结束处增加一个额外的内存区，其中填充已知的字节模式，如果模式被修改，程序员在分析内核内存时注意到，可能某些代码访问了不属于它们的内存区。

对象毒化（*Object Poisoning*）

在建立和释放slab时，将对象用预定义的模式填充，如果在对象分配时注意到该模式已经改变，程序员就知道已经发生了未授权的访问。

为了简明，我们可以关注整体而不是细节，所以我们只关注一个纯粹的slab分配器。

### 数据结构 ###

每个缓存由*kmem_cache*结构的一个实例表示，代码如下：

#### <include/linux/slab_def.h> ####

{% highlight c++ %}
struct kmem_cache {
/* 1) per-CPU数据，在每次分配和释放的时候都会访问 */
    struct array_cache *array[NR_CPUS];
/* 2) 可调整的缓存的参数，由cache_chain_mutex保护 */
    unsigned int batchcount;
    unsigned int limit;
    unsigned int shared;

    unsigned int buffer_size;
    u32 reciprocal_buffer_size;
/* 3) 在后端每次分配和释放内存时访问 */

    unsigned int flags;     /* 常数标志 */
    unsigned int num;       /* 每个slab中对象的数量 */

/* 4) 缓存的增长和缩减 */
    /* 每个slab中的页数，取以2为底数的对数 */
    unsigned int gfporder;

    /* 强制内存区域的GFP标志, 比如GFP_DMA */
    gfp_t gfpflags;

    size_t colour;          /* 缓存着色范围 */
    unsigned int colour_off;    /* 着色的偏移量 */
    struct kmem_cache *slabp_cache;
    unsigned int slab_size;
    unsigned int dflags;        /* 动态标志 */

    /* 构造函数 */
    void (*ctor)(void *obj);

/* 5) 创建和移除缓存 */
    const char *name;
    struct list_head next;

/* 6) 统计 */
#ifdef CONFIG_DEBUG_SLAB
    unsigned long num_active;
    unsigned long num_allocations;
    unsigned long high_mark;
    unsigned long grown;
    unsigned long reaped;
    unsigned long errors;
    unsigned long max_freeable;
    unsigned long node_allocs;
    unsigned long node_frees;
    unsigned long node_overflow;
    atomic_t allochit;
    atomic_t allocmiss;
    atomic_t freehit;
    atomic_t freemiss;

    /*
     * DEBUG
     */
    int obj_offset;
    int obj_size;
#endif /* CONFIG_DEBUG_SLAB */

    /*
     * 静态定义的一些变量
     * /
    struct kmem_list3 *nodelists[MAX_NUMNODES];
    /*
     * 不要在nodelists后面写变量
     * 因为我们需要定义这个数组的长度到
     * nr_node_ids，而不是使用MAX_NUMNODES
     * 看 kmem_cache_init() 函数
     */
};
{% endhighlight %}

在开始的几个成员涉及每次分配期间内核对特定于CPU数据的访问，除此之外还有几个重要的变量需要关注：

字段                  | 说明
------------          | -------------
array                 | 是一个指向数组的指针，每个数组项都对应于系统中的一个CPU，每个数组项都包含了另一个指针，指向下文讨论的*array_cache*结构的实例
batchcount            |指定了在per-CPU列表为空的情况下，从缓存的slab中获取对象的数目，它还表示在缓存增长时分配的对象数目
limit                 | 指定了per-CPU列表中保存的对象的最大数目。如果超出了这个值，内核会将*batchcount*个对象返回到slab
buffer_size           | 指定了缓存中管理的对象的长度[^1]
gfporder              | 指定了slab包含的页数目以2为底的对数，简而言之，slab包含2^gfporder页
colorur               | 指定了颜色的最大数目
colorur_next          | 则时内核建立的下一个slab的颜色
colour_off            | 基本偏移量乘以颜色值获得的绝对偏移量
dflags                | 另一标志集合，描述slab的动态性质。
ctor                  | 一个指针，指向在对象创建时调用的构造函数。
name                  | 一个字符串，表示缓存的名称
next                  | 是一个标准链表元素

假定内核有一个指针指向slab中的一个元素，而需要确定对应的对象索引，最容易的方法是将指针指向对象地址，减去slab内存区的起始地址，然后将获得的对象偏移量，除以对象的长度。

考虑一个例子，一个slab内存区起始于内存位置100，每个对象需要5个字节，则，上文所述的对象位于内存位置115。对象和slab的起始处之间的偏移量为115-100=15，因此对象索引时15/5=3。

由于乘法在计算机上快得多，所以内核使用所谓的[Newton-Raphson](http://en.wikipedia.org/wiki/Newton's_method)方法，这只需要乘法和位移，虽然我们对数学细节并不关系，但我们需要知道，内核可以不计算C=A/B，而是使用*C=reciprocal_divide(A, reciprocal_value(B))*的方式，后者涉及的两个函数都是库程序，由于特定slab中的对象长度时恒定的，内核可以将*buffer_size*的*recpirocal*值存储在*recpirocal_buffer_size*中，该值可以在后续的除法算法中使用。

如果slab头部的管理数据存储在slab外部，则*slabp_cache*指向反派所需内存的一般性缓存。如果slab头部在slab上，则*slabp_cache*为NULL指针。

----

内核对每个系统处理器都提供了一个*array_cache*，代码如下：

#### <mm/slab.c> ###

{% highlight c++%}
struct array_cache {
    unsigned int avail;
    unsigned int limit;
    unsigned int batchcount;
    unsigned int touched;
    spinlock_t lock;
    void *entry[];  /*
             * 为了对齐array_cache，必须定义在这里
             */
};
{% endhighlight %}

[^1]: 如果启用了slab调试，buffer_size可能与对象的长度不同，因为每个对象都加入了额外的填充字节，在这种情况下，由另一个变量来表示对象的真正长度。

我们已经知道了*batchcount*和*limit*的语义，*kmem_cache_s*的值用作per-CPU值的默认值，用于缓存和重新填充或清空。

字段                  | 说明
------------          | -------------
avail                 | 保存了当前可用对象的数目，在从缓存移除一个对象时，将*touched*设置为1，而缓存收缩的时候，将*touched*设置为0。这使得内核能够确认在缓存上一次收缩之后是否被访问过，也是缓存重要性的一个标志
entry                 | 是一个伪数组，从注释中我们可以看到，其中并没有数组项，只是为了便于访问内存中*array_cache*实例之后缓存中的各个对象而已

再回头看*kmem_cache*后续的代码，其中*falgs*时一个标志寄存器，定义缓存的全局性质，当前只有一个标志位，如果管理结构存储在slab外部，则置*CFLAGS_OFF_SLAB*。

*objectsize*是缓存中对象的长度，包括用于对齐目的的所有填充字节。*num*保存了可以放入slab的对象的最大数目。*free_limit*指定了缓存在收缩之后空闲对象的上限。

除了以上这些变量，还有一个必须说明，就是*nodelists*。*nodelists*是一个数组，每个数组项对应于系统中一个可能的内存节点，每个数组项都包含*kmem_list3*的一个实例，该结构中有三个slab列表，正如我们之前笔记所说的，包含完全用尽、空闲和部分空闲的三个slab列表。

这个成员必须置于结构的末尾，尽管数组形式化总是有*MAX_NUMNODES*项，但在NUMA计算机上实际可用的结点数目可能会少一些。因而该数组需要的项也会变少，内核在运行时对该结构分配比理论上更少的内存，就可以缩减该数组的项数。

但在UMA计算机上，这就不是问题，因为只有一个可用结点。

----

用于管理slab链表的表头保存在一个独立的数据结构中，称为*kmem_list3*，代码如下：

#### <mm/slab.c> ###

{% highlight c++%}
struct kmem_list3 {
    /* 首先是部分空闲链表，用于生成性能更好的汇编代码 */
    struct list_head slabs_partial;
    struct list_head slabs_full;
    struct list_head slabs_free;
    unsigned long free_objects;
    unsigned int free_limit;
    unsigned int colour_next;   /* 各个节点的缓存着色 */
    spinlock_t list_lock;
    struct array_cache *shared; /* 结点内存共享 */
    struct array_cache **alien; /* 在其他节点上 */
    unsigned long next_reap;    /* 无需锁就可以更新的变量 */
    int free_touched;       /* 同上 */
};
{% endhighlight %}

其中*free_objects*表示*slabs_partial*和*slabs_free*的所有slab中空闲对象的总数，*free_touched*表示缓存是否是active的，在从缓存获取一个对象时，内核将改变变量的值并设置为1。在缓存收缩时，重置为0。但内核只有在*free_touched*预先设置为0时，才会收缩内存[^2]。

[^2]: 并且free_couthced变量适用于整个缓存，而不同于per-CPU变量的touched。

除了这些重要的字段以外，还有其他重要的字段如下。

字段                  | 说明
------------          | -------------
next_reap             | 定义了内核在两次尝试搜索缓存之间，必须经过的时间间隔，其想法时防止由于频繁的缓存收缩和增长操作而降低系统的性能，这种操作可能在某些系统负荷下发生
free_limit            | 指定了所有slab上容许未使用对象的最大数目
free_objects          | 所有未使用对象
colorur_next          | 各个节点的缓存着色
