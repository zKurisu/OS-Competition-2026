# tests —— SG2002 / StarryOS 测试与打点资产

这个目录把项目开发过程中用到的**测试脚本、打点探针和宿主机工作流**集中管理，
目标是让任何一个人拿到板子后能复现"改内核 → 上板 → 出数字"的完整闭环。

目录分层：

| 目录 | 内容 | 是否需要板子 |
|---|---|---|
| [`workflow/`](workflow/) | 串口、文件上传、命令执行、引导与烧写、日志采集 | 需要（宿主机侧执行） |
| [`probes/`](probes/) | 按子系统分类的打点探针（用户态 `.c` + 设备 `.py`） | 需要（板端执行） |
| [`board/`](board/) | 上游 tgoskits 板级回归用例说明 + 本项目一键性能套件 + 板端自检脚本（`board/selftest/`） | 需要 |
| [`scripts/`](scripts/) | 一键入口：编译、跑套件、探针对照表 | 部分 |
| [`results/`](results/) | 运行结果归档（原始日志被 gitignore） | — |

## 1. 板子与端口约定

开发期间宿主机同时挂过两块 SG2002，链路必须显式区分：

| 用途 | 串口 | 说明 |
|---|---|---|
| 默认 / 比赛用板 | `/dev/ttyUSB0` | 所有脚本的默认值，可用 `--dev` 或 `SG2002_PORT` 覆盖 |
| 第二块板 | `/dev/ttyUSB1` | 移植验证侧用过；`/dev/serial/by-path/...-0:3:...` 是拔插不变的别名 |

```bash
export SG2002_PORT=/dev/ttyUSB0     # 全局指定
workflow/sg2002_cmd.py --list       # 列出候选串口
```

板子的 UMS 模式（`ums 0 mmc 0`）会把 SD 卡当 U 盘挂到宿主机。多块卡同时在位时，
`workflow/ums_device.sh` 按"卡里有没有我们的 marker"或"UMS 型号是否唯一"来认盘，
**脚本不会默认写 `/dev/sda`**。

## 2. 依赖

```bash
# 串口
python3 -m pip install pyserial          # 或 apt install python3-serial

# 交叉编译：默认用 LicheeRV-Nano-Build 自带的 Xuantie musl 工具链
#   <repo>/../opensource/LicheeRV-Nano-Build/host-tools/gcc/
#       riscv64-linux-musl-x86_64/bin/riscv64-unknown-linux-musl-gcc
# 也可以用 xPack 的 riscv64-unknown-linux-musl-gcc，或 export CC=...

# 烧写/镜像工具
sudo apt install mtools dosfstools e2fsprogs u-boot-tools   # mcopy/mdir/mdel、debugfs、mkimage
```

串口权限：重插后 udev 常把设备复位成 `root:uucp 660`，把当前用户加进 `uucp` 组，
或临时 `sudo chmod 666 /dev/ttyUSB0`。

## 3. 快速上手

```bash
# ① 编译全部探针（riscv64 静态二进制）
scripts/build_probes.sh

# ② 和板子说一句话
workflow/sg2002_cmd.py 'uname -a; cat /proc/uptime'

# ③ 打包 + 一键烧写引导（板子停在 U-Boot，或能从 StarryOS 软复位）
workflow/pack_fit.sh opt78 --root <tgoskits>
workflow/flash_ums.sh opt78 120

# ④ 没有 UMS 时用串口传文件
workflow/sg2002_upload.py build/probes/syscost2 /root/probes/syscost2 --exec-bit

# ⑤ 一键跑板级套件并收结果
scripts/run_suite.sh --side starry
scripts/run_suite.sh --side linux
```

## 4. 测试分层

**回归门禁**（上游 tgoskits，`cargo xtask starry test` 驱动）：`boot`、
`cmdqu-ipc`、`cmdqu-selftest`、`tennis-yolo`、`usb2-lsusb`、`wifi-iperf-smoke` 等。
详见 [`board/README.md`](board/README.md)。

**性能标尺**（本项目 harness + 探针）：同一批 riscv64 静态二进制在厂商 Linux 与
StarryOS 两侧各跑一遍，输出 `HL_*`/`HS_*` 行并可自动对齐比较。

报告里出现的关键指标与产生它们的探针：

| 报告指标 | 探针 / 脚本 |
|---|---|
| 空系统调用 `getpid` 10.6 µs → 1.6 µs | `probes/syscall/syslat.c`、`syscost2.c` |
| `fork+execve+waitpid` 43.5 → 22.4 ms | `probes/sched/forkcost.c`、harness |
| 64 MiB 首触 1302 µs → 44 µs / 页 | `probes/mm/faultcost.c`、`touch64.c`、`popcost.c` |
| 8 MiB 写+fsync 7.96 s → 0.93 s | `probes/fs/fsprobe.c`、`readprobe2.c` |
| 管道往返 46.8 µs → 12.6 µs | `probes/sched/schedprobe.c`、harness 的 `ppong` |
| 相机 / JPU / VPSS 链路 | `probes/dev/cam_*.py`、`s6_probe.py`、`vdec_poison.py` |
| WiFi 关联与吞吐 | `probes/net/early_wifi_probe.py`、`wifi_stress.sh` |
| 上电→shell / 上电→SSH | `workflow/boot_probe.py` + `boot_timing.py`、`boot_ssh_timing.py` |

## 5. 素材来源与 commit 对照

### tgoskits（诊断探针的出处）

内核侧的 `/proc/fault_attrib` 与各子系统 `diag` 计数，是下面这些提交留下的诊断面；
用户态探针正是配套的读数端：

| commit | 内容 | 对应探针 |
|---|---|---|
| `0a627ecb7` | 返回用户态不再每次刷 I-cache（10.6→3.0 µs） | `syslat.c` |
| `ce454eb52` | 系统调用循环开关、uaccess 每页三段、读路径每页三段 | `syscost2.c`、`sysattr.c`、`readprobe.c` |
| `1f70bafef` / `97ccc78a3` | populate 分段、apply 三段 | `faultattrib.c`、`popcost.c` |
| `f3624e32c` / `c16994af2` | munmap 六段归因、延迟失效不再逐页刷 TLB | `mmcoherence.c` |
| `82ddd33b5` / `a8b0dd9a8` | 调度决策八段、`ctx_switch` 全路径归因 | `schedprobe.c`、harness `ppong` |
| `10e67ae8d` / `f5d357d4a` | fork/exit/调度分段、exec 32→4.8 ms | `forkcost.c` |
| `371ffc0dd` / `130a98059` | 批量缺页整块分配、页索引插入 | `cowtest.c`、`insbench.c` |
| `29e264fd0` / `1db22090c` | 页缓存上限 512→4096 页、写回按连续页合并 | `fsprobe.c` |
| `5f1b870dd` / `584b07fa7` / `cc56cd47e` | 读路径页已缓存快路径、uaccess 整段快路径 | `readprobe.c`、`readprobe2.c` |
| `34bb1e025` / `f95192115` / `f80a4bb45` | H5 系列：把 ext4 `open+read+close` 的 10 ms 定位到 close 析构 | `fsprobe.c` |
| `a3cd50ece` | close 不再无条件同步写 atime | `fsprobe.c` |
| `18430ec6c` | OOM panic 的三处定位探针 | `leakchk.c` |
| `ce9b42a92` | 启动阶段等 DHCP 宽限期 2 s→300 ms | `early_wifi_probe.py` |

### LicheeRV-Nano-Build（板级固件与 U-Boot）

| commit | 内容 | 影响的工作流 |
|---|---|---|
| `dbb8a64be` | USB gadget RNDIS Ethernet + UMS、softfloat stubs | `ums_device.sh`、`deploy_via_ums.sh`、`flash_ums.sh` |
| `18b48849d` / `6c4b4408b` | 启用 UMS、`saveenv` 到 `mmc 0:1` | U-Boot 环境持久化 |
| `2c5f34757` | 用环境变量切换 USB eth 持久模式 | 网络工作流 |
| `f43fad3de` | 构建启用 FreeRTOS 小核固件 | `cmdqu-*` 用例、`/root/c906l_kick` |
| `f85904ca9` / `27d3983dd` | 小核状态上报、控制周期分布（kind=9） | `cmdqu-selftest` 第 ④ 步 |
| `859689d6d` / `2ae3b783e` | 小核接管 UART2 驱动舵机、先开时钟门控 | 机械臂链路 |

更完整的移植与验收记录见
`final_round/side_workspace/HANDOFF_TPU_VPSS.md` 与 `PORTING_LOG.md`。

## 6. 必须记住的坑

1. 串口**不可并发**——两个进程同时开同一条链路会丢字节并报
   "device disconnected or multiple access"。
2. StarryOS 提示符会带当前目录；跑命令前先 `cd /root`（`sg2002_serial` 已内置）。
3. U-Boot 会回显命令本身，判"命令结束"必须看**缓冲区末尾**的提示符，不能只搜子串。
4. `/boot` 是 FAT 且 `noexec`：二进制必须放 ext4。
5. 板内写完文件要 `sync`；FAT 只有 256 MB，传镜像前先删旧的 `starry-*.sd`。
6. 大文件一次性拷贝可能把板子拖死，分文件（每次 ≲ 3.6 MB）+ `sync` 更稳。
7. `/tmp` 有配额，`mkimage` 可能因 "Disk quota exceeded" 失败，临时目录用完要清。
8. 摄像头与 UMS 互斥：插着摄像头时不能走 UMS 传文件，需要 WiFi 或先拔摄像头。
