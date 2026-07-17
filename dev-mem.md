# 添加 /dev/mem

基于 tgoskits 版本添加 `/dev/mem` 文件

## 修改内容

1. 新增 kernel/src/pseudofs/dev/mem.rs

实现了 MemDev 设备，提供三种操作:

- mmap(offset, length) — 返回 DeviceMmap::Physical，让内核将物理地址直接线性映射到用户空间虚拟地址（uncached）
- read_at(buf, offset) — 通过 phys_to_virt 将物理地址转虚拟地址后直接拷贝
- write_at(buf, offset) — 同上，写方向

2. 修改 kernel/src/pseudofs/dev/mod.rs

- 添加 mod mem;
- 注册 /dev/mem（device_id = (1, 1)，使用 Linux 标准）
- pinmux 的 device_id 冲突：(1, 1) → (1, 254)

3. 实现了一个简单快速的mmap程序，通过写内存实现驱动gpio

具体代码和补丁(dev_mem_gpio.patch)见分支 [tgos-patches](./tgos-patches)
