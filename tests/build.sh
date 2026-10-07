#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() {
  echo "usage: $0 starry|linux [--setup] [--check]"
  echo "  --setup initializes the selected application's toolchain/TPU SDK (may download)."
  echo "  --check validates sources/model and prints paths without compiling."
}
[[ $# -ge 1 ]] || { usage; exit 2; }
os=$1; shift
app_root=$(case_root "$os")
setup=0; check=0
while (($#)); do
  case $1 in
    --setup) setup=1 ;;
    --check) check=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done
need_file "$app_root/scripts/build.sh"
need_file "$app_root/scripts/test-ball-count.sh"
check_model "$(case_model "$os")"
printf 'OS=%s\nAPP_ROOT=%s\nMODEL_SHA256=%s\n' "$os" "$app_root" "$MODEL_SHA256"
if [[ $os == starry ]]; then
  need_file "$TGOSKITS_ROOT/os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml"
  need_file "$TGOSKITS_ROOT/os/StarryOS/configs/board/aka-00-sg2002.dtb"
  printf 'KERNEL_ROOT=%s\n' "$TGOSKITS_ROOT"
fi
if ((check)); then exit 0; fi

need_cmd cargo
if ((setup)); then (cd "$app_root" && ./scripts/setup.sh); fi
(cd "$app_root" && ./scripts/build.sh)
app_binary="$app_root/target/$TARGET_TRIPLE/release/akars"
need_file "$app_binary"
file "$app_binary"
sha256sum "$app_binary"

if [[ $os == starry ]]; then
  need_cmd mkimage
  need_cmd dumpimage
  # The rootfs needs this userspace control tool for STA mode at boot.
  source "$AKARS_ROOT/scripts/env.sh"
  need_file "$TGOSKITS_ROOT/apps/starry/picoclaw-cli/wifi_switch.c"
  [[ -x $AKARS_CC ]] || die "missing cross C compiler: $AKARS_CC"
  mkdir -p "$REPRO_OUTPUT_DIR/starry"
  "$AKARS_CC" -static -O2 -Wall -Wextra \
    -o "$REPRO_OUTPUT_DIR/starry/wifi_switch" \
    "$TGOSKITS_ROOT/apps/starry/picoclaw-cli/wifi_switch.c"
  (cd "$TGOSKITS_ROOT" && cargo xtask starry build --config os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml)
  kernel="$TGOSKITS_ROOT/target/$TARGET_TRIPLE/release/starryos.bin"
  dtb="$TGOSKITS_ROOT/os/StarryOS/configs/board/aka-00-sg2002.dtb"
  need_file "$kernel"
  out="$REPRO_OUTPUT_DIR/starry"
  mkdir -p "$out"
  staging=$(mktemp -d)
  trap 'rm -r -- "$staging"' EXIT
  cp -- "$kernel" "$staging/starryos.bin"
  cp -- "$dtb" "$staging/licheerv-nano-sg2002.dtb"
  cp -- "$TESTS_ROOT/boot.its" "$staging/boot.its"
  (cd "$staging" && mkimage -f boot.its boot.sd)
  fit_info=$(dumpimage -l "$staging/boot.sd")
  for expected in 'kernel-1' 'fdt-1' 'config-sg2002_licheervnano_sd'; do
    [[ $fit_info == *"$expected"* ]] || die "FIT is missing $expected"
  done
  cp -- "$staging/boot.sd" "$out/boot.sd"
  dumpimage -l "$out/boot.sd"
  sha256sum "$out/boot.sd"
  printf 'STARRY_BOOT=%s\n' "$out/boot.sd"
  printf 'STARRY_WIFI_SWITCH=%s\n' "$out/wifi_switch"
fi
printf 'APP_BINARY=%s\n' "$app_binary"
