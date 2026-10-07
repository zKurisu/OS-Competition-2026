# SG2002 项目说明书（Typst 工程）

本目录是 **SG2002 / AKA-00（LicheeRV Nano，riscv64 C906）** 这一轮评测工作的**报告装配层**：
按大赛《项目说明书》的章节要求，把已完成的测量、修复与优化组织成一份可编译的正式报告。

排版：**Typst 0.13+**（本机 0.15.1）。版式**逐项对齐参考报告**
`project3136859-388489/docs/final-round/report` 的 LaTeX
（`\documentclass[11pt,a4paper]{ctexart}` + `preamble.tex` + `style/tokens.tex`），
不是调研册那套书页风格。对齐的参数、以及为什么是这些参数，都写在 `report/theme.typ` 的头部注释里。

| 项 | 参考报告（LaTeX） | 本工程（Typst） |
| --- | --- | --- |
| 页面 | `geometry, margin=2.4cm` | `page(margin: 2.4cm)` |
| 字体 | `\setCJKmainfont{Songti SC}`、`\setCJKsansfont{Heiti SC}` | 同名字族，缺失时回退思源/Noto |
| 标题 | ctex 的 `\part`/`\section` = `\Large\bfseries\centering`，`\subsection` = `\large\bfseries`，`\subsubsection` = `\normalsize\bfseries`；编号后是 `\quad` | 14.4pt 居中 / 12pt / 11pt **宋体加粗**（不是黑体），编号后留 1em |
| 正文 | `\linespread 1.3` + `parskip` + `autoindent` 两字 | `leading: 0.87em, spacing: 1.4em, first-line-indent: 2em` |
| 题注 | `captionsetup{font=small,labelfont=bf}` | 10pt，只有「图 1: / 表 1:」加粗 |
| 表格 | booktabs 三线表，表体 `\small`，列用 `\raggedright` 的 `p{}` | `#booktable(...)`；单元不两端对齐、表头不加粗 |
| 等宽 | `\texttt`（CM Typewriter） | Nimbus Mono PS（Courier 系），行内**不加底色** |
| 目录 | tocloft：section 级 `\bfseries`、subsection 级常规；引导点只从 subsection 级起出现 | 章=加粗且**无引导点**；节/小节=常规字重、带点线引导 |
| 页眉 | `\pagestyle{headings}`：左「当前章标题」、右页码 | `running-header`，正文页无页脚 |
| 链接 | `hyperref[hidelinks]` | 链接不染色 |
| 宏 | `\abl`（amber）、`\ours`/`\keyres` = `\textbf` | `#abl`（amber）、`#ours`/`#keyres` 纯加粗 |

两处**有意不跟**参考报告，因为要交大赛《项目说明书》：封面照大赛 Word 模板（不是那套深色封面）；
目录标题保留「目 录」居中。页眉/页脚另有一个一行开关：把 `main.typ` 的 `header`/`footer` 换成
`header: none, footer: plain-footer` 就回到大赛 Word 模板的「页脚居中页码」。

## 章节结构（按大赛要求，"至少包含"）

| 章 | 节 | 落点 |
| --- | --- | --- |
| 第 1 章 绪论 | 1.1 目的与意义、1.2 项目背景 | 应用方向、同类软件优缺点、作品新颖之处 |
| 第 2 章 技术理论 | 2.1 设计思想、2.2 技术路线、2.3 代码原创说明 | 方法、路线、三方引用与代码来源声明 |
| 第 3 章 项目介绍 | 3.1 功能介绍（3.1.1–3.1.3）、3.2 软件界面（可选） | 模块划分：评测框架 / 缺陷修复 / 独立优化 |
| 第 4 章 实验测试 | 4.1 测试说明、4.2 测试结果（4.2.1–4.2.7） | 七组实测数据与图，全部引用 `data/numbers.typ` |
| 第 5 章 实现难点说明 | 5.1–5.3 | 三处缺陷的「难点 → 定位 → 修法 → 验收」 |
| 第 6 章 总结 | 6.1 完成度、6.2 展望、6.3 鸣谢 | 含开源软件与作者鸣谢 |
| 参 考 | —— | 按引用顺序，**著者-出版年制** |

封面按大赛《项目说明书》Word 模板复刻：两行等大标题（竞赛名称 / 「项目说明书」，24pt 加粗）+
居中信息表（作品名称 / 参赛队伍 / 完成日期，标签列 4.30cm、填写列带通栏下划线 6.97cm）。
几何值取自模板 docx，改动见 `report/theme.typ` 的 `cover()`；封面内容仍只在 `data/meta.typ` 维护。
目录最多三级标题。正文每个一级标题（第 1–6 章、参 考）自动另起一页——这是 `theme.typ` 里
一级标题 show 规则中的 `pagebreak(weak: true)`，已在页首时不插空页，所以目录后的第 1 章不会多出白纸。

## 编译与检查

```bash
./build.sh      # → out/ 下的所有对外文档（见下）
./lint.sh       # 提交前跑一遍
./publish.sh    # = build.sh + 把三份对外文档同步到仓库根下的 docs/（草稿不参与发布）
```

`./build.sh` 把每份对外文档分别渲染到 `out/`，源文件不存在就跳过、不影响其他文档：

| 源文件 | 产物 |
| --- | --- |
| `report/main.typ` | `out/项目说明书.pdf` |
| `statements/innovation.typ` | `out/项目创新说明.pdf` |
| `statements/division.typ` | `out/成员分工及主要贡献说明.pdf` |
| `report/jqj.typ` | `out/第二部分-追球推理链路.pdf`（草稿预览，正文并入主报告后可以删） |

三个说明类文档（创新说明、分工说明）各自复用 `report/theme.typ`，只把封面上
「项目说明书」那一行换成自己的名字，正文各自从空开始写。

`./publish.sh` 里**不写死 `../` 的层数**，而是按这个顺序定位 `docs/`：
① 环境变量 `DOCS_DIR`；② 本仓库所在 git 工作区的根目录下的 `docs/`；
③ 从脚本目录逐级向上找最近的 `docs/`。在提交仓库（`0_competition_repo`）里，
②③ 都会落到 `0_competition_repo/docs`——从 `src/final_round/report` 数上去是
**三级** `..`，不是四级。

## 写作纪律

1. **正文不写数字**：一律引用 `data/numbers.typ` 的宏（如 `n-getpid-ours`）。
2. **待写内容显式标出**：用 `#todo[...]`（脚手架提示框，定稿前删净）；未测数字用 `#abl[...]`。
   `lint.sh` 会分别统计两者的剩余数量。
3. **图不手工放**：由 `../sg2002-eval/figures/render_sg2002.py` 生成，正文用 `#figph(name, caption: [...])` 引用；
   没生成的图渲染成"图待生成"占位，不会让编译失败。
4. **表格用三线表**：`#booktable((13%, 17%, 33%, 37%), ([表头 A], [表头 B], ...), (([a1], [b1], ...), ([a2], [b2], ...)))`
   —— 前三个参数按位置传（`columns` / `header` / `rows`），`header` 与 `rows` 都可以按行嵌套，宏内部摊平。
   需要带「表 N」编号与题注时套一层 `#tablefigure(booktable(...), caption: [...])`；
   表格与图片各自独立编号（`main.typ` 里用 `show figure.where(kind: table)` 把表定为「表 N」）。
5. **引用用著者-出版年制**：正文写 `（著者 年份）`，条目用 `#refitem[...]` 排在「参 考」。

## 大文件拆分与接入约定

固定一级章节仍由 `report/sections/01_ch1_intro.typ` 至 `06_ch6_summary.typ` 维护。篇幅较大的成员材料
不直接扩充这些入口文件，而是在 `report/sections/<材料代号>/` 下按目标一级章节拆分；子文件沿用
`02_ch2_tech.typ`、`03_ch3_project.typ`、`04_ch4_tests.typ`、`05_ch5_difficulties.typ`、
`06_ch6_summary.typ` 的命名，并由对应一级章节使用 `#include` 接入。这样可以保留固定的大章结构，
同时让后续材料以并列小节继续补充。`jqj.typ` 是首个按此规则拆分的文件，其内容位于
`report/sections/jqj/`。
