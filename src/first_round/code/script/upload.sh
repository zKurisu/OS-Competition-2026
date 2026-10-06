#!/bin/bash

set -euo pipefail

if [[ "$#" < 1 ]]; then
    echo "no device name"
    echo ""
    echo "usage: $0 <disk>"
    exit 1
fi

if [[ "$UID" != 0 ]]; then
    echo "root required"
    exit 1
fi

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${ROOT}/build"

command mount "$1" /mnt
command cp "${BUILD_ROOT}"/{fip.bin,boot.sd,uboot.env} /mnt/
ls -lhF /mnt
command umount /mnt

