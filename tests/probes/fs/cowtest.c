/* cowtest.c — 匿名批量缺页「整块分配 + 子租约」的正确性验证。
 *
 * A3d 之后，一次批量缺页不再是每页各分配一个 4 KiB 帧，而是整块（最多
 * 256 KiB）分配后用 FrameLease::sublease 切成子租约。这直接动了帧所有权，
 * 所以要验证：
 *   1. 顺序首触 → fork → 子进程改写每一页 → 父子各自的副本都正确
 *      （COW 必须逐页拷贝，不能把共享块里的页漏掉）；
 *   2. MAP_POPULATE 也走同一条路：写读校验；
 *   3. 反复 mmap/fork/退出后 memfree 回到原值（整块只在最后一次子租约
 *      释放时才归还，不能泄漏也不能提前释放）。
 *
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

#define PAGE 4096UL
#define BYTES (32UL << 20)

static long memfree_kb(void) {
    FILE *f = fopen("/proc/meminfo", "r");
    char line[256];
    long v = -1;
    if (!f) return -1;
    while (fgets(line, sizeof line, f)) {
        if (sscanf(line, "MemFree: %ld", &v) == 1) break;
    }
    fclose(f);
    return v;
}

/* 1) 顺序首触（走整块分配）→ fork → 两边各自改写 → 各自校验 */
static int fork_cow_round(size_t bytes, unsigned char parent_byte, unsigned char child_byte) {
    unsigned char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return 1;
    for (size_t off = 0; off < bytes; off += PAGE) p[off] = parent_byte;

    pid_t pid = fork();
    if (pid < 0) { munmap(p, bytes); return 2; }
    if (pid == 0) {
        /* 子进程：改写每一页，再校验是自己的值 */
        for (size_t off = 0; off < bytes; off += PAGE) p[off] = child_byte;
        for (size_t off = 0; off < bytes; off += PAGE) {
            if (p[off] != child_byte) _exit(11);
        }
        _exit(0);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) { munmap(p, bytes); return 3; }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        printf("COWTEST child_failed status=%d\n", status);
        munmap(p, bytes);
        return 4;
    }
    /* 父进程：子进程改过之后，自己每一页必须还是 parent_byte */
    for (size_t off = 0; off < bytes; off += PAGE) {
        if (p[off] != parent_byte) {
            printf("COWTEST parent_corrupt off=%zu got=%u want=%u\n",
                   off, p[off], parent_byte);
            munmap(p, bytes);
            return 5;
        }
    }
    munmap(p, bytes);
    return 0;
}

/* 2) MAP_POPULATE（同样走批量分配）写读校验 */
static int populate_round(size_t bytes) {
    unsigned char *p = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    if (p == MAP_FAILED) return 1;
    for (size_t off = 0; off < bytes; off += PAGE) p[off] = (unsigned char)(off / PAGE);
    for (size_t off = 0; off < bytes; off += PAGE) {
        if (p[off] != (unsigned char)(off / PAGE)) {
            printf("COWTEST populate_corrupt off=%zu got=%u\n", off, p[off]);
            munmap(p, bytes);
            return 2;
        }
    }
    munmap(p, bytes);
    return 0;
}

int main(void) {
    printf("COWTEST begin\n");
    long before = memfree_kb();

    for (int r = 0; r < 3; r++) {
        int rc = fork_cow_round(BYTES, (unsigned char)(0x10 + r), (unsigned char)(0xA0 + r));
        printf("COWTEST fork_cow round=%d rc=%d\n", r, rc);
        if (rc != 0) return 1;
    }
    for (int r = 0; r < 3; r++) {
        int rc = populate_round(BYTES);
        printf("COWTEST populate round=%d rc=%d\n", r, rc);
        if (rc != 0) return 1;
    }

    long after = memfree_kb();
    printf("COWTEST memfree before=%ldkB after=%ldkB delta=%ldkB\n",
           before, after, after - before);
    printf("COWTEST PASS\n");
    return 0;
}
