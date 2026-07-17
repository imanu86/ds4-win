/*
 * Standalone Q1_0 CUDA synthetic benchmark.
 *
 * Validates the 128-value / 18-byte Q1_0 layout against one 256-value Q8_K
 * activation block. Q1_0 polarity is bit 1 => +d and bit 0 => -d.
 *
 * This file intentionally does not include or modify ds4.c/ds4_cuda.cu.
 */

#include <cuda_fp16.h>
#include <cuda_runtime.h>

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <vector>

#define DS4_Q1_0_QK 128u
#define DS4_Q8_K_QK 256u
#define DS4_GUARD_BYTES 32u

typedef struct {
    uint16_t d;
    uint8_t qs[DS4_Q1_0_QK / 8u];
} ds4_block_q1_0;

typedef struct {
    float d;
    int8_t qs[DS4_Q8_K_QK];
    int16_t bsums[DS4_Q8_K_QK / 16u];
} ds4_block_q8_K;

typedef struct {
    uint8_t pre[DS4_GUARD_BYTES];
    ds4_block_q1_0 block;
    uint8_t post[DS4_GUARD_BYTES];
} ds4_guarded_q1_0;

static_assert(sizeof(ds4_block_q1_0) == 18, "Q1_0 must be 18 bytes per 128 weights");
static_assert(sizeof(ds4_block_q8_K) == 292, "Q8_K helper block size changed");
static_assert(offsetof(ds4_guarded_q1_0, post) ==
              offsetof(ds4_guarded_q1_0, block) + sizeof(ds4_block_q1_0),
              "guard post bytes must immediately follow Q1_0 block");

static void die_cuda(cudaError_t e, const char *what) {
    if (e != cudaSuccess) {
        std::fprintf(stderr, "%s: %s\n", what, cudaGetErrorString(e));
        std::exit(1);
    }
}

static size_t checked_mul_size(size_t a, size_t b, const char *what) {
    if (a != 0 && b > std::numeric_limits<size_t>::max() / a) {
        std::fprintf(stderr, "%s size overflow\n", what);
        std::exit(2);
    }
    return a * b;
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

__device__ static float dev_f16_bits_to_f32(uint16_t u) {
    return __half2float(*reinterpret_cast<const __half *>(&u));
}

__device__ static float dev_dequant_q1_0_value(const ds4_block_q1_0 *x, uint32_t i) {
    const uint32_t bit = (uint32_t)((x->qs[i >> 3u] >> (i & 7u)) & 1u);
    return dev_f16_bits_to_f32(x->d) * (float)(2 * (int32_t)bit - 1);
}

__device__ static float dev_dot_q1_0_q8_K_half128(
        const ds4_block_q1_0 *x,
        const ds4_block_q8_K *y,
        uint32_t half) {
    const uint32_t q8_base = half * 128u;
    int32_t positive_sum = 0;
    int32_t sum_all = 0;

#pragma unroll
    for (uint32_t i = 0; i < 8u; i++) {
        sum_all += (int32_t)y->bsums[half * 8u + i];
    }

#pragma unroll
    for (uint32_t byte = 0; byte < 16u; byte++) {
        const uint32_t bits = (uint32_t)x->qs[byte];
#pragma unroll
        for (uint32_t lane = 0; lane < 8u; lane++) {
            if ((bits >> lane) & 1u) {
                positive_sum += (int32_t)y->qs[q8_base + byte * 8u + lane];
            }
        }
    }

    const int32_t signed_sum = 2 * positive_sum - sum_all;
    return dev_f16_bits_to_f32(x->d) * y->d * (float)signed_sum;
}

__device__ static float dev_dot_q1_0_q8_K_pair(
        const ds4_block_q1_0 *x0,
        const ds4_block_q1_0 *x1,
        const ds4_block_q8_K *y) {
    return dev_dot_q1_0_q8_K_half128(x0, y, 0u) +
           dev_dot_q1_0_q8_K_half128(x1, y, 1u);
}

__global__ static void q1_0_pair_dot_kernel(
        const ds4_guarded_q1_0 *x0,
        const ds4_guarded_q1_0 *x1,
        const ds4_block_q8_K *y,
        float *out,
        uint32_t n) {
    const uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        out[i] = dev_dot_q1_0_q8_K_pair(&x0[i].block, &x1[i].block, y + i);
    }
}

__global__ static void q1_0_pair_dequant_kernel(
        const ds4_guarded_q1_0 *x0,
        const ds4_guarded_q1_0 *x1,
        float *out,
        uint32_t n) {
    const uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n * DS4_Q8_K_QK) return;
    const uint32_t b = i / DS4_Q8_K_QK;
    const uint32_t j = i - b * DS4_Q8_K_QK;
    const ds4_block_q1_0 *x = j < DS4_Q1_0_QK ? &x0[b].block : &x1[b].block;
    out[i] = dev_dequant_q1_0_value(x, j & 127u);
}

static double elapsed_ms(cudaEvent_t a, cudaEvent_t b) {
    float ms = 0.0f;
    die_cuda(cudaEventElapsedTime(&ms, a, b), "cudaEventElapsedTime");
    return (double)ms;
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

static void fill_q1(std::vector<ds4_guarded_q1_0> &x, uint32_t seed, uint8_t pre, uint8_t post) {
    uint32_t s = seed;
    for (size_t b = 0; b < x.size(); ++b) {
        std::memset(x[b].pre, pre, sizeof(x[b].pre));
        std::memset(x[b].post, post, sizeof(x[b].post));
        const float d = 0.015625f + 0.000977f * (float)((b * 7u + seed) & 31u);
        x[b].block.d = f32_to_f16_bits(d);
        for (uint32_t i = 0; i < 16u; ++i) {
            const uint8_t rnd = (uint8_t)xorshift32(s);
            const uint8_t stripe = (uint8_t)(0x5au ^ (uint8_t)(b * 17u + i * 29u));
            x[b].block.qs[i] = (uint8_t)(rnd ^ stripe);
        }
    }
}

static void fill_q8(std::vector<ds4_block_q8_K> &x) {
    uint32_t s = 0x514b5eedu;
    for (size_t b = 0; b < x.size(); ++b) {
        x[b].d = 0.0078125f + 0.00048828125f * (float)((b * 5u + 3u) & 15u);
        for (uint32_t i = 0; i < DS4_Q8_K_QK; ++i) {
            int v = (int)(xorshift32(s) % 255u) - 127;
            if (((i + (uint32_t)b) % 37u) == 0u) v = 127;
            if (((i + 3u * (uint32_t)b) % 41u) == 0u) v = -128;
            x[b].qs[i] = (int8_t)v;
        }
        for (uint32_t g = 0; g < DS4_Q8_K_QK / 16u; ++g) {
            int sum = 0;
            for (uint32_t i = 0; i < 16u; ++i) sum += (int)x[b].qs[g * 16u + i];
            x[b].bsums[g] = (int16_t)sum;
        }
    }
}

static void force_old_bug_probe_separation(
        std::vector<ds4_guarded_q1_0> &x1,
        std::vector<ds4_block_q8_K> &y) {
    for (size_t b = 0; b < x1.size(); ++b) {
        std::memset(x1[b].block.qs, 0x00, sizeof(x1[b].block.qs));
        std::memset(x1[b].post, 0xff, sizeof(x1[b].post));
        for (uint32_t i = 128u; i < DS4_Q8_K_QK; ++i) y[b].qs[i] = 1;
        for (uint32_t g = 8u; g < DS4_Q8_K_QK / 16u; ++g) y[b].bsums[g] = 16;
    }
}

static float cpu_dequant_q1(const ds4_block_q1_0 &x, uint32_t i) {
    const uint32_t bit = (uint32_t)((x.qs[i >> 3u] >> (i & 7u)) & 1u);
    return f16_bits_to_f32(x.d) * (float)(2 * (int32_t)bit - 1);
}

static float cpu_dot_ref(
        const ds4_block_q1_0 &x0,
        const ds4_block_q1_0 &x1,
        const ds4_block_q8_K &y) {
    double acc = 0.0;
    for (uint32_t i = 0; i < DS4_Q1_0_QK; ++i) {
        acc += (double)cpu_dequant_q1(x0, i) * (double)y.d * (double)y.qs[i];
        acc += (double)cpu_dequant_q1(x1, i) * (double)y.d * (double)y.qs[128u + i];
    }
    return (float)acc;
}

static float cpu_dot_formula_half(
        const ds4_block_q1_0 &x,
        const ds4_block_q8_K &y,
        uint32_t half) {
    int32_t positive_sum = 0;
    int32_t sum_all = 0;
    for (uint32_t i = 0; i < 8u; ++i) sum_all += (int32_t)y.bsums[half * 8u + i];
    for (uint32_t byte = 0; byte < 16u; ++byte) {
        const uint32_t bits = (uint32_t)x.qs[byte];
        for (uint32_t lane = 0; lane < 8u; ++lane) {
            if ((bits >> lane) & 1u) {
                positive_sum += (int32_t)y.qs[half * 128u + byte * 8u + lane];
            }
        }
    }
    return f16_bits_to_f32(x.d) * y.d * (float)(2 * positive_sum - sum_all);
}

static float cpu_dot_old_byte_base_bug_half1(
        const ds4_guarded_q1_0 &x1,
        const ds4_block_q8_K &y) {
    int32_t positive_sum = 0;
    int32_t sum_all = 0;
    for (uint32_t i = 0; i < 8u; ++i) sum_all += (int32_t)y.bsums[8u + i];
    for (uint32_t byte = 0; byte < 16u; ++byte) {
        const uint32_t bits = (uint32_t)x1.post[byte];
        for (uint32_t lane = 0; lane < 8u; ++lane) {
            if ((bits >> lane) & 1u) {
                positive_sum += (int32_t)y.qs[128u + byte * 8u + lane];
            }
        }
    }
    return f16_bits_to_f32(x1.block.d) * y.d * (float)(2 * positive_sum - sum_all);
}

static bool guards_ok(const std::vector<ds4_guarded_q1_0> &x, uint8_t pre, uint8_t post) {
    for (const ds4_guarded_q1_0 &b : x) {
        for (uint8_t v : b.pre) if (v != pre) return false;
        for (uint8_t v : b.post) if (v != post) return false;
    }
    return true;
}

int main(int argc, char **argv) {
    int iters = 1000;
    uint32_t nblocks = 4096;
    if (argc > 1) iters = std::atoi(argv[1]);
    if (argc > 2) {
        const unsigned long long parsed = std::strtoull(argv[2], nullptr, 10);
        if (parsed > (unsigned long long)std::numeric_limits<uint32_t>::max()) {
            std::fprintf(stderr, "pairs exceeds uint32 range\n");
            return 2;
        }
        nblocks = (uint32_t)parsed;
    }
    if (iters <= 0 || nblocks == 0) {
        std::fprintf(stderr, "usage: ds4_q1_0_bench [iters] [pairs]\n");
        return 2;
    }
    if (nblocks > std::numeric_limits<uint32_t>::max() / DS4_Q8_K_QK) {
        std::fprintf(stderr, "pairs overflow nblocks*256 kernel domain\n");
        return 2;
    }

    const size_t guarded_bytes = checked_mul_size((size_t)nblocks, sizeof(ds4_guarded_q1_0), "guarded Q1_0");
    const size_t q8_bytes = checked_mul_size((size_t)nblocks, sizeof(ds4_block_q8_K), "Q8_K");
    const size_t dot_bytes = checked_mul_size((size_t)nblocks, sizeof(float), "dot output");
    const size_t deq_values = checked_mul_size((size_t)nblocks, (size_t)DS4_Q8_K_QK, "dequant value count");
    const size_t deq_bytes = checked_mul_size(deq_values, sizeof(float), "dequant output");

    int dev = 0;
    cudaDeviceProp prop{};
    die_cuda(cudaGetDevice(&dev), "cudaGetDevice");
    die_cuda(cudaGetDeviceProperties(&prop, dev), "cudaGetDeviceProperties");

    std::vector<ds4_guarded_q1_0> h_x0(nblocks);
    std::vector<ds4_guarded_q1_0> h_x1(nblocks);
    std::vector<ds4_block_q8_K> h_y(nblocks);
    fill_q1(h_x0, 0x10325476u, 0xa5u, 0x5au);
    fill_q1(h_x1, 0x89abcdefu, 0x3cu, 0xc3u);
    fill_q8(h_y);
    force_old_bug_probe_separation(h_x1, h_y);

    ds4_guarded_q1_0 *d_x0 = nullptr;
    ds4_guarded_q1_0 *d_x1 = nullptr;
    ds4_block_q8_K *d_y = nullptr;
    float *d_dot = nullptr;
    float *d_deq = nullptr;
    die_cuda(cudaMalloc(&d_x0, guarded_bytes), "cudaMalloc d_x0");
    die_cuda(cudaMalloc(&d_x1, guarded_bytes), "cudaMalloc d_x1");
    die_cuda(cudaMalloc(&d_y, q8_bytes), "cudaMalloc d_y");
    die_cuda(cudaMalloc(&d_dot, dot_bytes), "cudaMalloc d_dot");
    die_cuda(cudaMalloc(&d_deq, deq_bytes), "cudaMalloc d_deq");
    die_cuda(cudaMemcpy(d_x0, h_x0.data(), guarded_bytes, cudaMemcpyHostToDevice), "cudaMemcpy d_x0");
    die_cuda(cudaMemcpy(d_x1, h_x1.data(), guarded_bytes, cudaMemcpyHostToDevice), "cudaMemcpy d_x1");
    die_cuda(cudaMemcpy(d_y, h_y.data(), q8_bytes, cudaMemcpyHostToDevice), "cudaMemcpy d_y");

    const dim3 block(128);
    const dim3 grid((nblocks + block.x - 1u) / block.x);
    const uint32_t deq_n = nblocks * DS4_Q8_K_QK;
    const dim3 deq_block(256);
    const dim3 deq_grid((deq_n + deq_block.x - 1u) / deq_block.x);

    q1_0_pair_dot_kernel<<<grid, block>>>(d_x0, d_x1, d_y, d_dot, nblocks);
    die_cuda(cudaGetLastError(), "q1_0_pair_dot_kernel");
    q1_0_pair_dequant_kernel<<<deq_grid, deq_block>>>(d_x0, d_x1, d_deq, nblocks);
    die_cuda(cudaGetLastError(), "q1_0_pair_dequant_kernel");
    die_cuda(cudaDeviceSynchronize(), "cudaDeviceSynchronize warmup");

    const double dot_ms = bench_kernel([&]() {
        q1_0_pair_dot_kernel<<<grid, block>>>(d_x0, d_x1, d_y, d_dot, nblocks);
    }, iters);
    die_cuda(cudaGetLastError(), "q1_0_pair_dot_kernel bench");
    const double deq_ms = bench_kernel([&]() {
        q1_0_pair_dequant_kernel<<<deq_grid, deq_block>>>(d_x0, d_x1, d_deq, nblocks);
    }, iters);
    die_cuda(cudaGetLastError(), "q1_0_pair_dequant_kernel bench");

    const size_t check_blocks = nblocks < 512u ? nblocks : 512u;
    std::vector<float> gpu_dot(check_blocks);
    std::vector<float> gpu_deq(check_blocks * DS4_Q8_K_QK);
    die_cuda(cudaMemcpy(gpu_dot.data(), d_dot, gpu_dot.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_dot");
    die_cuda(cudaMemcpy(gpu_deq.data(), d_deq, gpu_deq.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy gpu_deq");
    die_cuda(cudaMemcpy(h_x0.data(), d_x0, guarded_bytes, cudaMemcpyDeviceToHost), "cudaMemcpy h_x0 guards");
    die_cuda(cudaMemcpy(h_x1.data(), d_x1, guarded_bytes, cudaMemcpyDeviceToHost), "cudaMemcpy h_x1 guards");

    double dot_max_abs = 0.0;
    double formula_max_abs = 0.0;
    double deq_max_abs = 0.0;
    double old_byte_base_bug_probe_min_abs = 1.0e30;
    double worst_gpu = 0.0;
    double worst_ref = 0.0;
    size_t worst_block = 0;
    for (size_t b = 0; b < check_blocks; ++b) {
        const float ref = cpu_dot_ref(h_x0[b].block, h_x1[b].block, h_y[b]);
        const float formula =
            cpu_dot_formula_half(h_x0[b].block, h_y[b], 0u) +
            cpu_dot_formula_half(h_x1[b].block, h_y[b], 1u);
        const double err = std::fabs((double)gpu_dot[b] - (double)ref);
        if (err > dot_max_abs) {
            dot_max_abs = err;
            worst_gpu = gpu_dot[b];
            worst_ref = ref;
            worst_block = b;
        }
        formula_max_abs = std::fmax(formula_max_abs, std::fabs((double)formula - (double)ref));

        const float old_byte_base_bug =
            cpu_dot_formula_half(h_x0[b].block, h_y[b], 0u) +
            cpu_dot_old_byte_base_bug_half1(h_x1[b], h_y[b]);
        old_byte_base_bug_probe_min_abs = std::fmin(
            old_byte_base_bug_probe_min_abs,
            std::fabs((double)old_byte_base_bug - (double)ref));

        for (uint32_t j = 0; j < DS4_Q8_K_QK; ++j) {
            const ds4_block_q1_0 &qx = j < DS4_Q1_0_QK ? h_x0[b].block : h_x1[b].block;
            const float ref_deq = cpu_dequant_q1(qx, j & 127u);
            deq_max_abs = std::fmax(
                deq_max_abs,
                std::fabs((double)gpu_deq[b * DS4_Q8_K_QK + j] - (double)ref_deq));
        }
    }

    const bool guard_ok = guards_ok(h_x0, 0xa5u, 0x5au) && guards_ok(h_x1, 0x3cu, 0xffu);
    const bool pass =
        dot_max_abs <= 1.0e-5 &&
        formula_max_abs <= 1.0e-5 &&
        deq_max_abs <= 0.0 &&
        guard_ok &&
        old_byte_base_bug_probe_min_abs > 1.0e-4;

    std::printf("{\n");
    std::printf("  \"benchmark\": \"ds4_q1_0_bench\",\n");
    std::printf("  \"device\": {\"index\":%d,\"name\":\"%s\",\"sm\":%d%d},\n",
                dev, prop.name, prop.major, prop.minor);
    std::printf("  \"layout\": {\"q1_0_block_values\":128,\"q1_0_block_bytes\":18,\"q8_K_block_values\":256,\"q8_K_block_bytes\":292,\"polarity\":\"bit1=+d,bit0=-d\"},\n");
    std::printf("  \"validation\": {\"checked_pairs\":%llu,\"dot_max_abs\":%.9g,\"dot_tol_abs\":1e-5,\"formula_vs_dequant_ref_max_abs\":%.9g,\"dequant_max_abs\":%.9g,\"guard_ok\":%s,\"old_byte_base_bug_probe_min_abs\":%.9g,\"worst_block\":%llu,\"worst_gpu\":%.9g,\"worst_ref\":%.9g,\"pass\":%s},\n",
                (unsigned long long)check_blocks,
                dot_max_abs,
                formula_max_abs,
                deq_max_abs,
                guard_ok ? "true" : "false",
                old_byte_base_bug_probe_min_abs,
                (unsigned long long)worst_block,
                worst_gpu,
                worst_ref,
                pass ? "true" : "false");
    std::printf("  \"measurements\": {\"iters\":%d,\"pairs\":%u,\"dot_kernel_ms\":%.6f,\"dequant_kernel_ms\":%.6f,\"dot_pairs_per_s\":%.3f,\"dequant_values_per_s\":%.3f}\n",
                iters,
                nblocks,
                dot_ms,
                deq_ms,
                (double)nblocks / (dot_ms / 1000.0),
                (double)deq_n / (deq_ms / 1000.0));
    std::printf("}\n");

    cudaFree(d_deq);
    cudaFree(d_dot);
    cudaFree(d_y);
    cudaFree(d_x1);
    cudaFree(d_x0);
    return pass ? 0 : 1;
}
