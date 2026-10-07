# SG2002：StarryOS / Linux 同口径复现

# 0. 明确指定源码根目录

先进入本目录，将下列四个占位路径替换为自己机器上的真实**仓库根目录**：

```sh
./configure.sh \
  --starry-app /path/to/new_kernel/akars \
  --starry-kernel /path/to/new_kernel/tgoskits \
  --linux-app /path/to/linux_base/source/akars-linux \
  --linux-base /path/to/linux_base
```

配置保存到本目录的 `local-paths.conf`，不会提交到 Git。后续脚本统一读取它；未配置时直接报错。若要换一套源码，先自行备份或移走旧配置，再重新运行 `configure.sh`。也可设置 `REPRO_CONFIG` 指向另一份独立配置。脚本不切换 Git 分支，也不清理源码仓库中的本地改动。建议先记录各仓库的 `git rev-parse HEAD` 与 `git status --short`，使构建可追溯。

## 前提与测试契约

- 宿主机：Linux、Rust/Cargo、RISC-V Xuantie 交叉工具链、TPU SDK；StarryOS 内核还需要 `mkimage`/`dumpimage`。缺少应用依赖时，构建命令可加 `--setup`，这会联网初始化工具链和 SDK。Wi-Fi 使用 2.4 GHz 的 WPA2 热点/路由器。
- 同一块 SG2002、相同摄像头和机械结构；模型均为 `yolov8n_tennis_v2.cvimodel`，SHA-256：`60da9b28c5736624534cb625ee2b67bdb5081954e43e320e1d749421e5e4155b`，输入 `1×3×640×640`。默认阈值 `conf=0.5`、`iou=0.5`、`classes=1`、`tpu-debug=off`。
- 两套程序都通过各自的 `test-ball-count.sh N` 在成功放回第 `N` 个球后退出。脚本核对 `AKARS_MISSION_COMPLETE` 和 `AKARS_STAGE_AVERAGE report=final mode=tennis`，没有这些标记不能算测试通过。阶段均值只针对完成视觉链路的网球帧；平均置信度不等于 mAP。
- 模型源文件取自两个用户态仓库根目录中已跟踪的 `yolov8n_tennis_v2.cvimodel`；部署脚本在板端安装到各自目录的 `model/` 下，不依赖本地未跟踪的 `model/` 文件。
- 每轮摆球数量、位置、红色容器、照明和供电应尽量一致。真正的底盘、夹爪会动作，测试必须有人在旁值守。
- Linux 使用原厂基线内核镜像，**不编译或修改 Linux 内核**；Linux 适配改动在 `linux_base/source/akars-linux` 用户态。StarryOS 需要同时构建 `tgoskits` 内核和 `new_kernel/akars` 用户程序。

## 1. 构建

完成第 0 步配置后，在本目录执行：

```sh
./build.sh starry --check
./build.sh starry --setup  # 首次缺少交叉工具链/SDK时使用；已有依赖则去掉 --setup

./build.sh linux --check
./build.sh linux --setup
```

StarryOS 构建选择带 `ax-runtime/aic8800-wifi` 的板卡配置，生成 `artifacts/starry/boot.sd`，同时交叉编译 `artifacts/starry/wifi_switch`。`boot.sd` 是含 `kernel-1` 和 `fdt-1` 的 U-Boot FIT 文件，不是整盘镜像。Linux 用户态二进制位于所指定 Linux 用户态根目录的 `target/riscv64gc-unknown-linux-musl/release/akars`。两个用户态构建均由各自仓库的 `scripts/build.sh` 执行。

## 2. 上板：先准备 TF 卡

关机取卡，在宿主机确认设备名。以下 `/dev/sdX` 只是占位符，**必须替换为实际可移动整盘**；不要填分区 `/dev/sdX1`。

```sh
lsblk -o NAME,PATH,RM,TRAN,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
```

分别准备 StarryOS 卡和 Linux 卡，切勿在同一张卡上交替执行而不重新核对。先创建位于宿主机硬盘上的备份目录，并卸载目标卡的所有分区：

```sh
mkdir -p ./artifacts/backups/starry ./artifacts/backups/linux
sudo ./flash-card.sh starry /dev/sdX ./artifacts/backups/starry --confirm
sudo ./flash-card.sh linux  /dev/sdY ./artifacts/backups/linux  --confirm
```

StarryOS 路径只替换 FAT 启动分区中的 `/boot.sd`，先在宿主机备份原文件并校验；第二分区原有 StarryOS rootfs 保持不变。它拒绝看起来不是 StarryOS 的卡。Linux 路径先备份**整卡**，再调用 `linux_base/scripts/flash-linux-baseline.sh` 校验镜像、写盘并逐字节读回。备份会占用约一张 TF 卡的空间，备份目录不得位于这张卡。Linux 本地镜像可能含测试热点的私有 Wi-Fi 配置，公开分发前应重新制作不含凭据的镜像。上述写卡操作只在显式传入 `--confirm` 后执行；完成后 `sync`、安全弹出、插回机器人并上电。

### Wi-Fi 配置（写卡后、上电前）

上一步完成后，如果卡仍插在电脑上，重新确认设备名并卸载所有分区。下面的命令会在终端交互输入 SSID 和密码，**密码不会成为命令行参数，也不会写进 Git 文件**：

```sh
sudo ./wifi-card.sh starry /dev/sdX ./artifacts/backups/starry --confirm
sudo ./wifi-card.sh linux  /dev/sdY ./artifacts/backups/linux  --confirm
```

StarryOS 的 Wi-Fi 不只需要内核驱动。脚本还会把编译好的 `wifi_switch` 安装到 ext4 根分区，并设置 `/root/init.sh` 在启动时调用它切换 STA；原 `init.sh` 和网络配置会备份到指定目录。若原启动脚本存在，它会先执行原脚本，再切换到本次输入的网络。Linux 则在 FAT 启动分区写入 `wifi.sta`、`wifi.ssid`、`wifi.pass`，由原厂 `S30wifi` 在启动时完成关联与 DHCP。Linux 卡原有的 FAT Wi-Fi 文件也会先备份。备份目录包含旧凭据，应妥善保管；不要把 TF 镜像或备份上传到公开仓库。

配置完成后安全弹出并上电。笔记本连接同一个热点，从路由器/手机已连接设备列表或串口上的 `ip -4 addr` 获取机器人地址；IP 由 DHCP 分配，不固定为某个尾号。若 StarryOS 只显示默认 AP 而没有加入热点，先用串口检查 `/root/init.sh`、`wifi_switch` 和内核 Wi-Fi 日志。切换 TF 卡可能改变 SSH 主机密钥；应先从串口或可信渠道核对新指纹，再更新本机 `known_hosts`，不要用 `StrictHostKeyChecking=no` 绕过核验。

## 3. 上板：部署配套用户态

把 `root@BOARD_IP` 换成当前系统的真实地址：

```sh
./deploy.sh starry root@BOARD_IP --check
./deploy.sh starry root@BOARD_IP

./deploy.sh linux root@BOARD_IP --check
./deploy.sh linux root@BOARD_IP
```

部署前脚本检查摄像头与 TPU 设备节点、拒绝正在运行的 `akars`，校验模型和新程序 SHA-256，备份板端旧程序后再替换。StarryOS 安装目录为 `/akars_tennis`，Linux 为 `/root/akars_linux`。若新系统尚未联网，应先通过串口配置网络；`deploy.sh` 不会修改 Wi-Fi 配置。替换旧程序可能需要几 MB 可用空间。

## 4. 实物三球测试与结果

确认球与红色容器已摆好、有人值守，再运行：

```sh
./test.sh starry root@BOARD_IP 3
./test.sh linux  root@BOARD_IP 3
```

可把最后一个参数改为任意正整数。日志保存在板端 `/root/starry-ball-count-...log` 或 `/root/linux-ball-count-...log`；脚本会在完成时直接打印单帧视觉阶段均值、平均置信度、成功放球数及 `AKARS_REPRO_PASS`。抓取中断、程序退出非零或缺失最终统计时返回失败。

这里有两层不同的指标，不能混用：

- **单帧视觉性能**：摄像头等待、JPU、VPSS、TDMA、TPU 前向推理、后处理、视觉总时延和检出帧平均置信度。它们按成功完成视觉链路的网球帧取平均，计算口径见 `linux_base/docs/test-contract.md`；不包含搜索、底盘运动、抓取和放球的整轮耗时。
- **整轮任务性能**：`test.sh` 在板端读取 `/proc/uptime`，从调用 `test-ball-count.sh N` 前到该进程退出后计算 `wall_seconds`；只有日志确认放回 N 球且最终统计齐全时，才输出 `seconds_per_deposit = wall_seconds / N`。该时间包含程序/模型启动、搜索、运动、抓取、寻找红车和放球，但不含宿主机 SSH 握手、编译与刷卡。

