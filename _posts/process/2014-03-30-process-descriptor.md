---
layout:    post
title:     进程描述符
category:  进程
description: 进程描述符...
tags: 进程描述符 进程状态 task_struct 资源限制
---
为了进程管理，内核必须对每个进程所做的事情进行清楚的描述。比如内核需要知道进程的优先级，进程当前的状态，在挂起和恢复进程的时候，需要对进程进行相应的操作。进程描述符还描述了进程使用的地址空间，访问的文件等等，这些都是进程描述符的作用。

进程描述符都是*task_struct*类型的结构，它的字段包含了与一个进程相关的所有信息。因为进程描述符中存放了那么多信息，所以它是非常复杂的，它不仅仅包括了很多进程属性的字段，还有一些字段包括了指向其他数据结构的指针，如下图：

{:.center}
![task struct](/linux-kernel-architecture/images/task_struct.png){:style="max-width:600px"}

{:.center}
进程描述符结构

进程有很多状态，从代码中我们可以看：

    - volatile long state;
      /* -1 unrunnable, 0 runnable, >0 stopped */
      represents the state of the process.
      Authorized states are 
      TASK_RUNNING, TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE,
      TASK_STOPPED, TASK_TRACED
      TASK_ZOMBIE and TASK_DEAD

可运行状态：

* TASK\_RUNNING: 要么在CPU上执行，要么准备执行。
* TASK\_INTERRUPTIBLE: 进程被挂起（睡眠），直到某个为真的条件触发，产生一个硬件中断，释放进程正等待的系统资源，或传递一个信号都可以唤醒进程。
* TASK\_UNINTERRUPTIBLE: 不可中断的等待状态，与把信号传递给睡眠进程不能改变它的状态[^1]。
* TASK\_STOPPED: 进程的执行被暂停，当收到SIGSTOP、SIGTSTP、SIGTTIN或SIGTTOU信号后，进入暂停状态。
* TASK\_TRACED: 跟踪状态，进程的执行由debugger程序暂停。
* TASK\_ZOMBIE[^2]: 进程执行被终止，但是父进程还没有发布wait4或waitpid系统调用返回有关死亡进程的信息。
* TASK\_DEAD[^2]: 僵死撤销状态。

[^1]: 这种状态很少用到，但在一些特定的情况下，这种状态是很有用的。例如，当进程打开一个设备文件，其相应的设备驱动程序开始探测相应的硬件设备时会用到这种状态。探测完成之前，设备驱动程序不能被中断。

[^2]: 貌似有的版本叫EXIT_ZOMBIE和EXIT_DEAD。

task_struct可以看作是进程的一个实例，我并不想列出所有的代码，实际上理解进程也无需了解代码，毕竟笔记的目的只是为了了解，而不是做内核开发。但有时候特定的代码还是没办法完全忽略的。

#### <include/linux/sched.h> ####

{% highlight c++ %}
/*
 * 虽然有很多地方我们暂时还不是很了解，但是
 * 以后会有很多机会重新回到这个数据结构，毕
 * 竟这是内核中非常重要的数据结构。
 * 进程管理和内存管理都是内核中非常重要的知
 * 识，需要长期的理解和消化。
 */
struct task_struct {
  // -1表示不可运行，0表示可运行，大于0表示停止
  volatile long state;
  void *stack;
  atomic_t usage;
  // 每进程标志，上下文定义
  unsigned int flags;
  unsigned int ptrace;

  // 大内核锁的深度
  int lock_depth;

#ifdef CONFIG_SMP
#ifdef __ARCH_WANT_UNLOCKED_CTXSW
  int oncpu;
#endif
#endif
  // 优先级
  int prio, static_prio, normal_prio;
  unsigned int rt_priority;
  const struct sched_class *sched_class;
  struct sched_entity se;
  struct sched_rt_entity rt;

#ifdef CONFIG_PREEMPT_NOTIFIERS
  /* 同步的通知者 */
  struct hlist_head preempt_notifiers;
#endif
  unsigned char fpu_counter;
#ifdef CONFIG_BLK_DEV_IO_TRACE
  unsigned int btrace_seq;
#endif

  unsigned int policy;
  cpumask_t cpus_allowed;

#ifdef CONFIG_TREE_PREEMPT_RCU
  int rcu_read_lock_nesting;
  char rcu_read_unlock_special;
  struct rcu_node *rcu_blocked_node;
  struct list_head rcu_node_entry;
#endif

#if defined(CONFIG_SCHEDSTATS) \
  || defined(CONFIG_TASK_DELAY_ACCT)
  struct sched_info sched_info;
#endif

  struct list_head tasks;
  struct plist_node pushable_tasks;

  struct mm_struct *mm, *active_mm;

/* 进程状态 */
  int exit_state;
  int exit_code, exit_signal;
  // 在父进程终止时发送的信号
  int pdeath_signal;

  unsigned int personality;
  unsigned did_exec:1;
  unsigned in_execve:1;
  unsigned in_iowait:1;


  unsigned sched_reset_on_fork:1;

  // pid和组id
  pid_t pid;
  pid_t tgid;

#ifdef CONFIG_CC_STACKPROTECTOR
  unsigned long stack_canary;
#endif

  /* 
   * 分别指向原父进程
   * 最年轻的子进程
   * 年幼的兄弟进程
   * 年长的兄弟进程的指针
   */
  struct task_struct *real_parent;
  struct task_struct *parent;
  struct list_head children;
  struct list_head sibling;
  // 线程组的组长
  struct task_struct *group_leader;

  struct list_head ptraced;
  struct list_head ptrace_entry;

  struct bts_context *bts;

  /* PID/PID散列表的关系 */
  struct pid_link pids[PIDTYPE_MAX];
  struct list_head thread_group;

  // 用于vfork()
  struct completion *vfork_done;
  // CLONE_CHILD_SETTID
  int __user *set_child_tid;
  // CLONE_CHILD_CLEARTID
  int __user *clear_child_tid;

  cputime_t utime, stime, utimescaled, stimescaled;
  cputime_t gtime;
  cputime_t prev_utime, prev_stime;
  // 上下文切换计数器
  unsigned long nvcsw, nivcsw;
  // 单调时间
  struct timespec start_time;
  // 启动以来的时间
  struct timespec real_start_time;
  // 内存管理器失效和页交换信息
  unsigned long min_flt, maj_flt;

  struct task_cputime cputime_expires;
  struct list_head cpu_timers[3];

/* 进程身份 */
  const struct cred *real_cred;
  const struct cred *cred;
  struct mutex cred_guard_mutex;
  struct cred *replacement_session_keyring;

  char comm[TASK_COMM_LEN];

/* 文件系统信息 */
  int link_count, total_link_count;
#ifdef CONFIG_SYSVIPC
/* ipc相关信息 */
  struct sysv_sem sysvsem;
#endif
#ifdef CONFIG_DETECT_HUNG_TASK
  unsigned long last_switch_count;
#endif
/* 当前进程特定于CPU的状态信息 */
  struct thread_struct thread;
/* 文件系统信息 */
  struct fs_struct *fs;
/* 打开文件信息 */
  struct files_struct *files;
/* 命名空间 */
  struct nsproxy *nsproxy;
/* 信号处理程序 */
  struct signal_struct *signal;
  struct sighand_struct *sighand;

  sigset_t blocked, real_blocked;
  sigset_t saved_sigmask;
  struct sigpending pending;

  unsigned long sas_ss_sp;
  size_t sas_ss_size;
  int (*notifier)(void *priv);
  void *notifier_data;
  sigset_t *notifier_mask;
  struct audit_context *audit_context;
#ifdef CONFIG_AUDITSYSCALL
  uid_t loginuid;
  unsigned int sessionid;
#endif
  seccomp_t seccomp;

/* 进程组的信息 */
    u32 parent_exec_id;
    u32 self_exec_id;
  // 保护mm，files等信息的自旋锁
  spinlock_t alloc_lock;

#ifdef CONFIG_GENERIC_HARDIRQS
  /* IRQ处理进程 */
  struct irqaction *irqaction;
#endif

  spinlock_t pi_lock;

#ifdef CONFIG_RT_MUTEXES
  struct plist_head pi_waiters;
  struct rt_mutex_waiter *pi_blocked_on;
#endif

#ifdef CONFIG_DEBUG_MUTEXES
  struct mutex_waiter *blocked_on;
#endif
#ifdef CONFIG_TRACE_IRQFLAGS
  unsigned int irq_events;
  int hardirqs_enabled;
  unsigned long hardirq_enable_ip;
  unsigned int hardirq_enable_event;
  unsigned long hardirq_disable_ip;
  unsigned int hardirq_disable_event;
  int softirqs_enabled;
  unsigned long softirq_disable_ip;
  unsigned int softirq_disable_event;
  unsigned long softirq_enable_ip;
  unsigned int softirq_enable_event;
  int hardirq_context;
  int softirq_context;
#endif
#ifdef CONFIG_LOCKDEP
# define MAX_LOCK_DEPTH 48UL
  u64 curr_chain_key;
  int lockdep_depth;
  unsigned int lockdep_recursion;
  struct held_lock held_locks[MAX_LOCK_DEPTH];
  gfp_t lockdep_reclaim_gfp;
#endif

/* 日志文件系统信息 */
  void *journal_info;

/* 快设备信息 */
  struct bio *bio_list, **bio_tail;

/* 虚拟内存状态 */
  struct reclaim_state *reclaim_state;

  struct backing_dev_info *backing_dev_info;

  struct io_context *io_context;

  unsigned long ptrace_message;
  siginfo_t *last_siginfo;
  struct task_io_accounting ioac;
#if defined(CONFIG_TASK_XACCT)
  u64 acct_rss_mem1;
  u64 acct_vm_mem1;
  cputime_t acct_timexpd; /* stime + utime since last update */
#endif
#ifdef CONFIG_CPUSETS
  nodemask_t mems_allowed;
  int cpuset_mem_spread_rotor;
#endif
#ifdef CONFIG_CGROUPS
  struct css_set *cgroups;
  struct list_head cg_list;
#endif
#ifdef CONFIG_FUTEX
  struct robust_list_head __user *robust_list;
#ifdef CONFIG_COMPAT
  struct compat_robust_list_head __user *compat_robust_list;
#endif
  struct list_head pi_state_list;
  struct futex_pi_state *pi_state_cache;
#endif
#ifdef CONFIG_PERF_EVENTS
  struct perf_event_context *perf_event_ctxp;
  struct mutex perf_event_mutex;
  struct list_head perf_event_list;
#endif
#ifdef CONFIG_NUMA
  struct mempolicy *mempolicy;
  short il_next;
#endif
  atomic_t fs_excl;
  struct rcu_head rcu;

  // ...
{% endhighlight %}

### 进程资源限制 ###

每个进程都有一组相关的资源限制（*resource limit*），限制指定了进程能使用的系统资源数量。这些资源限制避免用户过分使用系统资源（CPU，磁盘空间等）。堆当前进程的资源限制存放在*current->signal->rlim*字段[^3]，即进程描述符的一个字段。这个字段类型为rlimit结构的数组，每个资源限制对应一个元素：

[^3]: current可以获取当前进程。

{% highlight c++ %}
struct rlimit {
    unsigned long rlim_cur;
    unsigned long rlim_max;
};
{% endhighlight %}

资源限制包括：

字段名              | 说明
------------       | -------------
RLIMIT_AS          | 进程地址空间的最大数，以字节为单位，当进程使用malloc或相关函数的时候会检查这个值
RLIMIT_CORE        | 内存信息转储文件的大小，当一个进程异常终止时，内核在进程的当前目录下创建内存信息转储文件之前检查这个值
RLIMIT_CPU         | 进程使用CPU的最长时间，以秒为单位
RLIMIT_DATA        | 堆大小的最大值
RLIMIT_FSIZE       | 文件大小的最大值，如果进程把一个文件的大小扩充到这个值，内核就给这个进程发送SIGXFSZ信号
RLIMIT_LOCKS       | 文件锁数量的最大值
RLIMIT_MEMLOCK     | 非交换内存的最大值，当进程试图通过mlock或者mlockall锁住页框时，会检查这个值
RLIMIT_MSGOUEUE    | POSIX消息队列中的最大字节数
RLIMIT_NOFILE      | 打开文件描述符的最大数，打开一个文件或复制一个文件时会检查这个值
RLIMIT_NPROC       | 用户能拥有的进程最大数
RLIMIT_RSS         | 进程锁拥有的页框最大数
RLIMIT_SIGPENDING  | 进程挂起信号的最大数
RLIMIT_STACK       | 栈大小的最大值，内核在扩充进程的用户态堆栈之前检查这个值