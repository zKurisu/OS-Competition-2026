# sg2002 wifi 启用

## 内核构建前

### aic8800.rs

wifi 的 硬件驱动为 `ax-driver/src/net/aic8800.rs`

但该文件存在错误，启用 IRQ 的时机有问题，会导致驱动配置时超时

因此需要将启用 IRQ 的代码提前

代码修改见 [patch](../../tree/tgos-patches/wifi_2026-07-22_1bba09815.md)

### wext.rs

wifi 接口为 `os/StarryOS/kernel/src/file/wext.rs`

在 starryos 上，wifi 用户态程序缺少一些 ioctl 接口，因此需要补充一些接口

代码修改见 [patch](../../tree/tgos-patches/wext_2026-07-22_1bba09815.md)

## 内核构建

在 `tgoskits` 仓库中选择 config `licheerv-nano-sg2002-wifi.toml`

```bash
cargo xtask starry build -c os/StarryOS/configs/board/licheerv-nano-sg2002-wifi.toml
```

其中编译到 `aic8800` 时会卡住，因为缺少以为文件，需要从 github 下载，因此构建前需要打开代理

## 用户态程序

用户态程序在 `tgoskits` 仓库下的 `apps/starry/picoclaw-cli/wifi_switch.c`

具体可参考 `apps/starry/picoclaw-cli/WIFI_SWITCH_DEMO.md`
