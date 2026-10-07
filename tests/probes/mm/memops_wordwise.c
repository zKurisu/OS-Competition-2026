/* memops_wordwise.c — host fuzz for the word-at-a-time mem* implementations
 * that replace the byte loops in axstd's libc_compat and the kernel's memset.
 *
 * The same algorithm is written here in C, checked against libc over random
 * sizes, offsets, alignments and overlaps, then ported verbatim to Rust.
 *
 * Build/run: cc -O2 -o /tmp/memops_wordwise memops_wordwise.c && /tmp/memops_wordwise
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static void *ww_memset(void *dst, int value, size_t n) {
    unsigned char *d = dst;
    unsigned char byte = (unsigned char)value;
    size_t i = 0;
    while (i < n && ((uintptr_t)(d + i) & 7) != 0) {
        d[i] = byte;
        i++;
    }
    uint64_t word;
    memcpy(&word, (unsigned char[8]){byte, byte, byte, byte, byte, byte, byte, byte}, 8);
    while (i + 8 <= n) {
        memcpy(d + i, &word, 8);
        i += 8;
    }
    while (i < n) {
        d[i] = byte;
        i++;
    }
    return dst;
}

static void *ww_memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    size_t i = 0;
    if (((uintptr_t)d & 7) == ((uintptr_t)s & 7)) {
        while (i < n && ((uintptr_t)(d + i) & 7) != 0) {
            d[i] = s[i];
            i++;
        }
        while (i + 8 <= n) {
            uint64_t word;
            memcpy(&word, s + i, 8);
            memcpy(d + i, &word, 8);
            i += 8;
        }
    }
    while (i < n) {
        d[i] = s[i];
        i++;
    }
    return dst;
}

static void *ww_memmove(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    if ((uintptr_t)d <= (uintptr_t)s) {
        return ww_memcpy(dst, src, n);
    }
    size_t i = n;
    if (((uintptr_t)d & 7) == ((uintptr_t)s & 7)) {
        while (i > 0 && ((uintptr_t)(d + i - 1) & 7) != 0) {
            i--;
            d[i] = s[i];
        }
        while (i >= 8) {
            i -= 8;
            uint64_t word;
            memcpy(&word, s + i, 8);
            memcpy(d + i, &word, 8);
        }
    }
    while (i > 0) {
        i--;
        d[i] = s[i];
    }
    return dst;
}

static int ww_memcmp(const void *lhs, const void *rhs, size_t n) {
    const unsigned char *l = lhs;
    const unsigned char *r = rhs;
    if (((uintptr_t)l & 7) == ((uintptr_t)r & 7)) {
        size_t i = 0;
        while (i + 8 <= n) {
            uint64_t a, b;
            memcpy(&a, l + i, 8);
            memcpy(&b, r + i, 8);
            if (a != b) {
                break;
            }
            i += 8;
        }
        for (; i < n; i++) {
            if (l[i] != r[i]) {
                return (int)l[i] - (int)r[i];
            }
        }
        return 0;
    }
    for (size_t i = 0; i < n; i++) {
        if (l[i] != r[i]) {
            return (int)l[i] - (int)r[i];
        }
    }
    return 0;
}

static unsigned long rng_state = 0x12345678;
static unsigned rng(void) {
    rng_state = rng_state * 6364136223846793005UL + 1442695040888963407UL;
    return (unsigned)(rng_state >> 33);
}

int main(void) {
    enum { POOL = 4096 };
    static unsigned char base[POOL + 64];
    static unsigned char ref[POOL + 64];
    static unsigned char got[POOL + 64];
    long checks = 0;

    for (int iter = 0; iter < 200000; iter++) {
        size_t n = rng() % 600;
        size_t off = rng() % 32;
        int value = (int)(rng() & 0xff);

        for (size_t i = 0; i < sizeof(base); i++) {
            base[i] = (unsigned char)rng();
        }

        /* memset */
        memcpy(got, base, sizeof(base));
        memcpy(ref, base, sizeof(base));
        ww_memset(got + off, value, n);
        memset(ref + off, value, n);
        if (memcmp(got, ref, sizeof(base)) != 0) {
            printf("MISMATCH memset n=%zu off=%zu value=%d\n", n, off, value);
            return 1;
        }
        checks++;

        /* memcpy */
        size_t src_off = rng() % 32;
        memcpy(got, base, sizeof(base));
        memcpy(ref, base, sizeof(base));
        ww_memcpy(got + off, base + src_off, n);
        memcpy(ref + off, base + src_off, n);
        if (memcmp(got, ref, sizeof(base)) != 0) {
            printf("MISMATCH memcpy n=%zu d=%zu s=%zu\n", n, off, src_off);
            return 1;
        }
        checks++;

        /* memmove, both directions and overlapping */
        size_t dst_off = rng() % 64;
        size_t move_src = rng() % 64;
        memcpy(got, base, sizeof(base));
        memcpy(ref, base, sizeof(base));
        ww_memmove(got + dst_off, got + move_src, n);
        memmove(ref + dst_off, ref + move_src, n);
        if (memcmp(got, ref, sizeof(base)) != 0) {
            printf("MISMATCH memmove n=%zu d=%zu s=%zu\n", n, dst_off, move_src);
            return 1;
        }
        checks++;

        /* memcmp */
        size_t cmp_off = rng() % 32;
        int expected = memcmp(base, base + cmp_off, n);
        int actual = ww_memcmp(base, base + cmp_off, n);
        if ((expected == 0) != (actual == 0) ||
            (expected < 0) != (actual < 0) || (expected > 0) != (actual > 0)) {
            printf("MISMATCH memcmp n=%zu off=%zu exp=%d got=%d\n", n, cmp_off, expected, actual);
            return 1;
        }
        checks++;
    }
    printf("OK %ld checks passed\n", checks);
    return 0;
}
