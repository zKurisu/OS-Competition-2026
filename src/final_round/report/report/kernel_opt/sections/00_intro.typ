#import "_prelude.typ": *

= 优化总览与评测口径

本分册只讲内核层。应用层的视觉推理链路（JPEG 硬解、VPSS 几何变换、TPU 推理、
检测后处理与追球控制）另见《第二部分：追球推理链路》，两者共用同一块板、同一份
用户态 ELF，互不重叠。

内核层的工作目标很具体：项目立项时的横向对比显示，同一块板、同一份静态
riscv64 ELF 上，StarryOS 在“每次系统调用、每次进程创建、每次缺页、每次文件读”
这些*固定开销*上比厂商 Linux 贵一到两个数量级，而在内存带宽、大块顺序写、
冷启动这些*带宽或总量型*指标上并不落后。因此这一阶段不做功能补全，而是沿着
“把每次都要付的固定成本降下来”这一条主线，逐个热点做归因、改机制、再实测。

== 评测平台与口径

平台与对照物固定如下，本分册所有数字都在这一组条件下取得：

#tablefigure(
  booktable(
    (20%, 80%),
    ([项], [内容]),
    (
      ([板卡], [#p-board，CPU 为 #p-cpu，内存 236 MiB]),
      ([对照系统], [#p-linux，卡上 `linux.sd`，同板同卡同一次上电周期内交替启动]),
      ([用户态], [同一份静态链接 riscv64 ELF。所有探针都是自研 C 程序，两边编译同一份源码]),
      ([计时], [板端 `rdtime`（时基 1 MHz）+ 主机侧串口逐行时间戳；微基准取 20–100 轮中位]),
      ([口径], [每个指标三列：Linux 实测／我们优化之前／我们优化之后]),
    ),
  ),
  caption: [评测平台与对照口径],
)

有三条读表纪律，先说清楚，否则数字容易被误读：

#enum(
  [*同板同 ELF 才算对照。* 所有“相对 Linux 的倍数”都取自本板实测的厂商内核，
   不引用其它论文或其它板卡的经验值。Linux 侧缺测的指标用 #abl[未测] 标出，
   不拿别处的数字补位。],
  [*冷启动受控 A/B。* 内核“优化前/后”的对比尽量在*同一次上电、同一份探针、
   交替顺序*下做（例如 `opt7 → opt10` 两两交替各测两遍取均值），以抵消“启动后
   第一次大分配明显更快”这类时间漂移。],
  [*探针本身有代价。* 热路径上的分段计时是每次系统调用多 12 次取时间戳，
   实测平白增加约 1.2 µs。凡是“优化前/后”的对照数字，探针都已撤掉；带探针的
   中间过程只在归因小节里出现，并注明口径。],
)

== 优化之前的总体画像

优化起点（2026-10-04 的 `ours` 基线镜像）与 Linux 的对照如下。这张表决定了后面
每一章的优先级：凡是差距在一个数量级以上的，都是“每个操作都要付的固定成本”；
凡是基本持平的，都是带宽型或总量型指标。

#tablefigure(
  booktable(
    (38%, 22%, 22%, 18%),
    ([指标], [Linux 5.10.4], [我们（优化前）], [差距]),
    (
      ([`getpid`（空系统调用）], [422.5 ns], [10 560 ns], [25.0×]),
      ([`pipe_wr`（4 KiB 往返）], [4 489 ns], [46 819 ns], [10.4×]),
      ([管道 ping-pong（含一次切换）], [26.0 µs], [445.7 µs], [17.1×]),
      ([`fork`+`exit`+`waitpid`], [338.1 µs], [7 497 µs], [22.2×]),
      ([`fork`+`execve`+`waitpid`], [2 407 µs], [43 537 µs], [18.1×]),
      ([上下文切换], [10.97 µs], [226.8 µs], [20.7×]),
      ([64 MiB 匿名首触（默认 4 KiB）], [7 899 ns/页], [1 302 123 ns/页], [165×]),
      ([ext4 `open`+`read`(1 KiB)+`close`], [42 µs], [10 320 µs], [246×]),
      ([8 MiB 顺序写 + `fsync`], [790 ms], [7 961 ms], [10.1×]),
      ([缓存命中大读（缓冲已触碰）], [671.6 MB/s], [374 MB/s], [1.80×]),
      ([缓存命中大读（每轮新缓冲）], [271.1 MB/s], [50.2 MB/s], [5.40×]),
      ([内存 `memcpy` / 顺序读带宽], [1.024 / 1.488 GB/s], [0.984 / 1.420 GB/s], [1.04× / 1.05×]),
      ([端到端冷启动（`bootm`→提示符）], [33.2 s], [13.21 s], [我方更快 2.5×]),
    ),
  ),
  caption: [优化起点的横向对照。前九行是“每个操作都要付的固定成本”，差距都在一个数量级以上；末四行是带宽型或总量型指标，本来就不落后],
)

这张表给出三点判断，后续九章都围绕它们展开：

+ *系统调用入口是最大的单点。* 一个什么都不做的 `getpid` 要 10.56 µs，是同板
  Linux 的 25 倍。它的处理体只取一个已在内存里的进程号，所以这 10.56 µs 几乎全部
  是“进入内核、返回用户态”这条固定路径。这也是第 2 章的对象。
+ *调度与进程生命周期的固定开销排在第二。* `fork`+`exit` 22 倍、上下文切换 20 倍、
  管道往返 17 倍、exec 18 倍，全都在同一个量级上。第 3 章把这条链路拆成
  “页表复制 / 首次入队 / 子进程析构 / 每次切换”四段分别处理。
+ *内存的“每页固定成本”比内存带宽问题严重得多。* 64 MiB 首触慢 165 倍，而
  `memcpy` 带宽只差 4%。说明缺的不是带宽，而是*每页一次事务*的簿记开销。
  第 4 章与第 5 章处理这一条（缺页路径、文件读路径）。

#kfig("F14_bandwidth_sg2002", caption: [五方对照下的内存带宽。`memcpy` 与顺序读在各方之间只差几个百分点——它说明本板的差距不在内存子系统，而在“每次操作要付多少固定成本”], width: 74%)

还有两条“看起来很小、实际很贵”的发现，分别对应第 6 章和第 7 章：ext4 上每次
`open`+`read`+`close` 要付一次约 10 ms 的同步日志提交（Linux 只在内存里改 atime），
以及启动期一个固定 2 s 的 DHCP 阻塞等待。

== 优化清单

下表是本阶段实际落地的改动，按子系统分组。每条都对应一个独立提交，且都满足
两个约束：*不与参考实现（报告团队的集成分支 `ref`）使用同一手段*，以及
*有“优化前/优化后”的同板 A/B 数据*。

#tablefigure(
  booktable(
    (13%, 47%, 40%),
    ([编号], [改动], [主要手段（与 `ref` 的差异）]),
    (
      ([B1], [返回用户态不再每次刷 I-cache], [把 `fence.i` 收敛到“用户映像可能陈旧”的少数事件上；`ref` 未做]),
      ([A1], [COW 页索引不再每次全量重建], [去掉每次插入的两遍 O(n) 存活计数，墓碑改在容量增长路径上摊还裁剪]),
      ([A3a], [`memcpy`/`memset` 从逐字节改字长循环], [消灭 64 位平台上的字节循环；`ref` 走的是 `dc zva`（aarch64 专属），riscv64 不可用]),
      ([A3b], [顺序缺页预取窗口（64 KiB）], [严格升序且私有匿名的缺页按窗批量物化；`ref` 是默认 2 MiB 大页，我们保持 4 KiB 叶子]),
      ([A3c], [窗口大小运行期旋钮 + 短流爬坡], [旋钮扫描定值 64 页，并按连续命中次数爬坡，避免短流被整窗放大]),
      ([A3d], [窗口内帧整块分配 + 子租约], [一次 `alloc_frame` 再切 4 KiB 子租约，块命中率 99.97%]),
      ([A3d′], [COW 页索引按 run 批量登记], [一次加锁、一次定位、一次整段落位，且全有或全无；`ref` 未做]),
      ([CC1], [地址空间退休不再逐页 unmap], [整段交给批量路径；子进程析构 3.57 ms → 0.41 ms]),
      ([H1], [exec 只物化可写段 + 按 run 批量 pin], [static-PIE 只读段改按需缺页；与 `ref` 的 `MADV_POPULATE_*` 路线完全不同]),
      ([H2], [页缓存 pin 住后直接拷给调用方], [去掉中间的 scratch 中转，少一次全量拷贝]),
      ([H3], [uaccess 整段快路径 / 整段 `populate_area`], [riscv64 无硬件探测，改成按段判定并整段物化]),
      ([H5], [`close` 不再无条件同步写 atime], [按 Linux 语义做 `relatime`，并用单调时钟而非墙上时钟判定]),
      ([D1], [脏页按连续 run 合并写回], [8 MiB 从 2048 次 4 KiB `write_at` 变成少数几次大块写]),
      ([D2], [页缓存上限 512 → 4096 页], [只改容量参数，不改回收策略]),
      ([E1], [启动期 DHCP 等待 2 s → 300 ms], [把固定阻塞等待改成带截止时间的轮询]),
    ),
  ),
  caption: [本阶段落地的内核改动。编号沿用内部优化清单，便于与原始测量记录对照],
)

== 优化之后的总体结果

#tablefigure(
  booktable(
    (31%, 17%, 17%, 17%, 18%),
    ([指标], [Linux], [优化前], [优化后], [优化后/ Linux]),
    (
      ([`getpid`（空系统调用）], [#n-getpid-lin ns], [#n-getpid-pre ns], [#n-getpid-post ns], [#n-getpid-ratio×]),
      ([`pipe_wr`（4 KiB 往返）], [#n-pipe-lin ns], [#n-pipe-pre ns], [#n-pipe-post ns], [#n-pipe-ratio×]),
      ([管道 ping-pong], [#n-ppong-lin µs], [#n-ppong-pre µs], [#n-ppong-post µs], [#n-ppong-ratio×]),
      ([`fork`+`exit`+`waitpid`], [#n-forkexit-lin µs], [#n-forkexit-pre µs], [#n-forkexit-post µs], [#n-forkexit-ratio×]),
      ([`fork`+`execve`+`waitpid`], [#n-forkexec-lin µs], [#n-forkexec-pre µs], [#n-forkexec-post µs], [#n-forkexec-ratio×]),
      ([上下文切换], [#n-ctx-lin µs], [#n-ctx-pre µs], [#n-ctx-post µs], [#n-ctx-ratio×]),
      ([双线程 `sched_yield` 交接], [#n-yield-lin µs], [#n-yield-pre µs], [#n-yield-post µs], [#n-yield-ratio×]),
      ([64 MiB 匿名首触（默认 4 KiB）], [#n-fault-lin-64 ns/页], [#n-fault-pre-64 ns/页], [#n-fault-a3d-64 ns/页], [5.6×]),
      ([64 MiB 首触（显式大页）], [#n-fault-huge-lin ns/页], [#n-fault-huge-pre ns/页], [#n-fault-huge-post ns/页], [1.41×]),
      ([ext4 `open`+`read`(1 KiB)+`close`], [#n-openread-lin µs], [#n-openread-pre µs], [#n-openread-post µs], [10.8×]),
      ([8 MiB 顺序写 + `fsync`], [#n-fsync-lin ms], [#n-fsync-pre ms], [#n-fsync-post ms], [1.18×]),
      ([8 MiB 页缓存顺序写], [#n-seqwrite-lin MiB/s], [#n-seqwrite-pre MiB/s], [#n-seqwrite-post MiB/s], [我方更快]),
      ([缓存命中读（warm）], [#n-read-warm-lin MB/s], [#n-read-warm-pre MB/s], [#n-read-warm-post MB/s], [1.42×]),
      ([缓存命中读（fresh）], [#n-read-fresh-lin MB/s], [#n-read-fresh-pre MB/s], [#n-read-fresh-post MB/s], [4.32×]),
      ([单次大读 803 KB], [#n-read-big-lin MB/s], [#n-read-big-pre MB/s], [#n-read-big-post MB/s], [3.64×]),
      ([冷启动到可交互 shell], [#n-boot-total-lin s †], [#n-boot-shell-pre s], [#n-boot-shell-post s], [我方更快]),
    ),
  ),
  caption: [优化前后总表。Linux 列为同板实测；"优化后/Linux"小于 1 表示我方更快。上下文切换与管道往返本轮只做了归因、未改行为，故仍落后一个数量级（第 3 章）；末行两侧的启动锚点不同（见第 7 章的说明），此处只作量级参考],
)

== 结论

把这张总表读完，可以得到四条结论：

+ *“每次调用都要付”的固定成本已经系统性下降，但没有到齐。* 空系统调用从
  25.0 倍收到 #n-getpid-ratio 倍，4 KiB 管道往返从 10.4 倍收到 #n-pipe-ratio 倍，
  exec 从 18.1 倍收到 #n-forkexec-ratio 倍，ext4 `open`+`read`+`close` 从 246 倍
  收到 10.8 倍。
+ *缺页这条最深的坑基本填平。* 64 MiB 默认路径从 #n-fault-pre-64 ns/页 降到
  #n-fault-a3d-64 ns/页（*29.5×*），与 Linux 的差距从 165 倍收到 5.6 倍，并且
  成本已经*不再随区域大小增长*。四条改动之间彼此独立，任何一条都可以单独回退。
+ *带宽型指标本来就领先或持平，优化后仍然领先。* 页缓存顺序写从
  #n-seqwrite-pre MiB/s 提到 #n-seqwrite-post MiB/s（Linux #n-seqwrite-lin MiB/s），
  冷启动 #n-boot-shell-post s 对 Linux #n-boot-total-lin s。
+ *剩下的差距集中在两处，且都已被精确定位但没有动。* 一是上下文切换（#n-ctx-post µs
  对 #n-ctx-lin µs），根因是 EEVDF 调度器热路径上十几处 1–15 µs 的固定开销叠加
  （第 3 章）；二是文件读的每页固定成本（fresh 仍差 #n-read-fresh-post 对
  #n-read-fresh-lin MB/s），根因是每页的 `MappingSlot`/rmap 发布与 `PageObject`
  堆分配（第 5 章）。两者都需要改动核心不变式，本轮只做了归因、没有改行为，
  详见第 8 章。
