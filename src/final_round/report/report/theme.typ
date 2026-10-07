// ============================================================
//  SG2002 项目说明书 · Typst 版式
//
//  版式逐项对齐参考报告 project3136859-388489/docs/final-round/report 的 LaTeX：
//  \documentclass[11pt,a4paper]{ctexart} + preamble.tex + ctex-scheme-chinese-article
//
//    * 页面    \usepackage[margin=2.4cm]{geometry}
//    * 字体    \setCJKmainfont{Songti SC} / \setCJKsansfont{Heiti SC}（style/tokens.tex）
//    * 标题    ctex 的 format=\bfseries 作用在 CJK 主字体上 ⇒ 宋体加粗（不是黑体）：
//                \part / \section   = \Large\bfseries\centering（14.4pt 居中）
//                \subsection        = \large\bfseries（12pt 左对齐）
//                \subsubsection     = \normalsize\bfseries（11pt 左对齐）
//                \paragraph         = \normalsize\bfseries（11pt，LaTeX 里是 run-in）
//              编号与标题之间是 aftername=\quad（1em）；标题后首段照常缩进（afterindent）
//    * 正文    \linespread 1.3 的行距 + parskip 的段间距 + autoindent 首行缩进两字
//    * 题注    \captionsetup{font=small,labelfont=bf} ⇒ 10pt，只有"图 1: / 表 1:"加粗
//    * 表格    booktabs 三线表；表体 \small（10pt），表头与表体同字重（不加粗）
//    * 等宽    \texttt（CM Typewriter）⇒ Nimbus Mono PS；行内不加底色
//    * 页眉    \pagestyle{headings} ⇒ 左"当前章标题"、右页码；正文页无页脚
//    * 链接    \usepackage[hidelinks]{hyperref} ⇒ 链接不染色
//    * 宏      \abl{} → #abl[]（amber）；\ours{}/\keyres{} → 纯加粗；\figph{} → #figph(...)
//
//  两处有意偏离，因为本文要交的是大赛《项目说明书》：
//    * 封面照大赛 Word 模板，不用参考报告那套深色封面
//    * 目录标题保留"目 录"居中（Word 模板如此）
//
//  用法：main.typ 里 `#import "theme.typ": *` 然后 `#show: report`
//  注意：所有 set / show 规则必须写在 report() 内部，写成子函数作用不到正文。
//
//  配色与出图脚本同源（style/style.py + style/tokens.tex）：
//    navy #0D1B2A / teal #2DD4BF / amber #F59E0B / muted #8AA0B4
// ============================================================

// —— 官方配色（与 style.py / tokens.tex 同步；改这里要同时改那两处）——
#let palette-navy = rgb("#0D1B2A")
#let palette-teal = rgb("#2DD4BF")
#let palette-amber = rgb("#F59E0B")
#let palette-muted = rgb("#8AA0B4")   // tokens.tex 的 muted：图占位提示等次要标注

// —— 文档用色 ——
#let accent = palette-navy          // 保留：图表/强调用
#let mark = palette-amber           // 未测标记（对齐 tokens.tex 的 \abl = {\color{amber}}）
#let ink = rgb("#1a2230")           // 正文
#let dim = rgb("#5d6b78")           // 次要文字
#let rule = rgb("#c9d2da")          // 表格线
#let note-bg = rgb("#faf7f0")       // 提示框底
#let muted = palette-muted          // 图占位提示文字

// —— 字体（与 tokens.tex 的 fontspec 设置同名；缺失时回退到思源/Noto）——
#let serif = ("Songti SC", "Source Han Serif", "Noto Serif CJK SC", "Noto Serif")
#let sans = ("Heiti SC", "Source Han Sans", "Noto Sans CJK SC", "Noto Sans")
// \texttt 在参考报告里是 Computer Modern Typewriter；本机最接近的是 Nimbus Mono PS（Courier 系）
#let mono = ("Nimbus Mono PS", "Noto Sans Mono CJK SC", "DejaVu Sans Mono")
// 标题用 \bfseries 作用于 CJK 主字体，即宋体加粗
#let heading-font = serif

// ────────────────────────────────────────────────────────────
//  章 / 节编号：一级 "第 N 章"，二三级 "1.1" / "1.1.1"
//  （在 main.typ 里 `#set heading(numbering: heading-numbering)` 启用）
// ────────────────────────────────────────────────────────────
#let heading-numbering = (..nums) => {
  let a = nums.pos()
  if a.len() == 1 { "第 " + str(a.at(0)) + " 章" } else { a.map(str).join(".") }
}

// ctex 的 aftername=\quad：编号与标题正文之间固定留 1em
#let _heading-body(it) = context {
  if it.numbering == none { it.body }
  else { counter(heading).display(it.numbering) + h(1em) + it.body }
}

// ────────────────────────────────────────────────────────────
//  正文排版规则
// ────────────────────────────────────────────────────────────
#let report(it, chapter-break: true) = {
  set text(font: serif, size: 11pt, fill: ink, lang: "zh", region: "cn")
  // ctex 的 autoindent：正文首行缩进两字符，两端对齐。
  // leading / spacing 按参考 PDF 实测反解：行距 1.6 倍、段间距约 0.54cm。
  set par(
    justify: true, leading: 0.87em, spacing: 1.4em,
    first-line-indent: (amount: 2em, all: false),
  )
  // hyperref 用 hidelinks：链接与正文同色

  // 列表、表格单元、提示框不缩进首行
  show list: set par(first-line-indent: 0pt)
  show enum: set par(first-line-indent: 0pt)
  // 表格单元：不缩进首行，也不两端对齐（参考报告的 p{} 列都带 \raggedright）
  show table.cell: set par(first-line-indent: 0pt, justify: false)
  show quote.where(block: true): set par(first-line-indent: 0pt)

  // —— 标题 ——
  // 一级（章）：宋体加粗、居中，对应 \part / \section 的 \Large\bfseries\centering。
  // chapter-break 为真时每章另起一页；pagebreak(weak: true) 已在页首时不再插空页，
  // 所以目录后的第 1 章不会多出白纸。短文档（如项目创新说明）可以
  // `#show: report.with(chapter-break: false)` 让一级标题连续排下去，避免留白。
  show heading.where(level: 1): it => {
    if chapter-break { pagebreak(weak: true) }
    block(
      above: 27pt, below: 20pt, width: 100%,
      align(center, text(font: heading-font, size: 14.4pt, weight: "bold", fill: ink)[#_heading-body(it)]),
    )
  }
  // 二级（1.1）：\subsection = \large\bfseries，左对齐；beforeskip 3.25ex / afterskip 1.5ex
  show heading.where(level: 2): it => block(
    above: 26pt, below: 16pt,
    text(font: heading-font, size: 12pt, weight: "bold", fill: ink)[#_heading-body(it)],
  )
  // 三级（1.1.1）：\subsubsection = \normalsize\bfseries，左对齐
  show heading.where(level: 3): it => block(
    above: 22pt, below: 14pt,
    text(font: heading-font, size: 11pt, weight: "bold", fill: ink)[#_heading-body(it)],
  )
  // 四级（段落级小标题）：对应 \paragraph{}。LaTeX 里它是 run-in（标题与正文同行），
  // Typst 的 heading 是块级、做不到真正的 run-in，这里退化为"独占一行的小字标题"。
  show heading.where(level: 4): it => block(
    above: 15pt, below: 9pt,
    text(font: heading-font, size: 11pt, weight: "bold", fill: ink)[#_heading-body(it)],
  )

  // —— 表格：三线表（只画顶/表头/底三条线，无竖线，无斑马纹）——
  show table: set table(stroke: none, inset: (x: 6pt, y: 4.5pt))
  show table: set text(size: 10pt)
  // 参考报告的 booktabs 表头与表体同字重，故不设 bold

  // —— 图/表题注：small（10pt）、只有标签加粗（captionsetup{font=small,labelfont=bf}）——
  show figure.caption: it => align(center, text(size: 10pt, {
    let lbl = if it.supplement != none and it.numbering != none {
      strong[#it.supplement #it.counter.display(it.numbering):]
    } else { none }
    if lbl == none { it.body } else { lbl + [ ] + it.body }
  }))
  // 浮动到页顶：图/表放不下时随文本一起流动到下一页页首，避免整块被推走后留下大片空白
  show figure: set block(above: 0.8em, below: 1.0em)
  show figure: set figure(placement: top)

  // —— 等宽：行内沿用 \texttt 的做法（只换字族、不加底色）；块级仍用浅底便于阅读 ——
  // —— 交叉引用：@标签 渲染为"图 N / 表 N / N.N 节"，而不是标签名（对齐参考报告的 \ref）——
  show ref: it => {
    let el = it.element
    if el == none { return it }
    if el.func() == figure {
      let kind = if el.kind == table { [表 ] } else { [图 ] }
      let num = numbering(el.numbering, ..counter(if el.kind == table {
        figure.where(kind: table)
      } else { figure }).at(el.location()))
      kind + num
    } else if el.func() == heading {
      if el.numbering == none { el.body } else {
        let num = numbering(el.numbering, ..counter(heading).at(el.location()))
        // 一级标题（章）自带"第 N 章"形式，不再追加"节"
        if el.level == 1 { num } else { num + [ 节] }
      }
    } else { it }
  }

  show raw.where(block: false): it => text(font: mono, size: 0.95em, it)
  // breakable: true —— 长代码块允许跨页续排，避免整块被推到下一页而留下大片空白
  show raw.where(block: true): it => block(
    width: 100%, inset: (x: 9pt, y: 7pt), radius: 3pt, breakable: true,
    fill: rgb("#f7f9fb"), stroke: 0.5pt + rule,
    text(font: mono, size: 8.6pt, it),
  )

  // —— 目录：对应 tocloft 的 \cftsecfont = \bfseries、\cftsubsecfont = 常规；
  //    引导点也只从 \subsection 这一级起才出现（section 级是"标题 …… 页码"直接留白）——
  //    本报告比参考报告多一级（章 → 节 → 小节），映射为：
  //      章（level 1）   = 参考报告的 \section  → 加粗、无引导点
  //      节（level 2/3） = 参考报告的 \subsection / \subsubsection → 常规字重、有引导点
  show outline.entry: set outline.entry(fill: repeat([#text(fill: rule)[.]], gap: 0.3em))
  show outline.entry.where(level: 1): set text(font: serif, size: 11pt, weight: "bold")
  show outline.entry.where(level: 1): set outline.entry(fill: none)
  show outline.entry.where(level: 2): set text(font: serif, size: 11pt)
  show outline.entry.where(level: 3): set text(font: serif, size: 11pt)

  it
}

// ────────────────────────────────────────────────────────────
//  页眉 / 页脚
//
//  参考报告用的 \pagestyle{headings}：左侧是当前一级标题（章），右侧是页码；
//  正文页没有页脚。封面与目录页自己在 page() 里关掉页眉页脚。
// ────────────────────────────────────────────────────────────
#let running-header = context {
  set text(font: serif, size: 10pt, fill: ink)
  // 取"当前页或之前最近的一个一级标题"：章首那一页也要显示本章标题，
  // 所以不能只查 here() 之前的标题（页眉的 here() 在本页正文之前）。
  let pg = here().page()
  let cur = query(heading.where(level: 1))
    .filter(h => h.location().page() <= pg)
    .last()
  if cur == none {
    align(right)[#counter(page).display("1")]
  } else {
    let num = if cur.numbering == none { none } else {
      numbering(cur.numbering, ..counter(heading).at(cur.location()))
    }
    grid(
      columns: (1fr, auto),
      align: (left, right),
      [#if num != none {num; h(1em)}#cur.body],
      [#counter(page).display("1")],
    )
  }
}

// 备用：大赛 Word 模板是"页脚居中页码、无页眉"。要用它就把 main.typ 的
// header/footer 换成 header: none, footer: plain-footer。
#let plain-footer = context {
  set text(font: serif, size: 10pt, fill: ink)
  align(center)[#counter(page).display("1")]
}

// ────────────────────────────────────────────────────────────
//  封面：对齐大赛《项目说明书》Word 模板
//
//         中国研究生操作系统开源创新大赛      ← 24pt 加粗楷体、居中
//
//                   项目说明书                ← 同为 24pt，与上一行同体例
//
//
//         作 品 名 称： │＿＿作品名＿＿＿＿＿＿
//         参 赛 队 伍： │＿＿队伍名＿＿＿＿＿＿
//         完 成 日 期： │＿＿2026年X月＿＿＿＿＿
//
//  模板原稿的几何（Word twips，1cm ≈ 567tw）：
//    * 页边距 top 1701tw = 3.0cm / 左右 1418tw = 2.5cm；信息表整体居中
//    * 信息表原稿 2439 + 3949tw = 11.27cm（标签列 4.30cm + 填写列 6.97cm）。
//      填写列太短：16pt 加粗的「面向智能机器人的AIOS」实测宽 6.09cm，再减去 1.11cm
//      缩进就放不下、会折行，故加宽到 9.00cm（整表 13.30cm，居中后仍在 A4 正文宽内）。
//    * 三行行距 0.68cm；填写值左缩进 628tw = 1.11cm，下划线通栏（原稿 0.5pt，此处 0.6pt）
//    * 标题 48 半点 = 24pt（原稿楷体，缺字族时回退宋体族）；信息 32 半点 = 16pt 宋体
//  另：原稿封面页末尾的红色「阅读后删除」提示不属于正式封面，此处不复制。
// ────────────────────────────────────────────────────────────
// 原稿两行标题用楷体；本机字体库里没有楷体族，故默认走宋体族（同为衬线、同为粗体，
// 版式一致）。若构建环境装了楷体，把它换成 ("KaiTi", "STKaiti", "Kaiti SC") + serif 即可。
#let cover-title-font = serif

// 一行「标签 + 带下划线的填写值」：行高与 Word 表格行一致（0.68cm，单行时），
// 底线通栏。作品名可能长到换行（Word 里单元格会自然变高），所以这里不写死行高，
// 而是让行高跟着内容走：标签撑起 0.68cm 的下限，值换行时整行一起变高、底线仍在最下面。
#let _cover-row(label, value) = (
  block(height: 0.68cm, align(left + bottom, text(font: serif, size: 16pt, weight: "bold", fill: ink)[#label])),
  align(bottom, block(
    width: 100%,
    stroke: (bottom: 0.6pt + ink),
    inset: (left: 1.11cm, right: 0pt, bottom: 2.2pt),
    {
      // 封面里的行距按单倍走，否则 16pt 的行高会把字段撑得比 0.68cm 高很多
      set par(leading: 0.08em, spacing: 0.08em)
      align(left + bottom, text(font: serif, size: 16pt, weight: "bold", fill: ink)[#value])
    },
  )),
)

#let _cover-info(rows) = grid(
  // 标签列沿用模板的 4.30cm；填写列由模板的 6.97cm 加宽到 9.00cm（见文件头注释）
  columns: (4.30cm, 9.00cm),
  column-gutter: 0pt, row-gutter: 0pt,
  ..rows.map(((label, value)) => _cover-row(label, value)).flatten(),
)

#let cover(
  competition: "中国研究生操作系统开源创新大赛",
  kind: "项目说明书",
  work: "作品名",
  team: "队伍名",
  date: "2026年X月",
) = page(
  header: none, footer: none, numbering: none,
  // 与模板一致：上边距 3.0cm、左右 2.5cm（Word 1418tw = 2.5cm）。
  margin: (x: 2.5cm, top: 3cm, bottom: 2.5cm),
)[
  #set par(first-line-indent: 0pt, justify: false)
  #set text(fill: ink)
  #v(2.5cm)
  #align(center, text(font: cover-title-font, size: 24pt, weight: "bold")[#competition])
  #v(1.55cm)
  #align(center, text(font: cover-title-font, size: 24pt, weight: "bold")[#kind])
  // 标题占上三分之一、信息表落在下三分之一：留白按模板实测比例 1 : 0.38 分配。
  #v(1fr)
  #align(center, block(width: 13.30cm)[
    #_cover-info((
      ("作 品 名 称：", work),
      ("参 赛 队 伍：", team),
      ("完 成 日 期：", date),
    ))
  ])
  #v(0.38fr)
]

// ────────────────────────────────────────────────────────────
//  目录页（"目 录" + 最多三级）
// ────────────────────────────────────────────────────────────
#let toc-page(depth: 3) = page(
  header: none, footer: none, numbering: none,
  margin: (x: 2.4cm, top: 2.6cm, bottom: 2.4cm),
)[
  #set par(first-line-indent: 0pt)
  #align(center)[
    // 参考报告的目录标题是宋体、常规字重（不加粗）；这里只保留大赛 Word 模板的"居中 + 目 录"写法
    #text(font: serif, size: 17pt, tracking: 0.3em)[目 录]
  ]
  #v(18pt)
  #outline(title: none, depth: depth, indent: 1.4em)
]
