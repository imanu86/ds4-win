#ifndef DS4_OS_FILE_H
#define DS4_OS_FILE_H

#include <stdint.h>
#include <stdio.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <unistd.h>
#endif

typedef struct {
#ifdef _WIN32
    HANDLE h;
#else
    int fd;
#endif
} os_file_t;

typedef struct {
#ifdef _WIN32
    HANDLE file;
    OVERLAPPED overlapped;
    volatile LONG active;
    volatile LONG cancel_sequence;
#else
    volatile uint32_t cancel_sequence;
#endif
} os_pread_cancellable_t;

#ifdef __cplusplus
extern "C" {
#endif

void os_file_init(os_file_t *f);
int os_file_open_read(os_file_t *f, const char *path_utf8);
int os_file_dup(os_file_t *dst, const os_file_t *src);
int os_file_reopen_read_sequential(os_file_t *dst, const os_file_t *src,
                                   int overlapped);
void os_file_close(os_file_t *f);
int os_file_valid(const os_file_t *f);
uint64_t os_file_size(const os_file_t *f);
int64_t os_pread(const os_file_t *f, void *buf, uint64_t len, uint64_t off);
void os_pread_cancellable_init(os_pread_cancellable_t *state);
void os_pread_cancellable_reset(os_pread_cancellable_t *state);
int64_t os_pread_cancellable(const os_file_t *f, void *buf, uint64_t len,
                             uint64_t off, os_pread_cancellable_t *state,
                             uint32_t sequence);
int64_t os_pread_cancellable_timeout(
    const os_file_t *f, void *buf, uint64_t len, uint64_t off,
    os_pread_cancellable_t *state, uint32_t sequence, uint32_t timeout_ms);
int os_pread_cancel(os_pread_cancellable_t *state, uint32_t sequence);
FILE *os_fopen(const char *path_utf8, const char *mode);

#ifdef __cplusplus
}
#endif

#endif
