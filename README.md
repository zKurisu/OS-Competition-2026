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

[dev_mem_gpio_2026-07-17_1bba09815](dev_mem_gpio_2026-07-17_1bba09815.md)

> 时间: 2026-07-17  
> 基于 tgoskits commit hash: 1bba09815

[wifi_2026-07-22_1bba09815.patch](wifi_2026-07-22_1bba09815.md)

> 时间: 2026-07-22  
> 基于 tgoskits commit hash: 1bba09815

[wext_2026-07-22_1bba09815.patch](wext_2026-07-22_1bba09815.md)

> 时间: 2026-07-22  
> 基于 tgoskits commit hash: 1bba09815

[dns_2026-07-22_1bba09815.patch](dns_2026-07-22_1bba09815.patch)

> 时间: 2026-07-22  
> 基于 tgoskits commit hash: 1bba09815  
> 基于 patches: wifi, wext
