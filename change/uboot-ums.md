# U-Boot 启用 UMS (USB Mass Storage)

## 用法

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

## 修改文件

本次 UMS 功能完整改动总结
1. defconfig：启用 USB gadget + UMS，移除冲突的 RNDIS/DM_USB_GADGET 段；修正 ENV_IS_IN_FAT。
2. RISC-V 移植：补 arch/riscv 原子位操作；修 config.c 描述符成员名；dwc2 的 mach-types/writel。
3. PHY：CVITEK 平台跳过 Exynos otg_phy_init/off；board_usb_init 使能 USB 时钟门控。
4. DWC2 4.20a 复位：按 GSNPSID 用 CSFTRST_DONE 判定复位完成（核心根因）。
5. 热插拔：udc_disable 退出时 soft-disconnect 拉低 D+。

***

1. defconfig 修改
```config
# USB gadget + UMS (USB Mass Storage) for starryos development
CONFIG_USB=y
CONFIG_USB_GADGET=y
CONFIG_USB_GADGET_DWC2_OTG=y
CONFIG_USB_GADGET_DOWNLOAD=y
CONFIG_USB_GADGET_MANUFACTURER="Cvitek"
CONFIG_USB_GADGET_VENDOR_NUM=0x18d1
CONFIG_USB_GADGET_PRODUCT_NUM=0x4ee0
CONFIG_USB_FUNCTION_MASS_STORAGE=y
CONFIG_CMD_USB_MASS_STORAGE=y
```

2. u-boot-2021.10/include/configs/mars-asic.h

删除了所有 `#define` 定义的宏，有的已经弃用，有的与其他文件中的定义有冲突

需要使用的 `CONFIG_*` 已经在 `defconfig` 中被定义

3. u-boot-2021.10/board/cvitek/mars/board.c

```diff
@@ -310,11 +310,16 @@ int board_usb_init(int index, enum usb_init_type init)
 {
        u32 value;
 
+       /* Enable USB clocks: AXI4, APB, 125M, 33K, 12M */
+       clrsetbits_le32(REG_CLK_EN_1, USB_CLK_EN1_MASK, USB_CLK_EN1_MASK);
+       clrsetbits_le32(REG_CLK_EN_2, USB_CLK_EN2_MASK, USB_CLK_EN2_MASK);
+
        value = mmio_read_32(TOP_BASE + REG_TOP_SOFT_RST) & (~BIT_TOP_SOFT_RST_USB);
        mmio_write_32(TOP_BASE + REG_TOP_SOFT_RST, value);
        udelay(50);
        value = mmio_read_32(TOP_BASE + REG_TOP_SOFT_RST) | BIT_TOP_SOFT_RST_USB;
        mmio_write_32(TOP_BASE + REG_TOP_SOFT_RST, value);
+       mdelay(10);
 
        /* Set USB phy configuration */
        value = mmio_read_32(REG_TOP_USB_PHY_CTRL);
@@ -325,7 +330,7 @@ int board_usb_init(int index, enum usb_init_type init)
        /* Enable ECO RXF */
        mmio_write_32(REG_TOP_USB_ECO, mmio_read_32(REG_TOP_USB_ECO) | BIT_TOP_USB_ECO_RX_FLUSH);
 
        printf("cvi_usb_hw_init done\n");
+       mdelay(10);
 
        return dwc2_udc_probe(&cv182x_otg_data);
 }
```

使用 `clrsetbits_le32` 设置始终使能寄存器中 `*_MASK` 中覆盖到的位为 1

使用 `mdelay` 等待时钟、PHY配置稳定，避免出现硬件上的偶发错误

4. u-boot-2021.10/board/cvitek/mars/mars_reg.c

定义一些常量；时钟使能寄存器地址、时钟MASK

5. u-boot-2021.10/drivers/usb/gadget/config.c

修正一些变量名

6. u-boot-2021.10/drivers/usb/gadget/dwc2_udc_otg.c

`sg2002` 的 dwc2 硬件版本为 rev4.20a，与 `u-boot-2021.10` 中实现的版本不同

- 旧版本（如 4.00a）的流程：

    1. 软件设置 GRSTCTL 寄存器的 Bit 0 (CSFTRST) 来触发软复位。
    2. 软件持续轮询等待 Bit 0 (CSFTRST) 被硬件自动清零，以此判断复位是否完成。

- 新版本 (4.20a 及之后) 的流程：

    1. 软件设置 GRSTCTL 寄存器的 Bit 0 (CSFTRST) 来触发软复位。
    2. 软件需要轮询等待一个全新的标志位：Bit 29 (GRSTCTL_CSFTRST_DONE)，当该位被硬件置1时，表示复位已完成。
    3. 软件在确认复位完成后，需要手动清除 Bit 0 和 Bit 29。

因此修复了这个文件中的复位判断流程，以及一些其他小问题

```diff
@@ -41,7 +41,9 @@
 #include <asm/unaligned.h>
 #include <asm/io.h>
 
+#ifdef CONFIG_ARM
 #include <asm/mach-types.h>
+#endif
 
 #include <power/regulator.h>
 
@@ -173,8 +175,16 @@ __weak void otg_phy_off(struct dwc2_udc *dev) {}
  */
 static void udc_disable(struct dwc2_udc *dev)
 {
+       u32 uTemp;
+
        debug_cond(DEBUG_SETUP != 0, "%s: %p\n", __func__, dev);
 
+       /* Soft-disconnect: drive D+ low so the host detects removal. */
+       uTemp = readl(&reg->dctl);
+       uTemp |= SOFT_DISCONNECT;
+       writel(uTemp, &reg->dctl);
+       mdelay(10);
+
        udc_set_address(dev, 0);
 
        dev->ep0state = WAIT_FOR_SETUP;
@@ -455,13 +465,60 @@ static void reconfig_usbd(struct dwc2_udc *dev)
 {
        /* 2. Soft-reset OTG Core and then unreset again. */
        int i;
-       unsigned int uTemp = writel(CORE_SOFT_RESET, &reg->grstctl);
+       unsigned int uTemp;
        uint32_t dflt_gusbcfg;
        uint32_t rx_fifo_sz, tx_fifo_sz, np_tx_fifo_sz;
        u32 max_hw_ep;
        int pdata_hw_ep;
 
-       debug("Reseting OTG controller\n");
+       /* Core soft reset. DWC2 >= 4.20a signals completion via CSFTRST_DONE
+        * (bit29) instead of self-clearing CSFTRST (bit0). */
+       {
+               u32 snpsid = readl((void *)((uintptr_t)reg + 0x040)) &
+                            DWC2_CORE_REV_MASK;
+               u32 greset;
+               int count = 0;
+
+               if (snpsid < (DWC2_CORE_REV_4_20a & DWC2_CORE_REV_MASK)) {
+                       writel(CORE_SOFT_RESET, &reg->grstctl);
+                       do {
+                               udelay(1);
+                               greset = readl(&reg->grstctl);
+                               if (++count > 100000) {
+                                       printf("reconfig_usbd: HANG soft reset GRSTCTL=%08x\n",
+                                              greset);
+                                       break;
+                               }
+                       } while (greset & CORE_SOFT_RESET);
+               } else {
+                       writel(CORE_SOFT_RESET, &reg->grstctl);
+                       do {
+                               udelay(1);
+                               greset = readl(&reg->grstctl);
+                               if (++count > 100000) {
+                                       printf("reconfig_usbd: HANG soft reset(4.2) GRSTCTL=%08x\n",
+                                              greset);
+                                       break;
+                               }
+                       } while (!(greset & CSFTRST_DONE));
+                       greset = readl(&reg->grstctl);
+                       greset &= ~CORE_SOFT_RESET;
+                       greset |= CSFTRST_DONE;
+                       writel(greset, &reg->grstctl);
+               }
+
+               /* Wait for AHB master IDLE state. */
+               count = 0;
+               do {
+                       udelay(1);
+                       greset = readl(&reg->grstctl);
+                       if (++count > 100000) {
+                               printf("reconfig_usbd: HANG AHB idle GRSTCTL=%08x\n",
+                                      greset);
+                               break;
+                       }
+               } while (!(greset & AHB_MASTER_IDLE));
+       }
 
        dflt_gusbcfg =
                0<<15           /* PHY Low Power Clock sel*/
```

`#include <asm/mach-types.h>` 只有arm架构使用，于是用编译选项包裹

`udc_disable` 函数中，手动将 `D+` 拉低以告诉主机自己断开连接

`reconfig_usbd` 中根据版本使用不同的复位检测方法


7. u-boot-2021.10/drivers/usb/gadget/dwc2_udc_otg_phy.c

其中的 `otg_phy_init` 和 `otg_phy_off` 中的原始代码不是为 `sg2002` 准备的，相关代码在 `board.c` 中处理

8. u-boot-2021.10/drivers/usb/gadget/dwc2_udc_otg_regs.h

定义了几个常量，在其他文件中使用

```diff
@@ -117,8 +117,13 @@ struct dwc2_usbotg_reg {
 
 /* DWC2_UDC_OTG_GRSTCTL */
 #define AHB_MASTER_IDLE                (1u<<31)
+#define CSFTRST_DONE           (0x1<<29)
 #define CORE_SOFT_RESET                (0x1<<0)
 
+/* Core release (GSNPSID) */
+#define DWC2_CORE_REV_4_20a    0x4f54420a
+#define DWC2_CORE_REV_MASK     0x0000ffff
+
 /* DWC2_UDC_OTG_GINTSTS/DWC2_UDC_OTG_GINTMSK core interrupt register */
 #define INT_RESUME                     (1u<<31)
 #define INT_DISCONN                    (0x1<<29)
```
