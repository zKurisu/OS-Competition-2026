#!/bin/bash
# pack_fit.sh <name> —— 把已构建好的 starryos.bin 打包成 FIT（starry-<name>.sd）。
#
# U-Boot 通过 fatload + bootm 加载的就是这个 FIT。产物默认落在 /tmp/pack_<name>/，
# 不写任何仓库目录。
#
# 用法：
#   ./pack_fit.sh opt78
#   ./pack_fit.sh perf1 --kernel /path/to/starryos.bin --out /tmp/mypack
#   TGOSKITS_ROOT=/path/to/tgoskits TARGET_TRIPLE=riscv64gc-unknown-linux-musl ./pack_fit.sh port23
#
# 参数：
#   --kernel PATH   内核 elf/bin（默认 $TGOSKITS_ROOT/target/$TARGET_TRIPLE/release/starryos.bin）
#   --triple TRIPLE 目标三元组（默认 riscv64gc-unknown-none-elf）
#   --root DIR      tgoskits 源码根（默认 $TGOSKITS_ROOT）
#   --its DIR       含 boot.its + fdt.dtb 的目录（默认自动在常见位置里找）
#   --out DIR       产物目录（默认 /tmp/pack_<name>）
set -euo pipefail

usage() {
    sed -n '2,20p' "$0"
    exit 1
}

NAME=""
KERNEL=""
TRIPLE="${TARGET_TRIPLE:-riscv64gc-unknown-none-elf}"
TG="${TGOSKITS_ROOT:-}"
ITS_DIR=""
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
    --kernel) KERNEL="$2"; shift 2 ;;
    --triple) TRIPLE="$2"; shift 2 ;;
    --root) TG="$2"; shift 2 ;;
    --its) ITS_DIR="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h | --help) usage ;;
    -*) echo "未知参数：$1" >&2; usage ;;
    *) NAME="$1"; shift ;;
    esac
done
[ -n "$NAME" ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-/tmp/pack_$NAME}"
IMG="starry-$NAME.sd"

if [ -z "$KERNEL" ]; then
    [ -n "$TG" ] || { echo "未指定 --kernel，也没有 TGOSKITS_ROOT" >&2; exit 1; }
    KERNEL="$TG/target/$TRIPLE/release/starryos.bin"
fi
[ -f "$KERNEL" ] || { echo "找不到内核产物：$KERNEL（先构建？）" >&2; exit 1; }

if [ -z "$ITS_DIR" ]; then
    for cand in "${SG2002_BOOT_DIR:-}" "$SCRIPT_DIR/../../../../1_genimage" \
        "$PWD" "$PWD/.." "$PWD/../.." "$SCRIPT_DIR/../assets"; do
        [ -n "$cand" ] || continue
        if [ -f "$cand/boot.its" ] && [ -f "$cand/fdt.dtb" ]; then
            ITS_DIR="$cand"
            break
        fi
    done
fi
[ -n "$ITS_DIR" ] || {
    echo "找不到含 boot.its + fdt.dtb 的目录，请用 --its 指定" >&2
    exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$KERNEL" "$OUT/kernel"
cp "$ITS_DIR/boot.its" "$ITS_DIR/fdt.dtb" "$OUT/"
(cd "$OUT" && mkimage -f boot.its "$IMG" >/dev/null)
echo "[pack] kernel=$KERNEL"
echo "[pack] its=$ITS_DIR"
ls -l "$OUT/$IMG"
