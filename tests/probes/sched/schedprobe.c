/* schedprobe.c — scheduler-facing costs, re-implemented from scratch for SG2002.
 *
 * The report measures this layer with hackbench / schbench, but no riscv64
 * static builds of those exist here (and hackbench needs N cores to be
 * meaningful). On a single-core board the interesting quantities are the
 * per-operation costs and the *sleep wakeup quality*:
 *
 *   fork_exit        fork() + _exit() + waitpid()          (us/op)
 *   fork_exec_exit   fork() + execve(/bin/true) + waitpid() (us/op)
 *   ctx_switch       two processes ping-ponging 1 byte over a pipe (us/switch)
 *   yield_pair       sched_yield() back-to-back, two threads (us/switch)
 *   sleep1ms         nanosleep(1ms) x N: actual delay distribution (us)
 *   drift1ms         clock_nanosleep absolute deadlines: cumulative drift (us)
 *
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <pthread.h>

static double now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

static void sleep_us(long us) {
    struct timespec ts = {us / 1000000, (us % 1000000) * 1000};
    nanosleep(&ts, NULL);
}

static int cmp_double(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static void report_dist(const char *name, double *v, int n, const char *unit) {
    qsort(v, n, sizeof(double), cmp_double);
    printf("SCHEDPROBE %-14s min=%.1f p50=%.1f p90=%.1f p99=%.1f max=%.1f %s\n",
           name, v[0], v[n / 2], v[(int)(n * 0.9)], v[(int)(n * 0.99)], v[n - 1], unit);
}

/* ---- fork/exec ---- */
static void bench_fork_exit(int n) {
    double t0 = now_us();
    for (int i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0) _exit(0);
        if (pid < 0) { printf("SCHEDPROBE fork_failed errno=%d\n", errno); return; }
        waitpid(pid, NULL, 0);
    }
    printf("SCHEDPROBE fork_exit      %.1f us/op (n=%d)\n", (now_us() - t0) / n, n);
}

static void bench_fork_exec_exit(int n) {
    double t0 = now_us();
    for (int i = 0; i < n; i++) {
        pid_t pid = fork();
        if (pid == 0) {
            char *argv[] = {"/bin/true", NULL};
            execve("/bin/true", argv, NULL);
            _exit(127);
        }
        if (pid < 0) { printf("SCHEDPROBE fork_failed errno=%d\n", errno); return; }
        waitpid(pid, NULL, 0);
    }
    printf("SCHEDPROBE fork_exec_exit %.1f us/op (n=%d)\n", (now_us() - t0) / n, n);
}

/* ---- context switch via pipe ping-pong ---- */
static void bench_ctx_switch(int n) {
    int a2b[2], b2a[2];
    if (pipe(a2b) || pipe(b2a)) { printf("SCHEDPROBE pipe_failed\n"); return; }
    pid_t pid = fork();
    if (pid == 0) {
        char c;
        close(a2b[1]); close(b2a[0]);
        for (int i = 0; i < n; i++) {
            if (read(a2b[0], &c, 1) != 1) _exit(1);
            if (write(b2a[1], "x", 1) != 1) _exit(1);
        }
        _exit(0);
    }
    char c = 'x';
    close(a2b[0]); close(b2a[1]);
    double t0 = now_us();
    for (int i = 0; i < n; i++) {
        if (write(a2b[1], &c, 1) != 1) break;
        if (read(b2a[0], &c, 1) != 1) break;
    }
    double dt = now_us() - t0;
    waitpid(pid, NULL, 0);
    /* 一次往返 = 2 次上下文切换 */
    printf("SCHEDPROBE ctx_switch    %.2f us/switch (round_trips=%d)\n", dt / (2.0 * n), n);
}

/* ---- yield ping-pong between two threads ---- */
static volatile int g_turn, g_stop;
static void *yielder(void *arg) {
    (void)arg;
    while (!g_stop) {
        while (g_turn != 1 && !g_stop) sched_yield();
        g_turn = 0;
    }
    return NULL;
}

static void bench_yield_pair(int n) {
    pthread_t th;
    if (pthread_create(&th, NULL, yielder, NULL) != 0) {
        printf("SCHEDPROBE pthread_create_failed\n");
        return;
    }
    double t0 = now_us();
    for (int i = 0; i < n; i++) {
        g_turn = 1;
        while (g_turn != 0) sched_yield();
    }
    double dt = now_us() - t0;
    g_stop = 1;
    pthread_join(th, NULL);
    printf("SCHEDPROBE yield_pair    %.2f us/handoff (n=%d)\n", dt / n, n);
}

/* ---- sleep wakeup quality ---- */
static void bench_sleep_jitter(int n, long req_us) {
    double *v = malloc(sizeof(double) * n);
    if (!v) return;
    for (int i = 0; i < n; i++) {
        double t0 = now_us();
        sleep_us(req_us);
        v[i] = now_us() - t0;
    }
    char name[32];
    snprintf(name, sizeof name, "sleep%ldus", req_us / 1000);
    report_dist(name, v, n, "us(actual)");
    free(v);
}

/* 绝对时限的 clock_nanosleep：看累积漂移 */
static void bench_drift(int n, long period_us) {
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);
    double t0 = now_us();
    for (int i = 0; i < n; i++) {
        next.tv_nsec += period_us * 1000;
        while (next.tv_nsec >= 1000000000L) { next.tv_sec++; next.tv_nsec -= 1000000000L; }
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
    }
    double dt = now_us() - t0;
    printf("SCHEDPROBE drift%ldus    expected=%.1f actual=%.1f drift=%.1f us (n=%d)\n",
           period_us / 1000, (double)n * period_us, dt, dt - (double)n * period_us, n);
}

int main(int argc, char **argv) {
    int n = (argc > 1) ? atoi(argv[1]) : 200;
    printf("SCHEDPROBE begin n=%d\n", n);
    bench_fork_exit(n / 4 + 1);
    bench_fork_exec_exit(n / 4 + 1);
    bench_ctx_switch(n);
    bench_yield_pair(n * 10);
    bench_sleep_jitter(200, 1000);
    bench_sleep_jitter(200, 5000);
    bench_drift(200, 1000);
    printf("SCHEDPROBE end\n");
    return 0;
}
