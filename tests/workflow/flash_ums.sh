#!/bin/bash
# flash_ums.sh <name> [observe_s] —— 一键完整刷写 + 引导流程：
#   1) 串口下发 sync + /root/c906l_kick reset  → 回到 U-Boot
#   2) 串口下发 ums 0 mmc 0                    → 卡以 U 盘形式挂到主机
#   3) 主机侧 mtools 写 FAT（空间不足先删最旧的 starry-*.sd）
#   4) Ctrl-C 退出 UMS，再 fatload + bootm 引导
#
# 用法：
#   ./flash_ums.sh opt78            # 刷 /tmp/pack_opt78/starry-opt78.sd 并引导
#   ./flash_ums.sh perf1 150        # 引导后观察 150 s
#   SG2002_PORT=/dev/ttyUSB1 ./flash_ums.sh opt78
#
# 前提：已用 pack_fit.sh 生成 /tmp/pack_<name>/starry-<name>.sd。
# 注意：全程只操作 $SG2002_PORT 指定的那一条串口，不会碰另一块板子。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ums_device.sh
source "$SCRIPT_DIR/ums_device.sh"

NAME="${1:?usage: flash_ums.sh <name> [observe_s]}"
OBSERVE="${2:-110}"
PACK="/tmp/pack_$NAME"
IMG="starry-$NAME.sd"
[ -f "$PACK/$IMG" ] || { echo "找不到 $PACK/$IMG（先跑 pack_fit.sh $NAME）" >&2; exit 1; }

PORT="${SG2002_PORT:-/dev/ttyUSB0}"

echo "[1/4] 复位到 U-Boot"
# 只清本项目自己的串口进程，避免误杀别的板卡会话。
pkill -f "[s]g2002_cmd.py" 2>/dev/null || true
sleep 1
python3 "$SCRIPT_DIR/sg2002_cmd.py" --dev "$PORT" 'sync; /root/c906l_kick reset' \
    --prompt shell --timeout 40 2>/dev/null | tail -3 || true

echo "[2/4] 启动 UMS"
timeout 400 python3 "$SCRIPT_DIR/sg2002_cmd.py" --dev "$PORT" 'ums 0 mmc 0' \
    --prompt uboot --timeout 20 >/dev/null 2>&1 || true
FAT=""
for _ in $(seq 1 40); do
    FAT=$(ums_find_unique_ums 2>/dev/null | awk '{print $1}') || true
    [ -n "$FAT" ] && mdir -i "$FAT" :: >/dev/null 2>&1 && break
    FAT=""
    sleep 1
done
[ -n "$FAT" ] || { echo "UMS 未就绪或设备不唯一，已停下" >&2; exit 1; }
echo "      FAT = $FAT"

echo "[3/4] 写入 $IMG"
free_bytes=$(mdir -i "$FAT" :: 2>/dev/null | tail -1 | tr -s ' ' | awk '{print $1*1000000+$2*1000+$3}')
while [ "${free_bytes:-0}" -lt 17000000 ]; do
    victim=$(mdir -i "$FAT" :: 2>/dev/null | awk '/starry-.*\.sd/ {print $NF}' |
        grep -v "^starry-$NAME\.sd$" | sort | head -1 || true)
    [ -z "$victim" ] && break
    echo "      删除旧镜像 $victim"
    mdel -i "$FAT" "::$victim" || true
    free_bytes=$(mdir -i "$FAT" :: 2>/dev/null | tail -1 | tr -s ' ' | awk '{print $1*1000000+$2*1000+$3}')
done
mcopy -i "$FAT" -o "$PACK/$IMG" "::$IMG" || { echo "mcopy 失败" >&2; exit 1; }
sync
mdir -i "$FAT" :: | tail -2

echo "[4/4] 退出 UMS 并引导"
pkill -f "[s]g2002_cmd.py" 2>/dev/null || true
sleep 1
timeout 60 python3 "$SCRIPT_DIR/sg2002_cmd.py" --dev "$PORT" --break >/dev/null 2>&1 || true
python3 "$SCRIPT_DIR/boot_probe.py" "$IMG" "$OBSERVE" --dev "$PORT" \
    --log "/tmp/boot_$NAME.log" | tail -4
