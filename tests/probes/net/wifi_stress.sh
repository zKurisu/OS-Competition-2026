#!/bin/bash
# wifi_stress.sh —— 量化「WiFi 链路累计传输到多少字节后静默失效」
#
# 背景：本板的 AIC8800 链路在连续传输约 8–10 MB 后会收发全断（接口仍显示 RUNNING、
# IP 仍在），从串口重新关联才恢复。这条直接影响"从网卡刷内核"的可行性，所以把它
# 变成可重复的测量：反复 scp 一个固定大小的文件，每轮之间 ping 一次，第一次失败就
# 报告"累计传输量"与"失败现象"。
#
# 用法： ./wifi_stress.sh [板子IP] [轮数] [每轮MB]
# 例：   ./wifi_stress.sh 192.168.43.158 40 1
set -u

IP=${1:-192.168.43.158}
ROUNDS=${2:-40}
MB=${3:-1}
SRC=/tmp/wifi_stress_payload.bin

head -c $((MB * 1024 * 1024)) /dev/urandom > "$SRC"
total=0
echo "[wifi_stress] target=$IP rounds=$ROUNDS payload=${MB}MiB"
for i in $(seq 1 "$ROUNDS"); do
    if ! timeout 20 ssh -F /dev/null -o ConnectTimeout=6 -o StrictHostKeyChecking=no \
         -o UserKnownHostsFile=/dev/null -o BatchMode=yes root@"$IP" true 2>/dev/null; then
        echo "[wifi_stress] 第 $i 轮：ssh 不通（累计已传 $total MiB）"
        break
    fi
    if timeout 120 scp -O -o ConnectTimeout=6 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$SRC" root@"$IP":/root/ \
        >/dev/null 2>&1; then
        total=$((total + MB))
    else
        echo "[wifi_stress] 第 $i 轮：scp 失败（累计已传 $total MiB）"
        break
    fi
    if ! timeout 6 ping -c 2 -W 2 "$IP" >/dev/null 2>&1; then
        echo "[wifi_stress] 第 $i 轮后：ping 不通（累计已传 $total MiB）"
        break
    fi
    printf "  轮 %2d ok 累计 %d MiB\n" "$i" "$total"
done
echo "[wifi_stress] 结束：累计成功传输 $total MiB"
