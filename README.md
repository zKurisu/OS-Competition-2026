# Intro
这里记录下最基础的驱动编写流程, 以 QEMU Virt 主机的 UART NS16550 为例. 示例程序已经放在 `my-bare` 目录下, 可以直接尝试:

```sh
cd my-bare

# 编译
cargo build --release

# 运行 (Ctrl+A 再按 X 退出)
qemu-system-riscv64 \
    -machine virt -cpu rv64 -smp 1 -m 128M -nographic \
    -bios default \
    -kernel target/riscv64gc-unknown-none-elf/release/my-bare
```

下面内容是完整的流程解释.

# 构建裸机运行环境
裸机驱动其实也就是裸机上运行的程序, 通过 MMIO 映射完成对外设的操作. 因此第一步就是构建裸机运行环境.

先创建一个 `cargo` 项目, 这里暂时用 `2021` 版:
```sh
cargo new my-bare
cd my-bare
cat > Cargo.toml <<EOF
[package]
name = "my-bare"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
```

配置一下构建信息和交叉编译信息, 指定链接脚本为 `src/linker.ld`:
```sh
mkdir .cargo
cat > .cargo/config.toml <<EOF
[build]
target = "riscv64gc-unknown-none-elf"

[target.riscv64gc-unknown-none-elf]
rustflags = ["-C", "link-arg=-Tsrc/linker.ld"]
EOF
```

## 内存布局
在 `src/linker.ld` 文件中加入下面内容, 手动指定一下入口符号, 链接顺序等:

```linker
ENTRY(_start);
OUTPUT_ARCH(riscv);
BASE_ADDRESS = 0x80200000;

SECTIONS
{
    . = BASE_ADDRESS;
    skernel = .;

    stext = .;
    .text : {
        *(.text.entry)
        *(.text .text.*)
    }

    . = ALIGN(4K);
    etext = .;
    srodata = .;
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    }

    . = ALIGN(4K);
    erodata = .;
    sdata = .;
    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    }

    . = ALIGN(4K);
    edata = .;
    .bss : {
        *(.bss.stack)
        sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
    }

    . = ALIGN(4K);
    ebss = .;
    ekernel = .;

    /DISCARD/ : {
        *(.eh_frame)
    }
}
```

## 汇编入口
在汇编里面完成栈空间的分配并跳转到 rust 入口, 在 `src/entry.asm` 中写入:

```asm
    .section .text
    .global _start
_start:
    la sp, _stack_top
    call rust_main
    
    .section .bss.stack
    .global _stack_base
_stack_base:
    .space 4096 * 16 
    .global _stack_top
_stack_top:
```

## 主程序
需要在 `no_std` 和 `no_main` 的环境下启动, 在 `src/main.rs` 中写入:
```rust
#![no_main]
#![no_std]

use core::arch::global_asm;
use core::panic::PanicInfo;

global_asm!(include_str!("entry.asm"));

#[panic_handler]
fn panic_handler(info: &PanicInfo) -> ! {
    loop {}
}

pub fn clear_bss() {
    extern "C" {
        fn sbss();
        fn ebss();
    }
    (sbss as usize..ebss as usize)
        .for_each(|a| unsafe { (a as *mut u8).write_volatile(0) });
}

#[no_mangle]
pub fn rust_main() {
    clear_bss();
}
```

此时可以编译成功即可开始下一步:
```sh
cargo build --release
```

## 驱动
```sh
cd my-bare
mkdir src/driver
touch src/driver/{mod.rs,uart.rs}
```

QEMU virt 会把 UART 控制器的寄存器组映射到物理地址 `0x10000000` 处. CPU 读写这个地址范围, 就等于直接跟 UART 硬件对话, 等价于用裸指针操作硬件寄存器.

NS16559 内部有一组 8 位寄存器, 相当于每个地址偏移对应一个寄存器, 这里只用到了 4 种:
- `THR`, Transmit Holding Register, 用于存储要发送的字节 (8 bits). 在偏移 `0` 位置
- `RBR`, Receiver Buffer Register, 用于存储接收的字节. 也是偏移 `0` 的位置 (与 `THR` 共用)
- `LSR`, Line Status Register, 用于查询通信状态

对于 `LSR`, 这里用到两个 bits:
| 位     | 常量     | 含义        |
|-------|--------|-----------|
| bit 0 | LSR_RX | 为 1 表示收到一个字节    |
| bit 5 | LSR_TX | 为 1 表示发送器空闲，可以写 |

下面会分段列出在 `src/driver/uart.rs` 中加入的代码, 首先就是上述寄存器位置偏移的定义:
```rust
// ── UART driver (NS16550 @ 0x10000000) ──────────────────────────────
const UART: usize = 0x10000000;  // 寄存器组开始的位置
const LSR: usize = 5;
const THR: usize = 0;
const RBR: usize = 0;
const LSR_RX: u8 = 1 << 0;
const LSR_TX: u8 = 1 << 5;
```

之后定义两个函数来读写指定偏移的寄存器内容:
```rust
fn uart_read(off: usize) -> u8 {
    unsafe { ((UART + off) as *const u8).read_volatile() }
}

fn uart_write(off: usize, val: u8) {
    unsafe { ((UART + off) as *mut u8).write_volatile(val) }
}
```

之后定义字符串读取和打印的逻辑:
- `uart_putc`, 当 `LSR_TX` 置为 `1` 的时候, 向 `THR` 寄存器写入一个字符
- `uart_getc`, 当 `LSR_RX` 置为 `1` 的时候, 从 `RBR` 寄存器读取一个字符

```rust
pub fn uart_putc(c: u8) {
    while uart_read(LSR) & LSR_TX == 0 {}
    uart_write(THR, c);
}

pub fn uart_puts(s: &str) {
    for b in s.bytes() {
        if b == b'\n' {
            uart_putc(b'\r');
        }
        uart_putc(b);
    }
}

pub fn uart_getc() -> u8 {
    while uart_read(LSR) & LSR_RX == 0 {}
    uart_read(RBR)
}
```

使用 NS16550 需要进行初始化, 即写一些控制寄存器:
```rust
pub fn uart_init() {
    // QEMU's 16550 works out of the box; minimal init
    uart_write(1, 0x00); // disable interrupts
    uart_write(3, 0x80); // DLAB=1
    uart_write(0, 0x01); // divisor LSB
    uart_write(1, 0x00); // divisor MSB
    uart_write(3, 0x03); // 8N1, DLAB=0
}
```

最后在 `mod.rs` 中加入:
```rust
pub mod uart;

pub use uart::{uart_init, uart_putc, uart_puts, uart_getc};
```

## 测试
此时 `rust_main` 函数变更为:
```rust
mod driver;
use driver::uart::*;

#[no_mangle]
pub fn rust_main() -> ! {
    clear_bss();
    uart_init();
    uart_puts("\nRISC-V 64 Bare-Metal (Rust)\nType anything, 'q' to quit.\n\n");
    loop {
        let c = uart_getc();
        uart_putc(c);
        if c == b'\r' {
            uart_putc(b'\n');
        }
        if c == b'q' {
            break;
        }
    }

    uart_puts("\nShutting down...\n");

    // SBI shutdown
    unsafe {
        core::arch::asm!("ecall", in("a7") 0x08u64, in("a6") 0u64);
    }

    loop {}
}
```

之后:
```sh
# 编译
cargo build --release

# 运行 (Ctrl+A 再按 X 退出)
qemu-system-riscv64 \
    -machine virt -cpu rv64 -smp 1 -m 128M -nographic \
    -bios default \
    -kernel target/riscv64gc-unknown-none-elf/release/my-bare
```

输出:
```sh
Boot HART ID                : 0
Boot HART Domain            : root
Boot HART Priv Version      : v1.12
Boot HART Base ISA          : rv64imafdch
Boot HART ISA Extensions    : sstc,zicntr,zihpm,zicboz,zicbom,sdtrig,svadu
Boot HART PMP Count         : 16
Boot HART PMP Granularity   : 2 bits
Boot HART PMP Address Bits  : 54
Boot HART MHPM Info         : 16 (0x0007fff8)
Boot HART Debug Triggers    : 2 triggers
Boot HART MIDELEG           : 0x0000000000001666
Boot HART MEDELEG           : 0x0000000000f4b509

RISC-V 64 Bare-Metal (Rust)
Type anything, 'q' to quit.
```

之后的每一次按键都会有回显, 说明成功了.
