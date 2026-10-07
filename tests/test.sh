#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() { echo "usage: $0 starry|linux root@BOARD_IP POSITIVE_BALL_COUNT"; }
[[ $# == 3 ]] || { usage >&2; exit 2; }
os=$1; remote=$2; count=$3
case_root "$os" >/dev/null
check_remote "$remote"
[[ $count =~ ^[1-9][0-9]*$ ]] || die "ball count must be a positive integer"
board_dir=$(case_board_dir "$os")
log="/root/${os}-ball-count-${count}-$(date -u +%Y%m%dT%H%M%SZ).log"
need_cmd ssh
echo "Board test: $os, $count deposited balls; motors and gripper WILL MOVE."
echo "Keep a person beside the robot and stop power immediately if motion is unsafe."
echo "Board log: $log"
ssh "$remote" "sh -s -- '$board_dir' '$log' '$count' '$MODEL_SHA256' '$MODEL_NAME' '$os'" <<'REMOTE_SH'
set -u
board_dir=$1
log=$2
count=$3
model_sha=$4
model_name=$5
os=$6
cd "$board_dir" || exit 1
test -x ./akars && test -x ./test-ball-count.sh || exit 1
test -r /proc/uptime && command -v awk >/dev/null && command -v tee >/dev/null || exit 1
printf '%s  model/%s\n' "$model_sha" "$model_name" | sha256sum -c - || exit 1
IFS=' ' read -r mission_start _ </proc/uptime
./test-ball-count.sh "$count" >"$log" 2>&1
rc=$?
IFS=' ' read -r mission_end _ </proc/uptime
grep -E '^(单帧平均性能汇总|摄像头等待|JPU解码|VPSS|摄像头/JPU等待|TPU输入TDMA搬运|TPU推理|后处理|其他视觉开销|视觉总时延|单帧平均置信度|AKARS_(MISSION_COMPLETE|PERFORMANCE_SUMMARY|MISSION_SUMMARY|STAGE_AVERAGE report=final))' "$log" || true
if test "$rc" -ne 0; then
  mission_line=$(awk -v start="$mission_start" -v stop="$mission_end" 'BEGIN {printf "AKARS_REPRO_MISSION wall_seconds=%.3f mission_complete=0\n", stop-start}')
  printf '%s\n' "$mission_line" | tee -a "$log"
  tail -n 60 "$log"
  echo "AKARS_REPRO_FAIL reason=exit_code code=$rc"
  exit "$rc"
fi
grep -q "AKARS_MISSION_COMPLETE completed_deposits=$count reason=target_reached" "$log" || {
  tail -n 60 "$log"; echo 'AKARS_REPRO_FAIL reason=missing_mission_complete'; exit 1;
}
grep -q 'AKARS_STAGE_AVERAGE report=final mode=tennis' "$log" || {
  tail -n 60 "$log"; echo 'AKARS_REPRO_FAIL reason=missing_timing'; exit 1;
}
mission_line=$(awk -v start="$mission_start" -v stop="$mission_end" -v count="$count" 'BEGIN {
  elapsed=stop-start;
  if (elapsed < 0) exit 1;
  printf "AKARS_REPRO_MISSION target_deposits=%d completed_deposits=%d wall_seconds=%.3f seconds_per_deposit=%.3f\n", count, count, elapsed, elapsed/count;
}') || exit 1
printf '%s\n' "$mission_line" | tee -a "$log"
echo "AKARS_REPRO_PASS os=$os completed_deposits=$count log=$log"
REMOTE_SH
