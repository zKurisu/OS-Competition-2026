# 宿主机工作流

这一层是"怎么和板子打交道"的工具箱：串口、文件传输、引导与烧写、日志采集。
所有脚本都遵循同一套约定，互相之间可以直接拼装。

## 约定

| 项 | 约定 |
|---|---|
| 串口设备 | `--dev` 参数 > `SG2002_PORT` 环境变量 > `/dev/ttyUSB0`。多板并存时务必显式指定 |
| 波特率 | 115200 8N1 |
| StarryOS 提示符 | `root@starry:/root #` |
| U-Boot 提示符 | `soph#` |
| 厂商 Linux | getty 的 `login:`；登录姿势是连敲两次 `root` 再输口令 `root` |
| 引导地址 | `fatload mmc 0 0x81800000 <fit>` → `bootm 0x81800000#config-sg2002_licheervnano_sd` |

## 脚本

| 脚本 | 作用 |
|---|---|
| `sg2002_serial.py` | 公共库：端口解析、提示符/哨兵判定、ANSI 与内核日志过滤 |
| `sg2002_cmd.py` | 跑一条板端命令；`--prompt shell\|uboot\|linux`、`--raw`、`--break`、`--list` |
| `sg2002_upload.py` | base64 分块经串口上传文件，可选执行与首尾 md5 核对 |
| `capture_serial.py` | 抓完整串口日志（含 FSBL/U-Boot），容忍拔插、可逐行打主机时间戳 |
| `serial_sentinel.py` | 哨兵式执行：固件不打印提示符时也能判定命令结束 |
| `boot_probe.py` | U-Boot `fatload`+`bootm` 并整段打时间戳；`--linux` 切基线口径；`--reset-from-starry` 支持软复位整段计时 |
| `boot_parts.py` | 把板内分片按序 `fatload` 成连续内存再 `bootm`（绕开单文件写上限） |
| `boot_timing.py` | 从 `boot_probe.py` 的日志算 上电→U-Boot→内核→shell 分段耗时（TTFI） |
| `boot_ssh_timing.py` | 量 `bootm` → SSH 可用的总时间（含 init/连网/DHCP/sshd） |
| `linux_cmd.py` | 在已登录的厂商 Linux shell 上跑命令（`echo __DONE__` 收尾） |
| `linux_boot_run.py` | 单进程完成「引导 Linux → 抢窗口登录 → 跑命令」 |
| `pack_fit.sh` | 把 `starryos.bin` 打包成 FIT（`starry-<name>.sd`） |
| `ums_device.sh` | UMS 块设备探测（按 UMS 型号唯一匹配，或按卡内 marker 匹配） |
| `deploy_via_ums.sh` | 板子在 UMS 时写 FAT（FIT）与 ext4（探针，debugfs 直写） |
| `flash_ums.sh` | 一键「复位→UMS→写卡→退出 UMS→引导」全流程 |

## 典型流程

**刷一版新内核并引导**

```bash
export SG2002_PORT=/dev/ttyUSB0
./pack_fit.sh opt78 --root ~/Do/.../opensource/tgoskits
./flash_ums.sh opt78 120
```

**没有 UMS 时的文件传输**（例如摄像头占着 USB）

```bash
./sg2002_upload.py ./build/probes/syscost2 /root/probes/syscost2 --exec-bit
./sg2002_cmd.py 'sh /root/probes/starry-harness-sg2002.sh' --timeout 1200
```

**冷启动抓证据**

```bash
./capture_serial.py --seconds 300 --log /tmp/cold.log --stamp-lines
grep -a -e C2S -e C2E -e RSC -e blcp_2nd_cksum /tmp/cold.log
./boot_timing.py /tmp/cold.log
```

## 工程上必须记住的坑

1. **串口不可并发**。两个进程同时开同一条链路，会出现 "device disconnected or
   multiple access" 并丢字节。跑实验前先确认没有残留的采集脚本。
2. **提示符会被当前目录改变**。板上 `cd` 过后提示符变成 `root@starry:/root/xxx #`，
   按固定串匹配会一直等到超时。`sg2002_serial.BoardLink` 每次跑命令前先 `cd /root`。
3. **U-Boot 会回显命令本身**，"缓冲区里出现过 `soph#`"不能作为结束判据，
   必须要求提示符出现在缓冲区末尾。
4. **`/boot` 是 FAT 且 noexec**。二进制/脚本必须放 ext4（如 `/root`）。
5. **板内写完要 `sync`**。不 sync 直接复位，掉数据是常态。
6. **大文件与 FAT**：FAT 只有 256 MB，传镜像前先删旧的 `starry-*.sd`；
   一次性大拷贝可能把板子拖死，分文件（每次 ≲ 3.6 MB）+ `sync` 更稳。
7. **`/tmp` 有配额**。`mkimage` 曾因 "Disk quota exceeded" 失败，
   自建临时目录（`/tmp/pack_*`）用完要清。
8. **多板并存**。本机曾同时挂两块 SG2002（`/dev/ttyUSB0` 与 `/dev/ttyUSB1`），
   用 `--list`、`SG2002_PORT` 和 `ums_device.sh` 把链路/磁盘钉死，绝不默认 `/dev/sda`。
