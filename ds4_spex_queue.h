#ifndef DS4_SPEX_QUEUE_H
#define DS4_SPEX_QUEUE_H

#include <stdint.h>

typedef struct ds4_gpu_spex_queue ds4_gpu_spex_queue;

#define DS4_GPU_SPEX_MAX_EXPERTS 6u

typedef struct {
    uint64_t epoch;
    uint64_t decode_seq;
    uint32_t source_layer;
    uint32_t target_layer;
} ds4_gpu_spex_key;

typedef struct {
    ds4_gpu_spex_key key;
    uint64_t gate_offset;
    uint64_t up_offset;
    uint64_t down_offset;
    uint32_t expert_count;
    uint32_t expert_ids[DS4_GPU_SPEX_MAX_EXPERTS];
} ds4_gpu_spex_job;

#ifdef DS4_TESTING
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t requested;
    uint64_t attempts;
    uint64_t successes;
    uint64_t failures;
    uint64_t stale;
    uint64_t dropped;
    uint64_t structural_rejects;
    uint64_t bytes_read;
    uint64_t promotion_request_used;
    uint64_t promotion_window_used;
    uint64_t promotion_failures;
    uint64_t tiering_failures;
    int failed;
    int ok;
} ds4_gpu_ssdwrap_test_result;

int ds4_gpu_ssdwrap_test_happy(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_stale_age(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_epoch_mismatch(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_victim_stale(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_destination_stale(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_pread_failure(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_provenance_mismatch(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_checksum_mismatch(ds4_gpu_ssdwrap_test_result *out);
int ds4_gpu_ssdwrap_test_pairing_break(ds4_gpu_ssdwrap_test_result *out);

#ifdef __cplusplus
}
#endif
#endif

#endif
