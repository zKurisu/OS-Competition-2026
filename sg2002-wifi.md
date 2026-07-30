# sg2002 wifi 启用

## 内核构建前

### aic8800.rs

wifi 的 硬件驱动为 `ax-driver/src/net/aic8800.rs`

但该文件存在错误，启用 IRQ 的时机有问题，会导致驱动配置时超时

> [ 79.050738 ax_driver::net::aic8800:140] [wifi] SDIO1 HW init (node=wifi-sd@4320000, sdio1=0x4320000)  
> [ 79.062438 ax_driver::net::aic8800:149] [wifi] SDIO1 IRQ resolved to IrqId { domain: IrqDomainId(7), hwirq: HwIrq(38) }  
> [ 79.128694 sdhci_cv1800:641] [SDIO] VENDOR_MSHC_CTRL: 0x00000302 -> 0x00010302  
> [ 79.137495 ax_driver::net::aic8800:165] [wifi] SDIO device: vendor=0xc8a1 device=0x0082  
> [ 79.146943 aic8800::wireless:34] [aic8800] chip=Aic8800D80 vid=0xc8a1 did=0x0082  
> [ 79.155901 aic8800::fw:112] [aic8800] firmware_init: chip=Aic8800D80  
> [ 79.168835 aic8800::fw:84] [aic8800] V3 SDIO ready (sleep_reg=0x10)  
> [ 79.596631 aic8800::fw::firmware::upload:59] [aic8800] Firmware uploaded (337184 bytes)  
> [ 79.644539 aic8800::fw::firmware::upload:206] [aic8800] AIC8800D80 firmware init done  
> [ 79.653813 aic8800::fw:174] [aic8800] Firmware init complete  
> [ 79.660965 aic8800::wireless:53] [aic8800] firmware loaded  
> [ 79.873060 aic8800::fdrv::core::init:150] [fdrv] flow_ctrl OK, reg=0x03, val=127 (raw=0x7f)  
> [ 79.936232 ax_driver::net::aic8800:180] [wifi] chip probe complete  
> [ 79.943802 aic8800::fdrv::wifi::api:360] [WifiClient] === start_ap_open START ===  
> [ 85.952884 aic8800::fdrv::protocol::cmd:237] [cmd_mgr] TIMEOUT waiting for cfm 0x006a (6000ms)  
> [ 85.962962 aic8800::fdrv::protocol::cmd:249] [cmd_mgr] send_cmd 0x0069 error: Timeout  
> [ 85.972380 ax_driver::net::aic8800:186] [wifi] AP start failed: Other(ConnectionTimeout)  
> [ 85.982083 rdrive:164] Probe failed for [AIC8800 WiFi (CV181x SDIO)]: other error: [wifi] AP start failed: Other(ConnectionTimeout)

因此将 axklib::irq::enable(irq_handle) 从 start_ap_open() 之后移到之前。现在的顺序是：

> aic8800::probe(sdio) → enable(irq_handle) → start_ap_open() → register wlan0

代码修改见 [wifi-patch](../../tree/tgos-patches/wifi_2026-07-22_1bba09815.md)

### wext.rs

wifi 接口为 `os/StarryOS/kernel/src/file/wext.rs`

在 starryos 上，wifi 用户态程序缺少一些 ioctl 接口

> root@starry:/root # ./wifi_switch sta UESTC-WiFi ""  
> [wifi_switch] wlan0 -> Station ssid="UESTC-WiFi" (open)  
> ioctl 0x8b00 failed: No such device

代码修改见 [wext-patch](../../tree/tgos-patches/wext_2026-07-22_1bba09815.md)

### 自动写入 resolv.conf

内核获取到来自路由的 DNS 后保存在内存里，其他用户态程序不知道，导致无法访问域名，只能访问ip

因此使用回调函数在 DNS 改变时自动写入 `/etc/resolv.conf`

| 文件                              | 改动                                                           |
|-----------------------------------|----------------------------------------------------------------|
| `net/ax-net/src/lib.rs`           | DNS 变更回调 + `set_dns_change_callback` + `notify_dns_change` |
| `net/ax-net/src/service.rs`       | `commit_interface_update` 尾部触发通知                         |
| `os/StarryOS/kernel/src/entry.rs` | `write_resolv_conf` 函数 + 回调注册                            |

代码修改见 [dns-patch](../../tree/tgos-patches/dns_2026-07-22_1bba09815.md)

## 内核构建

在 `tgoskits` 仓库中选择 config `licheerv-nano-sg2002-wifi.toml`

```bash
cargo xtask starry build -c os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml
```

其中编译到 `aic8800` 时会卡住，因为缺少文件，需要从 github 下载，因此构建前需要打开代理

## 用户态程序

用户态程序在 `tgoskits` 仓库下的 `apps/starry/picoclaw-cli/wifi_switch.c`

具体可参考 `apps/starry/picoclaw-cli/WIFI_SWITCH_DEMO.md`

编译命令

```bash
riscv64-linux-musl-gcc tgoskits/apps/starry/picoclaw-cli/wifi_switch.c -o wifi_switch
```
