/* forkcost.c — 把 fork 的成本拆成"父侧 fork() 返回耗时"与"等子进程退出耗时"。
 *
 * 关键问题：`AddrSpace::try_clone` 之外的 3 ms（尤其 `staged_task.activate()` 的
 * 2 ms）到底是"调度器入队本身慢"，还是"activate 里同步切到子进程、把子进程的
 * 运行/退出时间算了进来"。判据：让子进程在 fork 返回后先忙等 T 毫秒再退出，
 * 如果父侧 fork() 的耗时随 T 线性增长，就是同步切换（否则只是入队开销）。
 *
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

static void spin_us(double us) {
    double t0 = now_us();
    while (now_us() - t0 < us) {
    }
}

/* 读 /proc/fault_attrib 里的 task_switches / task_guard_drop_ns，用于把
 * "每次 fork 到底切了几个上下文" 分摊到各个子场景。 */
static long long read_attr(const char *key) {
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

static void report_attr_delta(const char *name, int iters,
                              long long sw0, long long sw1,
                              long long gd0, long long gd1) {
    if (sw0 < 0 || sw1 < 0 || gd0 < 0 || gd1 < 0) return;
    printf("FORKCOST %-14s iters=%3d switches=%lld (%.2f/iter) guard_drop=%lld (%.0f us/iter)\n",
           name, iters, sw1 - sw0, (double)(sw1 - sw0) / iters,
           gd1 - gd0, (double)(gd1 - gd0) / iters / 1000.0);
}

/* 子进程在退出前先忙等 child_us；父侧只统计 fork() 返回用了多久。 */
static void bench(const char *name, int n, double child_us) {
    double fsum = 0, wsum = 0;
    long long sw0 = read_attr("task_switches");
    long long gd0 = read_attr("task_guard_drop_ns");
    for (int i = 0; i < n; i++) {
        double t0 = now_us();
        pid_t pid = fork();
        if (pid == 0) {
            if (child_us > 0) spin_us(child_us);
            _exit(0);
        }
        if (pid < 0) {
            printf("FORKCOST %s fork_failed errno=%d\n", name, errno);
            return;
        }
        double t1 = now_us();
        waitpid(pid, NULL, 0);
        double t2 = now_us();
        fsum += t1 - t0;
        wsum += t2 - t1;
    }
    printf("FORKCOST %-14s n=%3d fork=%9.1f wait=%9.1f total=%9.1f us/op\n",
           name, n, fsum / n, wsum / n, (fsum + wsum) / n);
    report_attr_delta(name, n, sw0, read_attr("task_switches"), gd0,
                      read_attr("task_guard_drop_ns"));
}

/* 只测 fork：子进程睡 400 ms，父进程连开 n 个再统一回收。
 * 这样父侧 fork() 里不应包含任何子进程的运行时间。 */
static void bench_fork_only(int n) {
    pid_t *pids = calloc(n, sizeof(pid_t));
    long long sw0 = read_attr("task_switches");
    long long gd0 = read_attr("task_guard_drop_ns");
    double t0 = now_us();
    for (int i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            struct timespec ts = {0, 400 * 1000 * 1000};
            nanosleep(&ts, NULL);
            _exit(0);
        }
        if (pid < 0) {
            printf("FORKCOST fork_only fork_failed errno=%d\n", errno);
            return;
        }
        pids[i] = pid;
    }
    double t1 = now_us();
    for (int i = 0; i < n; i++) waitpid(pids[i], NULL, 0);
    double t2 = now_us();
    printf("FORKCOST %-14s n=%3d fork=%9.1f wait=%9.1f us/op\n",
           "fork-only", n, (t1 - t0) / n, (t2 - t1) / n);
    report_attr_delta("fork-only", n, sw0, read_attr("task_switches"), gd0,
                      read_attr("task_guard_drop_ns"));
    free(pids);
}

/* 子进程自己测 fork 返回后到 _exit 之间的时间，用来估 do_exit 相对大小。 */
static void bench_exit_only(int n) {
    double sum = 0;
    for (int i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            double t0 = now_us();
            _exit(0);
            (void)t0;
        }
        if (pid < 0) return;
        waitpid(pid, NULL, 0);
        sum += 0;
    }
    printf("FORKCOST %-14s n=%3d (no-op)\n", "exit-only", n);
}

int main(int argc, char **argv) {
    int n = (argc > 1) ? atoi(argv[1]) : 100;
    printf("FORKCOST begin n=%d\n", n);
    bench("child-fast", n, 0);
    bench("child-yield", n, 0); /* 同上，仅名字区分 */
    bench("child-spin1ms", n / 2, 1000);
    bench("child-spin10ms", n / 4, 10000);
    bench_fork_only(50);
    bench_exit_only(1);
    printf("FORKCOST end\n");
    return 0;
}
