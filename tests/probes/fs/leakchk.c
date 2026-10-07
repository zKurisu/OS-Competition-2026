/* leakchk.c — does mmap/touch/munmap churn leak memory?
 *
 * thp_protnone's T1 phase does exactly this loop and失败于 T1_mmap on SG2002
 * ("leak-exhaustion is also a failure" per its own comment), so measure the
 * free-memory trajectory directly: same mapping, touch, unmap, N times, print
 * MemFree after every iteration. A monotonic drop = leak.
 *
 * Usage: leakchk [MiB_per_region=8] [iters=10]
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static long meminfo_kb(const char *key) {
    FILE *f = fopen("/proc/meminfo", "r");
    char line[256];
    long val = -1;
    if (!f)
        return -1;
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, key, strlen(key)) == 0) {
            sscanf(line + strlen(key), ": %ld", &val);
            break;
        }
    }
    fclose(f);
    return val;
}

int main(int argc, char **argv) {
    size_t mib = (argc > 1) ? (size_t)strtoul(argv[1], NULL, 10) : 8;
    int iters = (argc > 2) ? atoi(argv[2]) : 10;
    size_t sz = mib * 1024UL * 1024UL;

    printf("LEAKCHK region=%zuMiB iters=%d\n", mib, iters);
    printf("LEAKCHK memfree_before=%ldkB\n", meminfo_kb("MemFree"));

    for (int i = 0; i < iters; i++) {
        char *p = mmap(NULL, sz, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) {
            printf("LEAKCHK iter=%d MMAP_FAILED\n", i);
            break;
        }
        for (size_t off = 0; off < sz; off += 4096)
            p[off] = 1; /* dense touch: every page resident */
        if (munmap(p, sz) != 0) {
            printf("LEAKCHK iter=%d MUNMAP_FAILED\n", i);
            break;
        }
        printf("LEAKCHK iter=%d memfree=%ldkB\n", i, meminfo_kb("MemFree"));
        fflush(stdout);
    }
    printf("LEAKCHK memfree_after=%ldkB\n", meminfo_kb("MemFree"));
    return 0;
}
