// ============================================================
//  正文小工具（对应参考报告 preamble.tex 里的几个宏）
//
//    abl 标记         未测 / 待补的数字（amber 深色版；lint.sh 统计数量）
//    todo 框          本节的写作要求 / 待填内容（脚手架提示框；定稿前删掉）
//    #figph(name, caption: [...])   图占位：图不存在时渲染"图待生成"方框
//    #booktable(...)  三线表（booktabs 风格）
//    #ours[...] / #ctr[...] / #keyres[...]   贡献归属与关键结果标记
//    #n3(x) / #ratio(a, b)                    千分位与比例
// ============================================================
#import "theme.typ": sans, mono, mark, muted, rule, ink, dim, palette-amber

// —— 未测标记 ——
#let abl(body) = text(fill: mark, weight: "bold")[#body]

// —— 贡献归属（对齐 LaTeX 的 \ours/\keyres = \textbf{...}，不染色）——
#let ours(body) = text(weight: "bold")[#body]
#let ctr(body) = text(fill: dim)[#body]
#let keyres(body) = text(weight: "bold")[#body]

// —— 写作要求（脚手架；定稿前应当删净）——
#let todo(body) = block(
  width: 100%, inset: (x: 10pt, y: 7pt), radius: 3pt,
  fill: rgb("#faf7f0"), stroke: (left: 3pt + palette-amber, rest: 0.4pt + rgb("#e6dcc4")),
  above: 0.8em, below: 0.9em,
)[
  #set par(first-line-indent: 0pt, justify: false, leading: 0.72em)
  #text(font: sans, size: 8.6pt, weight: "bold", tracking: 0.1em, fill: mark)[待写]
  #h(0.6em)
  #text(size: 9.5pt, body)
]

// —— 三线表：只画顶线、表头线、底线（booktabs）——
// header 与 rows 都可以写成"按行嵌套"的数组，宏内部摊平后按行主序填格：
//   #booktable((13%, 17%, 33%, 37%), ([A], [B], [C], [D]), (([a1], [b1], [c1], [d1]), ...))
#let booktable(columns, header, rows, align: left) = table(
  columns: columns,
  align: align,
  table.hline(stroke: 1.1pt + ink),
  ..header.flatten(),
  table.hline(stroke: 0.5pt + rule),
  ..rows.flatten(),
  table.hline(stroke: 1.1pt + ink),
)

// —— 带编号的表格：kind 为 table 的 figure → "表 N"，题注排在表下方 ——
// 用法：#tablefigure(booktable(...), caption: [表题])
#let tablefigure(body, caption: none) = figure(body, kind: table, caption: caption)

// —— 图占位 ——
// name：图号（如 "F25_boot_to_ssh_before_after"），取 light 版（白底，适合打印）。
// 图由 workspace/sg2002-eval/figures/render_sg2002.py 生成（lib.typ 在 report/ 下，
// 所以是 ../../sg2002-eval/...）。编译时用 --root .. 才能读到 report/ 之外，
// 并由 build.sh 通过 --input figures=... 传入"实际已生成的图"清单
// （这个 Typst 版本没有 try 表达式，所以不做文件探测）。
#let _have-figures = sys.inputs.at("figures", default: "")

#let figph(name, caption: none, width: 72%) = {
  let path = "../../sg2002-eval/figures/out/" + name + "_light.png"
  let exists = name in _have-figures.split(",")
  figure(
    if exists {
      image(path, width: width)
    } else {
      // 对齐 preamble.tex 的 \figph：\fbox 框、3cm 高、0.72\linewidth 宽，
      // 中间用 muted 色写 [图待生成: 路径]
      block(
        width: width, height: 3cm,
        stroke: 0.4pt + ink,
        align(center + horizon)[
          #text(font: mono, size: 9pt, fill: muted)[[图待生成: #path]]
        ],
      )
    },
    caption: caption,
  )
}

// —— 数字格式 ——
#let n3(x) = {
  let s = str(calc.round(x, digits: 0))
  let (sign, digits) = if s.starts-with("-") { ("-", s.slice(1)) } else { ("", s) }
  let out = ""
  let n = digits.len()
  for (i, c) in digits.clusters().enumerate() {
    if i > 0 and calc.rem(n - i, 3) == 0 { out += "," }
    out += c
  }
  sign + out
}

#let ratio(a, b) = calc.round(a / b, digits: 2)

// —— 参考文献条目（著者-出版年制）——
// 正文引用写成 `（著者 年份）`；条目按此格式排：
//   著者. 标题. 出处/URL.[访问日期]
#let refitem(body) = block(
  width: 100%, above: 0.35em, below: 0.35em,
)[
  #set par(first-line-indent: 0pt, justify: false, leading: 0.72em)
  #text(size: 9.5pt, body)
]
