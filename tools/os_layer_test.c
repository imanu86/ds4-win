// Runtime smoke of the ds4-win Win32 platform layer (POSIX->Win32 substitutions).
// Compiled+run with portable MinGW-UCRT (no MSVC, no CUDA). Exercises the paths
// the MSVC-compile-only CI never ran: 64-bit OffsetHigh pread, huge mmap, EOF,
// sparse gaps, and concurrent pread on a shared FILE_FLAG_OVERLAPPED handle.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "os_file.h"
#include "os_mmap.h"
#include "os_thread.h"
#include "os_random.h"
#include "os_clock.h"

static const uint64_t BLK = 1024ull * 1024ull;         // 1 MiB blocks
static const uint64_t OFFB = 0x120000000ull;           // 4.5 GiB -> exercises OffsetHigh

static uint8_t patByte(uint64_t i, uint8_t seed) {
    return (uint8_t)(((i * 2654435761u) >> 13) ^ seed);
}
static void fillpat(uint8_t *buf, uint64_t n, uint64_t base, uint8_t seed) {
    for (uint64_t i = 0; i < n; i++) buf[i] = patByte(base + i, seed);
}

static int pass = 0, fail = 0;
static void check(int cond, const char *msg) {
    if (cond) { printf("  PASS  %s\n", msg); pass++; }
    else      { printf("  FAIL  %s\n", msg); fail++; }
}

typedef struct { os_file_t *f; int iters; volatile long *errors; } worker_t;

static void *worker(void *arg) {
    worker_t *w = (worker_t *)arg;
    uint8_t *buf = (uint8_t *)malloc(BLK);
    uint8_t *exp = (uint8_t *)malloc(BLK);
    for (int it = 0; it < w->iters; it++) {
        int64_t n = os_pread(w->f, buf, BLK, 0);
        fillpat(exp, BLK, 0, 0xA5);
        if (n != (int64_t)BLK || memcmp(buf, exp, BLK) != 0) InterlockedIncrement(w->errors);
        n = os_pread(w->f, buf, BLK, OFFB);
        fillpat(exp, BLK, OFFB, 0x5A);
        if (n != (int64_t)BLK || memcmp(buf, exp, BLK) != 0) InterlockedIncrement(w->errors);
    }
    free(buf); free(exp);
    return NULL;
}

int main(void) {
    const char *path = "os_layer_test.bin";
    const uint64_t expected_size = OFFB + BLK;

    // Build a SPARSE test file: pattern A at 0, pattern B at 4.5 GiB, EOF just past B.
    HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) { printf("create fail %lu\n", GetLastError()); return 2; }
    DWORD br = 0; DeviceIoControl(h, FSCTL_SET_SPARSE, NULL, 0, NULL, 0, &br, NULL);
    uint8_t *blk = (uint8_t *)malloc(BLK);
    DWORD wr = 0; LARGE_INTEGER pos;
    fillpat(blk, BLK, 0, 0xA5);    pos.QuadPart = 0;               SetFilePointerEx(h, pos, NULL, FILE_BEGIN); WriteFile(h, blk, (DWORD)BLK, &wr, NULL);
    fillpat(blk, BLK, OFFB, 0x5A); pos.QuadPart = (LONGLONG)OFFB;  SetFilePointerEx(h, pos, NULL, FILE_BEGIN); WriteFile(h, blk, (DWORD)BLK, &wr, NULL);
    pos.QuadPart = (LONGLONG)expected_size; SetFilePointerEx(h, pos, NULL, FILE_BEGIN); SetEndOfFile(h);
    CloseHandle(h); free(blk);

    printf("== ds4-win platform-layer runtime smoke (MinGW-UCRT g++/gcc) ==\n");
    printf("test file: 4.5 GiB sparse, pattern A@0, pattern B@0x%llx\n", (unsigned long long)OFFB);

    os_file_t f; os_file_init(&f);
    check(os_file_open_read(&f, path) == 0 && os_file_valid(&f), "os_file_open_read");
    check(os_file_size(&f) == expected_size, "os_file_size == 4.5GiB+1MiB (64-bit)");

    uint8_t *buf = (uint8_t *)malloc(BLK), *exp = (uint8_t *)malloc(BLK);
    int64_t n;

    n = os_pread(&f, buf, BLK, 0);          fillpat(exp, BLK, 0, 0xA5);
    check(n == (int64_t)BLK && memcmp(buf, exp, BLK) == 0, "os_pread @0 (pattern A)");

    n = os_pread(&f, buf, BLK, OFFB);       fillpat(exp, BLK, OFFB, 0x5A);
    check(n == (int64_t)BLK && memcmp(buf, exp, BLK) == 0, "os_pread @4.5GiB (OffsetHigh, pattern B)");

    n = os_pread(&f, buf, 4096, 0x80000000ull);
    { int z = 1; for (int i = 0; i < 4096; i++) if (buf[i]) z = 0;
      check(n == 4096 && z, "os_pread @2GiB sparse gap -> zeros"); }

    n = os_pread(&f, buf, BLK, expected_size - 4096);
    check(n == 4096, "os_pread EOF overshoot -> short read == remaining");

    os_mmap_t m; os_mmap_init(&m);
    check(os_mmap_open_read(path, 0, &m) == 0 && m.addr && m.size == expected_size, "os_mmap_open_read (4.5GiB view)");
    fillpat(exp, BLK, OFFB, 0x5A);
    check(m.addr != NULL && memcmp(m.addr + OFFB, exp, BLK) == 0, "mmap high-offset read (pattern B @4.5GiB)");
    os_mmap_warm(&m); os_mmap_cold(&m, 0, BLK);
    os_mmap_close(&m);

    volatile long errors = 0;
    worker_t w = { &f, 200, &errors };
    os_thread_t th[8];
    for (int i = 0; i < 8; i++) os_thread_create(&th[i], worker, &w);
    for (int i = 0; i < 8; i++) os_thread_join(th[i]);
    check(errors == 0, "concurrent os_pread, shared OVERLAPPED handle (8 thr x 200 x 2 reads)");

    uint8_t rnd[32]; memset(rnd, 0, sizeof(rnd));
    { int rr = os_random_bytes(rnd, 32), nz = 0; for (int i = 0; i < 32; i++) if (rnd[i]) nz = 1;
      check(rr == 0 && nz, "os_random_bytes (BCrypt)"); }

    double t0 = os_monotonic_sec(); Sleep(5); double t1 = os_monotonic_sec();
    check(t1 > t0, "os_monotonic_sec advances");
    check(os_cpu_count() >= 1, "os_cpu_count");

    os_file_close(&f); free(buf); free(exp);
    DeleteFileA(path);
    printf("\nRESULT: %d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
