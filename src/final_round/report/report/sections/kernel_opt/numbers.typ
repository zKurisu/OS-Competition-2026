// ============================================================
//  内核优化分册 · 唯一权威数字表
//
//  口径（三种数据，正文只引用宏名，不写字面数字）：
//    * `lin`  = 厂商 Linux 5.10.4（同板、同一份静态 riscv64 ELF、同一批探针）
//    * `pre`  = 我们优化之前（2026-10-04 的基线镜像 ours / 2026-10-06 的 A 系列起点）
//    * `post` = 我们优化之后（2026-10-07 收尾镜像）
//
//  每个数字后面用注释给出原始文件（相对 final_round/workspace/sg2002-eval/results/）。
//  未测的不要写进来，正文用 `#abl[...]` 标出。
// ============================================================

// ------------------------------------------------------------
// 0. 平台
// ------------------------------------------------------------
#let k-board = "AKA-00-SG2002（LicheeRV Nano 血统）"
#let k-cpu = "C906（riscv64，单应用核）"
#let k-linux = "厂商 Linux 5.10.4"

// ------------------------------------------------------------
// 1. 系统调用与 IPC
//    results/2026-10-07-h2-pin-direct-copy.txt [4]（撤掉热路径探针后的干净口径）
//    results/2026-10-07-linux-comparison-filled.txt [2]
// ------------------------------------------------------------
// 空系统调用：优化前 10 560 ns → 优化后 1 631 ns（复测 1 233–1 631），Linux 422.5 ns
#let k-getpid-lin = 422.5
#let k-getpid-pre = 10560
#let k-getpid-post = 1631
#let k-getpid-best = 1233
#let k-getpid-ratio = 3.9

// 管道 4 KiB 往返（ppong 的批处理摊薄口径）
#let k-pipe-lin = 4489.2
#let k-pipe-pre = 46819
#let k-pipe-post = 12576
#let k-pipe-ratio = 2.8

// 管道 ping-pong：一次往返含一次阻塞、一次唤醒、一次上下文切换
#let k-ppong-lin = 26.0
#let k-ppong-pre = 445.7
#let k-ppong-post = 421.1
#let k-ppong-ratio = 16.2

// 双线程 sched_yield 交接
#let k-yield-lin = 6.90
#let k-yield-pre = 171.0
#let k-yield-post = 112.5
#let k-yield-ratio = 16.3

// ------------------------------------------------------------
// 2. 进程创建、exec 与上下文切换
//    results/2026-10-07-c1-fork-attribution.txt / -c1b-retire-teardown.txt /
//    -h1-d1-exec-fsync.txt / -c2-ctx-switch.txt
// ------------------------------------------------------------
// fork + _exit + waitpid
#let k-forkexit-lin = 338.1
#let k-forkexit-pre = 7497
#let k-forkexit-post = 6461
#let k-forkexit-ratio = 19.1

// fork + execve(/bin/true) + waitpid（static-PIE busybox 口径）
#let k-forkexec-lin = 2407
#let k-forkexec-pre = 43537
#let k-forkexec-post = 22359
#let k-forkexec-ratio = 9.3

// exec 的内核侧成本（execve 进入内核到返回用户态，探针口径）
#let k-exec-pre = 32.3       // ms/次
#let k-exec-post = 4.5

// 上下文切换（一次 switch 的墙钟，含阻塞与唤醒整包）
#let k-ctx-lin = 10.97
#let k-ctx-pre = 226.8
#let k-ctx-post = 220.4
#let k-ctx-ratio = 20.1

// fork 内部：一次 fork() 系统调用的分段（µs）
#let k-fork-syscall-pre = 4739
#let k-fork-syscall-post = 4418
#let k-fork-tryclone-pre = 1747
#let k-fork-tryclone-post = 1528
#let k-fork-activate = 1724       // 首次入队立即触发的重调度（wall）——未动
#let k-fork-clone-leaf-pre = 99
#let k-fork-clone-leaf-post = 82
#let k-fork-pub-prep-pre = 120
#let k-fork-pub-prep-post = 99

// 子地址空间退休（不在 fork_exit 关键路径上，但占子进程析构的 CPU）
#let k-exit-clear-pre = 3570      // µs
#let k-exit-clear-post = 410

// ------------------------------------------------------------
// 3. 缺页与地址空间
//    results/2026-10-06-fixes-before-after.txt / -2026-10-06-opt5-regression.txt /
//    2026-10-07-h2-fresh-breakdown.txt
// ------------------------------------------------------------
// 私有匿名首触，默认 4 KiB 路径，ns/4 KiB 页
#let k-fault-lin-64 = 7899
#let k-fault-pre-1 = 154179
#let k-fault-pre-4 = 307024
#let k-fault-pre-16 = 587627
#let k-fault-pre-64 = 1302123
#let k-fault-cow-1 = 168918
#let k-fault-cow-4 = 151250
#let k-fault-cow-16 = 153875
#let k-fault-cow-64 = 162213
#let k-fault-mem-64 = 170558
#let k-fault-around-1 = 134962
#let k-fault-around-4 = 63939
#let k-fault-around-16 = 57658
#let k-fault-around-64 = 70856
#let k-fault-a3d-64 = 44120
#let k-fault-a3d-64-best = 41717
// 显式 MADV_HUGEPAGE 路径
#let k-fault-huge-pre = 22216
#let k-fault-huge-post = 8014
#let k-fault-huge-lin = 5683
// 分段（优化后，占位判断用）
#let k-fa-pending-insert-pre = 719039
#let k-fa-pending-insert-post = 18461
#let k-frame-zero-pre = 30854
#let k-frame-zero-post = 4507
#let k-frame-alloc-pre = 18303
#let k-frame-alloc-post = 3671
#let k-page-object-pre = 30171
#let k-page-object-post = 8467
// 标准 harness 32 MiB 首触（墙钟）
#let k-membw-first-pre = 10.54      // s
#let k-membw-first-post = 1.1651

// ------------------------------------------------------------
// 4. 文件读路径 / 解析（MB/s）
//    results/2026-10-07-h2-pin-direct-copy.txt / -h2-h3-h4-readpath.txt /
//    -h2-fresh-breakdown.txt / -h2-cow-run-batch.txt / -linux-comparison-filled.txt
// ------------------------------------------------------------
#let k-read-warm-lin = 671.6
#let k-read-warm-pre = 374
#let k-read-warm-post = 474
#let k-read-warm-post2 = 437      // pin 直拷那一刀的单点
#let k-read-fresh-lin = 271.1
#let k-read-fresh-pre = 50.2
#let k-read-fresh-post = 62.8
#let k-read-big-lin = 277.2
#let k-read-big-pre = 60.9
#let k-read-big-post = 76.2
// H2 两条线索的中间值（MB/s）
#let k-read-warm-mid = 437          // pin 直拷之后
#let k-read-warm-mid2 = 474         // 整段物化之后
#let k-read-fresh-mid = 51.5        // 整段物化之后（fresh 几乎不动）
#let k-read-fresh-post2 = 50        // pin 直拷之后 fresh 不变
// read_bench 单次大读：H5 之后（它的计时不含 close，所以几乎不动）
#let k-read-big-pre2 = 60.7
#let k-read-big-post2 = 64.5
// ext4 open+read+close 的分文件对照（µs，中位）
#let k-readsys-proc = 404
#let k-readsys-etc = 7777
#let k-readsys-busybox = 10115
#let k-readsys-busybox0 = 10038
#let k-close-noread-ms = 0.9        // 只 open+close（不读）的每次耗时
#let k-openread-tmpfs-pre = 499     // 同一份文件在 tmpfs 上的对照
#let k-openread-tmpfs-post = 384
#let k-openread-loop-pre = 0.99     // 100 轮循环总墙钟（s）
#let k-openread-loop-post = 0.117
// rp2：fresh 缓冲三段拆解（µs/页）
#let k-rp2-mmap = 1.51
#let k-rp2-read-pre = 49.68       // 首触 + 拷贝
#let k-rp2-read-post = 44.55
#let k-rp2-munmap-pre = 29.51
#let k-rp2-munmap-post = 23.39
#let k-rp2-total-pre = 80.70
#let k-rp2-total-post = 69.75
// munmap 内部（µs/页，f3624e32c 的六段归因）
#let k-munmap-apply = 10.50
#let k-munmap-preimage = 3.61
#let k-munmap-detach = 3.28
#let k-munmap-other = 4.9
// 匿名首触的每页常量（µs/页）
#let k-anon-pageobject = 7.3
#let k-anon-index-pre = 4.9
#let k-anon-index-post = 1.0
#let k-anon-pte = 3.8
#let k-anon-materialize = 0.4
#let k-anon-frame = 3.9

// ------------------------------------------------------------
// 5. 存储写回与元数据
//    results/2026-10-07-h1-d1-exec-fsync.txt / 2026-10-06-fixes-before-after.txt /
//    -h5f-atime-policy.txt
// ------------------------------------------------------------
// 8 MiB 写 + fsync
#let k-fsync-lin = 790        // ms（page 档）
#let k-fsync-pre = 7961
#let k-fsync-post = 931
// ext4 8 MiB 顺序写吞吐（只落页缓存）
#let k-seqwrite-lin = 34      // MiB/s（32–36）
#let k-seqwrite-pre = 2.41
#let k-seqwrite-post = 42.43
// ext4 open + read(1 KiB) + close（中位）
#let k-openread-lin = 42      // µs
#let k-openread-pre = 10320
#let k-openread-post = 454
// 40 轮 open+read+close 期间的块写次数
#let k-blockwrite-pre = 136
#let k-blockwrite-post = 12
// 2 MiB fsync
#let k-fsync2m-lin = 790
#let k-fsync2m-post = 2000

// ------------------------------------------------------------
// 6. 启动
//    results/2026-10-05-linux-ttfi.txt / 2026-10-05-boot-timing.log
// ------------------------------------------------------------
#let k-boot-fatload-lin = 1.04      // s
#let k-boot-fatload-pre = 1.45
#let k-boot-kernel-lin = 1.20       // bootm → 首个用户态输出
#let k-boot-kernel-pre = 9.01
#let k-boot-user-to-shell-pre = 4.20
#let k-boot-total-pre = 13.21       // bootm → 提示符
#let k-boot-total-lin = 33.2        // bootm → getty login:（Linux 的 init 脚本很重）
#let k-boot-gate-pre = 10.81        // 上电 → 用户态标记
#let k-boot-gate-post = 9.61
#let k-boot-shell-pre = 12.3        // 上电 → shell 可交互
#let k-boot-shell-post = 10.8
// bootm→SSH 可用（含 90 s 闸门的旧口径）
#let k-boot-ssh-pre = 120
#let k-boot-ssh-post = 47

// ------------------------------------------------------------
// 7. 未优化项（对照用；这些指标本轮没有改动）
// ------------------------------------------------------------
#let k-sleep1-lin = 1071      // µs, p50
#let k-sleep1-post = 1268
#let k-sleep1-tail-post = 5576 // 5 ms 档 p99
#let k-memcpy-lin = 1.024     // GB/s
#let k-memcpy-post = 0.981
#let k-seqread-lin = 1.488
#let k-seqread-post = 1.428
