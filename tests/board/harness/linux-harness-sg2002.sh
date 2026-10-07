#!/usr/bin/env bash
# SG2002-side Linux baseline. Run ON the board Linux (vendor
# Linux 5.10.4, riscv64). Same binaries as the StarryOS run, per the RK3588
# report's "same ELF on both sides" rule.
#
# Prereq: build-harness-sg2002.sh output copied to the board's ext4 rootfs, e.g.
#   /root/probes/{cpuprobe,membw,syscost,ppong,thp_bw,mem_bw2,rusage_acct,...}
#
# Copy this file to the board and run:
#   sh /root/probes/linux-harness-sg2002.sh | tee /root/probes/linux-harness.out
#
# Env: PROBES_DIR (default /root/probes), PRIME (sysbench max prime, default 20000)
set -u

PROBES_DIR=${PROBES_DIR:-/root/probes}
PRIME=${PRIME:-20000}

# POSIX-only pass-through, identical to the StarryOS harness (see the comment
# there): "${@:2}" is a *string slice* on some shells, so use `shift`.
pc() { _c="$1"; shift; [ -x "$PROBES_DIR/$_c" ] && "$PROBES_DIR/$_c" "$@" 2>/dev/null; }

echo HARNESS_LINUX_SG2002_BEGIN
echo "HL_UNAME $(uname -r) $(uname -m)"
echo "HL_NPROC $(nproc 2>/dev/null || echo 1)"

echo "== core map (riscv64: SG2002 exposes one application hart) =="
if [ -f /proc/cpuinfo ]; then
  awk -F: '/^processor/{gsub(/ /,"",$2); print "HL_CORE cpu"$2" arch=riscv64"}' /proc/cpuinfo
fi

echo "== cpufreq (SG2002 has no userspace cpufreq; recorded for completeness) =="
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
  echo "HL_REF cl=0 curkhz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
else
  echo "HL_REF cl=0 no_cpufreq"
fi

echo "== per-core cpuprobe (counter self-calibrated against CLOCK_MONOTONIC) =="
cores=$(nproc 2>/dev/null || echo 1)
i=0
while [ "$i" -lt "$cores" ]; do
  line=$(pc cpuprobe "$i")
  [ -n "$line" ] && echo "HL_PC $line"
  i=$((i + 1))
done

echo "== per-core membw (first-touch + warm bandwidth, 128 MiB) =="
i=0
while [ "$i" -lt "$cores" ]; do
  # 32 MiB, same as the StarryOS side (board has 236 MB; membw allocates twice)
  line=$(pc membw "$i" 32)
  [ -n "$line" ] && echo "HL_PM $line"
  i=$((i + 1))
done

echo "== syscall entry / pipe data path =="
[ -x "$PROBES_DIR/syscost" ] && "$PROBES_DIR/syscost" 500000 2>/dev/null | sed 's/^/HL_MICRO /'
[ -x "$PROBES_DIR/ppong" ] && "$PROBES_DIR/ppong" 2>/dev/null | sed 's/^/HL_MICRO /'

echo "== page-fault / THP / memory bandwidth probes =="
[ -x "$PROBES_DIR/thp_bw" ] && "$PROBES_DIR/thp_bw" 64 2>/dev/null | sed 's/^/HL_MICRO /'
[ -x "$PROBES_DIR/mem_bw2" ] && "$PROBES_DIR/mem_bw2" 2>/dev/null | sed 's/^/HL_MICRO /'
[ -x "$PROBES_DIR/rusage_acct" ] && "$PROBES_DIR/rusage_acct" 2>/dev/null | sed 's/^/HL_MICRO /'

echo "== sysbench (optional; run only when the binary is staged) =="
if command -v sysbench >/dev/null 2>&1; then
  for t in 1; do
    ev=$(sysbench cpu --cpu-max-prime="$PRIME" --threads="$t" --time=5 run 2>/dev/null \
         | awk '/events per second/{print $4}')
    echo "HL_MX cpu t=$t ev=${ev:-NA}"
  done
  echo "HL_MX mem $(sysbench memory --threads=1 --memory-total-size=1G run 2>/dev/null | awk '/transferred/{print}')"
else
  echo "HL_MX sysbench_absent"
fi

echo HARNESS_LINUX_SG2002_END
