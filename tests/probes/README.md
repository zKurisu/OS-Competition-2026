# 打点探针

探针分两类：

* **用户态测量探针**（`.c`）——交叉编译成 riscv64 静态 musl 二进制，同一份二进制
  在厂商 Linux 与 StarryOS 上各跑一次，输出可直接对比的 `KEY value` 行。
  编译入口：`tests/scripts/build_probes.sh`（工具链默认取 LicheeRV-Nano-Build
  自带的 Xuantie musl gcc）。
* **设备/驱动探针**（`.py`、`.sh`）——跑在板子内部，直接对 `/dev/*` 做 ioctl、
  取流、故障注入，用来验证相机/JPU/VPSS 等驱动链路。

完整的"探针 → 测什么 → 关联 commit"对照在 [`../scripts/probe_matrix.tsv`](../scripts/probe_matrix.tsv)。

## 编译

```bash
tests/scripts/build_probes.sh                 # 产物到 tests/build/probes/
OUT=/tmp/probes ./build_probes.sh             # 指定产物目录
CC=<riscv64-unknown-linux-musl-gcc> ./build_probes.sh
```

编译参数统一为 `-O2 -static -pthread -march=rv64gc -mabi=lp64d`：
静态是为了绕开板上动态链接器/libc 版本的差异，`-pthread` 给调度类探针用。

## 目录

### `syscall/` —— 系统调用入口路径

| 探针 | 测什么 |
|---|---|
| `syslat.c` | 空系统调用（`getpid`）往返耗时，用于 `/proc/icache_flush` 的 A/B |
| `syscost2.c` | 照报告 §05 的"二分 handler 体量"方法拆入口成本 |
| `sysattr.c` | 只跑一种调用，读 `/proc/fault_attrib` 前后差值得到干净分解（阻塞调用样本由内核侧 100 µs 上限丢弃） |

### `mm/` —— 缺页、地址空间与一致性

| 探针 | 测什么 |
|---|---|
| `faultcost.c` | 首触成本 vs 区域大小 + `madvise` A/B；报告里的 `thp_*` 在 SG2002 上不可用（`thp_protnone` 要 2 GiB churn），这是有界替代 |
| `faultattrib.c` | 配合内核 `/proc/fault_attrib`，逐阶段读累计计数 |
| `fa_min.c` | 最小检查：`/proc/fault_attrib` 是否可读 |
| `popcost.c` | `MAP_POPULATE` 批量 populate 与逐页触碰的每页成本对比 |
| `bloat.c` | 顺序预取是否对跨步/随机访问超额预取（看 RSS） |
| `touch64.c` | 一次 64 MiB 私有匿名首触的冷态干净取样点 |
| `mmcoherence.c` | `munmap` 后同址重映射是否还能读到旧物理页（TLB 残留，非零即失败） |
| `memops_wordwise.c` | 字长循环 `mem*` 实现与 libc 的随机对齐/重叠对拍（宿主自检） |

### `sched/` —— 调度与 IPC

| 探针 | 测什么 |
|---|---|
| `schedprobe.c` | 单核上真正有意义的量：单次操作成本与 sleep 唤醒质量（hackbench/schbench 在 riscv64 单核无意义） |
| `forkcost.c` | 把 `fork` 拆成"父侧返回"与"等子退出"，判定 `activate` 是否同步切换 |
| `insbench.c` | 512 KiB 分散插入搬移的应然速度，用于判定内核页索引实现是否合理 |

### `fs/` —— 文件系统读写路径

| 探针 | 测什么 |
|---|---|
| `readprobe.c` | 缓存命中大读：预映射缓冲 vs fresh 缓冲分开量（区分 prepare 成本与缺页成本） |
| `readprobe2.c` | 把 fresh 缓冲再拆成 `mmap`/`read`/`munmap` 三段 |
| `fsprobe.c` | 主机文件系统写路径边界与行为（写上限、`EBUSY` 边界） |
| `cowtest.c` | 批量缺页整块分配 + 子租约后，父子各写各的副本是否正确 |
| `leakchk.c` | `mmap`/touch/`munmap` 循环是否泄漏 `MemFree` |

### `dev/` —— 相机 / JPU

| 探针 | 测什么 |
|---|---|
| `s6_probe.py` | 板上精确记录 cmd4（JPU 解码）逐次成败序列，定位 JPU 卡死点 |
| `cam_async_probe.py` | `/dev/cvi-usb-camera0` 异步取流 ioctl 6..13 全覆盖 |
| `cam_ion_probe.py` | ioctl 13 `GET_LATEST_YUV_ION`：ION 分配 → INIT/START_ASYNC → 取 YUV 帧 |
| `vdec_poison.py` | 给 JPU 喂坏码流制造真实解码失败，验证同一 boot 内能否恢复 |

### `net/` —— WiFi

| 探针 | 测什么 |
|---|---|
| `early_wifi_probe.py` | 引导后 shell 一出现就立刻连 WiFi，验证 90 s 闸门是否已去掉 |
| `wifi_stress.sh` | 量化链路累计传输多少字节后静默失效 |

## 板端运行约定

1. 二进制放 ext4（`/root/probes`），不要放 `/boot`（FAT + noexec）。
2. 跑之前先 `cd /root`，否则 StarryOS 的提示符会带上路径，宿主机脚本匹配不到。
3. 一次性跑全套用 `board/harness/starry-harness-sg2002.sh`（StarryOS）或
   `linux-harness-sg2002.sh`（基线），输出 `HS_*`/`HL_*` 行。
4. 设备类探针会独占设备（相机/JPU），跑之前确认没有别的取流进程。
