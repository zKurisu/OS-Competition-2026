#!/usr/bin/env python3
"""sg2002_cmd.py —— 在板卡串口上跑一条命令，并把输出过滤干净。

用法：
    ./sg2002_cmd.py 'cat /proc/uptime'
    ./sg2002_cmd.py './cmdqu_test uart-stats' --timeout 30
    ./sg2002_cmd.py 'run bootos' --prompt uboot --timeout 90
    ./sg2002_cmd.py --break                 # 给 U-Boot 的 ums 发 Ctrl+C
    ./sg2002_cmd.py --raw 'dmesg | tail'    # 不过滤内核日志
    ./sg2002_cmd.py --list                  # 列出候选串口

为什么不用交互式终端：长时间会话里宿主机的读线程可能卡住（表现为"再也收不到
任何字节"，但板子是好的）。本脚本每次独立开关串口，状态最干净，适合脚本化实验。
"""

import argparse
import sys

from sg2002_serial import BoardLink, PROMPT_CORE, candidate_ports, default_serial_port


def main() -> int:
    ap = argparse.ArgumentParser(description="在板卡串口上跑一条命令")
    ap.add_argument("command", nargs="?", default="", help="要执行的命令；--break 可省略")
    ap.add_argument("--dev", default=default_serial_port(), help="串口设备（默认 $SG2002_PORT 或 /dev/ttyUSB0）")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--prompt", choices=sorted(PROMPT_CORE), default="shell")
    ap.add_argument("--timeout", type=float, default=25.0, help="等到提示符出现的最长秒数")
    ap.add_argument("--settle", type=float, default=0.4, help="看到提示符后再多读一会儿")
    ap.add_argument("--raw", action="store_true", help="不过滤内核日志")
    ap.add_argument("--no-cd-root", action="store_true", help="不先 cd /root（默认会先 cd，避开提示符带 cwd）")
    ap.add_argument("--break", dest="send_break", action="store_true",
                    help="改发 Ctrl+C（中断 U-Boot 的 ums 这类前台命令）")
    ap.add_argument("--list", action="store_true", help="列出候选串口后退出")
    args = ap.parse_args()

    if args.list:
        for path in candidate_ports():
            print(path)
        return 0

    with BoardLink(args.dev, args.baud) as link:
        if args.send_break:
            link.send_break()
            return 0
        print(link.send(
            args.command,
            prompt=args.prompt,
            timeout=args.timeout,
            settle=args.settle,
            raw=args.raw,
            cd_root=not args.no_cd_root,
        ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
