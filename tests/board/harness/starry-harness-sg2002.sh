#!/bin/sh
# SG2002-side StarryOS harness. Deployed to the board ext4 rootfs as
# /root/probes/starry-harness-sg2002.sh and run by StarryOS.
#
# POSIX sh only: the StarryOS /bin/sh is dash. Same probe set as
# linux-harness-sg2002.sh so the two outputs are directly comparable.
#
# Emits HS_* lines and ends at SYSBENCH_BOARD_DONE (the board-run sentinel).

PROBES_DIR=${PROBES_DIR:-/root/probes}
PRIME=${PRIME:-20000}

have() { [ -x "$PROBES_DIR/$1" ]; }
# POSIX-only argument pass-through: StarryOS's /bin/sh (dash) does **not** treat
# "${@:2}" as "positional parameters from 2" — it slices the first parameter as a
# string, so `run syscost 500000` handed the probe the single argument
# "scost 500000" (atol -> 0, printed `inf`). Real-board evidence:
#   $ f1(){ echo "rest=[${@:2}]"; }; f1 syscost 20000   ->  rest=[scost 20000]
# Use `shift` instead; it behaves identically on dash/bash/busybox ash.
run()  { _c="$1"; shift; "$PROBES_DIR/$_c" "$@" 2>/dev/null; }

cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
[ -n "$cores" ] || cores=1

echo HARNESS_STARRY_SG2002_BEGIN
echo "HS_UNAME $(uname -r 2>/dev/null) $(uname -m 2>/dev/null)"
echo "HS_NPROC $cores"

echo "== per-core cpuprobe (rdtime self-calibrated) =="
i=0
while [ "$i" -lt "$cores" ]; do
  if have cpuprobe; then
    echo "HS_PC $(run cpuprobe "$i")"
  else
    echo "HS_PC req=$i no_cpuprobe"
  fi
  i=$((i + 1))
done

echo "== per-core membw (first-touch + warm bandwidth, 128 MiB) =="
i=0
while [ "$i" -lt "$cores" ]; do
  if have membw; then
    # 32 MiB: the SG2002 board has 236 MB total, and membw allocates two buffers.
    # The Linux side uses the same size so the two outputs stay comparable.
    echo "HS_PM $(run membw "$i" 32)"
  else
    echo "HS_PM core=$i no_membw"
  fi
  i=$((i + 1))
done

echo "== syscall entry / pipe data path =="
if have syscost; then
  run syscost 500000 | sed 's/^/HS_MICRO /'
fi
if have ppong; then
  run ppong | sed 's/^/HS_MICRO /'
fi

echo "== page-fault / THP / memory bandwidth probes =="
if have thp_bw; then
  # explicit 64 MiB (probe default is 256 MiB, which does not fit this board)
  run thp_bw 64 | sed 's/^/HS_MICRO /'
fi
if have mem_bw2; then
  run mem_bw2 | sed 's/^/HS_MICRO /'
fi
if have rusage_acct; then
  run rusage_acct | sed 's/^/HS_MICRO /'
fi

echo "== sysbench (optional; only when staged on the shared rootfs) =="
if [ -x /usr/local/bin/sysbench ] || command -v sysbench >/dev/null 2>&1; then
  SB=$(command -v sysbench 2>/dev/null || echo /usr/local/bin/sysbench)
  ev=$($SB cpu --cpu-max-prime="$PRIME" --threads=1 --time=5 run 2>/dev/null \
       | awk '/events per second/{print $4}')
  echo "HS_MX cpu t=1 ev=${ev:-NA}"
else
  echo "HS_MX sysbench_absent"
fi

sync 2>/dev/null
echo SYSBENCH_BOARD_DONE
