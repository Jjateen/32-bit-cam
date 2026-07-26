// Sample input for the pass. The functions differ in how much they touch memory
// so the per-function counts are visibly different: no_mem stays in registers,
// stores_only writes, loads_only reads, and mixed does both.
#include <stdint.h>

int no_mem(int a, int b) {
    return a * b + 1;
}

void stores_only(int *p) {
    p[0] = 1;
    p[1] = 2;
    p[2] = 3;
}

int loads_only(const int *p) {
    return p[0] + p[1] + p[2] + p[3];
}

int mixed(int *dst, const int *src, int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        dst[i] = src[i];
        sum += src[i];
    }
    return sum;
}

int main(void) {
    int buf[4] = {0};
    stores_only(buf);
    return mixed(buf, buf, 4) + loads_only(buf) + no_mem(2, 3);
}
