#include "ds4_spex_predict.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ds4_spex_load(const char *path, ds4_spex_model *model) {
    if (!path || !path[0] || !model) return -1;
    memset(model, 0, sizeof(*model));

    FILE *file = fopen(path, "rb");
    if (!file) return -1;

    char magic[4];
    uint32_t header[7];
    if (fread(magic, 1, sizeof(magic), file) != sizeof(magic) ||
        memcmp(magic, "SPX1", sizeof(magic)) != 0) {
        fclose(file);
        return -2;
    }
    if (fread(header, sizeof(header[0]), 7, file) != 7) {
        fclose(file);
        return -3;
    }

    model->version = header[0];
    model->predictor = header[1];
    model->n_layer = header[2];
    model->n_embd = header[3];
    model->n_expert = header[4];
    memcpy(&model->ridge, &header[5], sizeof(model->ridge));
    model->reserved = header[6];
    if (model->version != 1 || model->predictor != 2 ||
        model->n_layer == 0 || model->n_embd == 0 || model->n_expert == 0) {
        fclose(file);
        memset(model, 0, sizeof(*model));
        return -4;
    }

    const size_t layer_elems = (size_t)model->n_embd * model->n_expert;
    if (layer_elems / model->n_expert != model->n_embd ||
        model->n_layer > SIZE_MAX / layer_elems) {
        fclose(file);
        memset(model, 0, sizeof(*model));
        return -5;
    }
    const size_t count = (size_t)model->n_layer * layer_elems;
    if (count > SIZE_MAX / sizeof(uint16_t)) {
        fclose(file);
        memset(model, 0, sizeof(*model));
        return -5;
    }

    uint16_t *weights = (uint16_t *)malloc(count * sizeof(*weights));
    if (!weights) {
        fclose(file);
        memset(model, 0, sizeof(*model));
        return -6;
    }
    if (fread(weights, sizeof(*weights), count, file) != count) {
        free(weights);
        fclose(file);
        memset(model, 0, sizeof(*model));
        return -7;
    }
    fclose(file);
    model->weights = weights;
    model->owned = weights;
    return 0;
}

void ds4_spex_free(ds4_spex_model *model) {
    if (!model) return;
    free(model->owned);
    memset(model, 0, sizeof(*model));
}
