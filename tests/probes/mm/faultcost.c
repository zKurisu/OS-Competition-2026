/* faultcost.c — page-fault cost vs region size, plus madvise A/B.
 *
 * The report's thp_* probes are unusable on SG2002 (thp_protnone needs 256 x
 * 8 MiB = 2 GiB of churn; the others run > 90 s or fail outright). This is a
 * bounded replacement that answers the same question — "how much does one
 * first-touch cost, and does anything promote to huge pages?":
 *
 *   1. for each size: mmap -> touch one byte per 4 KiB -> per-page cost;
 *      a jump down at larger sizes = some form of huge-page promotion;
 *   2. MADV_HUGEPAGE vs MADV_NOHUGEPAGE A/B at the largest size;
 *   3. MADV_POPULATE_WRITE (bulk populate) vs manual touch, when supported.
 *
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#ifndef MADV_POPULATE_WRITE
#define MADV_POPULATE_WRITE 23
#endif

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

/* 逐页触碰，返回 ns/page */
static double touch_cost(size_t bytes, int advice) {
    char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        printf("FAULTCOST size=%zuMiB advice=%d MMAP_FAILED errno=%d\n",
               bytes >> 20, advice, errno);
        return -1;
    }
    if (advice >= 0) madvise(p, bytes, advice);
    double t0 = now_s();
    for (size_t off = 0; off < bytes; off += PAGE) p[off] = 1;
    double dt = now_s() - t0;
    munmap(p, bytes);
    return dt * 1e9 / (double)(bytes / PAGE);
}

/* MADV_POPULATE_WRITE：内核批量建立映射（如果支持） */
static void populate_cost(size_t bytes) {
    char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return;
    double t0 = now_s();
    int rc = madvise(p, bytes, MADV_POPULATE_WRITE);
    double dt = now_s() - t0;
    if (rc != 0) {
        printf("FAULTCOST populate_write size=%zuMiB UNSUPPORTED errno=%d\n",
               bytes >> 20, errno);
    } else {
        printf("FAULTCOST populate_write size=%zuMiB %.0f ns/page\n",
               bytes >> 20, dt * 1e9 / (double)(bytes / PAGE));
    }
    munmap(p, bytes);
}

int main(void) {
    const size_t sizes[] = {1, 4, 16, 64}; /* MiB */
    printf("FAULTCOST begin memfree=%ldkB\n", memfree_kb());
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        double nspp = touch_cost(sizes[i] << 20, -1);
        if (nspp > 0)
            printf("FAULTCOST touch size=%zuMiB %.0f ns/page\n", sizes[i], nspp);
    }
    /* 最大尺寸上做 madvise A/B（THP 提示是否有效） */
    size_t big = 64UL << 20;
    printf("FAULTCOST madvise_nohugepage size=64MiB %.0f ns/page\n",
           touch_cost(big, MADV_NOHUGEPAGE));
    printf("FAULTCOST madvise_hugepage   size=64MiB %.0f ns/page\n",
           touch_cost(big, MADV_HUGEPAGE));
    populate_cost(big);
    printf("FAULTCOST end memfree=%ldkB\n", memfree_kb());
    return 0;
}
