/* syscost2.c — attribute the per-syscall cost, following the report's §05
 * method (bisect the entry path with different handler bodies).
 *
 * The report found StarryOS's per-syscall cost on ARM was dominated by timer
 * accounting, and its biggest win came from skipping the POSIX-timer table
 * traversal when the process has no timer armed ("itimer_armed"). On SG2002
 * our getpid is 11–15 us while Linux is 0.42 us, so this probe asks the same
 * question on riscv64:
 *
 *   1. a battery of syscalls with very different handler bodies
 *      (invalid syscall vs getpid vs clock_gettime vs itimer ...);
 *   2. getpid measured **with and without** an armed itimer — if the cost
 *      jumps when a timer is armed, the per-syscall timer path is the culprit.
 *
 * Output: SYSCOST2 <name> <ns>/call
 * Build:  riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

static volatile long sink;

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

#define BENCH(name, n, expr)                       \
    do {                                           \
        double t0 = now_ns();                      \
        for (long i = 0; i < (n); i++) { expr; }   \
        double t1 = now_ns();                      \
        printf("SYSCOST2 %-24s %9.1f ns/call\n", name, (t1 - t0) / (double)(n)); \
    } while (0)

static void arm_itimer(int usec_interval) {
    struct itimerval it;
    memset(&it, 0, sizeof it);
    it.it_value.tv_sec = 3600;              /* 一小时后才触发，测的是"已装配"这件事 */
    it.it_interval.tv_usec = usec_interval; /* 0 = 一次性 */
    if (setitimer(ITIMER_REAL, &it, NULL) != 0)
        printf("SYSCOST2 itimer_arm_failed errno=%d\n", errno);
}

static void disarm_itimer(void) {
    struct itimerval it;
    memset(&it, 0, sizeof it);
    setitimer(ITIMER_REAL, &it, NULL);
}

int main(int argc, char **argv) {
    long N = (argc > 1) ? atol(argv[1]) : 100000;
    struct timespec zero = {0, 0};
    struct utsname un;
    struct rusage ru;
    sigset_t ss;
    int devnull = open("/dev/null", O_WRONLY);
    char c = 'x';

    printf("SYSCOST2 N=%ld\n", N);

    /* ---- 1. 不同处理体的系统调用 ---- */
    BENCH("invalid_syscall", N, sink += syscall(0x7f0L));
    BENCH("getpid", N, sink += syscall(SYS_getpid));
    BENCH("getppid", N, sink += syscall(SYS_getppid));
    BENCH("getuid", N, sink += syscall(SYS_getuid));
    BENCH("sched_yield", N, sink += syscall(SYS_sched_yield));
    BENCH("clock_gettime", N, {
        struct timespec ts;
        sink += syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &ts);
    });
    BENCH("gettimeofday", N, {
        struct timeval tv;
        sink += syscall(SYS_gettimeofday, &tv, NULL);
    });
    BENCH("nanosleep0", N, sink += syscall(SYS_nanosleep, &zero, NULL));
    BENCH("getrusage", N, sink += syscall(SYS_getrusage, RUSAGE_SELF, &ru));
    BENCH("sigprocmask", N, sink += syscall(SYS_rt_sigprocmask, SIG_BLOCK, NULL, &ss, 8));
    BENCH("uname", N, sink += syscall(SYS_uname, &un));
    if (devnull >= 0) {
        BENCH("write_devnull_1B", N, sink += syscall(SYS_write, devnull, &c, 1));
    }
    BENCH("getitimer", N, {
        struct itimerval it;
        sink += syscall(SYS_getitimer, ITIMER_REAL, &it);
    });
    BENCH("setitimer0", N, {
        struct itimerval it;
        memset(&it, 0, sizeof it);
        sink += syscall(SYS_setitimer, ITIMER_REAL, &it, NULL);
    });
    BENCH("mmap_munmap", N / 8 + 1, {
        void *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p != MAP_FAILED) {
            sink += (long)(size_t)p;
            syscall(SYS_munmap, p, 4096);
        }
    });

    /* ---- 2. 同一调用在有/无定时器下的对比（报告 §05 的核心假设）---- */
    disarm_itimer();
    BENCH("getpid_no_timer", N, sink += syscall(SYS_getpid));
    arm_itimer(0);
    BENCH("getpid_timer_armed", N, sink += syscall(SYS_getpid));
    BENCH("clock_gettime_timer_armed", N, {
        struct timespec ts;
        sink += syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &ts);
    });
    disarm_itimer();
    BENCH("getpid_after_disarm", N, sink += syscall(SYS_getpid));

    printf("SYSCOST2 sink=%ld\n", sink);
    return 0;
}
