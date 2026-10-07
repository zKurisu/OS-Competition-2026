// ============================================================
//  内核优化分册的小工具
//
//  图的路径是相对**本文件**解析的（Typst 的规则：路径相对出现该路径的文件），
//  所以放在 kernel_opt/ 下，正文里只写名字。
//  不用 lib.typ 的 #figph()——那个宏指向主报告的 ../../sg2002-eval/figures/out。
// ============================================================
#let kfig(name, caption: none, width: 86%) = figure(
  image("figures/" + name + ".png", width: width),
  caption: caption,
)
