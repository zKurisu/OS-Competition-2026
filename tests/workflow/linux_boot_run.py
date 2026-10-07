#!/usr/bin/env python3
"""linux_boot_run.py —— 一个进程里做完「U-Boot → 启动 Linux → 立刻登录 → 跑命令」。

为什么合成一个进程：这块板子的 getty 只在开机后很短一段时间里可用（登录超时
60 s 之后 init 会把它按 "respawning too fast" 停掉）。分两个脚本跑就会错过窗口，
所以从 `bootm` 到登录都在同一个进程里连做。

登录姿势（实测）：连续敲**两次** `root`，`Password:` 才出现，然后口令 `root`。

用法：
    ./linux_boot_run.py 'uname -a; id; echo __DONE__'
    ./linux_boot_run.py --fit linux.sd --dev /dev/ttyUSB1 '...; echo __DONE__'
"""

import argparse
import re
import sys
import time

import serial

from sg2002_serial import default_serial_port

ADDR = "0x81800000"
CONFIG = "config-sg2002_licheervnano_sd"
UBOOT = b"soph#"


def pump(port, secs, until=None, echo=False):
    """收 secs 秒；until 命中或缓冲区末尾出现 U-Boot 提示符则提前返回。"""
    end = time.time() + secs
    out = b""
    while time.time() < end:
        chunk = port.read(4096)
        if not chunk:
            continue
        out += chunk
        if echo:
            sys.stdout.write(chunk.decode("utf-8", "replace"))
            sys.stdout.flush()
        if until and re.search(until, out):
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="引导 Linux、登录并跑命令（单进程）")
    ap.add_argument("command", nargs="?", default="uname -a; id; echo __DONE__")
    ap.add_argument("--fit", default="linux.sd", help="FAT 分区里的 Linux FIT 名")
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--baud", type=int, default=115200)
    args = ap.parse_args()

    with serial.Serial(args.dev, args.baud, timeout=0.3) as port:
        port.write(b"\r")
        if not pump(port, 20, until=re.escape(UBOOT)):
            print("[boot] 没看到 U-Boot 提示符", flush=True)
            return 2
        print("[boot] 在 U-Boot", flush=True)

        for cmd in (f"fatload mmc 0 {ADDR} {args.fit}", f"bootm {ADDR}#{CONFIG}"):
            port.write(cmd.encode() + b"\r")
            if cmd.startswith("fatload"):
                pump(port, 40, until=re.escape(UBOOT))
                print("[boot] fatload 完成", flush=True)
            else:
                out = pump(port, 120, until=rb"login:")
                if b"login:" not in out:
                    print("[boot] 没等到 login 提示符，最后 400 字节：", flush=True)
                    print(out[-400:].decode("utf-8", "replace"), flush=True)
                    return 3
                print("[boot] 看到 login 提示符，立刻登录", flush=True)

        # 抢窗口：连敲两次 root，再送口令
        port.write(b"root\r")
        out = pump(port, 3)
        port.write(b"root\r")
        out += pump(port, 4)
        print("[login] " + repr(out[-200:]), flush=True)
        if b"assword" not in out:
            port.write(b"root\r")
            out = pump(port, 4)
            print("[login] 再试一次: " + repr(out[-200:]), flush=True)
        port.write(b"root\r")
        out = pump(port, 6, until=rb"[#$] ")
        print("[login] 口令后: " + repr(out[-200:]), flush=True)
        if not re.search(rb"[#$] ", out):
            print("[login] 失败", flush=True)
            return 4
        print("[login] OK，开始跑命令", flush=True)

        port.write(args.command.encode() + b"\r")
        pump(port, 1500, until=rb"__DONE__", echo=True)
        print("\n[run] 结束", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
