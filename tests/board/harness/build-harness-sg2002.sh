#!/usr/bin/env bash
# Cross-compile the RK3588-report probes for SG2002 (riscv64 musl, static) so the
# SAME binary runs under the board Linux and under StarryOS.
#
# Unlike build-harness.sh this needs no Docker/binfmt: it uses the Xuantie musl
# toolchain already shipped in the SG2002 SDK tree, and falls back to the system
# riscv64 gcc for a host-side smoke build.
#
# Usage:
#   apps/starry/sysbench-board/harness/build-harness-sg2002.sh
#
# Env overrides:
#   SG2002_MUSL_GCC  path to riscv64-unknown-linux-musl-gcc
#   SG2002_MARCH     default "rv64gc" (baseline C906; also runs under qemu-riscv64)
#   SG2002_OUT       output dir, default <harness>/sg2002-out
set -euo pipefail

harness_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$(cd "$harness_dir/.." && pwd)"
repo_root="$(cd "$app_dir/../../.." && pwd)"

# Probe sources: harness/ holds the timing/memory instruments, the app root holds
# the syscall/page-fault correctness probes from the RK3588 report.
harness_sources=(cpuprobe membw)
app_sources=(syscost ppong thp_bw thp_protnone thp_reenable thp_nohugepage
             thp_narrow mem_bw2 rusage_acct tickacct_desched)

resolve_toolchain() {
    if [[ -n "${SG2002_MUSL_GCC:-}" ]]; then
        printf '%s\n' "$SG2002_MUSL_GCC"
        return
    fi
    # 先找 SDK 自带的 Xuantie musl 工具链（在若干常见相对位置），再退回系统 gcc。
    # 本 harness 被搬进 OS-Competition-2026/tests 后相对路径会变，所以直接给候选列表，
    # 并允许用 SG2002_MUSL_GCC 显式指定。
    local cand
    for cand in \
        "$repo_root/../opensource/LicheeRV-Nano-Build/host-tools/gcc/riscv64-linux-musl-x86_64/bin/riscv64-unknown-linux-musl-gcc" \
        "$repo_root/../../opensource/LicheeRV-Nano-Build/host-tools/gcc/riscv64-linux-musl-x86_64/bin/riscv64-unknown-linux-musl-gcc" \
        "$HOME/Do/1_2026开源操作系统大赛/opensource/LicheeRV-Nano-Build/host-tools/gcc/riscv64-linux-musl-x86_64/bin/riscv64-unknown-linux-musl-gcc"; do
        if [[ -x "$cand" ]]; then
            printf '%s\n' "$cand"
            return
        fi
    done
    command -v riscv64-unknown-linux-musl-gcc || command -v riscv64-linux-musl-gcc || command -v riscv64-linux-gnu-gcc
}

cc="$(resolve_toolchain)"
out="${SG2002_OUT:-$harness_dir/sg2002-out}"
march="${SG2002_MARCH:-rv64gc}"

mkdir -p "$out"

build_one() {
    local name="$1" source="$2"
    "$cc" -O2 -static -pthread "-march=$march" -mabi=lp64d \
        -o "$out/$name" "$source"
    printf '  %-20s <- %s\n' "$name" "${source#"$repo_root/"}"
}

# 这些探针原本在 app 根目录（sysbench-board/），搬进 tests/board/harness 后
# 与 harness 同目录，所以先看 app_dir 再看 harness_dir。
src_of() {
    local name="$1"
    if [[ -f "$app_dir/$name.c" ]]; then
        printf '%s\n' "$app_dir/$name.c"
    else
        printf '%s\n' "$harness_dir/$name.c"
    fi
}

echo "== SG2002 probes =="
echo "toolchain: $cc"
echo "output:    $out"
for name in "${harness_sources[@]}"; do
    build_one "$name" "$harness_dir/$name.c"
done
for name in "${app_sources[@]}"; do
    build_one "$name" "$(src_of "$name")"
done

echo "== done =="
file "$out/cpuprobe" "$out/syscost"
echo
echo "Host smoke test (needs qemu-riscv64):"
echo "  qemu-riscv64 $out/syscost 20000"
