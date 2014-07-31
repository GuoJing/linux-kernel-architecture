---
layout:    post
title:     VFS相关的系统调用
category:  虚拟文件系统
description: VFS相关的系统调用...
tags: 系统调用 VFS
---
VFS提供了诸多的接口以便可以简单的调用，这些系统调用涉及文件系统、普通文件、目录文件以及符号链接文件。另外还有少数几个由VFS处理的其他系统调用例如*ioperm()*，*ioctl()*、*pipe()*等。

系统调用名                   | 说明
------------               | -------------
mount() umonut() umount2() | 安装/卸载文件系统
sysfs()                    | 获取文件系统信息
statfs() fstatfs() statfs64() fstatfs64() | 获取文件系统统计信息
ustat() chroot() pivot_root() | 更改根目录
chdir() fchdir() getcwd()  | 对当前目录进行操作
mkdir() rmdir()            | 创建和删除目录操作
get\_dents() getdents64() readdir() link() unlink() rename() lookup\_dcookie() readlink() symlink() | 对软连接进行操作
chown() fchown() lchown() chown16() fchown16() lchown16() | 更改文件所有者性
chmod() fchmod() utime()   | 更改文件属性
stat() fstat() lstat() access() oldstat() oldfstat() oldlstat() stat64() lstat64() fstat64() | 获取文件状态
open() close() creat() umask() | 打开关闭创建文件操作
dup() dup2() fcntl() fcntl64() | 对文件描述符进行操作
select() poll()            | 等待一组文件描述符上发生的事件
truncate() ftruncate() truncated64() ftruncate64() | 更改文件长度
lseek() _llseek()          | 更改文件指针
read() write() readv() writev() sendfile() sendfile64) readahead() | 进行文件I/O操作
io\_setup() io\_submit() io\_getevents() io\_cancel() io\_destroy() | 异步I/O
pread64() pwrite64()       | 搜索并访问文件
nmap() nmap2() munmap() madvise() mincore() remap\_file\_pages() | 处理文件内存映射
fdatasync() fsync() sync() msync()| 同步文件处理
flock()                    | 处理文件锁
setxattr() lsetxattr() fsetxattr() getxattr() lgetxattr() fgetxattr() listxattr() llistxattr() flistxattr() removexattr() lremovexattr() fremovexattr() | 处理文件扩展属性

虽然VFS是应用程序和具体文件系统之间的一层，不过，在某些情况下，一个文件操作可能由VFS本身去执行，无需调用低层函数。

例如，当某个进程关闭一个打开的文件时，并不需要涉及磁盘上的相应文件，因此VFS只需释放对应的文件对象。

同样，当系统调用*lseek()*修改一个文件指针，而这个文件指针是打开文件与进程交互所涉及的一个属性时，VFS就只需修改对应的文件对象，而不必访问磁盘上的文件，因此，无需调用具体文件系统的函数，所以可以把VFS看成『通用』文件系统，它在必要时才需要依赖某种具体的文件系统。
