# U-Boot 保存 env

## 使用方式

在 `uboot` 命令模式下使用 `env set <name> <args>` 设置 env 中的变量，例如

```soph
env set sdboot 'setenv bootargs ${reserved_mem} ${root} ${mtdparts} console=$consoledev,$baudrate $othbootargs;echo Boot from SD dev ${sddev} ...;mmc dev ${sddev} && fatload mmc ${sddev} ${uImage_addr} boot.sd;if test $? -eq 0; then bootm ${uImage_addr}#config-1;fi;'
```
可将 `sdboot` 内容改变，从而改变启动行为

## 编译选项

1. 文件:build/boards/sg200x/sg2002_licheervnano_sd/u-boot/sg2002_licheervnano_sd_defconfig

```config
# CONFIG_ENV_IS_NOWHERE is not set
CONFIG_ENV_IS_IN_FAT=y
CONFIG_ENV_FAT_INTERFACE="mmc"
CONFIG_ENV_FAT_DEVICE_AND_PART="0:1"
CONFIG_ENV_FAT_FILE="uboot.env"
```

作用:把环境从"nowhere"改为存到 SD 卡第 1 个 FAT 分区(mmc 0:1)的 uboot.env 文件。

2. 文件:board/cvitek/mars/Kconfig:58

```config
config ENV_SIZE
    default 0x10000 if ENV_IS_IN_SPI_FLASH
    default 0x20000 if ENV_IS_IN_MMC
    default 0x20000 if ENV_IS_IN_NAND
    default 0x20000 if ENV_IS_IN_FAT      ← 新增
```

作用:原定义没有 FAT 分支,导致 ENV_SIZE 解析为空。(注:非严格必需,因 cvipart.h 也提供 ENV_SIZE,但保留更清晰。)

3. 文件:build/tools/common/image_tool/mkcvipart.py:55-60
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
作用:mkcvipart.py 生成的 include/cvipart.h 被 mars-asic.h:26 包含,原先在 C 预处理层无条件 #define CONFIG_ENV_IS_NOWHERE,压过了 Kconfig 设置 → env_locations 数组始终含 ENVL_NOWHERE → saveenv 落到 nowhere。改为条件生成后,已通过 Kconfig 选了 FAT 就不再定义 nowhere。

依赖项
CONFIG_CMD_SAVEENV、CONFIG_SAVEENV、CONFIG_FAT_WRITE、CONFIG_ENV_SIZE=0x20000(由 cvipart.h 提供)。
