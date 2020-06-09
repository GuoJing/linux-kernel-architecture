---
layout:    post
title:     文件系统处理
category:  虚拟文件系统
description: 文件系统处理...
---
就像每个传统的Unix系统一样，Linux也使用系统的根文件系统，它由内核在引导阶段直接安装，并拥有系统初始化脚本以及最基本的系统程序。

其他文件系统要么由初始化脚本安装，要么由用户直接安装在已安装文件系统的目录上。作为一个目录树，每个文件系统豆邮自己的根目录（*root directory*）。安装文件系统的这个目录称之为安装点（*mount point*）已安装文件系统属于安装点目录的一个子文件系统。例如*/proc*虚拟文件系统是系统的根文件系统的孩子。已安装文件系统的根目录隐藏了父文件系统的安装点目录原来的内容，而且父文件系统的整个子树位于安装点之下。

### 命名空间 ###

在传统的Unix系统中，只有一个已安装文件系统树，从系统的根文件系统开始，每个进程通过指定合适的路径名可以访问已安装文件系统中的任何文件。从这个方面考虑，Linux更加精确：即每个进程可拥有自己的已安装文件系统树，叫做进程的命名空间。

通常大多数进程共享一个命名空间，即位于系统的根文件系统且被*init*进程使用的已安装文件系统数，不过，如果*clone()*系统调用以*CLONE_NEWNS*标志创建一个新进程，那么进程将获取一个新的命名空间。这个新的命名空间随后由子进程继承。

当进程安装或卸载一个文件系统时，仅修改它的命名空间。因此，所做的修改对共享同一命名空间的所有进程都是可见的，并且也只对它们可见。进程甚至可通过使用Linux特有的*pivot_root()*系统调用来改变它的命名空间的根文件系统。

### 文件系统的安装 ###

在大多数传统的Unix内核中，每个文件只能安装一次，并且使用*mount*命令安装。在使用*umount*命令卸载该文件系统前，所有其他作用于之前挂载的文件系统的命令都会失效。

但是Linux有所不同，同一个文件系统被安装多次时可能的，当然，如果一个文件系统被安装了n次，那么它的根目录就可以通过n个安装点来访问。尽管同一个文件系统可以通过不同的安装点来访问，但是文件系统的确时唯一的，因此，不管一个文件系统被安装了多少次，都只有一个超级块对象。

把多个安装堆叠在一个单独的安装点上也是允许的，尽管已经使用先前安装下的文件和目录的进程可以继续使用，但在同一安装点上的新安装隐藏前一个安装的文件系统。当最顶层的安装被删除时，下一层的安装再一次变为可见。

但这个时候跟踪已安装的文件系统会变得非常困难。对于每一个安装操作，内核必须在内存中保存安装点和安装标志，以及要安装文件系统与其他已安装文件系统之间的关系。这样的信息保存在已安装文件系统的描述符中，每个描述符时一个*vfsmount*类型的数据结构。

#### <include/linux/mount.h> ####

{% highlight c++ %}
struct vfsmount {
    struct list_head mnt_hash;
    struct vfsmount *mnt_parent;
    struct dentry *mnt_mountpoint;
    struct dentry *mnt_root;
    struct super_block *mnt_sb;
    struct list_head mnt_mounts;
    struct list_head mnt_child;
    int mnt_flags;
    const char *mnt_devname;
    struct list_head mnt_list;
    struct list_head mnt_expire;
    struct list_head mnt_share;
    struct list_head mnt_slave_list;
    struct list_head mnt_slave;
    struct vfsmount *mnt_master;
    struct mnt_namespace *mnt_ns;
    int mnt_id;
    int mnt_group_id;
    atomic_t mnt_count;
    int mnt_expiry_mark;
    int mnt_pinned;
    int mnt_ghosts;
#ifdef CONFIG_SMP
    int *mnt_writers;
#else
    int mnt_writers;
#endif
};
{% endhighlight %}

字段                  | 说明
------------          | -------------
mnt_hash              | 用于散列链表的指针
mnt_parent            | 指向父文件系统，这个文件系统安装在其上
mnt_mountpoint        | 指向这个文件系统安装点目录的dentry
mnt_root              | 指向这个文件系统根目录的dentry
mnt_sb                | 指向这个文件系统的超级块对象
mnt_mounts            | 包含所有文件系统描述符链表的头
mnt_child             | 用于已安装文件系统链表mnt\_mounts的指针
mnt_count             | 引用计数器
mnt_flags             | 标志
mnt\_expiry\_mark     | 文件系统是否到期
mnt_devname           | 设备文件名
mnt_list              | 已安装文件系统描述符的namespace链表的指针
mnt_fslink            | 具体文件系统到期链表指针
mnt_ns                | 指向安装了文件系统的进程命名空间的指针
mnt_share             | 共享装载
mnt_master            | 从属装载
mnt_slave             | 从/子装载
mnt\_slave\_list      | 从/子装载的链表的头
mnt_id                | 装载的id
mnt\_group\_id        | 装载的组id