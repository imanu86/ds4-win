#include "ds4.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2 || argc > 4) {
        fprintf(stderr, "usage: ds4_moe_gate_bench MODEL [TEXT] [REPEATS]\n");
        return 2;
    }

    ds4_engine_options opt = {
        .model_path = argv[1],
        .backend = DS4_BACKEND_CUDA,
        .mtp_draft_tokens = 1,
        .mtp_margin = 3.0f,
    };
    ds4_engine *engine = NULL;
    if (ds4_engine_open(&engine, &opt) != 0) return 1;

    ds4_tokens prompt = {0};
    ds4_tokenize_text(engine, argc >= 3 ? argv[2] : "Hi", &prompt);
    uint32_t repeats = 1;
    if (argc == 4) {
        char *end = NULL;
        const unsigned long value = strtoul(argv[3], &end, 10);
        if (end == argv[3] || *end != '\0' || value == 0 || value > 1000) {
            fprintf(stderr, "invalid repeats: %s\n", argv[3]);
            ds4_tokens_free(&prompt);
            ds4_engine_close(engine);
            return 2;
        }
        repeats = (uint32_t)value;
    }
    int rc = 0;
    for (uint32_t i = 0; i < repeats && rc == 0; i++) {
        fprintf(stderr, "ds4: MoE gate benchmark pass=%u/%u\n", i + 1, repeats);
        rc = ds4_engine_metal_graph_test(engine, &prompt);
    }
    ds4_tokens_free(&prompt);
    ds4_engine_close(engine);
    return rc;
}
