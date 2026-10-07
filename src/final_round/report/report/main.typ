// ============================================================
//  SG2002 项目说明书 · 编译入口
//
//  编译：./build.sh
//    （等价于 typst compile --root .. --input figures=... report/main.typ ../sg2002-report.pdf
//       --root .. 是为了让正文能读到 report/ 之外的图）
//
//  结构（按大赛《项目说明书》要求，至少包含这些章节）：
//    第 1 章 绪论            1.1 目的与意义 / 1.2 项目背景
//    第 2 章 技术理论        2.1 设计思想 / 2.2 技术路线 / 2.3 代码原创说明
//    第 3 章 项目介绍        3.1 功能介绍 / 3.2 软件界面（可选）
//    第 4 章 实验测试        4.1 测试说明 / 4.2 测试结果
//    第 5 章 实现难点说明      （可选章节）
//    第 6 章 总结
//    参 考                   按引用顺序，著者-出版年制
// ============================================================
#import "theme.typ": *
#import "lib.typ": *
#import "../data/numbers.typ": *
#import "../data/meta.typ": *

#show: report
#set heading(numbering: heading-numbering)
#set figure(supplement: [图], numbering: "1")
// 表格单独编号（kind: table 的 figure 记作"表 N"，正文用 #tablefigure(...) 包一层）
#show figure.where(kind: table): set figure(supplement: [表], numbering: "1")
#set page(
  paper: "a4",
  margin: 2.4cm,
  // 参考报告是 \pagestyle{headings}：页眉左"当前章标题"、右页码，正文无页脚
  // （大赛 Word 模板是页脚居中页码，要用它就把下面两行换成 header: none + footer: plain-footer）
  header: running-header,
  header-ascent: 0.85cm,
  footer: none,
)

// —— 封面（无页码）——
#cover(
  competition: competition-name,
  kind: doc-kind,
  work: work-title,
  team: team-name,
  date: finish-date,
)

// —— 目录（最多三级标题，无页码）——
#toc-page(depth: 3)

// 正文从第 1 页开始编号
#counter(page).update(1)

#include "sections/01_ch1_intro.typ"
#include "sections/02_ch2_tech.typ"
#include "sections/03_ch3_project.typ"
#include "sections/04_ch4_tests.typ"
#include "sections/05_ch5_difficulties.typ"
#include "sections/06_ch6_summary.typ"
#include "sections/07_references.typ"
