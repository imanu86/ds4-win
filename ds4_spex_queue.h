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

#endif
