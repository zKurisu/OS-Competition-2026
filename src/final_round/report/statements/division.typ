// ============================================================
//  成员分工及主要贡献说明 · 单独排版
//
//  版式复用 report/theme.typ（与主报告同一套风格）；封面照大赛
//  《项目说明书》模板，只把标题那一行换成「成员分工及主要贡献说明」。
//  封面之后直接开始正文。正文结构参考参考报告的"队员分工"一节：
//  引导段 → 分工表（三线表）→ 表后补充说明。
//
//  目前只收集到队员一的贡献，队员二/队员三先留空（用 #todo 标出）。
//
//  编译（在仓库根目录执行）：
//    typst compile --root . statements/division.typ statements/division.pdf
// ============================================================
#import "../report/theme.typ": *
#import "../report/lib.typ": *
#import "../data/meta.typ": *

#show: report
// 这一份是独立说明，不要主报告那套"第 N 章"编号，标题原样显示
#set heading(numbering: none)
#set figure(supplement: [图], numbering: "1")
#show figure.where(kind: table): set figure(supplement: [表], numbering: "1")
#set page(
  paper: "a4",
  margin: 2.4cm,
  header: running-header,
  header-ascent: 0.85cm,
  footer: none,
)

// —— 封面（标题那行换成"成员分工及主要贡献说明"）——
#cover(
  competition: competition-name,
  kind: "成员分工及主要贡献说明",
  work: work-title,
  team: team-name,
  date: finish-date,
)

// 正文从第 1 页开始编号（封面不计页码）
#counter(page).update(1)

// ============================================================
//  正文
// ============================================================

= 队员分工

本队共三名成员（姓名待补），按子系统分工，各自负责所辖模块的设计、实现、板级测量与复现。
队员一承担视觉推理与驱动协同的主体工作：SG2002 上 StarryOS 的端到端视觉推理链路，UVC、JPU、
VPSS、ION 与 TPU 驱动的实现与优化，YOLOv8 网球检测与机器人拾球闭环，以及全链路插桩与
StarryOS/Linux 同口径基线的对比验证。队员二与队员三的分工见下表。

#tablefigure(
  booktable(
    (2.4cm, 1fr),
    ([成员], [负责模块与交付物]),
    (
      (
        [队员一],
        [
          *视觉推理与驱动协同。* 围绕 SG2002 构建 StarryOS 端到端视觉推理链路，参与并完成
          *UVC、JPU、VPSS、ION 与 TPU 驱动的实现和优化*。UVC 后台异步采集、双缓冲最新帧发布、
          帧序号同步与一帧背压，避免历史帧积压；JPU 硬件解码 MJPEG 4:2:2，YUV422P 三平面直接
          写入 ION 物理缓冲，补齐 JPEG 完整性校验、有界重试、BBC 256 B 页边界预取和异常复位；
          VPSS 扩展 YUV422P 三平面输入 ABI，在单次离线任务中完成 CSC、letterbox、缩放及
          RGB planar/NCHW 输出，修复完成 IRQ 后约 43 ms 的调度长尾，使 VPSS 墙钟降至约
          1.64 ms。

          *TPU 驱动。* 对齐 SOPHGO/CVITEK 官方 ioctl、ION fd 解析、`WAIT_DMABUF` 返回语义和
          任务完成状态，补齐 CV181x 时钟、复位与任务生命周期管理（TPU 700 MHz、FAB 900 MHz）；
          建立 TDMA-only/compute 任务分类及 `submit_to_run`、`fire_to_irq`、`irq_to_resume`、
          `done_to_user` 四段计时，采用同步直通执行消除提交线程与 worker 的重复调度交接，
          并通过 TDMA IRQ 队首唤醒和 2 ms 兜底轮询修复中断—定时器竞态，将 TDMA 输入搬运稳定至
          约 1.11 ms。

          *用户态与机器人闭环。* 完成 YOLOv8 网球检测、红色容器识别、目标选择、二次曲线减速、
          近球微调、机械臂抓取、容器抵近、松球、后退和再次搜索状态机，实现多球连续自主回收。

          *测评与验证。* 建立摄像头、JPU、VPSS、TDMA、TPU、后处理全链路插桩和
          StarryOS/Linux 同口径基线，StarryOS 单帧视觉时延 53.024 ms、等效处理速率 18.86 FPS、
          平均置信度 93.13\%，较 Linux 基线 54.230 ms 降低 2.22\%，完成三球任务与长时间
          稳定性验证。
        ],
      ),
      ([队员二], [#todo[待填：负责模块与交付物]]),
      ([队员三], [#todo[待填：负责模块与交付物]]),
    ),
  ),
  caption: [三名成员按模块与交付物的分工],
)

视觉链路的结论建立在同口径基线上：摄像头取流、JPU 解码、VPSS 预处理、TDMA 搬运、TPU 前向与
后处理六段各自插桩计时，两侧使用同一份符合 Linux ABI 的可执行文件与同一模型，因此同一负载在
StarryOS 与 Linux 上呈现的差别只来自操作系统本身。VPSS 完成中断后的调度长尾与 TPU 的
中断—定时器竞态都是先由分段时间戳定位、再落到驱动改动，修复前后的对比数据与复现命令另见测试文档。

#todo[待补：队员二、队员三的负责模块与交付物；三位成员姓名与队长标注；三人工作在哪些环节交汇；
以及各贡献对应的 PR 编号与合入状态。]
