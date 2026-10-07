#!/bin/sh
# 在板子上模拟"开机时没有 IP"的情形：把 wlan0 断开，再跑一次 boot_net_up.sh，
# 看它能不能自己把链路拉回来。全程脱机会话（setsid）执行。
# 注意：这是**模拟**，不是真实重启——真实验证另做一次 reset。
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

log() { echo "[$(cat /proc/uptime)] $*"; }

log "step1: ifconfig wlan0 down"
ifconfig wlan0 down 2>&1
log "down 之后 ifconfig wlan0："
ifconfig wlan0 2>&1

log "step2: sleep 2，确认确实没有 IP"
sleep 2
ifconfig wlan0 | grep 192.168 && log "!! 仍有 IP，模拟没生效" || log "确认已无 IP"

log "step3: 运行 /root/boot_net_up.sh（对它来说等价于开机场景）"
/root/boot_net_up.sh
log "脚本返回后的 wlan0："
ifconfig wlan0 2>&1

# 兜底：万一这次关联失败，再给几次机会，避免把板子留在脱网状态。
k=0
while [ "$k" -lt 6 ]; do
    ifconfig wlan0 | grep -q 192.168 && break
    log "第 $k 次兜底重试"
    sleep 10
    /root/boot_net_up.sh
    k=$((k + 1))
done

log "结束：inet=$(ifconfig wlan0 | grep -c 192.168) sshd=$(ps | grep -c ssh[d]) sync=$(ps | grep -c "[s]ync_loop")"
sync
