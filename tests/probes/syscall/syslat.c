// syslat —— 空系统调用（getpid）往返耗时，用于 /proc/icache_flush 的 A/B。
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

int main(int argc, char **argv) {
    long n = argc > 1 ? atol(argv[1]) : 20000;
    for (int i = 0; i < 2000; i++) {
        (void)getpid();
    }
    uint64_t t0 = now_ns();
    for (long i = 0; i < n; i++) {
        (void)getpid();
    }
    uint64_t t1 = now_ns();
    double per_us = (double)(t1 - t0) / (double)n / 1000.0;
    printf("getpid: n=%ld total=%.3f ms  per-call=%.3f us\n",
           n, (double)(t1 - t0) / 1e6, per_us);
    return 0;
}
