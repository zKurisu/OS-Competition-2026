#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() { echo "usage: $0 starry|linux root@BOARD_IP [--check]"; }
[[ $# -ge 2 ]] || { usage >&2; exit 2; }
os=$1; remote=$2; shift 2
case_root "$os" >/dev/null
check_remote "$remote"
check=0
if (($#)); then [[ $# == 1 && $1 == --check ]] || { usage >&2; exit 2; }; check=1; fi
app_root=$(case_root "$os")
board_dir=$(case_board_dir "$os")
binary="$app_root/target/$TARGET_TRIPLE/release/akars"
model=$(case_model "$os")
need_file "$binary"
check_model "$model"
need_file "$app_root/scripts/test-ball-count.sh"
need_file "$app_root/scripts/run-robot.sh"
sdk_lib="$app_root/toolchains/tpu-sdk-sg200x/lib"
need_file "$sdk_lib/libcviruntime.so"
need_file "$sdk_lib/libcvikernel.so"
if [[ $os == linux ]]; then
  media_lib="$LINUX_BASE_ROOT/deploy/root/akars_linux/lib"
  for lib in libsys.so libvdec.so libvpu.so; do need_file "$media_lib/$lib"; done
fi
printf 'OS=%s\nBOARD=%s\nBOARD_DIR=%s\n' "$os" "$remote" "$board_dir"
sha256sum "$binary" "$model"
if ((check)); then exit 0; fi
need_cmd ssh
need_cmd scp
device_node=/dev/cvi-usb-camera0
if [[ $os == linux ]]; then device_node=/dev/video0; fi
ssh "$remote" "test -c '$device_node' && test -c /dev/cvi-tpu0 && command -v pidof >/dev/null && ! pidof akars >/dev/null" \
  || die "wrong OS/device nodes or akars is still running; stop it before deployment"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
stage="$board_dir/.repro-stage-$stamp-$$"
ssh "$remote" "mkdir -p '$board_dir' '$stage/lib' '$stage/model'"
scp "$binary" "$remote:$stage/akars"
scp "$model" "$remote:$stage/model/$MODEL_NAME"
scp "$app_root/scripts/test-ball-count.sh" "$app_root/scripts/run-robot.sh" "$remote:$stage/"
scp "$sdk_lib/libcviruntime.so" "$sdk_lib/libcvikernel.so" "$remote:$stage/lib/"
if [[ $os == linux ]]; then
  scp "$media_lib/libsys.so" "$media_lib/libvdec.so" "$media_lib/libvpu.so" "$remote:$stage/lib/"
fi
binary_sha=$(sha256sum "$binary"); binary_sha=${binary_sha%% *}
ssh "$remote" "set -eu
  echo '$binary_sha  $stage/akars' | sha256sum -c -
  echo '$MODEL_SHA256  $stage/model/$MODEL_NAME' | sha256sum -c -
  mkdir -p '$board_dir/model' '$board_dir/lib'
  if test -f '$board_dir/akars'; then cp -p '$board_dir/akars' '$board_dir/akars.before-repro-$stamp'; fi
  mv '$stage/akars' '$board_dir/akars'
  chmod 755 '$board_dir/akars'
  mv '$stage/test-ball-count.sh' '$stage/run-robot.sh' '$board_dir/'
  chmod 755 '$board_dir/test-ball-count.sh' '$board_dir/run-robot.sh'
  cp '$stage/model/$MODEL_NAME' '$board_dir/model/$MODEL_NAME'
  cp '$stage/lib/'*.so '$board_dir/lib/'
  sync
  echo '$binary_sha  $board_dir/akars' | sha256sum -c -
  echo '$MODEL_SHA256  $board_dir/model/$MODEL_NAME' | sha256sum -c -
  rm -r '$stage'
  echo AKARS_DEPLOY_OK os=$os path=$board_dir"
