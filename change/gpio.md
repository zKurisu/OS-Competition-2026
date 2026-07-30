# GPIO 驱动实现

[技术参考手册](https://github.com/sophgo/sophgo-doc/blob/main/SG200X/TRM/contents/cn/peripherals/gpio.rst)

## 修改内容

1. os/StarryOS/kernel/src/pseudofs/dev/gpio.rs

- read_at: 返回 4 组 GPIO 寄存器的可读状态（DR/DDR/EXT），便于 cat /dev/gpio 调试
- write_at: 文本控制接口，例如 echo "0 6 out" > /dev/gpio（设 GPIO0 第6脚为输出）、echo "0 6 1" > /dev/gpio（输出高电平）
- ioctl: 三个命令 — GPIO_SET_DIR(0x01)、GPIO_SET_VAL(0x02)、GPIO_GET_VAL(0x03)，均通过 GPIOOp { group, offset, value } 结构体传参
- 封装了 read_register、modify_register、read_pin、write_pin、set_direction 等 MMIO 底层操作

2. os/StarryOS/kernel/src/pseudofs/dev/mod.rs:

- 添加 mod gpio（#[cfg(feature = "sg2002")]）
- 在 builder() 的 #[cfg(feature = "sg2002")] 块中注册 /dev/gpio (设备号 1, 253)

补丁见分支 [tgos-patches](../../tree/tgos-patches)
