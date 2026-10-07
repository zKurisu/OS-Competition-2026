/* faultattrib.c — attribute the page-fault path stage by stage.
 *
 * Companion to the kernel's diagnostic /proc/fault_attrib (mm/fault_attrib.rs).
 * It reads the cumulative counters before and after each phase, so the printed
 * per-stage numbers belong to that phase only.
 *
 * Running the same region twice — once with the default policy and once with
 * MADV_HUGEPAGE — shows *where* the default path loses its time.
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

#ifndef MADV_HUGEPAGE
#define MADV_HUGEPAGE 14
#endif

#define PAGE 4096UL

struct attrib {
    long long plan, prepare, apply, tlb, mmucache, total, faults;
    long long frame_alloc, frame_zero, materialize, pending_insert, page_object;
    long long apply_prep, apply_map, apply_publish;
};

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static long long field(const char *text, const char *key) {
    const char *at = strstr(text, key);
    if (!at) {
        return -1;
    }
    return atoll(at + strlen(key));
}

static struct attrib read_attrib(void) {
    static char buf[1024];
    struct attrib a;
    memset(&a, 0xff, sizeof(a));
    const char *path = getenv("FAUTH_PATH");
    FILE *f = fopen(path ? path : "/proc/fault_attrib", "r");
    if (!f) {
        printf("FAUTH warn: /proc/fault_attrib not available (errno=%d)\n", errno);
        return a;
    }
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = '\0';
    fclose(f);
    a.plan = field(buf, "plan_ns=");
    a.prepare = field(buf, "prepare_ns=");
    a.apply = field(buf, "apply_ns=");
    a.tlb = field(buf, "tlb_ns=");
    a.mmucache = field(buf, "mmu_cache_ns=");
    a.total = field(buf, "total_ns=");
    a.faults = field(buf, "faults=");
    a.frame_alloc = field(buf, "frame_alloc_ns=");
    a.frame_zero = field(buf, "frame_zero_ns=");
    a.materialize = field(buf, "materialize_ns=");
    a.pending_insert = field(buf, "pending_insert_ns=");
    a.page_object = field(buf, "page_object_ns=");
    a.apply_prep = field(buf, "apply_prep_ns=");
    a.apply_map = field(buf, "apply_map_ns=");
    a.apply_publish = field(buf, "apply_publish_ns=");
    return a;
}

static void phase(const char *name, size_t bytes, int huge) {
    struct attrib a0 = read_attrib();
    double t0 = now_s();
    char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) {
        printf("FAUTH %s mmap_failed errno=%d (%s)\n", name, errno, strerror(errno));
        return;
    }
    if (huge && madvise(p, bytes, MADV_HUGEPAGE) != 0) {
        printf("FAUTH %s madvise_failed errno=%d (%s)\n", name, errno, strerror(errno));
    }
    for (size_t off = 0; off < bytes; off += PAGE) {
        p[off] = 1;
    }
    double wall = now_s() - t0;
    struct attrib a1 = read_attrib();
    munmap(p, bytes);

    long long faults = a1.faults - a0.faults;
    printf("FAUTH %-14s bytes=%zu wall_ms=%.1f faults=%lld ns_per_fault=%.0f\n",
           name, bytes, wall * 1000.0, faults,
           faults > 0 ? wall * 1e9 / (double)faults : 0.0);
    if (faults > 0) {
        printf("      plan=%lld prepare=%lld apply=%lld tlb=%lld mmu_cache=%lld\n",
               (a1.plan - a0.plan) / faults, (a1.prepare - a0.prepare) / faults,
               (a1.apply - a0.apply) / faults, (a1.tlb - a0.tlb) / faults,
               (a1.mmucache - a0.mmucache) / faults);
        printf("      inner: materialize=%lld pending_insert=%lld page_object=%lld\n",
               (a1.materialize - a0.materialize) / faults,
               (a1.pending_insert - a0.pending_insert) / faults,
               (a1.page_object - a0.page_object) / faults);
        printf("      inner: frame_alloc=%lld frame_zero=%lld apply_prep=%lld "
               "apply_map=%lld apply_publish=%lld\n",
               (a1.frame_alloc - a0.frame_alloc) / faults,
               (a1.frame_zero - a0.frame_zero) / faults,
               (a1.apply_prep - a0.apply_prep) / faults,
               (a1.apply_map - a0.apply_map) / faults,
               (a1.apply_publish - a0.apply_publish) / faults);
    }
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    long mib = (argc > 1) ? atol(argv[1]) : 64;
    size_t bytes = (size_t)mib * 1024 * 1024;
    printf("== fault attribution, region=%ld MiB ==\n", mib);
    phase("default", bytes, 0);
    phase("madv_hugepage", bytes, 1);
    printf("FAUTH end\n");
    return 0;
}
