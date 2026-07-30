# 补丁

本分支暂定为 tgoskits 仓库的 patch 位置，以免各自修改的 starryos 版本难以合并到同一个仓库中

## 补丁使用

补丁信息参考 [补丁信息](#补丁信息) 章节

先检查补丁能否顺利应用
```bash
git apply --check change.patch
```

 如果没有问题，则应用补丁
```bash
git apply change.patch
```

然后手动保存修改的文件
```bash
git add .
git commit -m "feat: apply patch change"
```

## 补丁生成

生成所有未暂存，但已跟踪文件的改动
```bash
git diff > change.patch
```

生成特定文件的改动
```bash
git diff src/file > change.patch
```

git add 后，生成暂存区改动
```bash
git diff --cached > change.patch
```

生成两个提交之间的差异
```bash
git diff some-commit-hash-1 some-commit-hash-2 > change.patch
```

## 补丁信息

[dev_mem_gpio_2026-07-17_1bba09815.patch](dev_mem_gpio_2026-07-17_1bba09815.patch)

> 时间: `2026-07-17`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/Cargo.toml  
> A  os/StarryOS/kernel/src/pseudofs/dev/gpio.rs  
> A  os/StarryOS/kernel/src/pseudofs/dev/mem.rs  
> M  os/StarryOS/kernel/src/pseudofs/dev/mod.rs  
> M  os/StarryOS/starryos/Cargo.toml

[wifi_2026-07-22_1bba09815.patch](wifi_2026-07-22_1bba09815.patch)

> 时间: `2026-07-22`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  drivers/ax-driver/src/net/aic8800.rs

[wext_2026-07-22_1bba09815.patch](wext_2026-07-22_1bba09815.patch)

> 时间: `2026-07-22`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/src/file/wext.rs

[dns_2026-07-22_1bba09815.patch](dns_2026-07-22_1bba09815.patch)

> 时间: `2026-07-22`  
> 基于 tgoskits commit hash: `1bba09815`  
> 基于 patches: wifi, wext

**文件修改**

> M  net/ax-net/src/lib.rs
> M  net/ax-net/src/service.rs
> M  os/StarryOS/kernel/src/entry.rs

[fat_2026-07-23_1bba09815.patch](fat_2026-07-23_1bba09815.patch)

> 时间: `2026-07-23`
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/Cargo.toml
> M  os/StarryOS/starryos/Cargo.toml
> M  os/arceos/modules/axfs-ng/src/fs/fat/fs.rs
> M  os/arceos/modules/axfs-ng/src/root.rs

[camera_2026-07-23_1bba09815.patch](camera_2026-07-23_1bba09815.patch)

> 时间: `2026-07-23`
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/src/pseudofs/dev/cvi_usb_camera.rs

[strace-fix_2026-07-24_1bba09815.patch](strace-fix_2026-07-24_1bba09815.patch)

> 时间: `2026-07-24`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/src/syscall/task/ptrace.rs  
> M  os/StarryOS/kernel/src/task/signal.rs  
> M  os/StarryOS/kernel/src/task/user.rs

[dmesg_2026-07-25_1bba09815.patch](dmesg_2026-07-25_1bba09815.patch)

> 时间: `2026-07-25`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/src/entry.rs  
> M  os/StarryOS/kernel/src/syscall/sys.rs  
> M  os/arceos/modules/axruntime/src/lib.rs

[init-sh_2026-07-26_1bba09815.patch](init-sh_2026-07-26_1bba09815.patch)

> 时间: `2026-07-26`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/starryos/src/init.sh

[ktracepoint-fix_2026-07-26_1bba09815.patch](ktracepoint-fix_2026-07-26_1bba09815.patch)

> 时间: `2026-07-26`  
> 基于 tgoskits commit hash: `1bba09815`

**文件修改**

> M  os/StarryOS/kernel/src/pseudofs/dev/cvi_usb_camera.rs  
> M  os/StarryOS/kernel/src/tracepoint/mod.rs

[jpu-fix_2026-07-29_11ba09815.patch](jpu-fix_2027-07-29_11ba09815.patch)

> 时间: `2026-07-29`  
> 基于 tgoskits commit hash: `1bba09815`  
> 基于 patch: camera

**文件修改**

> M os/StarryOS/kernel/src/pseudofs/dev/cvi_usb_camera.rs  
> M os/StarryOS/kernel/src/task/signal.rs
