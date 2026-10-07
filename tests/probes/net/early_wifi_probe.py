#!/usr/bin/env python3
"""early_wifi_probe.py —— boot 一个 FIT，然后在 shell 一出现就立刻连 WiFi。

为什么需要它：板子上的 `/root/boot_net_up.sh` 有 90 s 闸门（躲 AIC 异步启动期间
的 `Busy`）。要验证"内核侧已经敢在启动窗口里发控制请求"，就必须在 uptime 还很小
的时候动手，而"发 bootm"和"发 wifi_switch"必须在同一个串口会话里做。

用法： python3 early_wifi_probe.py <FIT 名> [boot 后等待提示符秒数] [--dev /dev/ttyUSB0]
"""

import os
import sys
import time

import serial


def _default_port() -> str:
    override = os.environ.get("SG2002_PORT")
    if override:
        return override
    return "/dev/ttyUSB0"


BAUD = 115200
UBOOT = b"soph#"
SHELL = b"root@starry:/root #"


def wait_for(port, token: bytes, timeout: float) -> tuple[bool, bytes]:
    """Waits until the token appears at the *end* of the stream.

    U-Boot/ash echo the command line, and that echo starts with the prompt, so
    a naive "token somewhere in the buffer" test returns before the command has
    even run (this cost us one bogus hang diagnosis).  Require the prompt to be
    the last thing received, like `serial_cmd.py` does.
    """
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = port.read(4096)
        if chunk:
            buf += chunk
            if buf.rstrip().endswith(token):
                return True, buf
    return False, buf


def main() -> int:
    args = sys.argv[1:]
    dev = _default_port()
    if "--dev" in args:
        i = args.index("--dev")
        dev = args[i + 1]
        del args[i:i + 2]
    fit = args[0] if len(args) > 0 else "starry-wififix.sd"
    boot_timeout = float(args[1]) if len(args) > 1 else 120.0

    port = serial.Serial(dev, BAUD, timeout=0.3)
    try:
        # Drain whatever U-Boot left on the console and settle on a clean
        # prompt first.  `boot_probe.py` (the tool that reliably works) does the
        # same; skipping it left the line editor confused.
        port.write(b"\r")
        wait_for(port, UBOOT, 40)

        # Use a bare CR as the line terminator, exactly like `boot_probe.py`.
        # A CRLF leaves a stray byte behind at the moment the kernel takes over
        # the UART.
        port.write(f"fatload mmc 0 0x81800000 {fit}\r".encode())
        ok, buf = wait_for(port, UBOOT, 120)
        print(f"[probe] fatload ok={ok}")
        if not ok:
            print(buf.decode(errors="replace")[-800:])
            return 1

        started = time.time()
        port.write(b"bootm 0x81800000#config-sg2002_licheervnano_sd\r")
        ok, buf = wait_for(port, SHELL, boot_timeout)
        print(f"[probe] shell ready={ok} after {time.time() - started:.1f}s")
        if not ok:
            print(buf.decode(errors="replace")[-2000:])
            return 1

        # Uptime is the number we care about: it must be well under the 90 s
        # gate for this to prove anything.
        port.write(b"cat /proc/uptime\r")
        _, up = wait_for(port, SHELL, 15)
        print("[probe] uptime:", up.decode(errors="replace").strip().splitlines()[-2:])

        port.write(b"/root/wifi_switch sta test 12345678; echo WIFI_RC=$?\r")
        ok, buf = wait_for(port, SHELL, 180)
        text = buf.decode(errors="replace")
        print("[probe] association output:")
        print(text[-2500:])

        port.write(b"sleep 6; ifconfig wlan0 | head -4\r")
        _, buf = wait_for(port, SHELL, 30)
        print("[probe] final state:")
        print(buf.decode(errors="replace")[-1200:])
        return 0
    finally:
        port.close()


if __name__ == "__main__":
    sys.exit(main())
