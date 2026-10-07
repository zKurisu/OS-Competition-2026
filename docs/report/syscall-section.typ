// 系统调用入口开销（板级实测，SG2002 riscv64，StarryOS 优化前/后 vs Linux）
#let n-getpid-before = 19350 // 原始 19.35 µs
#let n-getpid = 1920        // 上线后 1.9 µs
#let n-getpid-lin = 505     // 同机 Linux

= 系统调用入口开销

系统调用入口开销指用户态陷入内核、执行完毕再返回这条路径上，每次调用都要支付的固定成本，与调用具体做什么、是否触及调度或内存无关。在 riscv64 上，用户态执行 `ecall` 指令触发同步异常陷入内核态，内核保存现场、按调用号分发到处理函数、处理函数返回后再恢复现场、`sret` 返回用户态。这段路径的耗时是所有系统调用共同承担的固定成本，调用体本身越轻，它在总耗时中的占比越高。

最纯粹的探针是空系统调用 `getpid`，其处理体只取回一个已在内存中的进程号，几乎不做任何工作，测得的时延近乎全部来自陷入与返回路径。`syscost.c` 测得 StarryOS 的 `getpid` 原始需 `#n-getpid-before` ns，同机 Linux 仅 `#n-getpid-lin` ns，相差约 38 倍。一个不涉及调度、不涉及内存、仅进出内核一趟的调用仍慢 38 倍，说明差距落在这条路径本身。本节先剖析这条路径的构成，指出每次调用都要支付而多数调用并不使用的几处成本，再说明各处的机制与对应优化，最后给出结果。

== 陷入路径的构成

在 riscv64 上，一次系统调用的时延由两部分构成。第一部分是陷入往返本身，即 `uctx.run()` 一整趟：`ecall` 进入、保存通用寄存器现场、按调用号查表分发、处理函数执行、恢复现场、`sret` 返回。这一段由 axcpu 的架构代码实现，是 ArceOS、StarryOS、Axvisor 三套系统共用的底座；`getpid` 这类空调用的处理体只占其中极小一部分，其时延几乎全部是这趟往返。第二部分是返回路径上的一组固定记账，在处理函数返回之后、恢复用户态现场之前执行，用于维护跟踪、定时器、CPU 时间与安全策略等每进程状态。StarryOS 此前在这段返回路径上串接了几处工作，每次系统调用返回都完整执行一遍，而绝大多数调用并不需要其中任何一处。`getpid` 的 `#n-getpid-before` ns 正是这两部分之和。

== 每次调用固定支付的成本

以下几处均为 StarryOS 此前的既有行为，逐一说明其作用，以及在 `getpid` 路径上冗余的原因。

=== ptrace 停点

ptrace 是进程调试与系统调用跟踪机制，被跟踪进程在每次系统调用的进入与退出处停下，把控制权交给跟踪者读取或修改其状态。StarryOS 此前在每次系统调用返回时都执行一遍这套停点判断与相关状态检查，即便当前进程未被任何跟踪者附加。对未被跟踪的进程，这段逻辑的结论恒为无需停下，其执行不产生任何效果。

=== POSIX 定时器轮询

POSIX 定时器到期时须向进程投递信号，其到期检查此前由 `poll_process_timer` 在每次系统调用返回时执行。这段检查先获取全局进程表的读锁，再对当前进程做 Arc 升级，随后获取该进程 `posix_timers` 的互斥锁，最后遍历存放定时器的 `BTreeMap`。即便进程未装配任何 POSIX 定时器，这一整套加锁、升级、再加锁、遍历仍照常走完，遍历的是一棵空树，全程无一处能产生到期事件。

=== utime/stime 记账

CPU 时间记账把每个线程消耗的时间区分为用户态与内核态两部分，供 `getrusage`、`times` 与 `/proc` 读取。其实现要求在每次进出内核的边界上完成一次状态迁移并累加相应时段，而承载状态的时间字段为跨 CPU 共享，迁移须在一把 SMP 锁的保护下进行。锁架设于系统调用边界之上，每次进出内核各获取一次。在 riscv64 上这处成本还叠加了 128 位软件除法的开销：`monotonic_time_nanos()` 的纳秒换算在无 128 位除法指令的 C906 上退化为软件除法，比读 time CSR 贵一个量级。

=== 指令缓存刷新

StarryOS 此前在每次进入用户态时都执行 `fence.i`，刷新整个指令缓存。该指令的语义是同步指令流，用于自修改代码或可执行页填充后的指令一致性，对每次普通返回用户态并无必要，却是单项最大的固定成本。

=== seccomp 状态检查

seccomp 是系统调用过滤机制，未装配过滤规则的进程本应直接放行。StarryOS 此前在每次系统调用返回时仍会加锁并克隆 seccomp 状态，未装配规则时这段加锁与克隆同样不产生任何效果。

== 优化

针对上述成本各实现一处优化。各项只移除冗余，不改变对外可见的语义。

=== ptrace 快路径

将每次返回的停点判断收敛到一个预先算好的 `is_ptraced` 标志，对应 Linux 以 `TIF_SYSCALL_WORK` 位门控系统调用跟踪的做法：进程未被跟踪时整段 ptrace 停点逻辑不再进入，被跟踪时才照常执行。

=== poll_process_timer 跳过

在 `poll_process_timer` 之前引入一个无锁的 `count` 计数作为门槛。进程未装配任何 POSIX 定时器时该计数为零，前述的全局读锁、Arc 升级、互斥锁与 `BTreeMap` 遍历整段跳过，仅在确有定时器时才付出加锁与遍历的代价。

=== 无 itimer 跳过完整轮询

在 `TimeManager` 中增加 `itimer_armed()` 与轻量的 `poll_state()`，`set_timer_state` 在未装配 itimer 时跳过完整的定时器检查，仅在确有 itimer 装配时才执行完整的时间轮询。

=== fence_i 移除与指令缓存同步修复

去掉每次进入用户态都执行的 `fence.i`，同时在缺页填充可执行页之后执行 `flush_icache_all` 补偿指令缓存一致性。这样指令缓存只在真正需要时同步，普通返回路径不再承担刷新整个指令缓存的成本。

=== utime/stime 用 tick 累加

CPU 时间累加从 `monotonic_time_nanos()` 改为直接读 time CSR 的 `current_ticks()`，避开 128 位软件除法，纳秒换算延迟到真正读取 `rusage` 的 `output()` 时才做。

=== seccomp 快路径

增加一个无锁的 `seccomp_disabled` 原子镜像，未装配 seccomp 时跳过加锁与状态克隆，仅在确有过滤规则时才付出相应代价。

== 结果

上述优化叠加，`getpid` 由 `#n-getpid-before` ns 压至 `#n-getpid` ns，相对 Linux 由约 38 倍收敛至约 3.8 倍，已并入板级出厂配置。

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, center, center),
    table.header([版本], [getpid (ns)], [相对 Linux]),
    [Linux], [#n-getpid-lin], [1×],
    [StarryOS 原始], [#n-getpid-before], [38×],
    [三处记账优化], [16000], [32×],
    [fence_i 移除 + icache 修复], [3710], [7.3×],
    [128 位除法 → tick], [2600], [5.1×],
    [seccomp 快路径], [#n-getpid], [3.8×],
  ),
  caption: [getpid 微基准逐层下降，板级实测]
)

用计时埋点（25 MHz time CSR，1 tick = 40 ns）对最终版本做的分解如下表，剩余差距主要落在 `handle` 段。

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (left, center, center, left),
    table.header([段], [ticks], [时间], [说明]),
    [trap 入口], [12], [480 ns], [uctx.run() 保存/恢复寄存器，已到架构地板],
    [handle], [24], [~960 ns], [set_timer_state + handle_syscall（含 Sysno 大 match + as_thread 下转）],
    [tail], [12], [480 ns], [信号检查 + poll_process_timer + set_timer_state(User)],
  ),
  caption: [最终版本的 getpid 时延构成]
)

残余的 3.8 倍主要落在 `handle` 段，是 `Sysno` 的稀疏大 `match` 与 `as_thread` 的下转两个固定成本，进一步优化收益递减，故不触碰。
