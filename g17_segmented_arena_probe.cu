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
static const size_t kDeviceBufferBytes = 256ULL * 1024ULL * 1024ULL;
static const uint64_t kMaximumSegmentCount = 65536ULL;

static_assert(sizeof(size_t) == 8,
              "g17_segmented_arena_probe requires a 64-bit process");

struct MemorySnapshot {
    bool captured;
    bool windows_succeeded;
    DWORD windows_error;
    uint64_t windows_available_bytes;
    bool cuda_attempted;
    bool cuda_succeeded;
    cudaError_t cuda_error;
    uint64_t cuda_free_vram_bytes;
    uint64_t cuda_total_vram_bytes;
};

struct TimedCudaOperation {
    bool attempted;
    bool succeeded;
    double seconds;
    cudaError_t error;
};

struct SegmentResult {
    uint64_t index;
    uint64_t bytes;
    void *pointer;
    TimedCudaOperation allocation;
    MemorySnapshot after_allocation;
    bool touch_attempted;
    bool touch_succeeded;
    double touch_seconds;
    uint64_t pages_touched;
    MemorySnapshot after_touch;
    TimedCudaOperation h2d;
    uint64_t h2d_bytes;
    MemorySnapshot after_h2d;
    TimedCudaOperation release;
    uint64_t free_sequence;
    MemorySnapshot after_free;
};

struct ProbeResult {
    char timestamp_utc[32];
    DWORD process_id;
    bool success;
    bool operations_succeeded;
    bool all_live_segments_free_attempted;
    bool all_live_segments_freed;

    const char *failure_kind;
    char failure_stage[128];
    char failure_detail[256];
    cudaError_t failure_cuda_error;
    DWORD failure_windows_error;

    uint64_t total_gib;
    uint64_t total_bytes;
    const char *segmentation_mode;
    uint64_t requested_segment_gib;
    uint64_t requested_segment_count;
    uint64_t segment_gib;
    uint64_t segment_bytes;
    uint64_t segment_count;
    uint64_t page_size_bytes;
    uint64_t total_pages_touched;
    uint64_t total_h2d_bytes;

    int cuda_device_ordinal;
    char cuda_device_name[256];
    int cuda_runtime_version;
    int cuda_driver_version;
    bool device_buffer_allocation_succeeded;
    cudaError_t device_buffer_allocation_error;

    MemorySnapshot before;
    MemorySnapshot after_device_buffer_allocation;
    MemorySnapshot after_cleanup;

    bool cuda_device_reset_attempted;
    bool cuda_device_reset_succeeded;
    cudaError_t cuda_device_reset_error;

    SegmentResult *segments;
};

static void initialize_result(ProbeResult *result) {
    memset(result, 0, sizeof(*result));
    SYSTEMTIME now;
    GetSystemTime(&now);
    _snprintf_s(result->timestamp_utc, sizeof(result->timestamp_utc), _TRUNCATE,
                "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", now.wYear,
                now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
                now.wMilliseconds);
    result->process_id = GetCurrentProcessId();
    result->failure_kind = "none";
    result->failure_cuda_error = cudaSuccess;
    result->device_buffer_allocation_error = cudaSuccess;
    result->cuda_device_reset_error = cudaSuccess;
    result->cuda_device_ordinal = 0;
    result->all_live_segments_free_attempted = true;
    result->all_live_segments_freed = true;
}

static bool has_failure(const ProbeResult *result) {
    return result->failure_stage[0] != '\0';
}

static void copy_text(char *destination, size_t destination_size,
                      const char *source) {
    strncpy_s(destination, destination_size, source, _TRUNCATE);
}

static void set_argument_failure(ProbeResult *result, const char *stage,
                                 const char *detail) {
    if (!has_failure(result)) {
        result->failure_kind = "argument";
        copy_text(result->failure_stage, sizeof(result->failure_stage), stage);
        copy_text(result->failure_detail, sizeof(result->failure_detail), detail);
    }
}

static void set_system_failure(ProbeResult *result, const char *stage,
                               const char *detail) {
    if (!has_failure(result)) {
        result->failure_kind = "system";
        copy_text(result->failure_stage, sizeof(result->failure_stage), stage);
        copy_text(result->failure_detail, sizeof(result->failure_detail), detail);
    }
}

static void set_cuda_failure(ProbeResult *result, const char *stage,
                             cudaError_t error) {
    if (error != cudaSuccess && !has_failure(result)) {
        result->failure_kind = "cuda";
        copy_text(result->failure_stage, sizeof(result->failure_stage), stage);
        result->failure_cuda_error = error;
    }
}

static void set_windows_failure(ProbeResult *result, const char *stage,
                                DWORD error) {
    if (error != ERROR_SUCCESS && !has_failure(result)) {
        result->failure_kind = "windows";
        copy_text(result->failure_stage, sizeof(result->failure_stage), stage);
        result->failure_windows_error = error;
    }
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
    return (double)(end.QuadPart - start.QuadPart) /
           (double)frequency.QuadPart;
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
    if (value == NULL || value[0] == '\0') {
        fputs("null", stdout);
    } else {
        print_json_string(value);
    }
}

static void windows_error_message(DWORD error, char *buffer,
                                  size_t buffer_size) {
    if (error == ERROR_SUCCESS) {
        _snprintf_s(buffer, buffer_size, _TRUNCATE,
                    "The operation completed successfully.");
        return;
    }

    DWORD length = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
                                      FORMAT_MESSAGE_IGNORE_INSERTS,
                                  NULL, error, 0, buffer, (DWORD)buffer_size,
                                  NULL);
    if (length == 0) {
        _snprintf_s(buffer, buffer_size, _TRUNCATE, "Windows error %lu",
                    (unsigned long)error);
        return;
    }
    while (length > 0 &&
           (buffer[length - 1] == '\r' || buffer[length - 1] == '\n')) {
        buffer[--length] = '\0';
    }
}

static void initialize_snapshot(MemorySnapshot *snapshot) {
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->cuda_error = cudaSuccess;
}

static void capture_snapshot(MemorySnapshot *snapshot, bool query_cuda) {
    initialize_snapshot(snapshot);
    snapshot->captured = true;

    MEMORYSTATUSEX status;
    memset(&status, 0, sizeof(status));
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status)) {
        snapshot->windows_succeeded = true;
        snapshot->windows_available_bytes =
            (uint64_t)status.ullAvailPhys;
    } else {
        snapshot->windows_error = GetLastError();
    }

    snapshot->cuda_attempted = query_cuda;
    if (query_cuda) {
        size_t free_bytes = 0;
        size_t total_bytes = 0;
        snapshot->cuda_error = cudaMemGetInfo(&free_bytes, &total_bytes);
        if (snapshot->cuda_error == cudaSuccess) {
            snapshot->cuda_succeeded = true;
            snapshot->cuda_free_vram_bytes = (uint64_t)free_bytes;
            snapshot->cuda_total_vram_bytes = (uint64_t)total_bytes;
        }
    }
}

static void note_snapshot_failure(ProbeResult *result, const char *stage,
                                  const MemorySnapshot *snapshot) {
    char full_stage[128];
    if (!snapshot->windows_succeeded) {
        _snprintf_s(full_stage, sizeof(full_stage), _TRUNCATE, "%s_windows",
                    stage);
        set_windows_failure(result, full_stage, snapshot->windows_error);
    }
    if (snapshot->cuda_attempted && !snapshot->cuda_succeeded) {
        _snprintf_s(full_stage, sizeof(full_stage), _TRUNCATE, "%s_cuda",
                    stage);
        set_cuda_failure(result, full_stage, snapshot->cuda_error);
    }
}

static void make_segment_stage(char *buffer, size_t buffer_size,
                               uint64_t index, const char *operation) {
    _snprintf_s(buffer, buffer_size, _TRUNCATE, "segment_%llu_%s",
                (unsigned long long)index, operation);
}

static void print_snapshot(const MemorySnapshot *snapshot) {
    printf("{\"captured\":%s,\"windows_succeeded\":%s,"
           "\"windows_error_code\":%lu,\"windows_available_bytes\":%llu,"
           "\"cuda_attempted\":%s,\"cuda_succeeded\":%s,"
           "\"cuda_error_code\":%d,\"cuda_error_name\":",
           snapshot->captured ? "true" : "false",
           snapshot->windows_succeeded ? "true" : "false",
           (unsigned long)snapshot->windows_error,
           (unsigned long long)snapshot->windows_available_bytes,
           snapshot->cuda_attempted ? "true" : "false",
           snapshot->cuda_succeeded ? "true" : "false",
           (int)snapshot->cuda_error);
    print_json_string(cudaGetErrorName(snapshot->cuda_error));
    printf(",\"cuda_free_vram_bytes\":%llu,\"cuda_total_vram_bytes\":%llu}",
           (unsigned long long)snapshot->cuda_free_vram_bytes,
           (unsigned long long)snapshot->cuda_total_vram_bytes);
}

static void print_timed_cuda_operation(const TimedCudaOperation *operation) {
    printf("{\"attempted\":%s,\"succeeded\":%s,\"seconds\":%.9f,"
           "\"cuda_error_code\":%d,\"cuda_error_name\":",
           operation->attempted ? "true" : "false",
           operation->succeeded ? "true" : "false", operation->seconds,
           (int)operation->error);
    print_json_string(cudaGetErrorName(operation->error));
    putchar('}');
}

static void print_segment(const SegmentResult *segment) {
    printf("{\"index\":%llu,\"bytes\":%llu,\"allocation\":",
           (unsigned long long)segment->index,
           (unsigned long long)segment->bytes);
    print_timed_cuda_operation(&segment->allocation);
    fputs(",\"after_allocation\":", stdout);
    print_snapshot(&segment->after_allocation);
    printf(",\"touch\":{\"attempted\":%s,\"succeeded\":%s,"
           "\"seconds\":%.9f,\"pages_touched\":%llu},\"after_touch\":",
           segment->touch_attempted ? "true" : "false",
           segment->touch_succeeded ? "true" : "false",
           segment->touch_seconds,
           (unsigned long long)segment->pages_touched);
    print_snapshot(&segment->after_touch);
    fputs(",\"h2d\":", stdout);
    print_timed_cuda_operation(&segment->h2d);
    printf(",\"h2d_bytes\":%llu,\"after_h2d\":",
           (unsigned long long)segment->h2d_bytes);
    print_snapshot(&segment->after_h2d);
    fputs(",\"free\":", stdout);
    print_timed_cuda_operation(&segment->release);
    printf(",\"free_sequence\":%llu,\"after_free\":",
           (unsigned long long)segment->free_sequence);
    print_snapshot(&segment->after_free);
    putchar('}');
}

static const char *failure_message(const ProbeResult *result,
                                   char *windows_buffer,
                                   size_t windows_buffer_size) {
    if (strcmp(result->failure_kind, "cuda") == 0) {
        return cudaGetErrorString(result->failure_cuda_error);
    }
    if (strcmp(result->failure_kind, "windows") == 0) {
        windows_error_message(result->failure_windows_error, windows_buffer,
                              windows_buffer_size);
        return windows_buffer;
    }
    if (result->failure_detail[0] != '\0') {
        return result->failure_detail;
    }
    return NULL;
}

static void print_result(const ProbeResult *result) {
    char windows_buffer[512];
    const char *message =
        failure_message(result, windows_buffer, sizeof(windows_buffer));

    fputs("{\"schema\":\"g17_segmented_arena_probe_v1\","
          "\"timestamp_utc\":",
          stdout);
    print_json_string(result->timestamp_utc);
    printf(",\"process_id\":%lu,\"success\":%s,\"failure_kind\":",
           (unsigned long)result->process_id,
           result->success ? "true" : "false");
    print_json_string(result->failure_kind);
    fputs(",\"failure_stage\":", stdout);
    print_nullable_json_string(result->failure_stage);
    fputs(",\"failure_message\":", stdout);
    print_nullable_json_string(message);
    printf(",\"failure_cuda_error_code\":%d,"
           "\"failure_cuda_error_name\":",
           (int)result->failure_cuda_error);
    print_json_string(cudaGetErrorName(result->failure_cuda_error));
    printf(",\"failure_windows_error_code\":%lu,"
           "\"operations_succeeded\":%s,"
           "\"all_live_segments_free_attempted\":%s,"
           "\"all_live_segments_freed\":%s",
           (unsigned long)result->failure_windows_error,
           result->operations_succeeded ? "true" : "false",
           result->all_live_segments_free_attempted ? "true" : "false",
           result->all_live_segments_freed ? "true" : "false");

    printf(",\"requested_total_gib\":%llu,\"total_bytes\":%llu,"
           "\"segmentation_mode\":",
           (unsigned long long)result->total_gib,
           (unsigned long long)result->total_bytes);
    print_nullable_json_string(result->segmentation_mode);
    printf(",\"requested_segment_gib\":%llu,"
           "\"requested_segment_count\":%llu,\"segment_gib\":%llu,"
           "\"segment_bytes\":%llu,\"segment_count\":%llu,"
           "\"page_size_bytes\":%llu,\"total_pages_touched\":%llu,"
           "\"total_h2d_bytes\":%llu,"
           "\"host_allocation_flags\":\"cudaHostAllocDefault\","
           "\"mapped_host_pointer_requested\":false,"
           "\"device_buffer_bytes\":%llu",
           (unsigned long long)result->requested_segment_gib,
           (unsigned long long)result->requested_segment_count,
           (unsigned long long)result->segment_gib,
           (unsigned long long)result->segment_bytes,
           (unsigned long long)result->segment_count,
           (unsigned long long)result->page_size_bytes,
           (unsigned long long)result->total_pages_touched,
           (unsigned long long)result->total_h2d_bytes,
           (unsigned long long)kDeviceBufferBytes);

    printf(",\"cuda_device_ordinal\":%d,\"cuda_device_name\":",
           result->cuda_device_ordinal);
    print_json_string(result->cuda_device_name);
    printf(",\"cuda_runtime_version\":%d,\"cuda_driver_version\":%d,"
           "\"device_buffer_allocation_succeeded\":%s,"
           "\"device_buffer_allocation_error_code\":%d,"
           "\"device_buffer_allocation_error_name\":",
           result->cuda_runtime_version, result->cuda_driver_version,
           result->device_buffer_allocation_succeeded ? "true" : "false",
           (int)result->device_buffer_allocation_error);
    print_json_string(cudaGetErrorName(result->device_buffer_allocation_error));

    fputs(",\"memory_before\":", stdout);
    print_snapshot(&result->before);
    fputs(",\"memory_after_device_buffer_allocation\":", stdout);
    print_snapshot(&result->after_device_buffer_allocation);
    fputs(",\"memory_after_cleanup\":", stdout);
    print_snapshot(&result->after_cleanup);

    printf(",\"cuda_device_reset\":{\"attempted\":%s,"
           "\"succeeded\":%s,\"cuda_error_code\":%d,"
           "\"cuda_error_name\":",
           result->cuda_device_reset_attempted ? "true" : "false",
           result->cuda_device_reset_succeeded ? "true" : "false",
           (int)result->cuda_device_reset_error);
    print_json_string(cudaGetErrorName(result->cuda_device_reset_error));
    fputs("},\"segments\":[", stdout);
    for (uint64_t index = 0;
         result->segments != NULL && index < result->segment_count; ++index) {
        if (index != 0) {
            putchar(',');
        }
        print_segment(&result->segments[index]);
    }
    fputs("]}\n", stdout);
    fflush(stdout);
}

static void initialize_operation(TimedCudaOperation *operation) {
    memset(operation, 0, sizeof(*operation));
    operation->error = cudaSuccess;
}

static void initialize_segments(ProbeResult *result) {
    for (uint64_t index = 0; index < result->segment_count; ++index) {
        SegmentResult *segment = &result->segments[index];
        segment->index = index;
        segment->bytes = result->segment_bytes;
        initialize_operation(&segment->allocation);
        initialize_operation(&segment->h2d);
        initialize_operation(&segment->release);
        initialize_snapshot(&segment->after_allocation);
        initialize_snapshot(&segment->after_touch);
        initialize_snapshot(&segment->after_h2d);
        initialize_snapshot(&segment->after_free);
    }
}

static bool resolve_configuration(ProbeResult *result, uint64_t total_gib,
                                  const char *mode, uint64_t mode_value) {
    result->total_gib = total_gib;
    result->segmentation_mode = mode;

    if (total_gib > (uint64_t)SIZE_MAX / kGiB) {
        set_argument_failure(result, "total_size",
                             "Total GiB overflows the 64-bit address space.");
        return false;
    }

    if (strcmp(mode, "segment_gib") == 0) {
        result->requested_segment_gib = mode_value;
        if (mode_value > total_gib || total_gib % mode_value != 0) {
            set_argument_failure(
                result, "segmentation",
                "Total GiB must be exactly divisible by segment GiB.");
            return false;
        }
        result->segment_gib = mode_value;
        result->segment_count = total_gib / mode_value;
    } else {
        result->requested_segment_count = mode_value;
        if (mode_value > total_gib || total_gib % mode_value != 0) {
            set_argument_failure(
                result, "segmentation",
                "Segment count must exactly divide total GiB into whole-GiB segments.");
            return false;
        }
        result->segment_count = mode_value;
        result->segment_gib = total_gib / mode_value;
    }

    if (result->segment_count == 0 ||
        result->segment_count > kMaximumSegmentCount) {
        set_argument_failure(result, "segment_count",
                             "Resolved segment count is outside the supported range.");
        return false;
    }
    if (result->segment_count >
        (uint64_t)SIZE_MAX / sizeof(SegmentResult)) {
        set_argument_failure(result, "segment_metadata",
                             "Segment metadata size overflows size_t.");
        return false;
    }

    result->total_bytes = total_gib * kGiB;
    result->segment_bytes = result->segment_gib * kGiB;
    return true;
}

static void reset_cuda_device(ProbeResult *result) {
    result->cuda_device_reset_attempted = true;
    result->cuda_device_reset_error = cudaDeviceReset();
    result->cuda_device_reset_succeeded =
        result->cuda_device_reset_error == cudaSuccess;
    set_cuda_failure(result, "cuda_device_reset",
                     result->cuda_device_reset_error);
}

static int run_probe(ProbeResult *result) {
    void *device_pointer = NULL;
    bool cuda_context_ready = false;
    LARGE_INTEGER qpc_frequency;
    LARGE_INTEGER start_time;
    LARGE_INTEGER end_time;
    SYSTEM_INFO system_info;
    cudaDeviceProp device_properties;
    cudaError_t error = cudaSuccess;
    char stage[128];
    uint64_t free_sequence = 0;

    if (!QueryPerformanceFrequency(&qpc_frequency) ||
        qpc_frequency.QuadPart <= 0) {
        set_system_failure(result, "performance_counter",
                           "QueryPerformanceFrequency failed.");
        goto cleanup;
    }

    GetSystemInfo(&system_info);
    result->page_size_bytes = (uint64_t)system_info.dwPageSize;
    if (result->page_size_bytes == 0) {
        set_system_failure(result, "page_size",
                           "Windows reported a zero-byte page size.");
        goto cleanup;
    }

    result->segments = (SegmentResult *)calloc(
        (size_t)result->segment_count, sizeof(SegmentResult));
    if (result->segments == NULL) {
        set_system_failure(result, "segment_metadata",
                           "Unable to allocate segment metadata.");
        goto cleanup;
    }
    initialize_segments(result);

    error = cudaSetDevice(result->cuda_device_ordinal);
    if (error != cudaSuccess) {
        set_cuda_failure(result, "cuda_set_device", error);
        goto cleanup;
    }
    error = cudaFree(NULL);
    if (error != cudaSuccess) {
        set_cuda_failure(result, "cuda_context_initialization", error);
        goto cleanup;
    }
    cuda_context_ready = true;

    memset(&device_properties, 0, sizeof(device_properties));
    error = cudaGetDeviceProperties(&device_properties,
                                    result->cuda_device_ordinal);
    if (error != cudaSuccess) {
        set_cuda_failure(result, "cuda_device_properties", error);
        goto cleanup;
    }
    copy_text(result->cuda_device_name, sizeof(result->cuda_device_name),
              device_properties.name);

    error = cudaRuntimeGetVersion(&result->cuda_runtime_version);
    if (error != cudaSuccess) {
        set_cuda_failure(result, "cuda_runtime_version", error);
        goto cleanup;
    }
    error = cudaDriverGetVersion(&result->cuda_driver_version);
    if (error != cudaSuccess) {
        set_cuda_failure(result, "cuda_driver_version", error);
        goto cleanup;
    }

    capture_snapshot(&result->before, true);
    note_snapshot_failure(result, "memory_before", &result->before);
    if (has_failure(result)) {
        goto cleanup;
    }

    result->device_buffer_allocation_error =
        cudaMalloc(&device_pointer, kDeviceBufferBytes);
    result->device_buffer_allocation_succeeded =
        result->device_buffer_allocation_error == cudaSuccess;
    set_cuda_failure(result, "cuda_device_buffer_alloc",
                     result->device_buffer_allocation_error);
    capture_snapshot(&result->after_device_buffer_allocation, true);
    note_snapshot_failure(result, "memory_after_device_buffer_allocation",
                          &result->after_device_buffer_allocation);
    if (has_failure(result)) {
        goto cleanup;
    }

    for (uint64_t index = 0; index < result->segment_count; ++index) {
        SegmentResult *segment = &result->segments[index];
        segment->allocation.attempted = true;
        QueryPerformanceCounter(&start_time);
        segment->allocation.error = cudaHostAlloc(
            &segment->pointer, (size_t)segment->bytes, cudaHostAllocDefault);
        QueryPerformanceCounter(&end_time);
        segment->allocation.seconds =
            elapsed_seconds(start_time, end_time, qpc_frequency);
        segment->allocation.succeeded =
            segment->allocation.error == cudaSuccess;
        make_segment_stage(stage, sizeof(stage), index,
                           "cuda_host_alloc");
        set_cuda_failure(result, stage, segment->allocation.error);

        capture_snapshot(&segment->after_allocation, true);
        make_segment_stage(stage, sizeof(stage), index,
                           "after_allocation");
        note_snapshot_failure(result, stage, &segment->after_allocation);
        if (has_failure(result)) {
            goto cleanup;
        }

        segment->touch_attempted = true;
        QueryPerformanceCounter(&start_time);
        {
            volatile unsigned char *bytes =
                (volatile unsigned char *)segment->pointer;
            for (size_t offset = 0; offset < (size_t)segment->bytes;
                 offset += (size_t)result->page_size_bytes) {
                bytes[offset] = (unsigned char)(
                    ((uint64_t)offset >> 12) ^ index ^ 0xa5U);
                ++segment->pages_touched;
            }
        }
        QueryPerformanceCounter(&end_time);
        segment->touch_seconds =
            elapsed_seconds(start_time, end_time, qpc_frequency);
        segment->touch_succeeded = true;
        result->total_pages_touched += segment->pages_touched;

        capture_snapshot(&segment->after_touch, true);
        make_segment_stage(stage, sizeof(stage), index, "after_touch");
        note_snapshot_failure(result, stage, &segment->after_touch);
        if (has_failure(result)) {
            goto cleanup;
        }
    }

    for (uint64_t index = 0; index < result->segment_count; ++index) {
        SegmentResult *segment = &result->segments[index];
        segment->h2d.attempted = true;
        QueryPerformanceCounter(&start_time);
        for (size_t offset = 0; offset < (size_t)segment->bytes;) {
            size_t chunk_bytes = (size_t)segment->bytes - offset;
            if (chunk_bytes > kDeviceBufferBytes) {
                chunk_bytes = kDeviceBufferBytes;
            }
            segment->h2d.error = cudaMemcpy(
                device_pointer, (const unsigned char *)segment->pointer + offset,
                chunk_bytes, cudaMemcpyHostToDevice);
            if (segment->h2d.error != cudaSuccess) {
                break;
            }
            segment->h2d_bytes += (uint64_t)chunk_bytes;
            result->total_h2d_bytes += (uint64_t)chunk_bytes;
            offset += chunk_bytes;
        }
        QueryPerformanceCounter(&end_time);
        segment->h2d.seconds =
            elapsed_seconds(start_time, end_time, qpc_frequency);
        segment->h2d.succeeded =
            segment->h2d.error == cudaSuccess &&
            segment->h2d_bytes == segment->bytes;
        if (!segment->h2d.succeeded &&
            segment->h2d.error == cudaSuccess) {
            segment->h2d.error = cudaErrorUnknown;
        }
        make_segment_stage(stage, sizeof(stage), index, "cuda_h2d");
        set_cuda_failure(result, stage, segment->h2d.error);

        capture_snapshot(&segment->after_h2d, true);
        make_segment_stage(stage, sizeof(stage), index, "after_h2d");
        note_snapshot_failure(result, stage, &segment->after_h2d);
        if (has_failure(result)) {
            goto cleanup;
        }
    }

    result->operations_succeeded = true;

cleanup:
    if (result->segments != NULL) {
        for (uint64_t remaining = result->segment_count; remaining > 0;
             --remaining) {
            SegmentResult *segment = &result->segments[remaining - 1];
            if (segment->pointer == NULL) {
                continue;
            }
            segment->release.attempted = true;
            segment->free_sequence = ++free_sequence;
            QueryPerformanceCounter(&start_time);
            segment->release.error = cudaFreeHost(segment->pointer);
            QueryPerformanceCounter(&end_time);
            segment->release.seconds =
                elapsed_seconds(start_time, end_time, qpc_frequency);
            segment->release.succeeded =
                segment->release.error == cudaSuccess;
            segment->pointer = NULL;
            if (!segment->release.succeeded) {
                result->all_live_segments_freed = false;
            }
            make_segment_stage(stage, sizeof(stage), segment->index,
                               "cuda_host_free");
            set_cuda_failure(result, stage, segment->release.error);

            capture_snapshot(&segment->after_free, cuda_context_ready);
            make_segment_stage(stage, sizeof(stage), segment->index,
                               "after_free");
            note_snapshot_failure(result, stage, &segment->after_free);
        }

        for (uint64_t index = 0; index < result->segment_count; ++index) {
            const SegmentResult *segment = &result->segments[index];
            if (segment->allocation.succeeded &&
                !segment->release.attempted) {
                result->all_live_segments_free_attempted = false;
                result->all_live_segments_freed = false;
            }
        }
    }

    if (device_pointer != NULL) {
        error = cudaFree(device_pointer);
        set_cuda_failure(result, "cuda_device_buffer_free", error);
        device_pointer = NULL;
    }

    capture_snapshot(&result->after_cleanup, cuda_context_ready);
    note_snapshot_failure(result, "memory_after_cleanup",
                          &result->after_cleanup);
    reset_cuda_device(result);

    result->success = result->operations_succeeded &&
                      result->all_live_segments_free_attempted &&
                      result->all_live_segments_freed &&
                      result->cuda_device_reset_succeeded &&
                      !has_failure(result);
    print_result(result);
    free(result->segments);
    result->segments = NULL;
    return result->success ? 0 : 1;
}

static int print_command_line_failure(const char *detail) {
    ProbeResult result;
    initialize_result(&result);
    set_argument_failure(&result, "command_line", detail);
    reset_cuda_device(&result);
    print_result(&result);
    return 2;
}

int main(int argc, char **argv) {
    uint64_t total_gib = 0;
    uint64_t mode_value = 0;
    const char *mode = NULL;
    ProbeResult result;
    initialize_result(&result);

    if (argc != 4 || !parse_positive_uint64(argv[1], &total_gib) ||
        !parse_positive_uint64(argv[3], &mode_value)) {
        return print_command_line_failure(
            "Usage: g17_segmented_arena_probe.exe <total-gib> "
            "(--segment-gib <gib> | --segment-count <count>)");
    }
    if (strcmp(argv[2], "--segment-gib") == 0) {
        mode = "segment_gib";
    } else if (strcmp(argv[2], "--segment-count") == 0) {
        mode = "segment_count";
    } else {
        return print_command_line_failure(
            "Segmentation mode must be --segment-gib or --segment-count.");
    }

    if (!resolve_configuration(&result, total_gib, mode, mode_value)) {
        reset_cuda_device(&result);
        print_result(&result);
        return 2;
    }
    return run_probe(&result);
}
