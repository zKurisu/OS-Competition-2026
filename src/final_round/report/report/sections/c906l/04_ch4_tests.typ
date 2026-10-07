// 本文件由实时小核章节草稿（c906l-report-section.typ）拆分而来，
// 承载实验测试章中的"小核链路的测试说明与结果"。
#import "../_prelude.typ": *

== 小核链路的测试说明与方法

这一条工作线的每组数字都按同一套方法取得，这套方法本身就是它的产出之一，因为它决定了
"哪些结论可以被承诺"。

第一，*判据必须机器可判定*。每个实验都写成"一次运行给出一个布尔量与一个数值"，不用
肉眼看日志判断成败：链路握手看"拔线冻结、插回恢复"，协议自检看"步数与异常计数"，
看门狗看"停喂心跳后停车计数是否递增"，堵转保护看"双轮按住是否触发一次并锁存"。

第二，*口径必须显式声明"包含什么、不包含什么"*。例如控制周期延迟要写明是否含串口发送
时间、是否含底盘板的执行时间；启动与登录的时间要写明锚点是"内核就绪""首个用户态输出"
还是"可交互"。凡两侧口径不能对齐的指标一律拆开报，不把差异记到被测对象头上。

第三，*所有板级数字三次重复取中位数，基线版本冻结并记录*。每一条滞后于现实的结论都要
能追溯到当次运行的原始日志；一旦发现结论与日志不符，以日志为准并更正结论。

判据与门禁也写进流程：如果测出底盘板自身已有链路超时，就优先改底盘板而不是动小核；
如果命令路径的 p99 远小于机构容差，那么"确定性"就不成立为优化理由，叙事要改成
"系统无关与链路所有权"。这套门禁在本文档里也确实改变过一次结论——见"实现难点"一章
关于"度量假象"的记述。

== 小核链路的测试结果

=== 跨核往返延迟与稳定性

#tablefigure(
  booktable(
    (26%, 30%, 44%),
    ([观测], [实测值], [含义]),
    (
      ([往返延迟（发送 + 等待指定应答）], [274 / 277 / 299 µs], [旧轮询实现下界 1000 µs]),
      ([往返延迟分布], [min 53 / p50 54 / p90 266 / max 413 µs], [双峰：未入睡命中 / 中断唤醒]),
      ([稳定性], [`tx=rx=irq=12 dropped=0`（连续 5 次）], [无丢包、无落空]),
      ([共享区版本], [`version=3 header=192`，Ring A/B 偏移 320 / 4416], [与驱动常量逐项对应]),
      ([小核 tick], [5000.00 µs（−0 ppm），24 307/24 307 个间隔为 1 tick], [两核时间基准一致，无需比例补偿]),
    ),
  ),
  caption: [跨核通道的实测。往返延迟的双峰形状说明"未入睡即命中"与"经中断唤醒"是两条不同的路径，p50 比旧轮询实现的下界低一个数量级],
)

=== 底盘链路接管的验收结果

#tablefigure(
  booktable(
    (14%, 22%, 38%, 26%),
    ([阶段], [命令 / 模式], [实测结果], [判据]),
    (
      ([链路握手], [`0x61`，mode=1，kind=6], [INIT 4→6、ACK 4→6、24→36 字节、帧错误 0；拔线冻结、插回恢复], [小核独立完成收发]),
      ([协议自检], [`0x61` + mode=2，kind=7], [5/5 步、异常 0、ACK 10、60 字节、帧错误 0], [全程零速度指令]),
      ([周期控制], [`0x62`，mode=3，kind=8], [默认 100 ms；每 5 拍回读 RPM；`dt_max = 周期/5`], [闭环与大核负载解耦]),
      ([心跳看门狗], [`0x64` 设窗口（默认 500 ms）], [停喂心跳后 `wd_stops` 逐次 +1，窗口内停车], [大核失效后能停]),
      ([堵转保护], [kind=10], [双轮按住触发 1 次并锁存；单轮差速不触发；改目标解除], [不新增硬件即能"卡住就停"]),
    ),
  ),
  caption: [底盘链路接管的三阶段与两层保护的验收结果。每一行的判据都是布尔量，可以脚本复核],
)

=== 控制周期的确定性：大核直控与小核接管的 A/B 对照

要证明小核的价值，唯一有说服力的形式是*同机、同负载、同链路的对照*。A 组由大核用户态
按固定周期写 `/dev/ttyS1`，用工具测量每一拍的实际间隔；B 组由小核按 tick 计数下发，
kind=9 给出"恰好一个周期 / 多一个 tick / 多两个 tick"的分布。两组负载相同：空载、
3 个 `yes` 打满大核 CPU，以及卡上真实的感知流水线（`akars-tennis-validator`，它不占用
`/dev/ttyS1`，所以两组合并跑）。

#tablefigure(
  booktable(
    (20%, 30%, 28%, 22%),
    ([负载], [A 组：大核直控 p99 / max], [B 组：小核接管 kind=9], [说明]),
    (
      ([空载], [+0.21 ms / +0.22 ms], [236/236 落在 20 tick（min=mean=max）], [控制周期 100 ms]),
      ([3 × `yes` 打满 CPU], [*+1.54 ms / +1.75 ms*], [227/227 落在 20 tick], [同刻 uart 往返涨到 3 670 µs]),
      ([视觉 validator 流水线], [+0.947 ms / +0.950 ms], [200/200 落在 20 tick], [长尾取决于负载是否"持续就绪"]),
      ([带载（20%，压地）], [149 拍 p99 = 100 331 µs / max = 100 333 µs], [4 802/4 802 = 100%（20 tick）], [与空载同口径复测]),
    ),
  ),
  caption: [A/B 对照。大核直控的控制周期偏差随负载恶化到约 8 倍，小核接管在全部负载下 min = mean = max，样本 100% 落在期望 tick 刻度；带载一行为 20% 占空比、车压地工况],
)

#let c906l-lat = (min: 53, p50: 54, p90: 266, max: 413, poll: 1000)   // µs
#let c906l-ab = (                                                      // ms，相对 100 ms 周期
  ("空载", 0.211, 0.215),
  ("3 × yes 打满 CPU", 1.536, 1.750),
  ("视觉 validator", 0.947, 0.950),
  ("带载 20%（压地）", 0.331, 0.333),
)
#let c906l-period = (("5 ms", 2994, 2995), ("10 ms", 1456, 1457), ("20 ms", 664, 665), ("50 ms", 237, 237), ("100 ms", 79, 79))
#let c906l-navy = rgb("#0D1B2A")
#let c906l-teal = rgb("#2DD4BF")
#let c906l-amber = rgb("#F59E0B")
#let c906l-ink-light = rgb("#EEF3F8")
#let c906l-muted = rgb("#8AA0B4")
#let c906l-track = rgb("#22303F")
#let c906l-hbar(frac, fill: c906l-teal, h: 8pt, w: 4.4cm) = box(
  width: w, height: h, fill: c906l-track, radius: 2pt, clip: true,
)[#place(rect(width: w * calc.max(frac, 0.004), height: h, radius: 2pt, fill: fill))]

#figure(
  block(width: 88%, fill: c906l-navy, inset: (x: 14pt, y: 12pt), radius: 4pt)[
    #set par(first-line-indent: 0pt, leading: 0.7em, spacing: 0.4em)
    #text(font: sans, size: 9.5pt, fill: c906l-ink-light)[跨核往返延迟（中断驱动，单位 µs）]
    #v(6pt)
    #grid(
      columns: (2.6cm, 1fr),
      row-gutter: 5pt,
      align: (right + horizon, left),
      [#text(size: 9pt, fill: c906l-ink-light)[min]], [#c906l-hbar(c906l-lat.min / 1100) #h(5pt) #text(size: 9pt, fill: c906l-ink-light)[#c906l-lat.min]],
      [#text(size: 9pt, fill: c906l-ink-light)[p50]], [#c906l-hbar(c906l-lat.p50 / 1100) #h(5pt) #text(size: 9pt, fill: c906l-ink-light)[#c906l-lat.p50]],
      [#text(size: 9pt, fill: c906l-ink-light)[p90]], [#c906l-hbar(c906l-lat.p90 / 1100) #h(5pt) #text(size: 9pt, fill: c906l-ink-light)[#c906l-lat.p90]],
      [#text(size: 9pt, fill: c906l-ink-light)[max]], [#c906l-hbar(c906l-lat.max / 1100) #h(5pt) #text(size: 9pt, fill: c906l-ink-light)[#c906l-lat.max]],
      [#text(size: 9pt, fill: c906l-amber)[旧轮询下界]], [#c906l-hbar(c906l-lat.poll / 1100, fill: c906l-amber) #h(5pt) #text(size: 9pt, fill: c906l-amber)[#c906l-lat.poll]],
    )
  ],
  caption: [跨核往返延迟分布（中断驱动）与旧轮询实现的下界。所有条形按同一尺度绘制；中断驱动的 p50 比轮询下界低一个数量级],
)

#figure(
  block(width: 88%, fill: c906l-navy, inset: (x: 14pt, y: 12pt), radius: 4pt)[
    #set par(first-line-indent: 0pt, leading: 0.7em, spacing: 0.5em)
    #text(font: sans, size: 9.5pt, fill: c906l-ink-light)[控制周期偏差（相对 100 ms，单位 ms）]
    #v(6pt)
    #grid(
      columns: (3.8cm, 1fr, 2.6cm),
      row-gutter: 7pt,
      align: (right + horizon, left, left),
      ..c906l-ab.map(((label, p99, mx)) => (
        [#text(size: 9pt, fill: c906l-ink-light)[#label]],
        [#stack(dir: ttb, spacing: 2pt,
          [#c906l-hbar(p99 / 2) #h(5pt) #text(size: 8.8pt, fill: c906l-ink-light)[p99 +#p99]],
          [#c906l-hbar(mx / 2, fill: c906l-amber) #h(5pt) #text(size: 8.8pt, fill: c906l-ink-light)[max +#mx]],
        )],
        [#text(size: 8.6pt, fill: c906l-muted)[B 组 0 抖动]],
      )).flatten(),
    )
  ],
  caption: [A/B 对照：大核直控（A 组）相对 100 ms 控制周期的 p99 与 max 偏差；小核接管（B 组）在全部负载下 min = mean = max],
)

第三轮把负载换成真实感知流水线后出现了一个反直觉但重要的结果：A 组的 p99 偏差只有
0.947 ms、max 为 0.950 ms，*比 3 个 `yes` 反而更小*。原因不难解释：`yes` 是"永远
就绪"的纯计算竞争者，会把用户态控制进程从时间片上挤开；视觉流水线在文件读与 TPU ioctl
上会阻塞，反而给调度器留下了放行窗口。也就是说，*大核直控的长尾取决于负载是否持续
就绪，而不在于它"像不像视觉"*。小核一侧则与负载无关：200/200 仍全部落在 20 tick。
带载（车压地、20% 占空比）复测同样成立。

=== 控制周期档位与代价

控制的稳定性建立在"小核节拍不受大核负载影响"上，因此周期本身可以压得很短。把控制周期
从 100 ms 一路压到 5 ms，各档位的节拍精度如下：每档只有切换瞬间的一个过渡样本落在
100 ms 刻度，稳态不抖动。

#figure(
  block(width: 88%, fill: c906l-navy, inset: (x: 14pt, y: 12pt), radius: 4pt)[
    #set par(first-line-indent: 0pt, leading: 0.7em, spacing: 0.4em)
    #text(font: sans, size: 9.5pt, fill: c906l-ink-light)[控制周期档位与落在期望刻度的样本占比]
    #v(6pt)
    #grid(
      columns: (2.6cm, 1fr, 2.6cm),
      row-gutter: 5pt,
      align: (right + horizon, left, left),
      ..c906l-period.map(((ms, ok, n)) => (
        [#text(size: 9pt, fill: c906l-ink-light)[#ms]],
        [#c906l-hbar(ok / n) #h(5pt) #text(size: 8.8pt, fill: c906l-ink-light)[#ok / #n]],
        [#text(size: 8.8pt, fill: c906l-muted)[#calc.round(ok / n * 100, digits: 2)%]],
      )).flatten(),
    )
  ],
  caption: [控制周期可调范围与节拍精度：5–1000 ms 各档位实测落在期望 tick 刻度的样本比例],
)

代价只有一条：目标速度从"大核写入"到"线上生效"要等一个控制周期（100 ms 周期下平均
50 ms、最坏 100 ms）。把控制周期压到 5 ms（1 个 tick）后，这一项降到*平均 2.5 ms、
最坏 5 ms*，裸板实测 2 994/2 995 个样本落在 1 tick 刻度；代价是链路上 `SET_SPEED`
帧涨到 200 帧/秒，底盘板能不能吃下这个速率仍需带车验证。
