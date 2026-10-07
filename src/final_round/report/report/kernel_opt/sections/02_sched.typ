#import "_prelude.typ": *

= 进程创建、exec 与上下文切换

这一章处理三个互相关联的指标：`fork`+`exit`+`waitpid`、`fork`+`execve`+`waitpid`
与一次上下文切换。优化之前它们分别落后同板 Linux 22.2 倍、18.1 倍与 20.7 倍。
三者共享同一批底层结构（页表复制、任务入队、地址空间退休、EEVDF 就绪队列），
所以这一章的做法是先把整条链路拆到段，再挑出*纯算法、无行为变化*的部分动手。

== 优化前的账

#tablefigure(
  booktable(
    (40%, 20%, 20%, 20%),
    ([指标], [Linux 5.10.4], [优化前], [差距]),
    (
      ([`fork` + `exit` + `waitpid`], [#n-forkexit-lin µs], [#n-forkexit-pre µs], [22.2×]),
      ([`fork` + `execve` + `waitpid`], [#n-forkexec-lin µs], [#n-forkexec-pre µs], [18.1×]),
      ([上下文切换],[#n-ctx-lin µs], [#n-ctx-pre µs], [20.7×]),
      ([双线程 `sched_yield` 交接], [#n-yield-lin µs], [#n-yield-pre µs], [24.8×]),
    ),
  ),
  caption: [进程与调度面的优化起点。四项同源，差距都在一个数量级到两个数量级之间],
)

== `fork` 的全路径归因

`fork_exit` 优化前是 7 497 µs，此前只有一个总数。给内核侧（`mm/fault_attrib.rs`）
与任务侧（`components/ax-task/src/diag.rs`）各加一组分段计数器，全部渲染在
`/proc/fault_attrib`，用"工作负载前后的快照之差"取每次调用的平均值，得到的账是：

#tablefigure(
  booktable(
    (30%, 16%, 54%),
    ([层], [每次], [明细（µs）]),
    (
      ([`fork()` 系统调用], [4 418], [try_clone 1 528 / 首次入队激活 1 724 / 建线程 591 / fd+FS+线程 194 / 信号+映像+进程台账 197 / 发布 102 / pid+cgroup+命名空间 17]),
      ([子进程 `_exit()`], [1 013], [fd 271 / 进程台账 274 / 僵尸发布+信号+唤醒 481 / 退地址空间 2.4]),
      ([子地址空间回收], [1 459], [*不在* `fork_exit` 的墙钟里——由内存回收线程异步完成，每次 fork+exit 约 1.4 ms CPU]),
      ([上下文切换], [226×11–14 次], [`fork_exit` 里约 2.6–3.2 ms 花在这里]),
    ),
  ),
  caption: [`fork`+`exit` 的分段账（优化前，单位 µs/次）。这张表直接改写了优化优先级：最大的两块分别是"首次入队触发的重调度"与"上下文切换次数" ],
)

归因给出两条决定性判据，它们把后续方向定死了：

#enum(
  [*首次入队激活的 1.7 ms 全在守卫析构。* 把它拆成三段后：入队 44 µs、
   收尾 0.6 µs、定时器 10.5 µs，剩下的 1 852 µs 全在 `RuntimeIrqGuard` 的析构里
   ——激活时 `finish_owner_enqueue` 已经请求重调度，守卫析构于是直接进入
   "从 IRQ 守卫退出时挑下一个任务"。],
  [*这 1.7 ms 不是"子进程占用了 CPU"。* 让子进程在 `fork` 返回后先忙等
   T ms 再退出，父侧 `fork()` 的耗时完全不随 T 增长（子进程快速退出 5 527 µs，
   忙等 10 ms 后退出 4 529 µs）。所以它是*切换本身*的成本：切到一个全新任务
   再切回来。],
)

顺带否掉了两个假设：硬件 ASID 是可用的（`asid_tag_capacity=65536`，已经处于
标签模式，不存在"每次切换都全量刷 TLB"），以及子地址空间析构并不在 `fork_exit`
的关键路径上。

=== 已落地之一：取消每个叶子的第二次页表走查

`occupied_leaf_records()` 本来已经拿到页表遍历时的原始 PTE，却对每个叶子再调
一次 `pt.query()` 复核。改成复用遍历结果后，单个叶子的克隆成本从 99 µs 降到
82 µs。

=== 已落地之二：所有者发布去重的复杂度

`publish_prepared_pte_owners()` 用线性 `Vec::contains` 检测重复键。批量填充一次
要发布几百个所有者，代价是 O(n²)。换成 `BTreeSet` 后，这段从 120 µs 降到 99 µs。

这两处纯算法改动合计让 `try_clone` 从 1 747 µs 降到 1 528 µs、`fork()` 系统调用
从 4 739 µs 降到 4 418 µs。

=== 已落地之三：地址空间退休不再逐页摘除

子进程退出时要退休整个地址空间。原实现逐页 `unmap`，每次都要走查页表、
再走查一次页表、更新地址空间账目。改成整段交给批量路径后：

#tablefigure(
  booktable(
    (50%, 25%, 25%),
    ([项], [优化前], [优化后]),
    (
      ([子地址空间退休 `exit_clear`], [#n-exit-clear-pre µs], [*#n-exit-clear-post µs*（8.7×）]),
      ([`fork_exit` 端到端], [#n-forkexit-pre µs], [#n-forkexit-post µs]),
    ),
  ),
  caption: [退休路径批量化。这 3.2 ms 的收益不在 `fork_exit` 的墙钟里（它由回收线程异步做），但直接减少了每次 fork+exit 的 CPU 占用],
)

== `exec`：从 32 ms 到 4.5 ms

`fork`+`execve` 里，`execve` 的内核侧成本优化前是 32.3 ms。分段后 88% 落在一处：

#tablefigure(
  booktable(
    (34%, 22%, 46%),
    ([段], [ms/次], [说明]),
    (
      ([`exec_load`], [31.7], [装载映像]),
      ([└ `exec_populate`], [28.3], [*88%*：static-PIE 把每个 `PT_LOAD` 段整段物化]),
      ([└ `exec_map` / `exec_reloc` / `exec_parse`], [19.5], [嵌套计数：段映射含上面的物化；重定位 0.56、解析 0.05]),
      ([`exec_stack`], [1.13], [建立用户栈]),
      ([`exec_install`], [0.25], [安装新映像]),
    ),
  ),
  caption: [`execve` 的分段（优化前）。重定位与解析都不是问题，问题在页物化],
)

再往物化里挖，得到三条关键的否证：`file_pop_*`（文件后端的物化探针）*全程为 0*，
说明段映射走的是 COW 而不是共享文件映射；块层读数在一次 51 轮的 exec 压力前后
*增量为零*，说明 exec 完全不读 SD 卡；因此每页 120 µs 的成本是
"一次帧分配 + 三次 4 KiB 拷贝（页缓存 → scratch → 缓冲 → 新帧）+ `PageObject`
与 COW 索引 + 装页表"。

据此做了三刀：

#enum(
  [*文件后端按连续 run 批量处理。* 物化时把"逐页一次 `io_lock`"改成
   `CachedFile::pin_pages_run`（整段一次锁）、`FilePageDomain::reserve_pages_run`
   （整段一次域锁），并把每段一次的全表 `prune_stale` 收成一次。],
  [*只物化带写权限的段。* static-PIE 的重定位只写 `.got` / `.data.rel.ro` /
   `.bss`，只读段完全可以按需缺页——Linux 也是惰性的。改成只整段物化
   `PT_LOAD` 里带 `WRITE` 的那些，只读段交给缺页路径。],
  [*单页缺页不再每次跑 O(表长) 的清理。* `reserve_page` 原来每次都要扫一遍
   陈旧条目表；改成"命中陈旧条目才清 + 每 512 次兜底"，单页缺页因此每页少一次
   全表扫描。],
)

实测：`exec_load` 从 31.7 ms 降到 4.5 ms，其中 `exec_populate` 从 28.3 ms 降到
1.2 ms；exec 内部的缺页数从约 200 页/次降到 79 页/次；`fork_exec_exit` 从
#n-forkexec-pre µs 降到 #n-forkexec-post µs（−49%）。

值得一提的是，这一步与参考实现的路线完全不同：`ref` 用 `MADV_POPULATE_*` 把
整段一次性铺好，我们是*反过来减少要铺的页*，因此两者的收益不会互相抵消。

== 上下文切换：归因清楚了，但没动

一次 `ctx_switch` 优化前是 #n-ctx-pre µs，Linux #n-ctx-lin µs。它不是一个"切换指令"
的耗时，而是"管道写/读系统调用 + 阻塞 + 唤醒 + 一次切换"的整包成本。把它拆开：

#tablefigure(
  booktable(
    (46%, 22%, 32%),
    ([段], [µs/次], [说明]),
    (
      ([管道写（含唤醒）], [61], [其中唤醒 49：选中等待者 0.35、交付 43–47]),
      ([└ 入队：EEVDF 就绪树插入], [13.6], [红黑树插入与虚拟时间更新]),
      ([└ 入队：其余六段], [11.7], [实体克隆、`settle_current`、`push_class` 等]),
      ([调度入口], [2.1×4–6 次], [其中约 1/3 是空转：进去发现不需要切换，仍付全额]),
      ([调度决策], [15.6], [EEVDF 的选取与虚拟时间维护]),
      ([裸交接（`sw_*`）], [5], [地址空间激活 2.0 + CPU 绑定 0.4 + 汇编交接 2.2]),
    ),
  ),
  caption: [一次上下文切换的账。*没有单一热点*：十几处 1–15 µs 的固定开销叠加，其中"每次切换要进 4–6 次调度器、1/3 是空转"是可以立刻回收的一块],
)

这一章在此止步，原因是它已经不是"修一处 bug"的规模：要逼近 Linux 的 10.2 µs，
必须重构 EEVDF 热路径（空转入口前置判定、入队合并快照、收紧 `settle_current`
与虚拟时间更新），三条都动调度器不变式。本轮先把归因做完——这是后续任何改动的
前提——并把候选方案记入第 8 章。

顺带记录一条*负结果*，避免以后重复尝试：把"首次入队立刻抢占"改成 Linux 的
`WF_FORK` 语义（用运行期旋钮在同一镜像上做 A/B），只值 `fork_exit` 0.4%、
`fork_exec_exit` 0.9% 的改善。原因是那 1.7 ms 里子进程该做的工作本来就要付，
抑制抢占只是把时间从 `fork` 挪到 `waitpid`。

== 实测

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([`fork` + `exit` + `waitpid`], [#n-forkexit-lin µs], [#n-forkexit-pre µs], [#n-forkexit-post µs]),
      ([`fork` + `execve` + `waitpid`], [#n-forkexec-lin µs], [#n-forkexec-pre µs], [#n-forkexec-post µs]),
      ([└ 其中 execve 内核侧], [#abl[未测]], [#n-exec-pre ms], [*#n-exec-post ms*]),
      ([上下文切换], [#n-ctx-lin µs], [#n-ctx-pre µs], [#n-ctx-post µs]),
      ([双线程 `sched_yield` 交接], [#n-yield-lin µs], [#n-yield-pre µs], [#n-yield-post µs]),
      ([子地址空间退休], [#abl[未测]], [#n-exit-clear-pre µs], [#n-exit-clear-post µs]),
    ),
  ),
  caption: [进程与调度面的实测。`fork_exec_exit` 收掉 49%，`fork_exit` 收掉 14%；上下文切换本身本轮只做了归因，因此基本未动],
)

`fork_exit` 只降了 14%，看起来与前面几处改动不成比例。原因在归因表里已经写明：
它剩下的时间主要不是页表复制，而是"切到一个新任务再切回来"的 11–14 次上下文切换，
以及 EEVDF 热路径上的固定开销。因此 `fork` 的下一步与上下文切换是同一件事，
两者必须一起做。
