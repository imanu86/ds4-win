#include "ds4_bake.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#define DS4_BAKE_FOOTER_LEN 56u
#define DS4_BAKE_VERSION 1u
#define DS4_BAKE_MAGIC "DS4BAKEFILEv1\0\0\0"

typedef struct json_parser {
    const unsigned char *p;
    const unsigned char *end;
    char *err;
    size_t err_cap;
} json_parser;

typedef struct parse_state {
    ds4_bake_meta *meta;
    uint8_t selected[DS4_BAKE_MASK_LEN];
    bool selected_layer_seen[DS4_BAKE_LAYERS];
    bool tensor_seen[DS4_BAKE_LAYERS][DS4_BAKE_TENSOR_KINDS];
    uint32_t tensor_count;
    uint64_t payload_bytes;
    uint64_t extent_bytes;
    bool saw_format;
    bool saw_version;
    bool saw_source_size;
    bool saw_source_sha;
    bool saw_mask_sha;
    bool saw_payload_bytes;
    bool saw_extents;
    bool saw_selected;
    bool saw_routed;
} parse_state;

static void set_err(char *err, size_t cap, const char *fmt, ...) {
    if (!err || cap == 0) return;
    va_list ap;
    va_start(ap, fmt);
    (void)vsnprintf(err, cap, fmt, ap);
    va_end(ap);
    err[cap - 1] = '\0';
}

static bool fail(json_parser *j, const char *fmt, ...) {
    if (j && j->err && j->err_cap) {
        va_list ap;
        va_start(ap, fmt);
        (void)vsnprintf(j->err, j->err_cap, fmt, ap);
        va_end(ap);
        j->err[j->err_cap - 1] = '\0';
    }
    return false;
}

static uint32_t rd32(const unsigned char *p) {
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t rd64(const unsigned char *p) {
    return ((uint64_t)rd32(p)) | ((uint64_t)rd32(p + 4) << 32);
}

static uint32_t crc32_ieee(const unsigned char *p, uint64_t n) {
    uint32_t crc = 0xffffffffu;
    for (uint64_t i = 0; i < n; i++) {
        crc ^= p[i];
        for (int b = 0; b < 8; b++) {
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
        }
    }
    return crc ^ 0xffffffffu;
}

static bool add_u64(uint64_t a, uint64_t b, uint64_t *out) {
    if (UINT64_MAX - a < b) return false;
    *out = a + b;
    return true;
}

static bool validate_utf8(const unsigned char *s, uint64_t n) {
    uint64_t i = 0;
    while (i < n) {
        unsigned char c = s[i++];
        if (c < 0x80) continue;
        if (c >= 0xc2 && c <= 0xdf) {
            if (i >= n || (s[i++] & 0xc0) != 0x80) return false;
        } else if (c == 0xe0) {
            if (i + 1 >= n || s[i] < 0xa0 || s[i] > 0xbf || (s[i + 1] & 0xc0) != 0x80) return false;
            i += 2;
        } else if ((c >= 0xe1 && c <= 0xec) || (c >= 0xee && c <= 0xef)) {
            if (i + 1 >= n || (s[i] & 0xc0) != 0x80 || (s[i + 1] & 0xc0) != 0x80) return false;
            i += 2;
        } else if (c == 0xed) {
            if (i + 1 >= n || s[i] < 0x80 || s[i] > 0x9f || (s[i + 1] & 0xc0) != 0x80) return false;
            i += 2;
        } else if (c == 0xf0) {
            if (i + 2 >= n || s[i] < 0x90 || s[i] > 0xbf || (s[i + 1] & 0xc0) != 0x80 || (s[i + 2] & 0xc0) != 0x80) return false;
            i += 3;
        } else if (c >= 0xf1 && c <= 0xf3) {
            if (i + 2 >= n || (s[i] & 0xc0) != 0x80 || (s[i + 1] & 0xc0) != 0x80 || (s[i + 2] & 0xc0) != 0x80) return false;
            i += 3;
        } else if (c == 0xf4) {
            if (i + 2 >= n || s[i] < 0x80 || s[i] > 0x8f || (s[i + 1] & 0xc0) != 0x80 || (s[i + 2] & 0xc0) != 0x80) return false;
            i += 3;
        } else {
            return false;
        }
    }
    return true;
}

static void js_ws(json_parser *j) {
    while (j->p < j->end && (*j->p == ' ' || *j->p == '\n' || *j->p == '\r' || *j->p == '\t')) j->p++;
}

static bool js_lit(json_parser *j, const char *lit) {
    size_t n = strlen(lit);
    if ((size_t)(j->end - j->p) < n || memcmp(j->p, lit, n) != 0) return fail(j, "expected %s", lit);
    j->p += n;
    return true;
}

static int hexval(unsigned char c) {
    if (c >= '0' && c <= '9') return (int)(c - '0');
    if (c >= 'a' && c <= 'f') return (int)(c - 'a') + 10;
    if (c >= 'A' && c <= 'F') return (int)(c - 'A') + 10;
    return -1;
}

static bool js_string(json_parser *j, char *out, size_t cap) {
    size_t n = 0;
    bool overflow = false;
    js_ws(j);
    if (j->p >= j->end || *j->p++ != '"') return fail(j, "expected string");
    while (j->p < j->end) {
        unsigned char c = *j->p++;
        if (c == '"') {
            if (overflow) return fail(j, "string is too long");
            if (out && cap) out[n] = '\0';
            return true;
        }
        if (c < 0x20) return fail(j, "control character in string");
        if (c == '\\') {
            if (j->p >= j->end) return fail(j, "bad string escape");
            c = *j->p++;
            if (c == '"' || c == '\\' || c == '/') {
            } else if (c == 'b') c = '\b';
            else if (c == 'f') c = '\f';
            else if (c == 'n') c = '\n';
            else if (c == 'r') c = '\r';
            else if (c == 't') c = '\t';
            else if (c == 'u') {
                if (j->end - j->p < 4) return fail(j, "short unicode escape");
                for (int i = 0; i < 4; i++) if (hexval(j->p[i]) < 0) return fail(j, "bad unicode escape");
                j->p += 4;
                c = '?';
            } else {
                return fail(j, "bad string escape");
            }
        }
        if (out && cap) {
            if (n + 1 >= cap) overflow = true;
            else out[n] = (char)c;
        }
        n++;
    }
    return fail(j, "unterminated string");
}

static bool js_u64(json_parser *j, uint64_t *out) {
    uint64_t v = 0;
    js_ws(j);
    if (j->p >= j->end || *j->p < '0' || *j->p > '9') return fail(j, "expected integer");
    if (*j->p == '0') {
        j->p++;
    } else {
        while (j->p < j->end && *j->p >= '0' && *j->p <= '9') {
            uint32_t d = (uint32_t)(*j->p - '0');
            if (v > (UINT64_MAX - d) / 10u) return fail(j, "integer overflow");
            v = v * 10u + d;
            j->p++;
        }
    }
    if (j->p < j->end && (*j->p == '.' || *j->p == 'e' || *j->p == 'E')) return fail(j, "non-integer number");
    *out = v;
    return true;
}

static bool js_skip_value(json_parser *j);

static bool js_skip_array(json_parser *j) {
    if (j->p >= j->end || *j->p++ != '[') return fail(j, "expected array");
    js_ws(j);
    if (j->p < j->end && *j->p == ']') {
        j->p++;
        return true;
    }
    for (;;) {
        if (!js_skip_value(j)) return false;
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated array");
        if (*j->p == ']') {
            j->p++;
            return true;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
}

static bool js_skip_object(json_parser *j) {
    char key[128];
    if (j->p >= j->end || *j->p++ != '{') return fail(j, "expected object");
    js_ws(j);
    if (j->p < j->end && *j->p == '}') {
        j->p++;
        return true;
    }
    for (;;) {
        if (!js_string(j, key, sizeof(key))) return false;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != ':') return fail(j, "expected colon");
        if (!js_skip_value(j)) return false;
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated object");
        if (*j->p == '}') {
            j->p++;
            return true;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
}

static bool js_skip_value(json_parser *j) {
    js_ws(j);
    if (j->p >= j->end) return fail(j, "expected value");
    if (*j->p == '"') {
        return js_string(j, NULL, 0);
    }
    if (*j->p == '{') return js_skip_object(j);
    if (*j->p == '[') return js_skip_array(j);
    if (*j->p == 't') return js_lit(j, "true");
    if (*j->p == 'f') return js_lit(j, "false");
    if (*j->p == 'n') return js_lit(j, "null");
    if ((*j->p >= '0' && *j->p <= '9')) {
        uint64_t v;
        return js_u64(j, &v);
    }
    return fail(j, "unexpected value");
}

static bool is_hex64(const char *s) {
    for (int i = 0; i < 64; i++) if (hexval((unsigned char)s[i]) < 0) return false;
    return s[64] == '\0';
}

static void mask_set(uint8_t *m, uint32_t layer, uint32_t expert) {
    uint32_t bit = layer * DS4_BAKE_EXPERTS + expert;
    m[bit >> 3] = (uint8_t)(m[bit >> 3] | (uint8_t)(1u << (bit & 7u)));
}

int ds4_bake_expert_retained(const ds4_bake_meta *meta, uint32_t layer, uint32_t expert) {
    if (!meta || layer >= DS4_BAKE_LAYERS || expert >= DS4_BAKE_EXPERTS) return 0;
    uint32_t bit = layer * DS4_BAKE_EXPERTS + expert;
    return (meta->retained_mask[bit >> 3] & (uint8_t)(1u << (bit & 7u))) != 0;
}

static void init_all_selected(parse_state *st) {
    memset(st->selected, 0xff, DS4_BAKE_MASK_LEN);
    for (uint32_t l = 0; l < DS4_BAKE_LAYERS; l++) st->meta->retained_count[l] = DS4_BAKE_EXPERTS;
}

static bool parse_layer_key(const char *key, uint32_t *layer) {
    uint64_t v = 0;
    if (!key[0]) return false;
    for (const char *p = key; *p; p++) {
        if (*p < '0' || *p > '9') return false;
        v = v * 10u + (uint32_t)(*p - '0');
        if (v >= DS4_BAKE_LAYERS) return false;
    }
    *layer = (uint32_t)v;
    return true;
}

static bool parse_selected_array(json_parser *j, parse_state *st, uint32_t layer) {
    bool seen[DS4_BAKE_EXPERTS];
    uint32_t count = 0;
    memset(seen, 0, sizeof(seen));
    memset(st->selected + (layer * 32u), 0, 32u);
    js_ws(j);
    if (j->p >= j->end || *j->p++ != '[') return fail(j, "expected selected array");
    js_ws(j);
    if (j->p < j->end && *j->p == ']') return fail(j, "selected layer has too few experts");
    for (;;) {
        uint64_t v;
        if (!js_u64(j, &v)) return false;
        if (v >= DS4_BAKE_EXPERTS) return fail(j, "expert out of range");
        if (seen[v]) return fail(j, "duplicate expert");
        seen[v] = true;
        mask_set(st->selected, layer, (uint32_t)v);
        count++;
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated selected array");
        if (*j->p == ']') {
            j->p++;
            break;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
    if (count < 6u) return fail(j, "selected layer has too few experts");
    st->meta->retained_count[layer] = (uint16_t)count;
    return true;
}

static bool parse_selected(json_parser *j, parse_state *st) {
    char key[32];
    js_ws(j);
    if (j->p >= j->end || *j->p++ != '{') return fail(j, "expected selected object");
    js_ws(j);
    if (j->p < j->end && *j->p == '}') {
        j->p++;
        return true;
    }
    for (;;) {
        uint32_t layer;
        if (!js_string(j, key, sizeof(key))) return false;
        if (!parse_layer_key(key, &layer)) return fail(j, "layer key out of range");
        if (st->selected_layer_seen[layer]) return fail(j, "duplicate selected layer");
        st->selected_layer_seen[layer] = true;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != ':') return fail(j, "expected colon");
        if (!parse_selected_array(j, st, layer)) return false;
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated selected object");
        if (*j->p == '}') {
            j->p++;
            return true;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
}

static int kind_from_string(const char *s) {
    if (strcmp(s, "gate") == 0) return DS4_BAKE_TENSOR_GATE;
    if (strcmp(s, "up") == 0) return DS4_BAKE_TENSOR_UP;
    if (strcmp(s, "down") == 0) return DS4_BAKE_TENSOR_DOWN;
    return -1;
}

static bool expected_name(char *buf, size_t cap, uint32_t layer, int kind) {
    const char *k = kind == DS4_BAKE_TENSOR_GATE ? "gate" : (kind == DS4_BAKE_TENSOR_UP ? "up" : "down");
    return snprintf(buf, cap, "blk.%u.ffn_%s_exps.weight", layer, k) > 0;
}

static bool parse_tensor_record(json_parser *j, parse_state *st) {
    ds4_bake_tensor_record rec;
    bool saw_name = false, saw_layer = false, saw_kind = false, saw_offset = false;
    bool saw_bytes = false, saw_slice = false, saw_type = false, saw_count = false;
    char key[64], kind_s[16], expect[64];
    uint64_t tmp;
    memset(&rec, 0, sizeof(rec));
    memset(kind_s, 0, sizeof(kind_s));
    js_ws(j);
    if (j->p >= j->end || *j->p++ != '{') return fail(j, "expected tensor object");
    js_ws(j);
    if (j->p < j->end && *j->p == '}') return fail(j, "empty tensor object");
    for (;;) {
        if (!js_string(j, key, sizeof(key))) return false;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != ':') return fail(j, "expected colon");
        if (strcmp(key, "name") == 0) {
            if (saw_name) return fail(j, "duplicate tensor name");
            if (!js_string(j, rec.name, sizeof(rec.name))) return false;
            saw_name = true;
        } else if (strcmp(key, "layer") == 0) {
            if (saw_layer) return fail(j, "duplicate tensor layer");
            if (!js_u64(j, &tmp)) return false;
            if (tmp >= DS4_BAKE_LAYERS) return fail(j, "tensor layer out of range");
            rec.layer = (uint32_t)tmp;
            saw_layer = true;
        } else if (strcmp(key, "kind") == 0) {
            if (saw_kind) return fail(j, "duplicate tensor kind");
            if (!js_string(j, kind_s, sizeof(kind_s))) return false;
            int k = kind_from_string(kind_s);
            if (k < 0) return fail(j, "bad tensor kind");
            rec.kind = (ds4_bake_tensor_kind)k;
            saw_kind = true;
        } else if (strcmp(key, "offset") == 0) {
            if (saw_offset) return fail(j, "duplicate tensor offset");
            if (!js_u64(j, &rec.offset)) return false;
            saw_offset = true;
        } else if (strcmp(key, "bytes") == 0) {
            if (saw_bytes) return fail(j, "duplicate tensor bytes");
            if (!js_u64(j, &rec.bytes)) return false;
            saw_bytes = true;
        } else if (strcmp(key, "slice_bytes") == 0) {
            if (saw_slice) return fail(j, "duplicate tensor slice_bytes");
            if (!js_u64(j, &rec.slice_bytes)) return false;
            saw_slice = true;
        } else if (strcmp(key, "tensor_type") == 0) {
            if (saw_type) return fail(j, "duplicate tensor tensor_type");
            if (!js_u64(j, &tmp)) return false;
            if (tmp > UINT32_MAX) return fail(j, "tensor_type out of range");
            rec.tensor_type = (uint32_t)tmp;
            saw_type = true;
        } else if (strcmp(key, "selected_count") == 0) {
            if (saw_count) return fail(j, "duplicate tensor selected_count");
            if (!js_u64(j, &tmp)) return false;
            if (tmp > DS4_BAKE_EXPERTS) return fail(j, "selected_count out of range");
            rec.selected_count = (uint32_t)tmp;
            saw_count = true;
        } else {
            if (!js_skip_value(j)) return false;
        }
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated tensor object");
        if (*j->p == '}') {
            j->p++;
            break;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
    if (!saw_name || !saw_layer || !saw_kind || !saw_offset || !saw_bytes ||
        !saw_slice || !saw_type || !saw_count) return fail(j, "tensor missing required field");
    (void)expected_name(expect, sizeof(expect), rec.layer, (int)rec.kind);
    if (strcmp(rec.name, expect) != 0) return fail(j, "tensor name mismatch");
    if (rec.slice_bytes == 0 || rec.bytes == 0) return fail(j, "tensor byte size is zero");
    if (rec.slice_bytes > UINT64_MAX / DS4_BAKE_EXPERTS ||
        rec.bytes != rec.slice_bytes * DS4_BAKE_EXPERTS) return fail(j, "tensor bytes mismatch");
    if (rec.offset > st->meta->source_size || rec.bytes > st->meta->source_size - rec.offset) return fail(j, "tensor bounds exceed source");
    if (st->tensor_seen[rec.layer][rec.kind]) return fail(j, "duplicate routed tensor");
    st->tensor_seen[rec.layer][rec.kind] = true;
    st->meta->routed_tensors[rec.layer][rec.kind] = rec;
    st->tensor_count++;
    return true;
}

static bool parse_routed(json_parser *j, parse_state *st) {
    js_ws(j);
    if (j->p >= j->end || *j->p++ != '[') return fail(j, "expected routed_tensors array");
    js_ws(j);
    if (j->p < j->end && *j->p == ']') return fail(j, "empty routed_tensors");
    for (;;) {
        if (!parse_tensor_record(j, st)) return false;
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated routed_tensors");
        if (*j->p == ']') {
            j->p++;
            break;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
    return true;
}

static bool parse_extents(json_parser *j, parse_state *st) {
    uint64_t previous_end = 0;
    uint32_t count = 0;

    js_ws(j);
    if (j->p >= j->end || *j->p++ != '[') return fail(j, "expected extents array");
    js_ws(j);
    if (j->p < j->end && *j->p == ']') return fail(j, "empty extents array");
    for (;;) {
        uint64_t offset, length, end, total;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != '[') return fail(j, "expected extent pair");
        if (!js_u64(j, &offset)) return false;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != ',') return fail(j, "expected extent comma");
        if (!js_u64(j, &length)) return false;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != ']') return fail(j, "expected extent close");
        if (length == 0 || !add_u64(offset, length, &end) ||
            end > st->meta->source_size) {
            return fail(j, "extent outside source");
        }
        if (count != 0 && offset < previous_end) return fail(j, "extents overlap or are unsorted");
        if (!add_u64(st->extent_bytes, length, &total)) return fail(j, "extent byte sum overflow");
        st->extent_bytes = total;
        previous_end = end;
        count++;
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated extents array");
        if (*j->p == ']') {
            j->p++;
            return true;
        }
        if (*j->p++ != ',') return fail(j, "expected extents comma");
    }
}

static bool parse_manifest(json_parser *j, parse_state *st) {
    char key[64], s[96];
    uint64_t v;
    js_ws(j);
    if (j->p >= j->end || *j->p++ != '{') return fail(j, "expected manifest object");
    js_ws(j);
    if (j->p < j->end && *j->p == '}') return fail(j, "empty manifest");
    for (;;) {
        if (!js_string(j, key, sizeof(key))) return false;
        js_ws(j);
        if (j->p >= j->end || *j->p++ != ':') return fail(j, "expected colon");
        if (strcmp(key, "format") == 0) {
            if (st->saw_format) return fail(j, "duplicate manifest format");
            if (!js_string(j, s, sizeof(s))) return false;
            if (strcmp(s, "ds4-windows-sparse-bake") != 0) return fail(j, "bad manifest format");
            st->saw_format = true;
        } else if (strcmp(key, "version") == 0) {
            if (st->saw_version) return fail(j, "duplicate manifest version");
            if (!js_u64(j, &v)) return false;
            if (v != 1u) return fail(j, "bad manifest version");
            st->saw_version = true;
        } else if (strcmp(key, "source_model_size") == 0) {
            if (st->saw_source_size) return fail(j, "duplicate source_model_size");
            if (!js_u64(j, &v)) return false;
            if (v != st->meta->source_size) return fail(j, "source_model_size mismatch");
            st->saw_source_size = true;
        } else if (strcmp(key, "source_model_sha256") == 0) {
            if (st->saw_source_sha) return fail(j, "duplicate source_model_sha256");
            js_ws(j);
            if (j->p < j->end && *j->p == 'n') {
                if (!js_lit(j, "null")) return false;
                st->meta->source_model_sha256[0] = '\0';
                st->meta->source_model_sha256_present = 0;
            } else {
                if (!js_string(j, st->meta->source_model_sha256, sizeof(st->meta->source_model_sha256))) return false;
                if (!is_hex64(st->meta->source_model_sha256)) return fail(j, "bad source_model_sha256");
                st->meta->source_model_sha256_present = 1;
            }
            st->saw_source_sha = true;
        } else if (strcmp(key, "mask_sha256") == 0) {
            if (st->saw_mask_sha) return fail(j, "duplicate mask_sha256");
            if (!js_string(j, st->meta->mask_sha256, sizeof(st->meta->mask_sha256))) return false;
            if (!is_hex64(st->meta->mask_sha256)) return fail(j, "bad mask_sha256");
            st->saw_mask_sha = true;
        } else if (strcmp(key, "payload_bytes") == 0) {
            if (st->saw_payload_bytes) return fail(j, "duplicate payload_bytes");
            if (!js_u64(j, &st->payload_bytes) || st->payload_bytes == 0 ||
                st->payload_bytes > st->meta->source_size) {
                return fail(j, "invalid payload_bytes");
            }
            st->saw_payload_bytes = true;
        } else if (strcmp(key, "extents") == 0) {
            if (st->saw_extents) return fail(j, "duplicate extents");
            if (!parse_extents(j, st)) return false;
            st->saw_extents = true;
        } else if (strcmp(key, "selected_experts_by_layer") == 0) {
            if (st->saw_selected) return fail(j, "duplicate selected_experts_by_layer");
            if (!parse_selected(j, st)) return false;
            st->saw_selected = true;
        } else if (strcmp(key, "routed_tensors") == 0) {
            if (st->saw_routed) return fail(j, "duplicate routed_tensors");
            if (!parse_routed(j, st)) return false;
            st->saw_routed = true;
        } else {
            if (!js_skip_value(j)) return false;
        }
        js_ws(j);
        if (j->p >= j->end) return fail(j, "unterminated manifest");
        if (*j->p == '}') {
            j->p++;
            break;
        }
        if (*j->p++ != ',') return fail(j, "expected comma");
    }
    js_ws(j);
    if (j->p != j->end) return fail(j, "trailing JSON data");
    if (!st->saw_format || !st->saw_version || !st->saw_source_size ||
        !st->saw_source_sha || !st->saw_mask_sha || !st->saw_payload_bytes ||
        !st->saw_extents || !st->saw_selected || !st->saw_routed) {
        return fail(j, "manifest missing required key");
    }
    if (st->extent_bytes != st->payload_bytes) return fail(j, "payload extent sum mismatch");
    if (st->tensor_count != DS4_BAKE_LAYERS * DS4_BAKE_TENSOR_KINDS) return fail(j, "missing routed tensor");
    for (uint32_t layer = 0; layer < DS4_BAKE_LAYERS; layer++) {
        for (uint32_t kind = 0; kind < DS4_BAKE_TENSOR_KINDS; kind++) {
            if (st->meta->routed_tensors[layer][kind].selected_count != st->meta->retained_count[layer]) {
                return fail(j, "selected_count mismatch");
            }
        }
    }
    return true;
}

ds4_bake_probe_result ds4_bake_probe(const void *map, uint64_t mapped_size,
                                     ds4_bake_meta *out, char *err, size_t err_cap) {
    const unsigned char *base = (const unsigned char *)map;
    const unsigned char *footer;
    uint32_t version, n_layers, n_experts, mask_len;
    uint64_t source_size, manifest_len, end1, end2, expect_size;
    const unsigned char *manifest;
    const unsigned char *mask;
    parse_state st;
    json_parser j;
    if (err && err_cap) err[0] = '\0';
    if (!map || mapped_size < DS4_BAKE_FOOTER_LEN) return DS4_BAKE_PROBE_NONE;
    footer = base + mapped_size - DS4_BAKE_FOOTER_LEN;
    if (memcmp(footer, DS4_BAKE_MAGIC, 16) != 0) return DS4_BAKE_PROBE_NONE;
    if (!out) {
        set_err(err, err_cap, "out metadata is required");
        return DS4_BAKE_PROBE_INVALID;
    }
    memset(out, 0, sizeof(*out));
    out->mapped_size = mapped_size;
    version = rd32(footer + 16);
    n_layers = rd32(footer + 20);
    n_experts = rd32(footer + 24);
    mask_len = rd32(footer + 28);
    source_size = rd64(footer + 32);
    manifest_len = rd64(footer + 40);
    out->manifest_crc32 = rd32(footer + 48);
    out->mask_crc32 = rd32(footer + 52);
    out->source_size = source_size;
    out->manifest_len = manifest_len;
    if (version != DS4_BAKE_VERSION) {
        set_err(err, err_cap, "bad footer version");
        return DS4_BAKE_PROBE_INVALID;
    }
    if (n_layers != DS4_BAKE_LAYERS || n_experts != DS4_BAKE_EXPERTS || mask_len != DS4_BAKE_MASK_LEN) {
        set_err(err, err_cap, "bad footer dimensions");
        return DS4_BAKE_PROBE_INVALID;
    }
    if (!add_u64(source_size, manifest_len, &end1) ||
        !add_u64(end1, DS4_BAKE_MASK_LEN, &end2) ||
        !add_u64(end2, DS4_BAKE_FOOTER_LEN, &expect_size)) {
        set_err(err, err_cap, "trailer size overflow");
        return DS4_BAKE_PROBE_INVALID;
    }
    if (expect_size != mapped_size || source_size > mapped_size || end1 > mapped_size || end2 > mapped_size) {
        set_err(err, err_cap, "mapped size mismatch");
        return DS4_BAKE_PROBE_INVALID;
    }
    manifest = base + source_size;
    mask = base + end1;
    if (!validate_utf8(manifest, manifest_len)) {
        set_err(err, err_cap, "manifest is not valid UTF-8");
        return DS4_BAKE_PROBE_INVALID;
    }
    if (crc32_ieee(manifest, manifest_len) != out->manifest_crc32) {
        set_err(err, err_cap, "manifest CRC mismatch");
        return DS4_BAKE_PROBE_INVALID;
    }
    if (crc32_ieee(mask, DS4_BAKE_MASK_LEN) != out->mask_crc32) {
        set_err(err, err_cap, "mask CRC mismatch");
        return DS4_BAKE_PROBE_INVALID;
    }
    memset(&st, 0, sizeof(st));
    st.meta = out;
    init_all_selected(&st);
    j.p = manifest;
    j.end = manifest + manifest_len;
    j.err = err;
    j.err_cap = err_cap;
    if (!parse_manifest(&j, &st)) return DS4_BAKE_PROBE_INVALID;
    if (memcmp(st.selected, mask, DS4_BAKE_MASK_LEN) != 0) {
        set_err(err, err_cap, "retained mask mismatch");
        return DS4_BAKE_PROBE_INVALID;
    }
    memcpy(out->retained_mask, mask, DS4_BAKE_MASK_LEN);
    return DS4_BAKE_PROBE_VALID;
}
