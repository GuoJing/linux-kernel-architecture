---
layout:    post
title:     目录项对象
category:  虚拟文件系统
description: 目录项对象...
tags: 目录项
---
我们知道VFS把每个目录看作由若干子目录和文件组成的一个普通文件。然而，一旦目录项被读入内存，VFS就把它转换成基于*dentry*结构的一个目录项对象，该结构的代码如下：

#### <include/linux/dcache.h> ###

{% highlight c++ %}
struct dentry {
    atomic_t     d_count;
    unsigned int d_flags;
    spinlock_t   d_lock;
    int          d_mounted;
    struct inode *d_inode;
    struct hlist_node d_hash;
    struct dentry *d_parent;
    struct qstr d_name;

    struct list_head d_lru;
    union {
        struct list_head d_child;
        struct rcu_head d_rcu;
    } d_u;
    struct list_head d_subdirs;
    struct list_head d_alias;
    unsigned long d_time;
    const struct dentry_operations *d_op;
    struct super_block *d_sb;
    void *d_fsdata;
    unsigned char d_iname[DNAME_INLINE_LEN_MIN];
};
{% endhighlight %}

其中目录项对象的字段如下：

字段                  | 说明
------------          | -------------
d_count               | 目录项对象引用计数器
d_flag                | 目录项高速缓存标志
d_lock                | 保护目录项对象的自旋锁
d_inode               | 与文件名关联的索引节点
d_parent              | 父目录的目录项对象
d_name                | 文件名
d_lru                 | 用于未使用目录项链表的指针
d_child               | 对目录而言，用于同一父母路中的目录项链表的指针
d_subdirs             | 对目录而言，子目录链表的头
d_alias               | 用于与统一索引节点（别名）相关的目录项链表的指针
d_time                | 由d\_revalidate方法使用
d_op                  | 目录项方法
d_sb                  | 文件的超级块对象
d_fsdata              | 依赖于文件系统的数据
d_rcu                 | 回收目录项时由RCU描述符使用
d_cookie              | 指向内核配置文件使用的数据结构的指针
d_hash                | 指向散列表表项链表的指针
d_mounted             | 对目录而言，用于记录安装该目录项的文件系统数的计数器
d_iname               | 存放短文件名的空间

每个目录项可以处于以下四种状态：

1. 空闲状态。
2. 未使用状态。
3. 正在使用状态。
4. 负状态。

**空闲状态**

处于该状态的目录项对象不包括有效信息，而且还没有被VFS使用，对应的内存区由slab分配器进行处理。

**未使用状态**

处于该状态的目录项对象当前还没有被内核使用。该对象的引用计数器*d_count*的值未0，但其*i_node*字段仍然指向关联的索引节点。该目录项对象包含有效信息，但为了在必要时回收内存，它的内容可能被丢弃。

**正在使用状态**

处于该状态的目录项对象当前正在被内核使用，该对象的引用计数器*d_count*的值未正数，其*d_inode*字段指向关联的索引节点对象。该目录项对象包含有效的信息，并且不能被丢弃。

**负状态**

与目录项关联的索引节点不存在，那是因为相应的磁盘索引节点已被删除，或者因为目录项对象时通过解析一个不存在的文件的路径名创建的。目录项对象的*d_inode*字段设置为*NULL*，但该对象仍然被保存在目录项高速缓存中，以便后续对统一文件目录名的查找操作能够快速完成[^1]。

[^1]: 负状态这个名词容易使人误解，因为根本不涉及任何负值。

与目录项对象关联的方法称为目录项操作，这些方法由*dentry_operations*结构描述，该结构的地址放在目录项对象的*d_op*字段中。代码如下：

#### <include/linux/dcache.h> ###

{% highlight c++ %}
struct dentry_operations {
    int (*d_revalidate)(struct dentry *, struct nameidata *);
    int (*d_hash) (struct dentry *, struct qstr *);
    int (*d_compare) (
        struct dentry *, struct qstr *, struct qstr *);
    int (*d_delete)(struct dentry *);
    void (*d_release)(struct dentry *);
    void (*d_iput)(struct dentry *, struct inode *);
    char *(*d_dname)(struct dentry *, char *, int);
};
{% endhighlight %}

函数名                    | 说明
------------             | -------------
d_revalidate(dentry, nameidate) | 在把目录项对象转换为一个文件路径名之前，判定该目录项对象是否仍然有效。缺省的VFS函数什么也不做，而网络文件系统可以指定自己的函数
d_hash(dentry, name) | 生成一个散列值，这是用于目录项散列表、特定于具体文件系统的散列函数
d_compare(dir, name1, name2) | 比较两个文件名
d_delete(dentry) | 当对目录项对象的最后一个引用被删除，调用该方法，缺省的VFS函数什么也不做
d_release(dentry) | 当要释放一个目录项对象时，调用该方法
d_input(dentry, ino) | 当一个目录对象变为『负』状态时，调用该方法

