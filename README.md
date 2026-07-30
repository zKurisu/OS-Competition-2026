该仓库用作队伍 Xenoblade 对选题 "面向智能机器人的 AIOS" 的开发记录和提交. 由于各种原因, 我们对内核态并没有太多优化, 而是针对内核功能和用户态寻球程序的 Bug 完成了一些修复, 并且对开发环境和流程有一些总结和便利性的提升.

- [项目结构](#项目结构)
- [核心变更](#核心变更)
- [快速开始](#快速开始)
- [参考项目](#参考项目)

# 项目结构
```
.
├── change                        # 所有代码变更的说明
│   ├── akars.md                  # akars 用户态程序的变更说明
│   ├── u-boot.md                 # u-boot 新功能启用的变更说明
│   ├── tgoskits.md               # tgoskits 和 StarryOS 的更改说明
│   └── patch                     # tgoskits 的变更 patch (基于特定分支)
├── code                          # 所有涉及的代码
│   ├── akars                     # 机器人寻球的用户态程序
│   ├── bare_driver_example       # 编写裸机驱动的示例程序
│   ├── LicheeRV-Nano-Build       # 含 u-boot 源码
│   └── tgoskits                  # 内核源码
├── doc                           # 学习和流程记录文档
│   ├── 0_sg2002_start.md         # 在 SG2002 上运行 Linux
│   ├── 1_starryos_on_sg2002.md   # 在 SG2002 上运行 StarryOS
│   ├── 2_uboot_on_sg2002.md      # 用 U-Boot 便利开发
│   ├── 3_linux_baseline.md       # 测试 Linux baseline 程序
│   ├── 4_bare_driver_start.md    # 编写裸机驱动的示例流程
│   ├── 5_starry_driver_start.md  # 为 StarryOS 编写驱动的分析
│   ├── 6_starry_baseline.md      # 测试 StarryOS baseline 程序
│   └── img                       # 文档中用到的图片
├── README.md                     # 项目说明文档
├── 作品原创承诺书.pdf
├── 操作系统开源创新大赛PPT模板.pptx
├── 操作系统开源创新大赛项目说明书.docx
└── 演示视频.mp4

10 directories, 15 files
```

# 核心变更
## tgoskits
对于 `tgoskits` 以及 StarryOS, 变更的细节在 [change/tgoskits.md](change/tgoskits.md) 文件中, 具体包括:
- 启用 `init.sh` 初始化脚本, StarryOS 启动登入后自动运行一个 Shell 脚本
- 启用 WiFi, 能够创建网卡并连接无线网络
- 启用 FAT 挂载, 能够将 FAT 分区挂载到 `/boot` 目录下
- 启用 `ktracepoint`, 能够统计内核函数所使用的系统调用信息
- 启用 `dmesg`, 能够查看内核的日志输出
- 启用 `cvi` 重初始化, Camera 在 IO error 之后能重置状态

## u-boot
对于 `u-boot`, 变更的细节在 [change/u-boot.md](change/u-boot.md) 文件中, 具体包括:
- 启用 `saveenv`, 保存在 u-boot 环境下设置的环境变量
- 启用 `ums`, 用 USB 连接 SG2002 时, 可以将板子上的 SD 卡作为块设备挂载到本地
- 启用 `tftpboot`, 用 USB 连接 SG2002 时, 可以通过 RNIDS 网卡 与宿主机网络连接

## akars
对于 `akars`, 变更的细节在 [change/akars.md](change/aksrs.md) 文件中, 具体包括:
- 修改 `INIT` ioctl 代码顺序, 原逻辑导致大量不完整帧并触发丢弃
- 启用 JPU 硬件解码, 原逻辑用用户态程序软解码
- 寻球和拾取逻辑优化, 用多步电机控制, 先将网球拉近到车身再拾取, 并优化小车速度控制和机械臂角度

# 快速开始
拉取仓库:
```sh
git clone https://gitlink.org.cn/HTU05jAPnO/mxznjqrdaios.git
cd mxznjqrdaios
git submodule update --init --recursive
```

## 手动构建
具体流程见 [doc/](doc/) 下的文档.

# 参考项目
- [rcore-os/tgoskits](https://github.com/rcore-os/tgoskits)
- [chenlongos/AKA-00](https://github.com/chenlongos/AKA-00)
- [chenlongos/akars](https://github.com/chenlongos/akars)
- [sipeed/LicheeRV-Nano-Build](https://github.com/sipeed/LicheeRV-Nano-Build)
- [milkv-duo/duo-buildroot-sdk](https://github.com/milkv-duo/duo-buildroot-sdk)
