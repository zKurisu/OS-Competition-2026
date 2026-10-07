#!/bin/sh
# cam_selftest.sh —— 摄像头（/dev/cvi-usb-camera0）采帧数据"一次采全"
#
# 要采的四件事（判据见 docs/12 与 docs/06 的 Q1）：
#   ① 基本连通：分辨率 / 格式 / connected
#   ② cmd3（原始 MJPEG）与 cmd4（内核 JPU 解码成 YUV）的耗时分布
#      —— 二者 p50 之差就是"解码"那一段的量级
#   ③ 连续采帧长稳：帧数、实际 FPS、帧大小分布、重复帧（画面卡住）、出错
#   ④ 画面正确性：各存一帧 JPEG 与 YUV，由人眼看
#
# **顺序是有讲究的**：cmd4 走内核 JPU，而 JPU 一次解码超时就会永久锁死
# （`is poisoned … reboot is required`），此后所有 cmd4 都返回 EIO，只能重启整机。
# 所以凡是碰 cmd4 的项（②的 yuv 部分、③的 yuv 长稳）都必须排在 cmd3 之前，
# 否则已经锁死的 JPU 会把之后每一个 yuv 读数都污染成 0。cmd3 走 USB 等时通路，
# 不经过 JPU，放在最后跑，正好当"JPU 挂了但采帧通路仍然好着"的对照。
#
# 用法（板上）：sh /root/cam_selftest.sh
#   可调：FRAMES=60 SECS=120 sh /root/cam_selftest.sh
# 产物：/root/cam_selftest.log（全部输出，之后可用 UMS + debugfs 取回）
#       /root/cam_probe_frame.jpg、/root/cam_probe_last.jpg、/root/cam_probe_last.yuv

DEV=${DEV:-/dev/cvi-usb-camera0}
FRAMES=${FRAMES:-30}
SECS=${SECS:-30}
LOG=/root/cam_selftest.log
PROBE=/root/cam_probe

log() { echo "$@" | tee -a "$LOG"; }

: >"$LOG"
log "=== CAM SELFTEST begin $(date) ==="
log "设备：$DEV    bench 帧数：$FRAMES    长稳秒数：$SECS"

if [ ! -x "$PROBE" ]; then
    log "CAM_SELFTEST_NO_PROBE：/root/cam_probe 不存在"
    exit 1
fi
if [ ! -e "$DEV" ]; then
    log "CAM_SELFTEST_NO_DEVICE：$DEV 不存在（摄像头插好了吗？）"
    exit 1
fi

log ""
log "--- [1] 基本连通 ---"
$PROBE info "$DEV" 2>&1 | tee -a "$LOG"

log ""
log "--- [2]+[4a] 分段耗时（cmd3 与 cmd4 交替，各 $FRAMES 帧，预热 5 帧）---"
$PROBE bench "$DEV" --frames "$FRAMES" --warmup 5 --mode both --save /root/cam_probe_frame 2>&1 | tee -a "$LOG"

log ""
log "--- [3a] 连续采帧长稳：cmd4 YUV（含 JPU 解码），$SECS 秒 ---"
log "    先在干净状态下测这一项；若中途报 JPU 锁死，记录它成功了多少帧即可。"
$PROBE long "$DEV" --secs "$SECS" --mode yuv --save /root/cam_probe_last.yuv 2>&1 | tee -a "$LOG"

log ""
log "--- [3b] 连续采帧长稳：cmd3 原始 MJPEG，$SECS 秒 ---"
log "    这一项不经过 JPU，应当是满速且零出错——用它对照上一条的故障。"
$PROBE long "$DEV" --secs "$SECS" --mode raw --save /root/cam_probe_last.jpg 2>&1 | tee -a "$LOG"

log ""
log "--- [4b] 样本文件 ---"
ls -l /root/cam_probe_frame.jpg /root/cam_probe_frame.yuv /root/cam_probe_last.jpg /root/cam_probe_last.yuv 2>&1 | tee -a "$LOG"

log ""
log "=== CAM SELFTEST done $(date) ==="
log "CAM_SELFTEST_DONE"

# 收尾：StarryOS 的写只进页缓存，没有 Linux 那种周期性回写线程，所以
# ① 不 sync 的话，断电/硬复位之后文件长度是对的、内容全是 0；
# ② sync 只保住它**之前**写下去的内容，之后写的照样会丢。
# 结论是 sync 必须是这个脚本的最后一次落盘动作——所以它放在所有 log 之后，
# 而"可以断电了"这句只打到终端、不进日志（免得它自己丢在半路）。
sync
echo "已 sync，样本与日志可以断电取走了"
