---
layout:    post
title:     分配页
category:  内存管理
description: 分配页...
tags: 页 分配页 伙伴系统
---
无论外部使用什么函数和接口分配一个页，最终分配页的函数会调用到*alloc_pages_node*函数，这个函数是伙伴系统里主要的函数。伙伴系统还需要了解一些[页框分配器](/linux-kernel-architecture/posts/page-frame-allocator/)的知识。

#### <include/linux/gfp.h> ####

{% highlight c++ %}
static inline struct page *alloc_pages_node(int nid, 
    gfp_t gfp_mask,
    unsigned int order)
{
    /* 未知结点就是当前结点 */
    if (nid < 0)
        nid = numa_node_id();

    return __alloc_pages(gfp_mask,
                         order,
                         node_zonelist(nid, gfp_mask));
}
{% endhighlight %}

这里执行了一个简单的检查，避免分配过大的内存块，如果指定负结点的ID，那么结点就不存在，内核自动使用当前执行CPU对应的结点ID。接下来的工作委托给*\_\_alloc_pages*函数。而实际上*\_\_alloc_pages*函数调用了*__alloc_pages_nodemask*函数。

### 调用函数 ###

内核源代码将*__alloc_pages_nodemask*函数作为『伙伴系统的心脏』。我们可以直接找到代码如下：

#### <mm/page_alloc.c> ####

{% highlight c++ %}
struct page *
__alloc_pages_nodemask(gfp_t gfp_mask, unsigned int order,
            struct zonelist *zonelist, nodemask_t *nodemask)
{
    enum zone_type high_zoneidx = gfp_zone(gfp_mask);
    struct zone *preferred_zone;
    struct page *page;
    int migratetype = allocflags_to_migratetype(gfp_mask);

    gfp_mask &= gfp_allowed_mask;

    lockdep_trace_alloc(gfp_mask);

    might_sleep_if(gfp_mask & __GFP_WAIT);

    if (should_fail_alloc_page(gfp_mask, order))
        return NULL;

    if (unlikely(!zonelist->_zonerefs->zone))
        return NULL;

    first_zones_zonelist(zonelist,
                         high_zoneidx,
                         nodemask,
                         &preferred_zone);
    if (!preferred_zone)
        return NULL;

    /* 
       是伙伴系统的一个重要的辅助函数
       它通过标志集和分配阶来判断是否能够进行分配
       如果可以，则发起实际的分配操作
    */
    page = get_page_from_freelist(gfp_mask|__GFP_HARDWALL,
            nodemask, order,
            zonelist, high_zoneidx, ALLOC_WMARK_LOW|ALLOC_CPUSET,
            preferred_zone, migratetype);
    if (unlikely(!page))
        page = __alloc_pages_slowpath(gfp_mask, order,
                zonelist, high_zoneidx, nodemask,
                preferred_zone, migratetype);

    trace_mm_page_alloc(page, order, gfp_mask, migratetype);
    return page;
}
EXPORT_SYMBOL(__alloc_pages_nodemask);
{% endhighlight %}

其中*get_page_from_freelist*是伙伴系统页分配里一个非常重要的函数，它通过标志集和分配阶来判断是否能够进行分配，如果可以，则发起实际的分配操作。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static struct page *
get_page_from_freelist(gfp_t gfp_mask, nodemask_t *nodemask,
        unsigned int order, struct zonelist *zonelist,
        int high_zoneidx, int alloc_flags,
        struct zone *preferred_zone, int migratetype)
{
    struct zoneref *z;
    struct page *page = NULL;
    int classzone_idx;
    struct zone *zone;
    nodemask_t *allowednodes = NULL;
    int zlc_active = 0;
    int did_zlc_setup = 0;

    classzone_idx = zone_idx(preferred_zone);
zonelist_scan:
    /*
     * 扫描zonelist，寻找具有足够空间的内存域
     */
    for_each_zone_zonelist_nodemask(zone, z, zonelist,
                        high_zoneidx, nodemask) {
        if (NUMA_BUILD && zlc_active &&
            !zlc_zone_worth_trying(zonelist, z, allowednodes))
                continue;
        if ((alloc_flags & ALLOC_CPUSET) &&
            !cpuset_zone_allowed_softwall(zone, gfp_mask))
                goto try_next_zone;

        BUILD_BUG_ON(ALLOC_NO_WATERMARKS < NR_WMARK);
        if (!(alloc_flags & ALLOC_NO_WATERMARKS)) {
            unsigned long mark;
            int ret;

            mark = zone->watermark[alloc_flags & ALLOC_WMARK_MASK];
            if (zone_watermark_ok(zone, order, mark,
                    classzone_idx, alloc_flags))
                goto try_this_zone;

            if (zone_reclaim_mode == 0)
                goto this_zone_full;

            ret = zone_reclaim(zone, gfp_mask, order);
            switch (ret) {
            case ZONE_RECLAIM_NOSCAN:
                /* 不扫描 */
                goto try_next_zone;
            case ZONE_RECLAIM_FULL:
                /* 扫描到了但是这个内存域不能使用 */
                goto this_zone_full;
            default:
                /* 通过zone_watermark_ok水印判断是否足够 */
                if (!zone_watermark_ok(zone, order, mark,
                        classzone_idx, alloc_flags))
                    goto this_zone_full;
            }
        }

try_this_zone:
        // ...
this_zone_full:
        // ...
try_next_zone:
        // ...
    }

    if (unlikely(NUMA_BUILD && page == NULL && zlc_active)) {
        zlc_active = 0;
        goto zonelist_scan;
    }
    return page;
}
{% endhighlight %}

*zone_watermark_ok*函数用来检查标志，这个函数根据设置的标志判断是否能从给定的内存域内分配内存。这是一个比较重要的函数。

在跟入*zone_watermark_ok*函数之前，需要定义一些函数使用的标志，用于控制到达各个水印指定的临界状态时的行为。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
#define ALLOC_WMARK_MIN     WMARK_MIN
#define ALLOC_WMARK_LOW     WMARK_LOW
#define ALLOC_WMARK_HIGH    WMARK_HIGH
#define ALLOC_NO_WATERMARKS 0x04

#define ALLOC_WMARK_MASK    (ALLOC_NO_WATERMARKS-1)

#define ALLOC_HARDER        0x10
#define ALLOC_HIGH          0x20
#define ALLOC_CPUSET        0x40
{% endhighlight %}

其中字段及其意义如下：

{:.table_center}
字段名                  | 说明
------------           | -------------
ALLOC\_WMARK\_MIN      | 使用pages_min水印
ALLOC\_WMARK\_LOW      | 使用pages_low水印
ALLOC\_WMARK\_HIGH     | 使用pages_high水印
ALLOC\_NO\_WATERMARKS  | 不检查水印
ALLOC\_WMARK\_MASK     | 获取水印的比特位
ALLOC\_HARDER          | 试图更努力的分配，放宽限制
ALLOC\_HIGH            | 设置了\_\_GFP\_HIGH
ALLOC\_CPUSET          | 检查内存结点是否对应指定的CPU集合

前几个标志表示在判断页是否可分配时，需要考虑哪些水印。默认情况下，只有内存域包含页的数目至少为zone->pages\_high时，才能分配页。

我们再回到*get_page_from_freelist*函数，通过*zone_watermark_ok*得到查找的内存域是否能够分配可用的内存之后，如果成功，则走到*try_this_zone*。

我们可以看看*try_this_zone*的代码：

#### <mm/page_alloc.c> ####

{% highlight c++ %}
try_this_zone:
        page = buffered_rmqueue(preferred_zone, zone, order,
                        gfp_mask, migratetype);
        if (page)
            break;
{% endhighlight %}

我们看到如果内存域适用于分配内存，那么*buffered_rmqueue*试图分配所需的数目的页。当然，如果分配成功，则返回相应的页，否则选择备用列表的下一个内存域。

### 实际分配 ###

我们从上面的代码可以看到，如果分配页成功的话，*\_\_alloc_pages_nodemask*最后走到函数*\_\_alloc_pages_slowpath*。这个函数的代码如下：

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static inline struct page *
__alloc_pages_slowpath(gfp_t gfp_mask, unsigned int order,
    struct zonelist *zonelist, enum zone_type high_zoneidx,
    nodemask_t *nodemask, struct zone *preferred_zone,
    int migratetype)
{
    const gfp_t wait = gfp_mask & __GFP_WAIT;
    struct page *page = NULL;
    int alloc_flags;
    unsigned long pages_reclaimed = 0;
    unsigned long did_some_progress;
    struct task_struct *p = current;

    /* 检查阶是否大于系统最大阶 */
    if (order >= MAX_ORDER) {
        WARN_ON_ONCE(!(gfp_mask & __GFP_NOWARN));
        return NULL;
    }

    if (NUMA_BUILD && (gfp_mask & GFP_THISNODE) == GFP_THISNODE)
        goto nopage;

restart:
    /* 唤醒所有的kswapd进程 */
    wake_all_kswapd(order, zonelist, high_zoneidx);
    /* 唤醒进程之后设置gfp设置，这个地方更加复杂 */
    alloc_flags = gfp_to_alloc_flags(gfp_mask);

rebalance:
    /* 在goto nopage之前的尝试，再次查找空闲的页 */
    page = get_page_from_freelist(gfp_mask,
            nodemask, order, zonelist,
            high_zoneidx, alloc_flags & ~ALLOC_NO_WATERMARKS,
            preferred_zone, migratetype);
    if (page)
        goto got_pg;

    /* 如果完全不检查水印的话 */
    if (alloc_flags & ALLOC_NO_WATERMARKS) {
        page = __alloc_pages_high_priority(gfp_mask, order,
                zonelist, high_zoneidx, nodemask,
                preferred_zone, migratetype);
        if (page)
            goto got_pg;
    }

    /* 无法平衡则goto nopage */
    if (!wait)
        goto nopage;

    /* 如果page标志为PF_MEMALLOC */
    if (p->flags & PF_MEMALLOC)
        goto nopage;

    /* 如果没有设置重复分配内存直到成功，则goto nopage */
    if (test_thread_flag(TIF_MEMDIE) && !(gfp_mask & __GFP_NOFAIL))
        goto nopage;

    /* 直接申请页 */
    page = __alloc_pages_direct_reclaim(gfp_mask, order,
                    zonelist, high_zoneidx,
                    nodemask,
                    alloc_flags, preferred_zone,
                    migratetype, &did_some_progress);
    if (page)
        goto got_pg;

    /*
     * 如果实在没有办法申请内存，考虑使用OOM
     * OOM的意思为Out Of Memory
     */
    if (!did_some_progress) {
        if ((gfp_mask & __GFP_FS) && !(gfp_mask & __GFP_NORETRY)) {
            /* 如果oom_killer被关闭，则nopage */
            if (oom_killer_disabled)
                goto nopage;
            /* 最后再尝试一次 */
            page = __alloc_pages_may_oom(gfp_mask, order,
                    zonelist, high_zoneidx,
                    nodemask, preferred_zone,
                    migratetype);
            if (page)
                goto got_pg;

            if (order > PAGE_ALLOC_COSTLY_ORDER &&
                        !(gfp_mask & __GFP_NOFAIL))
                goto nopage;

            goto restart;
        }
    }

    /* 检查是否需要重试分配 */
    pages_reclaimed += did_some_progress;
    if (should_alloc_retry(gfp_mask, order, pages_reclaimed)) {
        /* Wait for some write requests to complete then retry */
        congestion_wait(BLK_RW_ASYNC, HZ/50);
        goto rebalance;
    }

nopage:
    if (!(gfp_mask & __GFP_NOWARN) && printk_ratelimit()) {
        printk(KERN_WARNING "%s: page allocation failure."
            " order:%d, mode:0x%x\n",
            p->comm, order, gfp_mask);
        dump_stack();
        show_mem();
    }
    return page;
got_pg:
    if (kmemcheck_enabled)
        kmemcheck_pagealloc_alloc(page, order, gfp_mask);
    return page;

}
{% endhighlight %}

可以看到内核进行了许多的尝试，当尝试失败之后，会进入OOM（*out of memory*），如果我们跟进*\_\_alloc\_pages\_may\_oom*的话，可以看到函数*out_of_memory*，这个函数会查找使用内存过多的进程并杀死进程，这样就能够获得一些空闲的进程，之后重新申请并返回。

如果杀死一个进程不一定能立即2^MAX\_COSTLY\_ORDER页的连续内存，因此如果当前要分配如此大的内存区，那么内核会放弃杀死所选进程，不执行杀死任务，而是goto nopage。

kswapd进程是一个守护进程，交换守护进程的任务非常复杂，也许在有空的时候会继续笔记。

### 移除选择的页 ###

如果内核找到了适当的内存域，具有足够的空间可供分配，但还有两件事需要完成。

1. 必须判断找到的这些页是否是连续的。
2. 必须按伙伴系统的方式从free_lists移除这些页，这可能需要分解并重排内存区。

内核将这个工作交给*buffered_rmqueue*来处理，前面我们已经了解了*buffered_rmqueue*这个函数的作用，那么详细了解*buffered_rmqueue*之前，我们需要了解，当只需要分配一个页时，内核会进行优化，即分配阶为0的情形，这个页不是从伙伴系统只哦难过直接读取，而是从per-CPU的页缓存读取。

我们直接看代码。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static inline
struct page *buffered_rmqueue(struct zone *preferred_zone,
            struct zone *zone, int order, gfp_t gfp_flags,
            int migratetype)
{
    unsigned long flags;
    struct page *page;
    int cold = !!(gfp_flags & __GFP_COLD);
    int cpu;

again:
    cpu  = get_cpu();
    /* 是否阶为0，如果是则分配1页，则从per_cpu缓存中读取 */
    if (likely(order == 0)) {
        struct per_cpu_pages *pcp;
        struct list_head *list;

        pcp = &zone_pcp(zone, cpu)->pcp;
        list = &pcp->lists[migratetype];
        local_irq_save(flags);
        if (list_empty(list)) {
            /* 选择了适当的per-CPU列表之后，重新填充缓存 */
            pcp->count += rmqueue_bulk(zone, 0,
                    pcp->batch, list,
                    migratetype, cold);
            if (unlikely(list_empty(list)))
                goto failed;
        }
        /* 如果分配标志设置了GFP_CODE，那么从per-CPU缓存取得冷页 */
        if (cold)
            page = list_entry(list->prev, struct page, lru);
        else
            page = list_entry(list->next, struct page, lru);

        list_del(&page->lru);
        pcp->count--;
    } else {
        /* 如果需要分配更多(>1)的页 */
        if (unlikely(gfp_flags & __GFP_NOFAIL)) {
            WARN_ON_ONCE(order > 1);
        }
        spin_lock_irqsave(&zone->lock, flags);
        /* 从内存域的伙伴列表中选择适当的内存块
           如果有必要，自动分解大块内存，将未用
           的部分放回列表中

           如果内存中有足够的内存但不是连续的
           则失败，返回NULL指针
        */
        page = __rmqueue(zone, order, migratetype);
        spin_unlock(&zone->lock);
        if (!page)
            goto failed;
        __mod_zone_page_state(zone, NR_FREE_PAGES, -(1 << order));
    }

    __count_zone_vm_events(PGALLOC, zone, 1 << order);
    zone_statistics(preferred_zone, zone);
    local_irq_restore(flags);
    put_cpu();

    VM_BUG_ON(bad_range(zone, page));
    /* 对页进行检查，确保分配之后分配器处于理想状态
       特别地，这意味着现存的映射中不能使用该页
       也没有设置不正确的标志
    */
    if (prep_new_page(page, order, gfp_flags))
        goto again;
    return page;

failed:
    local_irq_restore(flags);
    put_cpu();
    return NULL;
}
{% endhighlight %}

当申请的页大于1的时候，主要的函数使用*\_\_rmqueue*，这个函数从伙伴列表中选择适当的内存块，如果有必要则自动分解大块内存。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static struct page *__rmqueue(struct zone *zone, unsigned int order,
                        int migratetype)
{
    struct page *page;

retry_reserve:
    page = __rmqueue_smallest(zone, order, migratetype);

    if (unlikely(!page) && migratetype != MIGRATE_RESERVE) {
        page = __rmqueue_fallback(zone, order, migratetype);

        if (!page) {
            migratetype = MIGRATE_RESERVE;
            goto retry_reserve;
        }
    }

    trace_mm_page_alloc_zone_locked(page, order, migratetype);
    return page;
}
{% endhighlight %}

这个函数主要调用了*\_\_rmqueue_smallest*函数。*\_\_rmqueue_smallest*扫描页的列表，直至找到适当的连续内存块。在这样做的时候，可以按照之前的描述拆分伙伴，如果指定的迁移列表不能满足分配需求，则尝试*__rmqueue_fallback*函数尝试其他迁移列表。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static inline
struct page *__rmqueue_smallest(struct zone *zone,
    unsigned int order,
    int migratetype)
{
    unsigned int current_order;
    struct free_area * area;
    struct page *page;

    for (current_order = order; current_order < MAX_ORDER; ++current_order) {
        area = &(zone->free_area[current_order]);
        if (list_empty(&area->free_list[migratetype]))
            continue;

        page = list_entry(area->free_list[migratetype].next,
                            struct page, lru);
        list_del(&page->lru);
        /* 设置page标志为PG_buddy，表示不在伙伴系统内 */
        rmv_page_order(page);
        area->nr_free--;
        expand(zone, page, order, current_order, area, migratetype);
        return page;
    }

    return NULL;
}
{% endhighlight %}

可以看到*__rmqueue_smallest*函数的代码不是很长，也很清楚，从当前的阶到最高阶逐步尝试。这很容易理解，如果尝试第2阶，没有连续的内存，那么很可能高阶如第3阶有可用的空闲的连续内存。

如果需要分配的内存块长度小于所选择的连续页范围，即如果因为没有更小的适当的内存块可用，而从较高的内存阶分配了一块内存，那么该内存块必须按照伙伴系统分裂成更小的快，这是通过*expand*函数完成的。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static inline void expand(struct zone *zone, struct page *page,
    int low, int high, struct free_area *area,
    int migratetype)
{
    unsigned long size = 1 << high;

    while (high > low) {
        area--;
        high--;
        size >>= 1;
        VM_BUG_ON(bad_range(zone, &page[size]));
        list_add(&page[size].lru, &area->free_list[migratetype]);
        area->nr_free++;
        set_page_order(&page[size], high);
    }
}
{% endhighlight %}

循环中各个步骤都调用了*set_page_order*函数，对于回收到伙伴系统的内存区，这个函数第将第一个*struct page*实例的*private*标志设置为当前的分配阶，并设置页的*PG_buddy*标志位，表示这个内存块由伙伴系统管理。

再回到*\_\_rmqueue*函数，如果找不到可用的内存块，则继续再其他分配阶中查找可用的内存块，则调用了*\_\_rmqueue_fallback*函数。

#### <mm/page_alloc.c> ####

{% highlight c++ %}
static inline struct page *
__rmqueue_fallback(struct zone *zone,
                   int order,
                   int start_migratetype)
{
    struct free_area * area;
    int current_order;
    struct page *page;
    int migratetype, i;

    /* 从最高阶反向遍历 */
    for (current_order = MAX_ORDER-1; current_order >= order;
                        --current_order) {
        for (i = 0; i < MIGRATE_TYPES - 1; i++) {
            migratetype = fallbacks[start_migratetype][i];

            /* 如果有必要，则在后面处理 MIGRATE_RESERVE */
            /* 如果尝试了所有手段仍然无法分配
               则从MIGRATE_RESERVE列表满足分配 
            */
            if (migratetype == MIGRATE_RESERVE)
                continue;

            area = &(zone->free_area[current_order]);
            if (list_empty(&area->free_list[migratetype]))
                continue;

            page = list_entry(area->free_list[migratetype].next,
                    struct page, lru);
            area->nr_free--;

            /*
               如果分解一个大的内存块，则将所有空闲页移动到优先选用的分配列表
               如果内核在备用列表中分配可回收内存块，则会更为积极的取得空闲页
               的所有权
             */
            if (unlikely(current_order >= (pageblock_order >> 1)) ||
                    start_migratetype == MIGRATE_RECLAIMABLE ||
                    page_group_by_mobility_disabled) {
                unsigned long pages;
                pages = move_freepages_block(zone, page,
                                start_migratetype);

                /* 如果大内存超过一半是空闲的，则主张对整个大内存块的所有权 */
                if (pages >= (1 << (pageblock_order-1)) ||
                        page_group_by_mobility_disabled)
                    set_pageblock_migratetype(page,
                                start_migratetype);

                migratetype = start_migratetype;
            }

            /* 从空闲列表中移除页 */
            list_del(&page->lru);
            rmv_page_order(page);

            if (current_order >= pageblock_order)
                change_pageblock_range(page, current_order,
                            start_migratetype);
            /*
              如果已经改变了迁移类型，使用expand使用新的迁移类型
              将剩余部分放置在新的列表中
            */
            expand(zone, page, order, current_order,
                   area, migratetype);

            trace_mm_page_alloc_extfrag(page, order, current_order,
                start_migratetype, migratetype);

            return page;
        }
    }

    return NULL;
}
{% endhighlight %}

这个函数中重要的是，函数将会按照分配阶**从大到小**的遍历，这与通常的策略相反，如果无法避免分配迁移类型不同的内存块，那么就分配一个尽可能大的内存块，如果优先考虑小的内存块，那么更容易引起内存碎片。

MIGRATE\_RESERVE立表用于紧急的内存分配，需要特殊处理，如果尝试了所有的手段依旧无法获得内存，则从MIGRATE_RESERVE列表中获取，而不是立即出现异常。

成功后，内核将内存块从列表中移除，并使用*expand*将其中未用部分还给伙伴系统。