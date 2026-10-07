/* sysattr.c — 只看"一种系统调用"的入口/出口分段。
 *
 * `syscost2` 给出的是"一轮混合 workload 的均值"，会被 sched_yield/getrusage/
 * mmap 这类重调用拉高。这里只跑一种调用，并在同进程内读 `/proc/fault_attrib`
 * 的前后差值，拿到这一种调用的干净分解（阻塞型系统调用的样本由内核侧的
 * 100 µs 上限丢弃，见 mm/fault_attrib.rs 的 ScopeCapped）。
 *
 * 输出：SYSATTR <name> call=<ns/call> iter=<ns> uctx_enter=<ns> ptrace_pre=<ns>
 *       handle=<ns> post=<ns>
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static volatile long sink;

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static long long attr(const char *key) {
    FILE *f = fopen("/proc/fault_attrib", "r");
    if (!f) return -1;
    char line[256];
    long long value = -1;
    size_t klen = strlen(key);
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            value = atoll(line + klen + 1);
            break;
        }
    }
    fclose(f);
    return value;
}

struct snap {
    long long iters, iter, enter, pre, handle, post;
};

static struct snap take(void) {
    struct snap s;
    s.iters = attr("trap_iters");
    s.iter = attr("sys_iter_ns");
    s.enter = attr("sys_uctx_enter_ns");
    s.pre = attr("sys_ptrace_pre_ns");
    s.handle = attr("sys_handle_ns");
    s.post = attr("sys_post_ns");
    return s;
}

static void report(const char *name, int n, struct snap a, struct snap b) {
    long long iters = b.iters - a.iters;
    if (iters <= 0) iters = 1;
    printf("SYSATTR %-14s n=%d iters=%lld iter=%lld enter=%lld pre=%lld handle=%lld post=%lld (ns/iter)\n",
           name, n, iters, (b.iter - a.iter) / iters, (b.enter - a.enter) / iters,
           (b.pre - a.pre) / iters, (b.handle - a.handle) / iters,
           (b.post - a.post) / iters);
}

int main(int argc, char **argv) {
    int n = (argc > 1) ? atoi(argv[1]) : 100000;
    struct snap a, b;
    double t0, t1;

    a = take();
    t0 = now_ns();
    for (int i = 0; i < n; i++) sink += getpid();
    t1 = now_ns();
    b = take();
    printf("SYSATTR getpid          call=%.1f ns\n", (t1 - t0) / n);
    report("getpid", n, a, b);

    a = take();
    t0 = now_ns();
    for (int i = 0; i < n; i++) sink += syscall(-1);
    t1 = now_ns();
    b = take();
    printf("SYSATTR invalid         call=%.1f ns\n", (t1 - t0) / n);
    report("invalid", n, a, b);

    a = take();
    t0 = now_ns();
    for (int i = 0; i < n; i++) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        sink += ts.tv_nsec & 1;
    }
    t1 = now_ns();
    b = take();
    printf("SYSATTR clock_gettime   call=%.1f ns\n", (t1 - t0) / n);
    report("clock_gettime", n, a, b);

    printf("SYSATTR sink=%ld\n", sink);
    return 0;
}
