---
layout:    post
title:     内存碎片
category:  内存管理
description: 内存碎片...
tags: 反碎片 内存碎片 伙伴系统
---
虽然伙伴系统的让内存管理变得简单，但是会造成另外一个问题，就是内存碎片。内存碎片是非常重要的问题因为如果长期占用不同大小的内存产生了内存碎片，则在申请内存的时候会引发缺页异常，但是实际上，依旧有很多的空闲的内存可供使用。

{:.center}
![system](/linux-kernel-architecture/images/memory-fragmentation.png){:style="max-width:500px"}

正如上图所示，上图有非常多的剩余空间，但因为内存碎片的问题，当系统需要申请4个内存页的时候，就无法申请内存了，虽然我们的内存空间里剩余内存的数量远远大于4个内存页，但无法找到连续的4个内存页，则会产生一个缺页异常。

而对于理想情况下的内存而言，应该如下图中的图例所示，对于一个程序，在其可用的内存地址空间内，不应该存在大片的不连续的内存，应该说，对于应用程序看到的内存区而言，总应该是连续的。

我们谈到内存碎片的时候，大多数只涉及到内核，因为对于内核而言，内存碎片确实是一个非常大的问题。虽然大多数现代的CPU都提供了巨型的页使用，但解决内存碎片依旧对内存使用密集型的应用程序有好处。在使用更大的页的时候，地址转换后备缓冲器只需处理较少的项，降低了TLB缓存失效的可能性。但巨型页的分配依旧需要连续的空闲物理内存。

### 反碎片 ###

在2.6.24版本开发中，防止碎片的方法最终加入到内核，内核认为预防比治疗更加有效，所以内核使用**反碎片**（*anti-fragmentation*）的方法试图从最开始尽可能的防止碎片。

内核已经将已分配的页划分为以下3种类型：

1. 不可移动的页：在内存中有固定位置，不能移动到其他地方，例如内核。
2. 可回收的页：不能直接移动，但可以删除，其内容可以从某些源重新生成，例如映射自文件系统的数据。
3. 可移动的页：可以随意地移动，属于用户空间和应用程序的页属于这个类别，它们是通过页表映射的，如果它们复制到新的位置，页表项可以相应的更新，而不会影响到应用程序。

页的可移动性依赖页属于以上3种类别中的哪一种，内核使用的反碎片技术基于将具有相同可移动性分组的思想。也就是说可移动的页和可移动的页具有相同的分组，相同，不可移动的页和不可移动的页具有相同的分组。

但要注意的是，从最初开始，内存并未划分成可移动页等不同移动性的不同的区，这些是在运行时行程的，内核的另一种方法确实将内存划分为不同的区，分别用于可移动页和不可移动页的分配。

内核使用一些宏来表示不同的迁移类型：

#### <include/linux/mmzone.h> ####

{% highlight c++ %}
#define MIGRATE_UNMOVABLE     0
#define MIGRATE_RECLAIMABLE   1
#define MIGRATE_MOVABLE       2
#define MIGRATE_PCPTYPES      3
#define MIGRATE_RESERVE       3
#define MIGRATE_ISOLATE       4 /* can't allocate from here */
#define MIGRATE_TYPES         5
{% endhighlight %}

其中变量的意义如下：

{:.table_center}
字段名               | 说明
------------        | -------------
MIGRATE_UNMOVABLE   | 不可移动内存区
MIGRATE_RECLAIMABLE | 可回收内存区
MIGRATE_MOVABLE     | 可移动内存区
MIGRATE_PCPTYPES    | 在PCP列表上类型的数量
MIGRATE_RESERVE     | 如果向具有特定的内存区的内存分配失败，则可以从此内存区分配内存
MIGRATE_ISOLATE     | 不能通过这个区域申请内存，这是一个特殊的虚拟区域，用于跨越NUMA结点移动物理内存页。
MIGRATE_TYPES       | 代表迁移类型的数目，不代表具体的区域

对伙伴系统数据结构的主要调整，是将空闲列表分解为*MIGRATE_TYPES*个列表：

#### <include/linux/mmzone.h> ####

{% highlight c++ %}
struct free_area {
    struct list_head    free_list[MIGRATE_TYPES];
    unsigned long       nr_free;
};
{% endhighlight %}

其中*nr_free*统计了所有页表上空闲页的数目，而每种迁移类型都对应一个空闲列表。如果内核无法满足针对某一给定迁移类型的分配请求，则内核提供了一个备用列表，指定了列表中无法满足分配请求时，接下来使用哪种迁移类型。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static int fallbacks[MIGRATE_TYPES][MIGRATE_TYPES-1] = {
    [MIGRATE_UNMOVABLE]   = { MIGRATE_RECLAIMABLE,
                              MIGRATE_MOVABLE,
                              MIGRATE_RESERVE },
    [MIGRATE_RECLAIMABLE] = { MIGRATE_UNMOVABLE,
                              MIGRATE_MOVABLE,
                              MIGRATE_RESERVE },
    [MIGRATE_MOVABLE]     = { MIGRATE_RECLAIMABLE,
                              MIGRATE_UNMOVABLE,
                              MIGRATE_RESERVE },
    [MIGRATE_RESERVE]     = { MIGRATE_RESERVE,
                              MIGRATE_RESERVE,
                              MIGRATE_RESERVE }, /* Never used */
};
{% endhighlight %}

在内核想要分配不同的移动页时，如果对应链表为空，则后退到可回收页链表，接下来再到可移动页链表，最后到紧急分配链表。

### 虚拟可移动内存区 ###

依据可移动性组织页是防止物理内存碎片的一种可能方法，内核还提供了另一种组织该问题的手段，虚拟内存域*ZONE_MOVABLE*。这个机制和可移动性分组框架相比，*ZONE_MOVABLE*必须由管理员显式激活。

*ZONE_MOVABLE*的基本思想很简单，可用的物理内存划分为两个内存域，一个用于可移动分配，一个用于不可移动分配。这会自动防止不可移动页向可移动内存域引入碎片。

不过这也会造成另一个问题，内存如何在两个竞争的区域之间分配可用内存？这显然对内核要求太高，所以管理员必须做出决定。这个数据结构是我们非常熟悉的*zone_type*数据结构。

#### <include/linux/mmzone.h> ####

{% highlight c++ %}
enum zone_type {
#ifdef CONFIG_ZONE_DMA
    ZONE_DMA,
#endif
#ifdef CONFIG_ZONE_DMA32
    ZONE_DMA32,
#endif
    ZONE_NORMAL,
#ifdef CONFIG_HIGHMEM
    ZONE_HIGHMEM,
#endif
    ZONE_MOVABLE,
    __MAX_NR_ZONES
};
{% endhighlight %}

取决于体系结构和配置，其中*ZONE_MOVABLE*可能位于任何区域，甚至是高端内存区域。与系统中其他的内存区相反，*ZONE_MOVABLE*从不关联到任何硬件上有意义的内存范围，实际上，该内存域中的内存取自高端内存域或者是普通内存域，所以*ZONE_MOVABLE*是一个虚拟内存域。

从物理内存域中提取多少内存用于*ZONE_MOVABLE*必须考虑下面的情况：

1. 用于不可移动分配的内存会平均分布到所有的内存节点上。
2. 只使用来自最高内存域的内存[^1]。

以上情况所起到的结果是：

1. 用于为虚拟内存域ZONE\_MOVABLE提取内存页的物理内存域，保存在全局变量*movable_zone*中。
2. 对每个节点来说，*zone_movable_pfn[node_id]*表示*ZONE_MOVABLE*在*movable_zone*内存域中所取得内存的起始地址。

[^1]: 在32位系统上，这可能是ZONE_HIGHMEM，但对于64系统，可能是ZONE_NORMAL或ZONE_DMA32。