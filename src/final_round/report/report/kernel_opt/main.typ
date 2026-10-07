// ============================================================
//  SG2002 内核优化分册 · 编译入口
//
//  编译：
//    typst compile --root . report/kernel_opt/main.typ out/内核优化分册.pdf
//    （在 src/final_round/report/ 下执行；--root . 是为了让正文能读到
//      本目录以外的 ../data/meta.typ）
//
//  这是一份**可以单独交付**的分册：版式复用 report/theme.typ（与主报告同一套），
//  但内容只讲 kernel 层（系统调用、调度/进程、缺页、读路径、存储、启动）。
//  后续并入主报告时，把 sections/ 下的各章挪进 report/report/sections/ 即可，
//  章内不需要改写（章号由 Typst 自动编号）。
//
//  章目：
//    第 1 章 优化总览与评测口径
//    第 2 章 系统调用入口与返回路径
//    第 3 章 进程创建、exec 与上下文切换
//    第 4 章 缺页与地址空间
//    第 5 章 文件读路径
//    第 6 章 存储写回与元数据
//    第 7 章 启动时间
//    第 8 章 负结果与未完成项
//    第 9 章 复现与验收
// ============================================================
#import "../theme.typ": *
#import "../lib.typ": *
#import "../../data/meta.typ": *
#import "numbers.typ": *

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

// 每一章另起一页
#cover(
  competition: competition-name,
  kind: [项目说明书 · 内核优化分册],
  work: work-title,
  team: team-name,
  date: finish-date,
)

#toc-page(depth: 3)

#counter(page).update(1)

#include "sections/00_intro.typ"
#include "sections/01_syscall.typ"
#include "sections/02_sched.typ"
#include "sections/03_memory.typ"
#include "sections/04_readpath.typ"
#include "sections/05_storage.typ"
#include "sections/06_boot.typ"
#include "sections/07_negative.typ"
#include "sections/08_repro.typ"
