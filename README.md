# 面向智能机器人的 AIOS

> SG2002 网球拾取机器人上搭载 SG2002 并完成视觉流水线的实现与系统级优化

第三届中国研究生操作系统开源创新大赛 · 暨开放原子大赛操作系统专项赛 · 系统创新赛道

| 项 | 内容 |
|---|---|
| 赛题名称 | 面向智能机器人的 AIOS |
| 目标平台 | Licheerv-Nano / SG2002 |
| 参赛队伍 | Xenoblade |
| 参赛学校 | xxx |
| 队　　员 | xxx, xxx, xxx |
| 开源协议 | 源代码 Apache-2.0，文档与答辩材料 CC BY-SA 4.0 |

本工作以一台搭载 SG2002 芯片的开源网球捡拾机器人作为载体，面向边缘侧具身智能应用，将其操作系统由 C 语言编写的 Linux 移植到用 Rust 开发的 Starry。摄像头负责采集画面，YOLOv8 模型由片上 TPU 执行并给出检测结果，机械臂与底盘据此完成捡球动作。目前，从成像到抓取的整条链路已能在 Starry 上完整运行，检测输出与 Linux 基线相同；在 640×480 的输入分辨率下（与摄像头输出一致），单帧端到端处理时延为 53.024 ms，而 Linux 为 54.230 ms，两者基本持平。

## 决赛材料

决赛的主要材料如下，其余说明文档列举在后文:

| 材料 | 入口 |
|---|---|
| 项目说明书 | 📄 [`docs/项目说明书.pdf`](docs/项目说明书.pdf) |
| 项目创新说明 | 📄 [`docs/项目创新说明.pdf`](docs/项目创新说明.pdf) |
| 人工智能及第三方工具使用声明 | 📄 [`docs/人工智能及第三方工具使用声明.pdf`](docs/人工智能及第三方工具使用声明.pdf) |
| 成员分工及主要贡献说明 | 📄 [`docs/成员分工及主要贡献说明.pdf`](docs/成员分工及主要贡献说明.pdf) |
| 决赛现场演示PPT | 📑 [`presentation/决赛现场演示PPT.pptx`](presentation/决赛现场演示PPT.pptx) |
| 作品演示视频 | 🎬 [demo/demo.mp4](demo/demo.mp4) |
| 决赛报告材料目录（Typst 源码、数据、图）| 📁 [`src/final_round/report`](src/final-round/report) |

(作品演示可以添加其他脚本的运行视频以及开发流程视频)

## 基线版本

本工作的实现依托多个开源项目，其依赖关系在初次提交时已逐一注明。内核取自 rcore-os/tgoskits 的 main 分支；机器人程序从 chenlongos/akars 移植而来，并按 tgoskits 的应用形态改造；U-Boot 与 FreeRTOS 来自 sipeed/LicheeRV-Nano-Build，逐项出处见 [src/final_round/docs/THIRD_PARTY.md](src/final_round/docs/THIRD_PARTY.md)。

| 基础版本 | 仓库 | 基线 |
|---|---|---|
| 操作系统内核 | rcore-os/tgoskits @ `main` | commit `67beb17`（2026-09-14，“Merge pull request #2402 from rcore-os/dev”）|
| 机器人应用 | chenlongos/akars | 见 [`src/final_round/docs/THIRD_PARTY.md`](src/final_round/docs/THIRD_PARTY.md) |
| U-Boot和FreeRTOS | sipeed/LicheeRV-Nano-Build | 见 [`src/final_round/docs/THIRD_PARTY.md`](src/final_round/docs/THIRD_PARTY.md) |

## 完成情况

本工作的推进顺序与评审所设的三个阶段一致：第一阶段先把推理链路上板跑通，第二阶段转向机器人本体、接通感知与执行部件后完成真实拾球，第三阶段则对照 Linux 基线逐项做性能优化。

| 阶段 | 状态 | 说明 |
|---|---|---|
| 一　上板启动、打通 TPU 推理 | ✅ | xxx |
| 二　补齐本体外设、实现实际拾球 | ✅ | xxx |
| 三　对照 Linux 基线做性能优化 | ✅ | xxx |
| 　　启动速度、内存占用与整机功耗的对照 | 进行中 | xxx |

## 关键结果
两侧均部署在 SG2002 平台，采用相同的 640×640 网球检测模型、置信度阈值及处理流程。StarryOS 的单帧视觉总时延为 53.024 ms，Linux 基线为 54.230 ms，StarryOS 减少 1.206 ms，整体快约 2.22%；两侧平均置信度分别为 93.13% 和 93.62%，检测结果基本一致。

| 指标 | StarryOS | Linux 基线 |
|---|---:|---:|
| 摄像头等待 | 5.489 ms | 0.051 ms |
| JPU 解码 | 1.645 ms | 11.033 ms |
| VPSS | 1.643 ms | 1.865 ms |
| 摄像头/JPU等待 + VPSS | 8.776 ms | 12.949 ms |
| TPU 输入 TDMA 搬运 | 1.114 ms | 0.971 ms |
| TPU 推理 | 41.309 ms | 39.721 ms |
| 后处理 | 1.632 ms | 0.449 ms |
| 其他视觉开销 | 0.194 ms | 0.140 ms |
| **视觉总时延** | **53.024 ms** | **54.230 ms** |
| **单帧平均置信度** | **93.13%** | **93.62%** |

StarryOS 的主要优势集中在图像前端：JPU（解码仅需1.645 ms，使摄像头采集、硬件解码和VPSS（Video Processing Subsystem，视频处理子系统）预处理的合计时延降至8.776 ms，比Linux低4.173 ms。该优势主要来自StarryOS内核对UVC、JPU、ION和VPSS驱动链路的针对性优化，并由用户态程序通过专用ioctl和共享缓冲区接口完成设备间协同，从而减少帧积压、框架调度和大尺寸图像复制开销。

经过任务同步直通、worker排队消除、IRQ（Interrupt Request，中断请求）优先唤醒、TDMA等待竞态修复以及时钟与复位生命周期补全后，StarryOS的TPU内核驱动性能已基本比肩Linux。其输入TDMA搬运仅比Linux多0.143 ms，TPU推理仅多1.588 ms，两者已经处于同一性能量级，证明StarryOS此前由任务交接和中断后调度造成的数十毫秒软件开销已基本消除。当前差距主要来自运行时返回、DMA映射和缓存策略等细节，而非TPU硬件执行能力或内核调度架构的数量级差异。尽管CPU后处理仍多消耗1.183 ms，StarryOS凭借图像前端约4.173 ms的优势，最终将整条视觉链路的单帧时延降低至53.024 ms，比Linux基线低1.206 ms，表明优化后的StarryOS不仅实现了TPU驱动性能追平，也在端到端视觉处理性能上略微超过Linux。后端约2.968 ms的劣势，使整条视觉链路在本轮测试中追平并略微超过Linux基线。

内核侧收益:
| 指标 | StarryOS 优化前 | StarryOS 优化后 | Linux 基线 |
|---|---:|---:|---:|
| xxx | xxx | xxx | xxx |

## 增量贡献

本队在上述基础上的增量贡献见下表，还未提交至上游仓库 rcore-os/tgoskits，而是提交到了 fork 的仓库 zKurisu/tgoskits。

| 贡献 | 位置 | fork 仓库提交 |
|---|---|---|
| xxx | xxx | xxx |

## 后续工作
系统层面仍有几处可以推进。当前TPU计算占单帧视觉时延的77.9%，其中97%以上为真实硬件命令流，后续性能提升将主要依赖模型结构、编译器算子融合和片上内存规划，而非继续压缩已经接近硬件能力的VPSS阶段。TPU输出张量目前采用非缓存映射，CPU后处理仍比Linux多约1.183 ms，下一步将尝试可缓存映射与显式缓存失效相结合的所有权切换机制。摄像头与JPU之间尚存在一次几十KB的JPEG码流复制，也可通过不可变帧对象或物理位流环形缓冲进一步消除。在此基础上，系统还可配置双组ION缓冲区，使第 \(N\) 帧进行TPU推理时，第 \(N+1\) 帧同步完成JPU解码和VPSS预处理，形成跨帧硬件流水线；该方案将以闭环响应时间和图像帧龄为约束，避免单纯提高吞吐率却引入DDR争用和历史帧积压。
后续工作将重点提升视觉推理链路的计算效率与数据传输性能。
- 优化模型结构与编译策略，降低TPU计算时延。
- 改进TPU输出缓存属性，减少CPU后处理开销。
- 消除JPEG压缩码流的临时复制。
- 构建JPU、VPSS与TPU跨帧流水线，提高处理吞吐率。

系统层面有几处仍可推进。架构感知的调度将依据各核算力自动放置用户态与内核态的线程，免去手动绑核。NPU 的三核可独立工作，而当前的串行点在于设备锁在整个推理期间被持有，一个以每核队列与中断组织的并发完成路径，是进一步提升推理吞吐的结构前提。本队为运行 Weston 合成器而实现的一组图形与显示内核能力，亦开出一条面向用户侧的方向，在开发板上原生呈现相机画面、检测框与机器人状态的监控界面，并把 Weston 的图层合成由 CPU 改交视觉流水线已用到的同一块 RGA 引擎承担。

机器人应用层面还能继续推进的方案:

- 引入抓球是否成功的稳健判断, 在失败后继续重试。
- 引入决策模型, 让模型控制 action 而非状态机编码。

内核层面:
- xxx

## 其它文档
`src/first_round/docs/` 目录下的说明文档如下:
| 类别 | 文件 |
|---|---|
| SG2002上手手册 | [`src/first_round/docs/0_sg2002_start.md`](src/first_round/docs/0_sg2002_start.md) |
| StarryOS上板手册 | [`src/first_round/docs/1_starryos_on_sg2002.md`](src/first_round/docs/1_starryos_on_sg2002.md) |
| U-Boot上板手册 | [`src/first_round/docs/2_uboot_on_sg2002.md`](src/first_round/docs/2_uboot_on_sg2002.md) |
| Linux寻球基线手册 | [`src/first_round/docs/3_linux_baseline.md`](src/first_round/docs/3_linux_baseline.md) |
| 裸机驱动简单教程 | [`src/first_round/docs/4_bare_driver_start.md`](src/first_round/docs/4_bare_driver_start.md) |
| StarryOS驱动编写流程 | [`src/first_round/docs/5_starry_driver_start.md`](src/first_round/docs/5_starry_driver_start.md) |

`src/final_round/docs/` 目录下的说明文档如下:

| 类别 | 文件 |
|---|---|
| xxx | xxx |

## 构建与运行
xxx

## 开源协议

源代码以 Apache License 2.0 授权，沿用上游 tgoskits 的协议，见 [`LICENSE`](LICENSE)。文档与答辩材料以 Creative Commons Attribution-ShareAlike 4.0 授权，涵盖 `demo/`、 `docs/`、`presentation/`、`src/first_round/docs` 与 `src/final_round/docs`，见 [`LICENSE-docs`](LICENSE-docs)。
