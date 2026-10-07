/*
 * probes_arch.h - architecture-portable monotonic counter for the board probes.
 *
 * The RK3588 harness read CNTVCT_EL0/CNTFRQ_EL0 directly. SG2002 is riscv64:
 * there is no userspace-visible counter-frequency register, so the counter rate
 * is recovered by measuring the `time` CSR (rdtime) against CLOCK_MONOTONIC.
 *
 * Both paths expose the same two calls:
 *   pp_rd_time()   - monotonic counter value, cheap enough for a timed window.
 *   pp_resolve_hz() - counter ticks per second.
 *
 * aarch64 keeps the original CNTVCT_EL0/CNTFRQ_EL0 semantics so the RK3588
 * numbers stay comparable; riscv64 self-calibrates.
 */
#ifndef PROBES_ARCH_H
#define PROBES_ARCH_H

#include <stdint.h>
#include <time.h>

#if defined(__aarch64__)

static inline uint64_t pp_rd_time(void) {
    uint64_t value;
    __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(value) :: "memory");
    return value;
}

static inline uint64_t pp_resolve_hz(void) {
    uint64_t freq;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(freq));
    return freq ? freq : 24000000ULL;
}

#elif defined(__riscv)

static inline uint64_t pp_rd_time(void) {
    uint64_t value;
    __asm__ volatile("rdtime %0" : "=r"(value) :: "memory");
    return value;
}

/*
 * Recover the rdtime rate in Hz by spinning for ~20 ms of CLOCK_MONOTONIC time.
 * A spin (not nanosleep) is used so the calibration also works on StarryOS,
 * where sleeping tasks may be scheduled with coarse granularity. The result is
 * consistent with CLOCK_MONOTONIC by construction, which is the reference the
 * probes are compared against on both OSes.
 */
static inline uint64_t pp_resolve_hz(void) {
    static uint64_t cached_hz = 0;
    if (cached_hz) {
        return cached_hz;
    }

    struct timespec start, now;
    clock_gettime(CLOCK_MONOTONIC, &start);
    uint64_t c0 = pp_rd_time();

    uint64_t elapsed_ns;
    do {
        clock_gettime(CLOCK_MONOTONIC, &now);
        elapsed_ns = (uint64_t)(now.tv_sec - start.tv_sec) * 1000000000ULL
                   + (uint64_t)(now.tv_nsec - start.tv_nsec);
    } while (elapsed_ns < 20000000ULL);

    uint64_t c1 = pp_rd_time();
    if (elapsed_ns == 0 || c1 <= c0) {
        return 25000000ULL; /* SG2002 nominal timebase; only used if calibration fails */
    }

    cached_hz = (uint64_t)((double)(c1 - c0) * 1e9 / (double)elapsed_ns);
    return cached_hz;
}

#else
#error "probes_arch.h: unsupported architecture"
#endif

#endif /* PROBES_ARCH_H */
