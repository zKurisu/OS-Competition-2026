# sg2002 wifi 启用

## 内核构建前

### aic8800.rs

wifi 的 硬件驱动为 `ax-driver/src/net/aic8800.rs`

但该文件存在错误，启用 IRQ 的时机有问题，会导致驱动配置时超时

因此需要将启用 IRQ 的代码提前

代码修改见 [wifi-patch](./patch/wifi_2026-07-22_1bba09815.md)

### wext.rs

wifi 接口为 `os/StarryOS/kernel/src/file/wext.rs`

在 starryos 上，wifi 用户态程序缺少一些 ioctl 接口，因此需要补充一些接口

代码修改见 [wext-patch](./patch/wext_2026-07-22_1bba09815.md)

### 自动写入 resolv.conf

内核获取到来自路由的 DNS 后保存在内存里，其他用户态程序不知道，导致无法访问域名，只能访问ip

因此使用回调函数在 DNS 改变时自动写入 `/etc/resolv.conf`

| 文件                              | 改动                                                           |
|-----------------------------------|----------------------------------------------------------------|
| `net/ax-net/src/lib.rs`           | DNS 变更回调 + `set_dns_change_callback` + `notify_dns_change` |
| `net/ax-net/src/service.rs`       | `commit_interface_update` 尾部触发通知                         |
| `os/StarryOS/kernel/src/entry.rs` | `write_resolv_conf` 函数 + 回调注册                            |

代码修改见 [dns-patch](./patch/dns_2026-07-22_1bba09815.md)

## 内核构建

在 `tgoskits` 仓库中选择 config `licheerv-nano-sg2002-wifi.toml`

```bash
cargo xtask starry build -c os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml
```

其中编译到 `aic8800` 时会卡住，因为缺少以为文件，需要从 github 下载，因此构建前需要打开代理

## 用户态程序

用户态程序在 `tgoskits` 仓库下的 `apps/starry/picoclaw-cli/wifi_switch.c`

具体可参考 `apps/starry/picoclaw-cli/WIFI_SWITCH_DEMO.md`

编译命令

```bash
riscv64-linux-musl-gcc tgoskits/apps/starry/picoclaw-cli/wifi_switch.c -o wifi_switch
```
