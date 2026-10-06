#!/bin/bash

set -euo pipefail

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "command not fount: $1"
        exit 1
    fi
}

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${ROOT}/build"

mkdir -p "${BUILD_ROOT}"

check_cmd git
command git submodule update --init --recursive

# build fip.bin
cd "${ROOT}/LicheeRV-Nano-Build"
[ -d host-tools ] || git clone https://github.com/sophgo/host-tools --depth=1
bash -c 'source build/cvisetup.sh && defconfig sg2002_licheervnano_sd && build_uboot'
cp "install/soc_sg2002_licheervnano_sd/fip.bin" "${BUILD_ROOT}/"

# build starryos.bin
check_cmd cargo
cd "${ROOT}/tgoskits"
command cargo xtask starry build -c os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml
cp "target/riscv64gc-unknown-linux-musl/release/starryos.bin" "${BUILD_ROOT}/"

# build boot.sd
cd "${BUILD_ROOT}/"
cp "${ROOT}/script/boot.its" ./
cp "${ROOT}/tgoskits/os/StarryOS/configs/board/licheerv-nano-sg2002.dtb" ./
check_cmd mkimage
command mkimage -f boot.its boot.sd

# build uboot.env
touch uboot.env

printf '*%.0s' {1..20}; printf "SUCCESS"; printf '*%.0s' {1..20}; echo
echo "Then run"
echo ""
echo "${ROOT}/script/upload.sh /dev/sdXY # replayce /dev/sdXY with your own device name"
echo ""
echo "to install U-Boot and StarryOS"
