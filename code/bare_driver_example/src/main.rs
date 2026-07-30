#![no_main]
#![no_std]

mod driver;
use driver::uart::*;

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

