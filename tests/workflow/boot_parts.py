#!/usr/bin/env python3
"""boot_parts.py —— 抓 U-Boot 提示符，把 /boot 下的分片按序 fatload 成连续内存再 bootm。

为什么要把 FIT 切片：当板内文件系统对单文件写入有上限时（例如页缓存上限较小，
从板内往 /boot 写超过 ~2 MiB 的单文件会被截断），更新内核就得走
"宿主机切片 → 板内 /boot → U-Boot 拼装"这条路：U-Boot 的 fatload 没有这个限制。

用法：
    ./boot_parts.py p16/parts/p16_ 16 90          # 前缀、片数、bootm 后观察秒数
    ./boot_parts.py p16/parts/p16_ 16 90 --dev /dev/ttyUSB1
"""

import argparse
import sys
import time

import serial

from sg2002_serial import default_serial_port

BASE = 0x81800000
STEP = 0x100000
CONFIG = "config-sg2002_licheervnano_sd"
PROMPT_UBOOT = b"soph#"
PROMPT_SHELL = b"root@starry:/root #"


def main() -> int:
    ap = argparse.ArgumentParser(description="分片 fatload + bootm")
    ap.add_argument("prefix", nargs="?", default="parts/p", help="板内分片路径前缀（末尾带下划线/分隔）")
    ap.add_argument("count", nargs="?", type=int, default=16, help="分片数")
    ap.add_argument("observe", nargs="?", type=float, default=90.0, help="bootm 后观察秒数")
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--log", default="/tmp/boot_parts.log")
    args = ap.parse_args()

    log = open(args.log, "wb")
    p = serial.Serial(args.dev, args.baud, timeout=0.3)
    t0 = time.monotonic()

    def pump(deadline, want):
        """读到 want（缓冲区末尾）为止，顺带把内容写进日志。"""
        buf = b""
        while time.monotonic() < deadline:
            chunk = p.read(4096)
            if not chunk:
                continue
            buf += chunk
            log.write(chunk)
            log.flush()
            if buf.rstrip().endswith(want):
                return True
            if len(buf) > 1 << 20:
                buf = buf[-4096:]
        return False

    try:
        # 1) 抢提示符：上电后 U-Boot 会自己跑，这里连发 Ctrl+C 把它截住。
        got = False
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            p.write(b"\x03")
            if pump(time.monotonic() + 1.0, PROMPT_UBOOT):
                got = True
                break
        print(f"[boot] 抓到 U-Boot 提示符: {got}", flush=True)
        if not got:
            return 1

        # 2) 分片 fatload：一次发 4 条，控制在 U-Boot 的输入行长度以内。
        for start in range(0, args.count, 4):
            cmds = []
            for index in range(start, min(start + 4, args.count)):
                addr = BASE + index * STEP
                cmds.append(f"fatload mmc 0 {addr:#x} {args.prefix}{index:02d}")
            line = " ; ".join(cmds)
            print(f"[boot] {line}", flush=True)
            p.write(line.encode() + b"\r")
            if not pump(time.monotonic() + 60, PROMPT_UBOOT):
                print("[boot] fatload 超时", flush=True)
                return 1

        # 3) bootm
        cmd = f"bootm {BASE:#x}#{CONFIG}"
        print(f"[boot] {cmd}", flush=True)
        log.write(f"### {cmd}\n".encode())
        p.write(cmd.encode() + b"\r")
        ok = pump(time.monotonic() + args.observe, PROMPT_SHELL)
        print(f"[boot] shell={'ok' if ok else 'timeout'} t={time.monotonic() - t0:.1f}s", flush=True)
        print(f"log: {args.log}")
        return 0 if ok else 1
    finally:
        p.close()
        log.close()


if __name__ == "__main__":
    sys.exit(main())
