# U-Boot 修改

## SAVEENV 启用

启用 SAVEENV 可以在 U-Boot 命令行保存环境变量，而无需重新编译 `fip.bin`

### 编译选项

1. 文件: `build/boards/sg200x/sg2002_licheervnano_sd/u-boot/sg2002_licheervnano_sd_defconfig`

```config
# CONFIG_ENV_IS_NOWHERE is not set
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_INTERFACE="mmc"
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
CONFIG_ENV_FAT_FILE="uboot.env"
```

作用: 把环境从"nowhere"改为存到 SD 卡第 1 个 FAT 分区(mmc 0:1)的 uboot.env 文件

2. 文件: `board/cvitek/mars/Kconfig`

```config
config ENV_SIZE
    default 0x10000 if ENV_IS_IN_SPI_FLASH
    default 0x20000 if ENV_IS_IN_MMC
    default 0x20000 if ENV_IS_IN_NAND
    default 0x20000 if ENV_IS_IN_FAT      ← 新增
```

作用: 原定义没有 FAT 分支,导致 `ENV_SIZE` 解析为空

3. 文件: `build/tools/common/image_tool/mkcvipart.py`

把无条件的

```python
of.write("#ifndef CONFIG_ENV_IS_NOWHERE\n#define CONFIG_ENV_IS_NOWHERE\n#endif\n")
of.write("#define CONFIG_ENV_SIZE 0x20000\n")
```

改为仅当 Kconfig 未选任何 env 存储时才定义:

```python
of.write("#if !defined(CONFIG_ENV_IS_IN_FAT) && !defined(CONFIG_ENV_IS_IN_MMC) && "
         "!defined(CONFIG_ENV_IS_IN_SPI_FLASH) && !defined(CONFIG_ENV_IS_IN_NAND)\n")
of.write("#ifndef CONFIG_ENV_IS_NOWHERE\n#define CONFIG_ENV_IS_NOWHERE\n#endif\n")
of.write("#endif\n")
of.write("#ifndef CONFIG_ENV_SIZE\n#define CONFIG_ENV_SIZE 0x20000\n#endif\n")
```
`mkcvipart.py` 生成的 `include/cvipart.h` 被 `mars-asic.h` 包含, 原先在 C 预处理层无条件 `#define CONFIG_ENV_IS_NOWHERE`, 压过了 Kconfig 设置

改为条件生成后, Kconfig 选了 FAT 就不再定义 nowhere

依赖项 `CONFIG_CMD_SAVEENV`、`CONFIG_SAVEENV`、`CONFIG_FAT_WRITE`、`CONFIG_ENV_SIZE=0x20000` (由 cvipart.h 提供)。

### 使用方式

需要在 FAT 分区先创建一个 `uboot.env` 文件才能保存成功

在 `uboot` 命令模式下使用 `env set <name> <args>` 设置 env 中的变量，例如

```soph
env set sdboot 'setenv bootargs ${reserved_mem} ${root} ${mtdparts} console=$consoledev,$baudrate $othbootargs;echo Boot from SD dev ${sddev} ...;mmc dev ${sddev} && fatload mmc ${sddev} ${uImage_addr} boot.sd;if test $? -eq 0; then bootm ${uImage_addr}#config-1;fi;'
```
可将 `sdboot` 内容改变，从而改变启动行为，也可手动配置启动其他内核

```soph
env set lboot 'setenv bootargs ${reserved_mem} ${root} ${mtdparts} console=$consoledev,$baudrate $othbootargs;echo Boot from SD dev ${sddev} ...;mmc dev ${sddev} && fatload mmc ${sddev} ${uImage_addr} linux.sd;if test $? -eq 0; then bootm ${uImage_addr}#config;fi;'
```
可通过 `run lboot` 启动 Linux 内核

## RNDIS 启用

启用 RNDIS 可以将 SG2002 视为外部网卡，可以通过其提供的 IP 地址传输内核

### 使用方式

给 SG2002 上电, 进入 U-Boot 后:
```
setenv ipaddr 192.168.42.1
setenv serverip 192.168.42.100
ping 192.168.42.100
```

之后在宿主机终端里查看新的网络接口:
```sh
$ ip a
```

![](./.github/img/interface-show-up.png)

找到后快速设置:
```sh
$ sudo ip addr add 192.168.42.100/24 dev enp0s20f0u1c2
$ sudo ip link set enp0s20f0u1c2 up
```
![](./.github/img/setup-interface.png)

之后 U-Boot 中的 `ping 192.168.42.100` 会返回则表示连接成功:

![](./.github/img/u-boot-ping-alive.png)

安装 `tftp` 服务并启动, 我这里是 Archlinux:
```sh
sudo pacman -S tftp-hpa
sudo systemctl start tftpd
sudo mkdir -p /srv/tftp
sudo bash -c "echo 'Hello U-Boot' > /srv/tftp/hello.txt"
```

在 U-Boot 内拉取文件并查看:
```
tftpboot 0x84000000 hello.txt
md 0x84000000
```

![](./.github/img/u-boot-tftp.png)

拉取 `boot.sd` 示例:
```soph
tftpboot 0x81800000 boot.sd
bootm 0x81800000#config-sg2002_licheervnano_sd
```

## UMS 启用

启用 UMS 可以让 SG2002 通过 Type-C 连接到计算机后被识别为大容量存储设备，可以直接 mount 而无须拔卡

### 使用方式

在 U-Boot 命令行中使用 `ums 0 mmc 0` 可以将第0个 mmc 设备(SD卡)在 `usb 0` 上模拟为USB存储设备

然后可以使用 `mount /dev/sdxn /mnt` 将 `sdx` 的第 `n` 个分区挂载到 `/mnt`

```bash
$ ll /mnt
总计 14M
-rwxr-xr-x 1 root root  13M  7月 8日 21:28 boot.sd
-rwxr-xr-x 1 root root 450K  7月 9日 20:01 fip.bin
-rwxr-xr-x 1 root root 128K  7月 9日 01:22 uboot.env
```

```bash
$ sudo fdisk -l
...

Disk /dev/sdb：7.28 GiB，7816085504 字节，15265792 个扇区
磁盘型号：UMS disk 0
单元：扇区 / 1 * 512 = 512 字节
扇区大小(逻辑/物理)：512 字节 / 512 字节
I/O 大小(最小/最佳)：512 字节 / 512 字节
磁盘标签类型：dos
磁盘标识符：0x00000000

设备       启动   起点    末尾    扇区  大小 Id 类型
/dev/sdb1  *         1  262144  262144  128M  c W95 FAT32 (LBA)
/dev/sdb2       262145 1835008 1572864  768M 83 Linux
```
