#!/bin/sh
# rpm_sweep.sh —— 扫一遍 PWM→RPM 曲线（**带载**用；空载那轮见 docs/11 第 6.2 节）
#
# 为什么要重扫：现有标定（10/12/13% 不转、14% 起步、20%→44/46 RPM…）全是**车轮架空**
# 的数字。带载时同一 PWM 的转速会低一截、死区也会变，答辩问"空载数字能不能外推"时
# 需要这一组对照。
#
# 用法（板上，车要在你选好的工况下）：
#   sh /root/rpm_sweep.sh                          # 默认 14~60%
#   sh /root/rpm_sweep.sh "14 16 18 20 25 30 40"   # 自定义档位
#   SECS=8 STABLE=4 sh /root/rpm_sweep.sh          # 每档跑 8 s、第 4 s 读转速
#   sh /root/rpm_sweep.sh "-20 20"                 # 负值测另一侧方向
#
# 它怎么读数：把 `cmdqu_test target <p> --secs N` 丢到后台（那个进程负责喂心跳，
# 小核的看门狗窗口是 500 ms，所以心跳不能断），等 STABLE 秒后另开一个
# `cmdqu_test uart-stats` 读 kind=8 的"目标 PWM / RPM / 底盘状态"。
#
# 安全：脚本退出时（含 Ctrl+C）会补一条 `target 0 --secs 1` 把目标清零；
#       小核自己也有看门狗兜底。即便如此——**先确认车不会撞到东西**。
#
# 产物：一行一条的 CSV 风格输出；追加到 /root/rpm_sweep.log 便于取回。

set -u

CMDQU=/root/cmdqu_test
PCTS="${1:-14 16 18 20 25 30 40 50 60}"
SECS="${SECS:-6}"
STABLE="${STABLE:-3}"
LOG=/root/rpm_sweep.log

[ -x "$CMDQU" ] || { echo "找不到 $CMDQU"; exit 1; }
if [ "$STABLE" -ge "$SECS" ]; then
    echo "STABLE($STABLE) 必须小于 SECS($SECS)——否则还没转稳就去读转速了"
    exit 2
fi

cleanup() {
    $CMDQU target 0 --secs 1 >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

say() { echo "$@" | tee -a "$LOG"; }

say "=== RPM 扫描 begin $(date) ==="
say "档位：$PCTS   每档 ${SECS}s（第 ${STABLE}s 读读数）"
say ""
say "PWM%   目标PWM   状态      RPM左  RPM右   看门狗"

for p in $PCTS; do
    # target 是"喂心跳"的那个进程，必须活着；它到点会自己归零。
    $CMDQU target "$p" --secs "$((SECS + 2))" >/dev/null 2>&1 &
    worker=$!
    sleep "$STABLE"
    out=$($CMDQU uart-stats 2>&1)
    kill "$worker" 2>/dev/null
    wait "$worker" 2>/dev/null

    pwm=$(printf '%s\n' "$out" | sed -n 's/.*目标 PWM 左=\([-0-9]*\) 右=\([-0-9]*\).*/\1\/\2/p' | head -1)
    rpm=$(printf '%s\n' "$out" | sed -n 's/.*RPM 左=\([-0-9]*\) 右=\([-0-9]*\).*/\1 \2/p' | head -1)
    st=$(printf '%s\n' "$out" | sed -n 's/.*底盘状态=\([^ ]*\).*/\1/p' | head -1)
    wd=$(printf '%s\n' "$out" | sed -n 's/.*看门狗停车=\([-0-9]*\) 次.*/\1/p' | head -1)
    say "$(printf '%-5s  %-8s  %-8s  %-6s %s' "$p" "${pwm:-?}" "${st:-?}" "${rpm:-?}" "${wd:-?}")"

    cleanup
    sleep 1
done

say ""
say "=== RPM 扫描 end $(date) ==="
say "取回：UMS + debugfs 或直接把上面这张表抄走；完整日志 $LOG"
