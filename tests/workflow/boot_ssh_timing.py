#!/usr/bin/env python3
"""boot_ssh_timing.py —— 量「bootm → SSH 可用」的总时间（板子的真实可用性）。

口径：从 U-Boot 收到 `bootm` 那一刻算起，到宿主机能成功跑一次
`ssh root@<ip> true` 为止。这一步覆盖内核启动、init、自启脚本连 WiFi、DHCP 拿地址、
sshd 起来——也就是"拔了串口之后多久能远程用上板子"。

用法：
    ./boot_ssh_timing.py starry-final.sd 192.168.43.158 300
    ./boot_ssh_timing.py --fit starry.sd --ip 10.42.0.2 --dev /dev/ttyUSB1
"""

import argparse
import subprocess
import sys
import time

import serial

from sg2002_serial import default_serial_port

UBOOT = b"soph#"


def wait_for(port, token: bytes, timeout: float) -> bytes:
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = port.read(4096)
        if chunk:
            buf += chunk
            if buf.rstrip().endswith(token):
                return buf
    return buf


def ssh_ok(ip: str) -> bool:
    return (
        subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3",
             "-o", "StrictHostKeyChecking=no", f"root@{ip}", "true"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="bootm → SSH 可用 的总耗时")
    ap.add_argument("fit_pos", nargs="?", help="FAT 分区里的 FIT 名")
    ap.add_argument("ip_pos", nargs="?", help="板子 IP")
    ap.add_argument("timeout_pos", nargs="?", type=float, help="超时秒数")
    ap.add_argument("--fit", default=None)
    ap.add_argument("--ip", default=None)
    ap.add_argument("--timeout", type=float, default=None)
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--baud", type=int, default=115200)
    args = ap.parse_args()

    fit = args.fit or args.fit_pos or "starry-final.sd"
    ip = args.ip or args.ip_pos or "192.168.43.158"
    timeout = args.timeout or args.timeout_pos or 300.0

    port = serial.Serial(args.dev, args.baud, timeout=0.3)
    try:
        port.write(b"\r")
        wait_for(port, UBOOT, 40)
        port.write(f"fatload mmc 0 0x81800000 {fit}\r".encode())
        wait_for(port, UBOOT, 120)

        started = time.time()
        port.write(b"bootm 0x81800000#config-sg2002_licheervnano_sd\r")
        while time.time() - started < timeout:
            if ssh_ok(ip):
                elapsed = time.time() - started
                print(f"BOOT_SSH_READY fit={fit} ip={ip} seconds={elapsed:.1f}")
                return 0
            time.sleep(2)
        print(f"BOOT_SSH_TIMEOUT fit={fit} ip={ip} after={time.time() - started:.1f}s")
        return 1
    finally:
        port.close()


if __name__ == "__main__":
    sys.exit(main())
