#include "ds4.h"

#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ds4_inspect MODEL.gguf\n");
        return 2;
    }

    const ds4_engine_options options = {
        .model_path = argv[1],
        .backend = DS4_BACKEND_CPU,
    };
    ds4_engine *engine = NULL;
    if (ds4_engine_open(&engine, &options) != 0) return 1;
    ds4_engine_summary(engine);
    ds4_engine_close(engine);
    return 0;
}
