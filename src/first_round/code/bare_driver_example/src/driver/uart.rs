// ── UART driver (NS16550 @ 0x10000000) ──────────────────────────────
const UART: usize = 0x10000000;  // 寄存器组开始的位置
const LSR: usize = 5;
const THR: usize = 0;
const RBR: usize = 0;
const LSR_RX: u8 = 1 << 0;
const LSR_TX: u8 = 1 << 5;

fn uart_read(off: usize) -> u8 {
    unsafe { ((UART + off) as *const u8).read_volatile() }
}

fn uart_write(off: usize, val: u8) {
    unsafe { ((UART + off) as *mut u8).write_volatile(val) }
}

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

pub fn uart_init() {
    // QEMU's 16550 works out of the box; minimal init
    uart_write(1, 0x00); // disable interrupts
    uart_write(3, 0x80); // DLAB=1
    uart_write(0, 0x01); // divisor LSB
    uart_write(1, 0x00); // divisor MSB
    uart_write(3, 0x03); // 8N1, DLAB=0
}

