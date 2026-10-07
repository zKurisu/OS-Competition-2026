/* readprobe2.c — 把"fresh 缓冲"那条路拆成 mmap / read / munmap 三段。
 *
 * rp1 的 fresh_buf 每轮做 mmap(803 KB) + read() + munmap()，实测 80.7 µs/页
 * （Linux 同探针 15.1 µs/页）。但把 uaccess 的"逐页缺页事务"改成整段
 * `populate_area` 之后它**一点没变** ⇒ 瓶颈不在这条路上。这里把三段分开计时，
 * 直接看钱花在 mmap、首次触碰（read 内部）、还是 munmap 回收上。
 *
 * 输出：READPROBE2 <name> iters=<n> us/iter=<...> us/page=<...>
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define FILE_PATH "/bin/busybox"
#define PAGE 4096

static double now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

static size_t file_size(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    off_t end = lseek(fd, 0, SEEK_END);
    close(fd);
    return (size_t)end;
}

static void report(const char *name, int iters, size_t size, double total_us) {
    double pages = (double)size / PAGE;
    printf("READPROBE2 %-12s iters=%d us/iter=%8.1f us/page=%6.2f\n", name, iters,
           total_us / iters, total_us / iters / pages);
}

/* 三段分开：mmap 建 VMA / read 首次触碰+拷贝 / munmap 回收。 */
static void split_phases(size_t size, int iters) {
    int fd = open(FILE_PATH, O_RDONLY);
    if (fd < 0) { printf("READPROBE2 open_failed\n"); return; }
    char **bufs = calloc(iters, sizeof(char *));
    double t_mmap = 0, t_read = 0, t_unmap = 0;

    for (int i = 0; i < iters; i++) {
        double a = now_us();
        char *buf = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        double b = now_us();
        if (buf == MAP_FAILED) { printf("READPROBE2 mmap_failed\n"); break; }
        lseek(fd, 0, SEEK_SET);
        ssize_t n = read(fd, buf, size);
        double c = now_us();
        if (n < 0) { printf("READPROBE2 read_failed\n"); break; }
        bufs[i] = buf;
        t_mmap += b - a;
        t_read += c - b;
    }
    /* 单独量 munmap：先把所有缓冲都建好并读完，再逐个释放。 */
    double u0 = now_us();
    for (int i = 0; i < iters; i++) {
        if (bufs[i]) munmap(bufs[i], size);
    }
    double u1 = now_us();
    t_unmap = u1 - u0;
    report("mmap", iters, size, t_mmap);
    report("read(触碰+拷贝)", iters, size, t_read);
    report("munmap", iters, size, t_unmap);
    report("total", iters, size, t_mmap + t_read + t_unmap);
    free(bufs);
    close(fd);
}

int main(int argc, char **argv) {
    int iters = (argc > 1) ? atoi(argv[1]) : 20;
    size_t size = file_size(FILE_PATH);
    if (size == 0) { printf("READPROBE2 no_file\n"); return 1; }
    printf("READPROBE2 file=%s size=%zu iters=%d\n", FILE_PATH, size, iters);
    split_phases(size, iters);
    return 0;
}
