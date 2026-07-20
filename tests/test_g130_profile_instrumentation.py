#!/usr/bin/env python3
"""CPU/static contract tests for the G130 mixed-Q1 final profile schema.

No CUDA runtime path is executed: doing that requires the prohibited GPU build
and a CUDA device.  The tests inspect the real C/CUDA call sites, cleanup and
format strings, while the harness-facing key/value rejection rules execute on
representative logs.
"""

from __future__ import annotations

import math
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CUDA = (ROOT / "ds4_cuda.cu").read_text(encoding="utf-8")


def source_block(start: str, end: str) -> str:
    begin = CUDA.index(start)
    finish = CUDA.index(end, begin + len(start))
    return CUDA[begin:finish]


def balanced_call_containing(marker: str) -> str:
    marker_at = CUDA.index(marker)
    call_at = CUDA.rfind("fprintf(", 0, marker_at)
    if call_at < 0:
        raise ValueError(f"fprintf missing for {marker}")
    open_at = CUDA.index("(", call_at)
    depth = 0
    quote: str | None = None
    escaped = False
    for index in range(open_at, len(CUDA)):
        char = CUDA[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ('"', "'"):
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return CUDA[open_at + 1 : index]
    raise ValueError(f"unterminated fprintf for {marker}")


def split_top_level_arguments(arguments: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    quote: str | None = None
    escaped = False
    for index, char in enumerate(arguments):
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ('"', "'"):
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(arguments[start:index].strip())
            start = index + 1
    parts.append(arguments[start:].strip())
    return parts


PRINTF_SPECIFIER = re.compile(
    r"%(?!%)[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h|z|t|j)?[diuoxXfFeEgGaAcsp]"
)


def assert_fprintf_arity(test: unittest.TestCase, marker: str) -> None:
    arguments = split_top_level_arguments(balanced_call_containing(marker))
    test.assertGreaterEqual(len(arguments), 2)
    test.assertEqual(arguments[0], "stderr")
    literals = re.findall(r'"((?:\\.|[^"\\])*)"', arguments[1])
    test.assertTrue(literals, f"format string missing for {marker}")
    specifiers = PRINTF_SPECIFIER.findall("".join(literals))
    test.assertEqual(
        len(specifiers),
        len(arguments) - 2,
        f"printf placeholder/argument mismatch for {marker}",
    )


def profile_env_enabled(value: str | None) -> bool:
    """Executable fixture matching cuda_q1_0_profile_requested()."""
    return value is not None and bool(value) and value != "0"


def parse_kv_line(line: str, tag: str) -> dict[str, str]:
    prefix = f"ds4: [{tag}] "
    if not line.startswith(prefix):
        raise ValueError(f"missing {tag} prefix")
    fields: dict[str, str] = {}
    for token in line[len(prefix) :].split():
        if "=" not in token:
            raise ValueError(f"non key/value token: {token}")
        key, value = token.split("=", 1)
        if key in fields:
            raise ValueError(f"duplicate field: {key}")
        fields[key] = value
    return fields


def parse_final_pair(text: str) -> tuple[dict[str, str], dict[str, str]]:
    route_lines = [
        line
        for line in text.splitlines()
        if line.startswith("ds4: [q1-0-profile-route] ")
    ]
    selection_lines = [
        line
        for line in text.splitlines()
        if line.startswith("ds4: [q1-0-profile-selection] ")
    ]
    if len(route_lines) != 1 or len(selection_lines) != 1:
        raise ValueError("final route/selection summaries must occur exactly once")
    route = parse_kv_line(route_lines[0], "q1-0-profile-route")
    selection = parse_kv_line(
        selection_lines[0], "q1-0-profile-selection"
    )
    for fields in (route, selection):
        if fields.get("result") != "summary":
            raise ValueError("result must be summary")
        if fields.get("final") != "1":
            raise ValueError("final marker missing")
        if fields.get("path") != "mixed_q1":
            raise ValueError("mixed path marker missing")
        if fields.get("enabled") != "1":
            raise ValueError("enabled marker missing")
    return route, selection


def replace_fields(line: str, **updates: object) -> str:
    for key, value in updates.items():
        line, count = re.subn(
            rf"(?<!\S){re.escape(key)}=[^\s]+",
            f"{key}={value}",
            line,
            count=1,
        )
        if count != 1:
            raise ValueError(f"field not found: {key}")
    return line


def validate_selection(fields: dict[str, str]) -> None:
    calls = int(fields["calls"])
    completed = int(fields["completed_calls"])
    failed = int(fields["failed_calls"])
    completed_routes = int(fields["completed_routes"])
    hot_routes = int(fields["hot_routes"])
    q1_routes = int(fields["q1_routes"])
    if calls != completed + failed:
        raise ValueError("call balance")
    if completed_routes != hot_routes + q1_routes:
        raise ValueError("route balance")
    if fields["call_balance_ok"] != "1":
        raise ValueError("call_balance_ok")
    if fields["route_balance_ok"] != "1":
        raise ValueError("route_balance_ok")
    if fields["host_coverage_ok"] != "1":
        raise ValueError("host_coverage_ok")
    if fields["device_coverage_ok"] != "1":
        raise ValueError("device_coverage_ok")
    if fields["coverage_ok"] != "1":
        raise ValueError("coverage_ok")
    if fields["summary_valid"] != "1":
        raise ValueError("summary_valid")


def validate_route_coverage(
    route: dict[str, str], selection: dict[str, str]
) -> None:
    calls = int(route["calls"])
    completed = int(route["completed_calls"])
    failed = int(route["failed_calls"])
    if calls != completed + failed:
        raise ValueError("route call balance")
    for field in (
        "entry_contract_calls",
        "selection_d2h_calls",
        "classify_map_calls",
        "hot_branch_calls",
        "join_publish_calls",
    ):
        if int(route[field]) != completed:
            raise ValueError(f"completed coverage: {field}")
    q1_path_calls = int(selection["mixed_hot_q1_calls"]) + int(
        selection["q1_only_calls"]
    )
    for field in (
        "scratch_prepare_calls",
        "metadata_h2d_calls",
        "tier_observe_calls",
        "q1_dispatch_prepare_calls",
        "q1_entry_calls",
        "q1_selected_load_calls",
        "q1_prepare_calls",
        "q1_kernel_calls",
    ):
        if int(route[field]) != q1_path_calls:
            raise ValueError(f"Q1 coverage: {field}")
    if int(selection["join_kernel_calls"]) != q1_path_calls:
        raise ValueError("join coverage")


def validate_final_contract(
    route: dict[str, str], selection: dict[str, str]
) -> None:
    validate_selection(selection)
    validate_route_coverage(route, selection)
    for fields in (route, selection):
        if int(fields["failed_calls"]) != 0:
            raise ValueError("failed_calls")
        if int(fields["timer_failures"]) != 0:
            raise ValueError("timer_failures")
        if fields["cleanup_sync_ok"] != "1":
            raise ValueError("cleanup sync")
        if fields["summary_valid"] != "1":
            raise ValueError("summary valid")
    if int(route["cleanup_sync_error"]) != 0:
        raise ValueError("cleanup sync error")
    if int(route["q1_kernel_unfenced_calls"]) != 0:
        raise ValueError("unfenced")
    if int(route["q1_kernel_device_missing_calls"]) != 0:
        raise ValueError("device missing")
    kernel_calls = int(route["q1_kernel_calls"])
    if int(route["q1_kernel_fenced_calls"]) != kernel_calls:
        raise ValueError("fenced coverage")
    if int(route["q1_kernel_device_calls"]) != kernel_calls:
        raise ValueError("device coverage")
    if route["host_device_additive"] != "0":
        raise ValueError("host/device must not be summed")
    if route["q1_kernel_device_in_bucket"] != "0":
        raise ValueError("device metric included in host bucket")
    if route["cleanup_required"] != "1" or (
        route["missing_cleanup_policy"] != "incomplete_negative"
    ):
        raise ValueError("cleanup policy")
    for key, raw in route.items():
        if not key.endswith("_seconds") or key == "bucket_gap_seconds":
            continue
        value = float(raw)
        if not math.isfinite(value) or value < 0.0:
            raise ValueError(f"invalid timing: {key}")
    gap = float(route["bucket_gap_seconds"])
    tolerance = float(route["bucket_gap_tolerance_seconds"])
    if not math.isfinite(gap) or gap < -tolerance:
        raise ValueError("bucket gap")
    if route["timing_values_ok"] != "1" or route["bucket_gap_ok"] != "1":
        raise ValueError("runtime timing validity")


ROUTE_ZERO = (
    "ds4: [q1-0-profile-route] result=summary final=1 path=mixed_q1 "
    "enabled=1 unit=seconds clock=host_monotonic bucket_scope=completed "
    "phase_model=disjoint denominator=per_bucket_calls "
    "limitation_hot_device=unmeasured_no_new_sync "
    "limitation_failed_calls=counts_only "
    "cleanup_required=1 missing_cleanup_policy=incomplete_negative "
    "host_device_additive=0 "
    "summary_valid=1 cleanup_sync_ok=1 cleanup_sync_error=0 "
    "timer_failures=0 timing_values_ok=1 bucket_gap_ok=1 "
    "bucket_gap_tolerance_seconds=0.000001000 "
    "calls=0 completed_calls=0 failed_calls=0 call_seconds=0.000000000 "
    "bucket_seconds=0.000000000 bucket_gap_seconds=0.000000000 "
    "entry_contract_calls=0 entry_contract_seconds=0.000000000 "
    "selection_d2h_calls=0 selection_d2h_seconds=0.000000000 "
    "classify_map_calls=0 classify_map_seconds=0.000000000 "
    "scratch_prepare_calls=0 scratch_prepare_seconds=0.000000000 "
    "metadata_h2d_calls=0 metadata_h2d_seconds=0.000000000 "
    "hot_branch_calls=0 hot_branch_seconds=0.000000000 "
    "tier_observe_calls=0 tier_observe_seconds=0.000000000 "
    "q1_dispatch_prepare_calls=0 q1_dispatch_prepare_seconds=0.000000000 "
    "q1_entry_calls=0 q1_entry_seconds=0.000000000 "
    "q1_selected_load_calls=0 q1_selected_load_seconds=0.000000000 "
    "q1_prepare_calls=0 q1_prepare_seconds=0.000000000 "
    "q1_kernel_calls=0 q1_kernel_seconds=0.000000000 "
    "q1_kernel_device_calls=0 q1_kernel_device_seconds=0.000000000 "
    "q1_kernel_device_missing_calls=0 q1_kernel_device_in_bucket=0 "
    "q1_kernel_fenced_calls=0 q1_kernel_unfenced_calls=0 "
    "join_publish_calls=0 join_publish_seconds=0.000000000"
)

SELECTION_ZERO = (
    "ds4: [q1-0-profile-selection] result=summary final=1 path=mixed_q1 "
    "enabled=1 unit=count coverage_scope=completed denominator=completed_routes "
    "calls=0 completed_calls=0 "
    "failed_calls=0 requested_routes=0 completed_routes=0 hot_routes=0 "
    "q1_routes=0 all_iq2_calls=0 mixed_hot_q1_calls=0 q1_only_calls=0 "
    "join_kernel_calls=0 timer_failures=0 cleanup_sync_ok=1 "
    "call_balance_ok=1 route_balance_ok=1 host_coverage_ok=1 "
    "device_coverage_ok=1 coverage_ok=1 summary_valid=1"
)

ROUTE_NONZERO = ROUTE_ZERO.replace(
    "calls=0 completed_calls=0 failed_calls=0",
    "calls=2 completed_calls=2 failed_calls=0",
    1,
)
for _field in (
    "entry_contract_calls",
    "selection_d2h_calls",
    "classify_map_calls",
    "hot_branch_calls",
    "join_publish_calls",
):
    ROUTE_NONZERO = ROUTE_NONZERO.replace(f"{_field}=0", f"{_field}=2")
for _field in (
    "scratch_prepare_calls",
    "metadata_h2d_calls",
    "tier_observe_calls",
    "q1_dispatch_prepare_calls",
    "q1_entry_calls",
    "q1_selected_load_calls",
    "q1_prepare_calls",
    "q1_kernel_calls",
    "q1_kernel_device_calls",
    "q1_kernel_fenced_calls",
):
    ROUTE_NONZERO = ROUTE_NONZERO.replace(f"{_field}=0", f"{_field}=1")

SELECTION_NONZERO = (
    "ds4: [q1-0-profile-selection] result=summary final=1 path=mixed_q1 "
    "enabled=1 unit=count coverage_scope=completed denominator=completed_routes "
    "calls=2 completed_calls=2 "
    "failed_calls=0 requested_routes=12 completed_routes=12 hot_routes=7 "
    "q1_routes=5 all_iq2_calls=1 mixed_hot_q1_calls=1 q1_only_calls=0 "
    "join_kernel_calls=1 timer_failures=0 cleanup_sync_ok=1 "
    "call_balance_ok=1 route_balance_ok=1 host_coverage_ok=1 "
    "device_coverage_ok=1 coverage_ok=1 summary_valid=1"
)


class G130ProfileContractTests(unittest.TestCase):
    def test_env_off_and_reset_lock_order_use_real_source(self) -> None:
        self.assertFalse(profile_env_enabled(None))
        self.assertFalse(profile_env_enabled(""))
        self.assertFalse(profile_env_enabled("0"))
        self.assertTrue(profile_env_enabled("1"))
        enable = source_block(
            "static int cuda_q1_0_profile_requested(void)",
            "static void cuda_q1_0_mixed_profile_reset",
        )
        self.assertIn('getenv("DS4_Q1_0_PROFILE")', enable)
        self.assertIn(
            'value && value[0] && strcmp(value, "0") != 0', enable
        )
        self.assertIn("static int enabled = -1", enable)
        reset = source_block(
            "static void cuda_q1_0_mixed_profile_reset(int new_lifecycle)",
            "static void cuda_q1_0_mixed_profile_record_entered",
        )
        early_return = "if (!cuda_q1_0_profile_requested()) return;"
        lock = "std::lock_guard<std::mutex> guard"
        self.assertIn(early_return, reset)
        self.assertIn(lock, reset)
        self.assertLess(reset.index(early_return), reset.index(lock))

    def test_cleanup_sync_and_summary_topology_use_real_source(self) -> None:
        cleanup = source_block(
            'extern "C" void ds4_gpu_cleanup(void)',
            'extern "C" ds4_gpu_tensor *ds4_gpu_tensor_alloc',
        )
        self.assertEqual(cleanup.count("cudaDeviceSynchronize()"), 1)
        self.assertNotIn("(void)cudaDeviceSynchronize();", cleanup)
        self.assertIn(
            "const cudaError_t cleanup_sync_error = cudaDeviceSynchronize();",
            cleanup,
        )
        self.assertIn("cleanup_sync_error != cudaSuccess", cleanup)
        self.assertIn("cudaGetErrorString(cleanup_sync_error)", cleanup)
        self.assertEqual(
            cleanup.count(
                "cuda_q1_0_mixed_profile_finalize(cleanup_sync_error);"
            ),
            1,
        )
        self.assertEqual(
            CUDA.count("cuda_q1_0_mixed_profile_finalize(cleanup_sync_error);"),
            1,
        )
        finalize = source_block(
            "static void cuda_q1_0_mixed_profile_finalize(",
            "static int cuda_request_phase_trace_enabled(void)",
        )
        self.assertEqual(finalize.count("[q1-0-profile-route]"), 1)
        self.assertEqual(finalize.count("[q1-0-profile-selection]"), 1)
        self.assertIn("g_q1_0_mixed_profile_final_emitted", finalize)
        self.assertIn("cudaError_t cleanup_sync_error", finalize)
        self.assertIn("final=1", finalize)
        self.assertIn("path=mixed_q1", finalize)
        for field in (
            "phase_model=disjoint",
            "denominator=per_bucket_calls",
            "limitation_hot_device=unmeasured_no_new_sync",
            "limitation_failed_calls=counts_only",
            "cleanup_required=1",
            "missing_cleanup_policy=incomplete_negative",
            "host_device_additive=0",
            "summary_valid=",
            "cleanup_sync_ok=",
            "cleanup_sync_error=",
            "timer_failures=",
            "timing_values_ok=",
            "bucket_gap_ok=",
            "bucket_gap_tolerance_seconds=",
            "selection_d2h_calls=",
            "classify_map_calls=",
            "hot_branch_calls=",
            "q1_selected_load_calls=",
            "q1_kernel_calls=",
            "join_publish_calls=",
            "denominator=completed_routes",
            "hot_routes=",
            "q1_routes=",
            "host_coverage_ok=",
            "device_coverage_ok=",
            "coverage_ok=",
        ):
            self.assertIn(field, finalize)
        mixed = source_block(
            'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(',
            'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor(',
        )
        self.assertEqual(
            mixed.count("cuda_q1_0_mixed_profile_record_completed("), 2
        )
        self.assertEqual(len(re.findall(r"\breturn 1;", mixed)), 2)

    def test_final_fprintf_placeholder_arity_matches_arguments(self) -> None:
        assert_fprintf_arity(self, "[q1-0-profile-route]")
        assert_fprintf_arity(self, "[q1-0-profile-selection]")

    def test_host_and_device_coverage_are_strict_in_real_source(self) -> None:
        finalize = source_block(
            "static void cuda_q1_0_mixed_profile_finalize(",
            "static int cuda_request_phase_trace_enabled(void)",
        )
        self.assertIn("const int host_coverage_ok =", finalize)
        self.assertIn("const int device_coverage_ok =", finalize)
        self.assertIn(
            "p.q1_kernel_device_calls == p.q1_kernel_calls", finalize
        )
        self.assertIn(
            "p.q1_kernel_fenced_calls == p.q1_kernel_calls", finalize
        )
        self.assertIn("q1_kernel_device_missing_calls == 0", finalize)
        self.assertIn("q1_kernel_unfenced_calls == 0", finalize)
        self.assertIn("stats.timer_failures == 0", finalize)
        self.assertIn("failed_calls == 0", finalize)
        self.assertIn("cleanup_sync_ok", finalize)
        self.assertIn("timing_values_ok", finalize)
        self.assertIn("bucket_gap_ok", finalize)
        overall = finalize[
            finalize.index("const int coverage_ok =") :
            finalize.index("const int summary_valid")
        ]
        for required in (
            "call_balance_ok",
            "route_balance_ok",
            "host_coverage_ok",
            "device_coverage_ok",
            "failed_calls == 0",
            "stats.timer_failures == 0",
            "cleanup_sync_ok",
            "timing_values_ok",
            "bucket_gap_ok",
        ):
            self.assertIn(required, overall)

    def test_lifecycle_reset_sites_cover_rebind_bootstrap_and_release(self) -> None:
        self.assertIn(
            "cuda_q1_0_mixed_profile_reset(0);",
            source_block(
                "static void cuda_q1_0_sidecar_clear(void)",
                "static uint64_t cuda_round_down",
            ),
        )
        self.assertIn(
            "cuda_q1_0_mixed_profile_reset(0);",
            source_block(
                "static void cuda_q1_0_dynamic_arena_release(int report)",
                "static void cuda_primary_dynamic_arena_release",
            ),
        )
        prepare = source_block(
            'extern "C" int ds4_gpu_dynamic_arena_prepare_q1_0(',
            'extern "C" int ds4_gpu_dynamic_arena_prepare(',
        )
        self.assertIn("cuda_q1_0_mixed_profile_reset(1);", prepare)
        bind = source_block(
            'extern "C" int ds4_gpu_set_q1_0_sidecar(',
            'extern "C" int ds4_gpu_set_nested_residual_sidecar(',
        )
        self.assertIn("cuda_q1_0_mixed_profile_reset(1);", bind)

    def test_mixed_call_path_has_phase_and_coverage_hooks(self) -> None:
        mixed = source_block(
            'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(',
            'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor(',
        )
        for needle in (
            '"Q1_0 mixed selected D2H"',
            '"Q1_0 mixed weights D2H"',
            "classify_map_calls++",
            "hot_branch_calls++",
            "q1_dispatch_prepare_calls++",
            "join_publish_calls++",
            "cuda_q1_0_mixed_profile_record_entered(n_expert)",
            "cuda_q1_0_mixed_profile_record_completed(",
        ):
            self.assertIn(needle, mixed)
        routed = source_block(
            "static int routed_moe_launch(",
            'extern "C" int ds4_gpu_routed_moe_one_tensor(',
        )
        self.assertIn("q1_selected_load_calls++", routed)
        self.assertIn("q1_kernel_calls++", routed)
        self.assertIn("q1_kernel_fenced_calls++", routed)

    def test_legacy_q1_profile_schema_is_retained(self) -> None:
        legacy = source_block(
            '"ds4: [q1-0-profile] result=summary enabled=1 "',
            "if (report && arena.host_base &&\n",
        )
        for field in (
            "resident_hits_total=%llu",
            "pinned_route_hits=%llu",
            "pageable_route_hits=%llu",
            "upload_sync_calls=%llu",
            "q1_kernel_calls=%llu",
            "mixed_join_calls=%llu",
            "timer_failures=%llu",
        ):
            self.assertIn(field, legacy)

    def test_zero_and_nonzero_examples_parse_and_balance(self) -> None:
        for route_line, selection_line in (
            (ROUTE_ZERO, SELECTION_ZERO),
            (ROUTE_NONZERO, SELECTION_NONZERO),
        ):
            route, selection = parse_final_pair(
                route_line + "\n" + selection_line + "\n"
            )
            self.assertEqual(route["unit"], "seconds")
            self.assertEqual(selection["unit"], "count")
            validate_final_contract(route, selection)

    def test_incomplete_duplicate_and_unbalanced_summaries_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "exactly once"):
            parse_final_pair(ROUTE_ZERO)
        with self.assertRaisesRegex(ValueError, "exactly once"):
            parse_final_pair(
                ROUTE_ZERO + "\n" + ROUTE_ZERO + "\n" + SELECTION_ZERO
            )
        bad = parse_kv_line(
            SELECTION_NONZERO.replace("completed_routes=12", "completed_routes=11"),
            "q1-0-profile-selection",
        )
        with self.assertRaisesRegex(ValueError, "route balance"):
            validate_selection(bad)

    def test_harness_rejects_device_sync_timer_and_timing_failures(self) -> None:
        missing_device_route = replace_fields(
            ROUTE_NONZERO,
            q1_kernel_device_calls=0,
            q1_kernel_fenced_calls=0,
            q1_kernel_device_missing_calls=1,
            q1_kernel_unfenced_calls=1,
        )
        route, selection = parse_final_pair(
            missing_device_route + "\n" + SELECTION_NONZERO
        )
        with self.assertRaisesRegex(ValueError, "unfenced"):
            validate_final_contract(route, selection)

        sync_route = replace_fields(
            ROUTE_ZERO,
            cleanup_sync_ok=0,
            cleanup_sync_error=700,
        )
        sync_selection = replace_fields(
            SELECTION_ZERO,
            cleanup_sync_ok=0,
        )
        route, selection = parse_final_pair(sync_route + "\n" + sync_selection)
        with self.assertRaisesRegex(ValueError, "cleanup sync"):
            validate_final_contract(route, selection)

        for field, value, message in (
            ("call_seconds", "nan", "invalid timing"),
            ("q1_kernel_seconds", "inf", "invalid timing"),
            ("selection_d2h_seconds", "-0.1", "invalid timing"),
            ("bucket_gap_seconds", "-0.01", "bucket gap"),
        ):
            bad_route = replace_fields(ROUTE_ZERO, **{field: value})
            route, selection = parse_final_pair(
                bad_route + "\n" + SELECTION_ZERO
            )
            with self.assertRaisesRegex(ValueError, message):
                validate_final_contract(route, selection)

        timer_route = replace_fields(ROUTE_ZERO, timer_failures=1)
        timer_selection = replace_fields(SELECTION_ZERO, timer_failures=1)
        route, selection = parse_final_pair(
            timer_route + "\n" + timer_selection
        )
        with self.assertRaisesRegex(ValueError, "timer_failures"):
            validate_final_contract(route, selection)

        failed_route = replace_fields(
            ROUTE_ZERO, calls=1, failed_calls=1
        )
        failed_selection = replace_fields(
            SELECTION_ZERO, calls=1, failed_calls=1
        )
        route, selection = parse_final_pair(
            failed_route + "\n" + failed_selection
        )
        with self.assertRaisesRegex(ValueError, "failed_calls"):
            validate_final_contract(route, selection)


if __name__ == "__main__":
    unittest.main()
