#!/usr/bin/env python3
"""boot_timing.py —— 从 boot_probe.py / capture_serial.py --stamp-lines 的日志里
算"上电/复位 → U-Boot → 内核 → shell"的分段耗时（报告 §08 TTFI 的 SG2002 版口径）。

口径说明：
  * 只统计**最后一个 `### bootm` 标记之后**的行——同一次抓取里往往还包含
    "复位前旧内核"的输出，不排除会把时序算反（实测踩过）；
  * `uboot` 横幅允许缺省（从已有 U-Boot 直接 bootm 时日志里没有横幅），
    此时以 `kernel` 作为第一段；
  * 行首时间戳是**主机**时间（相对抓取开始），板子内核自己的 `[ 16.09 …]`
    是从内核启动起算，两者不能混用。

用法： ./boot_timing.py /tmp/boot_probe.log
"""

import re
import sys
from pathlib import Path

STAMP = re.compile(rb"^\[\+\s*([0-9]+(?:\.[0-9]+)?)\]\s?(.*)$")
UBOOT = re.compile(rb"U-Boot 20[0-9]{2}\.")
KERNEL = re.compile(rb"\[\s*[0-9]+\.[0-9]+\s+[0-9]+:.*(starry|arceos|ax_)")
USERSPACE = re.compile(rb"(init: |sshd\[|boot_net_up|Entering runlevel|Starting syslogd|Welcome to)")
SHELL = re.compile(rb"(root@starry:/root #|~ #)")
PATS = {"uboot": UBOOT, "kernel": KERNEL, "userspace": USERSPACE, "shell": SHELL}
ORDER = ["uboot", "kernel", "userspace", "shell"]


def parse(path: Path) -> dict:
    lines = path.read_bytes().split(b"\n")
    start = 0
    for idx, raw in enumerate(lines):
        if b"### bootm" in raw:
            start = idx + 1

    marks: dict[str, float] = {}
    skip: set[str] = set()
    for raw in lines[start:]:
        m = STAMP.match(raw)
        if not m:
            continue
        ts = float(m.group(1))
        line = m.group(2)
        key = next((k for k in ORDER if k not in marks and k not in skip), None)
        if key is None:
            break
        if key == "uboot" and not UBOOT.search(line):
            # 没有横幅：允许直接以更后面的段作为第一段
            for later in ("kernel", "userspace", "shell"):
                if PATS[later].search(line):
                    skip.add("uboot")
                    marks[later] = ts
                    break
            continue
        if PATS[key].search(line):
            marks[key] = ts
    return marks


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"找不到日志 {path}")
        return 2
    marks = parse(path)
    if not marks:
        print("日志里没有可用时间戳行（请用 boot_probe.py 或 capture_serial.py --stamp-lines 抓取）")
        return 1
    print("== 启动分段（主机时间戳，秒；口径=最后一个 ### bootm 之后） ==")
    prev = None
    for key in ORDER:
        if key not in marks:
            print(f"  {key:<10} 未捕获")
            continue
        ts = marks[key]
        delta = f"  (+{ts - prev:.3f})" if prev is not None else ""
        print(f"  {key:<10} t={ts:8.3f}{delta}")
        prev = ts
    keys = [k for k in ORDER if k in marks]
    if len(keys) >= 2:
        print(f"  合计       {marks[keys[-1]] - marks[keys[0]]:.3f} s"
              f"（{keys[0]} → {keys[-1]}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
