#!/bin/bash
# ums_device.sh —— 通用 UMS（USB Mass Storage）块设备探测。
#
# 背景：板子 `ums 0 mmc 0` 后 SD 卡会以 U 盘形式挂到宿主机。若同时有多块板子在
# UMS 状态，绝不能默认写 /dev/sda——必须按"卡里的内容是不是我们的"来认。
#
# 用法（source 后调用）：
#     source ums_device.sh
#     read FAT EXT < <(ums_find_by_markers "starry-opt" || true)
#     read FAT EXT < <(ums_find_unique_ums)
#
# 也可直接命令行运行：`bash ums_device.sh starry-opt`（打印 "FATDEV EXTDEV"）。

# 列出所有型号是 UMS 的大容量设备名（如 sda）。
ums_disks() {
    local d model
    for d in /sys/block/sd*; do
        [ -e "$d" ] || continue
        model=$(cat "$d/device/model" 2>/dev/null | tr -d '\n')
        case "$model" in
        "UMS disk 0" | *"UMS"*) basename "$d" ;;
        esac
    done
}

# ums_find_unique_ums —— 整机恰好有 1 个 UMS 设备时打印 "FAT EXT"，否则返回 1。
ums_find_unique_ums() {
    local list count disk fat ext
    list=$(ums_disks)
    count=$(printf '%s\n' "$list" | grep -c . || true)
    [ "$count" = "1" ] || {
        echo "ums_find_unique_ums: UMS 设备数=$count（要求恰好 1 个）" >&2
        return 1
    }
    disk="/dev/$(printf '%s\n' "$list" | head -1)"
    fat="${disk}1"
    ext="${disk}2"
    [ -b "$fat" ] || { echo "找不到 $fat" >&2; return 1; }
    [ -b "$ext" ] || { echo "找不到 $ext" >&2; return 1; }
    echo "$fat $ext"
}

# ums_find_by_markers <marker...> —— 遍历候选设备，要求 FAT 分区里同时出现所有
# marker（mtools 的长文件名列表），且存在第二分区。打印第一条命中的 "FAT EXT"。
ums_find_by_markers() {
    local markers=("$@")
    local dev fat ext listing m ok
    for dev in /dev/sd[a-z] /dev/mmcblk[0-9]; do
        [ -b "$dev" ] || continue
        fat="${dev}1"
        ext="${dev}2"
        [ -b "$fat" ] && [ -b "$ext" ] || continue
        listing=$(mdir -i "$fat" :: 2>/dev/null) || continue
        ok=1
        # 注意：mtools 对 8.3 之外的名字会显示短名 + 长名列（fip.bin 会变成
        # "fip      bin"），所以 marker 取"一定原样出现"的长名片段。
        for m in "${markers[@]}"; do
            echo "$listing" | grep -qi -- "$m" || { ok=0; break; }
        done
        [ "$ok" = 1 ] || continue
        echo "$fat $ext"
        return 0
    done
    echo "没有认出属于本项目的 UMS 设备（对方板子也在 UMS？或这块没起 UMS）" >&2
    return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    ums_find_by_markers "$@"
fi
