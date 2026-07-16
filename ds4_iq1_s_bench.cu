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
    uint32_t ds;
    int8_t qs[32];
} ds4_block_q8_1;

typedef struct {
    float d;
    int8_t qs[DS4_IQ1_QK_K];
    int16_t bsums[DS4_IQ1_QK_K / 16];
} ds4_block_q8_K;

static_assert(sizeof(ds4_block_iq1_s) == 50, "IQ1_S must be 50 bytes per 256 weights");
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
    int iters = 200;
    uint32_t nblocks = 2u * (DS4_N_FF_EXP * (DS4_N_EMBD / DS4_IQ1_QK_K)) +
        DS4_N_EMBD * (DS4_N_FF_EXP / DS4_IQ1_QK_K);
    if (argc > 1) iters = std::atoi(argv[1]);
    if (argc > 2) nblocks = (uint32_t)std::strtoul(argv[2], nullptr, 10);
    const char *iq1_path = argc > 3 ? argv[3] : nullptr;
    if (iters <= 0 || nblocks == 0) {
        std::fprintf(stderr, "usage: ds4_iq1_s_bench [iters] [iq1_blocks]\n");
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

    std::vector<ds4_block_iq1_s> h_w(nblocks);
    std::vector<ds4_block_q8_1> h_x((uint64_t)nblocks * 8u);
    std::vector<ds4_block_q8_K> h_xk(nblocks);
    if (iq1_path) {
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
        fill_iq1(h_w);
    }
    fill_q8_1(h_x);
    fill_q8_K(h_xk);

    ds4_block_iq1_s *d_w = nullptr;
    ds4_block_q8_1 *d_x = nullptr;
    ds4_block_q8_K *d_xk = nullptr;
    float *d_dot = nullptr;
    float *d_dotk = nullptr;
    float *d_deq = nullptr;
    die_cuda(cudaMalloc(&d_w, h_w.size() * sizeof(h_w[0])), "cudaMalloc d_w");
    die_cuda(cudaMalloc(&d_x, h_x.size() * sizeof(h_x[0])), "cudaMalloc d_x");
    die_cuda(cudaMalloc(&d_xk, h_xk.size() * sizeof(h_xk[0])), "cudaMalloc d_xk");
    die_cuda(cudaMalloc(&d_dot, h_w.size() * sizeof(float)), "cudaMalloc d_dot");
    die_cuda(cudaMalloc(&d_dotk, h_w.size() * sizeof(float)), "cudaMalloc d_dotk");
    die_cuda(cudaMalloc(&d_deq, (uint64_t)nblocks * DS4_IQ1_QK_K * sizeof(float)), "cudaMalloc d_deq");
    die_cuda(cudaMemcpy(d_w, h_w.data(), h_w.size() * sizeof(h_w[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_w");
    die_cuda(cudaMemcpy(d_x, h_x.data(), h_x.size() * sizeof(h_x[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_x");
    die_cuda(cudaMemcpy(d_xk, h_xk.data(), h_xk.size() * sizeof(h_xk[0]), cudaMemcpyHostToDevice), "cudaMemcpy d_xk");

    const dim3 dot_block(128);
    const dim3 dot_grid((nblocks + dot_block.x - 1u) / dot_block.x);
    const uint32_t deq_n = nblocks * DS4_IQ1_QK_K;
    const dim3 deq_block(256);
    const dim3 deq_grid((deq_n + deq_block.x - 1u) / deq_block.x);

    iq1_s_dot_kernel<<<dot_grid, dot_block>>>(d_w, d_x, d_dot, nblocks);
    die_cuda(cudaGetLastError(), "iq1_s_dot_kernel");
    iq1_s_q8_K_dot_kernel<<<dot_grid, dot_block>>>(d_w, d_xk, d_dotk, nblocks);
    die_cuda(cudaGetLastError(), "iq1_s_q8_K_dot_kernel");
    iq1_s_dequant_kernel<<<deq_grid, deq_block>>>(d_w, d_deq, nblocks);
    die_cuda(cudaGetLastError(), "iq1_s_dequant_kernel");
    die_cuda(cudaDeviceSynchronize(), "cudaDeviceSynchronize warmup");

    const size_t check_blocks = h_w.size() < 256 ? h_w.size() : 256;
    std::vector<float> gpu_dot(check_blocks);
    std::vector<float> gpu_dotk(check_blocks);
    std::vector<float> gpu_deq(check_blocks * DS4_IQ1_QK_K);
    die_cuda(cudaMemcpy(gpu_dot.data(), d_dot, gpu_dot.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_dot");
    die_cuda(cudaMemcpy(gpu_dotk.data(), d_dotk, gpu_dotk.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_dotk");
    die_cuda(cudaMemcpy(gpu_deq.data(), d_deq, gpu_deq.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_deq");

    double dot_max_abs = 0.0;
    double dot_q8_K_max_abs = 0.0;
    double dot_q8_K_packed_max_abs = 0.0;
    double dot_q8_K_worst_gpu = 0.0;
    double dot_q8_K_worst_ref = 0.0;
    size_t dot_q8_K_worst_block = 0;
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
        dot_q8_K_max_abs <= 1.0e-4 && deq_max_abs <= 1.0e-6;
    std::printf("{\n");
    std::printf("  \"benchmark\": \"ds4_iq1_s_bench\",\n");
    std::printf("  \"weight_source\": \"%s\",\n",
                iq1_path ? "real_gguf_range" : "deterministic_synthetic");
    std::printf("  \"provenance\": {\"repo\":\"ggml-org/llama.cpp\",\"commit\":\"b15ca938ad00aa6b3ee6c2edda7363fd02826b18\",\"files\":[\"ggml/src/ggml-common.h\",\"ggml/src/ggml-cuda/vecdotq.cuh\"]},\n");
    std::printf("  \"device\": {\"index\":%d,\"name\":\"%s\",\"sm\":%d%d},\n", dev, prop.name, prop.major, prop.minor);
    std::printf("  \"ds4_geometry\": {\"n_embd\":%u,\"n_ff_exp\":%u,\"n_expert\":%u,\"current_bytes_per_3x256\":216,\"iq1_s_bytes_per_3x256\":150,\n", DS4_N_EMBD, DS4_N_FF_EXP, DS4_N_EXPERT);
    std::printf("    \"current_expert_bytes\":%llu,\"iq1_s_expert_bytes\":%llu,\"current_gate_or_up_expert_bytes\":%llu,\"current_down_expert_bytes\":%llu,\"iq1_s_gate_or_up_expert_bytes\":%llu,\"iq1_s_down_expert_bytes\":%llu},\n",
        (unsigned long long)current_expert_bytes, (unsigned long long)iq1_expert_bytes,
        (unsigned long long)current_gate_expert, (unsigned long long)current_down_expert,
        (unsigned long long)iq1_gate_expert, (unsigned long long)iq1_down_expert);
    std::printf("  \"validation\": {\"checked_blocks\":%llu,\"dot_q8_1_max_abs\":%.9g,\"dot_q8_K_max_abs\":%.9g,\"dot_q8_K_packed_cpu_max_abs\":%.9g,\"dot_q8_K_worst_block\":%llu,\"dot_q8_K_worst_gpu\":%.9g,\"dot_q8_K_worst_ref\":%.9g,\"dot_tol_abs\":1e-4,\"dequant_max_abs\":%.9g,\"dequant_tol_abs\":1e-6,\"pass\":%s},\n",
        (unsigned long long)check_blocks, dot_max_abs, dot_q8_K_max_abs,
        dot_q8_K_packed_max_abs,
        (unsigned long long)dot_q8_K_worst_block,
        dot_q8_K_worst_gpu, dot_q8_K_worst_ref,
        deq_max_abs, pass ? "true" : "false");
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
    cudaFree(d_dotk);
    cudaFree(d_dot);
    cudaFree(d_xk);
    cudaFree(d_x);
    cudaFree(d_w);
    return pass ? 0 : 1;
}
