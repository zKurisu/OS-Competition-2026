// ============================================================
//  SG2002 C906L 小核工作线 —— 可嵌入决赛报告的一节（独立编译稿）
//  版式对齐 docs/final-round/report：Songti 正文、黑体标题、编号节、
//  booktabs 表、深蓝底图 + 青/琥珀配色、图题"图 N: …"。
//  编译：typst compile c906l-report-section.typ c906l-report-section.pdf
// ============================================================

#let sans = ("Heiti SC", "Source Han Sans", "Noto Sans CJK SC")
#let serif = ("Songti SC", "Source Han Serif", "Noto Serif CJK SC")
#let mono = ("JetBrains Mono", "Noto Sans Mono CJK SC", "DejaVu Sans Mono")
// 与 final-round/style/tokens.tex 同一组色板
#let navy = rgb("#0D1B2A")
#let teal = rgb("#2DD4BF")
#let amber = rgb("#F59E0B")
#let ink-light = rgb("#EEF3F8")
#let muted = rgb("#8AA0B4")
// 纸面正文用色（style.py 的 light 变体）
#let ink = rgb("#1A2230")
#let rule = rgb("#C8D2DC")
#let track = rgb("#22303F")

#let sec-no = "20"                    // 插入报告时改这一个数即可整体重编号
#let sec-title = "SG2002 实时小核：跨核通道、底盘链路接管与确定性验证"

#let running-head = context {
  set text(font: sans, size: 8.5pt, fill: ink)
  grid(
    columns: (1fr, auto),
    align: (left, right),
    [#sec-no #sec-title],
    [#counter(page).display()],
  )
  v(-4pt)
  line(length: 100%, stroke: 0.4pt + rule)
}

#set page(
  paper: "a4",
  margin: (x: 2.4cm, top: 2.4cm, bottom: 2.4cm),
  header: running-head,
  header-ascent: 1.1cm,
)
#set text(font: serif, size: 11pt, fill: ink, lang: "zh", region: "cn")
#set par(justify: true, leading: 0.87em, spacing: 0.87em, first-line-indent: (amount: 2em, all: true))
#show raw.where(block: false): it => box(
  fill: rgb("#F1F3F5"), inset: (x: 3pt, y: 0.8pt), radius: 2pt,
  text(font: mono, size: 0.9em, it),
)
// —— booktabs 式表格：无竖线、无底纹，只用横线 ——
#show table: set table(stroke: none, inset: (x: 6pt, y: 4.5pt))
#show table: set text(size: 9pt)
#show table.cell: set par(first-line-indent: 0pt)
#show table.cell.where(y: 0): set text(font: sans, weight: "bold")
#show table.hline: set line(stroke: 0.8pt + ink)
// —— 标题：与 report 一致，无颜色、黑体、编号写在标题里 ——
#show heading.where(level: 1): it => block(
  above: 2.2em, below: 0.9em,
  text(font: sans, size: 14.5pt, weight: "bold", it.body),
)
#show heading.where(level: 2): it => block(
  above: 1.4em, below: 0.55em,
  text(font: sans, size: 12pt, weight: "bold", it.body),
)
#show heading.where(level: 3): it => block(
  above: 0.9em, below: 0.35em,
  text(font: sans, size: 11pt, weight: "bold", it.body),
)
// —— 图题："图 N: 说明"，小号居中，标签加粗 ——
#show figure.caption: it => context {
  set text(size: 9pt)
  block(above: 0.55em, align(center)[
    #strong[#it.supplement #it.counter.display(it.numbering):] #it.body
  ])
}

// ------------------------------------------------------------
//  本节图表的数据单一来源：所有条形图都从这里取数，改数只改这一段。
//  数据出处（工作区内的原始记录）：
//    d-lat    ← typst/src/02-ipc-mailbox-cmdqu.typ 2.7.5/2.7.9.1（cmdqu_test latency 50）
//    d-ab     ← typst/src/11-m3-chassis-link.typ 6.7.3 与 typst/src/14-*.typ 11.10（A/B 与带载）
//    d-period ← typst/src/15-failover-and-control-period.typ 7.2（ctrl_period_sweep 原始采样）
//  更新流程：先更新上述章节里的实测值，再改这里，重新编译本文件即可复现全部图表。
// ------------------------------------------------------------
#let d-lat = (min: 53, p50: 54, p90: 266, max: 413, poll: 1000)          // µs
#let d-ab = (                                                              // ms，相对 100 ms 周期
  ("空载", 0.211, 0.215),
  ("3 × yes 打满 CPU", 1.536, 1.750),
  ("视觉 validator", 0.947, 0.950),
  ("带载 20%（压地）", 0.331, 0.333),
)
#let d-period = (("5 ms", 2994, 2995), ("10 ms", 1456, 1457), ("20 ms", 664, 665), ("50 ms", 237, 237), ("100 ms", 79, 79))

#let hbar(frac, fill: teal, h: 8pt, w: 4.4cm) = box(
  width: w, height: h, fill: track, radius: 2pt, clip: true,
)[#place(rect(width: w * calc.max(frac, 0.004), height: h, radius: 2pt, fill: fill))]

#let fig-todo(id, caption, prompt) = figure(
  block(
    width: 90%, inset: (x: 12pt, y: 10pt), radius: 4pt,
    stroke: (paint: rule, thickness: 0.9pt, dash: "dashed"),
  )[
    #text(font: sans, size: 9pt, weight: "bold", fill: muted)[待生成图 #id（占位）]
    #v(4pt)
    #set par(first-line-indent: 0pt, leading: 0.72em, spacing: 0.5em)
    #text(size: 9.3pt)[*画面要求（可直接交给图像模型）*：#prompt]
  ],
  caption: caption,
)

= #sec-no #sec-title

SG2002 是一颗面向低功耗视觉终端的异构 SoC：除一颗 1 GHz 的大核之外，片内还有一颗 RISC-V C906\@700MHz 的"协处理器"（本文称 C906L）。厂商把它的固件固定在 DRAM 末尾 2 MiB，出厂镜像里也确实在跑，但它既不参与 Linux/StarryOS 的调度，也不被内核的任何子系统管理，对操作系统而言是一颗"存在但未被使用"的核。本项目这条工作线做的事情，是把这颗核从"厂商固件里自转"变成"可被 StarryOS 管理、可被应用使用"的第二个可编程执行体：先打通核间通道并把它做成正式驱动，再让这颗实时核接管一条真实的硬实时链路（底盘串口控制），最后用同机、同负载、同链路的 A/B 数据回答它到底带来了什么。结论可以先用一句话概括：#strong[收益不在算力，而在确定性与故障兜底]------底盘控制周期的抖动从负载下 p99 恶化 1.5 ms 降到 0 抖动（控制周期 100 ms，全部样本落在同一 tick 刻度），并且在大核失效或卡死时，车能在心跳窗口内自主停车。本节按"平台事实—跨核通道—链路接管—确定性收益—失效兜底—可扩展能力—负结果与方法"的顺序展开，所有数字均来自实板测量，方法与边界一并给出。

== 20.1 为什么要用这颗小核：单核平台的实时缺口与冗余缺口

SG2002 在这一版板卡上只有一颗通用核在跑操作系统。C906 与 Cortex-A53 两颗大核由引脚二选一，实战配置里不会同时出现；小核虽然存在，却被厂商固件独占。于是整台车的软件栈------摄像头取流、JPEG 解码、TPU 推理、跟踪与决策、串口下发------全部排在同一个核的时间片上，实时工作与非实时工作共享同一个调度器。控制链路的延迟不再由代码决定，而由最拥挤的那一刻决定。

这个缺口可以用数字说清。空载时大核直控的控制周期 p99 相对 100 ms 只偏 0.21 ms，看起来完全够用；一旦有 3 个纯计算负载把核压满，p99 就恶化到 #strong[1.54 ms]（约 8 倍），同一时刻串口 ioctl 的往返从 120--390 µs 涨到 #strong[3,670 µs]。对"轮速闭环"这类机构而言，这种由负载决定的长尾不是性能问题，而是不可承诺的时序问题：机构容差是否被突破，取决于当时有没有别的程序在跑。小核接管之后，同一台车、同一条链路、同样的负载，控制周期在三种负载下都是 0 抖动------全部样本落在同一个 tick 刻度上。

比实时抖动更严重的是#strong[单点失效]。车在运动时，底盘板执行的是"最后一条速度指令一直有效"，它不会主动停车；如果唯一的通用核进入内核崩溃、关键进程被杀、或者被高优先级负载长时间饿死，那么限速、看门狗与停车指令会随它一起消失------车保持最后一条 PWM 继续冲，直到撞上东西或有人断电。我们在实车上复现过这条路径：应用退出后不再下发任何指令，轮子一直转；整芯片软复位也不停，因为底盘板仍有电、寄存器仍保存着最后的速度。反过来，当链路交给独立运行 RTOS 的小核，大核停止喂心跳约 500 ms 后小核就自己把两轮 `STOP` 并保持静默；即便大核完全挂死，另一个只读判据（小核 PC 恒为 0、控制计数不再前进）也能让大核侧脚本把 UART1 抢回来并补发停车序列。这条兜底链已经用"真的把核心停掉"的方式演练通过。

因此使用小核的理由可以归纳为三条，且都与算力无关。其一是#strong[实时职责的卸载]：底盘串口链路的所有权移交小核后，周期性下发、状态回读与超时判定都不再依赖大核的时间片，大核只需要交换目标与状态；对小核来说那只是每 100 ms 一次的串口任务，占用极小。其二是#strong[故障域的隔离]：控制与兜底跑在一颗不参与通用调度的核上，大核的崩溃、卡死与重启不再同时带走"停车"这个能力。其三是#strong[低成本的加法]：小核与大核同片集成，不增加 BOM、不增加板卡与连线、与内核共享同一块 DDR 可直接共享内存，并且可以被操作系统当作一个设备来管理------相比之下，外挂一颗 MCU 虽然也能解决实时与冗余问题，但要付出额外的器件、接口、电源以及两套固件维护的代价。

同样要说明它的代价：小核算力低于大核、没有 TPU 访问、外设面窄，工具链与引脚归属都存在未知项。所以我们对它的定位是#strong[只接实时与兜底职责]------底盘链路所有权、固定周期采样、停止与看门狗、上电快速就绪；推理、图像预处理与电机闭环仍然留在大核与底盘板上。下面的图把单核方案与小核方案的分工与失效路径画在一起，便于一眼看清这条工作线要解决的问题。

#fig-todo("A", [单核平台与小核兜底：分工与失效路径对比], [横版系统示意图，左右对照。左半"单核方案"：一颗大核方框内并排画出（相机取流 / JPEG 解码 / TPU 推理 / 决策 / 串口控制）五个任务块，共用一条拥挤的时间轴；下方用红色箭头标出"kernel panic 或高负载"导致整框熄灭，再画一条红色箭头从底盘板指向"车继续冲撞"，旁注"最后一条 PWM 一直有效"。右半"小核方案"：大核方框只留感知与决策，另画一颗标注 C906L 的独立小核方框，内含"100 ms 周期下发 / 状态回读 / 心跳看门狗 / 堵转停车"；两核之间用双箭头标出"ap_mailbox + 共享内存"，小核与底盘板之间用一条蓝色 UART 链连接；当大核框熄灭时，小核框保持亮起并向下发出一根"STOP"箭头，旁注"≤500 ms 内停车"。风格：扁平矢量，深色底（\#0D1B2A 深蓝）配青色 \#2DD4BF 主色与琥珀 \#F59E0B 警示色（与报告图表同一色板），文字用浅色 \#EEF3F8，方框圆角、箭头清晰，图内文字用中文、字号够大，适合 A4 单栏宽度（约 16 cm × 8 cm）。],)

== 20.2 平台事实：这颗核在哪、归谁管、能碰什么

C906L 与大核不是同一个 hart。大核由引脚 `GPIO_RTX` 二选一（RISC-V C906\@1GHz 或 ARM Cortex-A53\@1GHz），小核固定为 RISC-V C906\@700MHz，无引脚可换。厂商的头文件用 CPU0/CPU1/CPU2 区分三颗核：CPU0 = Cortex-A53、CPU1 = C906B（当前 StarryOS 运行核）、CPU2 = C906L（小核）。设备树只描述一个大核，`boot-hartid=0`，因此内核既看不到也不会调度这颗小核。

小核的固件有固定落点。厂商内存布局把 256 MiB DRAM 的最后 2 MiB 划给 C906L FreeRTOS，起始地址 `0x8FE00000`，内核可见内存因此是 254 MiB；这与 TGOSKits 现有 SG2002 设备树的 `memory@80000000`（0xFE00000）与 `fast_image`（`0x8fe00000 + 0x200000`、`ion-size = 0x1600000`）逐项对上。小核由 FSBL 在 M 模式释放一次，之后没有任何软件再动它；操作系统与它之间只有一条核间通道。

这条通道是 `ap_mailbox`（`0x01900000`，4 KiB）。它把 64 字节的上下文内存切成 8 个 8 字节槽位，与 8 个中断位一一对应；每槽放一个 `cmdqu` 信封（8 字节：`ip_id`、7 位 `cmd_id` 与 1 位 `block`、两个方向有效位或超时、32 位 `param_ptr`），真正的负载经 `param_ptr` 指向共享内存。协议头文件是公开的，#strong[不需要逆向]。控制面同样不神秘：厂商 Linux 走 SBI 的自定义 BASE 扩展（功能号 0x7/0x8/0x9），但这套服务在本项目的构建链里并不存在；实测表明 #strong[S 模式可以直接写小核的复位与入口寄存器]（`SEC_SYS_BASE`、`RSTC`），`sg200x-bsp` 已经把等价序列封装成 `SecSys::start_secondary_core()`。也就是说，启动或复位小核不需要改 M 模式固件，缺的只是通道驱动。

小核的外设面很窄。TRM 没有任何描述 C906L 外设归属的章节，只能从厂商 RTOS 固件反推：`driver/` 下有 `gpio`、`i2c`、`uart`、`pinmux`、`cif`、`jenc`、`sensor`、`rgn`，`task/` 下有 `isp`、`vi`、`vcodec`、`camera`、`audio`------换言之，厂商的设计意图就是"摄像头 + ISP + 视频编解码 + 音频 + 慢速外设的协处理器"。相反，小核固件里#strong[没有 USB、没有 TPU/NPU、没有 SD、没有以太网]，这说明#strong[不应把它当算力或推理单元使用]。

#figure(
  align(center)[#table(
    table.hline(stroke: 1.2pt + ink),
    columns: 2,
    align: (auto,auto,),
    table.header([项目], [事实],),
    table.hline(),
    [大核 / 小核], [C906\@1GHz 或 Cortex-A53\@1GHz（引脚选择）/ RISC-V C906\@700MHz 协处理器],
    [CPU 编号], [CPU0 = CA53、CPU1 = C906B（运行核）、CPU2 = C906L],
    [固件落点], [DRAM 末尾 2 MiB，`0x8FE00000`；内核可见内存 254 MiB],
    [核间硬件], [`ap_mailbox` @ `0x01900000`，4 KiB，8 槽 × 8 字节 `cmdqu` 信封],
    [控制路径], [S 模式直写 `SEC_SYS_BASE` / `RSTC` 即可复位与重载（已实测）],
    [小核外设面], [gpio / i2c / uart / pinmux / cif / jenc / sensor + isp / vi / vcodec / audio；无 USB / TPU / SD / 以太网],
    table.hline(stroke: 1.2pt + ink),
  )]
  , kind: table
  )

== 20.3 跨核通道：从寄存器到设备节点

通道的第一层是驱动。#strong[mailbox 的 MMIO 必须显式建立非缓存映射]：同一段发送代码用默认的 `iomap` 会让写滞留，表现为"消息写进槽位但小核始终不取、本核也收不到中断"，换用非缓存映射后一次跑通。共享上下文与负载缓冲同理，C906 的 D-cache 不参与跨核一致性。第二层是锁与唤醒：中断上下文只能用 IRQ-save 自旋锁（最初用睡眠锁会让内核直接以 `validate sleeping lock context failed` 终止），持锁期间不能调用分配器，因此接收队列是固定容量 64 的环形数组；等待路径按"硬中断 → 固定服务线程 → 等待队列"三段式实现------硬中断只把槽位搬进队列并用 `IrqWaitCell` 唤醒服务线程，服务线程在任务上下文里扇出 `WaitQueue`，等待者自身还保留一条"超时前复查硬件队列"的自愈路径。

第三层是共享内存。mailbox 只传 8 字节信封，状态快照、事件环与命令回流走一块 1 MiB 的保留区（`0x8B200000`，放在 ION 窗口正下方，严格不与厂商给小核的 carve-out 重叠），由设备树的 `reserved-memory` 声明，驱动按 `cvitek,cmdqu-shm` 探测并强制非缓存映射，用户态经 `mmap` 直接读写。布局当前为 v3：头部 192 字节按#strong[写入方]拆成三条独立 cache line（常量 / 大核写 / 小核写），同步块拆成大小核两半，后接两条 64 槽 × 64 字节的环（Ring A 大核到小核、Ring B 小核到大核），消息为 16 字节元信息加 48 字节载荷并带 CRC32。之所以把头部按写入方拆行，是一次实测教训：v2 把两个环的 head/tail 挤在一条 64 字节缓存行里，小核整行回写时会#strong[顺带用旧副本覆盖掉大核写的 `tail`]，大核按 tail 记账因此忽多忽少，一度被误读成"小核 tick 慢 2.19%"。

第四层是用户态接口。驱动注册 `/dev/cvi-rtos-cmdqu`（字符设备 10:58），提供发送（即发即弃）、接收、等待#strong[指定]应答命令号的 `EXCHANGE`、`poll`/`epoll` 就绪语义与调试体检接口；等待的应答命令号由调用方显式给出，这是厂商驱动做不到的（它把等待命令号写死成发送命令号，0x51 等 0x52 只能静默超时）。超时只通过 `errno` 返回（`ETIMEDOUT`），结构体不产生无定义的输出。

#fig-todo("B", [跨核通道的软件数据通路], [横版数据通路示意图，从左到右、上下两层。上层为大核 StarryOS 侧：用户态进程（画成方框）经设备节点 cvi-rtos-cmdqu 进入内核，内核里依次画出"中断处理（只搬运槽位）→ 固定服务线程 → 等待队列"三段，用不同颜色的圆角框区分硬中断上下文与任务上下文；下层为硬件与共享内存：ap_mailbox（0x01900000）画成 8 个小方格表示 8 个 8 字节槽位，旁边画一条共享内存块（0x8B200000，1 MiB），内部标出"头部三条 cache line（常量 / 大核写 / 小核写）"与两条环形队列 "Ring A 大核→小核"、"Ring B 小核→大核"。右侧是一颗标注 C906L 的小核，它经 mailbox 收门铃、从 Ring A 取命令、把状态写进 Ring B。要求用不同颜色标出"门铃与中断路径"与"数据路径"，并在关键处标注数字：往返 274--299 µs、p50 54 µs、dropped=0。风格：扁平矢量，深色底（\#0D1B2A）配青色 \#2DD4BF 与琥珀 \#F59E0B（与报告图表同一色板）、浅色文字，圆角方框、箭头清晰，图内中文标注，适合 A4 单栏宽度（约 16 cm × 9 cm）。],)

板级实测：单次"发送并等待应答"的往返 274/277/299 µs，而改造前的 1 ms 轮询实现下界就是 1000 µs；往返延迟分布呈双峰，p50 ≈ 54 µs 是未入睡即命中的快路径，p90 ≈ 266 µs、max ≈ 413 µs 是经中断唤醒的慢路径。连续 5 次运行累计 `tx=rx=irq=12 dropped=0`，环消息逐条 CRC 通过。双核时间基准也在这条工作线上钉死：修复度量缺陷后，小核每 tick 真实时长 #strong[5000.00 µs（-0 ppm）]，24,307/24,307 个间隔都正好一个 tick、两分钟零推迟。

#figure(
  block(width: 88%, fill: navy, inset: (x: 14pt, y: 12pt), radius: 4pt)[
    #set par(first-line-indent: 0pt, leading: 0.7em, spacing: 0.4em)
    #text(font: sans, size: 9.5pt, fill: ink-light)[跨核往返延迟（中断驱动，单位 µs）]
    #v(6pt)
    #grid(
      columns: (2.6cm, 1fr),
      row-gutter: 5pt,
      align: (right + horizon, left),
      [#text(size: 9pt, fill: ink-light)[min]], [#hbar(d-lat.min / 1100) #h(5pt) #text(size: 9pt, fill: ink-light)[#d-lat.min]],
      [#text(size: 9pt, fill: ink-light)[p50]], [#hbar(d-lat.p50 / 1100) #h(5pt) #text(size: 9pt, fill: ink-light)[#d-lat.p50]],
      [#text(size: 9pt, fill: ink-light)[p90]], [#hbar(d-lat.p90 / 1100) #h(5pt) #text(size: 9pt, fill: ink-light)[#d-lat.p90]],
      [#text(size: 9pt, fill: ink-light)[max]], [#hbar(d-lat.max / 1100) #h(5pt) #text(size: 9pt, fill: ink-light)[#d-lat.max]],
      [#text(size: 9pt, fill: amber)[旧轮询下界]], [#hbar(d-lat.poll / 1100, fill: amber) #h(5pt) #text(size: 9pt, fill: amber)[#d-lat.poll]],
    )
  ],
  caption: [跨核往返延迟分布（中断驱动）与旧轮询实现的下界。所有条形按同一尺度绘制；中断驱动的 p50 比轮询下界低一个数量级。],
)

#figure(
  align(center)[#table(
    table.hline(stroke: 1.2pt + ink),
    columns: 3,
    align: (auto,auto,auto,),
    table.header([观测], [实测值], [含义],),
    table.hline(),
    [往返延迟（发送 + 等待指定应答）], [274 / 277 / 299 µs], [旧轮询实现下界 1000 µs],
    [往返延迟分布], [min 53 / p50 54 / p90 266 / max 413 µs], [双峰：未入睡命中 / 中断唤醒],
    [稳定性], [`tx=rx=irq=12 dropped=0`（连续 5 次）], [无丢包、无落空],
    [共享区版本], [`version=3 header=192`，Ring A/B 偏移 320 / 4416], [与驱动常量逐项对应],
    [小核 tick], [5000.00 µs（-0 ppm），24,307/24,307 间隔 1 tick], [时间基准一致，无需比例补偿],
    table.hline(stroke: 1.2pt + ink),
  )]
  , kind: table
  )

== 20.4 小核接管底盘链路：三阶段落地

拾球小车的真实链路是"SG2002 经 UART1 连底盘控制板"：底盘在 A18/A19 焊盘上（厂商 Linux 的 `/dev/ttyS1`，115200），电机闭环、驱动与编码器都在底盘板一侧，主控只下发目标速度；机械臂舵机走 UART2。链路归属是用"协议指纹加双向拔插消元"在实车上定案的，不是靠读设备树猜出来的。小核接管这条链路分三步，每一步都有独立的验收判据。

第一步是#strong[独立掌握链路]：固件新增 UART1 轮询驱动与握手任务，默认关闭，由命令 `0x61` 打开后主动与底盘板做 `INIT → ACK` 握手，统计经共享环的 kind=6 消息上报。拔掉排线时 `ack_rx` 冻结、插回后自动恢复，证明收与发两个方向都由小核独立完成。实板结果：`INIT 已发 4→6 次 / ACK 4→6 次 / 累计 24→36 字节 / 帧错误 0`，与设计的 5 秒保活节拍完全吻合。反过来，在裸板上（没有底盘）同一命令会得到 `INIT` 持续增长而 `ACK` 恒为 0、`rx_bytes=0`、`frame_err=0` 的负向基线------两半配对，排除了"软件自说自话"。

第二步是#strong[协议层接管]：以 `mode=2` 走完一遍完整指令集，顺序是 `CONFIG(ppr=4680)` → `SET_SPEED(0,0)` → `SET_SPEED(1,0)` → `STOP(0)` → `STOP(1)`，每条命令等它的 ACK，结果经 kind=7 上报。实板验收 `stage=5`、`err=0`、ACK 总数 10（INIT 5 + CONFIG 1 + SET_SPEED 2 + STOP 2）、累计 60 字节、帧错误 0，且#strong[全程不含任何速度指令，车不会动]。

第三步是#strong[周期服务与心跳看门狗]：命令 `0x62` 下发目标速度即进入 `mode=3`，小核默认每 100 ms 发一次左右轮 `SET_SPEED`，每 5 个控制周期回读一次 `GET_STATUS`（状态加双轮 RPM），结果经 kind=8 上报；控制周期可用 `0x63` 在 5\~1000 ms 之间调整（按 5 ms 基础节拍量化）。同时落地#strong[心跳看门狗]：大核超过 500 ms（`0x64` 可调 100\~10000 ms）没有刷新目标，小核立即 `STOP` 两轮并保持静默，直到新目标到来；`wd_stops` 只在目标非 0 时计数。第四项是在此之上加#strong[堵转与碰撞的软件保护]（kind=10）：目标 PWM 越过死区、两轮 `|RPM| ≤ 5`、连续 3 次命中（起步宽限 700 ms）即停车并锁存，只有目标值发生变化才解除。实板验证：同时按住两个轮子触发 1 次并保持停止，只按住一个轮子判为差速、不触发，正常起步与巡航无误报。这条保护不需要任何新增硬件。

#figure(
  align(center)[#table(
    table.hline(stroke: 1.2pt + ink),
    columns: 4,
    align: (auto,auto,auto,auto,),
    table.header([阶段], [命令 / 模式], [实测结果], [判据],),
    table.hline(),
    [链路握手], [`0x61`，mode=1，kind=6], [INIT 4→6、ACK 4→6、24→36 字节、帧错误 0；拔线冻结、插回恢复], [小核独立完成收发],
    [协议自检], [`0x61` + mode=2，kind=7], [5/5 步、异常 0、ACK 10、60 字节、帧错误 0], [全程零速度指令],
    [周期控制], [`0x62`，mode=3，kind=8], [默认 100 ms；每 5 拍回读 RPM；`dt_max = 周期/5`], [闭环与大核负载解耦],
    [心跳看门狗], [`0x64` 设窗口（默认 500 ms）], [停喂心跳后 `wd_stops` 逐次 +1，窗口内停车], [大核失效后能停],
    [堵转保护], [kind=10], [双轮按住触发 1 次并锁存；单轮差速不触发；改目标解除], [不新增硬件即能"卡住就停"],
    table.hline(stroke: 1.2pt + ink),
  )]
  , kind: table
  )

== 20.5 确定性收益：大核直控与小核接管的 A/B 对照

要证明小核的价值，唯一有说服力的形式是#strong[同机、同负载、同链路的对照]。A 组由大核用户态按固定周期写 `/dev/ttyS1`，用工具测量每一拍的实际间隔；B 组由小核按 tick 计数下发，kind=9 给出"恰好一个周期 / 多一个 tick / 多两个 tick"的分布。两组负载相同：空载、3 个 `yes` 打满大核 CPU，以及卡上真实的感知流水线（`akars-tennis-validator`，它不占用 `/dev/ttyS1`，所以两组合并跑）。

结果是这条工作线最硬的一组数字。空载时大核直控的控制周期 p99 相对 100 ms 只偏 +0.21 ms；换成 CPU 饱和负载后，p99 恶化到 #strong[+1.54 ms]、max #strong[+1.75 ms]（约 8 倍），同一时刻 `uart 0` 的 ioctl 往返从 120--390 µs 涨到 3,670 µs，佐证大核确实被压满。而小核接管在同样两种负载下都是 #strong[min = mean = max = 100.000 ms]：236/236 与 227/227 个样本全部落在期望刻度，抖动为零，轮速稳定在 44--45 RPM。

第三轮把负载换成真实感知流水线后出现了一个反直觉但重要的结果：A 组 p99 只有 +0.947 ms、max +0.950 ms，#strong[比 3 个 `yes` 反而更小]。原因不难解释：`yes` 是"永远就绪"的纯计算竞争者，会把用户态控制进程从时间片上挤开；视觉流水线在文件读与 TPU ioctl 上会阻塞，反而给调度器留下了放行窗口。也就是说，#strong[大核直控的长尾取决于负载是否持续就绪，而不在于它"像不像视觉"]。小核一侧则与负载无关：200/200 仍全部落在 20 tick。带载（车压地、20% 占空比）复测同样成立：A 组 149 拍 p99 = 100,331 µs、max = 100,333 µs，B 组 4,802 个样本 100% 落在 20 tick。

代价只有一条：目标速度从"大核写入"到"线上生效"要等一个控制周期（100 ms 周期下平均 50 ms、最坏 100 ms）。把控制周期压到 5 ms（1 个 tick）后，这一项降到#strong[平均 2.5 ms、最坏 5 ms]，裸板实测 2994/2995 个样本落在 1 tick 刻度；代价是链路上 `SET_SPEED` 帧涨到 200 帧/秒，底盘板能不能吃下这个速率仍需带车验证。

#figure(
  block(width: 88%, fill: navy, inset: (x: 14pt, y: 12pt), radius: 4pt)[
    #set par(first-line-indent: 0pt, leading: 0.7em, spacing: 0.5em)
    #text(font: sans, size: 9.5pt, fill: ink-light)[控制周期偏差（相对 100 ms，单位 ms）]
    #v(6pt)
    #grid(
      columns: (3.8cm, 1fr, 2.6cm),
      row-gutter: 7pt,
      align: (right + horizon, left, left),
      ..d-ab.map(((label, p99, mx)) => (
        [#text(size: 9pt, fill: ink-light)[#label]],
        [#stack(dir: ttb, spacing: 2pt,
          [#hbar(p99 / 2) #h(5pt) #text(size: 8.8pt, fill: ink-light)[p99 +#p99]],
          [#hbar(mx / 2, fill: amber) #h(5pt) #text(size: 8.8pt, fill: ink-light)[max +#mx]],
        )],
        [#text(size: 8.6pt, fill: muted)[B 组 0 抖动]],
      )).flatten(),
    )
  ],
  caption: [A/B 对照：大核直控（A 组）相对 100 ms 控制周期的 p99 与 max 偏差；小核接管（B 组）在全部负载下 min=mean=max，样本 100% 落在期望 tick 刻度。带载一行为 20% 占空比、车压地工况。],
)

#figure(
  block(width: 88%, fill: navy, inset: (x: 14pt, y: 12pt), radius: 4pt)[
    #set par(first-line-indent: 0pt, leading: 0.7em, spacing: 0.4em)
    #text(font: sans, size: 9.5pt, fill: ink-light)[控制周期档位与落在期望刻度的样本占比]
    #v(6pt)
    #grid(
      columns: (2.6cm, 1fr, 2.6cm),
      row-gutter: 5pt,
      align: (right + horizon, left, left),
      ..d-period.map(((ms, ok, n)) => (
        [#text(size: 9pt, fill: ink-light)[#ms]],
        [#hbar(ok / n) #h(5pt) #text(size: 8.8pt, fill: ink-light)[#ok / #n]],
        [#text(size: 8.8pt, fill: muted)[#calc.round(ok / n * 100, digits: 2)%]],
      )).flatten(),
    )
  ],
  caption: [控制周期可调范围与节拍精度：5--1000 ms 各档位实测落在期望 tick 刻度的样本比例。每档只有切换瞬间的一个过渡样本落在 100 ms 刻度，稳态不抖动。],
)

#figure(
  align(center)[#table(
    table.hline(stroke: 1.2pt + ink),
    columns: 4,
    align: (auto,auto,auto,auto,),
    table.header([负载], [A 组：大核直控 p99 / max], [B 组：小核接管 kind=9], [说明],),
    table.hline(),
    [空载], [+0.21 ms / +0.22 ms], [236/236 落在 20 tick（min=mean=max）], [控制周期 100 ms],
    [3 × `yes` 打满 CPU], [#strong[+1.54 ms / +1.75 ms]], [227/227 落在 20 tick], [同刻 uart 往返涨到 3,670 µs],
    [视觉 validator 流水线], [+0.947 ms / +0.950 ms], [200/200 落在 20 tick], [长尾取决于负载是否"持续就绪"],
    [带载（20%，压地）], [149 拍 p99 = 100,331 µs / max = 100,333 µs], [4,802/4,802 = 100%（20 tick）], [与空载同口径复测],
    table.hline(stroke: 1.2pt + ink),
  )]
  , kind: table
  )

== 20.6 失效兜底：小核挂了谁停车

小核接管链路之后，看门狗与堵转保护都跑在它身上，于是出现一个新的失效面：#strong[小核自己挂了，这套保护就全没了]，而这时唯一还能动作的是大核。兜底因此要回答两件事：大核怎么确认小核已经死了，以及怎么在小核仍占着 UART1 的情况下把线抢回来。

判据用两条，缺一不可。其一是"小核 PC 恒为 0"（工具 `c906l_kick status` 的只读取证，退出码 3）；其二是"控制周期数在 2 秒内不再前进"（读 kind=8），后者覆盖"小核还活着但控制任务卡死"以及"读不到上报"这两种情况。演练时，活着的那一轮 A 不成立、B 计数前进 30，判定 `dead=0` 不误触发；`hold` 掉核心之后两条同时成立，判定 `dead=1`。动作序列是：先让驱动放掉小核侧对 UART1 的占用（即便小核已死、该命令必然超时，回填的 `mode=0` 仍表示大核驱动侧已释放），再把 A18/A19 的引脚复用切回大核 UART1，并补发 `INIT` 与"零速 + 停车 + 复位"序列，把车停住。裸板演练里真的把核心停掉后跑通了整条链，随后 `c906l_kick kick` 让小核重新启动、`cmdqu_test uart 1` 把链路交回，往返 390 µs。

边界必须一并说明：这是#strong[事后兜底]，动作延迟由大核调度决定，不是小核那种固定节拍；真正"毫秒级且不依赖任何软件"只能靠硬件急停，而本项目"不新增组件"的前提把它排除了。另外，抢回之后小核不能再碰 UART1，必须显式"kick + 交回"才能恢复；抢回瞬间 `uart-stats` 里残留的 `mode=3` 是小核死前的陈旧快照，不能当作"它还活着"的证据。同一轮排查中我们还定性了一个独立故障：这块板#strong[第一次上电时小核偶发不被释放]（PC 恒 0，U-Boot 阶段就已经是 0），用同一段释放序列在几秒后重放即可恢复，于是把它固化成了现场急救工具。

== 20.7 小核还能做什么，以及为什么现在没做

厂商把小核定位成"感知前端加慢速外设协处理器"：小核固件里有 `gpio`、`i2c`、`uart`、`pinmux`、`cif`、`jenc`、`sensor`、`rgn` 驱动与 `isp`、`vi`、`vcodec`、`camera`、`audio` 任务，官方 `sensor_quick_startup` 文档甚至要求在 boot 阶段由小核完成摄像头 sensor 的 I2C 初始化序列，好让大核起来的瞬间 sensor 已经稳定。换句话说，厂商原本期望它接管的是"摄像头采集加 ISP 加编码"这一整段；把小核的能力清单与本车实际硬件逐条对照，就能看清哪些能接、哪些接不了，以及各自卡在哪一步。

最典型、也是收益最大的一条是#strong[摄像头]。本车的相机是 USB（UVC，`1e45:8022`）摄像头，挂在大核的 DWC2 USB 主机上，节点为 `/dev/cvi-usb-camera0`；而小核固件里#strong[完全没有 USB 驱动]，它拿不到这台相机的控制权。厂商给小核准备的摄像头通路是另一条：MIPI CSI 加 sensor 加 ISP 加 VI，由小核的 `cif`/`sensor`/`isp` 驱动直接控制 sensor。要走这条路有两个前提，本车都不满足：其一，需要换成 CSI 接口的 sensor 模块并重新布线（当前走的是 USB 线）；其二，要把 sensor、ISP、VI 的时钟、pinmux 与缓冲所有权交给小核，还要补上厂商快速启动通路里那段"大核先分配 ION 缓冲"的握手------StarryOS 侧没有这段握手，小核的摄像头分支因此拿不到有效缓冲，也就不会去写 ION 窗口（我们实测过那块窗口是静态残留）。考虑到感知链路 89% 的时间花在解码与缩放上，这一条确实是"最值得做"的扩展，但目前卡在#strong[硬件形态不匹配]上，因此先记为不做。

不涉及换硬件的候选有三类，各自卡在不同的地方。第一类是#strong[把大核已经跑通、却仍需重复的实时工作搬过去]：机械臂 UART2 已经能由小核直发（kind=11 回报），但位置读回（`PRAD`）目前仍由大核工具做，要把它也做成小核闭环，先得定下"`/dev/ttyS2` 归谁"的交接约定------两边同时发会互相打架。第二类是#strong[新增传感器输入]：如果之后加装光电门、限位开关或 IMU，让小核做带时间戳的固定周期采样是天然合适的，但前提是先确认这些信号接在 SG2002 侧还是底盘板侧，并解决 GPIO 的 pinmux 归属；当前硬件清单里没有这些传感器，所以只能作为预留能力。第三类是#strong[需要新增触点的安全硬件]：小核的 `driver/gpio` 是现成的，做毫秒级急停只差一个外部触点（排针上 A15 是唯一纯 GPIO），但"不新增组件"是本项目的既定前提，现有堵转与碰撞的软件判据（600--800 ms 检出）先顶上。

还有几类工作被明确排除，理由不是"做不了"，而是"不划算"或"没必要"：电机 PWM 直驱在小核侧只有寄存器定义、没有现成驱动，而且会丢掉底盘板给出的 RPM 闭环；音频与 ISP 的其余功能块与拾球场景无关；WiFi 与 SD 在小核固件里没有驱动，且 SD1 焊盘与 UART3 复用冲突，接管会直接掉 WiFi；时间同步协议（`SYS_CMD_SYNC_TIME`）已经在协议里预留，但当前小核 tick 与名义值一致（5000.00 µs、0 ppm），只需按 ppm 级缓慢漂移设计，优先级排在上述功能之后。我们把"值得搬"的判断标准归纳成四条：#strong[驱动就绪]、#strong[不与大核现有链路冲突或有明确交接]、#strong[不新增硬件]、#strong[收益可量化]；四条同时满足才会排期，这也是这条工作线主动收敛边界的方式。

#fig-todo("C", [厂商预期的小核职责与本车实际可用路径], [横版对照示意图，上下两层。上层"厂商预期"：画一颗标注 C906L 的小核，右侧依次连接 MIPI CSI 摄像头 → ISP → VI → 编码 → 共享内存，标注"sensor_quick_startup：boot 阶段由小核完成 sensor I2C 初始化"，并用虚线框标出"需要大核先分配 ION 缓冲"；下层"本车实际"：画一颗大核 StarryOS，右侧连接 USB UVC 摄像头（标注 1e45:8022）→ DWC2 主机 → /dev/cvi-usb-camera0，再用一条红色虚线段表示"小核无 USB 驱动，此路不通"，并把小核画在下方、只连到底盘与机械臂 UART 以及共享内存。要求在两层差异处用同一套颜色高亮"能接"与"接不了"，图内中文标注，适合 A4 单栏宽度（约 16 cm × 9 cm）。风格：扁平矢量，深色底（\#0D1B2A）配青色 \#2DD4BF 与琥珀 \#F59E0B（与报告图表同一色板）、浅色文字，圆角方框、箭头清晰。],)

#figure(
  align(center)[#table(
    table.hline(stroke: 1.2pt + ink),
    columns: 5,
    align: (auto,auto,auto,auto,auto,),
    table.header([候选工作], [厂商预期 / 现成能力], [预期收益], [为什么没做], [启动条件],),
    table.hline(),
    [MIPI CSI 摄像头 + ISP（厂商主线）], [小核有 `cif`/`sensor`/`isp`/`vi`/`jenc` 全套驱动], [感知链 89% 时间在解码与缩放，前置到小核最值得], [本车是 USB UVC 摄像头，小核无 USB 驱动；需换 CSI 模块并补 ION 缓冲握手], [换 CSI 摄像头模块，明确 sensor/ISP 归属与 pinmux],
    [机械臂 UART2 读回闭环], [UART2 直发已通（kind=11），读回仍在大核], [抓取动作全程跑在小核节拍上], [需先约定 `/dev/ttyS2` 交接（两边同发会冲突），标定仍依赖大核工具], [明确交接协议并复测残差],
    [GPIO 急停 / 碰撞触点], [小核 `driver/gpio` 现成，A15 是唯一纯 GPIO], [毫秒级、不依赖大核], [需要外部触点，与"不新增组件"前提冲突], [允许新增微动开关或改接 DRV8833 STBY],
    [IMU / 光电门周期采样], [小核可做带时间戳的固定周期采样（归属待定）], [更稳的采样节拍与时间基准], [车上没有这些传感器，引脚归属与 pinmux 仲裁未定], [加装传感器并确认接在 SG2002 侧],
    [电机 PWM 直驱], [小核只有寄存器定义、无 PWM 驱动], [省掉一层转发], [会丢掉底盘板的 RPM 闭环，不划算], [仅当底盘板被移除时再评估],
    [音频与其余 ISP 功能块], [厂商固件有 `audio`/`isp`/`rgn` 任务], [---], [与拾球场景无关], [---],
    [WiFi / SD], [小核固件无驱动], [---], [SD1 焊盘与 UART3 复用冲突，接管会掉 WiFi], [---],
    [跨核时间同步协议], [`SYS_CMD_SYNC_TIME` 已预留], [双核时间戳可互算], [当前 tick 与名义值一致（0 ppm），优先级低], [需要跨核时间戳时再落地],
    table.hline(stroke: 1.2pt + ink),
  )]
  , kind: table
  )

== 20.8 负结果与取证纪律

报告同样记录被否定的设想与踩过的坑，因为它们决定了方案的边界。

第一，#strong[不要把推理或图像预处理搬到小核]。感知链路的瓶颈在 CPU 侧软件 JPEG 解码，不在 NPU，更不在小核：同一张 1279×1706 的图上，软件解码中位数约 829 ms、resize 约 76 ms、TPU 前向仅 #strong[41.4 ms]、编码约 710 ms，预处理占总时间的 89%，TPU 只占 7.7%。小核没有 TPU 访问也没有对应驱动，正确的做法是用大核上的 JPU/vdec 硬解通路解决解码瓶颈。

第二，#strong[不建议做 noMMU 版 StarryOS]。去掉 MMU 等于放弃 StarryOS 的 Linux ABI 价值（fork/COW、按需分页、`mprotect`、PIE/ASLR、用户指针校验），成本是月级而收益为负；小核真正需要的只是几百 KB 的实时固件。

第三，一条与"系统能力"直接相关的#strong[硬解缺陷]：走内核 JPU 的采帧路径（cmd4）会在连续解码若干秒后把 JPU 永久锁死，现场是 `[JPU] Timeout! status=0x4`（既非 DONE 也非 ERROR），之后每次返回 EIO 直到重启；四轮里首次超时前成功 39\~388 帧，而同一轮的原始 MJPEG 路径毫发无伤。把同一条解码路径换成卡上文件的离线重放（完全不经过 USB）后，仍然在第 3 次解码时以同一句报错锁死------所以"USB 抢总线"可以划掉，问题在 JPU 的状态机。这条负结果同时说明了为什么长稳数据要按"先硬解、后软解"的顺序采，以及为什么视觉流水线必须把"JPU 锁死"当成一种可观测的失效模式、一旦 EIO 就转软件解码或重启。

第四，一条取证纪律：StarryOS 的写只进页缓存、没有周期性回写，#strong[板端写出的文件必须先 `sync` 才算存下来]。受控实验里，不 `sync` 就硬复位，卡上留下的文件"长度正确、内容全零"（哈希与同长度全零数据完全一致），带回宿主侧的文件其实是空壳；而 `sync` 是一张"到此为止"的快照，它只保住自己之前写入的内容，所以脚本里的 `sync` 必须放在最后一次写入之后。

== 20.9 方法：让这些数字可信

上面的每组数字都按同一套方法取得，这套方法本身也是这条工作线的产出之一。判据必须#strong[机器可判定]：每个实验写成"一次运行给出一个布尔量与一个数值"，不用肉眼看日志；口径必须显式声明"包含什么、不包含什么"（例如控制周期延迟是否含串口发送时间、是否含底盘板执行时间）；所有板级数字#strong[三次重复取中位数]，基线版本冻结并记录；每一条滞后于现实的结论都要能追溯到当次运行的原始日志。判据与门禁也写进流程：如果测出 ESP32 底盘板自身已有链路超时，就优先改底盘板而不是动小核；如果命令路径 p99 远小于机构容差，那"确定性"就不成立为优化理由，叙事要改成"OS 无关与链路所有权"。

一个具体的例子可以说明这套方法值在哪里。早期测量给出"小核 tick 比标称慢 2.19%"，看起来像时钟配置错误。我们先引入#strong[独立于两个核的第三方参考]------用 PC 墙钟给板端串口逐行打时间戳，9 分钟、19 个样本测得宿主与 PC 相差 +55.6 ± 12.3 ppm，排除宿主；再改用直方图而不是平均值观察间隔，发现绝大多数的相邻间隔恰好是一个 tick，只有极少数是多个 tick，而"每 tick 偏慢"不可能产生这种形状；最后定位到真正的缺陷：共享头部的一条 cache line 被小核整行回写覆盖，大核按被污染的 tail 记账。把头部按写入方拆成三条 cache line、`SHM_VERSION` 从 2 升到 3 之后，复测得到每 tick 5000.00 µs、24,160/24,160 个间隔都正好一个 tick、两分钟零推迟。#strong[结论从"时钟慢 2%"改判为"度量假象"]，而这一次更正顺带修掉了跨核共享内存的一条硬规则。

== 20.10 边界与可复用产物

这条工作线到此封盘，能力与边界都已经有实板证据。已验收的能力包括：跨核驱动（`/dev/cvi-rtos-cmdqu`、指定应答等待、poll/epoll、共享缓冲 mmap）、小核接管底盘链路（握手、命令自检、周期控制、心跳看门狗、堵转保护）、大小核节拍 A/B 对照、控制周期可调到 5 ms、小核失控后的判定与接管、以及冷启动"小核没被释放"的现场急救。仍未完成或尚未验证的有：5 ms 控制周期下 200 帧/秒的链路负载需要带车验证；"抢回后底盘确实收到 STOP"需要带车验证；小核外设归属与 pinmux 仲裁、C906L 是否带 MMU，受限于 TRM 未给出小核章节，仍属未决问题。

可复用的产物除驱动与固件外，还包括一套板端与宿主侧工具（跨核自检、排线协议探针、采帧与 JPEG 解码分段计时、冷启动统计、上卡与刷写脚本）以及几条可以约束后续工作的硬规则：跨核共享内存必须显式非缓存映射；共享结构的每条 cache line 只能有一个写入方；任何布局改动必须递增版本并两侧同时重建；板端产出的证据文件必须先 `sync`。这些规则与工具都已用实板数据检验过，可以直接用于后续的异构协同工作。
