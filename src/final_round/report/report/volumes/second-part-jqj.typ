// ============================================================
//  第二部分（视觉推理与运动控制链路）· 独立交付稿的薄装配入口
//
//  编译（在 src/final_round/report/ 下执行）：
//    typst compile --root . report/volumes/second-part-jqj.typ "out/第二部分-追球推理链路.pdf"
//
//  正文片段在 ../sections/jqj/ 下，与主报告第 2–6 章**共用同一份源文件**：
//    jqj/02_ch2_tech.typ         技术理论章 · 视觉推理与运动控制链路
//    jqj/03_ch3_project.typ      项目介绍章 · 推理链路与机器人用户态的工程实现
//    jqj/04_ch4_tests.typ        实验测试章 · 与 Linux 的视觉性能对比
//    jqj/05_ch5_difficulties.typ 实现难点章 · 视觉链路难点与技术路线取舍
//    jqj/06_ch6_summary.typ      总结章 · 视觉链路阶段总结
//  本文件只提供封面、目录与五个一级标题，正文一律 include，不再保留第二份副本。
// ============================================================
#import "../theme.typ": *
#import "../lib.typ": *
#import "../../data/meta.typ": *

#show: report
#set heading(numbering: heading-numbering)
#set figure(supplement: [图], numbering: "1")
#show figure.where(kind: table): set figure(supplement: [表], numbering: "1")
#set page(
  paper: "a4",
  margin: 2.4cm,
  header: running-header,
  header-ascent: 0.85cm,
  footer: none,
)

#cover(
  competition: competition-name,
  kind: [项目说明书 · 第二部分 追球推理链路],
  work: work-title,
  team: team-name,
  date: finish-date,
)

#toc-page(depth: 3)

#counter(page).update(1)

= 视觉推理与运动控制链路

#include "../sections/jqj/02_ch2_tech.typ"

= 推理链路与机器人用户态的工程实现

#include "../sections/jqj/03_ch3_project.typ"

= 与厂商 Linux 的视觉性能对比

#include "../sections/jqj/04_ch4_tests.typ"

= 视觉链路的实现难点与技术路线取舍

#include "../sections/jqj/05_ch5_difficulties.typ"

= 视觉链路优化总结

#include "../sections/jqj/06_ch6_summary.typ"
