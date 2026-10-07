/* mmcoherence.c — munmap 之后同址重映射是否还能读到"上一轮的物理页"。
 *
 * 背景：把 unmap 路径里"每页一次 `sfence.vma`"去掉之后（外层事务已对整段登记
 * 一次 TLB 失效），最危险的失败模式是**旧翻译还在 TLB 里**：同一进程、同一 VA
 * 重新 mmap 到新的物理页，CPU 却仍用旧表项去访问 → 读到上一轮的内容。
 *
 * 判据（Linux 语义：新映射的匿名页必须是零页）：
 *   每轮固定地址 mmap 一段 → 用 0x11+i 填满 → munmap → 立刻在同一地址再 mmap
 *   → 逐字节检查是不是 0；不是 0 就说明读到了旧物理页。
 *
 * 输出：MMCOH ITERS=<n> SIZE=<sz> mismatch_pages=<n> first_bad=<...> verdict=PASS|FAIL
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define PAGE 4096
#define FIXED_ADDR ((void *)0x30000000UL) /* 固定地址，确保复用同一 VA */

int main(int argc, char **argv) {
    int iters = (argc > 1) ? atoi(argv[1]) : 200;
    size_t pages = (argc > 2) ? (size_t)atoi(argv[2]) : 64;
    size_t size = pages * PAGE;
    long long mismatch_pages = 0;
    unsigned long first_bad_addr = 0;
    unsigned char first_bad_value = 0;

    for (int i = 0; i < iters; i++) {
        unsigned char fill = (unsigned char)(0x11 + (i % 0x60));
        void *p = mmap(FIXED_ADDR, size, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        if (p == MAP_FAILED) {
            printf("MMCOH map1_failed errno=%d\n", errno);
            return 1;
        }
        memset(p, fill, size);
        if (munmap(p, size) != 0) {
            printf("MMCOH munmap_failed errno=%d\n", errno);
            return 1;
        }

        void *q = mmap(FIXED_ADDR, size, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        if (q == MAP_FAILED) {
            printf("MMCOH map2_failed errno=%d\n", errno);
            return 1;
        }
        const unsigned char *r = (const unsigned char *)q;
        for (size_t off = 0; off < size; off += PAGE) {
            if (r[off] != 0 || r[off + PAGE - 1] != 0) {
                mismatch_pages++;
                if (first_bad_addr == 0) {
                    first_bad_addr = (unsigned long)q + off;
                    first_bad_value = r[off];
                }
            }
        }
        if (munmap(q, size) != 0) {
            printf("MMCOH munmap2_failed errno=%d\n", errno);
            return 1;
        }
    }

    printf("MMCOH iters=%d pages=%zu mismatch_pages=%lld first_bad=0x%lx val=0x%02x verdict=%s\n",
           iters, pages, mismatch_pages, first_bad_addr, first_bad_value,
           mismatch_pages == 0 ? "PASS" : "FAIL");
    return mismatch_pages == 0 ? 0 : 2;
}
