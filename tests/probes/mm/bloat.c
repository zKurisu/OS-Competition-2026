/* bloat.c — 顺序缺页预取是否会对跨步访问超额预取（内存膨胀）。
 *
 * 三种访问模式各映射 64 MiB，报告耗时与 RSS：
 *   1. seq   : 每页都写        —— 应当命中预取（RSS ≈ 64 MiB）
 *   2. stride: 每 16 页写 1 页 —— 不该命中（RSS 应当 ≈ 4 MiB，即只映射触碰过的页）
 *   3. rand  : 伪随机页序      —— 不该命中（RSS 应当 ≈ 4 MiB）
 *
 * RSS 用 /proc/self/statm 的第 2 列（resident pages）换算。
 *
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define PAGE 4096UL
#define BYTES (64UL << 20)

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static long rss_kb(void) {
    FILE *f = fopen("/proc/self/statm", "r");
    long total = 0, resident = 0;
    if (!f) return -1;
    if (fscanf(f, "%ld %ld", &total, &resident) != 2) resident = -1;
    fclose(f);
    return resident < 0 ? -1 : resident * (long)(PAGE / 1024);
}

static unsigned long long rng_state = 88172645463325252ull;
static unsigned long long rng(void) {
    /* xorshift64：取全部位，避免 LCG 低位/高位截断造成「只是换个步长」 */
    unsigned long long s = rng_state;
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    rng_state = s;
    return s;
}

static void run(const char *name, int mode) {
    long before = rss_kb();
    char *p = mmap(NULL, BYTES, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        printf("BLOAT %s MMAP_FAILED\n", name);
        return;
    }
    size_t pages = BYTES / PAGE;
    double t0 = now_s();
    size_t touched = 0;
    switch (mode) {
    case 0: /* seq */
        for (size_t i = 0; i < pages; i++) { p[i * PAGE] = 1; touched++; }
        break;
    case 1: /* stride 16 */
        for (size_t i = 0; i < pages; i += 16) { p[i * PAGE] = 1; touched++; }
        break;
    default: { /* rand permutation: 触碰 1/16 的页 */
        size_t n = pages / 16;
        for (size_t k = 0; k < n; k++) {
            size_t i = (size_t)(rng() % (unsigned long long)pages);
            p[i * PAGE] = 1;
            touched++;
        }
        break;
    }
    }
    double dt = now_s() - t0;
    long after = rss_kb();
    printf("BLOAT %s pages_touched=%zu wall_ms=%.1f ns_per_touch=%.0f "
           "rss_kb_delta=%ld rss_pages_delta=%ld overmap=%.2fx\n",
           name, touched, dt * 1e3, dt * 1e9 / (double)touched,
           (after - before), (after - before) / 4,
           (double)((after - before) / 4) / (double)touched);
    munmap(p, BYTES);
}

/* 短顺序流：只碰 n 个连续页就停 —— 预取爬坡应当只多映射很少的页。
 * 这是大窗口的真实代价：固定 64 页窗口会白占 62 页（248 KiB），
 * 爬坡（8/16/32/64）只会白占 6 页。 */
static void short_run(const char *name, size_t n) {
    long before = rss_kb();
    char *p = mmap(NULL, BYTES, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        printf("BLOAT %s MMAP_FAILED\n", name);
        return;
    }
    for (size_t i = 0; i < n; i++) p[i * PAGE] = 1;
    long after = rss_kb();
    long mapped = (after - before) / 4;
    printf("BLOAT %s pages_touched=%zu rss_pages_delta=%ld overmap=%.2fx waste_kb=%ld\n",
           name, n, mapped, (double)mapped / (double)n, (after - before) - (long)n * 4);
    munmap(p, BYTES);
}

/* MADV_DONTNEED 语义：批量预取出来的页必须能被一次性丢弃并还给 RSS。 */
static void dontneed_check(void) {
    long before = rss_kb();
    char *p = mmap(NULL, BYTES, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        printf("BLOAT dontneed MMAP_FAILED\n");
        return;
    }
    /* 顺序触碰 1 MiB：预取窗口会越过 1 MiB 一点点（窗口按缺页地址对齐而不是
     * 按触碰长度截断），所以回收要按「被映射到的范围」来发，才能验证
     * 「预取出来的页照样能被 DONTNEED 一次性丢掉」。 */
    const size_t win = 1UL << 20;
    const size_t reclaim = 4UL << 20;
    for (size_t off = 0; off < win; off += PAGE) p[off] = 1;
    long peak = rss_kb();
    int rc = madvise(p, reclaim, MADV_DONTNEED);
    long after = rss_kb();
    printf("BLOAT dontneed touch_kb=%zu reclaim_kb=%zu madvise_rc=%d "
           "rss_after_touch_kb=%ld rss_after_dontneed_kb=%ld leftover_kb=%ld (want 0)\n",
           win / 1024, reclaim / 1024, rc, peak - before, after - before,
           after - before);
    munmap(p, BYTES);
}

int main(int argc, char **argv) {
    /* 行缓冲：万一某个用例把进程打挂，前面的输出还在（块缓冲会全丢）。 */
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *only = (argc > 1) ? argv[1] : "all";
    int all = strcmp(only, "all") == 0;
    printf("BLOAT begin case=%s\n", only);
    if (all || !strcmp(only, "seq")) run("seq", 0);
    if (all || !strcmp(only, "stride")) run("stride16", 1);
    if (all || !strcmp(only, "rand")) run("rand", 2);
    if (all || !strcmp(only, "short")) {
        short_run("short2", 2);
        short_run("short3", 3);
    }
    if (all || !strcmp(only, "dontneed")) dontneed_check();
    printf("BLOAT end\n");
    return 0;
}
