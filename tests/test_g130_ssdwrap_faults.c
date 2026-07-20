#include "../ds4_gpu.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define EXPECT_TRUE(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "%s:%d: expected true: %s\n", __FILE__, __LINE__, #expr); \
        failures++; \
    } \
} while (0)

#define EXPECT_U64_EQ(got, want) do { \
    uint64_t got__ = (uint64_t)(got); \
    uint64_t want__ = (uint64_t)(want); \
    if (got__ != want__) { \
        fprintf(stderr, "%s:%d: got %llu want %llu: %s\n", \
                __FILE__, __LINE__, \
                (unsigned long long)got__, (unsigned long long)want__, #got); \
        failures++; \
    } \
} while (0)

typedef int (*ssdwrap_case_fn)(ds4_gpu_ssdwrap_test_result *out);

static ds4_gpu_ssdwrap_test_result run_case(
        const char *name, ssdwrap_case_fn fn) {
    ds4_gpu_ssdwrap_test_result out;
    memset(&out, 0, sizeof(out));
    EXPECT_TRUE(fn(&out));
    fprintf(stderr,
            "g130-ssdwrap: %s ok=%d failed=%d successes=%llu failures=%llu "
            "stale=%llu dropped=%llu structural=%llu request_used=%llu "
            "window_used=%llu\n",
            name, out.ok, out.failed,
            (unsigned long long)out.successes,
            (unsigned long long)out.failures,
            (unsigned long long)out.stale,
            (unsigned long long)out.dropped,
            (unsigned long long)out.structural_rejects,
            (unsigned long long)out.promotion_request_used,
            (unsigned long long)out.promotion_window_used);
    return out;
}

static void expect_happy_path(const char *name, ssdwrap_case_fn fn) {
    ds4_gpu_ssdwrap_test_result out = run_case(name, fn);
    EXPECT_TRUE(out.ok);
    EXPECT_U64_EQ(out.failed, 0);
    EXPECT_U64_EQ(out.successes, 1);
    EXPECT_U64_EQ(out.failures, 0);
    EXPECT_U64_EQ(out.stale, 0);
    EXPECT_U64_EQ(out.dropped, 0);
    EXPECT_U64_EQ(out.structural_rejects, 0);
}

static void expect_nonfatal_drop(const char *name, ssdwrap_case_fn fn) {
    ds4_gpu_ssdwrap_test_result out = run_case(name, fn);
    EXPECT_TRUE(out.ok);
    EXPECT_U64_EQ(out.failed, 0);
    EXPECT_U64_EQ(out.successes, 0);
    EXPECT_U64_EQ(out.failures, 0);
    EXPECT_U64_EQ(out.stale, 1);
    EXPECT_U64_EQ(out.dropped, 1);
    EXPECT_U64_EQ(out.structural_rejects, 0);
    EXPECT_U64_EQ(out.promotion_request_used, 0);
    EXPECT_U64_EQ(out.promotion_window_used, 0);
    EXPECT_U64_EQ(out.promotion_failures, 0);
    EXPECT_U64_EQ(out.tiering_failures, 0);
}

static void expect_fail_closed(const char *name, ssdwrap_case_fn fn) {
    ds4_gpu_ssdwrap_test_result out = run_case(name, fn);
    EXPECT_TRUE(!out.ok);
    EXPECT_U64_EQ(out.failed, 1);
    EXPECT_U64_EQ(out.successes, 0);
    EXPECT_U64_EQ(out.failures, 1);
    EXPECT_U64_EQ(out.stale, 0);
    EXPECT_U64_EQ(out.dropped, 0);
    EXPECT_U64_EQ(out.structural_rejects, 1);
    EXPECT_U64_EQ(out.promotion_failures, 1);
    EXPECT_U64_EQ(out.tiering_failures, 1);
}

static void expect_commit_checksum_reject(const char *name, ssdwrap_case_fn fn) {
    ds4_gpu_ssdwrap_test_result out = run_case(name, fn);
    EXPECT_TRUE(!out.ok);
    EXPECT_U64_EQ(out.failed, 1);
    EXPECT_U64_EQ(out.successes, 0);
    EXPECT_U64_EQ(out.failures, 0);
    EXPECT_U64_EQ(out.structural_rejects, 0);
}

int main(void) {
    expect_happy_path("happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_nonfatal_drop("stale-age", ds4_gpu_ssdwrap_test_stale_age);
    expect_happy_path("stale-age-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_nonfatal_drop("epoch-mismatch", ds4_gpu_ssdwrap_test_epoch_mismatch);
    expect_happy_path("epoch-mismatch-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_nonfatal_drop("victim-stale", ds4_gpu_ssdwrap_test_victim_stale);
    expect_happy_path("victim-stale-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_nonfatal_drop("destination-stale", ds4_gpu_ssdwrap_test_destination_stale);
    expect_happy_path("destination-stale-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_fail_closed("pread-failure", ds4_gpu_ssdwrap_test_pread_failure);
    expect_happy_path("pread-failure-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_fail_closed("provenance-mismatch", ds4_gpu_ssdwrap_test_provenance_mismatch);
    expect_happy_path("provenance-mismatch-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_commit_checksum_reject("checksum-mismatch",
                                  ds4_gpu_ssdwrap_test_checksum_mismatch);
    expect_happy_path("checksum-mismatch-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    expect_fail_closed("pairing-break", ds4_gpu_ssdwrap_test_pairing_break);
    expect_happy_path("pairing-break-happy-baseline", ds4_gpu_ssdwrap_test_happy);

    if (failures) {
        fprintf(stderr, "g130-ssdwrap fault tests: %d failure(s)\n", failures);
        return 1;
    }
    puts("g130-ssdwrap fault tests: ok");
    return 0;
}
