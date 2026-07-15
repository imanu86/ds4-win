#ifndef DS4_BAKE_H
#define DS4_BAKE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DS4_BAKE_LAYERS 43u
#define DS4_BAKE_EXPERTS 256u
#define DS4_BAKE_MASK_LEN 1376u
#define DS4_BAKE_TENSOR_KINDS 3u

typedef enum ds4_bake_probe_result {
    DS4_BAKE_PROBE_NONE = 0,
    DS4_BAKE_PROBE_VALID = 1,
    DS4_BAKE_PROBE_INVALID = 2
} ds4_bake_probe_result;

typedef enum ds4_bake_tensor_kind {
    DS4_BAKE_TENSOR_GATE = 0,
    DS4_BAKE_TENSOR_UP = 1,
    DS4_BAKE_TENSOR_DOWN = 2
} ds4_bake_tensor_kind;

typedef struct ds4_bake_tensor_record {
    char name[64];
    uint32_t tensor_type;
    uint32_t layer;
    ds4_bake_tensor_kind kind;
    uint64_t offset;
    uint64_t bytes;
    uint64_t slice_bytes;
    uint32_t selected_count;
} ds4_bake_tensor_record;

typedef struct ds4_bake_meta {
    uint64_t mapped_size;
    uint64_t source_size;
    uint64_t manifest_len;
    uint32_t manifest_crc32;
    uint32_t mask_crc32;
    int source_model_sha256_present;
    /* Empty when source_model_sha256 is null in the manifest. */
    char source_model_sha256[65];
    char mask_sha256[65];
    uint8_t retained_mask[DS4_BAKE_MASK_LEN];
    uint16_t retained_count[DS4_BAKE_LAYERS];
    ds4_bake_tensor_record routed_tensors[DS4_BAKE_LAYERS][DS4_BAKE_TENSOR_KINDS];
} ds4_bake_meta;

ds4_bake_probe_result ds4_bake_probe(const void *map,
                                     uint64_t mapped_size,
                                     ds4_bake_meta *out,
                                     char *err,
                                     size_t err_cap);

int ds4_bake_expert_retained(const ds4_bake_meta *meta,
                             uint32_t layer,
                             uint32_t expert);

#ifdef __cplusplus
}
#endif

#endif
