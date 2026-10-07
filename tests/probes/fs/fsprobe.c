/* fsprobe.c — characterize the host filesystem write path.
 *
 * Motivation: on the AKA-00 board's root ext4 (mmcblk0p2) writes stop making
 * progress at ~2 MiB (dd bs=1M count=6 leaves 3 MiB; scp of an 11.6 MB FIT
 * stops at 2,113,536 bytes with EBUSY). That blocks "flash the kernel over the
 * network". This probe measures the boundary and the surrounding behaviour
 * instead of guessing:
 *
 *   * append one 64 KiB block at a time; print the first offset where the write
 *     short-writes or fails, plus errno;
 *   * do the same with O_APPEND single-byte writes at the boundary;
 *   * measure fsync() cost for a 1 MiB file;
 *   * read back and verify the bytes that did land.
 *
 * Usage: fsprobe [path=/root/fsprobe.bin] [max_MiB=8]
 * Build: riscv64-unknown-linux-musl-gcc -O2 -static -march=rv64gc -mabi=lp64d
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    const char *path = (argc > 1) ? argv[1] : "/root/fsprobe.bin";
    long max_mib = (argc > 2) ? atol(argv[2]) : 8;
    const size_t BLK = 64 * 1024;
    char *buf = malloc(BLK);
    if (!buf) return 1;
    memset(buf, 0xA5, BLK);

    unlink(path);
    int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) {
        printf("FSPROBE open_failed errno=%d (%s)\n", errno, strerror(errno));
        return 1;
    }
    printf("FSPROBE begin path=%s blk=%zu max=%ldMiB\n", path, BLK, max_mib);

    size_t want = 0, got = 0;
    for (long i = 0; i < max_mib * 1024 * 1024 / (long)BLK; i++) {
        want += BLK;
        ssize_t n = write(fd, buf, BLK);
        if (n != (ssize_t)BLK) {
            printf("FSPROBE short_write at offset=%zu wrote=%zd errno=%d (%s)\n",
                   want - BLK, n, errno, strerror(errno));
            break;
        }
        got += BLK;
    }
    if (got == want)
        printf("FSPROBE block_writes_ok up_to=%zu bytes (%.2f MiB)\n", got,
               (double)got / (1024 * 1024));

    double t0 = now_s();
    int fsync_rc = fsync(fd);
    double fsync_s = now_s() - t0;
    printf("FSPROBE fsync rc=%d cost=%.3f s after=%zu bytes\n", fsync_rc, fsync_s, got);

    /* 边界处单字节追加：看是不是"整数块写"特有的问题 */
    if (lseek(fd, 0, SEEK_END) >= 0) {
        for (int k = 0; k < 8; k++) {
            ssize_t n = write(fd, "Z", 1);
            if (n != 1) {
                printf("FSPROBE byte_append_failed k=%d errno=%d (%s)\n", k, errno,
                       strerror(errno));
                break;
            }
            if (k == 7) printf("FSPROBE byte_append_ok 8 bytes past the boundary\n");
        }
    }
    close(fd);

    /* 落地后回读校验 */
    fd = open(path, O_RDONLY);
    if (fd >= 0) {
        off_t sz = lseek(fd, 0, SEEK_END);
        lseek(fd, 0, SEEK_SET);
        size_t rd = 0;
        int bad = 0;
        ssize_t n;
        /* 只校验"按块写成功"的那部分：边界之后追加的 'Z' 是按设计写进去的 */
        while (rd < got && (n = read(fd, buf, BLK)) > 0) {
            for (ssize_t i = 0; i < n; i++) {
                if ((unsigned char)buf[i] != 0xA5) { bad++; break; }
            }
            rd += (size_t)n;
        }
        printf("FSPROBE readback size=%lld read=%zu mismatch_blocks=%d\n",
               (long long)sz, rd, bad);
        close(fd);
    }
    printf("FSPROBE end\n");
    free(buf);
    return 0;
}
