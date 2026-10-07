#!/usr/bin/env python3
"""vdec_poison.py —— 通过 /dev/cvi_vc_dec0 给 JPU 喂坏码流，制造一次真实解码失败。

用途：验证"JPU 出错后能否在同一 boot 内恢复"。流程：
  1) 从 /dev/cvi-usb-camera0 取一帧真实 MJPEG（cmd3，不经过 JPU）；
  2) 按 mode 做破坏：base=原样 / ecs=熵数据置为 0xA5 / sof=采样因子改成 4:2:0 / both；
  3) 经 vdec 通道 SEND_STREAM 送进去，打印返回值；
  4) DESTROY_CHN 释放 vdec 独占，让摄像头的 cmd4 能接着用。

用法（板上）：python3 /root/vdec_poison.py <base|ecs|sof|both>
"""

import ctypes
import fcntl
import os
import sys

CAM = "/dev/cvi-usb-camera0"
VDEC = "/dev/cvi_vc_dec0"

GET_FRAME = 3

VDEC_IOCTL = lambda n: (ord("V") << 8) | n  # noqa: E731
CREATE_CHN = VDEC_IOCTL(47)
DESTROY_CHN = VDEC_IOCTL(48)
START_RECV_STREAM = VDEC_IOCTL(51)
SET_CHN_PARAM = VDEC_IOCTL(55)
SEND_STREAM = VDEC_IOCTL(57)

PT_JPEG = 26
VIDEO_MODE_FRAME = 1
PIXEL_FORMAT_YUV_PLANAR_420 = 13


class VdecChnAttr(ctypes.Structure):
    _fields_ = [
        ("payload_type", ctypes.c_int32),
        ("video_mode", ctypes.c_int32),
        ("picture_width", ctypes.c_uint32),
        ("picture_height", ctypes.c_uint32),
        ("stream_buffer_size", ctypes.c_uint32),
        ("frame_buffer_size", ctypes.c_uint32),
        ("frame_buffer_count", ctypes.c_uint32),
        ("video_attr", ctypes.c_uint32 * 3),
    ]


class VdecChnParam(ctypes.Structure):
    _fields_ = [
        ("payload_type", ctypes.c_int32),
        ("pixel_format", ctypes.c_int32),
        ("display_frame_count", ctypes.c_uint32),
        ("codec_param", ctypes.c_uint32 * 5),
    ]


class VdecStream(ctypes.Structure):
    _fields_ = [
        ("length", ctypes.c_uint32),
        ("_pad0", ctypes.c_uint8 * 4),
        ("pts", ctypes.c_uint64),
        ("end_of_frame", ctypes.c_uint8),
        ("end_of_stream", ctypes.c_uint8),
        ("display", ctypes.c_uint8),
        ("_pad1", ctypes.c_uint8 * 5),
        ("address", ctypes.c_uint64),
    ]


class VdecStreamEx(ctypes.Structure):
    _fields_ = [
        ("stream", ctypes.c_uint64),
        ("timeout_ms", ctypes.c_int32),
        ("_pad", ctypes.c_uint8 * 4),
    ]


def grab_jpeg() -> bytes:
    fd = os.open(CAM, os.O_RDWR)
    try:
        fcntl.ioctl(fd, 1, 0)  # INIT
        buf = bytearray(1 << 20)
        size = fcntl.ioctl(fd, GET_FRAME, buf)
        return bytes(buf[:size])
    finally:
        os.close(fd)


def scan_markers(jpeg: bytes):
    """返回 (SOF0 偏移, SOS 偏移)，都按标记段长度正向走，避免误判 ECS 里的伪标记。"""
    sof = sos = None
    i = 2
    while i + 4 <= len(jpeg):
        if jpeg[i] != 0xFF:
            i += 1
            continue
        marker = jpeg[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        seg_len = (jpeg[i + 2] << 8) | jpeg[i + 3]
        if marker == 0xC0 and sof is None:
            sof = i
        if marker == 0xDA:
            sos = i
            break
        i += 2 + seg_len
    return sof, sos


def damage(jpeg: bytes, mode: str) -> bytes:
    data = bytearray(jpeg)
    sof, sos = scan_markers(data)
    if mode in ("sof", "both"):
        if sof is None:
            raise SystemExit("找不到 SOF0")
        ncomp = data[sof + 9]
        # 解析器只认色度 (1,1)，格式由亮度采样决定：Y=2x2 -> 4:2:0。
        # 相机是 4:2:2（Y=2x1），把亮度竖直采样从 1 改成 2 就"声明"成 4:2:0，
        # 熵数据却仍是按 4:2:2 编的 —— 正好用来逼 JPU 报错。
        for c in range(ncomp):
            data[sof + 10 + 3 * c + 1] = 0x22 if c == 0 else 0x11
        print(f"SOF@{sof}: components={ncomp} 亮度改为 0x22、色度 0x11（声明 4:2:0）")
    if mode in ("ecs", "both"):
        if sos is None:
            raise SystemExit("找不到 SOS")
        seg_len = (data[sos + 2] << 8) | data[sos + 3]
        start = sos + 2 + seg_len
        for i in range(start, len(data) - 2):
            data[i] = 0xA5
        print(f"SOS@{sos}: 熵数据 {len(data) - 2 - start} 字节置为 0xA5")
    return bytes(data)


def send(jpeg: bytes, width: int, height: int) -> str:
    fd = os.open(VDEC, os.O_RDWR)
    try:
        # 清掉上一次可能残留的通道，否则 vdec 独占会让摄像头的 cmd4 一直 EBUSY。
        try:
            fcntl.ioctl(fd, DESTROY_CHN, 0)
        except OSError:
            pass
        attr = VdecChnAttr(
            payload_type=PT_JPEG,
            video_mode=VIDEO_MODE_FRAME,
            picture_width=width,
            picture_height=height,
            stream_buffer_size=4 << 20,
            frame_buffer_size=4 << 20,
            frame_buffer_count=1,
            video_attr=(ctypes.c_uint32 * 3)(0, 0, 0),
        )
        try:
            fcntl.ioctl(fd, CREATE_CHN, attr)
        except OSError as err:
            return f"CREATE errno={err.errno}({os.strerror(err.errno)})"
        param = VdecChnParam(
            payload_type=PT_JPEG,
            pixel_format=PIXEL_FORMAT_YUV_PLANAR_420,
            display_frame_count=0,
            codec_param=(ctypes.c_uint32 * 5)(0, 0, 0, 0, 0),
        )
        fcntl.ioctl(fd, SET_CHN_PARAM, param)
        fcntl.ioctl(fd, START_RECV_STREAM, 0)

        blob = ctypes.create_string_buffer(jpeg, len(jpeg))
        stream = VdecStream(
            length=len(jpeg),
            pts=1,
            end_of_frame=1,
            end_of_stream=0,
            display=1,
            address=ctypes.addressof(blob),
        )
        stream_ex = VdecStreamEx(
            stream=ctypes.addressof(stream),
            timeout_ms=0,
            _pad=(ctypes.c_uint8 * 4)(0, 0, 0, 0),
        )
        try:
            fcntl.ioctl(fd, SEND_STREAM, stream_ex)
            outcome = "SEND ok"
        except OSError as err:
            outcome = f"SEND errno={err.errno}({os.strerror(err.errno)})"
        try:
            fcntl.ioctl(fd, DESTROY_CHN, 0)
        except OSError as err:
            outcome += f" | DESTROY errno={err.errno}"
        return outcome
    finally:
        os.close(fd)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "base"
    jpeg = grab_jpeg()
    print(f"取帧 {len(jpeg)} 字节，mode={mode}")
    bad = damage(jpeg, mode)
    print("送入 vdec:", send(bad, 640, 480))
    return 0


if __name__ == "__main__":
    sys.exit(main())
