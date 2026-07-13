#ifndef DS4_SPEX_PREDICT_H
#define DS4_SPEX_PREDICT_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t version;
    uint32_t predictor;
    uint32_t n_layer;
    uint32_t n_embd;
    uint32_t n_expert;
    uint32_t reserved;
    float ridge;
    const uint16_t *weights;
    void *owned;
} ds4_spex_model;

/* Load an SPX1 hidden-to-next-layer predictor. Returns zero on success. */
int ds4_spex_load(const char *path, ds4_spex_model *model);
void ds4_spex_free(ds4_spex_model *model);

#endif
