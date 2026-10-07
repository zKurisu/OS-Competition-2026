#import "_prelude.typ": *

= 文件读路径

读路径是所有上层负载的共同底座：`exec` 要读可执行文件、模型加载要读几 MB 的
权重、`scp` 要读整个文件、视觉链路要读摄像头配置与模型。优化之前，缓存命中的
大读只有 #n-read-warm-pre MB/s（Linux #n-read-warm-lin MB/s），每轮换一块新缓冲的
读只有 #n-read-fresh-pre MB/s（Linux #n-read-fresh-lin MB/s），单次 803 KB 大读
#n-read-big-pre MB/s（Linux #n-read-big-lin MB/s）。

这一章的推进过程比结论更有价值：前两条线索各自只带来 10% 左右的收益，真正把
指标拉起来的是第三条——一个与"读"看上去无关的元数据行为。这也说明为什么这一阶段
坚持"先归因、再改动"：如果只看"读慢"，很容易一直在拷贝路径上打磨。

== 第一条线索：省掉一次拷贝

缓存命中时，原实现每 4 KiB 页要付三笔：取页（映射布局锁 + 页缓存锁 + LRU）、
把页内容拷进一个临时*暂存页*、出了锁再从暂存页拷到用户缓冲。中间那次拷贝的
唯一理由是"必须在拷给用户之前把页缓存索引锁放掉"。

而页缓存本来就有钉子机制：`CachedPagePin` 把引用计数加一，回收、缩容、截断
三条路径都会跳过"有钉子"的页。于是改成：*pin 住这一页 → 出锁 → 用该帧的
内核直接映射把内容直接拷给调用方 → 放下钉子*。为此给文件页提供者加了一个
"物理地址转内核虚拟地址"的接口。

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([缓存命中大读（缓冲已触碰）], [#n-read-warm-lin MB/s], [#n-read-warm-pre MB/s], [#n-read-warm-mid MB/s]),
      ([单次大读 803 KB], [#n-read-big-lin MB/s], [#n-read-big-pre MB/s], [*#n-read-big-post MB/s*]),
      ([缓存命中大读（每轮新缓冲）], [#n-read-fresh-lin MB/s], [#n-read-fresh-pre MB/s], [#n-read-fresh-post2 MB/s（不变）]),
    ),
  ),
  caption: [第一刀：去掉暂存页中转。收益 +17%，但每轮新缓冲的那一列*完全不动*——那 82 µs/页 根本不是拷贝成本],
)

fresh 一列不动，本身就是重要信息：它的成本主要落在"数据要写进用户缓冲、
而那一页还没有映射"的缺页路径上（关掉顺序预取会涨到 179.7 µs/页），与拷贝无关。
要动它得让用户内存准备的慢路径用上与硬件缺页同一条整段物化原语。

== 第二条线索：用户内存准备整段化

riscv64 上没有可用的硬件"用户访问探测"指令，所以内核此前*每次*用户访问都要
取地址空间锁并逐页跑一遍完整的缺页事务。改成"整段已映射"的快路径，再进一步把
用户内存准备从"逐页缺页事务"改成"整段物化一次"（内部按 VMA 分段，并把整段收进
一次变更事务；任何一步不成立就回退到原来的逐页循环）。

#tablefigure(
  booktable(
    (40%, 20%, 20%, 20%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([单次大读 803 KB], [#n-read-big-lin MB/s], [#n-read-big-pre MB/s], [*76.2 MB/s*]),
      ([缓存命中大读（缓冲已触碰）], [#n-read-warm-lin MB/s], [#n-read-warm-mid MB/s], [*#n-read-warm-mid2 MB/s*]),
      ([缓存命中大读（每轮新缓冲）], [#n-read-fresh-lin MB/s], [#n-read-fresh-pre MB/s], [#n-read-fresh-mid MB/s]),
    ),
  ),
  caption: [第二刀：整段物化。整段路径确实生效（分段计数确认），但 fresh 只从 50.2 走到 51.5——缺页事务的"外壳"也不是主要瓶颈],
)

两条线索合计只把 fresh 从 #n-read-fresh-pre 推到 51.5 MB/s。到这里必须换思路：
既然数据路径与事务外壳都不是瓶颈，那就该问"这些时间到底花在哪个*操作*上"。

== 第三条线索：瓶颈在 `close`，不在读

决定性对照来自同一个探针（`open` + `read` + `close`）换不同文件：

#tablefigure(
  booktable(
    (36%, 32%, 32%),
    ([探针], [中位耗时], [说明]),
    (
      ([`read_syscall /proc/uptime 1 KB`], [#n-readsys-proc µs], [procfs，纯内存]),
      ([`read_syscall /etc/profile 1 KB`], [#n-readsys-etc µs], [ext4，连跑两遍都是 7.7–7.8 ms]),
      ([`read_syscall /bin/busybox 1 KB`], [#n-readsys-busybox µs], [ext4，连跑三遍都是 10.10–10.16 ms]),
      ([`read_syscall /bin/busybox 0 KB`], [#n-readsys-busybox0 µs], [*读 0 字节也一样慢*]),
    ),
  ),
  caption: [决定性对照。耗时与"读多少字节"无关，与"在哪个文件系统"强相关（差 20 倍），且每次重复都一样（不是冷启动开销）],
)

三条推论把范围收得很窄：与读的数据量无关；ext4 比 procfs 慢 20 倍；不是一次性
开销。于是转向"`open`+`read`+`close` 里哪一段固定地做了 I/O"。

=== 定位链：从 `close` 一直到 `atime`

分段计时把 10 ms 钉在*文件对象析构*上；随后四轮探针逐一排除：VFS 节点驱逐
（共享缓存对象从未析构，"跨 open 保留"的设计是生效的）、目录项与文件节点析构、
ext4 inode 析构。最后用三个"零代码"实验直接指认根因：

#tablefigure(
  booktable(
    (46%, 20%, 34%),
    ([实验], [结果], [说明]),
    (
      ([40 次 shell `exec 3</bin/busybox` 后立即关闭（*不读*）], [#n-close-noread-ms ms/次], [只 open+close 不慢]),
      ([`read_syscall /bin/busybox 0 40`（读 0 字节）], [10.0 ms/次], [触发条件是"`read` 被调用过"]),
      ([40 轮前后 `/proc/diskstats`], [writes *+136*、sectors +1088], [≈1 个 inode 块 + 一次日志提交；tmpfs 上增量为 0]),
    ),
  ),
  caption: [三条零代码实验。答案是：`Drop for File` 只要句柄"被读过"（0 字节 `read` 也算）就在 close 时同步更新访问时间],
)

根因是：`Drop for File` 检测到句柄被读过，就调用一次"更新元数据（访问时间）"，
而 ext4 的元数据更新末尾直接做一次*同步日志提交*——在这块 SD 卡上约 10 ms。
tmpfs 与 procfs 的同一操作是纯内存的，所以同一个探针在它们上面只要 0.4 ms，
20 倍差距由此而来。

=== 改法：按 Linux 的 `relatime` 语义处理访问时间

改动很小：挂载选项 `noatime` 时不写、`strictatime` 时照旧每次写，其余按默认的
`relatime`（每个文件每 24 小时至多写一次）。

这里有一个与本板硬件相关的坑必须记录：*不能拿墙上时钟判断"是否超过 24 小时"*。
板上没有 RTC、也没有 NTP，`date` 显示 1970 年，比镜像里文件的 2025/2026 年时间戳
还小，用它套 `relatime` 判据会永远判成"已过期"，退化成每次都写。最终改用
*单调时钟*，并把"上次持久化时间"记在本来就跨 `open` 存活的页缓存身份里
（免锁、免分配）。

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标（中位）], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([ext4 `open`+`read`(1 KiB)+`close`], [#n-openread-lin µs], [#n-openread-pre µs], [*#n-openread-post µs*（22×）]),
      ([同一份文件在 tmpfs 上（对照）], [#abl[未测]], [#n-openread-tmpfs-pre µs], [#n-openread-tmpfs-post µs（不变）]),
      ([100 轮循环总墙钟], [#abl[未测]], [#n-openread-loop-pre s], [*#n-openread-loop-post s*]),
      ([40 轮循环的块写次数], [#abl[未测]], [*+#n-blockwrite-pre*], [+#n-blockwrite-post（= 后台底噪）]),
    ),
  ),
  caption: [`relatime` 的效果。相对 Linux 的差距从 246 倍收到 10.8 倍；块写退到后台底噪说明"close 里的同步提交"确实被消掉了],
)

#kfig("F30_ext4_close_atime_before_after", caption: [ext4 `open`+`read`+`close` 的中位耗时（对数轴）：优化前 10 320 µs、优化后 454 µs、同板 Linux 42 µs], width: 76%)

=== 边界：这一刀不改善"读"本身

必须说清楚，否则会把两个不同的指标混在一起：`read_bench` 的计时*不含 close*，
因此它在这一刀前后几乎不变（#n-read-big-pre2 → #n-read-big-post2 MB/s）；`exec` 也完全没变（它的成本在
ELF 映射与缺页）。扫描类负载（每个文件只读一次）只改善 4%，因为在 `relatime`
下"每个文件的第一次读"本来就要写一次访问时间——要再往前走，得把这次写回
*延后或批量*（Linux 是交给回写线程的，这里是在析构里同步提交）。

这条也与第 6 章同源：*文件对象的析构路径不应该做同步 I/O。*

== 回到读路径：fresh 缓冲的三段拆解

搞清 `close` 之后，再回到"每轮换一块新缓冲"的那条路。新探针把整轮拆成三段：

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([每轮 803 KB，µs/页], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([`mmap` 建映射], [#abl[未测]], [#n-rp2-mmap], [1.81]),
      ([读：首触 + 拷贝], [#abl[未测]], [#n-rp2-read-pre], [*#n-rp2-read-post*（−22%）]),
      ([`munmap` 拆除], [#abl[未测]], [#n-rp2-munmap-pre], [#n-rp2-munmap-post]),
      ([整轮合计], [#abl[未测]], [#n-rp2-total-pre], [*#n-rp2-total-post*（−14%）]),
    ),
  ),
  caption: [fresh 缓冲的三段拆解。`mmap` 只要 1.5 µs/页（不算问题），另外两段才是大头],
)

其中 `munmap` 一段又被拆到六段：清页表 10.5 µs/页、捕获前像 3.6、摘除映射槽 3.3、
退休所有者 0.9、摘要 0.4、提交 0.3，其余约 5 µs 是系统调用入口与 VMA 树操作。

据此做了两刀，都属于"取消重复工作"：

- *延迟失效路径不再逐页刷 TLB。* 四个后端的 `unmap_range` 都调"逐页摘除"，
  而它内部会*每一页*做一次本地 TLB 失效；但调用方已经进入了延迟失效守卫，
  并对*整段*登记过一次失效、提交时统一发布。逐页那次是纯冗余（与第 2 章那次
  "每次返回都刷指令缓存"是同一类问题）。去掉之后 `munmap` 从 29.4 降到
  #n-rp2-munmap-pre µs/页（−24%）。这条动 TLB 语义，专门写了新探针自检——
  固定地址反复"映射 → 填图案 → 拆除 → 同址再映射 → 检查是否读到零页"，
  200 轮 × 64 页，不匹配页数为 0。
- *整块填充不再重复走查已判定未映射的第一页。* 顺序预取的窗口在判定连续性时
  已经查过一次该页，随后又查了一遍。

在这两刀之上，第 4 章的"页索引按 run 批量登记"继续把 fresh 推到
#n-read-fresh-post MB/s。

== 实测与边界

#tablefigure(
  booktable(
    (34%, 22%, 22%, 22%),
    ([指标], [Linux 5.10.4], [优化前], [优化后]),
    (
      ([缓存命中读（warm）], [#n-read-warm-lin MB/s], [#n-read-warm-pre MB/s], [#n-read-warm-post MB/s]),
      ([缓存命中读（fresh）], [#n-read-fresh-lin MB/s], [#n-read-fresh-pre MB/s], [*#n-read-fresh-post MB/s*]),
      ([单次大读 803 KB], [#n-read-big-lin MB/s], [#n-read-big-pre MB/s], [#n-read-big-post MB/s]),
      ([ext4 `open`+`read`(1 KiB)+`close`], [#n-openread-lin µs], [#n-openread-pre µs], [#n-openread-post µs]),
    ),
  ),
  caption: [读路径的最终位置。`open`+`read`+`close` 改善 22 倍，读吞吐改善约 1.25 倍；fresh 一列仍差 4.3 倍，差距在每页固定开销上],
)

正确性上，读路径这一串改动都用同一套口径校验：同一文件三种分块方式（4 KiB、
64 KiB、`md5sum` 默认）读出的校验和完全一致，且与*在主机侧从板子 rootfs 直接
导出的同一文件逐字节相同*。用户内存整段化之后专门复测了带宽与进程创建指标，
没有观测到变化。

还有一条语义边界需要写明：直接拷贝期间不再持有页缓存索引锁，因此与"并发写同一
文件"重叠时可能出现撕裂读。这与 Linux 的 `copy_page_to_iter` 行为一致（靠引用
计数与页锁保证写入顺序，而不是在拷贝期间持索引锁），同一进程内"写完再读"不受影响。

== 剩余空间

fresh 一列剩下的 4.3 倍差距，与第 4 章结尾列的是同一批东西：每页一次的页对象
建立（7.3 µs）、装页表（3.8 µs）、以及*尚未精确归因的约 19 µs/页*（嫌疑是
每页一次的映射槽与反向映射发布）。`munmap` 一侧剩下最大的一块是清页表
（10.5 µs/页，仍在逐页走查两次），但它必须与"空叶子表回收"一起设计，理由见
第 4 章结尾。
