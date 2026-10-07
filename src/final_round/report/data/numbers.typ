// ============================================================
//  SG2002 评测报告的 **唯一权威数字表**
//
//  约定（照参考报告 `docs/final-round/data/numbers.tex` 的做法）：
//    * 正文只引用宏名，不写字面数字；
//    * 每个数字后面用注释给出原始文件（相对 ../sg2002-eval/）；
//    * 方向：除显式标注"越低越好"的时延外，都是越高越好；
//    * 未测/待补的数字不要写进来，正文用 `#abl[...]` 标出。
//
//  平台代号：ours=本分支 / ref=报告团队集成分支 / main,dev=上游 / lin=厂商 Linux 5.10.4
// ============================================================

// ------------------------------------------------------------
// 0. 板子与镜像
// ------------------------------------------------------------
#let board-name = "AKA-00-SG2002（LicheeRV Nano 血统）"
#let board-cpu = "C906（riscv64，单应用核）"
#let board-mem-mb = 236
#let image-final = "starry-final.sd"

// ------------------------------------------------------------
// 1. 系统调用入口与 IPC（ns；results/2026-10-04-*.out、2026-10-05-*-suite.out）
// ------------------------------------------------------------
#let n-getpid-lin = 422.5
#let n-getpid-ours = 11268.5
#let n-getpid-ref = 14912.3
#let n-getpid-main = 12885.1
#let n-getpid-dev = 9904.0
#let n-getpid-ratio = 26.7          // ours / lin

#let n-pipe-wr-lin = 4489.2
#let n-pipe-wr-ours = 46188.3
#let n-pipe-wr-ref = 92410.7
#let n-pipe-wr-main = 45850.7
#let n-pipe-wr-dev = 44431.2

#let n-ppong-lin = 26.0            // µs/msg
#let n-ppong-ours = 444.2
#let n-ppong-ref = 261.4

// syscost2：逐项 ns/call（results/2026-10-04-syscost2-sg2002.txt 等）
#let n-sc-getpid-lin = 428.1
#let n-sc-getpid-ours = 9499.3
#let n-sc-getppid-lin = 444.4
#let n-sc-getppid-ours = 15299.0
#let n-sc-getrusage-lin = 3059.5
#let n-sc-getrusage-ours = 66931.7
#let n-sc-write-null-lin = 781.2
#let n-sc-write-null-ours = 65241.2
#let n-sc-mmap-munmap-lin = 7109.8
#let n-sc-mmap-munmap-ours = 375273.4
#let n-sc-invalid-before = 256855.4   // 一条 warn! 日志的代价
#let n-sc-invalid-after = 8541.4

// 入口"地板"：8.5 µs 里与具体 syscall 无关的比例（测量文档 §19）
#let n-syscall-floor-us = 8.5
#let n-syscall-floor-fixed-pct = 90

// ------------------------------------------------------------
// 2. 调度与睡眠（µs；results/2026-10-05-selfdesigned-probes.txt、ref-branch-probes.txt）
// ------------------------------------------------------------
#let n-fork-exit-ours = 7475.1
#let n-fork-exit-ref = 6053.6
#let n-fork-exit-lin = 338.1
#let n-fork-exec-ours = 46897.2
#let n-fork-exec-ref = 47306.5
#let n-fork-exec-lin = 2407.0
#let n-ctx-ours = 223.3
#let n-ctx-ref = 133.2
#let n-ctx-lin = 11.0
#let n-yield-ours = 156.7
#let n-yield-ref = 46.4
#let n-yield-lin = 6.9
#let n-sleep5-p50-ours = 5268
#let n-sleep5-p99-ours = 7693
#let n-sleep5-max-ours = 12064
#let n-sleep5-p99-ref = 5158
#let n-sleep5-max-ref = 5159
#let n-sleep5-max-lin = 5089
#let n-drift-ours = 338            // 200×1 ms 累积漂移
#let n-drift-ref = 42
#let n-drift-lin = 69

// ------------------------------------------------------------
// 3. 内存：缺页、首触、带宽（results/2026-10-05-*.txt）
// ------------------------------------------------------------
#let n-firsttouch32-ours = 11.130  // s
#let n-firsttouch32-ref = 1.096
#let n-firsttouch32-main = 16.219
#let n-firsttouch32-dev = 2.579
#let n-firsttouch32-lin = 0.189

#let n-fault-1m-ours = 154179     // ns/page
#let n-fault-1m-ref = 233148
#let n-fault-1m-lin = 6377
#let n-fault-4m-ours = 307024
#let n-fault-4m-ref = 63006
#let n-fault-4m-lin = 5714
#let n-fault-16m-ours = 587627
#let n-fault-16m-ref = 63165
#let n-fault-16m-lin = 5759
#let n-fault-64m-ours = 1302123
#let n-fault-64m-ref = 64427
#let n-fault-64m-lin = 7899
#let n-fault-64m-huge-ours = 22216    // MADV_HUGEPAGE
#let n-fault-64m-huge-ref = 64164
#let n-fault-64m-huge-lin = 5683
#let n-fault-64m-populate-ref = 25165 // MADV_POPULATE_WRITE（ours 不支持）
#let n-fault-64m-huge-gap = 58.6      // ours 默认 / ours 大页

#let n-bw-memcpy-ours = 0.972     // GB/s
#let n-bw-read-ours = 1.411
#let n-bw-memcpy-ref = 1.030
#let n-bw-read-ref = 1.489
#let n-bw-memcpy-lin = 1.024
#let n-bw-read-lin = 1.488

// ------------------------------------------------------------
// 4. 存储（MiB/s、ms；results/2026-10-06-blockrw-*-final.txt、2026-10-05-*）
// ------------------------------------------------------------
// 2 MiB 档（最终镜像）四档 io_size：512 B / 4 KiB / 1 MiB-16 / 1 MiB
#let n-br2-write-ours = (3.00, 14.93, 18.90, 18.82)
#let n-br2-read-ours = (32.27, 29.37, 14.07, 13.77)
#let n-br2-fsync-ours = (2079, 2012, 1652, 1683)
#let n-br2-write-lin = (10.76, 31.67, 35.29, 35.41)
#let n-br2-enable = "512 B / 4 KiB / 1 MiB-16 / 1 MiB"

// 8 MiB 档（最终镜像；修复前该档直接 EBUSY）
#let n-br8-write-ours = (1.20, 2.09, 2.41, 2.33)
#let n-br8-read-ours = (4.15, 4.14, 3.92, 4.06)
#let n-br8-fsync-ours = (3812, 5058, 5025, 4957)
#let n-br8-write-lin = (10.98, 32.20, 36.31, 36.27)
#let n-br8-multitask-ms-ours = 28751   // 8 workers × 2 MiB

#let n-fsprobe-8m-bytes = 8388608
#let n-fsprobe-8m-fsync-s = 4.998
#let n-fsprobe-2m-boundary-pass = 2097152    // 修复前：刚好能写完
#let n-fsprobe-2m-boundary-fail = 2097664    // 修复前：下一个 512 B 块 EBUSY

// ------------------------------------------------------------
// 5. 启动 TTFI（s；results/2026-10-05-boot-timing.log、linux-ttfi.txt、ref-boot-timing.log）
// ------------------------------------------------------------
#let n-ttfi-fatload-ours = 1.45
#let n-ttfi-kernel-ours = 9.01
#let n-ttfi-user-ours = 4.20
#let n-ttfi-total-ours = 14.66
#let n-ttfi-fatload-lin = 1.04
#let n-ttfi-kernel-lin = 1.20
#let n-ttfi-user-lin = 31.99
#let n-ttfi-total-lin = 34.23
#let n-ttfi-fatload-ref = 1.20
#let n-ttfi-kernel-ref = 6.01
#let n-ttfi-user-ref = 88.80
#let n-ttfi-total-ref = 96.01

// ------------------------------------------------------------
// 6. 网络（MiB；results/2026-10-06-*、2026-10-05-wifi-stress*.log）
// ------------------------------------------------------------
#let n-wifi-before-first = 9          // 首次记录：第 10 轮 SSH 失效
#let n-wifi-before-repro = 4          // 后续复现区间 3–6 MiB 的下沿
#let n-wifi-before-repro-hi = 6
#let n-wifi-after = 60                // 修复后 60 轮全过
#let n-wifi-lin = 60
#let n-wifi-http-single = 120         // 单连接 HTTP 大流量（零丢包）
#let n-wifi-assoc-s = 16.5            // bootm → association complete
#let n-wifi-dhcp-s = 23.1             // bootm → DHCP 拿到地址

// ------------------------------------------------------------
// 7. 视觉/推理流水线（ms，p50；results/2026-10-05-akars-*.log）
// ------------------------------------------------------------
#let n-ak-decode-sw = 404.8
#let n-ak-resize-sw = 74.9
#let n-ak-pre-sw = 479.6
#let n-ak-fwd-sw = 41.1
#let n-ak-post-sw = 16.2
#let n-ak-total-sw = 537.2
#let n-ak-decode-jpu = 18.8
#let n-ak-resize-jpu = 359.5
#let n-ak-total-jpu = 437.0
#let n-ak-pre-lin = 425.0
#let n-ak-fwd-lin = 39.5
#let n-ak-post-lin = 1.0
#let n-ak-total-lin = 465.5
#let n-ak-total-ci = 466.7

// ------------------------------------------------------------
// 8. 资源（results/2026-10-05-*；文档 §23.5）
// ------------------------------------------------------------
#let n-mem-total-ours = 236296      // kB
#let n-mem-total-lin = 130960
#let n-mem-peak-ours = 19316        // kB（39 张图）
#let n-mem-peak-lin = 7604
#let n-model-load-ours = 2.99       // s
#let n-model-load-lin = 0.07
#let n-pass-wall-ours = 1.54        // s（3 张图）
#let n-pass-wall-lin = 1.37

// ------------------------------------------------------------
// 9. 修复项（before → after；results/2026-10-06-fixes-before-after.txt）
// ------------------------------------------------------------
#let n-writelimit-before = 2.0      // MiB
#let n-writelimit-after = 8.0
#let n-writelimit-ref = 8.0
#let n-writelimit-lin = 8.0
#let n-boot-ssh-before = 120.0      // s（90 s 闸门 + 未修内核）
#let n-boot-ssh-after = 47.0        // s（20 s 闸门 + 已修内核）

// ------------------------------------------------------------
// 10. 独立优化目标（当前进度见 workspace/SG2002_OPTIMIZATION_PLAN.md）
//     目标值只写"目标"，实测值补测后填进对应条目；未补测保持 #abl[...]。
// ------------------------------------------------------------
#let n-goal-syscall-floor-us = 2.0
#let n-goal-getpid-us = 4.0
#let n-goal-fault64-ours = 30000    // ns/page，目标 40× 改善
#let n-goal-fork-exit-us = 3000
#let n-goal-ctx-us = 50
#let n-goal-sleep5-max-us = 5500
#let n-goal-fsync-2m-s = 0.5
#let n-goal-boot-user-s = 4.0
#let n-goal-model-load-s = 1.0

// ------------------------------------------------------------
// 11. 芯片 / 板卡 / 上游工程的静态规格
//     不是本项目的测量值，是引用别人的事实；正文同样只写宏名。
// ------------------------------------------------------------
// 出处：sophgo-doc SG200X TRM《系统概述 · 特性介绍》（index 中 only:: sg2002 选取的本篇）
//   主处理器 RISCV C906 @1.0GHz（或 ARM Cortex-A53 @1.0GHz，由管脚 GPIO_RTX 二选一）
//   协处理器 RISCV C906 @700MHz；内建 TPU，算力 ~1.0TOPS INT8
#let soc-bigcore-ghz = 1.0
#let soc-smallcore-mhz = 700
#let soc-tpu-tops-int8 = 1.0
// 出处：duo-buildroot-sdk-v2 内存布局；末 2 MiB 划给小核固件（见 sg2002-c906l/docs/01）
#let soc-ddr-mib = 256

// 出处：tgoskits docs/docs/introduction/overview.md §2.2（workspace 版本 0.5.12）
#let upstream-workspace-members = 184
#let upstream-archs = 4

// ------------------------------------------------------------
// 12. 视觉闭环端到端（成功帧的单帧视觉总时延均值）
//     出处：jqj《第二部分》§7.1 测试结果概述的汇总表，原始日志见 sg2002-eval/results/
// ------------------------------------------------------------
#let n-vision-ete-ours = 53.024    // ms
#let n-vision-ete-lin = 54.230     // ms
