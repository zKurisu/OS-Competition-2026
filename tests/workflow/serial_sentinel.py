#!/usr/bin/env python3
"""serial_sentinel.py —— 用哨兵字符串在串口上跑命令，不依赖提示符。

背景：部分分支构建的内核在板上启动后 shell 不打印提示符，于是按提示符判定
命令结束的 `sg2002_cmd.py` 会一直等不到、被误判成挂死。这里把命令与 echo 哨兵
一起发出去，只等哨兵出现，因此对"提示符缺失/被日志冲掉"的固件也能用。

哨兵必须不出现在命令行回显里，否则会提前匹配：脚本把标记拆成两段拼出来，
回显里只有 `__S` 和 `IG_0__$?`，真正的 `__SIG_0__` 只在输出末尾出现。

用法：
    ./serial_sentinel.py 'cat /proc/uptime' 'ls /root'
    ./serial_sentinel.py --dev /dev/ttyUSB1 'dmesg | tail -20'
"""

import argparse
import sys
import time

import serial

from sg2002_serial import default_serial_port


def main() -> int:
    ap = argparse.ArgumentParser(description="哨兵式串口命令执行")
    ap.add_argument("commands", nargs="*", default=["echo HELLO"], help="要执行的命令")
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=900.0, help="单条命令等待上限（秒）")
    args = ap.parse_args()

    with serial.Serial(args.dev, args.baud, timeout=0.3) as port:
        port.write(b"\r")
        time.sleep(1.0)
        port.reset_input_buffer()
        for i, cmd in enumerate(args.commands):
            mark = "__SIG_%d__" % i
            head, tail = mark[:4], mark[4:]
            line = "%s; S=%s; echo ${S}%s$?" % (cmd, head, tail)
            port.write(line.encode() + b"\r")
            out = b""
            deadline = time.time() + args.timeout
            while time.time() < deadline:
                chunk = port.read(4096)
                if chunk:
                    out += chunk
                    if mark.encode() in out:
                        break
            print("--- [%s] ---" % cmd)
            print(out.decode("utf-8", "replace"))
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
