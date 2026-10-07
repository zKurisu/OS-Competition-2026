/* popcost.c — 批量 populate 路径的每页成本 vs. 逐页缺页。
 *
 * 目的：判断「匿名缺页预取批处理（fault-around）」值不值得做。
 *   - MAP_POPULATE 走的是内核的批量 populate_area 原语（一次事务映射整段），
 *     所以对 16 页（64 KiB）调用它就等于「一批 16 页」的成本上界；
 *   - 同一段内存用逐页触碰再测一次，两者之比就是批量能省下的份额。
 *
 * Build: riscv64-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define PAGE 4096UL

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static long memfree_kb(void) {
    FILE *f = fopen("/proc/meminfo", "r");
    char line[256];
    long v = -1;
    if (!f) return -1;
    while (fgets(line, sizeof line, f)) {
        if (sscanf(line, "MemFree: %ld", &v) == 1) break;
    }
    fclose(f);
    return v;
}

/* 批量路径：mmap(MAP_POPULATE) 建映射 + 立刻映满 */
static void populate_cost(size_t bytes) {
    double t0 = now_s();
    char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    double dt = now_s() - t0;
    if (p == MAP_FAILED) {
        printf("POPCOST populate size=%zuKiB MMAP_FAILED errno=%d\n", bytes >> 10, errno);
        return;
    }
    /* 读回一页确认确实映射了 */
    volatile char c = p[0] + p[bytes - PAGE];
    (void)c;
    printf("POPCOST populate size=%zuKiB pages=%zu ns_per_page=%.0f wall_ms=%.2f\n",
           bytes >> 10, bytes / PAGE, dt * 1e9 / (double)(bytes / PAGE), dt * 1e3);
    munmap(p, bytes);
}

/* 逐页缺页路径 */
static void touch_cost(size_t bytes) {
    char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        printf("POPCOST touch size=%zuKiB MMAP_FAILED errno=%d\n", bytes >> 10, errno);
        return;
    }
    double t0 = now_s();
    for (size_t off = 0; off < bytes; off += PAGE) p[off] = 1;
    double dt = now_s() - t0;
    printf("POPCOST touch    size=%zuKiB pages=%zu ns_per_page=%.0f wall_ms=%.2f\n",
           bytes >> 10, bytes / PAGE, dt * 1e9 / (double)(bytes / PAGE), dt * 1e3);
    munmap(p, bytes);
}

/* 逐页缺页，但一次推进 16 页（模拟 fault-around 的访存模式，防止 malloc 合并） */
static void touch_stride16_cost(size_t bytes) {
    char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return;
    double t0 = now_s();
    for (size_t off = 0; off < bytes; off += PAGE * 16) p[off] = 1;
    double dt = now_s() - t0;
    (void)dt;
    munmap(p, bytes);
}

int main(int argc, char **argv) {
    static const size_t sizes[] = {64UL << 10, 256UL << 10, 1UL << 20,
                                   4UL << 20, 16UL << 20, 64UL << 20};
    printf("POPCOST begin memfree=%ldkB\n", memfree_kb());
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        populate_cost(sizes[i]);
        touch_cost(sizes[i]);
    }
    /* 只做一次，确认采样噪声 */
    populate_cost(64UL << 10);
    touch_cost(64UL << 10);
    printf("POPCOST end memfree=%ldkB\n", memfree_kb());
    (void)argv;
    (void)argc;
    (void)touch_stride16_cost;
    return 0;
}
