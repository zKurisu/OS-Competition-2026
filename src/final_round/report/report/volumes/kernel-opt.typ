// ============================================================
//  内核优化分册 · 独立编译入口
//
//  编译（在 src/final_round/report/ 下执行）：
//    typst compile --root . report/volumes/kernel-opt.typ "out/内核优化分册.pdf"
//
//  正文片段在 ../sections/kernel_opt/ 下，就是**主报告正文**里内核部分的同一份源文件：
//    02_ch2_route.typ          技术理论章 · 内核优化路线与机制族清单
//    02_ch2_originality.typ    技术理论章 · 代码原创说明
//    03_ch3_project.typ        项目介绍章 · 内核优化的工程实现
//    04_ch4_tests.typ          实验测试章 · 测试说明与测试结果
//    05_ch5_difficulties.typ   实现难点章 · 定位方法、负结果与未完成项
//    06_ch6_summary.typ        总结章 · 内核优化总结
//  主报告由 main.typ 逐章 include 它们；本文件只是给出一册
//  只讲内核层的独立排版（额外加了五个一级标题，主报告里没有）。
//
//  ../sections/kernel_opt/ 下另外两个文件不是正文：
//    numbers.typ   内核部分的数字宏（k- 前缀；正文只引用宏名，不写字面数字）
//    _lib.typ      出图宏 kfig()（图在 figures/ 下）
// ============================================================
#import "../theme.typ": *
#import "../sections/_prelude.typ": *
#import "../../data/meta.typ": *
#import "../sections/kernel_opt/_lib.typ": *
#import "../sections/kernel_opt/numbers.typ": *

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
  kind: [项目说明书 · 内核优化分册],
  work: work-title,
  team: team-name,
  date: finish-date,
)

#toc-page(depth: 3)

#counter(page).update(1)

= 内核优化路线

#include "../sections/kernel_opt/02_ch2_route.typ"

= 代码原创说明 <sec:originality>

#include "../sections/kernel_opt/02_ch2_originality.typ"

= 内核优化的工程实现

#include "../sections/kernel_opt/03_ch3_project.typ"

= 内核优化的测试

#include "../sections/kernel_opt/04_ch4_tests.typ"

= 内核优化的难点与未完成项

#include "../sections/kernel_opt/05_ch5_difficulties.typ"

= 内核优化总结

#include "../sections/kernel_opt/06_ch6_summary.typ"
