/* insbench.c — 标定「在 512 KiB 数组里做一次分散位置的插入搬移」到底该多快。
 *
 * 目的是判断内核 CowPageIndex 的 pend_store（老化态 74 µs/次、平均只搬
 * 251 个 32 字节条目 = 8 KB）是不是合理：如果用户态同样模式能到 ~1 GB/s，
 * 那问题就不在 memmove 本身。
 *
 * 分布按内核里的实测直方图构造：追加 21%、距尾部 ≤64 的 ~68%、更远的 ~11%。
 *
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ENTRY 32UL

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* 数组元素按 paddr 排序：这里用「插入位置」直接模拟内核里的分布 */
static unsigned long long rng_state = 1234567891234567ull;
static unsigned long long rng(void) {
    unsigned long long s = rng_state;
    s ^= s << 13; s ^= s >> 7; s ^= s << 17;
    rng_state = s;
    return s;
}

int main(int argc, char **argv) {
    size_t entries = (argc > 1) ? strtoul(argv[1], NULL, 10) : 16384;
    size_t rounds  = (argc > 2) ? strtoul(argv[2], NULL, 10) : 1;

    /* 一次插满 entries 个，位置分布模拟内核实测（越接近尾部越便宜） */
    unsigned char *buf = malloc(entries * ENTRY);
    if (!buf) { printf("INSBENCH alloc_fail\n"); return 1; }

    double best_ns = 1e30;
    unsigned long long shifted_total = 0;
    for (size_t r = 0; r < rounds; r++) {
        size_t len = 0;
        unsigned long long shifted = 0;
        double t0 = now_s();
        for (size_t k = 0; k < entries; k++) {
            unsigned long long roll = rng() % 100;
            size_t dist;               /* 距尾部的条目数 */
            if (roll < 21) {
                dist = 0;              /* 追加 */
            } else if (roll < 89) {
                dist = 1 + (rng() % 64);
            } else {
                dist = 1 + (rng() % (len ? len : 1));
            }
            size_t pos = (dist > len) ? 0 : len - dist;
            /* 搬移 len-pos 个条目：等价 Vec::insert */
            memmove(buf + (pos + 1) * ENTRY, buf + pos * ENTRY, (len - pos) * ENTRY);
            memset(buf + pos * ENTRY, (int)(k & 0xff), ENTRY);
            shifted += len - pos;
            len++;
        }
        double dt = now_s() - t0;
        if (dt * 1e9 < best_ns) best_ns = dt * 1e9;
        shifted_total = shifted;
    }
    double mb = (double)shifted_total * ENTRY / 1e6;
    printf("INSBENCH entries=%zu rounds=%zu total_ms=%.1f shifted_entries=%llu "
           "shifted_MB=%.1f per_insert_ns=%.0f effective_MBps=%.0f\n",
           entries, rounds, best_ns / 1e6, shifted_total, mb,
           best_ns / (double)entries, mb / (best_ns / 1e9));
    free(buf);
    return 0;
}
