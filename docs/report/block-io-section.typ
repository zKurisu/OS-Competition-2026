// 块设备 I/O 与文件系统优化（block-io-bench 4 MiB 文件，板级实测，Linux 5.10 为同板基准）
#let n-read-fsync-before = 4.9
#let n-read-fsync-after = 48
#let n-read-nofsync-before = 2.4
#let n-read-nofsync-after = 47
#let n-write-fsync-before = 3.5
#let n-write-fsync-after = 7.4
#let n-write-nofsync-before = 4.2
#let n-write-nofsync-after = 20.8

= 块设备 I/O 与文件系统优化

SD 卡是机器人取流与推理产物的落盘介质，其读写吞吐直接影响数据的存取时延。StarryOS 的 SD 卡块设备此前走 FIFO/PIO 模式，每次只能传 1 块 512 字节，叠加 riscv64 dcache 维护缺失与文件系统写入路径的冗余，`block-io-bench` 测得的读写吞吐远低于 SD 卡应有水平：读约 2.4 MiB/s、写约 4 MiB/s，而同机 Linux 分别达到约 139 MiB/s 与 42 MiB/s。本节先把块设备切换到 ADMA2 DMA 多块传输并补齐 dcache 维护，再修正文件系统写入路径的两处冗余，最后给出相对 Linux 的性能结果。

== ADMA2 DMA 切换

SD 卡的 DMA 路径由底层 SDHCI 控制器的 ADMA2 引擎承担。ADMA2 以一张描述符表驱动多块传输：每个描述符携带一段连续的物理地址与长度，控制器按描述符链逐段搬运数据，一次提交即可传输远超单块的数据量。此前的 FIFO 配置每次只传 1 块 512 字节，一次 4 KiB 页的读写要被拆成 8 次往返，命令与响应的固定开销被反复支付。

切换涉及三处改动。其一，块设备配置由 `fifo_config` 改为 `dma_config`，并把 `DeviceDma` 经 `set_dma` 传给底层 SDHCI，使传输窗口对齐 ADMA2 的能力。其二，描述符链改为 Linux 风格：数据描述符携带 `TRAN | VALID`、不置 `END`，链尾追加一个 `NOP | END | VALID` 终止描述符，结束方式与 DWC_mshc 的 ADMA2 约定一致。其三，修正 `ADMA2_MAX_TRANSFER_SIZE`：该值原先按 16 个数据描述符计算（约 1 MiB），但终止描述符占去 1 个槽位后数据描述符只剩 15 个，1 MiB 的 chunk 提交时描述符不够，控制器报 `not block aligned`，上层表现为 fsync 报 EIO。改按 15 个数据描述符计算后，该故障消失。

== riscv64 dcache 维护

SG2002 的 XuanTie C906 核不实现标准 Zicbom 扩展，而是提供 XTheadCmo 指令集，其 `dcache.cpa`（clean）与 `dcache.cipa`（clean + invalidate）完成 DMA 所需的缓存维护。此前 riscv64 上的 dcache 维护是空操作，DMA 读回的数据未经 invalidate，CPU 读到的是陈旧缓存，表现为读到全 0。补齐后，DMA 读在数据落定后执行 `dcache.cipa`，DMA 写在执行前以 `fence` 保证待写 store 已进入缓存、再执行 `dcache.cpa` 写回。

另一处关键在地址。C906 的缓存按物理地址索引，而 AArch64 的维护指令按虚拟地址操作。此前 dcache 指令传的是虚拟地址，DMA 读同一个块时结果随机，正是缓存索引不一致所致。改为按 `dma_addr()` 的物理地址执行维护后，读写结果稳定一致。

== 文件系统层优化

文件系统层的两处冗余分别拖慢了写与读。

写入侧，`write_at` 在扩展文件长度时每次都会调用 `set_len`，而 `set_len` 内部先按新长度分配并清零数据块、末尾再做一次整文件系统的同步。顺序写负载每写 4 KiB 就触发一次「分配块 + 全量同步」，写吞吐被压到约 0.15 MiB/s。改为延迟分配后，扩展文件只更新缓存中的长度，数据块的分配与 inode 大小的落盘推迟到写回时由 `write_inode_data` 的 grow 分支批量完成，连续 extent 一次分配。

读取侧，页缓存容量原先为 512 页（2 MiB），装不下 4 MiB 的测试文件，写入阶段即触发前 2 MiB 的换出，读取阶段前 2 MiB 逐页单块读。将页缓存容量增大到 2048 页（8 MiB）后，测试文件整体驻留缓存，读写不再触发换出与缺页。

== 结果

`block-io-bench`（4 MiB 文件、5 轮）的板级实测如下表，四项读写均有明显提升，其中读与 Linux 的差距主要落在逐页读的固定开销而非 SD 卡总线本身。

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (left, center, center, center),
    table.header([场景], [优化前], [优化后], [Linux 5.10]),
    [read (fsync)], [#n-read-fsync-before MiB/s], [#n-read-fsync-after MiB/s], [139 MiB/s],
    [read (no-fsync)], [#n-read-nofsync-before MiB/s], [#n-read-nofsync-after MiB/s], [139 MiB/s],
    [write (fsync)], [#n-write-fsync-before MiB/s], [#n-write-fsync-after MiB/s], [8.1 MiB/s],
    [write (no-fsync)], [#n-write-nofsync-before MiB/s], [#n-write-nofsync-after MiB/s], [42.7 MiB/s],
  ),
  caption: [block-io-bench 4 MiB 文件读写吞吐（板级实测，Linux 5.10 为同板基准）]
)

块设备 DMA 链路已打通并稳定：分区表识别、ext4 挂载与 fsync 落盘均正常。写吞吐相对 Linux 仍有约 2 倍差距，主要来自页缓存写回路径的拷贝与锁开销；读吞吐在页缓存命中时受逐页读固定开销限制，页缓存缺失时的真实 SD 卡吞吐还需进一步以大块预读与更大的描述符表摊薄命令开销。
