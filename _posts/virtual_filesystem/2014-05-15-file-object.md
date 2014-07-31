---
layout:    post
title:     文件对象
category:  虚拟文件系统
description: 文件对象...
tags: 文件
---
文件对象描述符进程怎样与一个打开的文件进行交互，文件对象是在文件被打开时间创建的一个file结构组成，代码如下：

#### <include/linux/fs.h> ####

{% highlight c++ %}
struct file {
    union {
        struct list_head    fu_list;
        struct rcu_head     fu_rcuhead;
    } f_u;
    struct path     f_path;
#define f_dentry    f_path.dentry
#define f_vfsmnt    f_path.mnt
    const struct file_operations    *f_op;
    spinlock_t      f_lock;
    atomic_long_t   f_count;
    unsigned int    f_flags;
    fmode_t         f_mode;
    loff_t          f_pos;
    struct fown_struct   f_owner;
    const struct cred    *f_cred;
    struct file_ra_state f_ra;

    u64                  f_version;
#ifdef CONFIG_SECURITY
    void                 *f_security;
#endif
    void                 *private_data;

#ifdef CONFIG_EPOLL
    struct list_head    f_ep_links;
    struct list_head    f_tfile_llink;
#endif /* #ifdef CONFIG_EPOLL */
    struct address_space    *f_mapping;
#ifdef CONFIG_DEBUG_WRITECOUNT
    unsigned long f_mnt_write_state;
#endif
};
{% endhighlight %}

其中文件对象的字段如下：

字段                  | 说明
------------          | -------------
fu_list               | 用于通用文件对象链表的指针
fu_rcuhead            | 用于rcu读写拷贝的链表头
f_dentry              | 与文件相关的目录项对象
f_vfsmnt              | 含有该文件的已安装文件系统
f_op                  | 指向文件操作表的指针
f_count               | 文件对象的引用计数器
f_flags               | 打开文件时所指定的标志
f_mode                | 进程的访问模式
f_error               | 网络写操作的错误码
f_pos                 | 当前文件位移量，也就是文件指针
f_owner               | 通过信号进行I/O事件通知的数据
f_uid                 | 用户的UID
f_gid                 | 用户的GID
f_ra                  | 文件的预读状态
f_version             | 版本号，每次使用后自动递增
f_security            | 指向文件对象的安全结构的指针
parivate_data         | 指向特定文件系统或设备驱动程序所需的数据的指针
f\_ep_links           | 文件的事件轮询等待者链表的头
f\_ep_lock            | 保护f\_ep\_links链表的自旋锁
f_mapping             | 指向文件地址空间对象的指针

存放在文件对象中的主要信息是文件指针，即文件中当前的位置，下一个操作将在该位置发生。由于几个进程可能同时访问同一个文件，因此文件指针必须存放在文件对象而不是索引节点对象中。

文件对象通过一个名为*filp*的*slab*高速缓存分配，*filp*描述符地址存放在*filp_cachep*变量中。由于分配的文件对象数目是有限的，因此*files_stat*变量在其*max_files*字段中指定了可分配文件对象的最大数目，也就是系统可同事访问的最大文件数。

内核初始化期间，*files_init()*函数把*max_files*字段设置为可用RAM大小的1/10。不过系统管理员可以修改这个值。而且，即使*max_files*文件对象已经被分配，超级用户也总是可以获得一个文件对象。

『在使用』文件对象包含在由具体文件系统的超级块所确立的几个链表中，每个超级块多想把文件对象链表的头存放在*s_files*字段中，因此，属于不同文件系统的文件对象就包含在不同的链表中。连表中分别指向前一个元素和后一个元素的指针都存放在文件对象的*f_list*字段中。*files_lock*自旋锁保护超级块*s_files*链表免受多处理器系统上的同时访问。

文件对象的*f_count*字段是一个引用计数器，它记录使用文件对象的进程数[^1]。当内核本身使用该文件对象时也要增加计数器的值。

[^1]: 以CLONE_FILES标志创建的轻量级进程共享打开文件表，因此它们可以使用相同的文件对象。

当VFS代表进程必须打开一个文件时，它调用*get_empty_filp()*函数来分配一个全新的文件对象。该函数调用*kmem_cache_alloc()*从*filp*高速缓存中获得空闲的文件对象，然后初始化这个字段。

----

每个文件系统都有其自己的文件操作集合，执行诸如读写文件这样的操作。当内核将一个索引节点从磁盘装入内存时，就会把指向这些文件操作的指针存放在*file_operations*结构中，而该结构的地址存放在该索引节点inode对象的*i_fop*字段中。

当进程打开这个文件时，VFS就用存放在索引节点中的这个地址初始化新文件对象的*f_op*字段，使得对文件操作的后续调用能够使用这些函数，如果需要，VFS随后页可以通过在*f_op*字段存放一个新值而修改文件操作的集合。

文件操作集合如下：

#### <include/linux/fs.h> ###

{% highlight c++ %}
struct file_operations {
    struct module *owner;
    loff_t (*llseek) (struct file *, loff_t, int);
    ssize_t (*read) (
        struct file *, char __user *,
        size_t, loff_t *);
    ssize_t (*write) (
        struct file *, const char __user *,
        size_t, loff_t *);
    ssize_t (*aio_read) (
        struct kiocb *, const struct iovec *,
        unsigned long, loff_t);
    ssize_t (*aio_write) (
        struct kiocb *, const struct iovec *,
        unsigned long, loff_t);
    int (*readdir) (struct file *, void *, filldir_t);
    unsigned int (*poll) (
        struct file *, struct poll_table_struct *);
    int (*ioctl) (
        struct inode *, struct file *,
        unsigned int, unsigned long);
    long (*unlocked_ioctl) (
        struct file *, unsigned int, unsigned long);
    long (*compat_ioctl) (
        struct file *, unsigned int, unsigned long);
    int (*mmap) (struct file *, struct vm_area_struct *);
    int (*open) (struct inode *, struct file *);
    int (*flush) (struct file *, fl_owner_t id);
    int (*release) (struct inode *, struct file *);
    int (*fsync) (struct file *, struct dentry *, int datasync);
    int (*aio_fsync) (struct kiocb *, int datasync);
    int (*fasync) (int, struct file *, int);
    int (*lock) (struct file *, int, struct file_lock *);
    ssize_t (*sendpage) (
        struct file *, struct page *,
        int, size_t, loff_t *, int);
    unsigned long (*get_unmapped_area)(
        struct file *, unsigned long,
        unsigned long, unsigned long,
        unsigned long);
    int (*check_flags)(int);
    int (*flock) (struct file *, int,
        struct file_lock *);
    ssize_t (*splice_write)(struct pipe_inode_info *,
        struct file *, loff_t *,
        size_t, unsigned int);
    ssize_t (*splice_read)(struct file *,
        loff_t *, struct pipe_inode_info *,
        size_t, unsigned int);
    int (*setlease)(
        struct file *, long,
        struct file_lock **);
};
{% endhighlight %}

函数名                    | 说明
------------             | -------------
llseek(file, offset, origin) | 更新文件指针
read(file, buf, count, offset) | 从文件的offset处开始读count个字节，然后增加offset的值
aio_read(req, buf, len, pos) | 启动一个异步I/O操作，从文件的pos处开始读处len个字节的数据并将它们放入buf中
write(file, buf, count, offset) | 从文件的offset处开始写入count个字节然后增加offset的值
aio_write(req, buf, len, pos) | 启动一个异步I/O的操作，从buf中取出len个字节写入pos处
readdir(dir, dirent, filldir) | 返回一个目录的下一个目录项，返回值存入参数dirent
poll(file, poll_table) | 检查是否在一个文件上有操作发生，如果没有则睡眠，知道该文件上有操作发生
ioctl(inode, file, cmd, arg) | 项一个基本硬件设备发送命令
unlocked_ioctl(file, cmd, arg) | 与ioctl方法类似，但是不用获得大内核锁
compat_ioctl(file, cmd, arg) | 64位的内核使用该方法执行32位的系统调用ioctl
mmap(file, vma) | 执行文件的内存映射，并将映射放入进程的地址空间
open(inode, file) | 通过创建一个新的文件对象而打开一个我呢贱，并把它链接到相应的索引节点对象
flush(file) | 当打开文件的引用被关闭时调用该方法，该方法取决于文件系统
release(inode, file) | 释放文件对象，当打开文件的最后一个引用被关闭时调用该方法
fsync(file, dentry, flag) | 将文件所缓存的全部数据写入磁盘
aio_fsync(req, flag) | 启动一次异步I/O刷新操作
fasync(fd, file, on) | 通过信号来启用或禁止I/O时间通告
lock(file, cmd, file_lock) | 对file文件申请一个锁
readv(file, vector, count, offset) | 从文件中读字节，并把结果放入vector描述的缓冲区中，缓冲区的个数由count指定
writev(file, vector, count, offset) | 把vector描述的缓冲区中的字节写入文件，缓冲区的个数由count指定
sendfile(in\_file, offset, count, file\_send\_actor, out\_file) | 把数据从in\_file传送到out\_file中
sendpage(file, page, offset, size, pointer, fill) | 把数据从文件传送到页高速缓存的页，这个底层方法由sendfile()和用于套接字的网络代码使用
get\_unmapped_area(file, addr, len, offset, flags) | 获得一个未使用的地址范围来隐射文件
check\_flags(flags) | 当设置文件的状态标志时，fcntl()系统调用的服务例程用该方法执行附加的检查，目前只适用于NFS网络文件系统
dir\_notify(file, arg) | 当建立一个目录更改消息时，由fcntl()系统调用的服务例程调用该方法，当前只适用于CIFS网络文件系统
flock(file, flag, lock) | 用于定制flock()系统调用的行为，Linux文件系统不使用该方法

