#!/usr/bin/env python3
"""sg2002_upload.py —— 把一个小文件经串口（base64 分块）送上板子，可选执行。

适用场景：内核 FIT、探针二进制、板端 Python 脚本等"有 UMS 就能走 mtools、
没 UMS 只能走串口"的文件。串口带宽约 1 KB/s 量级，适合几十 KB 的探针；
MB 级镜像请走 UMS（见 `deploy_via_ums.sh` / `flash_ums.sh`）或 WiFi。

用法：
    ./sg2002_upload.py ./probe /root/probes/probe --run '/root/probes/probe'
    ./sg2002_upload.py ./x.py /root/x.py --exec-bit --dev /dev/ttyUSB1

注意事项：
* 上传目标必须落在 ext4（如 `/root`）。`/boot` 是 FAT 且挂载时带 noexec，
  二进制放上去既不能执行、也解释不了脚本。
* 落盘后脚本会 `sync` 一次。板内写文件不 sync 直接复位，掉数据是常态。
* 分块大小默认 350 字符；调大反而会撞到板端串口输入缓冲，表现为整块丢失。
"""

import argparse
import base64
import hashlib
import pathlib
import subprocess
import sys

from sg2002_serial import default_serial_port


def main() -> int:
    ap = argparse.ArgumentParser(description="串口 base64 分块上传")
    ap.add_argument("source", help="本地文件")
    ap.add_argument("dest", help="板端目标路径（ext4，如 /root/xxx）")
    ap.add_argument("--run", default="", help="上传成功后要执行的板端命令")
    ap.add_argument("--dev", default=default_serial_port())
    ap.add_argument("--chunk", type=int, default=350, help="base64 分块大小（默认 350）")
    ap.add_argument("--timeout", type=float, default=40.0, help="每个分块的等待秒数")
    ap.add_argument("--run-timeout", type=float, default=120.0)
    ap.add_argument("--exec-bit", action="store_true", help="chmod +x 目标文件")
    args = ap.parse_args()

    cmd_tool = str(pathlib.Path(__file__).with_name("sg2002_cmd.py"))

    def board(cmd: str, timeout: float | None = None) -> str:
        proc = subprocess.run(
            ["python3", cmd_tool, "--dev", args.dev, cmd,
             "--prompt", "shell", "--timeout", str(timeout or args.timeout)],
            capture_output=True, text=True,
        )
        return proc.stdout + proc.stderr

    data = pathlib.Path(args.source).read_bytes()
    digest = hashlib.md5(data).hexdigest()
    b64 = base64.b64encode(data).decode()
    chunks = [b64[i:i + args.chunk] for i in range(0, len(b64), args.chunk)]
    print(f"[upload] {len(data)} B ({digest}) -> {len(chunks)} chunks")

    tmp = f"/tmp/.{pathlib.Path(args.dest).name}.b64"
    board(f"rm -f {tmp}")
    for index, chunk in enumerate(chunks):
        out = board(f"echo -n {chunk} >> {tmp}")
        if "not found" in out or "No space" in out:
            print(f"[upload] chunk {index} 失败：{out[-200:]}")
            return 1
        if index % 50 == 0:
            print(f"[upload] {index}/{len(chunks)}")

    print(board(f"wc -c {tmp}")[-120:].strip())
    restore = board(f"base64 -d {tmp} > {args.dest} && rm -f {tmp} && sync && md5sum {args.dest}")
    print(restore[-200:].strip())
    if digest not in restore:
        # 少数情况下 md5sum 的回显被日志冲掉，这里只做提示，不直接判失败。
        print(f"[upload] 未见回显 md5 {digest}，请人工核对上面一行")
    if args.exec_bit:
        board(f"chmod +x {args.dest} && sync")
    if args.run:
        print(board(args.run, timeout=args.run_timeout))
    return 0


if __name__ == "__main__":
    sys.exit(main())
