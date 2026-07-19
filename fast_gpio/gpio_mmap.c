/*
 * gpio_mmap.c — 通过 /dev/mem + mmap 直接操作 SG2002 GPIO
 *
 *   ./gpio_mmap <bank> <pin> <cmd> [value]
 *     bank: 0-3 (GPIO bank)
 *     pin:  0-31
 *     cmd:  out | high | low | read | blink
 *     value: (blink 时可选，默认 0.5 秒间隔)
 *
 * 示例:
 *   ./gpio_mmap 0 17 out         # GPIO0.17 设为输出 (配合 A17 引脚)
 *   ./gpio_mmap 0 17 high        # GPIO0.17 输出高电平
 *   ./gpio_mmap 0 17 low         # GPIO0.17 输出低电平
 *   ./gpio_mmap 1 5  read        # GPIO1.5  读取输入状态
 *   ./gpio_mmap 0 17 blink 0.2   # GPIO0.17 闪烁, 0.2 秒间隔
 *
 * 注意:
 *   运行前需通过 /dev/pinmux 将引脚设为 GPIO 功能:
 *     echo "0x<offset> 0" > /dev/pinmux
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <errno.h>

#define PAGE_SIZE   4096

/* GPIO 寄存器基地址 (SG2002/CV181x) */
#define GPIO0_BASE  0x03020000
#define GPIO1_BASE  0x03021000
#define GPIO2_BASE  0x03022000
#define GPIO3_BASE  0x03023000

/* GPIO 寄存器偏移 (DesignWare APB GPIO) */
#define SWPORTA_DR   0x00   /* 数据寄存器 (输出) */
#define SWPORTA_DDR  0x04   /* 方向寄存器 (0=输入, 1=输出) */
#define EXT_PORTA    0x50   /* 外部端口 (读取实际引脚电平) */

/* 内存屏障 (架构自适应) */
#if defined(__riscv)
#define mmio_fence()  __asm__ volatile("fence iorw,iorw" ::: "memory")
#define mmio_fence_w() __asm__ volatile("fence ow,ow"   ::: "memory")
#elif defined(__aarch64__)
#define mmio_fence()  __asm__ volatile("dmb ish" ::: "memory")
#elif defined(__x86_64__) || defined(__i386__)
/* volatile 本身已做 Load+Store 序; 编译器屏障即可 */
#define mmio_fence()  __asm__ volatile("" ::: "memory")
#else
#define mmio_fence()  __asm__ volatile("" ::: "memory")
#endif

static const uint32_t gpio_bases[] = {
    GPIO0_BASE, GPIO1_BASE, GPIO2_BASE, GPIO3_BASE
};

typedef struct {
    int            mem_fd;
    volatile void *base;     /* mmap 映射基地址 */
    size_t         page_off; /* 页内偏移 */
    uint32_t       phys;     /* GPIO bank 物理基地址 */
} gpio_ctx_t;

static int gpio_open(gpio_ctx_t *ctx, int bank, int pin)
{
    (void)pin;

    if (bank < 0 || bank > 3) {
        fprintf(stderr, "无效的 GPIO bank: %d\n", bank);
        return -1;
    }

    ctx->phys = gpio_bases[bank];
    ctx->page_off = ctx->phys & (PAGE_SIZE - 1);
    ctx->mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (ctx->mem_fd < 0) {
        perror("open /dev/mem");
        return -1;
    }

    ctx->base = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE,
                     MAP_SHARED, ctx->mem_fd,
                     ctx->phys & ~(PAGE_SIZE - 1));
    if (ctx->base == MAP_FAILED) {
        perror("mmap");
        close(ctx->mem_fd);
        return -1;
    }

    return 0;
}

static void gpio_close(gpio_ctx_t *ctx)
{
    munmap((void *)ctx->base, PAGE_SIZE);
    close(ctx->mem_fd);
}

static volatile uint32_t *gpio_reg(gpio_ctx_t *ctx, uint32_t offset)
{
    return (volatile uint32_t *)((char *)ctx->base + ctx->page_off + offset);
}

static void gpio_set_direction(gpio_ctx_t *ctx, int pin, int output)
{
    volatile uint32_t *ddr = gpio_reg(ctx, SWPORTA_DDR);
    mmio_fence();
    if (output) {
        *ddr |= (1u << pin);
    } else {
        *ddr &= ~(1u << pin);
    }
    mmio_fence();
}

static void gpio_write(gpio_ctx_t *ctx, int pin, int value)
{
    volatile uint32_t *dr = gpio_reg(ctx, SWPORTA_DR);
    mmio_fence();
    if (value) {
        *dr |= (1u << pin);
    } else {
        *dr &= ~(1u << pin);
    }
    mmio_fence();
}

static int gpio_read(gpio_ctx_t *ctx, int pin)
{
    volatile uint32_t *ext = gpio_reg(ctx, EXT_PORTA);
    mmio_fence();
    int val = (*ext >> pin) & 1;
    mmio_fence();
    return val;
}

static void usage(const char *prog)
{
    fprintf(stderr,
        "用法: %s <bank> <pin> <cmd> [arg]\n"
        "\n"
        "  bank       GPIO 组   (0-3)\n"
        "  pin        引脚编号  (0-31)\n"
        "  cmd        命令，可选:\n"
        "               out      设为输出 (默认高电平)\n"
        "               in       设为输入\n"
        "               high     输出高电平\n"
        "               low      输出低电平\n"
        "               toggle   翻转电平\n"
        "               read     读取输入电平\n"
        "               blink    闪烁, arg=间隔秒数 (默认 0.5)\n"
        "\n"
        "示例:\n"
        "  %s 0 17 out          # GPIO0.17 设为输出\n"
        "  %s 0 17 high         # GPIO0.17 输出高\n"
        "  %s 0 17 blink 0.2    # GPIO0.17 以 0.2s 间隔闪烁\n"
        "  %s 1 5  read         # GPIO1.5 读取电平\n",
        prog, prog, prog, prog, prog);
}

int main(int argc, char *argv[])
{
    if (argc < 4) {
        usage(argv[0]);
        return 1;
    }

    int bank   = atoi(argv[1]);
    int pin    = atoi(argv[2]);
    const char *cmd = argv[3];

    if (pin < 0 || pin > 31) {
        fprintf(stderr, "无效的引脚编号: %d (需要 0-31)\n", pin);
        return 1;
    }

    gpio_ctx_t ctx;
    if (gpio_open(&ctx, bank, pin) < 0) {
        return 1;
    }

    int ret = 0;

    if (strcmp(cmd, "out") == 0) {
        gpio_set_direction(&ctx, pin, 1);
        gpio_write(&ctx, pin, 1);
        printf("GPIO%d.%d 设为输出, 初始值: 高\n", bank, pin);

    } else if (strcmp(cmd, "in") == 0) {
        gpio_set_direction(&ctx, pin, 0);
        printf("GPIO%d.%d 设为输入\n", bank, pin);

    } else if (strcmp(cmd, "high") == 0) {
        gpio_write(&ctx, pin, 1);
        printf("GPIO%d.%d → 高\n", bank, pin);

    } else if (strcmp(cmd, "low") == 0) {
        gpio_write(&ctx, pin, 0);
        printf("GPIO%d.%d → 低\n", bank, pin);

    } else if (strcmp(cmd, "toggle") == 0) {
        int cur = gpio_read(&ctx, pin);
        gpio_write(&ctx, pin, !cur);
        printf("GPIO%d.%d: %d → %d\n", bank, pin, cur, !cur);

    } else if (strcmp(cmd, "read") == 0) {
        int val = gpio_read(&ctx, pin);
        printf("GPIO%d.%d = %d\n", bank, pin, val);

    } else if (strcmp(cmd, "blink") == 0) {
        double interval = (argc > 4) ? atof(argv[4]) : 0.5;
        int usec = (int)(interval * 1000000);
        if (usec < 10000) usec = 10000;

        gpio_set_direction(&ctx, pin, 1);
        printf("GPIO%d.%d 闪烁, 间隔 %.2fs (Ctrl-C 停止)\n", bank, pin, interval);

        for (int i = 0; ; i++) {
            gpio_write(&ctx, pin, i & 1);
            usleep(usec);
        }

    } else {
        fprintf(stderr, "未知命令: %s\n", cmd);
        usage(argv[0]);
        ret = 1;
    }

    gpio_close(&ctx);
    return ret;
}
