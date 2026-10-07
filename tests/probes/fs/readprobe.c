/* readprobe.c — 把"缓存命中的大读"拆成两种用户缓冲场景（H2 归因）。
 *
 * 读路径里每 4 KiB 页要做：取页（锁+LRU）→ 拷进 scratch → 再拷到用户缓冲。
 * 用户那一侧的拷贝走 uaccess（prepare：地址空间锁 + 页表走查；然后异常表拷贝）。
 * 于是有两种完全不同的成本来源：
 *   A) 用户缓冲**早就映射好**（同一块 buffer 反复读）→ 付的是 prepare + 拷贝；
 *   B) 每次换一块**没碰过的**缓冲（mmap 后不预触碰）→ 还要在拷贝过程中逐页缺页。
 * 把两者分开量，才能判断优化该落在 prepare 还是缺页/预映射。
 *
 * 输出：READPROBE <name> iters=<n> bytes=<n> us/iter=<...> MB/s=<...> us/page=<...>
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

/* 同一块已触碰过的缓冲反复读：隔离出 prepare + 拷贝的成本。 */
static void warm_buffer(size_t size, int iters) {
    int fd = open(FILE_PATH, O_RDONLY);
    if (fd < 0) { printf("READPROBE open_failed\n"); return; }
    char *buf = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (buf == MAP_FAILED) { printf("READPROBE mmap_failed\n"); close(fd); return; }
    for (size_t off = 0; off < size; off += PAGE) buf[off] = (char)off; /* 预触碰 */
    /* 预热一次，把文件页也放进页缓存 */
    lseek(fd, 0, SEEK_SET);
    if (read(fd, buf, size) < 0) { printf("READPROBE warm_read_failed\n"); }

    double t0 = now_us();
    for (int i = 0; i < iters; i++) {
        lseek(fd, 0, SEEK_SET);
        ssize_t n = read(fd, buf, size);
        if (n < 0) { printf("READPROBE read_failed\n"); break; }
    }
    double dt = now_us() - t0;
    printf("READPROBE warm_buf     iters=%d bytes=%zu us/iter=%.1f MB/s=%.1f us/page=%.2f\n",
           iters, size, dt / iters, (double)size * iters / dt, dt / iters / (size / PAGE));
    munmap(buf, size);
    close(fd);
}

/* 每轮换一块没触碰过的缓冲：把"拷贝途中逐页缺页"的成本也算进来。 */
static void cold_buffer(size_t size, int iters) {
    int fd = open(FILE_PATH, O_RDONLY);
    if (fd < 0) { printf("READPROBE open_failed\n"); return; }
    double t0 = now_us();
    for (int i = 0; i < iters; i++) {
        char *buf = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (buf == MAP_FAILED) { printf("READPROBE mmap_failed\n"); break; }
        lseek(fd, 0, SEEK_SET);
        ssize_t n = read(fd, buf, size);
        if (n < 0) { printf("READPROBE read_failed\n"); break; }
        munmap(buf, size);
    }
    double dt = now_us() - t0;
    printf("READPROBE fresh_buf    iters=%d bytes=%zu us/iter=%.1f MB/s=%.1f us/page=%.2f\n",
           iters, size, dt / iters, (double)size * iters / dt, dt / iters / (size / PAGE));
    close(fd);
}

int main(int argc, char **argv) {
    int iters = (argc > 1) ? atoi(argv[1]) : 30;
    size_t size = file_size(FILE_PATH);
    if (size == 0) { printf("READPROBE no_file\n"); return 1; }
    printf("READPROBE file=%s size=%zu iters=%d\n", FILE_PATH, size, iters);
    warm_buffer(size, iters);
    cold_buffer(size, iters);
    return 0;
}
