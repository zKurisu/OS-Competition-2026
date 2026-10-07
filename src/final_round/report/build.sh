#!/usr/bin/env bash
# ============================================================
#  一键编译：把对外文档统一渲染到 out/
#
#    report/main.typ             → out/项目说明书.pdf
#    statements/innovation.typ   → out/项目创新说明.pdf
#    statements/division.typ     → out/成员分工及主要贡献说明.pdf
#    report/jqj.typ              → out/第二部分-追球推理链路.pdf   （草稿预览，并入正文后可删）
#
#  说明：
#    * --root 指到仓库的上一级：正文里的图在仓库外的 ../sg2002-eval/figures/out/，
#      用默认 root（report/）读不到。把"实际已生成的图"清单通过 --input figures= 传进去，
#      没有的图会渲染成"图待生成"占位框，不会让编译失败。
#    * 源文件不存在就跳过（例如还没写的 innovation/division），不影响其他文档的编译。
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"      # 仓库根（build.sh 所在目录）
ROOT="$(dirname "$HERE")"                  # 上一级：让 ../sg2002-eval/... 落在 root 内
OUT="$HERE/out"

command -v typst >/dev/null || { echo "缺少 typst（需要 0.13 以上）"; exit 1; }

# 把"实际已生成的图"清单传给正文：没有的图渲染成"图待生成"占位，不会让编译失败。
FIGDIR="$ROOT/sg2002-eval/figures/out"
FIGS="$(ls "$FIGDIR" 2>/dev/null | sed -n 's/_light\.png$//p' | paste -sd, - || true)"

mkdir -p "$OUT"

# 源文件（相对仓库根）| 输出文件名
TARGETS=(
  "report/main.typ|项目说明书.pdf"
  "statements/innovation.typ|项目创新说明.pdf"
  "statements/division.typ|成员分工及主要贡献说明.pdf"
  # 视觉链路的独立稿：源文件已移入 sections/jqj/（与主报告正文同一份内容）
  "report/sections/jqj/jqj.typ|第二部分-追球推理链路.pdf"
  # 内核优化分册：内容已并入主报告正文的技术理论/项目介绍/实验测试/实现难点/总结五章；
  # 这里仍单独排一册，便于评审只看内核部分。它不用 --input figures=，
  # 编译时也不需要 sg2002-eval/ 下的图。
  "report/sections/kernel_opt/main.typ|内核优化分册.pdf"
)

built=0
for target in "${TARGETS[@]}"; do
  src="${target%%|*}"
  name="${target##*|}"
  if [ ! -f "$HERE/$src" ]; then
    echo "[跳过] 找不到 $src，未生成 $name"
    continue
  fi
  echo "[编译] $src  →  out/$name"
  typst compile --root "$ROOT" --input "figures=$FIGS" "$HERE/$src" "$OUT/$name"
  built=$((built + 1))
done

if [ "$built" -eq 0 ]; then
  echo "没有任何可编译的源文件"
  exit 1
fi

echo "[完成] $built 份 PDF 已输出到 $OUT"
ls -1 "$OUT"
