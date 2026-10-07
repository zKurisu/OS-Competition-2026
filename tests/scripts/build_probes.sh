#!/bin/bash
# build_probes.sh —— 交叉编译 tests/probes 下的全部 C 探针为 riscv64 静态二进制。
#
# 为什么必须静态：板子上的 StarryOS / 厂商 Linux 都不保证有动态链接器与 libc 版本，
# 探针一律 `-static` 编译成独立的 musl 可执行文件。
#
# 用法：
#   ./build_probes.sh                 # 产物落到 tests/build/probes/
#   OUT=/tmp/probes ./build_probes.sh # 指定产物目录
#   CC=/path/to/riscv64-unknown-linux-musl-gcc ./build_probes.sh
#
# 产物目录里同时会生成 `probe_manifest.txt`，记录每个二进制的来源与大小，
# 便于上板前核对。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${OUT:-$ROOT/build/probes}"

pick_cc() {
    if [ -n "${CC:-}" ]; then
        echo "$CC"
        return
    fi
    if [ -n "${SG2002_MUSL_GCC:-}" ] && [ -x "$SG2002_MUSL_GCC" ]; then
        echo "$SG2002_MUSL_GCC"
        return
    fi
    # LicheeRV-Nano-Build 自带的 Xuantie musl 工具链（板 Linux 与 StarryOS 通用）。
    local bundled
    for bundled in \
        "$ROOT/../../opensource/LicheeRV-Nano-Build/host-tools/gcc/riscv64-linux-musl-x86_64/bin/riscv64-unknown-linux-musl-gcc" \
        "$HOME/Do/1_2026开源操作系统大赛/opensource/LicheeRV-Nano-Build/host-tools/gcc/riscv64-linux-musl-x86_64/bin/riscv64-unknown-linux-musl-gcc"; do
        if [ -x "$bundled" ]; then
            echo "$bundled"
            return
        fi
    done
    for cand in riscv64-unknown-linux-musl-gcc riscv64-linux-musl-gcc; do
        if command -v "$cand" >/dev/null 2>&1; then
            echo "$cand"
            return
        fi
    done
    echo ""
}

CC_RV="$(pick_cc)"
[ -n "$CC_RV" ] || { echo "找不到 riscv64 交叉编译器，请设 CC=..." >&2; exit 1; }

CFLAGS=(-O2 -static -pthread -march=rv64gc -mabi=lp64d -Wall)

mkdir -p "$OUT"
MANIFEST="$OUT/probe_manifest.txt"
: >"$MANIFEST"
echo "# toolchain: $CC_RV" >>"$MANIFEST"
echo "# built: $(date -Iseconds)" >>"$MANIFEST"

fail=0
count=0
build_one() {
    local src="$1" name rel
    name="$(basename "$src" .c)"
    rel="${src#"$ROOT"/}"
    if "$CC_RV" "${CFLAGS[@]}" -I "$ROOT/board/harness" -o "$OUT/$name" "$src" 2>"$OUT/$name.build.log"; then
        rm -f "$OUT/$name.build.log"
        printf '%-14s %-40s %s B\n' "$name" "$rel" "$(stat -c %s "$OUT/$name")" | tee -a "$MANIFEST"
        count=$((count + 1))
    else
        echo "!! 编译失败：$rel（见 $OUT/$name.build.log）" >&2
        fail=$((fail + 1))
    fi
}

while IFS= read -r src; do
    build_one "$src"
done < <(find "$ROOT/probes" "$ROOT/board/harness" -name '*.c' | sort)

echo "[build] $count 个探针 -> $OUT（失败 $fail）"
[ "$fail" = 0 ] || exit 1
