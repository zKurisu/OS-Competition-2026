/* touch64.c — 只做一次 64 MiB 私有匿名首触，作为「冷启动后第一次大分配」的
 * 干净取样点（fc2 会先跑 1/4/16 MiB，等轮到 64 MiB 时系统状态已经变了）。
 *
 * 用法: touch64 [MiB] [repeat]   —— 第 1 次是冷态，之后是稳定态。
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define PAGE 4096UL

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    size_t mib = (argc > 1) ? strtoul(argv[1], NULL, 10) : 64;
    int reps = (argc > 2) ? atoi(argv[2]) : 1;
    size_t bytes = mib << 20;
    size_t pages = bytes / PAGE;
    for (int r = 0; r < reps; r++) {
        char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) {
            printf("TOUCH64 rep=%d MMAP_FAILED\n", r + 1);
            return 1;
        }
        double t0 = now_s();
        for (size_t off = 0; off < bytes; off += PAGE) p[off] = 1;
        double dt = now_s() - t0;
        printf("TOUCH64 rep=%d mib=%zu pages=%zu ns_per_page=%.0f wall_ms=%.1f\n",
               r + 1, mib, pages, dt * 1e9 / (double)pages, dt * 1e3);
        munmap(p, bytes);
    }
    return 0;
}
