#!/bin/sh
# bare_board_selftest.sh —— 裸板（只开发板、不接底盘/舵机/摄像头）自检
#
# 为什么要这个脚本：裸板上能采的证据分几类，但它们的前置条件互相影响
# （小核链路要先打开才有点数、负载会污染节拍），分开一条条敲容易把状态搞乱，
# 也让日志零散。这里按固定顺序跑一遍，每段打 BEGIN/END 标记，整段日志可以直接贴。
#
# 用法（板端）：
#   cp /root/bare_board_selftest.sh /root/ ; cd /root ; chmod +x bare_board_selftest.sh
#   ./bare_board_selftest.sh              # 空载，约 1~2 分钟
#   ./bare_board_selftest.sh --load       # 额外采一轮 CPU 满载对照（再加约 1 分钟）
#   ./bare_board_selftest.sh --secs 20    # 每段多跑一会儿
#   ./bare_board_selftest.sh --tick       # 额外跑 20 秒的 tick/时基测量（默认跳过）
#
# TPU 那一段（Q1 的固件侧耗时）需要板上已有的 akars 与模型/图片，用环境变量打开：
#   BB_AKARS=/root/akars BB_MODEL=/root/AKA-00/yolov8n_tennis_v2.cvimodel \
#   BB_IMAGE=/root/AKA-00/test.jpg ./bare_board_selftest.sh
# （BB_LD_LIBRARY_PATH 默认 /root/AKA-00/lib，akars 起不来时先设这个）
# 这一段默认跑 3 次取中位数（每次约 5.6 s）；只想看一眼就 BB_DETECT_RUNS=1。
#
# 前置：cmdqu_test、uart_probe 与它放在同一个目录里（默认找 . ）
# 输出：同时也写一份到 /tmp/bare_board_selftest.log（**下次运行会覆盖它**，要留就先拷走）
#
# 耗时分布：默认一轮约 25~30 秒，几乎全部花在三个刻意留长的测量窗口上——
#   [4] target --secs 10、[5] bench --secs 10 各 10 秒（要够 100 拍才谈得上 p99），
#   [3] 的 1+2 秒固定等待；[2] 的 20 秒时基测量默认关掉（加 --tick 打开）。
#   想更快就 --secs 5（拍数减半，p99 分辨力也减半）。
#
# 判据见 docs/13-bare-board-plan.md；本脚本只负责把证据采全，不做判定。

set -u

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
CMDQU="$TOOLS_DIR/cmdqu_test"
PROBE="$TOOLS_DIR/uart_probe"
LOG=/tmp/bare_board_selftest.log
SECS=10
DO_LOAD=0
DO_TICK=0
TMP=/tmp/_bb_out

while [ $# -gt 0 ]; do
    case "$1" in
        --load) DO_LOAD=1 ;;
        --secs) shift; SECS="${1:-10}" ;;
        --tick) DO_TICK=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

: >"$LOG"

emit() { printf '%s\n' "$*"; printf '%s\n' "$*" >>"$LOG"; }

# 跑一条命令：先回显命令，再把它的输出逐行收进日志，最后记返回码。
run() {
    emit "\$ $*"
    if "$@" >"$TMP" 2>&1; then rc=0; else rc=$?; fi
    while IFS= read -r line; do emit "$line"; done <"$TMP"
    emit "[rc=$rc]"
}

need() {
    if [ ! -x "$1" ]; then
        emit "缺少可执行文件：$1（把 cmdqu_test 与 uart_probe 放在脚本同目录）"
        exit 2
    fi
}

need "$CMDQU"
need "$PROBE"

T0_S=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
now_s() { cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1; }
# 每段开始前调一次：先把上一段的耗时打出来（第一段没有上一段），再记住本段的起点。
SEC_L=""
SEC_T="$T0_S"
section() {
    t=$(now_s)
    if [ -n "$SEC_L" ]; then
        emit "    [耗时] $SEC_L ≈ $((t - SEC_T)) s"
    fi
    SEC_L="$1"
    SEC_T="$t"
}

emit "=== BARE-BOARD SELFTEST begin ==="
emit "date=$(date 2>/dev/null || echo '?')  secs=$SECS  load=$DO_LOAD  tick=$DO_TICK  tools=$TOOLS_DIR"
run sh -c 'cat /proc/uptime 2>/dev/null'
run sh -c 'ls -l /dev/cvi-rtos-cmdqu /dev/cvi-usb-camera0 2>&1'

# ---------------------------------------------------------------------------
emit ""
emit "--- [1] cmdqu 基本通路（不需要底盘）---"
section "[1] cmdqu 基本"
run "$CMDQU" diag
# 前置判定：小核到底在不在跑。不在跑的话，第 2/3/4 段每条命令都会白等 1 秒超时，
# 采集到的只有"超时"，看不出别的东西——所以先把门关上，把排查方向写出来。
#
# 判据只能是"PC 是不是 0"：**PC 非 0 但两次采样相同，仍然是在跑**——小核空闲时
# 停在同一个循环里是常事。2026-10-03 就因为拿"两次相同"当判据误判过一次
# （那次 PC 是 0x8fe105f8，是活的，却把 [2][3][4] 全跳过了）。
if ! grep -q '小核 PC' "$TMP"; then
    CORE_ALIVE=1
    emit "[前置] 没拿到小核 PC 采样（diag 可能没跑成），按'未知'处理，继续采各段"
elif grep -q '小核 PC = 0x00000000' "$TMP"; then
    CORE_ALIVE=0
else
    CORE_ALIVE=1
fi
if [ "$CORE_ALIVE" = 1 ]; then
    emit "[前置] 小核在跑（diag 的 PC 采样非 0）——继续采小核相关的段"
else
    emit "[前置] 小核没在跑（diag 采到的 PC 是 0x00000000，说明还在复位态）"
    emit "       后面的第 2/3/4 段依赖小核应答，跳过；第 5 段（大核直控）仍然有效。"
    emit "       按 docs/11 第 8 节排查，顺序是："
    emit "         1) 供电——只插电脑 Type-C 会表现为小核完全无响应，换小车电源或独立 5V；"
    emit "         2) 开机日志的 C2S/… 与 C2E./RSC.：FSBL 有没有把固件释放到 0x8FE00000；"
    emit "            （出现 No C906L image. 说明 FIP 里没有小核段）"
    emit "         3) 开机日志的 blcp_2nd_cksum 是否报错（卡上的 fip.bin 写坏了）；"
    emit "         4) 卡上 fip.bin 的 sha256 与 C2S 的大小字段，确认是哪一版固件；"
    emit "         5) 彻底断电（断电池）清邮箱残留。"
    emit "       冷启动前记得拔掉所有外接（尤其 TTL 转接器）。"
fi
run "$CMDQU" ring
run "$CMDQU" stats
run "$CMDQU" shm

# ---------------------------------------------------------------------------
emit ""
section "[2] 上报确定性与时基"
if [ "$CORE_ALIVE" = 1 ]; then
    if [ "$DO_TICK" = 1 ]; then
        emit "--- [2] 小核上报确定性与时基（不需要底盘）---"
        run "$CMDQU" drift-hist 20
        run "$CMDQU" jitter
        # drift-hist 会把上报周期压到 5 ms（一个小核 tick），快照因此变成 ~200 条/秒，
        # 而环只有 64 条 ≈ 320 ms 历史——每秒一条的 kind=6/8/9 会被挤出去读不到。
        # 后面第 3/4 段正是要读这些状态上报，所以这里必须调回去。
        run "$CMDQU" period 200
    else
        emit "--- [2] 小核上报确定性与时基：已跳过（这一段要 20 秒，加 --tick 打开）---"
        emit "        已测结论见 docs/13 第 4 节：每 tick 5000.00 µs、间隔零推迟，两条轮次一致。"
    fi
else
    emit "--- [2] 小核上报确定性与时基：已跳过（小核没在跑，环里不会有样本）---"
fi

# ---------------------------------------------------------------------------
emit ""
section "[3] 空链路负向基线"
if [ "$CORE_ALIVE" = 1 ]; then
    emit "--- [3] 空链路负向基线：没人应答时 INIT 计数应当增长、ACK 恒为 0 ---"
    run "$CMDQU" uart 1
    sleep 1
    run "$CMDQU" uart-stats
    sleep 2
    run "$CMDQU" uart-stats
    run "$CMDQU" uart 0
else
    emit "--- [3] 空链路负向基线：已跳过（小核没在跑，UA==0 时这条没有信息量）---"
fi

# ---------------------------------------------------------------------------
# B 组：小核接管。没有底盘时 RPM 恒为 0，但控制循环照常按 tick 走，
# kind=9 的周期分布仍然是有效证据。
emit ""
section "[4] B 组（小核接管）"
if [ "$CORE_ALIVE" = 1 ]; then
    emit "--- [4] B 组 小核接管：控制周期分布（无底盘，RPM 恒 0）---"
    run "$CMDQU" uart 0
    run "$CMDQU" ctrl-period 100
    run "$CMDQU" target 20 --secs "$SECS"
    run "$CMDQU" uart-stats
    run "$CMDQU" uart 0
else
    emit "--- [4] B 组 小核接管：已跳过（小核没在跑）---"
fi

# ---------------------------------------------------------------------------
# A 组：大核直控。--no-ack 让它在没有底盘应答时也能采节拍，
# 但这条数字只反映大核自己的调度，不代表链路健康。
emit ""
section "[5] A 组（大核直控）"
emit "--- [5] A 组 大核直控：节拍分布（--no-ack，无底盘）---"
run "$PROBE" bench /dev/ttyS1 20 --secs "$SECS" --period 100 --no-ack

# ---------------------------------------------------------------------------
if [ "$DO_LOAD" = 1 ]; then
    emit ""
    section "[6] 负载对照"
    emit "--- [6] 负载对照（3 个 yes 打满大核）---"
    yes >/dev/null 2>&1 & p1=$!
    yes >/dev/null 2>&1 & p2=$!
    yes >/dev/null 2>&1 & p3=$!
    emit "已起负载：pid=$p1 $p2 $p3"
    sleep 1
    run "$PROBE" bench /dev/ttyS1 20 --secs "$SECS" --period 100 --no-ack
    if [ "$CORE_ALIVE" = 1 ]; then
        run "$CMDQU" ctrl-period 100
        run "$CMDQU" target 20 --secs "$SECS"
        run "$CMDQU" uart-stats
        run "$CMDQU" uart 0
    else
        emit "B 组已跳过（小核没在跑）：负载下只有 A 组可采"
    fi
    kill "$p1" "$p2" "$p3" 2>/dev/null
    wait 2>/dev/null
    emit "负载已收（kill $p1 $p2 $p3）"
fi

emit ""
section "[7] 收尾"
emit "--- [7] 收尾 ---"
run "$CMDQU" uart 0
run "$CMDQU" stats

# ---------------------------------------------------------------------------
# TPU：固定图片推理计时。这是 Q1（感知链路分段）里除"采帧"之外的部分，
# 不需要摄像头。只有在给了 BB_AKARS/BB_MODEL/BB_IMAGE 时才跑。
emit ""
section "[8] TPU 固定图片计时"
if [ -n "${BB_AKARS:-}" ] && [ -n "${BB_MODEL:-}" ] && [ -n "${BB_IMAGE:-}" ]; then
    emit "--- [8] TPU 固定图片推理计时（不需要摄像头）---"
    LIBDIR="${BB_LD_LIBRARY_PATH:-/root/AKA-00/lib}"
    RUNS="${BB_DETECT_RUNS:-3}"
    emit "LD_LIBRARY_PATH=$LIBDIR"
    i=1
    while [ "$i" -le "$RUNS" ]; do
        emit "  第 $i 次："
        run env LD_LIBRARY_PATH="$LIBDIR" "$BB_AKARS" detect "$BB_MODEL" "$BB_IMAGE"
        i=$((i + 1))
    done
else
    emit "--- [8] TPU 固定图片推理计时：已跳过 ---"
    emit "   （设 BB_AKARS / BB_MODEL / BB_IMAGE 后重跑即可，见脚本头部或 docs/13 第 3.2 节）"
fi

# 收尾：把最后一段的耗时打出来，再给总耗时。
t=$(now_s)
[ -n "$SEC_L" ] && emit "    [耗时] $SEC_L ≈ $((t - SEC_T)) s"
emit "总耗时 ≈ $((t - T0_S)) s"

emit "=== BARE-BOARD SELFTEST end ==="
emit "日志副本：$LOG（**下次运行会覆盖它**，要留就先拷走）"

# 收尾落盘：StarryOS 的写只进页缓存、没有周期性回写，且 `sync` 只保住它之前写的内容。
# 所以 sync 放在最后一条 emit 之后；"可以断电了"只打终端，免得那句话本身丢在半路。
sync
echo "已 sync，可以断电取走 $LOG 了"
