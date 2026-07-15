#include "../ds4_bake.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__, #x); \
    return 1; \
} } while (0)

typedef struct strbuf {
    char *p;
    size_t n;
    size_t cap;
} strbuf;

typedef enum fixture_mode {
    FIX_VALID,
    FIX_MANIFEST_BAD_VERSION,
    FIX_MALFORMED_JSON,
    FIX_TOO_FEW,
    FIX_DUP_SELECTION,
    FIX_DUP_LAYER,
    FIX_OOR_SELECTION,
    FIX_MISSING_TENSOR,
    FIX_DUP_TENSOR,
    FIX_DUP_TENSOR_FIELD,
    FIX_DUP_TOP_KEY,
    FIX_OVERLONG_SHA,
    FIX_OVERLAP_EXTENTS,
    FIX_K60_SHAPE
} fixture_mode;

static int sb_init(strbuf *b, size_t cap) {
    b->p = (char *)malloc(cap);
    if (!b->p) return 0;
    b->n = 0;
    b->cap = cap;
    b->p[0] = '\0';
    return 1;
}

static int sb_add(strbuf *b, const char *fmt, ...) {
    va_list ap;
    int got;
    if (b->n >= b->cap) return 0;
    va_start(ap, fmt);
    got = vsnprintf(b->p + b->n, b->cap - b->n, fmt, ap);
    va_end(ap);
    if (got < 0 || (size_t)got >= b->cap - b->n) return 0;
    b->n += (size_t)got;
    return 1;
}

static uint32_t crc32_ieee_test(const unsigned char *p, size_t n) {
    uint32_t crc = 0xffffffffu;
    for (size_t i = 0; i < n; i++) {
        crc ^= p[i];
        for (int b = 0; b < 8; b++) crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return crc ^ 0xffffffffu;
}

static void wr32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)v;
    p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16);
    p[3] = (unsigned char)(v >> 24);
}

static void wr64(unsigned char *p, uint64_t v) {
    wr32(p, (uint32_t)v);
    wr32(p + 4, (uint32_t)(v >> 32));
}

static void set_mask_bit(unsigned char *m, uint32_t layer, uint32_t expert) {
    uint32_t bit = layer * DS4_BAKE_EXPERTS + expert;
    m[bit >> 3] = (unsigned char)(m[bit >> 3] | (unsigned char)(1u << (bit & 7u)));
}

static uint32_t layer_count(uint32_t layer, fixture_mode mode) {
    if (mode == FIX_TOO_FEW) return 5;
    if (mode == FIX_K60_SHAPE && layer >= 3) return 154;
    return 6;
}

static int append_selected(strbuf *j, fixture_mode mode) {
    if (!sb_add(j, "\"selected_experts_by_layer\":{")) return 0;
    if (mode == FIX_K60_SHAPE) {
        bool first = true;
        for (uint32_t layer = 3; layer < DS4_BAKE_LAYERS; layer++) {
            if (!sb_add(j, "%s\"%u\":[", first ? "" : ",", layer)) return 0;
            first = false;
            for (uint32_t e = 0; e < 154; e++) {
                if (!sb_add(j, "%s%u", e ? "," : "", e)) return 0;
            }
            if (!sb_add(j, "]")) return 0;
        }
    } else if (mode == FIX_OOR_SELECTION) {
        if (!sb_add(j, "\"43\":[0,1,2,3,4,5]")) return 0;
    } else if (mode == FIX_DUP_SELECTION) {
        if (!sb_add(j, "\"0\":[0,1,2,3,4,4]")) return 0;
    } else if (mode == FIX_DUP_LAYER) {
        if (!sb_add(j, "\"0\":[0,1,2,3,4,5],\"0\":[0,1,2,3,4,5]")) return 0;
    } else {
        uint32_t n = layer_count(0, mode);
        if (!sb_add(j, "\"0\":[")) return 0;
        for (uint32_t e = 0; e < n; e++) {
            if (!sb_add(j, "%s%u", e ? "," : "", e)) return 0;
        }
        if (!sb_add(j, "]")) return 0;
    }
    return sb_add(j, "}");
}

static const char *kind_name(uint32_t kind) {
    return kind == 0 ? "gate" : (kind == 1 ? "up" : "down");
}

static int append_tensor(strbuf *j, uint32_t layer, uint32_t kind, uint64_t offset,
                         uint32_t selected_count, fixture_mode mode) {
    const uint64_t slice = 16;
    const uint64_t bytes = slice * 256u;
    const char *k = kind_name(kind);
    return sb_add(j,
        "{\"name\":\"blk.%u.ffn_%s_exps.weight\",\"layer\":%u,\"kind\":\"%s\","
        "\"offset\":%llu,\"bytes\":%llu,\"slice_bytes\":%llu,"
        "\"tensor_type\":1,\"selected_count\":%u%s}",
        layer, k, layer, k,
        (unsigned long long)offset, (unsigned long long)bytes,
        (unsigned long long)slice, selected_count,
        mode == FIX_DUP_TENSOR_FIELD && layer == 0 && kind == 0 ?
            ",\"selected_count\":6" : "");
}

static int append_routed(strbuf *j, fixture_mode mode) {
    uint32_t emitted = 0;
    if (!sb_add(j, "\"routed_tensors\":[")) return 0;
    for (uint32_t l = 0; l < DS4_BAKE_LAYERS; l++) {
        for (uint32_t k = 0; k < DS4_BAKE_TENSOR_KINDS; k++) {
            uint32_t layer = l;
            uint32_t kind = k;
            if (mode == FIX_MISSING_TENSOR && l == 42 && k == DS4_BAKE_TENSOR_DOWN) continue;
            if (mode == FIX_DUP_TENSOR && l == 42 && k == DS4_BAKE_TENSOR_DOWN) {
                layer = 0;
                kind = DS4_BAKE_TENSOR_GATE;
            }
            if (emitted && !sb_add(j, ",")) return 0;
            uint32_t selected = mode == FIX_K60_SHAPE
                ? (layer < 3 ? 256u : 154u)
                : (layer == 0 ? layer_count(0, mode) : 256u);
            if (!append_tensor(j, layer, kind, 4096ull + (uint64_t)emitted * 4096ull,
                               selected, mode)) return 0;
            emitted++;
        }
    }
    return sb_add(j, "]");
}

static unsigned char *build_fixture(fixture_mode mode, size_t *out_len) {
    const uint64_t source_size = 1024ull * 1024ull;
    strbuf j;
    unsigned char mask[DS4_BAKE_MASK_LEN];
    unsigned char *buf;
    unsigned char *footer;
    size_t total;
    memset(mask, 0xff, sizeof(mask));
    if (mode == FIX_K60_SHAPE) {
        for (uint32_t layer = 3; layer < DS4_BAKE_LAYERS; layer++) {
            memset(mask + layer * 32u, 0, 32u);
            for (uint32_t e = 0; e < 154; e++) set_mask_bit(mask, layer, e);
        }
    } else {
        memset(mask, 0, 32);
        for (uint32_t e = 0; e < layer_count(0, mode); e++) set_mask_bit(mask, 0, e);
    }

    if (!sb_init(&j, 65536)) return NULL;
    if (!sb_add(&j,
        "{\"format\":\"ds4-windows-sparse-bake\",\"version\":%u,"
        "\"source_model_size\":%llu,\"source_model_sha256\":null,"
        "\"mask_sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef%s\"," 
        "\"payload_bytes\":%llu,\"extents\":%s,",
        mode == FIX_MANIFEST_BAD_VERSION ? 2u : 1u,
        (unsigned long long)source_size,
        mode == FIX_OVERLONG_SHA ? "f" : "",
        (unsigned long long)source_size,
        mode == FIX_OVERLAP_EXTENTS ? "[[0,600000],[500000,448576]]" : "[[0,1048576]]")) goto fail;
    if (mode == FIX_DUP_TOP_KEY && !sb_add(&j, "\"version\":1,")) goto fail;
    if (!append_selected(&j, mode)) goto fail;
    if (!sb_add(&j, ",")) goto fail;
    if (!append_routed(&j, mode)) goto fail;
    if (mode != FIX_MALFORMED_JSON) {
        if (!sb_add(&j, "}")) goto fail;
    }

    total = (size_t)source_size + j.n + DS4_BAKE_MASK_LEN + 56u;
    buf = (unsigned char *)calloc(1, total);
    if (!buf) goto fail;
    memcpy(buf + source_size, j.p, j.n);
    memcpy(buf + source_size + j.n, mask, sizeof(mask));
    footer = buf + total - 56u;
    memcpy(footer, "DS4BAKEFILEv1\0\0\0", 16);
    wr32(footer + 16, 1);
    wr32(footer + 20, DS4_BAKE_LAYERS);
    wr32(footer + 24, DS4_BAKE_EXPERTS);
    wr32(footer + 28, DS4_BAKE_MASK_LEN);
    wr64(footer + 32, source_size);
    wr64(footer + 40, (uint64_t)j.n);
    wr32(footer + 48, crc32_ieee_test((const unsigned char *)j.p, j.n));
    wr32(footer + 52, crc32_ieee_test(mask, sizeof(mask)));
    free(j.p);
    *out_len = total;
    return buf;
fail:
    free(j.p);
    return NULL;
}

static int expect_invalid(fixture_mode mode) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(mode, &n);
    CHECK(buf != NULL);
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_INVALID);
    CHECK(err[0] != '\0');
    free(buf);
    return 0;
}

static int test_ordinary(void) {
    char err[32];
    ds4_bake_meta meta;
    unsigned char buf[80];
    memset(buf, 0x5a, sizeof(buf));
    CHECK(ds4_bake_probe(buf, sizeof(buf), &meta, err, sizeof(err)) == DS4_BAKE_PROBE_NONE);
    return 0;
}

static int test_valid(void) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(FIX_VALID, &n);
    CHECK(buf != NULL);
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_VALID);
    CHECK(meta.mapped_size == (uint64_t)n);
    CHECK(meta.source_size == 1024ull * 1024ull);
    CHECK(meta.source_model_sha256_present == 0);
    CHECK(meta.source_model_sha256[0] == '\0');
    CHECK(meta.retained_count[0] == 6);
    CHECK(meta.retained_count[1] == 256);
    CHECK(ds4_bake_expert_retained(&meta, 0, 5) == 1);
    CHECK(ds4_bake_expert_retained(&meta, 0, 6) == 0);
    CHECK(strcmp(meta.routed_tensors[42][DS4_BAKE_TENSOR_DOWN].name, "blk.42.ffn_down_exps.weight") == 0);
    free(buf);
    return 0;
}

static int test_k60_shape(void) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(FIX_K60_SHAPE, &n);
    CHECK(buf != NULL);
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_VALID);
    CHECK(meta.retained_count[0] == 256);
    CHECK(meta.retained_count[2] == 256);
    CHECK(meta.retained_count[3] == 154);
    CHECK(meta.retained_count[42] == 154);
    CHECK(meta.routed_tensors[3][DS4_BAKE_TENSOR_GATE].selected_count == 154);
    CHECK(ds4_bake_expert_retained(&meta, 42, 153) == 1);
    CHECK(ds4_bake_expert_retained(&meta, 42, 154) == 0);
    free(buf);
    return 0;
}

static int test_bad_footer_version(void) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(FIX_VALID, &n);
    CHECK(buf != NULL);
    wr32(buf + n - 56u + 16u, 2);
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_INVALID);
    free(buf);
    return 0;
}

static int test_overflow(void) {
    unsigned char buf[56];
    char err[160];
    ds4_bake_meta meta;
    memset(buf, 0, sizeof(buf));
    memcpy(buf, "DS4BAKEFILEv1\0\0\0", 16);
    wr32(buf + 16, 1);
    wr32(buf + 20, DS4_BAKE_LAYERS);
    wr32(buf + 24, DS4_BAKE_EXPERTS);
    wr32(buf + 28, DS4_BAKE_MASK_LEN);
    wr64(buf + 32, UINT64_MAX);
    wr64(buf + 40, 1);
    CHECK(ds4_bake_probe(buf, sizeof(buf), &meta, err, sizeof(err)) == DS4_BAKE_PROBE_INVALID);
    return 0;
}

static int test_manifest_crc(void) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(FIX_VALID, &n);
    CHECK(buf != NULL);
    buf[1024u * 1024u] ^= 1u;
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_INVALID);
    free(buf);
    return 0;
}

static int test_mask_crc(void) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(FIX_VALID, &n);
    CHECK(buf != NULL);
    buf[n - 56u - DS4_BAKE_MASK_LEN] ^= 1u;
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_INVALID);
    free(buf);
    return 0;
}

static int test_bitset_mismatch(void) {
    size_t n = 0;
    char err[160];
    ds4_bake_meta meta;
    unsigned char *buf = build_fixture(FIX_VALID, &n);
    unsigned char *mask;
    CHECK(buf != NULL);
    mask = buf + n - 56u - DS4_BAKE_MASK_LEN;
    mask[0] ^= 0x40u;
    wr32(buf + n - 56u + 52u, crc32_ieee_test(mask, DS4_BAKE_MASK_LEN));
    CHECK(ds4_bake_probe(buf, (uint64_t)n, &meta, err, sizeof(err)) == DS4_BAKE_PROBE_INVALID);
    free(buf);
    return 0;
}

int main(void) {
    CHECK(test_ordinary() == 0);
    CHECK(test_valid() == 0);
    CHECK(test_k60_shape() == 0);
    CHECK(test_bad_footer_version() == 0);
    CHECK(test_overflow() == 0);
    CHECK(test_manifest_crc() == 0);
    CHECK(test_mask_crc() == 0);
    CHECK(expect_invalid(FIX_MALFORMED_JSON) == 0);
    CHECK(test_bitset_mismatch() == 0);
    CHECK(expect_invalid(FIX_TOO_FEW) == 0);
    CHECK(expect_invalid(FIX_DUP_SELECTION) == 0);
    CHECK(expect_invalid(FIX_DUP_LAYER) == 0);
    CHECK(expect_invalid(FIX_OOR_SELECTION) == 0);
    CHECK(expect_invalid(FIX_MISSING_TENSOR) == 0);
    CHECK(expect_invalid(FIX_DUP_TENSOR) == 0);
    CHECK(expect_invalid(FIX_DUP_TENSOR_FIELD) == 0);
    CHECK(expect_invalid(FIX_DUP_TOP_KEY) == 0);
    CHECK(expect_invalid(FIX_OVERLONG_SHA) == 0);
    CHECK(expect_invalid(FIX_OVERLAP_EXTENTS) == 0);
    CHECK(expect_invalid(FIX_MANIFEST_BAD_VERSION) == 0);
    return 0;
}
