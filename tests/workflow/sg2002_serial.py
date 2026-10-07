#!/usr/bin/env python3
"""sg2002_serial.py —— SG2002 板卡串口通信库（提示符/哨兵判定、噪声过滤）。

本模块是 tests/workflow 下所有串口脚本的公共底座：`sg2002_cmd`、`sg2002_upload`、
`boot_probe`、`capture_serial`、`serial_sentinel`、`linux_cmd`、`linux_boot_run`
都通过它打开同一条链路，避免各自造轮子导致口径不一致。

为什么需要这层封装：

* **串口同一时刻只能被一个进程占用**。宿主机若同时挂两块板卡，脚本必须先确认
  自己打开的是哪一条链路，否则会读到另一块板子的输出。端口一律通过 `--dev`
  参数或 `SG2002_PORT` 环境变量显式指定，默认 `/dev/ttyUSB0`。
* **判"命令跑完"不能只找提示符子串**。U-Boot 会把命令本身（含提示符名）回显出来，
  于是"缓冲区里出现过 `soph#`"会在回显那一行就误判结束。本库的判据是提示符出现
  在**缓冲区末尾附近**，且发送前先清空残留缓冲。
* **提示符会带上当前目录**。StarryOS 的 shell 提示符是 `root@starry:/root #`，
  一旦在板上 `cd` 过就变成 `root@starry:/root/xxx #`，按固定串匹配会一直等不到。
  因此跑命令前脚本会先 `cd /root`（见 `BoardLink.run_shell`）。
* **内核日志噪声大**。每个用户态进程进出都会打一行 `starry_kernel::task::*`，
  ANSI 颜色转义也会混进输出；默认过滤这两类，`--raw` 可关闭过滤。

端口约定（可在 `--dev` / `SG2002_PORT` 中覆盖）：

    /dev/ttyUSB0                     默认（比赛用板）
    /dev/serial/by-path/...-0:2:...  USB 端口固定别名，拔插后路径不变
    SG2002_PORT=/dev/ttyUSB1         多板并存时显式区分
"""

from __future__ import annotations

import os
import re
import time

import serial

# 提示符核心串（不含结尾空格）。判定"命令结束"时要求它出现在缓冲区末尾。
PROMPT_CORE = {
    "shell": b"root@starry:/root #",
    "uboot": b"soph#",
    "linux": b"#",
}

# 用于人眼识别/过滤的提示符前缀（去掉输出里的提示符那一行）。
PROMPT_MARKERS = {
    "shell": ("root@starry",),
    "uboot": ("soph#",),
    "linux": ("login:", "Password:"),
}

ANSI = re.compile(rb"\x1b\[[0-9;]*[A-Za-z]")

# 内核日志里每进程一行的高频噪声；要看的 diag 日志（如 `[cmdqu] diag: …`）不在此列。
NOISE_SUBSTRINGS = ("starry_kernel::task::", "starry_kernel::syscall::")


def default_serial_port() -> str:
    """解析默认串口：`SG2002_PORT` > `/dev/ttyUSB0`。"""
    for key in ("SG2002_PORT", "SERIAL_PORT"):
        override = os.environ.get(key)
        if override:
            return override
    return "/dev/ttyUSB0"


def candidate_ports() -> list[str]:
    """列出当前可能属于 SG2002 的串口，供 `--list` 与排障使用。"""
    found: list[str] = []
    by_path = "/dev/serial/by-path"
    if os.path.isdir(by_path):
        for name in sorted(os.listdir(by_path)):
            if "usb" in name:
                found.append(os.path.join(by_path, name))
    for name in sorted(os.listdir("/dev")):
        if name.startswith("ttyUSB"):
            path = os.path.join("/dev", name)
            if path not in found:
                found.append(path)
    return found


def strip_noise(data: bytes, command: str = "", raw: bool = False) -> str:
    """把串口原始字节清洗成可读文本：去 ANSI、去回显行、去提示符行与内核噪声。"""
    text = ANSI.sub(b"", data).decode("utf-8", "replace")
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

    first = command.split()[0] if command.strip() else ""
    if lines and first and first in lines[0]:
        lines = lines[1:]  # 去掉板子回显的命令行
    if not raw:
        lines = [
            line
            for line in lines
            if not any(token in line for token in NOISE_SUBSTRINGS)
        ]
    lines = [line for line in lines if "root@starry" not in line and "soph#" not in line]
    return "\n".join(lines).strip("\n")


class BoardLink:
    """一条板卡串口链路的会话封装。"""

    def __init__(self, dev: str | None = None, baud: int = 115200):
        self.dev = dev or default_serial_port()
        self.baud = baud
        self.port = serial.Serial(self.dev, self.baud, timeout=0.3)

    def __enter__(self) -> "BoardLink":
        return self

    def __exit__(self, *_exc) -> None:
        self.close()

    def close(self) -> None:
        try:
            self.port.close()
        except Exception:  # noqa: BLE001 - 关闭失败不阻断收尾
            pass

    def _drain(self) -> None:
        """敲一个回车、清掉残留（半行输入 + 未读完的日志），保证后续读到的是本条命令的输出。"""
        self.port.write(b"\r\n")
        time.sleep(0.3)
        self.port.reset_input_buffer()

    def send(self, command: str, *, prompt: str = "shell", timeout: float = 25.0,
             settle: float = 0.4, raw: bool = False, cd_root: bool = True) -> str:
        """发一条命令并等提示符回来，返回清洗后的输出。

        `cd_root`：先 `cd /root`，绕开"提示符带 cwd"导致的匹配失败（默认开启）。
        """
        core = PROMPT_CORE[prompt]
        self.port.reset_input_buffer()
        self._drain()
        if cd_root and prompt == "shell":
            self.port.write(b"cd /root\r")
            time.sleep(0.15)
            self.port.reset_input_buffer()
        if command:
            self.port.write(command.encode() + b"\r")

        deadline = time.monotonic() + timeout
        buf = b""
        while time.monotonic() < deadline:
            buf += self.port.read(4096)
            if core in buf:
                time.sleep(settle)
                buf += self.port.read(65536)
                break
        return strip_noise(buf, command=command, raw=raw)

    def send_break(self) -> None:
        """改发 Ctrl+C，用于中断 U-Boot 的 `ums` 这类前台命令。"""
        self.port.reset_input_buffer()
        self._drain()
        self.port.write(b"\x03")
        time.sleep(0.3)

