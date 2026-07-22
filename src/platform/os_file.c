#include "os_file.h"
#include "os_clock.h"

#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <string.h>

#ifdef _WIN32
#include "os_path.h"

#include <stdlib.h>
#else
#include <aio.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <time.h>

typedef struct {
    struct aiocb aio;
    _Atomic uint32_t active;
    _Atomic uint32_t cancel_sequence;
} os_pread_cancellable_impl_t;

_Static_assert(sizeof(os_pread_cancellable_impl_t) <=
                   sizeof(((os_pread_cancellable_t *)0)->opaque),
               "os_pread_cancellable_t opaque storage is too small");
_Static_assert(_Alignof(os_pread_cancellable_impl_t) <=
                   _Alignof(os_pread_cancellable_t),
               "os_pread_cancellable_t opaque storage is under-aligned");

static os_pread_cancellable_impl_t *os_pread_cancellable_impl(
        os_pread_cancellable_t *state) {
    return (os_pread_cancellable_impl_t *)(void *)state->opaque;
}
#endif

#ifdef _WIN32
static int os_win_error_to_errno(DWORD e) {
    switch (e) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
        return ENOENT;
    case ERROR_ACCESS_DENIED:
        return EACCES;
    case ERROR_SHARING_VIOLATION:
    case ERROR_LOCK_VIOLATION:
        return EBUSY;
    case ERROR_ALREADY_EXISTS:
    case ERROR_FILE_EXISTS:
        return EEXIST;
    case ERROR_HANDLE_EOF:
        return 0;
    case ERROR_INVALID_HANDLE:
        return EBADF;
    case ERROR_INVALID_PARAMETER:
    case ERROR_INVALID_FUNCTION:
        return EINVAL;
    case ERROR_NOT_ENOUGH_MEMORY:
    case ERROR_OUTOFMEMORY:
        return ENOMEM;
    default:
        return EIO;
    }
}
#endif

void os_file_init(os_file_t *f) {
    if (!f) return;
#ifdef _WIN32
    f->h = INVALID_HANDLE_VALUE;
#else
    f->fd = -1;
#endif
}

int os_file_valid(const os_file_t *f) {
    if (!f) return 0;
#ifdef _WIN32
    return f->h != NULL && f->h != INVALID_HANDLE_VALUE;
#else
    return f->fd >= 0;
#endif
}

int os_file_open_read(os_file_t *f, const char *path_utf8) {
    if (!f || !path_utf8) {
        errno = EINVAL;
        return -1;
    }
    os_file_init(f);
#ifdef _WIN32
    wchar_t wpath[OS_MAX_PATH_W];
    if (os_utf8_to_wide(path_utf8, wpath, OS_MAX_PATH_W) <= 0) {
        errno = EINVAL;
        return -1;
    }
    HANDLE h = CreateFileW(wpath,
                           GENERIC_READ,
                           FILE_SHARE_READ,
                           NULL,
                           OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL |
                               FILE_FLAG_RANDOM_ACCESS |
                               FILE_FLAG_OVERLAPPED,
                           NULL);
    if (h == INVALID_HANDLE_VALUE) {
        errno = os_win_error_to_errno(GetLastError());
        return -1;
    }
    f->h = h;
    return 0;
#else
    int fd = open(path_utf8, O_RDONLY);
    if (fd < 0) return -1;
    f->fd = fd;
    return 0;
#endif
}

int os_file_dup(os_file_t *dst, const os_file_t *src) {
    if (!dst || !os_file_valid(src)) {
        errno = EINVAL;
        return -1;
    }
    os_file_init(dst);
#ifdef _WIN32
    HANDLE h = INVALID_HANDLE_VALUE;
    HANDLE self = GetCurrentProcess();
    if (!DuplicateHandle(self, src->h, self, &h, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
        errno = os_win_error_to_errno(GetLastError());
        return -1;
    }
    dst->h = h;
    return 0;
#else
    int fd = dup(src->fd);
    if (fd < 0) return -1;
    dst->fd = fd;
    return 0;
#endif
}

int os_file_reopen_read_sequential(os_file_t *dst, const os_file_t *src,
                                   int overlapped) {
    if (!dst || !os_file_valid(src)) {
        errno = EINVAL;
        return -1;
    }
    if (os_file_valid(dst)) {
        errno = EBUSY;
        return -1;
    }
    os_file_init(dst);
#ifdef _WIN32
    DWORD flags = FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN;
    if (overlapped) flags |= FILE_FLAG_OVERLAPPED;
    wchar_t path[OS_MAX_PATH_W];
    DWORD path_len = GetFinalPathNameByHandleW(
        src->h, path, OS_MAX_PATH_W,
        FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (path_len == 0 || path_len >= OS_MAX_PATH_W) {
        errno = path_len >= OS_MAX_PATH_W ? ENAMETOOLONG :
            os_win_error_to_errno(GetLastError());
        return -1;
    }
    HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                           OPEN_EXISTING, flags, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        errno = os_win_error_to_errno(GetLastError());
        return -1;
    }
    dst->h = h;
    return 0;
#else
    (void)overlapped;
    return os_file_dup(dst, src);
#endif
}

FILE *os_fopen(const char *path_utf8, const char *mode) {
#ifdef _WIN32
    wchar_t wpath[OS_MAX_PATH_W];
    wchar_t wmode[32];
    if (os_utf8_to_wide(path_utf8, wpath, OS_MAX_PATH_W) <= 0) {
        errno = EINVAL;
        return NULL;
    }
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, mode, -1, wmode, 32);
    if (n <= 0) {
        errno = EINVAL;
        return NULL;
    }
    FILE *fp = _wfopen(wpath, wmode);
    if (!fp) errno = os_win_error_to_errno(GetLastError());
    return fp;
#else
    return fopen(path_utf8, mode);
#endif
}

void os_file_close(os_file_t *f) {
    if (!f || !os_file_valid(f)) return;
#ifdef _WIN32
    CloseHandle(f->h);
    f->h = INVALID_HANDLE_VALUE;
#else
    close(f->fd);
    f->fd = -1;
#endif
}

uint64_t os_file_size(const os_file_t *f) {
    if (!os_file_valid(f)) {
        errno = EBADF;
        return UINT64_MAX;
    }
#ifdef _WIN32
    LARGE_INTEGER sz;
    if (!GetFileSizeEx(f->h, &sz) || sz.QuadPart < 0) {
        errno = os_win_error_to_errno(GetLastError());
        return UINT64_MAX;
    }
    return (uint64_t)sz.QuadPart;
#else
    struct stat st;
    if (fstat(f->fd, &st) != 0 || st.st_size < 0) return UINT64_MAX;
    return (uint64_t)st.st_size;
#endif
}

void os_pread_cancellable_init(os_pread_cancellable_t *state) {
    if (!state) return;
    memset(state, 0, sizeof(*state));
#ifdef _WIN32
    state->file = INVALID_HANDLE_VALUE;
#else
    os_pread_cancellable_impl_t *impl = os_pread_cancellable_impl(state);
    atomic_init(&impl->active, 0u);
    atomic_init(&impl->cancel_sequence, 0u);
#endif
}

int os_pread_cancellable_prepare(os_pread_cancellable_t *state) {
    if (!state) {
        errno = EINVAL;
        return -1;
    }
#ifdef _WIN32
    if (state->event) return 0;
    state->event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!state->event) {
        errno = os_win_error_to_errno(GetLastError());
        return -1;
    }
#endif
    return 0;
}

int os_pread_cancellable_pending(os_pread_cancellable_t *state) {
    if (!state) return 0;
#ifdef _WIN32
    if (InterlockedCompareExchange(&state->active, 1, 1) != 1) return 0;
    DWORD got = 0;
    if (GetOverlappedResult(state->file, &state->overlapped, &got, FALSE)) {
        InterlockedExchange(&state->active, 0);
        state->file = INVALID_HANDLE_VALUE;
        return 0;
    }
    if (GetLastError() == ERROR_IO_INCOMPLETE) return 1;
    InterlockedExchange(&state->active, 0);
    state->file = INVALID_HANDLE_VALUE;
    return 0;
#else
    os_pread_cancellable_impl_t *impl = os_pread_cancellable_impl(state);
    if (atomic_load_explicit(&impl->active, memory_order_acquire) == 0u) {
        return 0;
    }
    const int status = aio_error(&impl->aio);
    if (status == EINPROGRESS) return 1;
    (void)aio_return(&impl->aio);
    atomic_store_explicit(&impl->active, 0u, memory_order_release);
    return 0;
#endif
}

void os_pread_cancellable_destroy(os_pread_cancellable_t *state) {
    if (!state) return;
#ifdef _WIN32
    if (InterlockedCompareExchange(&state->active, 1, 1) == 1) {
        (void)CancelIoEx(state->file, &state->overlapped);
        (void)WaitForSingleObject(state->event, INFINITE);
        DWORD got = 0;
        (void)GetOverlappedResult(
            state->file, &state->overlapped, &got, FALSE);
        InterlockedExchange(&state->active, 0);
    }
    state->file = INVALID_HANDLE_VALUE;
    if (state->event) CloseHandle(state->event);
    state->event = NULL;
#else
    os_pread_cancellable_impl_t *impl = os_pread_cancellable_impl(state);
    if (atomic_load_explicit(&impl->active, memory_order_acquire) != 0u) {
        (void)aio_cancel(impl->aio.aio_fildes, &impl->aio);
        while (aio_error(&impl->aio) == EINPROGRESS) {
            const struct timespec pause = {0, 1000000};
            (void)nanosleep(&pause, NULL);
        }
        (void)aio_return(&impl->aio);
        atomic_store_explicit(&impl->active, 0u, memory_order_release);
    }
#endif
}

void os_pread_cancellable_reset(os_pread_cancellable_t *state) {
#ifdef _WIN32
    if (state) InterlockedExchange(&state->cancel_sequence, 0);
#else
    if (state) {
        os_pread_cancellable_impl_t *impl = os_pread_cancellable_impl(state);
        atomic_store_explicit(
            &impl->cancel_sequence, 0u, memory_order_release);
    }
#endif
}

int os_pread_cancel(os_pread_cancellable_t *state, uint32_t sequence) {
#ifdef _WIN32
    if (!state) return 0;
    InterlockedExchange(&state->cancel_sequence, (LONG)sequence);
    if (InterlockedCompareExchange(&state->active, 1, 1) != 1 ||
        state->file == NULL || state->file == INVALID_HANDLE_VALUE) {
        return 0;
    }
    if (CancelIoEx(state->file, &state->overlapped)) return 1;
    return GetLastError() == ERROR_NOT_FOUND;
#else
    if (!state) return 0;
    os_pread_cancellable_impl_t *impl = os_pread_cancellable_impl(state);
    atomic_store_explicit(
        &impl->cancel_sequence, sequence, memory_order_release);
    if (atomic_load_explicit(&impl->active, memory_order_acquire) != 0u) {
        (void)aio_cancel(impl->aio.aio_fildes, &impl->aio);
    }
    return 1;
#endif
}

int64_t os_pread_cancellable_timeout(
        const os_file_t *f, void *buf, uint64_t len, uint64_t off,
        os_pread_cancellable_t *state, uint32_t sequence,
        uint32_t timeout_ms) {
    if (!os_file_valid(f) || (!buf && len != 0)) {
        errno = EINVAL;
        return -1;
    }
    if (!state || os_pread_cancellable_prepare(state) != 0) {
        errno = EINVAL;
        return -1;
    }
    if (os_pread_cancellable_pending(state)) {
        errno = EBUSY;
        return -1;
    }
    uint64_t done = 0;
#ifdef _WIN32
    const ULONGLONG started_tick = GetTickCount64();
    while (done < len) {
        const uint64_t remaining = len - done;
        DWORD chunk = (DWORD)(remaining > 0x100000ull ? 0x100000ul : remaining);
        memset(&state->overlapped, 0, sizeof(state->overlapped));
        const uint64_t cur = off + done;
        state->overlapped.Offset = (DWORD)(cur & 0xffffffffu);
        state->overlapped.OffsetHigh = (DWORD)(cur >> 32);
        state->overlapped.hEvent = state->event;
        state->file = f->h;
        ResetEvent(state->event);
        /* Arm and start the real read before honoring a pre-cancel or zero
         * timeout. This closes the check/submit race and makes those cases
         * exercise the same kernel-I/O lifetime as ordinary cancellation. */
        InterlockedExchange(&state->active, 1);

        DWORD got = 0;
        BOOL ok = ReadFile(
            f->h, (char *)buf + done, chunk, NULL, &state->overlapped);
        const int cancel_requested = InterlockedCompareExchange(
            &state->cancel_sequence, 0, 0) == (LONG)sequence;
        if (cancel_requested || timeout_ms == 0u) {
            (void)CancelIoEx(f->h, &state->overlapped);
        }
        if (!ok) {
            DWORD err = GetLastError();
            if (err == ERROR_IO_PENDING) {
                /* Close the check-to-submit window: a cancel that found the
                 * armed operation before ReadFile queued it is reissued by
                 * the worker before it waits. */
                if (InterlockedCompareExchange(
                        &state->cancel_sequence, 0, 0) == (LONG)sequence) {
                    (void)CancelIoEx(f->h, &state->overlapped);
                }
                DWORD wait_ms = INFINITE;
                if (timeout_ms != UINT32_MAX) {
                    const ULONGLONG elapsed = GetTickCount64() - started_tick;
                    wait_ms = elapsed >= timeout_ms ? 0u :
                        (DWORD)(timeout_ms - elapsed);
                }
                if (cancel_requested || timeout_ms == 0u) wait_ms = 0u;
                const DWORD waited = WaitForSingleObject(state->event, wait_ms);
                if (waited == WAIT_TIMEOUT) {
                    (void)CancelIoEx(f->h, &state->overlapped);
                    /* A timeout never clears or reuses this slot. The
                     * OVERLAPPED, event, and caller-owned persistent buffer stay
                     * alive until pending() observes GetOverlappedResult. */
                    const DWORD cancelled = WaitForSingleObject(state->event, 50u);
                    if (cancelled == WAIT_OBJECT_0) {
                        (void)GetOverlappedResult(
                            f->h, &state->overlapped, &got, FALSE);
                        InterlockedExchange(&state->active, 0);
                        state->file = INVALID_HANDLE_VALUE;
                    }
                    errno = cancel_requested ? ECANCELED : ETIMEDOUT;
                    return -1;
                }
                if (waited != WAIT_OBJECT_0) {
                    (void)CancelIoEx(f->h, &state->overlapped);
                    const DWORD cancelled = WaitForSingleObject(state->event, 50u);
                    if (cancelled == WAIT_OBJECT_0) {
                        (void)GetOverlappedResult(
                            f->h, &state->overlapped, &got, FALSE);
                        InterlockedExchange(&state->active, 0);
                        state->file = INVALID_HANDLE_VALUE;
                    }
                    errno = EIO;
                    return -1;
                }
                ok = GetOverlappedResult(
                    f->h, &state->overlapped, &got, FALSE);
                if (!ok) err = GetLastError();
            }
            if (!ok) {
                InterlockedExchange(&state->active, 0);
                state->file = INVALID_HANDLE_VALUE;
                if (cancel_requested || timeout_ms == 0u) {
                    errno = cancel_requested ? ECANCELED : ETIMEDOUT;
                    return -1;
                }
                if (err == ERROR_HANDLE_EOF) return (int64_t)done;
                errno = os_win_error_to_errno(err);
                return -1;
            }
        } else if (!GetOverlappedResult(
                       f->h, &state->overlapped, &got, FALSE)) {
            DWORD err = GetLastError();
            InterlockedExchange(&state->active, 0);
            state->file = INVALID_HANDLE_VALUE;
            if (err == ERROR_HANDLE_EOF) return (int64_t)done;
            errno = os_win_error_to_errno(err);
            return -1;
        }
        InterlockedExchange(&state->active, 0);
        state->file = INVALID_HANDLE_VALUE;
        if (cancel_requested || timeout_ms == 0u) {
            errno = cancel_requested ? ECANCELED : ETIMEDOUT;
            return -1;
        }
        if (got == 0) break;
        done += got;
    }
#else
    os_pread_cancellable_impl_t *impl = os_pread_cancellable_impl(state);
    const double deadline = timeout_ms == UINT32_MAX ? 0.0 :
        os_monotonic_sec() + (double)timeout_ms * 0.001;
    const uint64_t max_chunk = 1024u * 1024u;
    while (done < len) {
        const uint64_t remaining = len - done;
        size_t chunk = remaining > max_chunk ? (size_t)max_chunk :
            (size_t)remaining;
        if (chunk > (size_t)SSIZE_MAX) chunk = (size_t)SSIZE_MAX;
        memset(&impl->aio, 0, sizeof(impl->aio));
        impl->aio.aio_fildes = f->fd;
        impl->aio.aio_buf = (char *)buf + done;
        impl->aio.aio_nbytes = chunk;
        impl->aio.aio_offset = (off_t)(off + done);
        atomic_store_explicit(&impl->active, 1u, memory_order_release);
        if (aio_read(&impl->aio) != 0) {
            atomic_store_explicit(&impl->active, 0u, memory_order_release);
            return -1;
        }
        for (;;) {
            const int cancel_requested = atomic_load_explicit(
                &impl->cancel_sequence, memory_order_acquire) == sequence;
            const int timed_out = deadline != 0.0 &&
                os_monotonic_sec() >= deadline;
            if (cancel_requested || timed_out) {
                (void)aio_cancel(f->fd, &impl->aio);
                const int status = aio_error(&impl->aio);
                if (status != EINPROGRESS) {
                    (void)aio_return(&impl->aio);
                    atomic_store_explicit(
                        &impl->active, 0u, memory_order_release);
                }
                errno = cancel_requested ? ECANCELED : ETIMEDOUT;
                return -1;
            }
            const int status = aio_error(&impl->aio);
            if (status == EINPROGRESS) {
                const struct timespec pause = {0, 1000000};
                (void)nanosleep(&pause, NULL);
                continue;
            }
            const ssize_t n = aio_return(&impl->aio);
            atomic_store_explicit(
                &impl->active, 0u, memory_order_release);
            if (status != 0 || n < 0) {
                errno = status != 0 ? status : errno;
                return -1;
            }
            if (n == 0) return (int64_t)done;
            done += (uint64_t)n;
            break;
        }
    }
#endif
    return (int64_t)done;
}

int64_t os_pread_cancellable(const os_file_t *f, void *buf, uint64_t len,
                             uint64_t off, os_pread_cancellable_t *state,
                             uint32_t sequence) {
    return os_pread_cancellable_timeout(
        f, buf, len, off, state, sequence, UINT32_MAX);
}

int64_t os_pread_plain(const os_file_t *f, void *buf, uint64_t len,
                       uint64_t off) {
    const uint64_t max_chunk = 1024u * 1024u;
    if (!os_file_valid(f) || (!buf && len != 0) || len > max_chunk) {
        errno = EINVAL;
        return -1;
    }
    if (len == 0) return 0;
#ifdef _WIN32
    LARGE_INTEGER position;
    position.QuadPart = (LONGLONG)off;
    if (!SetFilePointerEx(f->h, position, NULL, FILE_BEGIN)) {
        errno = os_win_error_to_errno(GetLastError());
        return -1;
    }
    DWORD got = 0;
    if (!ReadFile(f->h, buf, (DWORD)len, &got, NULL)) {
        const DWORD error = GetLastError();
        if (error == ERROR_HANDLE_EOF) return 0;
        errno = os_win_error_to_errno(error);
        return -1;
    }
    return (int64_t)got;
#else
    for (;;) {
        const ssize_t got = pread(f->fd, buf, (size_t)len, (off_t)off);
        if (got < 0 && errno == EINTR) continue;
        return (int64_t)got;
    }
#endif
}

int64_t os_pread(const os_file_t *f, void *buf, uint64_t len, uint64_t off) {
    if (!os_file_valid(f) || (!buf && len != 0)) {
        errno = EINVAL;
        return -1;
    }
    uint64_t done = 0;
#ifdef _WIN32
    HANDLE ev = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!ev) {
        errno = os_win_error_to_errno(GetLastError());
        return -1;
    }
    while (done < len) {
        const uint64_t remaining = len - done;
        DWORD chunk = (DWORD)(remaining > 0x40000000ull ? 0x40000000ul : remaining);
        OVERLAPPED ol;
        memset(&ol, 0, sizeof(ol));
        const uint64_t cur = off + done;
        ol.Offset = (DWORD)(cur & 0xffffffffu);
        ol.OffsetHigh = (DWORD)(cur >> 32);
        ol.hEvent = ev;
        ResetEvent(ev);

        DWORD got = 0;
        BOOL ok = ReadFile(f->h, (char *)buf + done, chunk, NULL, &ol);
        if (!ok) {
            DWORD err = GetLastError();
            if (err == ERROR_IO_PENDING) {
                ok = GetOverlappedResult(f->h, &ol, &got, TRUE);
                if (!ok) err = GetLastError();
            }
            if (!ok) {
                CloseHandle(ev);
                if (err == ERROR_HANDLE_EOF) return (int64_t)done;
                errno = os_win_error_to_errno(err);
                return -1;
            }
        } else if (!GetOverlappedResult(f->h, &ol, &got, FALSE)) {
            DWORD err = GetLastError();
            CloseHandle(ev);
            if (err == ERROR_HANDLE_EOF) return (int64_t)done;
            errno = os_win_error_to_errno(err);
            return -1;
        }
        if (got == 0) break;
        done += got;
    }
    CloseHandle(ev);
#else
    while (done < len) {
        const uint64_t remaining = len - done;
        size_t chunk = remaining > (uint64_t)SSIZE_MAX ? (size_t)SSIZE_MAX : (size_t)remaining;
        ssize_t n = pread(f->fd, (char *)buf + done, chunk, (off_t)(off + done));
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (n == 0) break;
        done += (uint64_t)n;
    }
#endif
    return (int64_t)done;
}
