#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <cuda_runtime.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const uint64_t kGiB = 1024ULL * 1024ULL * 1024ULL;
static const uint64_t kMiB = 1024ULL * 1024ULL;
static_assert(sizeof(size_t) == 8, "g17_arena_probe requires a 64-bit process");

struct ProbeResult {
    char timestamp_utc[32];
    DWORD process_id;
    bool success;
    bool host_alloc_succeeded;
    bool touch_succeeded;
    bool h2d_succeeded;
    const char *failure_kind;
    const char *failure_stage;
    const char *argument_error;
    cudaError_t cuda_error;
    DWORD windows_error;

    uint64_t requested_arena_gib;
    uint64_t arena_bytes;
    uint64_t requested_device_buffer_mib;
    uint64_t device_buffer_bytes;
    uint64_t h2d_iterations;
    uint64_t page_size_bytes;
    uint64_t pages_touched;
    uint64_t h2d_bytes;

    double host_alloc_seconds;
    double touch_seconds;
    double h2d_seconds;
    double h2d_gbps;
    double h2d_gib_per_second;

    uint64_t windows_available_physical_bytes_before;
    uint64_t windows_available_physical_bytes_after_host_alloc;
    uint64_t windows_available_physical_bytes_after_touch;
    uint64_t windows_available_physical_bytes_after_bandwidth;
    uint64_t windows_available_physical_bytes_after_cleanup;

    uint64_t cuda_free_vram_bytes_before;
    uint64_t cuda_total_vram_bytes_before;
    uint64_t cuda_free_vram_bytes_after_host_alloc;
    uint64_t cuda_total_vram_bytes_after_host_alloc;
    uint64_t cuda_free_vram_bytes_after_device_alloc;
    uint64_t cuda_total_vram_bytes_after_device_alloc;
    uint64_t cuda_free_vram_bytes_after_bandwidth;
    uint64_t cuda_total_vram_bytes_after_bandwidth;
    uint64_t cuda_free_vram_bytes_after_cleanup;
    uint64_t cuda_total_vram_bytes_after_cleanup;

    int cuda_device_ordinal;
    char cuda_device_name[256];
};

static void initialize_result(ProbeResult *result) {
    memset(result, 0, sizeof(*result));
    SYSTEMTIME now;
    GetSystemTime(&now);
    _snprintf_s(result->timestamp_utc, sizeof(result->timestamp_utc), _TRUNCATE,
                "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
                now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
                now.wSecond, now.wMilliseconds);
    result->process_id = GetCurrentProcessId();
    result->failure_kind = "none";
    result->cuda_error = cudaSuccess;
    result->cuda_device_ordinal = 0;
}

static void set_argument_failure(ProbeResult *result, const char *stage,
                                 const char *message) {
    if (result->failure_stage == NULL) {
        result->failure_kind = "argument";
        result->failure_stage = stage;
        result->argument_error = message;
    }
}

static void set_cuda_failure(ProbeResult *result, const char *stage,
                             cudaError_t error) {
    if (error != cudaSuccess && result->failure_stage == NULL) {
        result->failure_kind = "cuda";
        result->failure_stage = stage;
        result->cuda_error = error;
    }
}

static void set_windows_failure(ProbeResult *result, const char *stage,
                                DWORD error) {
    if (error != ERROR_SUCCESS && result->failure_stage == NULL) {
        result->failure_kind = "windows";
        result->failure_stage = stage;
        result->windows_error = error;
    }
}

static DWORD query_available_physical_memory(uint64_t *available_bytes) {
    MEMORYSTATUSEX status;
    memset(&status, 0, sizeof(status));
    status.dwLength = sizeof(status);
    if (!GlobalMemoryStatusEx(&status)) {
        return GetLastError();
    }
    *available_bytes = (uint64_t)status.ullAvailPhys;
    return ERROR_SUCCESS;
}

static cudaError_t query_vram(uint64_t *free_bytes, uint64_t *total_bytes) {
    size_t free_value = 0;
    size_t total_value = 0;
    cudaError_t error = cudaMemGetInfo(&free_value, &total_value);
    if (error == cudaSuccess) {
        *free_bytes = (uint64_t)free_value;
        *total_bytes = (uint64_t)total_value;
    }
    return error;
}

static bool parse_positive_uint64(const char *text, uint64_t *value) {
    char *end = NULL;
    errno = 0;
    unsigned __int64 parsed = _strtoui64(text, &end, 10);
    if (errno == ERANGE || end == text || *end != '\0' || parsed == 0) {
        return false;
    }
    *value = (uint64_t)parsed;
    return true;
}

static double elapsed_seconds(LARGE_INTEGER start, LARGE_INTEGER end,
                              LARGE_INTEGER frequency) {
    return (double)(end.QuadPart - start.QuadPart) / (double)frequency.QuadPart;
}

static void print_json_string(const char *value) {
    putchar('"');
    if (value != NULL) {
        const unsigned char *cursor = (const unsigned char *)value;
        while (*cursor != 0) {
            switch (*cursor) {
                case '"': fputs("\\\"", stdout); break;
                case '\\': fputs("\\\\", stdout); break;
                case '\b': fputs("\\b", stdout); break;
                case '\f': fputs("\\f", stdout); break;
                case '\n': fputs("\\n", stdout); break;
                case '\r': fputs("\\r", stdout); break;
                case '\t': fputs("\\t", stdout); break;
                default:
                    if (*cursor < 0x20) {
                        printf("\\u%04x", (unsigned int)*cursor);
                    } else {
                        putchar((int)*cursor);
                    }
                    break;
            }
            ++cursor;
        }
    }
    putchar('"');
}

static void print_nullable_json_string(const char *value) {
    if (value == NULL) {
        fputs("null", stdout);
    } else {
        print_json_string(value);
    }
}

static void windows_error_message(DWORD error, char *buffer, size_t buffer_size) {
    if (error == ERROR_SUCCESS) {
        _snprintf_s(buffer, buffer_size, _TRUNCATE, "The operation completed successfully.");
        return;
    }

    DWORD length = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
                                      FORMAT_MESSAGE_IGNORE_INSERTS,
                                  NULL, error, 0, buffer, (DWORD)buffer_size, NULL);
    if (length == 0) {
        _snprintf_s(buffer, buffer_size, _TRUNCATE, "Windows error %lu",
                    (unsigned long)error);
        return;
    }
    while (length > 0 && (buffer[length - 1] == '\r' || buffer[length - 1] == '\n')) {
        buffer[--length] = '\0';
    }
}

static void print_result(const ProbeResult *result) {
    char windows_message[512];
    windows_error_message(result->windows_error, windows_message,
                          sizeof(windows_message));

    const char *failure_message = NULL;
    if (strcmp(result->failure_kind, "cuda") == 0) {
        failure_message = cudaGetErrorString(result->cuda_error);
    } else if (strcmp(result->failure_kind, "windows") == 0) {
        failure_message = windows_message;
    } else if (strcmp(result->failure_kind, "argument") == 0) {
        failure_message = result->argument_error;
    }

    fputs("{\"schema\":\"g17_arena_probe_v1\",\"timestamp_utc\":", stdout);
    print_json_string(result->timestamp_utc);
    printf(",\"process_id\":%lu,\"success\":%s",
           (unsigned long)result->process_id, result->success ? "true" : "false");
    fputs(",\"failure_kind\":", stdout);
    print_json_string(result->failure_kind);
    fputs(",\"failure_stage\":", stdout);
    print_nullable_json_string(result->failure_stage);
    fputs(",\"failure_message\":", stdout);
    print_nullable_json_string(failure_message);
    printf(",\"cuda_error_code\":%d", (int)result->cuda_error);
    fputs(",\"cuda_error_name\":", stdout);
    print_json_string(cudaGetErrorName(result->cuda_error));
    printf(",\"windows_error_code\":%lu", (unsigned long)result->windows_error);

    printf(",\"requested_arena_gib\":%llu,\"arena_bytes\":%llu",
           (unsigned long long)result->requested_arena_gib,
           (unsigned long long)result->arena_bytes);
    printf(",\"host_alloc_succeeded\":%s,\"host_alloc_seconds\":%.9f",
           result->host_alloc_succeeded ? "true" : "false",
           result->host_alloc_seconds);
    printf(",\"page_size_bytes\":%llu,\"pages_touched\":%llu",
           (unsigned long long)result->page_size_bytes,
           (unsigned long long)result->pages_touched);
    printf(",\"touch_succeeded\":%s,\"touch_seconds\":%.9f",
           result->touch_succeeded ? "true" : "false", result->touch_seconds);
    printf(",\"requested_device_buffer_mib\":%llu,\"device_buffer_bytes\":%llu",
           (unsigned long long)result->requested_device_buffer_mib,
           (unsigned long long)result->device_buffer_bytes);
    printf(",\"h2d_iterations\":%llu,\"h2d_bytes\":%llu",
           (unsigned long long)result->h2d_iterations,
           (unsigned long long)result->h2d_bytes);
    printf(",\"h2d_succeeded\":%s,\"h2d_seconds\":%.9f",
           result->h2d_succeeded ? "true" : "false", result->h2d_seconds);
    printf(",\"h2d_gbps\":%.6f,\"h2d_gib_per_second\":%.6f",
           result->h2d_gbps, result->h2d_gib_per_second);

    printf(",\"windows_available_physical_bytes_before\":%llu",
           (unsigned long long)result->windows_available_physical_bytes_before);
    printf(",\"windows_available_physical_bytes_after_host_alloc\":%llu",
           (unsigned long long)result->windows_available_physical_bytes_after_host_alloc);
    printf(",\"windows_available_physical_bytes_after_touch\":%llu",
           (unsigned long long)result->windows_available_physical_bytes_after_touch);
    printf(",\"windows_available_physical_bytes_after_bandwidth\":%llu",
           (unsigned long long)result->windows_available_physical_bytes_after_bandwidth);
    printf(",\"windows_available_physical_bytes_after_cleanup\":%llu",
           (unsigned long long)result->windows_available_physical_bytes_after_cleanup);

    printf(",\"cuda_free_vram_bytes_before\":%llu,\"cuda_total_vram_bytes_before\":%llu",
           (unsigned long long)result->cuda_free_vram_bytes_before,
           (unsigned long long)result->cuda_total_vram_bytes_before);
    printf(",\"cuda_free_vram_bytes_after_host_alloc\":%llu,\"cuda_total_vram_bytes_after_host_alloc\":%llu",
           (unsigned long long)result->cuda_free_vram_bytes_after_host_alloc,
           (unsigned long long)result->cuda_total_vram_bytes_after_host_alloc);
    printf(",\"cuda_free_vram_bytes_after_device_alloc\":%llu,\"cuda_total_vram_bytes_after_device_alloc\":%llu",
           (unsigned long long)result->cuda_free_vram_bytes_after_device_alloc,
           (unsigned long long)result->cuda_total_vram_bytes_after_device_alloc);
    printf(",\"cuda_free_vram_bytes_after_bandwidth\":%llu,\"cuda_total_vram_bytes_after_bandwidth\":%llu",
           (unsigned long long)result->cuda_free_vram_bytes_after_bandwidth,
           (unsigned long long)result->cuda_total_vram_bytes_after_bandwidth);
    printf(",\"cuda_free_vram_bytes_after_cleanup\":%llu,\"cuda_total_vram_bytes_after_cleanup\":%llu",
           (unsigned long long)result->cuda_free_vram_bytes_after_cleanup,
           (unsigned long long)result->cuda_total_vram_bytes_after_cleanup);

    printf(",\"cuda_device_ordinal\":%d,\"cuda_device_name\":",
           result->cuda_device_ordinal);
    print_json_string(result->cuda_device_name);
    fputs("}\n", stdout);
    fflush(stdout);
}

static int run_probe(uint64_t arena_gib, uint64_t device_buffer_mib,
                     uint64_t iterations) {
    ProbeResult result;
    void *host_pointer = NULL;
    void *device_pointer = NULL;
    cudaStream_t stream = NULL;
    cudaEvent_t start_event = NULL;
    cudaEvent_t stop_event = NULL;
    bool cuda_device_selected = false;
    bool cuda_context_ready = false;
    LARGE_INTEGER qpc_frequency;
    LARGE_INTEGER start_time;
    LARGE_INTEGER end_time;
    SYSTEM_INFO system_info;
    cudaDeviceProp device_properties;
    cudaError_t error = cudaSuccess;
    DWORD windows_error = ERROR_SUCCESS;
    size_t arena_bytes = 0;
    size_t device_buffer_bytes = 0;
    float elapsed_milliseconds = 0.0f;

    initialize_result(&result);
    result.requested_arena_gib = arena_gib;
    result.requested_device_buffer_mib = device_buffer_mib;
    result.h2d_iterations = iterations;

    if (arena_gib > (uint64_t)SIZE_MAX / kGiB) {
        set_argument_failure(&result, "arena_size", "Arena size overflows size_t.");
        goto cleanup;
    }
    if (device_buffer_mib > (uint64_t)SIZE_MAX / kMiB) {
        set_argument_failure(&result, "device_buffer_size",
                             "Device buffer size overflows size_t.");
        goto cleanup;
    }

    arena_bytes = (size_t)(arena_gib * kGiB);
    device_buffer_bytes = (size_t)(device_buffer_mib * kMiB);
    if (device_buffer_bytes > arena_bytes) {
        device_buffer_bytes = arena_bytes;
    }
    if (arena_bytes > UINT64_MAX / iterations) {
        set_argument_failure(&result, "h2d_byte_count",
                             "Transferred byte count overflows uint64_t.");
        goto cleanup;
    }
    result.arena_bytes = (uint64_t)arena_bytes;
    result.device_buffer_bytes = (uint64_t)device_buffer_bytes;
    result.h2d_bytes = (uint64_t)arena_bytes * iterations;

    QueryPerformanceFrequency(&qpc_frequency);
    GetSystemInfo(&system_info);
    result.page_size_bytes = (uint64_t)system_info.dwPageSize;
    if (result.page_size_bytes == 0) {
        result.page_size_bytes = 4096;
    }

    windows_error = query_available_physical_memory(
        &result.windows_available_physical_bytes_before);
    set_windows_failure(&result, "windows_memory_before", windows_error);

    error = cudaSetDevice(result.cuda_device_ordinal);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_set_device", error);
        goto cleanup;
    }
    cuda_device_selected = true;

    error = cudaFree(NULL);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_context_initialization", error);
        goto cleanup;
    }
    cuda_context_ready = true;

    memset(&device_properties, 0, sizeof(device_properties));
    error = cudaGetDeviceProperties(&device_properties, result.cuda_device_ordinal);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_device_properties", error);
        goto cleanup;
    }
    strncpy_s(result.cuda_device_name, sizeof(result.cuda_device_name),
              device_properties.name, _TRUNCATE);

    error = query_vram(&result.cuda_free_vram_bytes_before,
                       &result.cuda_total_vram_bytes_before);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_vram_before", error);
        goto cleanup;
    }

    QueryPerformanceCounter(&start_time);
    error = cudaHostAlloc(&host_pointer, arena_bytes, cudaHostAllocDefault);
    QueryPerformanceCounter(&end_time);
    result.host_alloc_seconds = elapsed_seconds(start_time, end_time, qpc_frequency);
    if (error == cudaSuccess) {
        result.host_alloc_succeeded = true;
    } else {
        set_cuda_failure(&result, "cuda_host_alloc", error);
    }

    windows_error = query_available_physical_memory(
        &result.windows_available_physical_bytes_after_host_alloc);
    set_windows_failure(&result, "windows_memory_after_host_alloc", windows_error);
    error = query_vram(&result.cuda_free_vram_bytes_after_host_alloc,
                       &result.cuda_total_vram_bytes_after_host_alloc);
    set_cuda_failure(&result, "cuda_vram_after_host_alloc", error);
    if (!result.host_alloc_succeeded || error != cudaSuccess) {
        goto cleanup;
    }

    QueryPerformanceCounter(&start_time);
    {
        volatile unsigned char *bytes = (volatile unsigned char *)host_pointer;
        size_t offset = 0;
        for (;;) {
            bytes[offset] = (unsigned char)(((uint64_t)offset >> 12) ^ 0xa5U);
            ++result.pages_touched;
            if (arena_bytes - offset <= (size_t)result.page_size_bytes) {
                break;
            }
            offset += (size_t)result.page_size_bytes;
        }
    }
    QueryPerformanceCounter(&end_time);
    result.touch_seconds = elapsed_seconds(start_time, end_time, qpc_frequency);
    result.touch_succeeded = true;

    windows_error = query_available_physical_memory(
        &result.windows_available_physical_bytes_after_touch);
    set_windows_failure(&result, "windows_memory_after_touch", windows_error);

    error = cudaMalloc(&device_pointer, device_buffer_bytes);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_device_buffer_alloc", error);
        goto cleanup;
    }
    error = query_vram(&result.cuda_free_vram_bytes_after_device_alloc,
                       &result.cuda_total_vram_bytes_after_device_alloc);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_vram_after_device_alloc", error);
        goto cleanup;
    }

    error = cudaStreamCreateWithFlags(&stream, cudaStreamNonBlocking);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_stream_create", error);
        goto cleanup;
    }
    error = cudaEventCreate(&start_event);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_start_event_create", error);
        goto cleanup;
    }
    error = cudaEventCreate(&stop_event);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_stop_event_create", error);
        goto cleanup;
    }

    error = cudaMemcpyAsync(device_pointer, host_pointer, device_buffer_bytes,
                            cudaMemcpyHostToDevice, stream);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_h2d_warmup", error);
        goto cleanup;
    }
    error = cudaStreamSynchronize(stream);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_h2d_warmup_sync", error);
        goto cleanup;
    }

    error = cudaEventRecord(start_event, stream);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_h2d_start_event", error);
        goto cleanup;
    }
    for (uint64_t iteration = 0; iteration < iterations; ++iteration) {
        size_t offset = 0;
        while (offset < arena_bytes) {
            size_t chunk_bytes = arena_bytes - offset;
            if (chunk_bytes > device_buffer_bytes) {
                chunk_bytes = device_buffer_bytes;
            }
            error = cudaMemcpyAsync(device_pointer,
                                    (const unsigned char *)host_pointer + offset,
                                    chunk_bytes, cudaMemcpyHostToDevice, stream);
            if (error != cudaSuccess) {
                set_cuda_failure(&result, "cuda_h2d_copy", error);
                goto cleanup;
            }
            offset += chunk_bytes;
        }
    }
    error = cudaEventRecord(stop_event, stream);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_h2d_stop_event", error);
        goto cleanup;
    }
    error = cudaEventSynchronize(stop_event);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_h2d_stop_sync", error);
        goto cleanup;
    }
    error = cudaEventElapsedTime(&elapsed_milliseconds, start_event, stop_event);
    if (error != cudaSuccess) {
        set_cuda_failure(&result, "cuda_h2d_elapsed_time", error);
        goto cleanup;
    }
    if (elapsed_milliseconds <= 0.0f) {
        set_argument_failure(&result, "cuda_h2d_elapsed_time",
                             "CUDA reported a non-positive elapsed time.");
        goto cleanup;
    }

    result.h2d_seconds = (double)elapsed_milliseconds / 1000.0;
    result.h2d_gbps = (double)result.h2d_bytes / result.h2d_seconds / 1.0e9;
    result.h2d_gib_per_second =
        (double)result.h2d_bytes / result.h2d_seconds / (double)kGiB;
    result.h2d_succeeded = true;

    windows_error = query_available_physical_memory(
        &result.windows_available_physical_bytes_after_bandwidth);
    set_windows_failure(&result, "windows_memory_after_bandwidth", windows_error);
    error = query_vram(&result.cuda_free_vram_bytes_after_bandwidth,
                       &result.cuda_total_vram_bytes_after_bandwidth);
    set_cuda_failure(&result, "cuda_vram_after_bandwidth", error);

cleanup:
    if (stream != NULL) {
        error = cudaStreamSynchronize(stream);
        set_cuda_failure(&result, "cuda_stream_cleanup_sync", error);
    }
    if (stop_event != NULL) {
        error = cudaEventDestroy(stop_event);
        set_cuda_failure(&result, "cuda_stop_event_destroy", error);
    }
    if (start_event != NULL) {
        error = cudaEventDestroy(start_event);
        set_cuda_failure(&result, "cuda_start_event_destroy", error);
    }
    if (stream != NULL) {
        error = cudaStreamDestroy(stream);
        set_cuda_failure(&result, "cuda_stream_destroy", error);
    }
    if (device_pointer != NULL) {
        error = cudaFree(device_pointer);
        set_cuda_failure(&result, "cuda_device_buffer_free", error);
    }
    if (host_pointer != NULL) {
        error = cudaFreeHost(host_pointer);
        set_cuda_failure(&result, "cuda_host_free", error);
    }

    windows_error = query_available_physical_memory(
        &result.windows_available_physical_bytes_after_cleanup);
    set_windows_failure(&result, "windows_memory_after_cleanup", windows_error);
    if (cuda_context_ready) {
        error = query_vram(&result.cuda_free_vram_bytes_after_cleanup,
                           &result.cuda_total_vram_bytes_after_cleanup);
        set_cuda_failure(&result, "cuda_vram_after_cleanup", error);
    }
    if (cuda_device_selected) {
        error = cudaDeviceReset();
        set_cuda_failure(&result, "cuda_device_reset", error);
    }

    result.success = result.failure_stage == NULL && result.host_alloc_succeeded &&
                     result.touch_succeeded && result.h2d_succeeded;
    print_result(&result);
    return result.success ? 0 : 1;
}

int main(int argc, char **argv) {
    uint64_t arena_gib = 0;
    uint64_t device_buffer_mib = 256;
    uint64_t iterations = 1;

    if (argc < 2 || argc > 4 || !parse_positive_uint64(argv[1], &arena_gib) ||
        (argc >= 3 && !parse_positive_uint64(argv[2], &device_buffer_mib)) ||
        (argc >= 4 && !parse_positive_uint64(argv[3], &iterations))) {
        ProbeResult result;
        initialize_result(&result);
        set_argument_failure(
            &result, "command_line",
            "Usage: g17_arena_probe.exe <arena-gib> [device-buffer-mib] [iterations]");
        print_result(&result);
        return 2;
    }

    return run_probe(arena_gib, device_buffer_mib, iterations);
}
