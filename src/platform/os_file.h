#ifndef DS4_OS_FILE_H
#define DS4_OS_FILE_H

#include <stdint.h>
#include <stdio.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

typedef struct {
#ifdef _WIN32
    HANDLE h;
#else
    int fd;
#endif
} os_file_t;

#ifdef _WIN32
typedef struct {
    HANDLE file;
    HANDLE event;
    OVERLAPPED overlapped;
    volatile LONG active;
    volatile LONG cancel_sequence;
} os_pread_cancellable_t;
#else
typedef union {
    /* POSIX AIO state, including its C11 atomics, is private to os_file.c.
     * Fixed opaque storage gives C and C++ consumers one ABI view. */
    void *pointer_alignment;
    long double scalar_alignment;
    unsigned char opaque[256];
} os_pread_cancellable_t;
#endif

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
/* One plain synchronous positional read, capped at 1 MiB. On Windows the file
 * must have been opened without FILE_FLAG_OVERLAPPED. */
int64_t os_pread_plain(const os_file_t *f, void *buf, uint64_t len,
                       uint64_t off);
void os_pread_cancellable_init(os_pread_cancellable_t *state);
int os_pread_cancellable_prepare(os_pread_cancellable_t *state);
void os_pread_cancellable_reset(os_pread_cancellable_t *state);
int os_pread_cancellable_pending(os_pread_cancellable_t *state);
void os_pread_cancellable_destroy(os_pread_cancellable_t *state);
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
