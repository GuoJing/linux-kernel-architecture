---
layout:    post
title:     索引节点对象
category:  虚拟文件系统
description: 索引节点对象...
tags: inode 索引节点
---
文件系统处理文件所需要的所有信息都放在一个名为索引节点的数据结构中，文件名可以随时更改，但是索引节点对文件是唯一的，并且随文件的存在而存在。内存中的索引节点对象由一个*inode*数据结构组成，代码如下：

#### <include/linux/fs.h> ###

{% highlight c++ %}
struct inode {
    struct hlist_node   i_hash;
    struct list_head    i_list;
    struct list_head    i_sb_list;
    struct list_head    i_dentry;
    unsigned long       i_ino;
    atomic_t            i_count;
    unsigned int        i_nlink;
    uid_t               i_uid;
    gid_t               i_gid;
    dev_t               i_rdev;
    u64                 i_version;
    loff_t              i_size;
#ifdef __NEED_I_SIZE_ORDERED
    seqcount_t          i_size_seqcount;
#endif
    struct timespec     i_atime;
    struct timespec     i_mtime;
    struct timespec     i_ctime;
    blkcnt_t            i_blocks;
    unsigned int        i_blkbits;
    unsigned short      i_bytes;
    umode_t             i_mode;
    spinlock_t          i_lock;
    struct mutex        i_mutex;
    struct rw_semaphore i_alloc_sem;
    const struct inode_operations   *i_op;
    const struct file_operations    *i_fop;
    struct super_block      *i_sb;
    struct file_lock        *i_flock;
    struct address_space    *i_mapping;
    struct address_space    i_data;
#ifdef CONFIG_QUOTA
    struct dquot            *i_dquot[MAXQUOTAS];
#endif
    struct list_head        i_devices;
    union {
        struct pipe_inode_info  *i_pipe;
        struct block_device     *i_bdev;
        struct cdev             *i_cdev;
    };

    __u32           i_generation;

#ifdef CONFIG_FSNOTIFY
    __u32               i_fsnotify_mask;
    struct hlist_head   i_fsnotify_mark_entries;
#endif

#ifdef CONFIG_INOTIFY
    struct list_head    inotify_watches;
    struct mutex        inotify_mutex;
#endif

    unsigned long       i_state;
    unsigned long       dirtied_when;
    unsigned int        i_flags;
    atomic_t            i_writecount;

#ifdef CONFIG_SECURITY
    void                *i_security;
#endif
#ifdef CONFIG_FS_POSIX_ACL
    struct posix_acl    *i_acl;
    struct posix_acl    *i_default_acl;
#endif
    void                *i_private;
};
{% endhighlight %}

字段名                | 说明
------------         | -------------
i_hash               | 用于散列链表的指针
i_list               | 用于描述索引节点当前状态的链表指针
i\_sb\_list          | 用于超级块的索引节点链表的指针
i_dentry             | 引用索引节点的目录项对象链表的头
i_ino                | 索引节点号
i_count              | 引用计数器
i_mode               | 文件类型与访问权限
i_nlink              | 硬链接数目
i_uid                | 所有者标识符
i_gid                | 组标识符
i_rdev               | 实设备标识符
i_size               | 文件的字节数
i_attime             | 上次访问文件的时间
i_mtime              | 上次写文件的时间
i_ctime              | 上次修改索引节点的时间
i_blkbits            | 块的位数
i_blksize            | 块的字节数
i_version            | 版本号，每次使用之后自动递增
i_blocks             | 文件的块数
i_bytes              | 文件中最后一个块的字节数
i_sock               | 如果文件时一个套接字则为非0
i_lock               | 保护索引节点一些字段的自旋锁
i_sem                | 索引节点的信号量
i\_alloc\_sem        | 在直接I/O文件操作系统中避免出现竞争条件的读/写信号量
i_op                 | 索引节点的操作
i_fop                | 缺省文件操作
i_sb                 | 指向超级块对象的指针
i_flock              | 指向文件锁链表的指针
i\_mapping           | 指向*address_space*对象的指针
i\_data              | 文件的*address_space*对象
i_dquot              | 索引节点的磁盘限额
i_devices            | 用于具体的字符或块设备索引节点链表的指针
i_pipe               | 如果文件时一个管道则使用它
i_bdev               | 指向块设备驱动程序的指针
i_cdev               | 指向字符设备驱动程序的指针
i_cindex             | 拥有一组次设备好的设备文件的索引
i_generation         | 索引节点版本号
i\_dnotify\_mask     | 目录通知事件的位掩码
i_dnotify            | 用于目录通知
i_state              | 索引节点的状态标志
dirtied_when         | 索引节点的弄脏的时间
i_flags              | 文件系统的安装标志
i_writecount         | 用于写进程的引用计数器
i_security           | 指向索引节点安全结构的指针
i\_size\_seqcount    | SMP系统为*i_size*字段获取一致值时使用的顺序计数器

每个索引节点（*inode*）对象都会复制磁盘索引节点包含的一些数据，比如分配给文件的磁盘块数。如果*i_state*字段的值等于*I_DIRTY_SYNC*、*I_DIRTY_DATASYNC*或*I_DIRTY_PAGES*，该索引节点就是『脏』的，也就是说，对应的磁盘索引节点必须被更新。

*I_DIRTY*宏可以用来立即检查这三个标志的值：

#### <include/linux/fs.h> ###

{% highlight c++ %}
#define I_DIRTY (
    I_DIRTY_SYNC |
    I_DIRTY_DATASYNC |
    I_DIRTY_PAGES)
{% endhighlight %}

*i_state*字段的其他值有*I_LOCK*、*I_FREEING*、*I_CLEAR*以及*I_NEW*。其中*I_LOCK*表示
涉及的索引节点对象处于I/O传送中，而*I_FREEING*表示索引节点对象正在被释放，*I_CLEAR*表示索引节点对象的内容不再有意义，*I_NEW*表示索引节点对象已经分配但还没有从磁盘索引节点读取来的数据填充。

每个索引节点对象总是出现在下列双向循环链表的某个链表中：

1. 有效未使用的索引节点链表，典型的如哪些镜像有效的磁盘索引节点，且当前未被任何进程使用。这些索引节点不为脏，且它们的*i_count*字段设置为0。链表中的首元素和尾元素时由变量*inode_unused*的*next*字段和*prev*字段分别指向的。这个链表用作磁盘高速缓存。
2. 正在使用的索引节点链表，也就是那些镜像有效的磁盘索引节点，且当前被某些进程使用，这些索引节点不为脏，但它们的*i_count*字段为正数，链表中的首元素和尾元素由变量*inode_in_use*引用。
3. 脏索引节点的链表。链表中的首元素和尾元素是由相应超级块对象的*s_dirty*字段引用的。

这些链表都是通过适当的索引节点对象的*i_list*字段链接在一起的。

此外，每个索引节点对象也包含在每文件系统（*per-filesystem*）的双向循环连表中，链表的头存放在超级块对象的*s_inodes*字段中，索引节点对象的*i_sb_list*字段存放了指向链表相邻元素的指针。

最后，索引节点对象也存放一个称为*inode_hashtable*的散列表中，散列表加快了对索引节点对象的搜索，前提是系统内核要知道索引节点号及文件所在文件系统对应的超级块对象的地址。

由于散列技术可能引发冲突，所以索引节点对象包含一个*i_hash*字段，该字段中包含向前和向后的两个指针，分别指向散列到统一地址和前一个索引节点和后一个索引节点，该字段因此创建了由这些索引节点组成的一个双向链表。

与索引节点对象关联的方法也叫索引节点操作，它们由*inode_operation*结构来描述，该结构的地址存放在*i_op*字段中。*inode_operation*结构代码如下：

#### <include/linux/fs.h> ###

{% highlight c++ %}
struct inode_operations {
    int (*create) (struct inode *,
                   struct dentry *,int,
                   struct nameidata *);
    struct dentry * (*lookup) (struct inode *,
                               struct dentry *,
                               struct nameidata *);
    int (*link) (struct dentry *,struct inode *,struct dentry *);
    int (*unlink) (struct inode *,struct dentry *);
    int (*symlink) (struct inode *,struct dentry *,const char *);
    int (*mkdir) (struct inode *,struct dentry *,int);
    int (*rmdir) (struct inode *,struct dentry *);
    int (*mknod) (struct inode *,struct dentry *,int,dev_t);
    int (*rename) (struct inode *, struct dentry *,
            struct inode *, struct dentry *);
    int (*readlink) (struct dentry *, char __user *,int);
    void * (*follow_link) (struct dentry *, struct nameidata *);
    void (*put_link) (
        struct dentry *, struct nameidata *, void *);
    void (*truncate) (struct inode *);
    int (*permission) (struct inode *, int);
    int (*check_acl)(struct inode *, int);
    int (*setattr) (struct dentry *, struct iattr *);
    int (*getattr) (
        struct vfsmount *mnt, struct dentry *, struct kstat *);
    int (*setxattr) (
        struct dentry *, const char *,const void *,size_t,int);
    ssize_t (*getxattr) (struct dentry *, const char *, void *, size_t);
    ssize_t (*listxattr) (struct dentry *, char *, size_t);
    int (*removexattr) (struct dentry *, const char *);
    void (*truncate_range)(struct inode *, loff_t, loff_t);
    long (*fallocate)(
        struct inode *inode, int mode, loff_t offset,
        loff_t len);
    int (*fiemap)(struct inode *,
        struct fiemap_extent_info *, u64 start,
        u64 len);
};
{% endhighlight %}

函数名                    | 说明
------------             | -------------
create(dir, dentry, mode, nameidata) | 在某一目录下，为与目录项对象相关的普通文件创建一个新的磁盘索引节点
lookup(dir, dentry, nameidata) | 包含在一个目录项对象中的文件名对应的索引节点查找目录
link(old_dentry, dir, new_dentry) | 创建一个新的硬链接，它指向*dir*目录下名为*Old_dentry*的文件
unlink(dir, dentry) | 从一个目录中删除目录项对象所指定文件的硬链接
symlink(dir, dentry, symname) | 在某个目录下，为与目录项对象相关的符号链接创建一个新的索引节点
mkdir(dir, dentry, mode) | 在某个目录下，为与目录项对象相关的目录创建一个新的索引节点
rmdir(dir, dentry) | 从一个目录删除子目录，子目录的名称包含在目录项对象中
mknod(dir, dentry, mode, rdev) | 在某个目录中，为与目录项对象相关的特定文件创建一个新的磁盘索引节点，其中*mode*和*rdev*分别表示文件的类型和设备的主次设备号
rename(old_dir, old_dentry, new_dir, new_dentry) | 将*old_dir*目录下由*old_entry*标识的文件移到*new_dir*目录下，新文件名包含在*new_dentry*指向的目录项对象中
readlink(dentry, buffer, buflen) | 将目录项所知道的符号链接中对应的文件路径名拷贝到*buffer*所指定的用户态内存区
follow_link(inode, nameidata) | 解析索引节点对象所指定的符号链接，如果该符号链接是一个相对路径名，则从第二个参数所指定的目录开始进行查找
put_link(dentry, nameidata) | 释放由*follow_link*方法分配的用于解析符号链接的所有临时数据机构
truncate(inode) | 修改与索引节点相关的文件长度
permission(inode, mask, nameidata) | 检查是否允许对与索引节点所指的文件进行指定模式的访问
setattr(dentry, iattr) | 在吃几索引节点属性后通知一个『修改事件』
getattr(mnt, dentry, kstat) | 由一些文件系统用于读取索引节点属性
setxattr(dentry, name, value, size, flags) | 为索引节点设置扩展属性[^1]
getxattr(dentry, name, buffer, size) | 获取索引节点的扩展属性
listxattr(dentry, buffer, size) | 获取扩展属性名称的整个链表
removexattr(dentry, name) | 删除索引节点的扩展属性

[^1]: 扩展属性存放在任何索引节点之外的磁盘快中。

同[超级块对象](/linux-kernel-architecture/posts/super-block-object/)一样，上面的所有方法对所有的文件类型都是可用的，不过只有其中一个子集应用到某一个特定的索引节点和文件系统，未实现的方法对应的字段被设置为NULL。