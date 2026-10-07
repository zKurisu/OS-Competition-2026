#!/usr/bin/env bash
# ============================================================
#  提交前检查（照参考报告 lint.sh 的思路）
#   1) 禁用串：裸 IP、sudo、交接文档泄漏、含糊数值
#   2) 配色同步：theme.typ 与评测出图脚本的官方 hex 必须一致
#   3) 统计正文里还剩多少 #abl[...] 未测标记
#   4) 编译冒烟：typst compile 必须过
# ============================================================
set -u
fail=0
red() { echo "LINT FAIL: $1"; fail=1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
FIGSTYLE="$ROOT/sg2002-eval/figures/render_sg2002.py"
# 调色板的真正定义处：出图脚本从决赛报告的 style/ 里 import（多行 Path(...) 写法）
STYLE_PY="$(grep -A2 '^STYLE_DIR = Path(' "$FIGSTYLE" 2>/dev/null \
  | sed -n 's/^ *"\(.*\)".*/\1/p' | head -1)/style.py"
[ -f "$STYLE_PY" ] || STYLE_PY="/home/jie/Do/1_2026开源操作系统大赛/project3136859-388489/docs/final-round/style/style.py"

# 1) 禁用串（正文与数据表）
#    四条工作线均已并入 report/sections/ 并由 main.typ 逐章 include，
#    正文只有一份来源，因此检查覆盖 report/ 全量，不再豁免任何草稿文件。
if grep -rInE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "$HERE/report" "$HERE/data" 2>/dev/null; then
  red "正文里出现裸 IP（应写成 板子/宿主 或占位名）"
fi
if grep -rInE 'sudo |AGENT_HANDOFF|交接文档' "$HERE/report" "$HERE/data" 2>/dev/null; then
  red "出现内部串（sudo / 交接文档）"
fi
if grep -rInE '不是[^。]{1,40}而是|并非[^。]{1,40}而是|与其[^。]{1,40}不如' "$HERE/report" 2>/dev/null; then
  red "not-A-but-B 对比句式（改为直接陈述）"
fi
if grep -rInE '约[0-9]|大概[0-9]' "$HERE/report" "$HERE/data" 2>/dev/null; then
  red "含糊数值（要么给确切数字，要么用 #abl[...] 标出）"
fi

# 2) 配色同步（官方三色）
for hx in 0D1B2A 2DD4BF F59E0B; do
  if ! grep -qi "$hx" "$HERE/report/theme.typ"; then
    red "theme.typ 缺少官方配色 $hx"
  fi
  if [ -f "$STYLE_PY" ] && ! grep -qi "$hx" "$STYLE_PY"; then
    red "出图调色板 $STYLE_PY 缺少 $hx（两边要同步）"
  fi
done

# 3) 待写 / 未测标记统计
n=$(grep -rho '#abl\[' "$HERE/report" 2>/dev/null | wc -l | tr -d ' ')
echo "INFO: 正文还有 $n 处 #abl[...] 未测标记"
t=$(grep -rho '#todo\[' "$HERE/report" 2>/dev/null | wc -l | tr -d ' ')
echo "INFO: 正文还有 $t 处 #todo[...] 待写提示（定稿前应删净）"

# 4) 编译冒烟
if command -v typst >/dev/null; then
  FIGDIR="$ROOT/sg2002-eval/figures/out"
  FIGS="$(ls "$FIGDIR" 2>/dev/null | sed -n 's/_light\.png$//p' | paste -sd, - || true)"
  if typst compile --root "$ROOT" --input "figures=$FIGS" \
       "$HERE/report/main.typ" /tmp/sg2002-report-lint.pdf >/dev/null 2>&1; then
    echo "INFO: typst 编译通过"
  else
    red "typst 编译失败（跑 ./build.sh 看详细报错）"
  fi
else
  echo "INFO: 未安装 typst，跳过编译冒烟"
fi

[ "$fail" -eq 0 ] && echo "LINT OK" || exit 1
