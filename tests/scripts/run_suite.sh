#!/bin/bash
# run_suite.sh —— 一键跑板级套件：编译探针 → 部署到板子 → 跑 harness → 收结果。
#
# 用法：
#   ./run_suite.sh --side starry                    # StarryOS 侧
#   ./run_suite.sh --side linux                     # 厂商 Linux 基线侧
#   ./run_suite.sh --side starry --deploy serial    # 没有 UMS 时走串口上传
#   ./run_suite.sh --side starry --dev /dev/ttyUSB1 --no-build
#
# 流程：
#   1) build_probes.sh 交叉编译（--no-build 跳过）
#   2) 部署：--deploy ums 用 debugfs 直接写 ext4（快）；--deploy serial 用串口分块上传（慢但无需 UMS）
#   3) 把 board/harness 下对应的 harness 脚本送到板上
#   4) 串口触发执行，输出与日志落到 --out（默认 tests/results/）
#
# 前后端约定：harness 打印 HS_*/HL_* 行，最后以 SYSBENCH_BOARD_DONE 结束，
# 于是日志本身就是可解析的"结果文件"。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$ROOT/workflow"

SIDE="starry"
DEPLOY="ums"
DEV="${SG2002_PORT:-/dev/ttyUSB0}"
BUILD=1
PROBES_DIR="/root/probes"
OUT="$ROOT/results"
BOARD_IP="${BOARD_IP:-192.168.43.158}"
RUN_TIMEOUT="${RUN_TIMEOUT:-1200}"

while [ $# -gt 0 ]; do
    case "$1" in
    --side) SIDE="$2"; shift 2 ;;
    --deploy) DEPLOY="$2"; shift 2 ;;
    --dev) DEV="$2"; shift 2 ;;
    --probes-dir) PROBES_DIR="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --ip) BOARD_IP="$2"; shift 2 ;;
    --timeout) RUN_TIMEOUT="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
    esac
done

case "$SIDE" in
starry) HARNESS="starry-harness-sg2002.sh" ;;
linux) HARNESS="linux-harness-sg2002.sh" ;;
*) echo "--side 只支持 starry|linux" >&2; exit 1 ;;
esac

mkdir -p "$OUT"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
LOG="$OUT/$STAMP-harness-$SIDE.log"
BIN="$ROOT/build/probes"

if [ "$BUILD" = 1 ]; then
    echo "[suite] 编译探针"
    bash "$SCRIPT_DIR/build_probes.sh"
fi
[ -d "$BIN" ] || { echo "没有 $BIN，先跑 build_probes.sh" >&2; exit 1; }

echo "[suite] 部署探针（$DEPLOY）"
if [ "$DEPLOY" = "ums" ]; then
    PROBE_DIR="$PROBES_DIR" EXTRA_DIR="$BIN" bash "$WORKFLOW/deploy_via_ums.sh"
elif [ "$DEPLOY" = "serial" ]; then
    for f in "$BIN"/*; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "probe_manifest.txt" ] && continue
        python3 "$WORKFLOW/sg2002_upload.py" "$f" "$PROBES_DIR/$(basename "$f")" \
            --dev "$DEV" --exec-bit
    done
else
    echo "--deploy 只支持 ums|serial" >&2
    exit 1
fi

echo "[suite] 部署 harness 脚本"
python3 "$WORKFLOW/sg2002_upload.py" "$ROOT/board/harness/$HARNESS" \
    "$PROBES_DIR/$HARNESS" --dev "$DEV" --exec-bit

echo "[suite] 运行 $HARNESS（超时 ${RUN_TIMEOUT}s）"
if [ "$SIDE" = "starry" ]; then
    PROBES_DIR="$PROBES_DIR" python3 "$WORKFLOW/sg2002_cmd.py" --dev "$DEV" \
        "sh $PROBES_DIR/$HARNESS" --timeout "$RUN_TIMEOUT" | tee "$LOG"
else
    PROBES_DIR="$PROBES_DIR" python3 "$WORKFLOW/linux_cmd.py" --dev "$DEV" \
        "sh $PROBES_DIR/$HARNESS; echo __DONE__" --timeout "$RUN_TIMEOUT" | tee "$LOG"
fi

echo "[suite] 结果：$LOG"
if grep -q SYSBENCH_BOARD_DONE "$LOG"; then
    echo "[suite] ✅ 套件正常结束"
else
    echo "[suite] ⚠️ 未见 SYSBENCH_BOARD_DONE，可能中途挂死，请看 $LOG"
    exit 2
fi
