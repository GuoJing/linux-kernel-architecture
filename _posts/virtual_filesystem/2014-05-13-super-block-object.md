---
layout:    post
title:     超级块对象
category:  虚拟文件系统
description: VFS数据结构之一...
tags: 超级块
---
每个VFS对象都存放在一个适当的数据结构中，其中包括对象的属性和指向对象的方法的指针，内核可以动态地修改对象的方法，因此可以为对象建立专用的行为。

内核中有多重对象，超级块对象是一种常用的对象。超级块对象由*super_block*结构组成。代码如下：

#### <include/linux/fs.h> ###

{% highlight c++ %}
struct super_block {
    struct list_head    s_list;
    dev_t               s_dev;
    unsigned long       s_blocksize;
    unsigned char       s_blocksize_bits;
    unsigned char       s_dirt;
    loff_t              s_maxbytes;
    struct file_system_type         *s_type;
    const struct super_operations   *s_op;
    const struct dquot_operations   *dq_op;
    const struct quotactl_ops       *s_qcop;
    const struct export_operations  *s_export_op;
    unsigned long       s_flags;
    unsigned long       s_magic;
    struct dentry       *s_root;
    struct rw_semaphore s_umount;
    struct mutex        s_lock;
    int         s_count;
    int         s_need_sync;
    atomic_t        s_active;
#ifdef CONFIG_SECURITY
    void                *s_security;
#endif
    struct xattr_handler  **s_xattr;

    struct list_head    s_inodes;
    struct hlist_head   s_anon;
    struct list_head    s_files;
    struct list_head    s_dentry_lru;
    int                 s_nr_dentry_unused; 

    struct block_device *s_bdev;
    struct backing_dev_info *s_bdi;
    struct mtd_info     *s_mtd;
    struct list_head    s_instances;
    struct quota_info   s_dquot;

    int                 s_frozen;
    wait_queue_head_t   s_wait_unfrozen;

    char s_id[32];

    void                *s_fs_info;
    fmode_t             s_mode;

    struct mutex s_vfs_rename_mutex;

    u32    s_time_gran;

    char *s_subtype;
    char *s_options;
};
{% endhighlight %}

字段名                | 说明
------------         | -------------
s_list               | 指向超级块链表的指针
s_dev                | 设备标识符
s_blocksize          | 以字节为单位的块大小
s\_old_blocksize     | 基本块设备驱动程序中提到的以字节为单位的块大小
s\_blocksize_bits    | 以位为单位的块大小
s_dirt               | 修改（脏）标志
s_maxbytes           | 文件的最长长度
s_type               | 文件系统类型
s_op                 | 超级块方法
dp_op                | 磁盘限额处理方法
s_qcop               | 磁盘限额管理方法
s\_export_op         | 网络文件系统使用的输出操作
s_flags              | 安装标志
s_magic              | 文件系统的magic words
s_root               | 文件系统根目录的目录项对象
s_unmount            | 卸载所用的信号量
s_lock               | 超级块信号量
s_count              | 引用计数器
s_syncing            | 表示对超级块的索引节点进行同步的标志
s\_need\_sync_fs     | 对超级块的已安装文件系统进行同步的标志
s_active             | 次级引用计数器
s_security           | 指向超级块安全数据结构的指针
s_xattr              | 指向超级块扩展属性结构的指针
s_inodes             | 所有索引节点的链表
s_dirty              | 改进型索引节点的链表
s_io                 | 等待被写入磁盘的索引节点的链表
s_anon               | 用于处理远程网络文件系统的你们目录项的链表
s_files              | 文件对象的链表
s_bdev               | 指向块设备驱动程序描述符的指针
s_instances          | 用于给定文件系统类型的超级块对象链表的指针
s_dquot              | 磁盘限额的描述符
s_frozen             | 冻结文件系统时使用的标志
s\_wait_unforzen     | 进程挂起的等待队列，直到文件系统被解冻
s\_id                | 包含超级块的块设备名称
s\_fs_info           | 指向特定文件系统的超级块信息的指针
s\_vfs\_rename_sem   | 当VFS通过目录重命名文件时使用的信号量
s\_time_gran         | 纳秒级的时间戳的粒度

所有超级块对象都以双向链表的形式链接在一起，链表中的第一个元素用*super_blocks*变量来表示，而超级块多想的*s_list*字段存放指向链表相邻元素的指针，*sb_lock*自旋锁保护链表受多处理器系统上的同时访问。

*s_fs_info*字段指向属于具体文件系统的超级块信息，例如，加入超级块对象指向的时Ext文件系统，该字段就指向*extx_sb_info*数据结构，该结构包括磁盘分配位掩码和其他与VFS的通用文件模型无关的数据。

通常，为了效率期间，由*s_fs_info*字段所指向的数据结构被复制到内存。任何基于磁盘文件系统都需要访问和更改自己的磁盘分配位图，以便分配或释放磁盘块，VFS允许这些文件系统直接对内存超级块*s_fs_info*字段进行操作，而无需访问磁盘。

但是这种方法会带来一个新问题，有可能VFS超级块最终不再与磁盘上相应的超级块同步。因此，有必要引入一个*s_dirty*标志来表示该超级块是否时脏的---由此可以推断磁盘上的数据是否有必要更新。缺乏同步还会导致产生一个问题，就是当一台机器的电源突然断开而用户来不及正常关闭系统时，就会出现文件系统崩溃，Linux时他哦难过周期性地将所有『脏』超级块写回磁盘来减少该问题带来的危害。

与超级块关联的方法就是超级块操作，当VFS需要调用其中一个操作时，比如说*read_inode()*，它就会执行下列操作：

    sb->s_op->read_incode(inode);

这里*sb*存放所涉及超级块对象的地址。*super_operations*表的*read_inode*
字段存放这这个函数的地址，所以可以看作这个函数直接被调用。我们可以通过了解*super_operations()*函数来了解一下超级块的操作。

代码如下：

#### <include/linux/fs.h> ###

{% highlight c++ %}
struct super_operations {
    struct inode *(*alloc_inode)(struct super_block *sb);
    void (*destroy_inode)(struct inode *);
    void (*dirty_inode) (struct inode *);
    int (*write_inode) (struct inode *, int);
    void (*drop_inode) (struct inode *);
    void (*delete_inode) (struct inode *);
    void (*put_super) (struct super_block *);
    void (*write_super) (struct super_block *);
    int (*sync_fs)(struct super_block *sb, int wait);
    int (*freeze_fs) (struct super_block *);
    int (*unfreeze_fs) (struct super_block *);
    int (*statfs) (struct dentry *, struct kstatfs *);
    int (*remount_fs) (struct super_block *, int *, char *);
    void (*clear_inode) (struct inode *);
    void (*umount_begin) (struct super_block *);
    int (*show_options)(struct seq_file *, struct vfsmount *);
    int (*show_stats)(struct seq_file *, struct vfsmount *);
#ifdef CONFIG_QUOTA
    ssize_t (*quota_read)(
        struct super_block *, int, char *, size_t, loff_t);
    ssize_t (*quota_write)(
        struct super_block *, int,
        const char *, size_t, loff_t);
#endif
    int (*bdev_try_to_free_page)(
        struct super_block*,
        struct page*,
        gfp_t);
};
{% endhighlight %}

函数名                    | 说明
------------             | -------------
alloc_inocde(sb)         | 为索引节点对象分配空间，包括具体文件系统的数据所需的空间
destory_inode(inodes)    | 撤销索引节点对象，包括具体文件系统的数据
read\_inode(inode)       | 用磁盘上的数据填充以参数传递过来的索引节点对象的字段，索引节点对象的*i_ino*字段标识从磁盘上要读取的具体文件系统的索引节点
dirty_inode(inode)       | 当索引节点标记为修改时调用
write\_inode(inode, flag)| 用通过传递参数指定的索引节点对象的内容更新一个文件系统的索引节点，索引节点对象的*i_ino*字段标识所涉及磁盘上文件系统的索引节点。*flag*参数表示I/O操作是否应当同步
put_inode(inode)         | 释放索引节点时调用以执行具体文件系统操作
drop\_inode(inode)       | 在即将撤销索引节点时调用，也就是说，当最后一个用户释放该索引节点时，实现该方法的文件系统使用*generic_drop_inode()*函数。该函数从VFS数据结构中移走对索引节点的每一个引用，如果索引节点不再出现在任何目录中，则调用超级块方法*delete_inode*将它从文件系统中删除
delete_inode(inode)      | 在必须撤销索引节点时调用，删除内存中的VFS索引节点和磁盘上的文件数据及元数据
put_super(super)         | 释放通过传递的参数知道的超级块对象
write_super(super)       | 用指定对象的内容更新文件系统的超级块
sync_fs(sb, wait)        | 在清除文件系统来更新磁盘上的具体文件系统数据结构时调用
write\_super\_lockfs(super) | 阻塞对文件系统的修改并用指定对象的内容更新超级块。当文件系统被冻结时调用该方法
unlockfs(super)          | 取消由*write\_super\_lockfs()*超级块方法实现的对文件系统更新的阻塞
statfs(super, buf)       | 将文件系统的统计信息返回并填写在*buf*缓冲中
remount_fs(super, flags, data) | 用新的选项重新安装文件系统
clear_inode(inode)       | 当撤销磁盘索引节点执行具体文件系统操作时调用
umount_begin(super)      | 中断一个安装操作，因为相应的卸载操作已经开始，此操作只在网络文件系统中使用
show\_options(seq_file, vfsmount) | 用来显式特定文件系统的选项
quota_read(super, type, data, size, offset) | 限额系统使用该方法从文件中读取数据，该文件详细说明了所在文件系统的限制
quota_write(super, type, data, size, offset)| 限额系统使用该方法将数据写入文件中，该文件详细说明了所在文件系统的限制[^1]

[^1]: 限额系统（*quota system*）为每个用户和（或）组限制了它们在给定文件系统上所能使用的空间大小。

上表的方法对所有可能的文件系统类型均是可用的，但是只有其中的一个自己应用到每个具体的文件系统，未实现的方法对应的字段设置为NULL。
