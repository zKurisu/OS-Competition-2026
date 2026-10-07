#!/usr/bin/env bash
# ============================================================
#  发布脚本：先跑 build.sh，再把三份对外文档同步到仓库的 docs/
#
#    out/项目说明书.pdf              → docs/项目说明书.pdf
#    out/项目创新说明.pdf            → docs/项目创新说明.pdf
#    out/成员分工及主要贡献说明.pdf   → docs/成员分工及主要贡献说明.pdf
#
#  docs/ 的位置不用数 ".."：脚本按下面顺序自动定位
#    1) 环境变量 DOCS_DIR（显式指定，最优先）
#    2) 如果本仓库在 git 工作区内，取 git 仓库根下的 docs/
#    3) 否则从本脚本所在目录逐级向上找最近的 docs/
#  在提交仓库里 2) 与 3) 都会定位到
#  /home/jie/Do/1_2026开源操作系统大赛/0_competition_repo/docs
#  （注意：从 report/ 数上去是三级 ".."，不是四级）
#
#  另外：out/第二部分-追球推理链路.pdf 是草稿预览，不参与发布。
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
PUBLISH=(项目说明书.pdf 项目创新说明.pdf 成员分工及主要贡献说明.pdf)

resolve_docs() {
  if [ -n "${DOCS_DIR:-}" ]; then
    [ -d "$DOCS_DIR" ] && { printf '%s\n' "$DOCS_DIR"; return 0; }
    echo "DOCS_DIR 指向的目录不存在：$DOCS_DIR" >&2
    return 1
  fi
  local top
  if top="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" && [ -d "$top/docs" ]; then
    printf '%s\n' "$top/docs"
    return 0
  fi
  local dir="$HERE"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/docs" ]; then
      printf '%s\n' "$dir/docs"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if ! DOCS="$(resolve_docs)"; then
  echo "找不到 docs/ 目录。可以用 DOCS_DIR=/path/to/docs $0 显式指定。" >&2
  exit 1
fi

echo "[1/2] 编译"
"$HERE/build.sh"

echo "[2/2] 同步到 $DOCS"
for name in "${PUBLISH[@]}"; do
  src="$OUT/$name"
  if [ ! -f "$src" ]; then
    echo "  缺少 $src（build.sh 没生成？）" >&2
    exit 1
  fi
  if [ ! -s "$src" ]; then
    echo "  $src 是空文件，先看 build.sh 的输出" >&2
    exit 1
  fi
  cp -f "$src" "$DOCS/$name"
  printf '  %-28s → %s\n' "$name" "$(du -h "$DOCS/$name" | cut -f1)"
done

echo "完成。$DOCS 现在有："
ls -1 "$DOCS"
