#!/usr/bin/env python3
"""boot_probe.py —— 在 U-Boot 上执行 fatload+bootm，并给整段输出打主机时间戳。

为什么需要它：串口同一时刻只能被一个进程占用，所以"发命令"和"逐行记录"必须在
同一个进程里做；而 U-Boot **回显的命令行里就含提示符**，按"缓冲区里出现过 soph#"
判断会提前返回（第一次实现就踩过这个坑）。这里要求提示符出现在**缓冲区末尾**。

用法：
    ./boot_probe.py starry-opt78.sd 120
    ./boot_probe.py linux.sd 120 --linux --log /tmp/boot-linux.log
    ./boot_probe.py starry.sd 90 --reset-from-starry    # 从 StarryOS 软复位回 U-Boot 再整段计时

产物：`[+秒] 行` 格式的日志（默认 /tmp/boot_probe.log），可直接喂 `boot_timing.py`。

`--linux`：抓厂商 Linux 启动（FIT 名给 linux.sd），"就绪"锚点由 StarryOS 的
`root@starry:/root #` 换成 Linux 的 `login:`——两边都用"`bootm` 回显 → 可交互提示符"
同一口径，才好在 TTFI 上对比。
"""

import argparse
import re
import sys
import time

import serial

from sg2002_serial import default_serial_port

ADDR = "0x81800000"
CONFIG = "config-sg2002_licheervnano_sd"
PROMPT_UBOOT = b"soph#"
PROMPT_SHELL = b"root@starry:/root #"

# 厂商 Linux：内核 loglevel=0 几乎不打印，但 busybox init 的 `INIT: ...` 与 getty 的
# `login:` 是直接写 console 的，一定看得见。所以用它做"用户态"和"就绪"锚点。
PATTERNS_STARRY = {
    "kernel": rb"\[\s*[0-9]+\.[0-9]+\s+[0-9]+:.*(starry|arceos|ax_)",
    "userspace": rb"(init: |sshd\[|boot_net_up|Entering runlevel|Starting syslogd|Welcome to)",
    "ready": rb"root@starry:/root #",
}
PATTERNS_LINUX = {
    "kernel": rb"\[\s*[0-9]+\.[0-9]+\]\s",   # loglevel=0 下大多被压掉，允许缺失
    "userspace": rb"(INIT: |Welcome to Linux|Starting |udhcpc|random: crng)",
    # getty 的提示符后面可能跟空格/光标控制码，不能用 `\s*$` 卡死。
    "ready": rb"login:",
}


def main() -> int:
    ap = argparse.ArgumentParser(description="U-Boot 引导 + 整段主机时间戳")
    ap.add_argument("fit", nargs="?", default="starry-final.sd", help="FAT 分区里的 FIT 文件名")
    ap.add_argument("observe", nargs="?", type=float, default=120.0, help="bootm 后观察秒数")
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--log", default="/tmp/boot_probe.log")
    ap.add_argument("--linux", action="store_true", help="抓厂商 Linux 启动（就绪锚点用 login:）")
    ap.add_argument("--reset-from-starry", action="store_true",
                    help="板子当前在 StarryOS：先 /root/c906l_kick reset 回 U-Boot，再整段计时")
    args = ap.parse_args()

    patterns = PATTERNS_LINUX if args.linux else PATTERNS_STARRY
    ready = PATTERNS_LINUX["ready"] if args.linux else PROMPT_SHELL
    log = open(args.log, "wb")
    p = serial.Serial(args.dev, args.baud, timeout=0.3)
    t0 = time.monotonic()
    residual = b""
    marks: dict[str, float] = {}

    def pump(deadline, stop_at=None, pattern=None):
        """读到 stop_at（缓冲区末尾）或 pattern 出现；全程逐行打时间戳。"""
        nonlocal residual
        while time.monotonic() < deadline:
            chunk = p.read(4096)
            if not chunk:
                continue
            residual += chunk
            # shell 提示符不带换行，会一直留在残缓冲区；只看完整行会永远匹配不到，
            # 所以这里对残缓冲区也做一次匹配。
            for key, pat in patterns.items():
                if key not in marks and re.search(pat, residual):
                    marks[key] = time.monotonic() - t0
                    log.write(b"[+%9.3f] " % marks[key] + residual.strip() + b"\n")
                    log.flush()
                    residual = b""
                    if key == "ready" and pattern:
                        return True
            while b"\n" in residual:
                line, residual = residual.split(b"\n", 1)
                ts = time.monotonic() - t0
                log.write(b"[+%9.3f] " % ts + line.rstrip(b"\r") + b"\n")
                log.flush()
                for key, pat in patterns.items():
                    if key not in marks and re.search(pat, line):
                        marks[key] = ts
                if pattern and re.search(pattern, line):
                    return True
            if stop_at and residual.rstrip().endswith(stop_at):
                return True
        return False

    try:
        if args.reset_from_starry:
            # 板子当前在 StarryOS（我们内核带 c906l_kick）：先软复位回 U-Boot，
            # 这样一次运行就能给出「复位→shell」的整段耗时。
            p.write(b"\r")
            time.sleep(1.0)
            p.write(b"/root/c906l_kick reset\r")
            time.sleep(2.0)
        p.write(b"\r")
        pump(time.monotonic() + 40, stop_at=PROMPT_UBOOT)
        for cmd, stop in (
            (f"fatload mmc 0 {ADDR} {args.fit}", PROMPT_UBOOT),
            (f"bootm {ADDR}#{CONFIG}", ready),
        ):
            log.write(f"### {cmd}\n".encode())
            log.flush()
            if cmd.startswith("bootm"):
                # 复位前旧内核的提示符会被残缓冲区匹配到，先清标记，只统计这次 bootm 之后。
                marks.clear()
            p.write(cmd.encode() + b"\r")
            ok = pump(time.monotonic() + (30 if stop is PROMPT_UBOOT else args.observe), stop_at=stop)
            print(f"[probe] {cmd[:32]}… {'ok' if ok else 'timeout'}", flush=True)
            if stop is ready and ok:
                break
        print("marks:", {k: round(v, 3) for k, v in marks.items()})
        print(f"log: {args.log}")
    finally:
        p.close()
        log.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
