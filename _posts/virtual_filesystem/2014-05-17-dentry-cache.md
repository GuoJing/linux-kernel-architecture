---
layout:    post
title:     目录项高速缓存
category:  虚拟文件系统
description: 目录项高速缓存...
tags: 目录项 高速缓存
---
由于从磁盘读入一个目录项并构造相应的目录项对象需要花费大量的时间，所以，再完成对目录项对象的操作后，可能后面还要使用它，因此仍在内存中保留它有重要的意义。例如，我们经常需要编译文件，随后编译它，或者编辑并打印它，或者复制它并编辑这个拷贝，再诸如此类的情况中，同一个文件需要被反复访问。

为了最大限度地提高处理这些目录项对象的效率，Linux使用目录项高速缓存，它由两种类型的数据结构组成：

1. 一个处于正在使用，未使用或负状态的目录项对象的集合。
2. 一个散列表，从中能够快速获取与给定的文件名和目录名对应的目录项对象，同样，如果访问的对象不在目录项高速缓存中，则散列函数返回一个空值。

目录项高速缓存的作用还相当于索引节点高速缓存（*inode cache*）的控制器，在内核内存中，并不丢弃与未用目录项相关的索引节点，这是由于目录项高速缓存仍在使用它们。因此，这些索引节点对象保存在RAM中，并能够借助相应的目录项快速引用它们。

所有未使用的目录项对象都放在一个『最近最少使用（LRU）』的双向链表中，该链表按照插入的时间排序，也就是说，最后释放的目录项对象放在链表的首部，所以最近最少使用的目录项对象总是靠近链表的尾部。

一旦目录项高速缓存的空间开始变小，内核就从链表的尾部删除元素，使得最近最常使用的对象得以保留，LRU链表的首元素和尾元素的地址存放在*list_headr*类型的*dentry_unused*变量的*next*字段和*prev*字段中，目录项对象的*d_lru*字段包含指向链表中相邻目录项的指针。

每个正在使用的目录项对象都被插入一个双向链表中，该链表由相应索引节点对象的*i_dentry*字段所指向。目录项对象的*d_alias*字段存放链表中相邻元素的地址，从前面的对象笔记中就可以清楚的明白。

当指向相应文件的最后一个硬连接被删除后，一个正在使用的目录项对象可能会变成负状态。在这种情况下，该目录项对象被移到未使用目录项对象组成的LRU链表中。每当内核缩减目录项高速缓存时，负状态目录项对象就朝着LRU链表的尾部移动，这样这些对象就会被逐渐释放。

散列表是由*dentry_hashtable*数组实现的。数组中的每个元素时一个指向链表的指针，这种链表就是把具有相同散列表值的目录项进行散列而成的。该数组的长度取决于系统已安装RAM的数量，缺省值时每兆字节RAM包含256个元素。

目录项对象的*d_hash*字段包含指向具有相同散列值的链表中的相邻元素，散列函数产生的值是由目录的目录项对象及文件名计算出来的。

*dcache_lock*自旋锁保护目录项高速缓存数据结构免受多处理器系统上的同时访问。*d_lookup()*函数在散列表中查找给定的父目录对象和文件名，为了避免发生竞争，使用顺序锁。*__d_lookup()*函数与之类似，但假定不会发生竞争，因此也不需要顺序锁。

#### <fs/dcache.c> ####

{% highlight c++ %}
struct dentry * d_lookup(
    struct dentry * parent, struct qstr * name)
{
    struct dentry * dentry = NULL;
    unsigned long seq;

        do {
                seq = read_seqbegin(&rename_lock);
                dentry = __d_lookup(parent, name);
                if (dentry)
            break;
    } while (read_seqretry(&rename_lock, seq));
    return dentry;
}
{% endhighlight %}

*d_lookup()*函数最终会调用到*__d_lookup()*函数。

#### <fs/dcache.c> ####

{% highlight c++ %}
struct dentry * __d_lookup(
    struct dentry * parent, struct qstr * name)
{
    unsigned int len = name->len;
    unsigned int hash = name->hash;
    const unsigned char *str = name->name;
    struct hlist_head *head = d_hash(parent,hash);
    struct dentry *found = NULL;
    struct hlist_node *node;
    struct dentry *dentry;

    rcu_read_lock();
    
    hlist_for_each_entry_rcu(dentry, node, head, d_hash) {
        struct qstr *qstr;

        if (dentry->d_name.hash != hash)
            continue;
        if (dentry->d_parent != parent)
            continue;

        spin_lock(&dentry->d_lock);

        /*
         * 在上锁之后重新检查目录项因为
         * d_move可能会更改一些其他属性
         */
        if (dentry->d_parent != parent)
            goto next;

        if (d_unhashed(dentry))
            goto next;

        /*
         * 因为d_mode()不能修改qstr，因为被自旋锁保护
         * 所以检查和比较名字是安全的
         */
        qstr = &dentry->d_name;
        if (parent->d_op && parent->d_op->d_compare) {
            if (parent->d_op->d_compare(parent, qstr, name))
                goto next;
        } else {
            if (qstr->len != len)
                goto next;
            if (memcmp(qstr->name, str, len))
                goto next;
        }

        atomic_inc(&dentry->d_count);
        /* 找到了 */
        found = dentry;
        spin_unlock(&dentry->d_lock);
        break;
next:
        spin_unlock(&dentry->d_lock);
    }
    rcu_read_unlock();
    /* 返回命中的缓存项 */
    return found;
}
{% endhighlight %}

可以看到，缓存项的相关逻辑并不是那么复杂。