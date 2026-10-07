#!/usr/bin/env python3
"""linux_cmd.py —— 在**已经登录**的厂商 Linux shell 上跑命令。

约定：命令里带 `echo __DONE__`，脚本只认行首的标记（命令行回显里也含 `__DONE__`，
不能直接匹配子串）。板子不要重启，会话就一直有效。

用法：
    ./linux_cmd.py 'uname -a; echo __DONE__'
    ./linux_cmd.py --dev /dev/ttyUSB1 'ls /root; echo __DONE__'
"""

import argparse
import re
import sys
import time

import serial

from sg2002_serial import default_serial_port


def main() -> int:
    ap = argparse.ArgumentParser(description="在已登录的厂商 Linux shell 上跑命令")
    ap.add_argument("command", nargs="?", default="echo __DONE__")
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=1500.0)
    args = ap.parse_args()

    with serial.Serial(args.dev, args.baud, timeout=0.5) as port:
        # 先唤醒：把提示符钓出来（也顺便确认 shell 还活着）
        for _ in range(3):
            port.write(b"\r")
            end = time.time() + 2
            out = b""
            while time.time() < end:
                chunk = port.read(4096)
                if chunk:
                    out += chunk
            if re.search(rb"[#$] ", out):
                break
        else:
            print("[cmd] shell 没回应（会话可能已断，需要重新登录）", flush=True)
            return 2

        port.write(args.command.encode() + b"\r")
        deadline = time.time() + args.timeout
        buf = b""
        while time.time() < deadline:
            chunk = port.read(4096)
            if chunk:
                buf += chunk
                sys.stdout.write(chunk.decode("utf-8", "replace"))
                sys.stdout.flush()
                # 只认"行首的"标记：命令回显里也含 __DONE__，不能直接匹配子串
                if re.search(rb"\n__DONE__", buf):
                    break
        print("\n[cmd] 结束", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
