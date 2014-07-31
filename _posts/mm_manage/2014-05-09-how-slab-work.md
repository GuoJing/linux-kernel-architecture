---
layout:    post
title:     slab分配的原理
category:  内存管理
description: slab分配的原理...
tags: slab 分配器
---
slab分配器由一个紧密地交织的数据和内存结构的网络组成，出看起来不容易理解，所以，重要的是获得各个结构之间关系的一个理解，理解之后我们才能够深入的进行slab分配器代码的查看。

基本上slab缓存由下图所示的两部分组成：保存管理性数据的缓存对象和保存被管理对象的各个slab。

{:.center}
![slab](/linux-kernel-architecture/images/slab2.png){:style="max-width:500px"}

{:.center}
slab分配器的各个部分

每个缓存只负责一种对象类型[^1]，或提供一般性的缓冲区。各个缓冲中slab的数目各有不同，这与已经使用的页的数目、对象长度和被管理对象的数目有关。另外，系统中所有的缓存都保存在一个双链表中。这使得内核有机会依次遍历所有的缓存，这是有必要的，例如在发生内存不足的情况下，内核可能需要缩减分配给缓存的内存数量。

[^1]: 例如struct unix_sock实例。

如果更加仔细的研究缓存的结构，就会注意到一些细节，如下图：

{:.center}
![slab](/linux-kernel-architecture/images/slab3.png){:style="max-width:600px"}

{:.center}
slab缓存的精细结构

除了管理性数据，即易用和空闲对象或标志寄存器的数目，缓存结构包括两个特别重要的成员。

1. 指向一个数组的指针，其中保存了各个CPU最后释放的对象。
2. 每个内存结点都对应3个表头，用于组织slab的链表。第一个链表包含完全用尽的slab，第二个是部分空闲的slab，第三个是空闲的slab。

缓存结构指向一个数组，其中包含了与系统CPU数目相同的数组项。每一个元素都是一个指针，指向一个进一步的结构称之为数组缓存（*array cache*），其中包含了对应于特定系统CPU的管理数据，但并非用于缓存。管理性数据之后的内存区包含了一个指针数组，各个数组项指向*slab*中未使用的对象。

为了更好地利用CPU高速缓存，这些per-CPU指针是很重要的，在分配和释放对象时，采用后进先出（*last in  first out，LIFO*）原理。内核假定刚释放的对象仍然处于CPU高速缓存中，会尽快再次分配它以便响应下一个分配请求。仅当per-CPU缓存为空时，才会用slab中的空闲对象重新填充它们。

这样，对象分配的体系就形成了一个三层的层次结构，分配成本和操作对CPU高速缓存和TLB的负面影响逐渐升高。

1. 仍然处于CPU高速缓存中的per-CPU对象。
2. 现存slab中未使用的对象。
3. 刚使用伙伴系统分配的新slab中未使用的对象。

对象在slab中并非连续排列，而是按照一个相当复杂的方案分布，如下图：

{:.center}
![slab](/linux-kernel-architecture/images/slab4.png){:style="max-width:600px"}

{:.center}
slab的精细结构

用于每个对象的长度并不反应其确切的大小，相反，长度已经进行了舍入以满足某些对齐方式的要求。有两种可用的备选对齐方案：

1. slab创建时使用*SLAB_HWCACHE_ALIGN*，slab用户可以要求对象按硬件缓存行对齐。要么按照*cache_line_size*的返回值进行对齐，该函数返回特定于处理器的L1缓存大小。如果对象小于缓存行长度的一般，那么将多个对象放入一个缓存行。
2. 如果不要求按硬件缓存行对齐，那么内核保证对象按*BYTES_PER_WORD*对齐，该值时表示*void*指针所需字节的数目。

在32位处理器上，*void*指针需要4个字节。因此，对有6个字节的对象，需要8=2x4个字节，对于的字节称为填充字节。

填充字节可以加速对slab中对象的访问，如果使用对齐的地址，那么几乎在所有的体系结构上，内存访问都会更快，这弥补了使用填充字节必然导致需要更多内存的不利情况。管理结构位于每个slab的起始处，保存了所有的管理结构。其后面时一个数组。

每个数组项对应于slab中的一个对象，只有在对象没有分配时，相应的数组项才有意义。在这种情况下，它指定了下一个空闲对象的索引。由于最低编号的空闲对象的编号还保存在slab起始处的管理结构中，内核无需使用链表或其他复杂的关联机制就可以轻松找到当前可用的所有对象，数组的最后一项总是一个结束标记，值为*BUFCTL_END*。

{:.center}
![slab](/linux-kernel-architecture/images/slab5.png){:style="max-width:600px"}

{:.center}
slab中空闲对象的管理

大多数情况下，slab内存区的长度时不能被对象长度整除的，因此，内核就有了一些多余的内存，可以用来以偏移量的形式给slab『着色』。缓存的各个slab成员会指定不同的偏移量，以便将数据定位到不同的缓存行，因而slab开始和结束处的空闲内存时不同的。在计算偏移量时，内核必须考虑其他的对齐因素，例如L1高速缓存中数据结构的对齐。

管理数据可以放置在slab自身，也可以放置到使用kmalloc分配的不同内存区中，内存如何选择取决于slab的长度和已用对象的数量。相应的选择标准稍后讨论，管理数据和slab内存之间的关系很容易建立，因为slab头包含了一个指针，指向slab数据区的起始处，无论管理数据是否在slab上。

最后，内核需要一种方法通过对象自身即可识别slab以及对象驻留的缓存，根据对象的物理内存地址，可以找到相关的页，因此可以在全局的*mem_map*数组中找到对应的*page*实例。*page*结构包含一个连表元素，用于管理各种链表中的页，对于slab缓存中的页而言，该指针时不必要的，可以用于其他用途。

1. page->lru.next指向页驻留的缓存和管理结构。
2. page->lru.prev指向保存该页的slab的管理结构。

设置或者读取slab信息分别由*set_page_slab*和*get_page_slab*函数完成，带有*__cache*后缀的函数则处理缓存信息的设置和读取。

#### <mm/slab.c> ####

{% highlight c++ %}
static inline void
page_set_cache(struct page *page, struct kmem_cache *cache)
{
    page->lru.next = (struct list_head *)cache;
}

static inline struct
kmem_cache *page_get_cache(struct page *page)
{
    page = compound_head(page);
    BUG_ON(!PageSlab(page));
    return (struct kmem_cache *)page->lru.next;
}

static inline void
page_set_slab(struct page *page, struct slab *slab)
{
    page->lru.prev = (struct list_head *)slab;
}

static inline struct slab
*page_get_slab(struct page *page)
{
    BUG_ON(!PageSlab(page));
    return (struct slab *)page->lru.prev;
}
{% endhighlight %}

此外，内核还对分配给slab分配器的每个物理内存页都设置标志*PG_SLAB*。