# Intro
该文档记录 `boot.sd` 和 `fip.bin` 文件的构建 (包括单一 image 文件构建), 以及 StarryOS 在 SG2002 上的启动流程.

最终需要的文件有:
```
.
├── boot.its    # Image Tree Source 文件, 描述 FIT 镜像需要包含的组件
├── boot.sd     # Flatted Image Tree 文件, `.sd` 后缀只是说明其用于 SD 卡上启动, 是一种内核打包格式, 含内核镜像, 设备树
├── fdt.dtb     # 设备树文件
├── fip.bin     # Firmware Image Package, 一种固件打包格式, 含 OpenSBI 和 U-Boot
├── kernel      # StarryOS 镜像
└── rootfs-riscv64.img # 硬盘文件

1 directory, 6 files
```

# Env
当前环境是 Arch Linux (Linux 7.0.14-arch1-1), 安装一些工具链 (可以根据报错看缺啥就装啥):
```sh
sudo pacman -S uboot-tools
wget https://musl.cc/riscv64-linux-musl-cross.tgz
tar xvf riscv64-linux-musl-cross.tgz
export PATH=$(pwd)/riscv64-linux-musl-cross/bin:$PATH
```

拉取 `tgoskits` 仓库:
```sh
mkdir ~/workspace
cd ~/workspace
git clone https://github.com/rcore-os/tgoskits.git
```

复制出设备树文件:
```sh
mkdir ~/workspace/genimage
cd ~/workspace/genimage
cp ~/workspace/tgoskits/os/StarryOS/configs/board/licheerv-nano-sg2002.dtb fdt.dtb
```

拉取 Disk 文件 (含 BusyBox):
```sh
cd ~/workspace/genimage
curl -f -L https://github.com/Starry-OS/rootfs/releases/download/20260214/rootfs-riscv64.img.xz  -O
xz -d rootfs-riscv64.img.xz
```

拉取 `duo-buildroot-sdk-v2` 仓库, 用于后续编译构建 `fip` 文件:

```sh
cd ~/workspace
git clone https://github.com/milkv-duo/duo-buildroot-sdk-v2.git
cd duo-buildroot-sdk-v2
git clone https://github.com/milkv-duo/host-tools.git
```

# 编译 StarryOS 内核二进制
```sh
cd ~/workspace/tgoskits
cargo xtask starry build --config os/StarryOS/configs/board/licheerv-nano-sg2002.toml

cd ~/workspace/genimage
cp ~/workspace/tgoskits/target/riscv64gc-unknown-linux-musl/release/starryos.bin kernel
```

# 编译 FIP 文件
```
cd ~/workspace/duo-buildroot-sdk-v2
source build/envsetup_milkv.sh milkv-duo256m-musl-riscv64-sd
build_fsbl
cp fsbl/build/sg2002_milkv_duo256m_musl_riscv64_sd/fip.bin ~/workspace/genimage
```

# 编写 Image Tree Source 文件
```sh
cd ~/workspace/genimage
cat > boot.its <<EOF
/dts-v1/;
/ {
    description = "StarryOS SG2002";
    #address-cells = <1>;
    images {
        kernel-1 {
            data = /incbin/("kernel");
            type = "kernel"; arch = "riscv"; os = "linux";
            compression = "none";
            load = <0x80200000>; entry = <0x80200000>;
            hash-1 { algo = "sha256"; };
        };
        fdt-1 {
            data = /incbin/("fdt.dtb");
            type = "flat_dt"; arch = "riscv";
            compression = "none";
            hash-1 { algo = "sha256"; };
        };
    };
    configurations {
        default = "config-sg2002_milkv_duo256m_musl_riscv64_sd";
        config-sg2002_milkv_duo256m_musl_riscv64_sd { kernel = "kernel-1"; fdt = "fdt-1"; };
    };
};
EOF
```

# 生成 Flatted Image Tree 文件
```sh
cd ~/workspace/genimage
mkimage -f boot.its boot.sd
```

# 生成 image 镜像并写入 SD 卡
由于 `rootfs-riscv64.img` 的大小已经是 `1.1GB`, 这里假设镜像的大小为 `1.5GB`:
```sh
IMAGE_SIZE=1536 # 1.5GB
```

创建一个 1.5GB 大小的文件作为镜像载体:
```sh
sudo dd if=/dev/zero of=sd.img bs=1M count=$IMAGE_SIZE status=progress
```

给文件分区:
```sh
sudo sfdisk sd.img << EOF
label: dos
,64M,c,*
,,L
EOF
```
- `label: dos` 表示建立 MBR 分区表
- `,64M,c,*` 表示从默认起点 (2048扇区) 开始, 把大小为 64MiB 的空间标记类型为 `0x0c` (FAT32 LBA)
- `,,L` 将剩余空间标记为类型 `0x83` (Linux)
(这部分应该只是写到超级块内)

将文件挂载为 loop device:
```sh
LOOP=$(sudo losetup -fP --show sd.img)
echo "Loop device: $LOOP"
# Loop device: /dev/loop0
```

格式化分区:
```sh
sudo mkfs.vfat -F 16 ${LOOP}p1
sudo mkfs.ext4 -F ${LOOP}p2
```

挂载分区到本地, 便于复制文件:
```sh
mkdir -p /tmp/boot /tmp/rootfs
sudo mount ${LOOP}p1 /tmp/boot
sudo mount ${LOOP}p2 /tmp/rootfs
```

写入 boot 分区文件:
```sh
sudo cp boot.sd fip.bin /tmp/boot/
```

写入文件系统:
```sh
sudo dd if=disk.img of=${LOOP}p2 bs=1M status=progress
```

卸载并释放 loop device:
```sh
sudo umount /tmp/boot /tmp/rootfs
sudo losetup -d $LOOP
rmdir /tmp/boot /tmp/rootfs
```

# 烧录到 SD 卡
注意用 `lsblk` 或 `fdisk` 确认 SD 卡的设备名:
```sh
cd /workspace/genimage
sudo dd if=sd.img of=/dev/sda status=progress
```
