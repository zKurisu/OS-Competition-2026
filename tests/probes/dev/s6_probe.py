#!/usr/bin/env python3
"""s6_probe.py —— 在板上精确记录 cmd4（JPU 解码）逐次成败，用于定位 JPU 卡死点。

用法（板上）：python3 /root/s6_probe.py yuv 40 | raw 20 | reset
输出：INIT 结果 + 每次调用的成败序列（O=成功，数字=errno）+ 汇总
"""

import fcntl
import os
import sys
import time

DEV = "/dev/cvi-usb-camera0"
INIT, GET_INFO, GET_FRAME, GET_YUV, HARD_RESET = 1, 2, 3, 4, 5


def run(mode: str, count: int) -> None:
    fd = os.open(DEV, os.O_RDWR)
    try:
        try:
            fcntl.ioctl(fd, INIT, 0)
            print("INIT rc=0", flush=True)
        except OSError as err:
            print(f"INIT errno={err.errno}", flush=True)
            return
        if mode == "reset":
            try:
                fcntl.ioctl(fd, HARD_RESET, 0)
                print("HARD_RESET rc=0", flush=True)
            except OSError as err:
                print(f"HARD_RESET errno={err.errno}", flush=True)
            return
        cmd = GET_FRAME if mode == "raw" else GET_YUV
        buf = bytearray(1 << 20)
        seq = []
        t0 = time.time()
        for _ in range(count):
            try:
                fcntl.ioctl(fd, cmd, buf)
                seq.append("O")
            except OSError as err:
                seq.append(str(err.errno))
        print("SEQ " + "".join(seq), flush=True)
        print(
            f"ok={seq.count('O')}/{count} elapsed={time.time() - t0:.2f}s",
            flush=True,
        )
    finally:
        os.close(fd)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    run(sys.argv[1], count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
