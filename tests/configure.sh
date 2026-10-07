#!/usr/bin/env bash
# One-time, explicit repository-root selection. No directory is inferred.
set -euo pipefail

TESTS_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPRO_CONFIG=${REPRO_CONFIG:-$TESTS_ROOT/local-paths.conf}

usage() {
  echo "usage: $0 --starry-app DIR --starry-kernel DIR --linux-app DIR --linux-base DIR"
  echo "  Saves absolute paths to local-paths.conf (gitignored)."
  echo "  Set REPRO_CONFIG to use another configuration file."
}

starry_app=; starry_kernel=; linux_app=; linux_base=
while (($#)); do
  case $1 in
    --starry-app|--starry-kernel|--linux-app|--linux-base)
      (($# >= 2)) || { usage >&2; exit 2; }
      case $1 in
        --starry-app) starry_app=$2 ;;
        --starry-kernel) starry_kernel=$2 ;;
        --linux-app) linux_app=$2 ;;
        --linux-base) linux_base=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

for name in starry_app starry_kernel linux_app linux_base; do
  [[ -n ${!name} ]] || { usage >&2; exit 2; }
  [[ -d ${!name} ]] || { printf 'error: %s is not a directory: %s\n' "$name" "${!name}" >&2; exit 1; }
done
starry_app=$(realpath -e -- "$starry_app")
starry_kernel=$(realpath -e -- "$starry_kernel")
linux_app=$(realpath -e -- "$linux_app")
linux_base=$(realpath -e -- "$linux_base")

[[ -f $starry_app/scripts/build.sh && -f $starry_app/yolov8n_tennis_v2.cvimodel ]] || {
  echo 'error: --starry-app is not the expected application repository' >&2; exit 1;
}
[[ -f $starry_kernel/os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml ]] || {
  echo 'error: --starry-kernel is not the expected kernel repository' >&2; exit 1;
}
[[ -f $linux_app/scripts/build.sh && -f $linux_app/yolov8n_tennis_v2.cvimodel ]] || {
  echo 'error: --linux-app is not the expected application repository' >&2; exit 1;
}
[[ -f $linux_base/scripts/flash-linux-baseline.sh ]] || {
  echo 'error: --linux-base lacks the baseline flashing script' >&2; exit 1;
}

if [[ -e $REPRO_CONFIG || -L $REPRO_CONFIG ]]; then
  echo "error: configuration already exists: $REPRO_CONFIG" >&2
  echo 'Remove or move it explicitly before changing repository roots.' >&2
  exit 1
fi
umask 077
{
  printf 'AKARS_ROOT=%q\n' "$starry_app"
  printf 'TGOSKITS_ROOT=%q\n' "$starry_kernel"
  printf 'LINUX_AKARS_ROOT=%q\n' "$linux_app"
  printf 'LINUX_BASE_ROOT=%q\n' "$linux_base"
} > "$REPRO_CONFIG"
printf 'Configured repository roots in %s\n' "$REPRO_CONFIG"
printf 'StarryOS app:    %s\n' "$starry_app"
printf 'StarryOS kernel: %s\n' "$starry_kernel"
printf 'Linux app:       %s\n' "$linux_app"
printf 'Linux baseline:  %s\n' "$linux_base"
