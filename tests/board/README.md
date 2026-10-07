# 板级用例

这一层放"需要真实 SG2002 板子参与"的测试：一类是上游 tgoskits 仓库自带的
板级用例（由 `cargo xtask starry test` 驱动），一类是我们在开发过程中搭起来的
一键套件 harness。两者互补——前者守内核回归，后者做性能打点。

## 1. 上游 tgoskits 板级用例（回归）

来源：`tgoskits/test-suit/starryos/`。用例以 `board-<board>.toml` 发现，
其中 `board-aka-00-sg2002` 与 `board-licheerv-nano-sg2002` 两个目录与本项目相关，
运行入口是：

```bash
cd <tgoskits>
cargo xtask starry test -c test-suit/starryos/board-aka-00-sg2002/<case>/board-aka-00-sg2002.toml
# 或批量：cargo xtask starry test -l 先列出可发现的 case
```

| case | 位置 | 守什么 |
|---|---|---|
| `boot` | `board-aka-00-sg2002/boot/`、`board-licheerv-nano-sg2002/boot/` | 上电到 shell 的最基本回归：内核能挂根、起来、给出提示符 |
| `cmdqu-selftest` | `board-aka-00-sg2002/cmdqu-selftest/` | 跨核命令队列协议级自检：共享区头部/CRC、小核 PC 非 0、上报环 CRC、控制周期分布、`dropped=0`、等待超时返回 `ETIMEDOUT(110)`。需要 `/root/cmdqu_test`（`1_genimage/install-to-sd.sh` 会预置） |
| `cmdqu-ipc` | `board-licheerv-nano-sg2002/cmdqu-ipc/` | 只证明驱动 probe 成功、`/dev/cvi-rtos-cmdqu` 是字符设备（10:58）；守设备树/iomap/中断注册类回归 |
| `tennis-yolo` | `board-aka-00-sg2002/tennis-yolo/` | 板端跑 `/akars_tennis`，出现 `STARRY_AKA00_TENNIS_DETECT_OK` 即通过；守 TPU 运行时与模型的整链可用性 |
| `usb2-lsusb` | `board-aka-00-sg2002/usb2-lsusb/` | USB2 主机栈枚举（`lsusb` 能看到设备） |
| `usb2-libuvc-init` | `board-aka-00-sg2002/usb2-libuvc-init/`（`.toml.disabled`） | libuvc 初始化/取流；摄像机相关，插上摄像头才能跑，故默认停用 |
| `wifi-iperf-smoke` | `board-aka-00-sg2002/wifi-iperf-smoke/` | WiFi 关联 + DHCP + 从会话文件下发 `iperf2.tar.gz` 后跑吞吐 |
| `iperf2` | `board-common/iperf2/` | 两侧共用的 iperf2 构建与冒烟，供上面的 wifi 用例引用 |

> 注：`usb2-libuvc-init` 与摄像头用例互斥于 UMS——插着摄像头时 SD 卡不能当 U 盘用，
> 传文件要走 WiFi 或先拔摄像头。

## 2. 本项目的一键套件（性能打点）

`board/harness/` 是从 RK3588 报告移植过来的 Sysbench 板级 harness，
**同一批 riscv64 静态二进制在厂商 Linux 与 StarryOS 两侧各跑一遍**，
输出 `HL_*` / `HS_*` 行，末尾以 `SYSBENCH_BOARD_DONE` 收尾，可直接对比。

| 文件 | 作用 |
|---|---|
| `harness/build-harness-sg2002.sh` | 用 Xuantie musl 工具链交叉编译 harness 全套探针（无需 Docker）；等价入口是 `tests/scripts/build_probes.sh` |
| `harness/deploy-harness.sh` | 把二进制与 harness 脚本部署到板卡 ext4 |
| `harness/starry-harness-sg2002.sh` | StarryOS 侧套件（POSIX sh / dash 兼容；注意 `"${@:2}"` 在 dash 上是字符串切片，脚本用 `shift` 规避） |
| `harness/linux-harness-sg2002.sh` | 厂商 Linux 基线侧套件（同一批二进制、同一口径） |
| `harness/sysbench-compare.sh`、`harness/decompose.py` | 把两份 `HL_*`/`HS_*` 输出对齐、算差值与分解 |
| `harness/HARNESS.md` | 上游 harness 的原始说明 |
| `harness/*.c` | harness 用到的探针源码（cpuprobe、membw、ppong、THP 系列等） |

宿主机侧的一键入口是 `tests/scripts/run_suite.sh`：

```bash
tests/scripts/run_suite.sh --side starry          # 编译 + 部署 + 跑 + 收日志
tests/scripts/run_suite.sh --side linux           # Linux 基线
tests/scripts/run_suite.sh --side starry --deploy serial --dev /dev/ttyUSB1
```

结果落在 `tests/results/`，文件名形如 `<时间戳>-harness-<side>.log`。

## 3. 板端自检脚本（`board/selftest/`）

这些是"在板子上按固定顺序把一类证据一次采全"的脚本，用串口传上去后
`sh /root/<name>.sh` 跑，整段日志可以直接贴进验收记录。它们不看通过/失败，
而是把测量前提（小核链路是否打开、JPU 是否已锁死、是否带载）都先摆正。

| 脚本 | 干什么 | 关键前提 |
|---|---|---|
| `bare_board_selftest.sh` | 裸板（不接底盘/舵机/摄像头）自检：按固定顺序采各类证据，打 `BEGIN/END` 标记 | 空载约 1–2 min；`--load` 多采一轮 CPU 满载对照；`--tick` 追加时基测量 |
| `cam_selftest.sh` | 摄像头一次采全：① 分辨率/格式/connected ② cmd3（原始 MJPEG）与 cmd4（内核 JPU 解码）耗时分布 ③ 连续采帧长稳（帧数/FPS/重复帧/出错）④ 存一帧 JPEG 与 YUV 人工看 | **顺序有讲究**：cmd4 走内核 JPU，解码超时一次就永久锁死（`is poisoned … reboot is required`），所以碰 cmd4 的项必须排在 cmd3 之前；cmd3 走 USB 等时通路，放最后当"JPU 挂了但采帧通路仍然好着"的对照 |
| `rpm_sweep.sh` | 扫一遍 PWM→RPM 曲线（带载用；空载那轮见 docs/11 §6.2） | 用 `cmdqu_test target <p> --secs N` 后台喂心跳（小核看门狗窗口 500 ms，心跳不能断），退出时补 `target 0` 清零 |
| `wifi_recover_probe.sh` | 模拟"开机时没有 IP"：断开 wlan0 后重跑 `boot_net_up.sh`，看能否自愈（`setsid` 脱机会话执行） | 这是模拟，不是真实重启；真实场景另做一次 reset 验证 |

## 4. 两套用例的关系

上游 `test-suit` 用例是"通过/不通过"的回归门禁，本项目 harness 是"数字对比"的
性能标尺。改动内核后建议的顺序是：先跑 `cmdqu-selftest` + `boot` 确认没砸基础功能，
再跑本 harness 看指标是否退化。
