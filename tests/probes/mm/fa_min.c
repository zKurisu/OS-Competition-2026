/* fa_min.c — minimal check: does reading /proc/fault_attrib work at all? */
#include <errno.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("fa_min: opening\n");
    FILE *f = fopen("/proc/fault_attrib", "r");
    printf("fa_min: fopen=%p errno=%d\n", (void *)f, errno);
    if (!f) {
        return 1;
    }
    static char buf[1024];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    printf("fa_min: fread=%zu errno=%d\n", n, errno);
    buf[n] = '\0';
    printf("fa_min: first_line=[%.*s]\n", 40, buf);
    fclose(f);
    printf("fa_min: parsing\n");
    struct attrib {
        long long plan, prepare, apply, tlb, mmucache, total, faults;
        long long frame_alloc, frame_zero, materialize, pending_insert, page_object;
        long long apply_prep, apply_map, apply_publish;
    } a;
    memset(&a, 0xff, sizeof(a));
    printf("fa_min: after memset size=%zu\n", sizeof(a));
    a.plan = 1;
    a.apply_publish = 2;
    printf("fa_min: fields plan=%lld publish=%lld\n", a.plan, a.apply_publish);
    printf("fa_min: done\n");
    return 0;
}
