// 本文件由内核优化分册（kernel_opt）拆分而来，承载实验测试章中的
// "内核优化的测试说明与测试结果"。
#import "../_prelude.typ": *
#import "_lib.typ": *
#import "numbers.typ": *

== 内核优化的测试说明 <sec:kernel-test>

=== 本线特有的测试口径

全篇统一的评测口径（同一块板、同一份符合 Linux ABI 的静态可执行文件、两侧各测一次、
未测项显式标注）已在"测试说明"中给出，本节不重复；内核这条线在此基础上另有三条
特有约定，因为它的对照组是"优化前/优化后"，而不同次上电之间的读数本身会漂移。

#tablefigure(
  booktable(
    (20%, 80%),
    ([项], [内容]),
    (
      ([板卡], [#k-board，CPU 为 #k-cpu，内存 236 MiB]),
      ([对照系统], [#k-linux，卡上 `linux.sd`，同板同卡同一次上电周期内交替启动]),
      ([用户态], [同一份静态链接 riscv64 ELF。所有探针都是自研 C 程序，两侧编译同一份源码]),
      ([计时], [板端 `rdtime`（时基 1 MHz）+ 主机侧串口逐行时间戳；微基准取 20–100 轮中位]),
      ([口径], [每个指标三列：Linux 实测／优化之前／优化之后]),
    ),
  ),
  caption: [内核优化的评测平台与对照口径],
)

三条特有约定如下：

#enum(
  [*冷启动受控 A/B。* 内核"优化前/后"的对比尽量在*同一次上电、同一份探针、交替顺序*
   下做（例如两两交替各测两遍取均值），以抵消"启动后第一次大分配明显更快"这类时间漂移。],
  [*探针本身有代价。* 热路径上的分段计时是每次系统调用多 12 次取时间戳，实测平白增加
   约 1.2 µs。凡是"优化前/后"的对照数字，探针都已撤掉；带探针的中间过程只在归因时出现，
   并注明口径。],
  [*分段计账取快照之差。* 内核侧的分段数字由 `/proc/fault_attrib` 的计数器给出，取
   "工作负载前后的快照之差"折算为每次调用的平均值；该口径只反映被测量路径自身，
   不含探针与被测负载之外的干扰。],
)

=== 探针与验收门

#tablefigure(
  booktable(
    (24%, 34%, 42%),
    ([探针], [测什么], [对应的优化族]),
    (
      ([`syscost2`], [九个系统调用的单次开销（含 `invalid_syscall` 对照）], [K1 系统调用返回路径]),
      ([`sa1`], [返回路径的开关分段（单步 / ptrace / seccomp / trace）], [K1]),
      ([`sp2`], [`fork`+`exit`+`waitpid` 与 `fork`+`execve`+`waitpid` 的墙钟], [K2、K3]),
      ([`fk1`/`fk2`], [`fork` 内部分段（页表复制 / 首次入队 / 建线程）], [K2]),
      ([`faultcost`], [匿名首触成本 vs 区域大小（1/4/16/64 MiB）], [K4、K5]),
      ([`faultattrib`], [缺页的 plan/prepare/apply/TLB 分段], [K4、K5]),
      ([`popcost`], [逐页缺页与整段物化的对照（动手前的上界实验）], [K5]),
      ([`touch64`], [冷启动 64 MiB 首触单点（受控 A/B 口径）], [K5]),
      ([`bloat`], [预取窗口的膨胀验证（短流 / 跨步 / 随机 / `MADV_DONTNEED`）], [K5]),
      ([`cowtest`], [`fork` 后逐页改写父子各自正确、`MAP_POPULATE` 写读校验], [K5]),
      ([`read_bench`], [不同缓冲大小下的读吞吐], [K6]),
      ([`read_syscall`], [`open`+`read`+`close` 的分档中位耗时], [K6、K7]),
      ([`rp1`/`rp2`], [warm/fresh 缓冲读，以及 `mmap`/读/`munmap` 三段拆解], [K5、K6]),
      ([`mmc`], [TLB 一致性自检（固定地址反复映射-填-拆除-再映射）], [K6]),
      ([`block-rw-bench`], [ext4 顺序写与 `fsync`（多档位）], [K7]),
      ([`/proc/fault_attrib`], [内核侧分段计数、索引插入位置、回收队列长度], [K2、K4、K5]),
    ),
  ),
  caption: [本项目的探针清单。`/proc/fault_attrib` 是内核侧计数出口，所有分段数字都由"工作负载前后快照之差"取得],
)

每一处改动上线前都过同一组门：

#tablefigure(
  booktable(
    (26%, 44%, 30%),
    ([层], [判据], [适用族]),
    (
      ([宿主单测], [文件系统与内存相关 crate 的宿主回归全绿（内核 crate 收尾时 261 项）], [全部]),
      ([板端功能], [标准 harness 全项 + 功能用例（`ls`/`head`/`grep`/`sh -c`/退出码）], [全部]),
      ([数据正确性], [同一文件多种分块读的校验和一致，且与主机侧直接导出的文件逐字节相同], [K3、K6]),
      ([内存不泄漏], [mmap/touch/munmap 反复折腾后可用内存稳定；预取窗口另有膨胀验证], [K5]),
      ([一致性], [TLB 一致性自检不匹配页数为 0（改 TLB 语义的改动必须跑）], [K6]),
      ([压力], [多二进制 `exec` 压力、`fork`/`exec` 风暴、泄漏检查与调度探针全过], [K1、K2]),
      ([可回退], [动语义的改动都留运行期回退开关（`/proc/icache_flush`、`/proc/fault_around`）], [K1、K5]),
    ),
  ),
  caption: [验收门。凡改动动到对外语义（指令缓存、TLB、访问时间、地址空间退休），都额外做了对应的专项自检],
)

板端跑一组微基准（两侧同一份命令）：

```text
# StarryOS 侧（登录后的 shell）
cd /root/probes
./syscost2                       # 系统调用入口
./sp2                            # 进程创建与 exec
./faultcost 64                   # 64 MiB 首触
./read_syscall /bin/busybox 1 100
./rp1 && ./rp2                   # warm/fresh 读与三段拆解
./mmc                            # TLB 一致性自检
cat /proc/fault_attrib           # 内核侧分段（读前读后各取一次，相减即"每次调用"）
```

== 内核优化的测试结果 <sec:kernel-result>

=== 总体对照

#tablefigure(
  booktable(
    (31%, 17%, 17%, 17%, 18%),
    ([指标], [Linux], [优化前], [优化后], [优化后/ Linux]),
    (
      ([`getpid`（空系统调用）], [#k-getpid-lin ns], [#k-getpid-pre ns], [#k-getpid-post ns], [#k-getpid-ratio×]),
      ([`pipe_wr`（4 KiB 往返）], [#k-pipe-lin ns], [#k-pipe-pre ns], [#k-pipe-post ns], [#k-pipe-ratio×]),
      ([管道 ping-pong], [#k-ppong-lin µs], [#k-ppong-pre µs], [#k-ppong-post µs], [#k-ppong-ratio×]),
      ([`fork`+`exit`+`waitpid`], [#k-forkexit-lin µs], [#k-forkexit-pre µs], [#k-forkexit-post µs], [#k-forkexit-ratio×]),
      ([`fork`+`execve`+`waitpid`], [#k-forkexec-lin µs], [#k-forkexec-pre µs], [#k-forkexec-post µs], [#k-forkexec-ratio×]),
      ([上下文切换], [#k-ctx-lin µs], [#k-ctx-pre µs], [#k-ctx-post µs], [#k-ctx-ratio×]),
      ([双线程 `sched_yield` 交接], [#k-yield-lin µs], [#k-yield-pre µs], [#k-yield-post µs], [#k-yield-ratio×]),
      ([64 MiB 匿名首触（默认 4 KiB）], [#k-fault-lin-64 ns/页], [#k-fault-pre-64 ns/页], [#k-fault-a3d-64 ns/页], [5.6×]),
      ([64 MiB 首触（显式大页）], [#k-fault-huge-lin ns/页], [#k-fault-huge-pre ns/页], [#k-fault-huge-post ns/页], [1.41×]),
      ([ext4 `open`+`read`(1 KiB)+`close`], [#k-openread-lin µs], [#k-openread-pre µs], [#k-openread-post µs], [10.8×]),
      ([8 MiB 顺序写 + `fsync`], [#k-fsync-lin ms], [#k-fsync-pre ms], [#k-fsync-post ms], [1.18×]),
      ([8 MiB 页缓存顺序写], [#k-seqwrite-lin MiB/s], [#k-seqwrite-pre MiB/s], [#k-seqwrite-post MiB/s], [我方更快]),
      ([缓存命中读（warm）], [#k-read-warm-lin MB/s], [#k-read-warm-pre MB/s], [#k-read-warm-post MB/s], [1.42×]),
      ([缓存命中读（fresh）], [#k-read-fresh-lin MB/s], [#k-read-fresh-pre MB/s], [#k-read-fresh-post MB/s], [4.32×]),
      ([单次大读 803 KB], [#k-read-big-lin MB/s], [#k-read-big-pre MB/s], [#k-read-big-post MB/s], [3.64×]),
      ([冷启动到可交互 shell], [#k-boot-total-lin s †], [#k-boot-shell-pre s], [#k-boot-shell-post s], [我方更快]),
    ),
  ),
  caption: [内核优化的总体结果。Linux 列为同板实测；"优化后/Linux"小于 1 表示本侧更快。上下文切换与管道往返本轮只做了归因、未改行为，故仍落后一个数量级（见 @sec:kernel-hard）；† 末行两侧的启动锚点不同，只作量级参考，口径见 @sec:kernel-boot],
)

=== 系统调用与进程间通信

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([`getpid`（空系统调用）], [#k-getpid-lin ns], [#k-getpid-pre ns], [#k-getpid-post ns]),
      ([`pipe_wr`（4 KiB 往返）], [#k-pipe-lin ns], [#k-pipe-pre ns], [#k-pipe-post ns]),
      ([双线程 `sched_yield` 交接], [#k-yield-lin µs], [#k-yield-pre µs], [#k-yield-post µs]),
      ([管道 ping-pong], [#k-ppong-lin µs], [#k-ppong-pre µs], [#k-ppong-post µs]),
      ([上下文切换], [#k-ctx-lin µs], [#k-ctx-pre µs], [#k-ctx-post µs]),
      ([`memcpy` / 顺序读带宽], [#k-memcpy-lin / #k-seqread-lin GB/s], [0.984 / 1.420 GB/s], [0.981 / 1.428 GB/s]),
    ),
  ),
  caption: [返回路径瘦身前后的对照。前三行是"调用体很轻"的指标，收益最直接；后三行主要由调度与内存主导，与归因一致],
)

`getpid` 从 25.0 倍收到 #k-getpid-ratio 倍、`pipe_wr` 从 10.4 倍收到 #k-pipe-ratio 倍，
`sched_yield` 交接下降约三分之一。有两个口径必须写明：其一，带探针时会低估收益——同一镜像
在带 5 个系统调用探针时 `getpid` 显示为 3 050 ns，而撤掉探针后是 #k-getpid-post ns，也就是
说真实收益是 6.5 倍；其二，`getpid` 的复测区间是 #k-getpid-best–#k-getpid-post ns，
上表取最差值，最好的 #k-getpid-best ns 对应 2.9 倍。剩下的固定成本构成与"为什么停手"
见 @sec:kernel-hard。

=== 进程创建与 exec

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([`fork` + `exit` + `waitpid`], [#k-forkexit-lin µs], [#k-forkexit-pre µs], [#k-forkexit-post µs]),
      ([`fork` + `execve` + `waitpid`], [#k-forkexec-lin µs], [#k-forkexec-pre µs], [#k-forkexec-post µs]),
      ([└ 其中 execve 内核侧], [#abl[未测]], [#k-exec-pre ms], [*#k-exec-post ms*]),
      ([上下文切换], [#k-ctx-lin µs], [#k-ctx-pre µs], [#k-ctx-post µs]),
      ([双线程 `sched_yield` 交接], [#k-yield-lin µs], [#k-yield-pre µs], [#k-yield-post µs]),
      ([子地址空间退休], [#abl[未测]], [#k-exit-clear-pre µs], [#k-exit-clear-post µs]),
    ),
  ),
  caption: [进程与 exec 面的实测。`fork_exec_exit` 收掉 49%，exec 内核侧收掉 86%；`fork_exit` 只降 14%，原因见 @sec:kernel-hard 的归因],
)

`fork_exit` 只降 14%，看起来与前面几处改动不成比例：其剩余时间主要落在"切到一个新任务
再切回来"的 11–14 次上下文切换与调度热路径的固定开销上，页表复制只占小头。因此 `fork`
的下一步与上下文切换是同一件事，两者必须一起做。

=== 缺页与地址空间

#tablefigure(
  booktable(
    (32%, 22%, 24%, 22%),
    ([64 MiB 匿名首触], [Linux], [优化前], [优化后]),
    (
      ([默认 4 KiB 路径，每页], [#k-fault-lin-64 ns/页], [#k-fault-pre-64 ns/页], [*#k-fault-a3d-64 ns/页*（29.5×）]),
      ([显式大页路径，每页], [#k-fault-huge-lin ns/页], [#k-fault-huge-pre ns/页], [#k-fault-huge-post ns/页]),
    ),
  ),
  caption: [缺页路径的最终位置。默认路径相对自身优化前是 29.5×，相对 Linux 从 165 倍收到 5.6 倍；显式大页路径只差 1.41 倍],
)

分档看"成本不再随区域膨胀"这件事最直观（ns/页）：

#tablefigure(
  booktable(
    (22%, 26%, 26%, 26%),
    ([区域], [优化前], [优化后（索引）], [优化后（窗口）]),
    (
      ([1 MiB], [#k-fault-pre-1], [#k-fault-cow-1], [#k-fault-around-1]),
      ([4 MiB], [#k-fault-pre-4], [#k-fault-cow-4], [#k-fault-around-4]),
      ([16 MiB], [#k-fault-pre-16], [#k-fault-cow-16], [#k-fault-around-16]),
      ([64 MiB], [#k-fault-pre-64], [#k-fault-cow-64], [*#k-fault-a3d-64*]),
    ),
  ),
  caption: [优化前每页成本随区域线性上升（154 µs → 1 302 µs）；修掉页索引后四条基本持平，窗口批量物化再整体下移一档],
)

#kfig("F26_faultcost_before_after", caption: [优化前/后的首触成本随区域大小的变化，以及与 Linux 的对照。优化前四条随区域线性上升，优化后四条变平（对数轴）], width: 92%)

#kfig("F27_fault_around_before_after", caption: [顺序缺页预取的同板冷启动受控 A/B（两遍均值）。四种区域大小一致下降约 2.0–2.4 倍，显式大页路径不变], width: 84%)

#kfig("F28_fault_firsttouch_journey", caption: [64 MiB 匿名首触的逐级优化历程，以及与 Linux 的对照。四个台阶分别是页索引、字长内存操作，以及窗口批量物化里的"窗口预取"与"帧整块 + 子租约"两步（对数轴，越低越好）], width: 92%)

=== 文件读路径

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([缓存命中读（warm）], [#k-read-warm-lin MB/s], [#k-read-warm-pre MB/s], [#k-read-warm-post MB/s]),
      ([缓存命中读（fresh）], [#k-read-fresh-lin MB/s], [#k-read-fresh-pre MB/s], [*#k-read-fresh-post MB/s*]),
      ([单次大读 803 KB], [#k-read-big-lin MB/s], [#k-read-big-pre MB/s], [#k-read-big-post MB/s]),
      ([ext4 `open`+`read`(1 KiB)+`close`], [#k-openread-lin µs], [#k-openread-pre µs], [#k-openread-post µs]),
    ),
  ),
  caption: [读路径的最终位置。`open`+`read`+`close` 改善 22 倍，读吞吐改善约 1.25 倍；fresh 一列仍差 4.3 倍，差距在每页固定开销上],
)

同一份文件三种分块方式（4 KiB、64 KiB、`md5sum` 默认）读出的校验和完全一致，且与在
主机侧从板子根分区直接导出的同一文件逐字节相同。每轮换一块新 mmap 缓冲时，整轮 803 KB
被拆成三段：`mmap` 1.5–1.8 µs/页、读（首触 + 拷贝）从 #k-rp2-read-pre µs/页降到
#k-rp2-read-post µs/页、`munmap` 从 #k-rp2-munmap-pre µs/页降到 #k-rp2-munmap-post µs/页，
整轮合计从 #k-rp2-total-pre µs/页降到 #k-rp2-total-post µs/页。

#kfig("F30_ext4_close_atime_before_after", caption: [ext4 `open`+`read`+`close` 的中位耗时（对数轴）：优化前 10 320 µs、优化后 454 µs、同板 Linux 42 µs], width: 76%)

=== 存储写回与元数据

#tablefigure(
  booktable(
    (30%, 24%, 24%, 22%),
    ([8 MiB 档，`fsync` 耗时], [Linux ms], [优化前 ms], [优化后 ms]),
    (
      ([扇区写（512 B）], [814], [7 961], [1 050]),
      ([页写（4 KiB）], [#k-fsync-lin], [#k-fsync-pre], [*#k-fsync-post*]),
      ([硬件最大块（1 MiB）], [857], [7 636], [926]),
      ([规划器切分（1 MiB）], [793], [7 754], [934]),
    ),
  ),
  caption: [写回批量化前后的 `fsync` 耗时。四个档位全部落到与 Linux 同一水平（±20%），不再有"档位越大越慢"的现象],
)

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([8 MiB 顺序写 + `fsync`], [#k-fsync-lin ms], [#k-fsync-pre ms], [*#k-fsync-post ms*]),
      ([8 MiB 页缓存顺序写], [#k-seqwrite-lin MiB/s], [#k-seqwrite-pre MiB/s], [*#k-seqwrite-post MiB/s*]),
      ([ext4 `open`+`read`(1 KiB)+`close`], [#k-openread-lin µs], [#k-openread-pre µs], [*#k-openread-post µs*]),
      ([`fsync`(2 MiB)], [#k-fsync2m-lin ms], [#abl[未测]], [#k-fsync2m-post ms]),
    ),
  ),
  caption: [存储面的最终位置。写 + `fsync` 差 1.18 倍、顺序写吞吐反超、`open`+`read`+`close` 差 10.8 倍；`fsync`(2 MiB) 仍差 2.5 倍，属未完成项],
)

吞吐提升有一条必须写清的边界：*页缓存容量把吞吐提了 17.6 倍，但"写完 + `fsync`"的端到端
时间几乎不变*。因为 8 MiB 现在一次性回写，而这块 SD 卡约 1 MiB/s 的顺序写速度才是真正的
底——上限调到 20 MiB 档实测反而只有 1.0–1.4 MiB/s。所以这一族解决的是"每次小批量回写带来
的额外事务与抖动"，不是"卡本身慢"。

#kfig("F29_blockrw_pagecache_cap", caption: [页缓存上限提升前后的 ext4 顺序写吞吐（8 MiB 档）。吞吐提高 17.6 倍，但"写完 + `fsync`"的端到端时间不变——底在这块 SD 卡本身], width: 80%)

=== 启动时间 <sec:kernel-boot>

启动时间必须分段报，否则会把结论说反。用同一个主机侧探针（同一条串口、同样的逐行时间戳）
把启动切成三段，两侧只在"就绪锚点"上不同——本侧取 shell 提示符，Linux 取 `getty` 的
`login:` 提示符：

#tablefigure(
  booktable(
    (30%, 21%, 21%, 28%),
    ([段], [Linux 5.10.4], [优化前], [归属]),
    (
      ([U-Boot `fatload`], [#k-boot-fatload-lin s], [#k-boot-fatload-pre s], [镜像大小差异：两侧都是约 10.7 MiB/s]),
      ([`bootm` → 首个用户态输出], [#k-boot-kernel-lin s], [*#k-boot-kernel-pre s*], [*这一段才是内核*：内核初始化 + 设备探测]),
      ([首个用户态 → 可交互提示符], [#abl[约 32 s]], [#k-boot-user-to-shell-pre s], [rootfs 与 init 脚本]),
      ([合计（`bootm` → 提示符）], [#k-boot-total-lin s], [#k-boot-total-pre s], [端到端我方更快 2.5×]),
    ),
  ),
  caption: [启动分段对照。能归给内核的是中间那一段：本侧 9.01 s 对 Linux 1.20 s，落后 7.5 倍；而端到端本侧更快，主要因为 Linux 的 init 脚本很重],
)

这张表给出两个不能混淆的结论：其一，*端到端我方更快*（#k-boot-total-pre s 对
#k-boot-total-lin s），但这主要来自 Linux 自己的脚本重，不能当成"内核更快"的证据；其二，
*内核段落后 7.5 倍*（#k-boot-kernel-pre s 对 #k-boot-kernel-lin s），这一段全是内核初始化
与设备探测。本轮只动了一处固定等待，上电到用户态标记从 #k-boot-gate-pre s 降到
#k-boot-gate-post s、到 shell 可交互从 #k-boot-shell-pre s 降到 #k-boot-shell-post s；
其余静默块与不动的理由见 @sec:kernel-hard。

#kfig("F25_boot_to_ssh_before_after", caption: [`bootm` → SSH 可用的时间。优化前绝大部分是"等无线设备启动窗口"的固定闸门（内核修复后闸门从 90 s 降到 20 s）], width: 74%)
