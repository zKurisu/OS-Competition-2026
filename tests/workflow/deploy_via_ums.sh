#!/bin/bash
# deploy_via_ums.sh —— 板子在 U-Boot 且已 `ums 0 mmc 0` 时从宿主机部署：
#   1) 内核 FIT  -> FAT 分区（U-Boot fatload 用）
#   2) 探针二进制 -> ext4 的 /root/probes（用 debugfs 直接写，无需 mount/root）
#
# 用法：
#   ./deploy_via_ums.sh /tmp/pack_opt78/starry-opt78.sd
#   ./deploy_via_ums.sh --extra-dir ./build/probes --probe-dir /root/probes \
#                       /tmp/pack_opt78/starry-opt78.sd
#   FAT_DEV=/dev/sdb1 EXT_DEV=/dev/sdb2 ./deploy_via_ums.sh starry.sd
#
# 设备识别：默认用 ums_device.sh 按 FAT 里的 marker 认自己的卡；多板并存时
# 请显式设 FAT_DEV/EXT_DEV，脚本不会默认写 /dev/sda。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ums_device.sh
source "$SCRIPT_DIR/ums_device.sh"

PROBE_DIR=${PROBE_DIR:-/root/probes}
EXTRA_DIR=${EXTRA_DIR:-}
FAT_DEV=${FAT_DEV:-}
EXT_DEV=${EXT_DEV:-}
FITS=()

while [ $# -gt 0 ]; do
    case "$1" in
    --probe-dir) PROBE_DIR="$2"; shift 2 ;;
    --extra-dir) EXTRA_DIR="$2"; shift 2 ;;
    --fat) FAT_DEV="$2"; shift 2 ;;
    --ext) EXT_DEV="$2"; shift 2 ;;
    -*) echo "未知参数：$1" >&2; exit 1 ;;
    *) FITS+=("$1"); shift ;;
    esac
done

if [ -z "$FAT_DEV" ] || [ -z "$EXT_DEV" ]; then
    detected=$(ums_find_by_markers "starry-" "fip") || {
        echo "[deploy] 认不出属于本项目的 UMS 卡；请显式设 FAT_DEV/EXT_DEV" >&2
        exit 1
    }
    FAT_DEV=${FAT_DEV:-${detected%% *}}
    EXT_DEV=${EXT_DEV:-${detected##* }}
fi

say() { echo "[deploy] $*"; }
[ -b "$FAT_DEV" ] || { say "找不到 $FAT_DEV（UMS 起来了吗？）"; exit 1; }
[ -b "$EXT_DEV" ] || { say "找不到 $EXT_DEV"; exit 1; }

for f in "${FITS[@]}"; do
    [ -f "$f" ] || { say "跳过不存在的 $f"; continue; }
    say "FIT -> FAT: $(basename "$f") ($(stat -c %s "$f") B)"
    mcopy -i "$FAT_DEV" -o "$f" "::/$(basename "$f")" || say "mcopy 失败：$f"
done

# 额外的探针：放进 ext4 的 PROBE_DIR 并设成可执行
if [ -n "$EXTRA_DIR" ] && [ -d "$EXTRA_DIR" ]; then
    for p in "$EXTRA_DIR"/*; do
        [ -f "$p" ] || continue
        name=$(basename "$p")
        say "probe -> ext4:$PROBE_DIR/$name ($(stat -c %s "$p") B)"
        if debugfs -w -R "write $p $PROBE_DIR/$name" "$EXT_DEV" >/dev/null 2>&1 &&
            debugfs -w -R "sif $PROBE_DIR/$name mode 0100755" "$EXT_DEV" >/dev/null 2>&1; then
            say "  ok"
        else
            say "  debugfs 写入失败（已存在？先 rm 再 write）"
            debugfs -w -R "rm $PROBE_DIR/$name" "$EXT_DEV" >/dev/null 2>&1
            debugfs -w -R "write $p $PROBE_DIR/$name" "$EXT_DEV" >/dev/null 2>&1 &&
                debugfs -w -R "sif $PROBE_DIR/$name mode 0100755" "$EXT_DEV" >/dev/null 2>&1 &&
                say "  重试 ok"
        fi
    done
fi

say "完成；FAT 目录："
mdir -i "$FAT_DEV" ::/ 2>/dev/null | tail -12
