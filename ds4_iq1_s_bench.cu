/*
 * Standalone IQ1_S CUDA microbenchmark for ds4-win.
 *
 * Provenance:
 *   - block_iq1_s layout, IQ1S_DELTA, iq1s_grid_gpu table, and the device
 *     dot/dequant math are ported from ggml-org/llama.cpp commit
 *     b15ca938ad00aa6b3ee6c2edda7363fd02826b18.
 *   - Upstream files: ggml/src/ggml-common.h and ggml/src/ggml-cuda/vecdotq.cuh.
 *
 * This file intentionally does not include or modify ds4.c/ds4_cuda.cu.
 */

#include <cuda_fp16.h>
#include <cuda_runtime.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

#define DS4_IQ1_QK_K 256
#define DS4_N_EMBD 4096u
#define DS4_N_FF_EXP 2048u
#define DS4_N_EXPERT 256u

typedef struct {
    uint16_t d;
    uint8_t  qs[DS4_IQ1_QK_K / 8];
    uint16_t qh[DS4_IQ1_QK_K / 32];
} ds4_block_iq1_s;

typedef struct {
    uint8_t  scales[DS4_IQ1_QK_K / 16];
    uint8_t  qs[DS4_IQ1_QK_K / 4];
    uint16_t d;
    uint16_t dmin;
} ds4_block_q2_K;

typedef struct {
    uint32_t ds;
    int8_t qs[32];
} ds4_block_q8_1;

typedef struct {
    float d;
    int8_t qs[DS4_IQ1_QK_K];
    int16_t bsums[DS4_IQ1_QK_K / 16];
} ds4_block_q8_K;

static_assert(sizeof(ds4_block_iq1_s) == 50, "IQ1_S must be 50 bytes per 256 weights");
static_assert(sizeof(ds4_block_q2_K) == 84, "Q2_K must be 84 bytes per 256 weights");
static_assert(sizeof(ds4_block_q8_1) == 36, "Q8_1 helper block size changed");
static_assert(sizeof(ds4_block_q8_K) == 292, "Q8_K helper block size changed");

#include "ds4_iq1_tables_cuda.inc"

static void die_cuda(cudaError_t e, const char *what) {
    if (e != cudaSuccess) {
        std::fprintf(stderr, "%s: %s\n", what, cudaGetErrorString(e));
        std::exit(1);
    }
}

static uint32_t xorshift32(uint32_t &s) {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
}

static uint16_t f32_to_f16_bits(float v) {
    const __half h = __float2half(v);
    uint16_t u;
    std::memcpy(&u, &h, sizeof(u));
    return u;
}

static float f16_bits_to_f32(uint16_t u) {
    __half h;
    std::memcpy(&h, &u, sizeof(h));
    return __half2float(h);
}

static uint32_t pack_half2_bits(float lo, float hi) {
    return (uint32_t)f32_to_f16_bits(lo) | ((uint32_t)f32_to_f16_bits(hi) << 16);
}

struct real_sample {
    std::string name;
    uint32_t layer;
    const char *part;
    const char *type_name;
    uint32_t type;
    uint64_t rows;
    uint64_t cols;
    uint64_t experts;
    uint64_t blocks_offset;
    uint64_t blocks;
    uint32_t source_shard;
    uint32_t source_shard_count;
    uint64_t source_shard_physical_base;
    uint64_t source_shard_tensor_data_base;
    uint64_t tensor_relative_offset;
    uint64_t physical_offset;
    uint64_t sample_bytes;
};

struct gguf_tensor_info {
    std::string name;
    uint32_t n_dims;
    uint64_t dims[8];
    uint32_t type;
    uint64_t relative_offset;
    uint64_t physical_offset;
    uint64_t bytes;
    uint32_t source_shard;
    uint64_t source_shard_physical_base;
    uint64_t source_shard_tensor_data_base;
};

struct gguf_split_metadata {
    bool has_no;
    bool has_count;
    bool has_tensor_count;
    uint64_t no;
    uint64_t count;
    uint64_t tensor_count;
};

struct gguf_shard_info {
    uint64_t physical_base;
    uint64_t tensor_data_base;
    uint64_t physical_end;
    gguf_split_metadata split;
    std::vector<gguf_tensor_info> tensors;
};

static bool ends_with_ci(const std::string &s, const char *suffix) {
    const size_t n = std::strlen(suffix);
    if (s.size() < n) return false;
    for (size_t i = 0; i < n; ++i) {
        char a = s[s.size() - n + i];
        char b = suffix[i];
        if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
        if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
        if (a != b) return false;
    }
    return true;
}

static uint64_t align_up_u64(uint64_t x, uint64_t a) {
    if (a == 0 || (a & (a - 1u)) != 0) throw std::runtime_error("invalid GGUF alignment");
    if (x > UINT64_MAX - (a - 1u)) throw std::runtime_error("GGUF alignment overflow");
    return (x + a - 1u) & ~(a - 1u);
}

static uint64_t checked_add_u64(uint64_t a, uint64_t b, const char *what) {
    if (a > UINT64_MAX - b) throw std::runtime_error(std::string(what) + " overflow");
    return a + b;
}

static uint64_t checked_mul_u64(uint64_t a, uint64_t b, const char *what) {
    if (a != 0 && b > UINT64_MAX / a) throw std::runtime_error(std::string(what) + " overflow");
    return a * b;
}

template <typename T>
static T read_pod(std::ifstream &in, const char *what) {
    T v{};
    in.read((char *)&v, sizeof(v));
    if (!in) throw std::runtime_error(std::string("failed to read ") + what);
    return v;
}

static std::string read_gguf_string(std::ifstream &in) {
    const uint64_t n = read_pod<uint64_t>(in, "GGUF string length");
    if (n > (1ull << 30) || n > (uint64_t)std::numeric_limits<std::streamsize>::max()) {
        throw std::runtime_error("GGUF string is too large");
    }
    std::string s((size_t)n, '\0');
    if (n) in.read(&s[0], (std::streamsize)n);
    if (!in) throw std::runtime_error("failed to read GGUF string");
    return s;
}

static void skip_bytes(std::ifstream &in, uint64_t n, const char *what) {
    if (n > (uint64_t)std::numeric_limits<std::streamoff>::max()) {
        throw std::runtime_error(std::string(what) + " is too large");
    }
    in.seekg((std::streamoff)n, std::ios::cur);
    if (!in) throw std::runtime_error(std::string("failed to skip ") + what);
}

static uint64_t gguf_scalar_size(uint32_t type) {
    switch (type) {
    case 0: case 1: case 7: return 1;
    case 2: case 3: return 2;
    case 4: case 5: case 6: return 4;
    case 10: case 11: case 12: return 8;
    default: return 0;
    }
}

static void skip_gguf_value(std::ifstream &in, uint32_t type, uint32_t depth = 0) {
    if (depth > 8) throw std::runtime_error("GGUF metadata array nesting is too deep");
    const uint64_t scalar_size = gguf_scalar_size(type);
    if (scalar_size != 0) {
        skip_bytes(in, scalar_size, "GGUF metadata scalar");
        return;
    }
    if (type == 8) {
        (void)read_gguf_string(in);
        return;
    }
    if (type != 9) throw std::runtime_error("unsupported GGUF metadata type");
    const uint32_t item_type = read_pod<uint32_t>(in, "GGUF array type");
    const uint64_t n = read_pod<uint64_t>(in, "GGUF array length");
    const uint64_t item_size = gguf_scalar_size(item_type);
    if (item_size != 0) {
        skip_bytes(in, checked_mul_u64(n, item_size, "GGUF metadata array"),
                   "GGUF metadata array");
        return;
    }
    if (n > (1ull << 34)) throw std::runtime_error("GGUF metadata array is too large");
    for (uint64_t i = 0; i < n; ++i) skip_gguf_value(in, item_type, depth + 1);
}

static bool gguf_block_layout(uint32_t type, uint64_t &block_elems, uint64_t &block_bytes) {
    switch (type) {
    case 0:  block_elems = 1;   block_bytes = 4;   break;
    case 1:  block_elems = 1;   block_bytes = 2;   break;
    case 2:  block_elems = 32;  block_bytes = 18;  break;
    case 3:  block_elems = 32;  block_bytes = 20;  break;
    case 6:  block_elems = 32;  block_bytes = 22;  break;
    case 7:  block_elems = 32;  block_bytes = 24;  break;
    case 8:  block_elems = 32;  block_bytes = 34;  break;
    case 9:  block_elems = 32;  block_bytes = 40;  break;
    case 10: block_elems = 256; block_bytes = 84;  break;
    case 11: block_elems = 256; block_bytes = 110; break;
    case 12: block_elems = 256; block_bytes = 144; break;
    case 13: block_elems = 256; block_bytes = 176; break;
    case 14: block_elems = 256; block_bytes = 210; break;
    case 15: block_elems = 256; block_bytes = 292; break;
    case 16: block_elems = 256; block_bytes = 66;  break;
    case 17: block_elems = 256; block_bytes = 74;  break;
    case 18: block_elems = 256; block_bytes = 98;  break;
    case 19: block_elems = 256; block_bytes = 50;  break;
    case 20: block_elems = 256; block_bytes = 50;  break;
    case 21: block_elems = 256; block_bytes = 110; break;
    case 22: block_elems = 256; block_bytes = 82;  break;
    case 23: block_elems = 256; block_bytes = 136; break;
    case 24: block_elems = 1;   block_bytes = 1;   break;
    case 25: block_elems = 1;   block_bytes = 2;   break;
    case 26: block_elems = 1;   block_bytes = 4;   break;
    case 27: block_elems = 1;   block_bytes = 8;   break;
    case 28: block_elems = 1;   block_bytes = 8;   break;
    case 29: block_elems = 256; block_bytes = 56;  break;
    case 30: block_elems = 1;   block_bytes = 2;   break;
    default: return false;
    }
    return true;
}

static uint64_t gguf_tensor_nbytes(uint32_t type, uint64_t elements) {
    uint64_t block_elems = 0;
    uint64_t block_bytes = 0;
    if (!gguf_block_layout(type, block_elems, block_bytes)) {
        throw std::runtime_error("unsupported GGUF tensor type at split boundary");
    }
    const uint64_t blocks = elements / block_elems + (elements % block_elems != 0);
    return checked_mul_u64(blocks, block_bytes, "GGUF tensor byte size");
}

static uint64_t gguf_type_size(uint32_t type) {
    uint64_t block_elems = 0;
    uint64_t block_bytes = 0;
    if (!gguf_block_layout(type, block_elems, block_bytes) || block_elems != DS4_IQ1_QK_K) {
        return 0;
    }
    return block_bytes;
}

static const char *gguf_type_name(uint32_t type) {
    switch (type) {
    case 10: return "Q2_K";
    case 19: return "IQ1_S";
    default: return "unsupported";
    }
}

static const gguf_tensor_info *find_tensor(
        const std::vector<gguf_tensor_info> &tensors,
        const std::string &name) {
    for (const gguf_tensor_info &t : tensors) {
        if (t.name == name) return &t;
    }
    return nullptr;
}

static uint64_t read_nonnegative_gguf_integer(
        std::ifstream &in,
        uint32_t type,
        const std::string &key) {
    switch (type) {
    case 0: return read_pod<uint8_t>(in, key.c_str());
    case 2: return read_pod<uint16_t>(in, key.c_str());
    case 4: return read_pod<uint32_t>(in, key.c_str());
    case 10: return read_pod<uint64_t>(in, key.c_str());
    case 1: {
        const int8_t v = read_pod<int8_t>(in, key.c_str());
        if (v >= 0) return (uint64_t)v;
        break;
    }
    case 3: {
        const int16_t v = read_pod<int16_t>(in, key.c_str());
        if (v >= 0) return (uint64_t)v;
        break;
    }
    case 5: {
        const int32_t v = read_pod<int32_t>(in, key.c_str());
        if (v >= 0) return (uint64_t)v;
        break;
    }
    case 11: {
        const int64_t v = read_pod<int64_t>(in, key.c_str());
        if (v >= 0) return (uint64_t)v;
        break;
    }
    default: break;
    }
    throw std::runtime_error("invalid nonnegative integer metadata: " + key);
}

static uint64_t stream_position(std::ifstream &in, const char *what) {
    const std::streamoff pos = in.tellg();
    if (pos < 0) throw std::runtime_error(std::string("failed to locate ") + what);
    return (uint64_t)pos;
}

static void seek_absolute(std::ifstream &in, uint64_t offset, const char *what) {
    if (offset > (uint64_t)std::numeric_limits<std::streamoff>::max()) {
        throw std::runtime_error(std::string(what) + " offset is too large");
    }
    in.seekg((std::streamoff)offset, std::ios::beg);
    if (!in) throw std::runtime_error(std::string("failed to seek to ") + what);
}

static gguf_shard_info parse_gguf_shard(
        std::ifstream &in,
        uint64_t file_size,
        uint64_t shard_base,
        uint32_t shard_index) {
    if (shard_base > file_size || file_size - shard_base < 24) {
        throw std::runtime_error("concatenated split GGUF is truncated before the next shard");
    }
    seek_absolute(in, shard_base, "GGUF shard header");
    const uint32_t magic = read_pod<uint32_t>(in, "GGUF magic");
    const uint32_t version = read_pod<uint32_t>(in, "GGUF version");
    if (magic != 0x46554747u || version != 3u) {
        throw std::runtime_error("invalid GGUF v3 header at concatenated split boundary");
    }
    const uint64_t n_tensors = read_pod<uint64_t>(in, "GGUF tensor count");
    const uint64_t n_kv = read_pod<uint64_t>(in, "GGUF metadata count");
    if (n_tensors > (1ull << 24) || n_kv > (1ull << 24) ||
        n_tensors > (uint64_t)std::numeric_limits<size_t>::max()) {
        throw std::runtime_error("GGUF header counts are unreasonable");
    }

    gguf_shard_info shard{};
    shard.physical_base = shard_base;
    uint64_t alignment = 32;
    bool has_alignment = false;
    for (uint64_t i = 0; i < n_kv; ++i) {
        const std::string key = read_gguf_string(in);
        const uint32_t type = read_pod<uint32_t>(in, "GGUF metadata type");
        if (key == "general.alignment") {
            if (has_alignment || type != 4) {
                throw std::runtime_error("invalid or duplicate general.alignment metadata");
            }
            alignment = read_pod<uint32_t>(in, "GGUF alignment");
            has_alignment = true;
        } else if (key == "split.no") {
            if (shard.split.has_no) throw std::runtime_error("duplicate split.no metadata");
            shard.split.no = read_nonnegative_gguf_integer(in, type, key);
            shard.split.has_no = true;
        } else if (key == "split.count") {
            if (shard.split.has_count) throw std::runtime_error("duplicate split.count metadata");
            shard.split.count = read_nonnegative_gguf_integer(in, type, key);
            shard.split.has_count = true;
        } else if (key == "split.tensors.count") {
            if (shard.split.has_tensor_count) {
                throw std::runtime_error("duplicate split.tensors.count metadata");
            }
            shard.split.tensor_count = read_nonnegative_gguf_integer(in, type, key);
            shard.split.has_tensor_count = true;
        } else {
            skip_gguf_value(in, type);
        }
    }

    shard.tensors.reserve((size_t)n_tensors);
    for (uint64_t i = 0; i < n_tensors; ++i) {
        gguf_tensor_info t{};
        t.name = read_gguf_string(in);
        t.n_dims = read_pod<uint32_t>(in, "GGUF tensor n_dims");
        if (t.n_dims == 0 || t.n_dims > 8u) {
            throw std::runtime_error("GGUF tensor has an unsupported number of dimensions");
        }
        uint64_t elements = 1;
        for (uint32_t d = 0; d < t.n_dims; ++d) {
            t.dims[d] = read_pod<uint64_t>(in, "GGUF tensor dim");
            elements = checked_mul_u64(elements, t.dims[d], "GGUF tensor element count");
        }
        t.type = read_pod<uint32_t>(in, "GGUF tensor type");
        t.relative_offset = read_pod<uint64_t>(in, "GGUF tensor offset");
        t.bytes = gguf_tensor_nbytes(t.type, elements);
        t.source_shard = shard_index;
        t.source_shard_physical_base = shard_base;
        for (const gguf_tensor_info &prior : shard.tensors) {
            if (prior.name == t.name) {
                throw std::runtime_error("duplicate tensor name in GGUF shard: " + t.name);
            }
        }
        shard.tensors.push_back(t);
    }

    const uint64_t header_end = stream_position(in, "GGUF tensor directory");
    if (header_end < shard_base) throw std::runtime_error("GGUF shard header offset underflow");
    const uint64_t local_data_base = align_up_u64(header_end - shard_base, alignment);
    shard.tensor_data_base = checked_add_u64(shard_base, local_data_base, "GGUF tensor data offset");
    shard.physical_end = shard.tensor_data_base;
    for (gguf_tensor_info &t : shard.tensors) {
        t.source_shard_tensor_data_base = shard.tensor_data_base;
        t.physical_offset = checked_add_u64(
            shard.tensor_data_base, t.relative_offset, "GGUF tensor physical offset");
        const uint64_t tensor_end = checked_add_u64(t.physical_offset, t.bytes, "GGUF tensor extent");
        if (tensor_end > file_size) throw std::runtime_error("GGUF tensor points outside physical file: " + t.name);
        if (tensor_end > shard.physical_end) shard.physical_end = tensor_end;
    }
    return shard;
}

static bool has_any_split_metadata(const gguf_split_metadata &split) {
    return split.has_no || split.has_count || split.has_tensor_count;
}

static bool has_complete_split_metadata(const gguf_split_metadata &split) {
    return split.has_no && split.has_count && split.has_tensor_count;
}

static void append_unique_tensors(
        std::vector<gguf_tensor_info> &all,
        const gguf_shard_info &shard) {
    for (const gguf_tensor_info &t : shard.tensors) {
        for (const gguf_tensor_info &prior : all) {
            if (prior.name == t.name) {
                throw std::runtime_error("duplicate tensor across split GGUF shards: " + t.name);
            }
        }
        all.push_back(t);
    }
}

static std::vector<gguf_tensor_info> parse_concatenated_gguf(
        std::ifstream &in,
        uint64_t file_size,
        uint32_t &shard_count_out) {
    gguf_shard_info first = parse_gguf_shard(in, file_size, 0, 0);
    if (has_any_split_metadata(first.split) && !has_complete_split_metadata(first.split)) {
        throw std::runtime_error("incomplete concatenated split GGUF metadata in shard 0");
    }

    uint64_t split_count = 1;
    uint64_t expected_tensors = first.tensors.size();
    if (has_complete_split_metadata(first.split)) {
        split_count = first.split.count;
        expected_tensors = first.split.tensor_count;
        if (first.split.no != 0 || split_count == 0 || split_count > 16) {
            throw std::runtime_error("unsupported or invalid concatenated split GGUF metadata");
        }
    }

    std::vector<gguf_tensor_info> tensors;
    if (expected_tensors > (uint64_t)std::numeric_limits<size_t>::max()) {
        throw std::runtime_error("concatenated split GGUF tensor count is too large");
    }
    tensors.reserve((size_t)expected_tensors);
    append_unique_tensors(tensors, first);

    uint64_t shard_base = first.physical_end;
    for (uint64_t shard_index = 1; shard_index < split_count; ++shard_index) {
        gguf_shard_info shard = parse_gguf_shard(
            in, file_size, shard_base, (uint32_t)shard_index);
        if (!has_complete_split_metadata(shard.split) ||
            shard.split.no != shard_index ||
            shard.split.count != split_count ||
            shard.split.tensor_count != expected_tensors) {
            throw std::runtime_error("concatenated split GGUF shard metadata mismatch");
        }
        append_unique_tensors(tensors, shard);
        shard_base = shard.physical_end;
    }

    if (tensors.size() != expected_tensors || shard_base != file_size) {
        throw std::runtime_error("concatenated split GGUF tensor count or final size mismatch");
    }
    shard_count_out = (uint32_t)split_count;
    return tensors;
}

static void require_tensor_layout(
        const gguf_tensor_info &t,
        uint32_t type,
        uint64_t d0,
        uint64_t d1,
        uint64_t d2) {
    if (t.type != type || t.n_dims != 3 ||
        t.dims[0] != d0 || t.dims[1] != d1 || t.dims[2] != d2) {
        throw std::runtime_error("GGUF tensor layout mismatch: " + t.name);
    }
}

static void load_real_gguf_samples(
        const std::string &path,
        std::vector<ds4_block_iq1_s> &iq1,
        std::vector<ds4_block_q2_K> &q2,
        std::vector<real_sample> &samples,
        uint32_t &shard_count) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) throw std::runtime_error("failed to open GGUF input");
    const std::streamoff file_end = in.tellg();
    if (file_end < 24) throw std::runtime_error("GGUF input is too small");
    const uint64_t file_size = (uint64_t)file_end;
    const std::vector<gguf_tensor_info> tensors =
        parse_concatenated_gguf(in, file_size, shard_count);
    struct request {
        uint32_t layer;
        const char *part;
        uint32_t type;
        uint64_t d0;
        uint64_t d1;
        uint64_t d2;
    };
    const request requests[] = {
        {0,  "gate", 19, DS4_N_EMBD,   DS4_N_FF_EXP, DS4_N_EXPERT},
        {0,  "up",   19, DS4_N_EMBD,   DS4_N_FF_EXP, DS4_N_EXPERT},
        {0,  "down", 10, DS4_N_FF_EXP, DS4_N_EMBD,   DS4_N_EXPERT},
        {1,  "down", 10, DS4_N_FF_EXP, DS4_N_EMBD,   DS4_N_EXPERT},
        {2,  "down", 10, DS4_N_FF_EXP, DS4_N_EMBD,   DS4_N_EXPERT},
        {3,  "gate", 19, DS4_N_EMBD,   DS4_N_FF_EXP, DS4_N_EXPERT},
        {3,  "up",   19, DS4_N_EMBD,   DS4_N_FF_EXP, DS4_N_EXPERT},
        {3,  "down", 19, DS4_N_FF_EXP, DS4_N_EMBD,   DS4_N_EXPERT},
        {42, "gate", 19, DS4_N_EMBD,   DS4_N_FF_EXP, DS4_N_EXPERT},
        {42, "up",   19, DS4_N_EMBD,   DS4_N_FF_EXP, DS4_N_EXPERT},
        {42, "down", 19, DS4_N_FF_EXP, DS4_N_EMBD,   DS4_N_EXPERT},
    };

    for (const request &r : requests) {
        char name[96];
        std::snprintf(name, sizeof(name), "blk.%u.ffn_%s_exps.weight", r.layer, r.part);
        const gguf_tensor_info *t = find_tensor(tensors, name);
        if (!t) throw std::runtime_error(std::string("missing GGUF tensor: ") + name);
        require_tensor_layout(*t, r.type, r.d0, r.d1, r.d2);
        const uint64_t block_size = gguf_type_size(r.type);
        const uint64_t row_blocks = r.d0 / DS4_IQ1_QK_K;
        const uint64_t row_bytes = row_blocks * block_size;
        const uint64_t expert_bytes = r.d1 * row_bytes;
        const uint64_t blocks = r.d1 * row_blocks;
        const uint64_t tensor_bytes = checked_mul_u64(expert_bytes, r.d2, "sample tensor size");
        if (block_size == 0 || t->bytes != tensor_bytes) {
            throw std::runtime_error("GGUF tensor byte size mismatch: " + t->name);
        }
        const uint64_t src = t->physical_offset;

        real_sample s{};
        s.name = name;
        s.layer = r.layer;
        s.part = r.part;
        s.type = r.type;
        s.type_name = gguf_type_name(r.type);
        s.rows = r.d1;
        s.cols = r.d0;
        s.experts = r.d2;
        s.blocks = blocks;
        s.source_shard = t->source_shard;
        s.source_shard_count = shard_count;
        s.source_shard_physical_base = t->source_shard_physical_base;
        s.source_shard_tensor_data_base = t->source_shard_tensor_data_base;
        s.tensor_relative_offset = t->relative_offset;
        s.physical_offset = src;
        s.sample_bytes = expert_bytes;
        if (r.type == 19) {
            s.blocks_offset = iq1.size();
            iq1.resize(iq1.size() + (size_t)blocks);
            seek_absolute(in, src, "IQ1_S sample tensor");
            in.read((char *)(iq1.data() + s.blocks_offset), (std::streamsize)expert_bytes);
        } else if (r.type == 10) {
            s.blocks_offset = q2.size();
            q2.resize(q2.size() + (size_t)blocks);
            seek_absolute(in, src, "Q2_K sample tensor");
            in.read((char *)(q2.data() + s.blocks_offset), (std::streamsize)expert_bytes);
        } else {
            throw std::runtime_error("unsupported sample tensor type");
        }
        if (!in) throw std::runtime_error("failed to read GGUF tensor bytes: " + s.name);
        samples.push_back(s);
    }
}

__device__ static float dev_f16_to_f32(uint16_t v) {
    __half h;
    memcpy(&h, &v, sizeof(h));
    return __half2float(h);
}

__device__ __forceinline__ static int dev_get_int_b2(const uint8_t *p, int i) {
    const uint8_t *q = p + 4 * i;
    return (int)((uint32_t)q[0] | ((uint32_t)q[1] << 8) | ((uint32_t)q[2] << 16) | ((uint32_t)q[3] << 24));
}

__device__ __forceinline__ static int dev_get_int_b4(const int8_t *p, int i) {
    const uint8_t *q = (const uint8_t *)(p + 4 * i);
    return (int)((uint32_t)q[0] | ((uint32_t)q[1] << 8) | ((uint32_t)q[2] << 16) | ((uint32_t)q[3] << 24));
}

__device__ static float dev_dot_iq1_s_q8_1(const ds4_block_iq1_s *bq1, const ds4_block_q8_1 *bq8_1, int iqs) {
    const int qs_packed = dev_get_int_b2(bq1->qs, iqs);
    const uint8_t *qs = (const uint8_t *)&qs_packed;
    const int qh = bq1->qh[iqs];

    int sumi = 0;
#pragma unroll
    for (int l0 = 0; l0 < 8; l0 += 2) {
        const int grid = ds4_cuda_iq1s_grid_gpu[qs[l0 / 2] | (((qh >> (3 * (l0 / 2))) & 0x07) << 8)];
        const int grid0 = (grid >> 0) & 0x0F0F0F0F;
        const int grid1 = (grid >> 4) & 0x0F0F0F0F;
        const int u0 = dev_get_int_b4(bq8_1[iqs].qs, l0 + 0);
        const int u1 = dev_get_int_b4(bq8_1[iqs].qs, l0 + 1);
        sumi = __dp4a(grid0, u0, sumi);
        sumi = __dp4a(grid1, u1, sumi);
    }

    const float d1q = dev_f16_to_f32(bq1->d) * (float)(((qh >> 11) & 0x0E) + 1);
    const float delta = -1.0f + DS4_IQ1S_DELTA - (qh & 0x8000) * (2.0f * DS4_IQ1S_DELTA / 0x8000);
    const float d8 = dev_f16_to_f32((uint16_t)(bq8_1[iqs].ds & 0xffffu));
    const float s8 = dev_f16_to_f32((uint16_t)(bq8_1[iqs].ds >> 16));
    return d1q * (d8 * (float)sumi + s8 * delta);
}

__global__ static void iq1_s_dot_kernel(const ds4_block_iq1_s *w, const ds4_block_q8_1 *x, float *out, uint32_t nblocks) {
    const uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nblocks) return;
    float acc = 0.0f;
#pragma unroll
    for (int iqs = 0; iqs < 8; ++iqs) {
        acc += dev_dot_iq1_s_q8_1(w + i, x + (uint64_t)i * 8u, iqs);
    }
    out[i] = acc;
}

__device__ static float dev_dot_iq1_s_q8_K(
        const ds4_block_iq1_s *w,
        const ds4_block_q8_K *x) {
    float sum = 0.0f;
    const float d = dev_f16_to_f32(w->d) * x->d;
    for (uint32_t iqs = 0; iqs < 8u; ++iqs) {
        const uint32_t qh = w->qh[iqs];
        int sumi = 0;
        for (uint32_t g = 0; g < 4u; ++g) {
            const uint32_t index = (uint32_t)w->qs[iqs * 4u + g] |
                (((qh >> (3u * g)) & 7u) << 8u);
            const uint32_t grid = ds4_cuda_iq1s_grid_gpu[index];
            for (uint32_t lane = 0; lane < 8u; ++lane) {
                sumi += (int)((grid >> (4u * lane)) & 0x0fu) *
                    (int)x->qs[iqs * 32u + g * 8u + lane];
            }
        }
        const int sumq = x->bsums[iqs * 2u] + x->bsums[iqs * 2u + 1u];
        const float scale = (float)(((qh >> 11) & 0x0eu) + 1u);
        const float delta = -1.0f + DS4_IQ1S_DELTA -
            (qh & 0x8000u) * (2.0f * DS4_IQ1S_DELTA / 32768.0f);
        sum += scale * ((float)sumi + delta * (float)sumq);
    }
    return d * sum;
}

__global__ static void iq1_s_q8_K_dot_kernel(
        const ds4_block_iq1_s *w,
        const ds4_block_q8_K *x,
        float *out,
        uint32_t nblocks) {
    const uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < nblocks) out[i] = dev_dot_iq1_s_q8_K(w + i, x + i);
}

__device__ __forceinline__ static int dev_dot_q2_16(
        const uint8_t *q2,
        const int8_t *q8,
        int shift) {
    int sum = 0;
#pragma unroll
    for (int i = 0; i < 16; ++i) {
        sum += (int)((q2[i] >> shift) & 3u) * (int)q8[i];
    }
    return sum;
}

__device__ static float dev_dot_q2_K_q8_K(
        const ds4_block_q2_K *w,
        const ds4_block_q8_K *x) {
    const uint8_t *q2 = w->qs;
    const int8_t *q8 = x->qs;
    const uint8_t *sc = w->scales;
    int summs = 0;
    for (int j = 0; j < 16; ++j) summs += (int)x->bsums[j] * (int)(sc[j] >> 4);
    const float dall = x->d * dev_f16_to_f32(w->d);
    const float dmin = x->d * dev_f16_to_f32(w->dmin);
    int isum = 0;
    int is = 0;
    for (int k = 0; k < DS4_IQ1_QK_K / 128; ++k) {
        int shift = 0;
        for (int j = 0; j < 4; ++j) {
            int d = (int)(sc[is++] & 0x0fu);
            isum += d * dev_dot_q2_16(q2, q8, shift);
            d = (int)(sc[is++] & 0x0fu);
            isum += d * dev_dot_q2_16(q2 + 16, q8 + 16, shift);
            shift += 2;
            q8 += 32;
        }
        q2 += 32;
    }
    return dall * (float)isum - dmin * (float)summs;
}

__global__ static void q2_K_q8_K_dot_kernel(
        const ds4_block_q2_K *w,
        const ds4_block_q8_K *x,
        float *out,
        uint32_t nblocks) {
    const uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < nblocks) out[i] = dev_dot_q2_K_q8_K(w + i, x + i);
}

__global__ static void iq1_s_dequant_kernel(const ds4_block_iq1_s *w, float *out, uint32_t nblocks) {
    const uint32_t gid = blockIdx.x * blockDim.x + threadIdx.x;
    const uint32_t n = nblocks * DS4_IQ1_QK_K;
    if (gid >= n) return;
    const uint32_t b = gid / DS4_IQ1_QK_K;
    const uint32_t j = gid - b * DS4_IQ1_QK_K;
    const uint32_t iqs = j / 32u;
    const uint32_t j32 = j - iqs * 32u;
    const uint32_t g = j32 / 8u;
    const uint32_t lane = j32 - g * 8u;
    const ds4_block_iq1_s *xb = w + b;
    const uint32_t qh = xb->qh[iqs];
    const uint32_t grid = ds4_cuda_iq1s_grid_gpu[xb->qs[iqs * 4u + g] | (((qh >> (3u * g)) & 0x07u) << 8u)];
    const float q = (float)((grid >> (4u * lane)) & 0x0fu);
    const float d1q = dev_f16_to_f32(xb->d) * (float)(((qh >> 11) & 0x0E) + 1);
    const float delta = -1.0f + DS4_IQ1S_DELTA - (qh & 0x8000u) * (2.0f * DS4_IQ1S_DELTA / 0x8000);
    out[gid] = d1q * (q + delta);
}

static void fill_iq1(std::vector<ds4_block_iq1_s> &w) {
    uint32_t rng = 0x1a551101u;
    for (size_t b = 0; b < w.size(); ++b) {
        ds4_block_iq1_s &x = w[b];
        x.d = f32_to_f16_bits(0.0025f + 0.00001f * (float)(b % 97));
        for (uint32_t iqs = 0; iqs < 8; ++iqs) {
            uint16_t qh = 0;
            for (uint32_t g = 0; g < 4; ++g) {
                const uint16_t idx = (uint16_t)(xorshift32(rng) & 2047u);
                x.qs[iqs * 4u + g] = (uint8_t)(idx & 0xffu);
                qh |= (uint16_t)(((idx >> 8) & 7u) << (3u * g));
            }
            const uint16_t scale = (uint16_t)(((2u * ((xorshift32(rng) % 8u))) & 0x0eu) << 11);
            const uint16_t delta_sign = (xorshift32(rng) & 1u) ? 0x8000u : 0u;
            x.qh[iqs] = (uint16_t)(qh | scale | delta_sign);
        }
    }
}

static float deterministic_input(uint32_t i) {
    const int32_t a = (int32_t)((i * 37u + 17u) % 251u) - 125;
    const int32_t b = (int32_t)((i * 13u + 91u) % 127u) - 63;
    return 0.013f * (float)a + 0.003f * (float)b;
}

static void fill_q8_1(std::vector<ds4_block_q8_1> &x) {
    for (size_t b = 0; b < x.size(); ++b) {
        float vals[32];
        float amax = 0.0f;
        for (uint32_t i = 0; i < 32; ++i) {
            vals[i] = deterministic_input((uint32_t)(b * 32u + i));
            amax = fmaxf(amax, fabsf(vals[i]));
        }
        const float d = amax > 0.0f ? amax / 127.0f : 1.0f;
        int sum = 0;
        for (uint32_t i = 0; i < 32; ++i) {
            int q = (int)lrintf(vals[i] / d);
            if (q < -127) q = -127;
            if (q > 127) q = 127;
            x[b].qs[i] = (int8_t)q;
            sum += q;
        }
        x[b].ds = pack_half2_bits(d, d * (float)sum);
    }
}

static void fill_q8_K(std::vector<ds4_block_q8_K> &x) {
    for (size_t b = 0; b < x.size(); ++b) {
        float vals[DS4_IQ1_QK_K];
        float max = 0.0f;
        float amax = 0.0f;
        for (uint32_t i = 0; i < DS4_IQ1_QK_K; ++i) {
            vals[i] = deterministic_input((uint32_t)(b * DS4_IQ1_QK_K + i));
            const float av = fabsf(vals[i]);
            if (av > amax) { amax = av; max = vals[i]; }
        }
        const float iscale = amax > 0.0f ? -127.0f / max : 0.0f;
        x[b].d = iscale != 0.0f ? 1.0f / iscale : 0.0f;
        for (uint32_t i = 0; i < DS4_IQ1_QK_K; ++i) {
            int q = iscale != 0.0f ? (int)lrintf(iscale * vals[i]) : 0;
            if (q < -128) q = -128;
            if (q > 127) q = 127;
            x[b].qs[i] = (int8_t)q;
        }
        for (uint32_t i = 0; i < DS4_IQ1_QK_K / 16; ++i) {
            int sum = 0;
            for (uint32_t j = 0; j < 16; ++j) sum += x[b].qs[i * 16u + j];
            x[b].bsums[i] = (int16_t)sum;
        }
    }
}

static float cpu_dequant_one(const ds4_block_iq1_s &x, uint32_t j) {
    const uint32_t iqs = j / 32u;
    const uint32_t j32 = j - iqs * 32u;
    const uint32_t g = j32 / 8u;
    const uint32_t lane = j32 - g * 8u;
    const uint32_t qh = x.qh[iqs];
    const uint32_t grid = ds4_iq1s_grid_gpu_host[x.qs[iqs * 4u + g] | (((qh >> (3u * g)) & 0x07u) << 8u)];
    const float q = (float)((grid >> (4u * lane)) & 0x0fu);
    const float d1q = f16_bits_to_f32(x.d) * (float)(((qh >> 11) & 0x0E) + 1);
    const float delta = -1.0f + DS4_IQ1S_DELTA - (qh & 0x8000u) * (2.0f * DS4_IQ1S_DELTA / 0x8000);
    return d1q * (q + delta);
}

static float cpu_dot_one(const ds4_block_iq1_s &w, const ds4_block_q8_1 *x) {
    float acc = 0.0f;
    for (uint32_t iqs = 0; iqs < 8; ++iqs) {
        const float d8 = f16_bits_to_f32((uint16_t)(x[iqs].ds & 0xffffu));
        const float s8 = f16_bits_to_f32((uint16_t)(x[iqs].ds >> 16));
        const uint32_t qh = w.qh[iqs];
        const float d1q = f16_bits_to_f32(w.d) * (float)(((qh >> 11) & 0x0E) + 1);
        const float delta = -1.0f + DS4_IQ1S_DELTA - (qh & 0x8000u) * (2.0f * DS4_IQ1S_DELTA / 0x8000);
        int sumi = 0;
        for (uint32_t l0 = 0; l0 < 8; l0 += 2) {
            const uint32_t g = l0 / 2u;
            const uint32_t grid = ds4_iq1s_grid_gpu_host[w.qs[iqs * 4u + g] | (((qh >> (3u * g)) & 0x07u) << 8u)];
            for (uint32_t k = 0; k < 4; ++k) {
                const int q_even = (int)((grid >> (8u * k)) & 0x0fu);
                const int q_odd = (int)((grid >> (8u * k + 4u)) & 0x0fu);
                sumi += q_even * (int)x[iqs].qs[4u * (l0 + 0u) + k];
                sumi += q_odd * (int)x[iqs].qs[4u * (l0 + 1u) + k];
            }
        }
        acc += d1q * (d8 * (float)sumi + s8 * delta);
    }
    return acc;
}

static float cpu_dot_q8_K_one(
        const ds4_block_iq1_s &w,
        const ds4_block_q8_K &x) {
    float acc = 0.0f;
    for (uint32_t j = 0; j < DS4_IQ1_QK_K; ++j) {
        acc += cpu_dequant_one(w, j) * x.d * (float)x.qs[j];
    }
    return acc;
}

static float cpu_dot_q8_K_packed(
        const ds4_block_iq1_s &w,
        const ds4_block_q8_K &x) {
    const float d = f16_bits_to_f32(w.d) * x.d;
    float sum = 0.0f;
    for (uint32_t iqs = 0; iqs < 8u; ++iqs) {
        const uint32_t qh = w.qh[iqs];
        int sumi = 0;
        for (uint32_t g = 0; g < 4u; ++g) {
            const uint32_t index = (uint32_t)w.qs[iqs * 4u + g] |
                (((qh >> (3u * g)) & 7u) << 8u);
            const uint32_t grid = ds4_iq1s_grid_gpu_host[index];
            for (uint32_t lane = 0; lane < 8u; ++lane) {
                sumi += (int)((grid >> (4u * lane)) & 0x0fu) *
                    (int)x.qs[iqs * 32u + g * 8u + lane];
            }
        }
        const int sumq = x.bsums[iqs * 2u] + x.bsums[iqs * 2u + 1u];
        const float scale = (float)(((qh >> 11) & 0x0eu) + 1u);
        const float delta = -1.0f + DS4_IQ1S_DELTA -
            (qh & 0x8000u) * (2.0f * DS4_IQ1S_DELTA / 32768.0f);
        sum += scale * ((float)sumi + delta * (float)sumq);
    }
    return d * sum;
}

static int cpu_dot_q2_16(const uint8_t *q2, const int8_t *q8, int shift) {
    int sum = 0;
    for (int i = 0; i < 16; ++i) {
        sum += (int)((q2[i] >> shift) & 3u) * (int)q8[i];
    }
    return sum;
}

static float cpu_dot_q2_K_packed(
        const ds4_block_q2_K &w,
        const ds4_block_q8_K &x) {
    const uint8_t *q2 = w.qs;
    const int8_t *q8 = x.qs;
    const uint8_t *sc = w.scales;
    int summs = 0;
    for (int j = 0; j < 16; ++j) summs += (int)x.bsums[j] * (int)(sc[j] >> 4);
    const float dall = x.d * f16_bits_to_f32(w.d);
    const float dmin = x.d * f16_bits_to_f32(w.dmin);
    int isum = 0;
    int is = 0;
    for (int k = 0; k < DS4_IQ1_QK_K / 128; ++k) {
        int shift = 0;
        for (int j = 0; j < 4; ++j) {
            int d = (int)(sc[is++] & 0x0fu);
            isum += d * cpu_dot_q2_16(q2, q8, shift);
            d = (int)(sc[is++] & 0x0fu);
            isum += d * cpu_dot_q2_16(q2 + 16, q8 + 16, shift);
            shift += 2;
            q8 += 32;
        }
        q2 += 32;
    }
    return dall * (float)isum - dmin * (float)summs;
}

static std::vector<float> read_f32_file(const char *path) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) throw std::runtime_error(std::string("failed to open ") + path);
    const std::streamoff bytes = in.tellg();
    if (bytes <= 0 || (bytes % (std::streamoff)sizeof(float)) != 0) {
        throw std::runtime_error(std::string("expected non-empty f32 vector: ") + path);
    }
    std::vector<float> v((size_t)bytes / sizeof(float));
    in.seekg(0);
    in.read((char *)v.data(), bytes);
    if (!in) throw std::runtime_error(std::string("failed to read ") + path);
    return v;
}

static int correlate_outputs_main(int argc, char **argv) {
    if (argc != 6) {
        std::fprintf(stderr,
            "usage: ds4_iq1_s_bench --correlate-outputs <main.f32> <sidecar.f32> <layer:part:expert> <source_note>\n");
        return 2;
    }
    try {
        const std::vector<float> a = read_f32_file(argv[2]);
        const std::vector<float> b = read_f32_file(argv[3]);
        if (a.size() != b.size() || a.empty()) {
            throw std::runtime_error("correlation inputs must have identical non-zero f32 length");
        }
        long double dot = 0.0, aa = 0.0, bb = 0.0, sum_a = 0.0, sum_b = 0.0;
        long double diff2 = 0.0, max_abs = 0.0;
        for (size_t i = 0; i < a.size(); ++i) {
            dot += (long double)a[i] * (long double)b[i];
            aa += (long double)a[i] * (long double)a[i];
            bb += (long double)b[i] * (long double)b[i];
            sum_a += a[i];
            sum_b += b[i];
            const long double d = (long double)b[i] - (long double)a[i];
            diff2 += d * d;
            if (fabsl(d) > max_abs) max_abs = fabsl(d);
        }
        const long double mean_a = sum_a / (long double)a.size();
        const long double mean_b = sum_b / (long double)b.size();
        long double cov = 0.0, var_a = 0.0, var_b = 0.0;
        for (size_t i = 0; i < a.size(); ++i) {
            const long double da = (long double)a[i] - mean_a;
            const long double db = (long double)b[i] - mean_b;
            cov += da * db;
            var_a += da * da;
            var_b += db * db;
        }
        const long double cosine = (aa > 0.0 && bb > 0.0) ? dot / sqrtl(aa * bb) : 0.0;
        const long double pearson = (var_a > 0.0 && var_b > 0.0) ? cov / sqrtl(var_a * var_b) : 0.0;
        const long double rel_l2 = aa > 0.0 ? sqrtl(diff2 / aa) : 0.0;
        std::printf("{\n");
        std::printf("  \"benchmark\": \"ds4_iq1_s_bench\",\n");
        std::printf("  \"mode\": \"cross_quant_checkpoint_correlation\",\n");
        std::printf("  \"metadata\": \"%s\",\n", argv[4]);
        std::printf("  \"source_note\": \"%s\",\n", argv[5]);
        std::printf("  \"values\": %llu,\n", (unsigned long long)a.size());
        std::printf("  \"cosine\": %.17g,\n", (double)cosine);
        std::printf("  \"pearson\": %.17g,\n", (double)pearson);
        std::printf("  \"relative_l2_error\": %.17g,\n", (double)rel_l2);
        std::printf("  \"max_abs_error\": %.17g,\n", (double)max_abs);
        std::printf("  \"pass\": true\n");
        std::printf("}\n");
        return 0;
    } catch (const std::exception &e) {
        std::fprintf(stderr, "correlation failed: %s\n", e.what());
        return 2;
    }
}

static double elapsed_ms(cudaEvent_t a, cudaEvent_t b) {
    float ms = 0.0f;
    die_cuda(cudaEventElapsedTime(&ms, a, b), "cudaEventElapsedTime");
    return (double)ms;
}

static double bench_copy(void *dst, const void *src, size_t bytes, int iters) {
    cudaEvent_t a, b;
    die_cuda(cudaEventCreate(&a), "cudaEventCreate");
    die_cuda(cudaEventCreate(&b), "cudaEventCreate");
    die_cuda(cudaEventRecord(a), "cudaEventRecord");
    for (int i = 0; i < iters; ++i) {
        die_cuda(cudaMemcpyAsync(dst, src, bytes, cudaMemcpyHostToDevice), "cudaMemcpyAsync H2D");
    }
    die_cuda(cudaEventRecord(b), "cudaEventRecord");
    die_cuda(cudaEventSynchronize(b), "cudaEventSynchronize");
    const double ms = elapsed_ms(a, b) / (double)iters;
    die_cuda(cudaEventDestroy(a), "cudaEventDestroy");
    die_cuda(cudaEventDestroy(b), "cudaEventDestroy");
    return ms;
}

template <typename Fn>
static double bench_kernel(Fn launch, int iters) {
    cudaEvent_t a, b;
    die_cuda(cudaEventCreate(&a), "cudaEventCreate");
    die_cuda(cudaEventCreate(&b), "cudaEventCreate");
    die_cuda(cudaEventRecord(a), "cudaEventRecord");
    for (int i = 0; i < iters; ++i) launch();
    die_cuda(cudaEventRecord(b), "cudaEventRecord");
    die_cuda(cudaEventSynchronize(b), "cudaEventSynchronize");
    const double ms = elapsed_ms(a, b) / (double)iters;
    die_cuda(cudaEventDestroy(a), "cudaEventDestroy");
    die_cuda(cudaEventDestroy(b), "cudaEventDestroy");
    return ms;
}

int main(int argc, char **argv) {
    if (argc > 1 && std::strcmp(argv[1], "--correlate-outputs") == 0) {
        return correlate_outputs_main(argc, argv);
    }

    int iters = 200;
    uint32_t nblocks = 2u * (DS4_N_FF_EXP * (DS4_N_EMBD / DS4_IQ1_QK_K)) +
        DS4_N_EMBD * (DS4_N_FF_EXP / DS4_IQ1_QK_K);
    if (argc > 1) iters = std::atoi(argv[1]);
    if (argc > 2) nblocks = (uint32_t)std::strtoul(argv[2], nullptr, 10);
    const char *iq1_path = argc > 3 ? argv[3] : nullptr;
    const bool real_gguf = iq1_path && ends_with_ci(iq1_path, ".gguf");
    if (iters <= 0 || nblocks == 0) {
        std::fprintf(stderr, "usage: ds4_iq1_s_bench [iters] [iq1_blocks] [iq1_blocks.bin|sidecar.gguf]\n");
        return 2;
    }

    int dev = 0;
    cudaDeviceProp prop{};
    die_cuda(cudaGetDevice(&dev), "cudaGetDevice");
    die_cuda(cudaGetDeviceProperties(&prop, dev), "cudaGetDeviceProperties");

    const uint64_t current_gate_row = (uint64_t)(DS4_N_EMBD / 256u) * 66u;
    const uint64_t current_down_row = (uint64_t)(DS4_N_FF_EXP / 256u) * 84u;
    const uint64_t current_gate_expert = (uint64_t)DS4_N_FF_EXP * current_gate_row;
    const uint64_t current_down_expert = (uint64_t)DS4_N_EMBD * current_down_row;
    const uint64_t current_expert_bytes = current_gate_expert * 2u + current_down_expert;

    const uint64_t iq1_gate_row = (uint64_t)(DS4_N_EMBD / 256u) * sizeof(ds4_block_iq1_s);
    const uint64_t iq1_down_row = (uint64_t)(DS4_N_FF_EXP / 256u) * sizeof(ds4_block_iq1_s);
    const uint64_t iq1_gate_expert = (uint64_t)DS4_N_FF_EXP * iq1_gate_row;
    const uint64_t iq1_down_expert = (uint64_t)DS4_N_EMBD * iq1_down_row;
    const uint64_t iq1_expert_bytes = iq1_gate_expert * 2u + iq1_down_expert;

    std::vector<real_sample> real_samples;
    std::vector<ds4_block_iq1_s> h_w;
    std::vector<ds4_block_q2_K> h_q2;
    uint32_t real_gguf_shards = 0;
    if (real_gguf) {
        try {
            load_real_gguf_samples(
                iq1_path, h_w, h_q2, real_samples, real_gguf_shards);
        } catch (const std::exception &e) {
            std::fprintf(stderr, "GGUF sample load failed: %s\n", e.what());
            return 2;
        }
        if (h_w.empty() || h_q2.empty()) {
            std::fprintf(stderr, "GGUF sample load produced incomplete IQ1/Q2 coverage\n");
            return 2;
        }
        nblocks = (uint32_t)h_w.size();
    } else {
        h_w.resize(nblocks);
    }
    std::vector<ds4_block_q8_1> h_x((uint64_t)nblocks * 8u);
    std::vector<ds4_block_q8_K> h_xk(nblocks);
    std::vector<ds4_block_q8_K> h_xk_q2(h_q2.size());
    if (iq1_path && !real_gguf) {
        std::ifstream in(iq1_path, std::ios::binary | std::ios::ate);
        const std::streamoff expected =
            (std::streamoff)(h_w.size() * sizeof(h_w[0]));
        if (!in || in.tellg() != expected) {
            std::fprintf(stderr,
                         "IQ1_S input must contain exactly %lld bytes\n",
                         (long long)expected);
            return 2;
        }
        in.seekg(0);
        in.read((char *)h_w.data(), expected);
        if (!in) {
            std::fprintf(stderr, "failed to read IQ1_S input\n");
            return 2;
        }
    } else {
        if (!real_gguf) fill_iq1(h_w);
    }
    fill_q8_1(h_x);
    fill_q8_K(h_xk);
    fill_q8_K(h_xk_q2);

    ds4_block_iq1_s *d_w = nullptr;
    ds4_block_q2_K *d_q2 = nullptr;
    ds4_block_q8_1 *d_x = nullptr;
    ds4_block_q8_K *d_xk = nullptr;
    ds4_block_q8_K *d_xk_q2 = nullptr;
    float *d_dot = nullptr;
    float *d_dotk = nullptr;
    float *d_dotq2 = nullptr;
    float *d_deq = nullptr;
    die_cuda(cudaMalloc(&d_w, h_w.size() * sizeof(h_w[0])), "cudaMalloc d_w");
    if (!h_q2.empty()) die_cuda(cudaMalloc(&d_q2, h_q2.size() * sizeof(h_q2[0])), "cudaMalloc d_q2");
    die_cuda(cudaMalloc(&d_x, h_x.size() * sizeof(h_x[0])), "cudaMalloc d_x");
    die_cuda(cudaMalloc(&d_xk, h_xk.size() * sizeof(h_xk[0])), "cudaMalloc d_xk");
    if (!h_xk_q2.empty()) die_cuda(cudaMalloc(&d_xk_q2, h_xk_q2.size() * sizeof(h_xk_q2[0])), "cudaMalloc d_xk_q2");
    die_cuda(cudaMalloc(&d_dot, h_w.size() * sizeof(float)), "cudaMalloc d_dot");
    die_cuda(cudaMalloc(&d_dotk, h_w.size() * sizeof(float)), "cudaMalloc d_dotk");
    if (!h_q2.empty()) die_cuda(cudaMalloc(&d_dotq2, h_q2.size() * sizeof(float)), "cudaMalloc d_dotq2");
    die_cuda(cudaMalloc(&d_deq, (uint64_t)nblocks * DS4_IQ1_QK_K * sizeof(float)), "cudaMalloc d_deq");
    die_cuda(cudaMemcpy(d_w, h_w.data(), h_w.size() * sizeof(h_w[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_w");
    if (!h_q2.empty()) die_cuda(cudaMemcpy(d_q2, h_q2.data(), h_q2.size() * sizeof(h_q2[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_q2");
    die_cuda(cudaMemcpy(d_x, h_x.data(), h_x.size() * sizeof(h_x[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_x");
    die_cuda(cudaMemcpy(d_xk, h_xk.data(), h_xk.size() * sizeof(h_xk[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_xk");
    if (!h_xk_q2.empty()) die_cuda(cudaMemcpy(d_xk_q2, h_xk_q2.data(), h_xk_q2.size() * sizeof(h_xk_q2[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_xk_q2");

    const dim3 dot_block(128);
    const dim3 dot_grid((nblocks + dot_block.x - 1u) / dot_block.x);
    const dim3 q2_grid(((uint32_t)h_q2.size() + dot_block.x - 1u) / dot_block.x);
    const uint32_t deq_n = nblocks * DS4_IQ1_QK_K;
    const dim3 deq_block(256);
    const dim3 deq_grid((deq_n + deq_block.x - 1u) / deq_block.x);

    iq1_s_dot_kernel<<<dot_grid, dot_block>>>(d_w, d_x, d_dot, nblocks);
    die_cuda(cudaGetLastError(), "iq1_s_dot_kernel");
    iq1_s_q8_K_dot_kernel<<<dot_grid, dot_block>>>(d_w, d_xk, d_dotk, nblocks);
    die_cuda(cudaGetLastError(), "iq1_s_q8_K_dot_kernel");
    if (!h_q2.empty()) {
        q2_K_q8_K_dot_kernel<<<q2_grid, dot_block>>>(
            d_q2, d_xk_q2, d_dotq2, (uint32_t)h_q2.size());
        die_cuda(cudaGetLastError(), "q2_K_q8_K_dot_kernel");
    }
    iq1_s_dequant_kernel<<<deq_grid, deq_block>>>(d_w, d_deq, nblocks);
    die_cuda(cudaGetLastError(), "iq1_s_dequant_kernel");
    die_cuda(cudaDeviceSynchronize(), "cudaDeviceSynchronize warmup");

    const size_t check_blocks = real_gguf ? h_w.size() : (h_w.size() < 256 ? h_w.size() : 256);
    std::vector<float> gpu_dot(check_blocks);
    std::vector<float> gpu_dotk(check_blocks);
    std::vector<float> gpu_dotq2(h_q2.size());
    std::vector<float> gpu_deq(check_blocks * DS4_IQ1_QK_K);
    die_cuda(cudaMemcpy(gpu_dot.data(), d_dot, gpu_dot.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_dot");
    die_cuda(cudaMemcpy(gpu_dotk.data(), d_dotk, gpu_dotk.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_dotk");
    if (!gpu_dotq2.empty()) die_cuda(cudaMemcpy(gpu_dotq2.data(), d_dotq2, gpu_dotq2.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_dotq2");
    die_cuda(cudaMemcpy(gpu_deq.data(), d_deq, gpu_deq.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_deq");

    double dot_max_abs = 0.0;
    double dot_q8_K_max_abs = 0.0;
    double dot_q8_K_packed_max_abs = 0.0;
    double dot_q8_K_worst_gpu = 0.0;
    double dot_q8_K_worst_ref = 0.0;
    size_t dot_q8_K_worst_block = 0;
    double dot_q2_K_max_abs = 0.0;
    double dot_q2_K_worst_gpu = 0.0;
    double dot_q2_K_worst_ref = 0.0;
    size_t dot_q2_K_worst_block = 0;
    double deq_max_abs = 0.0;
    for (size_t b = 0; b < check_blocks; ++b) {
        const double ref = (double)cpu_dot_one(h_w[b], h_x.data() + b * 8u);
        dot_max_abs = fmax(dot_max_abs, fabs((double)gpu_dot[b] - ref));
        const double refk = (double)cpu_dot_q8_K_one(h_w[b], h_xk[b]);
        const double packedk = (double)cpu_dot_q8_K_packed(h_w[b], h_xk[b]);
        const double errk = fabs((double)gpu_dotk[b] - refk);
        if (errk > dot_q8_K_max_abs) {
            dot_q8_K_max_abs = errk;
            dot_q8_K_worst_gpu = gpu_dotk[b];
            dot_q8_K_worst_ref = refk;
            dot_q8_K_worst_block = b;
        }
        dot_q8_K_packed_max_abs = fmax(dot_q8_K_packed_max_abs,
                                      fabs(packedk - refk));
        for (uint32_t j = 0; j < DS4_IQ1_QK_K; ++j) {
            const double r = (double)cpu_dequant_one(h_w[b], j);
            deq_max_abs = fmax(deq_max_abs, fabs((double)gpu_deq[b * DS4_IQ1_QK_K + j] - r));
        }
    }
    for (size_t b = 0; b < h_q2.size(); ++b) {
        const double refq2 = (double)cpu_dot_q2_K_packed(h_q2[b], h_xk_q2[b]);
        const double errq2 = fabs((double)gpu_dotq2[b] - refq2);
        if (errq2 > dot_q2_K_max_abs) {
            dot_q2_K_max_abs = errq2;
            dot_q2_K_worst_gpu = gpu_dotq2[b];
            dot_q2_K_worst_ref = refq2;
            dot_q2_K_worst_block = b;
        }
    }

    std::vector<double> real_sample_max_abs(real_samples.size(), 0.0);
    for (size_t si = 0; si < real_samples.size(); ++si) {
        const real_sample &s = real_samples[si];
        for (uint64_t b = 0; b < s.blocks; ++b) {
            const size_t bi = (size_t)(s.blocks_offset + b);
            double err = 0.0;
            if (s.type == 19) {
                const double ref = (double)cpu_dot_q8_K_packed(h_w[bi], h_xk[bi]);
                err = fabs((double)gpu_dotk[bi] - ref);
            } else {
                const double ref = (double)cpu_dot_q2_K_packed(h_q2[bi], h_xk_q2[bi]);
                err = fabs((double)gpu_dotq2[bi] - ref);
            }
            if (err > real_sample_max_abs[si]) real_sample_max_abs[si] = err;
        }
    }

    void *h_current = nullptr, *h_iq1 = nullptr, *d_current = nullptr, *d_iq1 = nullptr;
    die_cuda(cudaHostAlloc(&h_current, (size_t)current_expert_bytes, cudaHostAllocDefault), "cudaHostAlloc current");
    die_cuda(cudaHostAlloc(&h_iq1, (size_t)iq1_expert_bytes, cudaHostAllocDefault), "cudaHostAlloc iq1");
    die_cuda(cudaMalloc(&d_current, (size_t)current_expert_bytes), "cudaMalloc current");
    die_cuda(cudaMalloc(&d_iq1, (size_t)iq1_expert_bytes), "cudaMalloc iq1");
    std::memset(h_current, 0x5a, (size_t)current_expert_bytes);
    std::memset(h_iq1, 0xa5, (size_t)iq1_expert_bytes);

    const double h2d_current_ms = bench_copy(d_current, h_current, (size_t)current_expert_bytes, iters);
    const double h2d_iq1_ms = bench_copy(d_iq1, h_iq1, (size_t)iq1_expert_bytes, iters);
    const double dot_ms = bench_kernel([&]() {
        iq1_s_dot_kernel<<<dot_grid, dot_block>>>(d_w, d_x, d_dot, nblocks);
    }, iters);
    die_cuda(cudaGetLastError(), "iq1_s_dot_kernel bench");
    const double dot_q8_K_ms = bench_kernel([&]() {
        iq1_s_q8_K_dot_kernel<<<dot_grid, dot_block>>>(
            d_w, d_xk, d_dotk, nblocks);
    }, iters);
    die_cuda(cudaGetLastError(), "iq1_s_q8_K_dot_kernel bench");
    const double deq_ms = bench_kernel([&]() {
        iq1_s_dequant_kernel<<<deq_grid, deq_block>>>(d_w, d_deq, nblocks);
    }, iters);
    die_cuda(cudaGetLastError(), "iq1_s_dequant_kernel bench");

    const bool pass = dot_max_abs <= 1.0e-4 &&
        dot_q8_K_max_abs <= 1.0e-4 &&
        dot_q2_K_max_abs <= 1.0e-4 &&
        deq_max_abs <= 1.0e-6;
    std::printf("{\n");
    std::printf("  \"benchmark\": \"ds4_iq1_s_bench\",\n");
    std::printf("  \"weight_source\": \"%s\",\n",
                real_gguf ? "real_gguf_representative_ranges" :
                (iq1_path ? "real_flat_iq1_blocks" : "deterministic_synthetic"));
    std::printf("  \"gguf_shards\": %u,\n", real_gguf_shards);
    std::printf("  \"provenance\": {\"repo\":\"ggml-org/llama.cpp\",\"commit\":\"b15ca938ad00aa6b3ee6c2edda7363fd02826b18\",\"files\":[\"ggml/src/ggml-common.h\",\"ggml/src/ggml-cuda/vecdotq.cuh\"]},\n");
    std::printf("  \"device\": {\"index\":%d,\"name\":\"%s\",\"sm\":%d%d},\n", dev, prop.name, prop.major, prop.minor);
    std::printf("  \"ds4_geometry\": {\"n_embd\":%u,\"n_ff_exp\":%u,\"n_expert\":%u,\"current_bytes_per_3x256\":216,\"iq1_s_bytes_per_3x256\":150,\n", DS4_N_EMBD, DS4_N_FF_EXP, DS4_N_EXPERT);
    std::printf("    \"current_expert_bytes\":%llu,\"iq1_s_expert_bytes\":%llu,\"current_gate_or_up_expert_bytes\":%llu,\"current_down_expert_bytes\":%llu,\"iq1_s_gate_or_up_expert_bytes\":%llu,\"iq1_s_down_expert_bytes\":%llu},\n",
        (unsigned long long)current_expert_bytes, (unsigned long long)iq1_expert_bytes,
        (unsigned long long)current_gate_expert, (unsigned long long)current_down_expert,
        (unsigned long long)iq1_gate_expert, (unsigned long long)iq1_down_expert);
    std::printf("  \"validation\": {\"checked_blocks\":%llu,\"dot_q8_1_max_abs\":%.9g,\"dot_q8_K_max_abs\":%.9g,\"dot_q8_K_packed_cpu_max_abs\":%.9g,\"dot_q8_K_worst_block\":%llu,\"dot_q8_K_worst_gpu\":%.9g,\"dot_q8_K_worst_ref\":%.9g,\"dot_q2_K_max_abs\":%.9g,\"dot_q2_K_worst_block\":%llu,\"dot_q2_K_worst_gpu\":%.9g,\"dot_q2_K_worst_ref\":%.9g,\"dot_tol_abs\":1e-4,\"dequant_max_abs\":%.9g,\"dequant_tol_abs\":1e-6,\"pass\":%s},\n",
        (unsigned long long)check_blocks, dot_max_abs, dot_q8_K_max_abs,
        dot_q8_K_packed_max_abs,
        (unsigned long long)dot_q8_K_worst_block,
        dot_q8_K_worst_gpu, dot_q8_K_worst_ref,
        dot_q2_K_max_abs,
        (unsigned long long)dot_q2_K_worst_block,
        dot_q2_K_worst_gpu, dot_q2_K_worst_ref,
        deq_max_abs, pass ? "true" : "false");
    std::printf("  \"real_samples\": [");
    for (size_t i = 0; i < real_samples.size(); ++i) {
        const real_sample &s = real_samples[i];
        std::printf("%s{\"tensor\":\"%s\",\"layer\":%u,\"part\":\"%s\",\"type\":\"%s\",\"expert\":0,\"rows\":%llu,\"cols\":%llu,\"experts\":%llu,\"blocks\":%llu,\"source_shard\":%u,\"source_shard_count\":%u,\"source_shard_physical_base\":%llu,\"source_shard_tensor_data_base\":%llu,\"tensor_relative_offset\":%llu,\"physical_offset\":%llu,\"sample_bytes\":%llu,\"dot_max_abs\":%.9g,\"dot_tol_abs\":1e-4,\"pass\":%s}",
            i ? "," : "",
            s.name.c_str(), s.layer, s.part, s.type_name,
            (unsigned long long)s.rows,
            (unsigned long long)s.cols,
            (unsigned long long)s.experts,
            (unsigned long long)s.blocks,
            s.source_shard,
            s.source_shard_count,
            (unsigned long long)s.source_shard_physical_base,
            (unsigned long long)s.source_shard_tensor_data_base,
            (unsigned long long)s.tensor_relative_offset,
            (unsigned long long)s.physical_offset,
            (unsigned long long)s.sample_bytes,
            real_sample_max_abs[i],
            real_sample_max_abs[i] <= 1.0e-4 ? "true" : "false");
    }
    std::printf("],\n");
    std::printf("  \"measurements\": {\"iters\":%d,\"iq1_blocks\":%u,\"h2d_pinned_current_ms\":%.6f,\"h2d_pinned_iq1_s_ms\":%.6f,\"dot_q8_1_kernel_ms\":%.6f,\"dot_q8_K_kernel_ms\":%.6f,\"dequant_kernel_ms\":%.6f,\n",
        iters, nblocks, h2d_current_ms, h2d_iq1_ms, dot_ms,
        dot_q8_K_ms, deq_ms);
    std::printf("    \"h2d_current_gib_s\":%.6f,\"h2d_iq1_s_gib_s\":%.6f,\"dot_q8_1_blocks_per_s\":%.3f,\"dot_q8_K_blocks_per_s\":%.3f,\"dequant_values_per_s\":%.3f}\n",
        ((double)current_expert_bytes / (1024.0 * 1024.0 * 1024.0)) / (h2d_current_ms / 1000.0),
        ((double)iq1_expert_bytes / (1024.0 * 1024.0 * 1024.0)) / (h2d_iq1_ms / 1000.0),
        (double)nblocks / (dot_ms / 1000.0),
        (double)nblocks / (dot_q8_K_ms / 1000.0),
        (double)deq_n / (deq_ms / 1000.0));
    std::printf("}\n");

    cudaFreeHost(h_current);
    cudaFreeHost(h_iq1);
    cudaFree(d_current);
    cudaFree(d_iq1);
    cudaFree(d_deq);
    if (d_dotq2) cudaFree(d_dotq2);
    cudaFree(d_dotk);
    cudaFree(d_dot);
    if (d_xk_q2) cudaFree(d_xk_q2);
    cudaFree(d_xk);
    cudaFree(d_x);
    if (d_q2) cudaFree(d_q2);
    cudaFree(d_w);
    return pass ? 0 : 1;
}
