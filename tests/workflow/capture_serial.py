#!/usr/bin/env python3
"""capture_serial.py —— 抓板卡完整串口日志（含 FSBL/U-Boot），并容忍拔插。

为什么需要它：冷启动"小核没被释放"的定性证据在**开机最开头那几行**——
FSBL 的 `C2S/…`（从 FIP 读到的加载/运行地址与大小）、`blcp_2nd_cksum`（镜像校验）、
`RSC.` / `C2E.`（有没有真的复位释放小核）。这些行只在通电那一刻出现一次，
而冷启动要求"拔掉除 TTL 以外的所有外接"，TTL 转接器也可能被一起拔掉。
所以抓取脚本会**在端口消失时继续重试**，而不是退出。

用法：
    ./capture_serial.py --seconds 180                  # 抓 3 分钟
    ./capture_serial.py --log /tmp/cold.log --seconds 300
    ./capture_serial.py --dev /dev/ttyUSB1             # 换板子

抓完 grep 这几条：
    grep -a -e C2S -e C2E -e RSC -e blcp_2nd_cksum -e "No C906L" <log>
"""

import argparse
import datetime
import sys
import time

import serial

from sg2002_serial import default_serial_port

DEFAULT_LOG = "/tmp/sg2002-serial-capture.log"


def stamp() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def mark(log, text: str) -> None:
    """写一条抓取侧的事件标记（与板子打印的内容区分开）。"""
    line = f"\n--- [host] {stamp()} {text}\n"
    log.write(line.encode())
    log.flush()
    sys.stderr.write(line)
    sys.stderr.flush()


def main() -> int:
    ap = argparse.ArgumentParser(description="抓板卡串口日志（容忍拔插）")
    ap.add_argument("--dev", "--port", dest="dev", default=default_serial_port(),
                    help="串口设备（默认 $SG2002_PORT 或 /dev/ttyUSB0）")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--log", default=DEFAULT_LOG)
    ap.add_argument("--seconds", type=float, default=180.0, help="总抓取时长（秒）")
    ap.add_argument("--idle-exit", type=float, default=0.0,
                    help="连续这么久没有任何字节就提前退出（0 = 不启用）")
    ap.add_argument("--stamp-lines", action="store_true",
                    help="给每一行加主机时间戳（[+秒] 前缀）——算「上电→shell」这类整段指标用；"
                         "板子自己的内核日志时间戳只从内核启动开始计时，两者不能混用")
    args = ap.parse_args()

    deadline = time.monotonic() + args.seconds
    last_byte = time.monotonic()
    with open(args.log, "ab") as log:
        mark(log, f"开始抓取 {args.dev} @ {args.baud} 8N1，日志 {args.log}")
        last_error = None
        while time.monotonic() < deadline:
            try:
                port = serial.Serial(args.dev, args.baud, timeout=1.0)
            except (OSError, serial.SerialException) as exc:
                err = str(exc)
                if "No such file" in err or "could not open" in err or "Permission" in err:
                    if err != last_error:
                        hint = ""
                        if "Permission" in err:
                            hint = ("（重插后 udev 会把权限复位成 root:uucp 660；"
                                    "当前用户不在 uucp 组时先 chmod 666）")
                        mark(log, f"端口不可用（{err}）{hint}，继续重试")
                        last_error = err
                    time.sleep(1.0)
                    continue
                mark(log, f"打开失败：{err}")
                return 2
            last_error = None
            mark(log, "端口已打开，开始记录")
            t_start = time.monotonic()
            residual = b""
            try:
                while time.monotonic() < deadline:
                    chunk = port.read(4096)
                    if chunk:
                        if args.stamp_lines:
                            residual += chunk
                            while b"\n" in residual:
                                line, residual = residual.split(b"\n", 1)
                                ts = time.monotonic() - t_start
                                log.write(b"[+%9.3f] " % ts + line.rstrip(b"\r") + b"\n")
                        else:
                            log.write(chunk)
                        log.flush()
                        last_byte = time.monotonic()
                    elif args.idle_exit and time.monotonic() - last_byte > args.idle_exit:
                        mark(log, f"空闲 {args.idle_exit} 秒，提前结束")
                        return 0
            except (OSError, serial.SerialException) as exc:
                mark(log, f"读取中断：{exc}（重试）")
            finally:
                try:
                    port.close()
                except Exception:  # noqa: BLE001
                    pass
        mark(log, "到时结束")
    return 0


if __name__ == "__main__":
    sys.exit(main())
