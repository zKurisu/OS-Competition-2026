#!/usr/bin/env python3
"""cam_ion_probe.py —— 验证相机 ioctl 13（GET_LATEST_YUV_ION）。

流程照 test_akars/src/vpss_pipeline.rs 的 next_inner + allocate：
  1) /dev/ion 用 ION_IOC_ALLOC（heap = 1<<1 = DMA coherent，2 MiB）拿缓冲 fd
  2) /dev/cvi-usb-camera0 INIT(1) + START_ASYNC(6)
  3) ioctl 13 传 CameraIonFrameRequest{abi_version=2, ion_fd, timeout_ms, capacity}
"""

import ctypes
import fcntl
import os
import time

ION = "/dev/ion"
CAM = "/dev/cvi-usb-camera0"
ION_IOC_ALLOC = (3 << 30) | (64 << 16) | (ord("I") << 8) | 0
CAMERA_ION_ABI_VERSION = 2
CAPACITY = 2 * 1024 * 1024


class IonAllocData(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_uint64),
        ("heap_id_mask", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("fd", ctypes.c_uint32),
        ("unused", ctypes.c_uint32),
        ("paddr", ctypes.c_uint64),
        ("name", ctypes.c_char * 32),
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


class CameraIonFrameRequest(ctypes.Structure):
    _fields_ = [
        ("abi_version", ctypes.c_uint32),
        ("flags", ctypes.c_uint32),
        ("ion_fd", ctypes.c_int32),
        ("timeout_ms", ctypes.c_uint32),
        ("buffer_offset", ctypes.c_uint64),
        ("capacity", ctypes.c_uint64),
        ("last_sequence", ctypes.c_uint64),
        ("sequence", ctypes.c_uint64),
        ("timestamp_ns", ctypes.c_uint64),
        ("y_offset", ctypes.c_uint64),
        ("cb_offset", ctypes.c_uint64),
        ("cr_offset", ctypes.c_uint64),
        ("length", ctypes.c_uint32),
        ("stride_y", ctypes.c_uint32),
        ("stride_c", ctypes.c_uint32),
        ("width", ctypes.c_uint16),
        ("height", ctypes.c_uint16),
        ("format", ctypes.c_uint8),
        ("reserved", ctypes.c_uint8 * 3),
        ("jpu_decode_us", ctypes.c_uint64),
        ("profile", CameraCaptureProfile),
    ]


def main() -> int:
    print("size of CameraIonFrameRequest =", ctypes.sizeof(CameraIonFrameRequest), "(内核断言 168)")
    ion = os.open(ION, os.O_RDWR)
    cam = os.open(CAM, os.O_RDWR)
    try:
        alloc = IonAllocData()
        alloc.len = CAPACITY
        alloc.heap_id_mask = 1 << 1  # ION_HEAP_DMA_COHERENT
        alloc.name = b"ion-probe"
        fcntl.ioctl(ion, ION_IOC_ALLOC, alloc)
        print(f"  ION alloc ok: fd={alloc.fd} paddr=0x{alloc.paddr:x} len={alloc.len}")

        fcntl.ioctl(cam, 1, 0)
        print("  INIT(1) ok")
        fcntl.ioctl(cam, 6, 0)
        print("  START_ASYNC(6) ok")
        time.sleep(1.5)

        for attempt in range(1, 4):
            request = CameraIonFrameRequest(
                abi_version=CAMERA_ION_ABI_VERSION,
                ion_fd=alloc.fd,
                timeout_ms=2000,
                capacity=CAPACITY,
            )
            try:
                ret = fcntl.ioctl(cam, 13, request)
                print(
                    f"  GET_LATEST_YUV_ION(13) attempt{attempt}: ret={ret} "
                    f"seq={request.sequence} len={request.length} "
                    f"{request.width}x{request.height} fmt={request.format} "
                    f"stride_y={request.stride_y} stride_c={request.stride_c} "
                    f"y={request.y_offset} cb={request.cb_offset} cr={request.cr_offset} "
                    f"jpu_us={request.jpu_decode_us}"
                )
                break
            except OSError as err:
                print(
                    f"  GET_LATEST_YUV_ION(13) attempt{attempt}: errno={err.errno} "
                    f"({os.strerror(err.errno)})"
                )
        fcntl.ioctl(cam, 7, 0)
        print("  STOP_ASYNC(7) ok")
        return 0
    finally:
        os.close(cam)
        os.close(ion)


if __name__ == "__main__":
    raise SystemExit(main())
