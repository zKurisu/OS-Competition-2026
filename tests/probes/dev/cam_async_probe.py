#!/usr/bin/env python3
"""cam_async_probe.py —— 验证 /dev/cvi-usb-camera0 的新 ioctl（6..13）。

覆盖：INIT / GET_INFO / START_ASYNC / GET_LATEST_FRAME / GET_CAPTURE_STATS /
      GET_LATEST_YUV_FRAME(Planar) / GET_LATEST_NV12_FRAME / RESET_CAPTURE_STATS /
      STOP_ASYNC / HARD_RESET
结构体布局照抄内核 src/pseudofs/dev/cvi_usb_camera.rs 的 repr(C) 定义。
"""

import ctypes
import fcntl
import os
import time

DEV = "/dev/cvi-usb-camera0"
INIT, GET_INFO, GET_FRAME, GET_YUV = 1, 2, 3, 4
HARD_RESET, START_ASYNC, STOP_ASYNC, GET_LATEST_FRAME = 5, 6, 7, 8
GET_CAPTURE_STATS, RESET_CAPTURE_STATS = 9, 10
GET_LATEST_YUV, GET_LATEST_NV12, GET_LATEST_YUV_ION = 11, 12, 13


class CameraInfo(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_uint16),
        ("height", ctypes.c_uint16),
        ("format", ctypes.c_uint8),
        ("connected", ctypes.c_uint8),
    ]


class CameraCaptureProfile(ctypes.Structure):
    _fields_ = [
        ("capabilities", ctypes.c_uint32),
        ("attempts", ctypes.c_uint32),
        ("frame_total_us", ctypes.c_uint64),
        ("uvc_total_us", ctypes.c_uint64),
        ("wait_first_packet_us", ctypes.c_uint64),
        ("usb_transfer_us", ctypes.c_uint64),
        ("jpeg_assemble_us", ctypes.c_uint64),
        ("validate_us", ctypes.c_uint64),
    ]


class CameraFrameRequest(ctypes.Structure):
    _fields_ = [
        ("buffer", ctypes.c_uint64),
        ("capacity", ctypes.c_uint64),
        ("last_sequence", ctypes.c_uint64),
        ("timeout_ms", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("sequence", ctypes.c_uint64),
        ("timestamp_ns", ctypes.c_uint64),
        ("length", ctypes.c_uint32),
        ("width", ctypes.c_uint16),
        ("height", ctypes.c_uint16),
        ("format", ctypes.c_uint8),
        ("reserved", ctypes.c_uint8 * 3),
        ("profile", CameraCaptureProfile),
    ]


class CameraCaptureStats(ctypes.Structure):
    _fields_ = [
        (name, ctypes.c_uint64)
        for name in (
            "capture_calls",
            "transfer_attempts",
            "successful_frames",
            "failed_frames",
            "retry_attempts",
            "invalid_frames",
            "invalid_soi",
            "invalid_eoi",
            "invalid_too_small",
            "usb_errors",
            "published_frames",
            "overwritten_frames",
            "total_frame_us",
            "max_frame_us",
        )
    ] + [("last_profile", CameraCaptureProfile)]


def call(fd, cmd, arg, name):
    try:
        ret = fcntl.ioctl(fd, cmd, arg)
        print(f"  ok   {name}: ret={ret}")
        return True
    except OSError as err:
        print(f"  FAIL {name}: errno={err.errno} ({os.strerror(err.errno)})")
        return False


def main() -> int:
    fd = os.open(DEV, os.O_RDWR)
    try:
        call(fd, INIT, 0, "INIT(1)")
        info = CameraInfo()
        if call(fd, GET_INFO, info, "GET_INFO(2)"):
            print(
                f"       info: {info.width}x{info.height} format={info.format} "
                f"connected={info.connected}"
            )

        if not call(fd, START_ASYNC, 0, "START_ASYNC(6)"):
            return 1
        time.sleep(1.5)

        jpeg = ctypes.create_string_buffer(1 << 20)
        request = CameraFrameRequest()
        request.buffer = ctypes.addressof(jpeg)
        request.capacity = len(jpeg)
        request.timeout_ms = 2000
        if call(fd, GET_LATEST_FRAME, request, "GET_LATEST_FRAME(8)"):
            head = bytes(jpeg.raw[:2])
            print(
                f"       seq={request.sequence} len={request.length} "
                f"{request.width}x{request.height} fmt={request.format} head={head.hex()}"
            )

        stats = CameraCaptureStats()
        if call(fd, GET_CAPTURE_STATS, stats, "GET_CAPTURE_STATS(9)"):
            print(
                f"       calls={stats.capture_calls} ok={stats.successful_frames} "
                f"failed={stats.failed_frames} published={stats.published_frames} "
                f"overwritten={stats.overwritten_frames}"
            )

        yuv = ctypes.create_string_buffer(1 << 20)
        request = CameraFrameRequest()
        request.buffer = ctypes.addressof(yuv)
        request.capacity = len(yuv)
        request.timeout_ms = 2000
        if call(fd, GET_LATEST_YUV, request, "GET_LATEST_YUV_FRAME(11)"):
            print(
                f"       len={request.length} {request.width}x{request.height} "
                f"fmt={request.format}（4:2:2 planar 应为 614400）"
            )

        # 本机是 4:2:2 源，NV12 按设计应被拒绝（EINVAL）。
        call(fd, GET_LATEST_NV12, request, "GET_LATEST_NV12_FRAME(12) 预期 EINVAL")
        call(fd, RESET_CAPTURE_STATS, 0, "RESET_CAPTURE_STATS(10)")
        call(fd, STOP_ASYNC, 0, "STOP_ASYNC(7)")
        call(fd, HARD_RESET, 0, "HARD_RESET(5)")
        return 0
    finally:
        os.close(fd)


if __name__ == "__main__":
    raise SystemExit(main())
