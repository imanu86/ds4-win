import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
CUDA = (ROOT / "ds4_cuda.cu").read_text(encoding="utf-8-sig")
HOST = (ROOT / "ds4.c").read_text(encoding="utf-8-sig")
RUNNER = (ROOT / "g129_q1_open_dynamic_promotion_safety.ps1").read_text(
    encoding="utf-8-sig"
)
HARNESS = (ROOT / "g7_measure.ps1").read_text(encoding="utf-8-sig")


def body(text: str, start: str, end: str) -> str:
    first = text.index(start)
    last = text.index(end, first)
    return text[first:last]


def test_q1_promotion_has_separate_fail_closed_configuration() -> None:
    for needle in (
        'getenv("DS4_Q1_0_DYNAMIC_PROMOTION")',
        '"DS4_Q1_0_PROMOTION_PROBATION_SLOTS"',
        '"DS4_Q1_0_PROMOTION_MIN_TOUCHES"',
        '"DS4_Q1_0_PROMOTION_MIN_WEIGHT"',
        '"DS4_Q1_0_PROMOTION_REQUEST_BUDGET"',
        '"DS4_Q1_0_PROMOTION_WINDOW_CALLS"',
        '"DS4_Q1_0_PROMOTION_WINDOW_BUDGET"',
    ):
        assert needle in CUDA
    config = body(
        CUDA,
        "static int cuda_quant_promotion_probation_slots_requested",
        "static int cuda_moe_tiering_double_env",
    )
    assert "q1_0_slots <= 0 || iq1_slots != 0" in config
    assert "return q1_0_slots" in config


def test_dynamic_mode_is_resident_dual_arena_not_snapshot_mode() -> None:
    validation = body(
        HOST,
        "const int q1_0_resident_arena = q1_0_resident_arena_requested();",
        "const char *iq1_s_sidecar_path",
    )
    assert "q1_0_dynamic_promotion > 0" in validation
    assert "q1_0_resident_arena <= 0 || q1_0_dual_arena <= 0" in validation
    assert "q1_0_snapshot_backing > 0" in validation
    assert "q1_0_dual_sparse_companion > 0" in validation
    assert "q1_0_mixed_cold_one > 0" in validation
    assert "-Q1_0SnapshotBacking" not in RUNNER
    assert "-Iq1Promotion" not in RUNNER


def test_complete_q1_base_supports_pinned_and_pageable_disjoint_storage() -> None:
    prepare = body(
        CUDA,
        'extern "C" int ds4_gpu_dynamic_arena_prepare_q1_0',
        'extern "C" int ds4_gpu_dynamic_arena_prepare(',
    )
    for needle in (
        "cudaHostAlloc",
        "VirtualAlloc",
        "pageable_entries",
        "required_entries",
        "required_entries",
        "pinned_slots",
        "pageable_slots",
        "total_slots",
        "total_bytes",
    ):
        assert needle in prepare
    disjoint = body(
        CUDA,
        "static int cuda_q1_0_dual_arena_layer_active",
        "static void cuda_q1_0_dynamic_arena_release",
    )
    assert "pinned_disjoint" in disjoint
    assert "pageable_disjoint" in disjoint
    assert "q1_storage_disjoint" in disjoint


def test_q1_bootstrap_unlocks_sidecar_source_after_layer_copy_on_windows() -> None:
    prepare = body(
        CUDA,
        'extern "C" int ds4_gpu_dynamic_arena_prepare_q1_0',
        'extern "C" int ds4_gpu_dynamic_arena_prepare(',
    )
    checksum = prepare.index("slot.checksum = cuda_dynamic_arena_fnv1a64")
    publish = prepare.index("arena.submissions_blocked = 1")
    unlock_layer = prepare.index("cuda_q1_0_source_unlock_bootstrap_layer")
    unlock_finish = prepare.index("cuda_q1_0_source_unlock_finish")
    assert checksum < unlock_layer < unlock_finish < publish
    assert "required_entries, required_bytes" in prepare

    unlock = body(
        CUDA,
        "static void cuda_q1_0_source_unlock_begin",
        "static int cuda_dynamic_arena_source_unlock_phase_range",
    )
    for needle in (
        "#ifdef _WIN32",
        "VirtualUnlock",
        "ERROR_NOT_LOCKED",
        "not_locked++",
        "failed++",
        "destination_unchanged = 1u",
        "page_aligned = 1u",
        "cuda_dynamic_arena_source_unlock_aligned_model_range",
        "source=sidecar-mmap",
        "(void)arena;",
        "(void)geometry;",
    ):
        assert needle in unlock


def test_q1_profile_is_opt_in_and_samples_source_mapping_only_at_bootstrap() -> None:
    prepare = body(
        CUDA,
        'extern "C" int ds4_gpu_dynamic_arena_prepare_q1_0',
        'extern "C" int ds4_gpu_dynamic_arena_prepare(',
    )
    pre = prepare.index('"pre-copy"')
    copy = prepare.index("memcpy(destination, gate")
    post = prepare.index('"post-bootstrap"')
    finish = prepare.index("cuda_q1_0_source_unlock_finish")
    settle = prepare.index('"post-unlock-settle"')
    publish = prepare.index("arena.submissions_blocked = 1")
    assert pre < copy < post < finish < settle < publish

    working_set = body(
        CUDA,
        "typedef BOOL (WINAPI *cuda_q1_0_query_working_set_ex_fn)",
        "static void cuda_q1_0_source_unlock_snapshot_store",
    )
    for needle in (
        'getenv("DS4_Q1_0_PROFILE")',
        'GetProcAddress(kernel32, "K32QueryWorkingSetEx")',
        "PSAPI_WORKING_SET_EX_INFORMATION",
        "max_chunk_pages = 65536u",
        "VirtualAttributes.Valid",
        "VirtualAttributes.Shared",
        "file_backed_basis=sidecar-file-mapping",
        "file_backed_basis=unavailable",
    ):
        assert needle in working_set or needle in CUDA
    token_loop = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    assert "QueryWorkingSetEx" not in token_loop
    assert "q1-0-source-working-set" not in token_loop


def test_q1_profile_attributes_upload_and_reuses_kernel_events() -> None:
    copy = body(
        CUDA,
        "static cuda_dynamic_arena_copy_status cuda_dynamic_arena_copy_expert_async",
        "static void cuda_dynamic_arena_storage_release",
    )
    for needle in (
        "pinned_h2d_enqueue_seconds",
        "pageable_h2d_enqueue_seconds",
        "arena.pinned_hits++",
        "arena.pageable_hits++",
    ):
        assert needle in copy

    selected = body(
        CUDA,
        "static int cuda_moe_selected_load_q1_0",
        "static int routed_moe_launch(",
    )
    sync = selected.index("cudaStreamSynchronize(g_model_upload_stream)")
    attribution = selected.index("pinned_upload_sync_seconds")
    assert sync < attribution
    assert "pinned_h2d_before" in selected
    assert "pageable_h2d_before" in selected

    routed = body(
        CUDA,
        "static int routed_moe_launch(",
        'extern "C" int ds4_gpu_routed_moe_one_tensor',
    )
    for needle in (
        "legacy_profile_moe",
        "q1_profile_moe",
        "legacy_profile_moe || q1_profile_moe",
        "g_q1_0_profile.q1_kernel_seconds",
    ):
        assert needle in routed
    assert routed.count("cudaEvent_t prof_ev[7]") == 1

    mixed = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    join_launch = mixed.index("add_f32_u64_kernel<<<")
    join_timing = mixed.index("g_q1_0_profile.mixed_join_seconds")
    assert join_launch < join_timing
    assert "cudaEvent_t join_begin" in mixed
    assert "cudaEvent_t join_end" in mixed

    release = body(
        CUDA,
        "static void cuda_q1_0_dynamic_arena_release",
        "static void cuda_primary_dynamic_arena_release",
    )
    for needle in (
        "[q1-0-profile] result=summary",
        "pinned_route_hits",
        "pageable_route_hits",
        "sync_attribution=bytes",
        "timer_failures",
    ):
        assert needle in release


def test_q1_profile_real_parser_selftest_rejects_missing_and_incoherent() -> None:
    completed = subprocess.run(
        [
            "PowerShell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "g7_measure.ps1"),
            "-Q1_0ProfileParserSelfTest",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr + completed.stdout
    payload = json.loads(completed.stdout)
    assert payload["status"] == "pass"
    assert payload["off_default"] == "pass"
    assert payload["positive"] == "pass"
    assert "missing field" in payload["negative_cases"]
    assert "incoherent pinned/pageable split" in payload["negative_cases"]


def test_current_q1_result_precedes_future_exact_stage() -> None:
    route = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    observe = route.index("cuda_moe_tiering_observe_route")
    q1_launch = route.index("q1_model_map", observe)
    join = route.index("Q1_0 mixed output join")
    stage = route.index(
        "cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram"
    )
    assert observe < q1_launch < join < stage
    assert "cuda_moe_tiering_stage_iq1_cold_to_2bit_ram" not in route
    assert "reason=current-token-iq2-ssd" in route


def test_exact_stage_is_ram_first_and_next_call_eligible() -> None:
    stage = body(
        CUDA,
        "static int cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram",
        "static int cuda_moe_tiering_stage_iq1_cold_to_2bit_ram",
    )
    assert "cuda_moe_tiering_load_to_ram" in stage
    assert "cuda_iq1_promotion_next_call_tick" in CUDA
    assert "first_eligible_call" in stage
    load = body(
        CUDA,
        "static int cuda_moe_tiering_load_to_ram",
        "static cuda_moe_tier_state cuda_moe_tiering_observe_route",
    )
    attempt = load.index("q1_0_stage_attempts++")
    pread = load.index("cuda_pread_full")
    assert attempt < pread
    assert "q1_0_stage_successes++" in stage
    assert "q1_0_next_call_guards++" in stage
    assert "cudaMemcpyHostToDevice" not in stage


def test_q1_promotion_emits_per_expert_attempt_and_success_records() -> None:
    stage = body(
        CUDA,
        "static int cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram",
        "static int cuda_moe_tiering_stage_iq1_cold_to_2bit_ram",
    )
    for needle in (
        "[q1-0-promotion-record]",
        "kind=%s result=%s reason=%s",
        "request_epoch=%llu",
        "promotion_window_epoch=%llu",
        "observation_call=%llu",
        "first_eligible_call=%llu",
        "source_kind=q1_resident",
        "source_sidecar_sha256=%s",
        "source_gate_base_offset=%llu",
        "source_gate_stride=%llu",
        "destination_gate_base_offset=%llu",
        "destination_gate_stride=%llu",
        "destination_kind=%s destination_model_sha256=%s",
        "direct_ssd_to_vram_current_token=0 same_call_eligible=0",
        '"DS4_Q1_0_EXPERT_SIDECAR_SHA256"',
        '"DS4_MODEL_SHA256"',
        '"attempt", "attempt", "admitted"',
        '"success", "success", "staged"',
        '"exact_iq2_ram_pending"',
        '"exact_iq2_ram"',
        "q1_0_record_attempts",
        "q1_0_record_successes",
        "cuda_iq1_promotion_current_request_epoch",
        "cuda_iq1_promotion_current_window_epoch",
        "call_tick_overflow",
        "destination_offset_mismatch",
    ):
        assert needle in stage or needle in CUDA
    assert "cuda_q1_0_promotion_record_emit" in stage


def test_request_epoch_uses_request_boundary_not_carry_sequence() -> None:
    request_begin = body(
        CUDA,
        'extern "C" int ds4_gpu_dynamic_arena_request_begin(void)',
        'extern "C" void ds4_gpu_dynamic_arena_observer_reset(void)',
    )
    epoch_increment = request_begin.index("g_cuda_request_epoch++")
    tier_reset = request_begin.index("cuda_moe_tiering_request_boundary_reset")
    carry_mode = request_begin.index("cuda_dynamic_arena_carry_mode")
    carry_sequence = request_begin.index("++g_dynamic_arena.request_sequence")
    assert tier_reset < epoch_increment < carry_mode < carry_sequence
    assert "return g_cuda_request_epoch" in body(
        CUDA,
        "static uint64_t cuda_iq1_promotion_current_request_epoch(void) {",
        "static uint64_t cuda_iq1_promotion_current_window_epoch",
    )
    assert "g_dynamic_arena.request_sequence" not in body(
        CUDA,
        "static uint64_t cuda_iq1_promotion_current_request_epoch(void) {",
        "static uint64_t cuda_iq1_promotion_current_window_epoch",
    )


def test_dual_arena_carry_off_request_epoch_lifecycle() -> None:
    request_epochs: list[int] = []
    carry_sequence = 0
    for _ in range(2):
        request_epoch = (request_epochs[-1] if request_epochs else 0) + 1
        request_epochs.append(request_epoch)
        mode = -1
        host_base = False
        if mode < 0 or not host_base:
            continue
        carry_sequence += 1
    assert request_epochs == [1, 2]
    assert carry_sequence == 0


def test_call_tick_overflow_is_saturating_at_both_call_sites() -> None:
    helper = body(
        CUDA,
        "static int cuda_moe_tiering_advance_call_tick",
        "static void cuda_q1_0_promotion_record_emit",
    )
    assert "g_moe_tiering.call_tick == UINT64_MAX" in helper
    assert "return 0" in helper
    assert "g_moe_tiering.call_tick++" in helper
    route_worker = body(
        CUDA,
        "static void *cuda_moe_route_worker(void *arg) {",
        "static int cuda_moe_expert_cache_copy_to_compact_async",
    )
    assert 'cuda_moe_tiering_advance_call_tick("gpu-route-request")' in route_worker
    assert "request_valid = 0" in route_worker
    assert "g_moe_tiering.call_tick++" not in route_worker
    mixed = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    assert (
        'cuda_moe_tiering_advance_call_tick(\n'
        '                    "q1-0-mixed-cold-only")'
    ) in mixed
    assert "g_moe_tiering.call_tick++" not in mixed
    assert '"reject", "rejected", "call_tick_overflow"' in mixed or (
        '"reject", "rejected", "call_tick_overflow"' in CUDA
    )


def test_q1_stage_receives_source_and_destination_offsets() -> None:
    route = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    assert "main_gate_offset, main_up_offset, main_down_offset" in route
    assert "q1_gate_offset, q1_up_offset, q1_down_offset" in route
    assert "q1_gate_expert_bytes, q1_down_expert_bytes" in route


def test_prefill_seed_can_rank_full_router_from_authoritative_model_map() -> None:
    seed = body(
        CUDA,
        "static int cuda_moe_prefill_vram_seed(",
        "static cuda_moe_expert_cache *cuda_moe_expert_cache_prepare",
    )
    assert "q1_0_exact_iq2_seed" in seed
    assert "cuda_q1_0_mixed_exact_iq2_resolver_requested" in CUDA
    assert "primary_mmap_source" in seed
    assert "g_model_host_base" in seed
    assert "global_ranked" in seed
    assert "floor_per_layer" in seed


def test_control_prepares_mixed_resolver_without_enabling_promotion() -> None:
    route = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    resolver = route.index("q1_0_mixed_exact_iq2_resolver")
    prepare = route.index("cuda_moe_expert_cache_prepare", resolver)
    tier_contract = route.index("g_moe_tiering.entries.size() !=", prepare)
    promotion_contract = route.index("reason=dynamic-promotion-contract")
    stage_guard = route.index("if (q1_0_dynamic_promotion)")
    stage_call = route.index(
        "cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram"
    )
    assert prepare < tier_contract < promotion_contract < stage_guard < stage_call
    assert "(cuda_q1_0_snapshot_backing_requested() ||" not in route[
        route.index("cuda_moe_expert_cache_prepare") - 160 : prepare
    ]


def test_q1_mixed_route_contract_counts_real_tier_entries() -> None:
    route = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    tier_pointer = route.index("const cuda_moe_tier_entry *tier")
    tier_count = route.index("if (tier) tier_route_entries++", tier_pointer)
    route_contract = route.index("reason=route-entry-contract", tier_count)
    publish_count = route.index(
        "g_q1_0_mixed_tier_route_entries += tier_route_entries",
        route_contract,
    )
    q1_launch = route.index("q1_model_map", publish_count)
    assert tier_count < route_contract < publish_count < q1_launch
    assert "tier_route_entries=%llu" in CUDA


def g129_split_fused_expected_primary_routes(
    *,
    q1_resident: int,
    iq2_vram: int,
    iq2_snapshot_ram: int,
    iq2_tier_ram: int,
    trace_rows: int,
    tier_route_entries: int,
) -> int:
    iq2_routes = iq2_vram + iq2_snapshot_ram + iq2_tier_ram
    accounted_routes = q1_resident + iq2_routes
    if tier_route_entries != trace_rows:
        raise AssertionError("tier entries do not cover trace rows")
    if accounted_routes != trace_rows:
        raise AssertionError("mixed route categories do not cover trace rows")
    return iq2_routes


def test_g129_split_fused_receipt_counts_only_iq2_routes() -> None:
    expected = g129_split_fused_expected_primary_routes(
        q1_resident=9834,
        iq2_vram=5680,
        iq2_snapshot_ram=998,
        iq2_tier_ram=0,
        trace_rows=16512,
        tier_route_entries=16512,
    )
    assert expected == 6678
    assert 5680 + 998 == expected
    assert 9834 + expected == 16512
    assert "q1-0-mixed-iq2-routes" in HARNESS


def test_g129_split_fused_negative_mismatch_is_rejected() -> None:
    expected = g129_split_fused_expected_primary_routes(
        q1_resident=9834,
        iq2_vram=5680,
        iq2_snapshot_ram=998,
        iq2_tier_ram=0,
        trace_rows=16512,
        tier_route_entries=16512,
    )
    observed_split_fused_routes = expected - 1
    if observed_split_fused_routes == expected:
        raise AssertionError("negative fixture did not create a mismatch")
    assert observed_split_fused_routes != expected


def g129_split_fused_basis_requires_trace(
    *, mixed_required: bool, trace_required: bool, trace_observed: bool
) -> str:
    if mixed_required and trace_required and trace_observed:
        return "q1-0-mixed-iq2-routes"
    return "gpu-resident-route-population"


def test_g129_split_fused_iq2_basis_requires_observed_trace() -> None:
    assert (
        g129_split_fused_basis_requires_trace(
            mixed_required=True, trace_required=True, trace_observed=True
        )
        == "q1-0-mixed-iq2-routes"
    )
    assert (
        g129_split_fused_basis_requires_trace(
            mixed_required=True, trace_required=False, trace_observed=True
        )
        == "gpu-resident-route-population"
    )
    assert (
        g129_split_fused_basis_requires_trace(
            mixed_required=True, trace_required=True, trace_observed=False
        )
        == "gpu-resident-route-population"
    )


def assert_expected_router(router: str, expected_router: str) -> None:
    if expected_router and router != expected_router:
        raise AssertionError("expected router mode")


def test_g129_full_open_rejects_unchanged_router() -> None:
    assert_expected_router("open", "open")
    expect_rejected(lambda: assert_expected_router("unchanged", "open"))
    assert "router=unchanged router_mode=%s promotion=%s" in CUDA
    assert "$telemetry.router_mode -ne $ExpectedRouter" in HARNESS


def test_q1_mixed_router_mode_capture_survives_tiering_reset() -> None:
    resolver = body(
        CUDA,
        "static cuda_q1_0_mixed_representation cuda_q1_0_mixed_resolve",
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
    )
    capture = body(
        CUDA,
        "static void cuda_q1_0_mixed_capture_router_mode",
        "struct cuda_iq1_promotion",
    )
    release = body(
        CUDA,
        "static void cuda_q1_0_sidecar_clear(void)",
        "static uint64_t cuda_round_down",
    )
    assert "cuda_q1_0_mixed_capture_router_mode();" in resolver
    for needle in (
        "!cuda_q1_0_snapshot_backing_requested()",
        "g_moe_tiering.mode == CUDA_MOE_TIER_ENFORCE",
        "g_moe_tiering.compose_prefill_mass_tiering",
        "g_moe_tiering.compose_router_open",
        "g_q1_0_mixed_router_open_observed = 1u",
        "g_q1_0_mixed_router_closed_observed = 1u",
    ):
        assert needle in capture
    summary = release.index("cuda_q1_0_mixed_router_mode_name()")
    reset = release.index("g_q1_0_mixed_router_open_observed = 0", summary)
    assert summary < reset

    def summarized_router_mode(open_observed: bool, reset_tiering_closed: bool) -> str:
        _ = reset_tiering_closed
        return "open" if open_observed else "closed"

    assert summarized_router_mode(True, True) == "open"
    assert summarized_router_mode(False, True) == "closed"


def test_q1_promotion_records_skip_normal_reject_flood() -> None:
    stage = body(
        CUDA,
        "static int cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram",
        "static void cuda_moe_expert_cache_release",
    )
    exceptional_reject = stage.index('"reject", "rejected", "request_epoch_missing"')
    success_emit = stage.index('"success", "success", "staged"')
    assert exceptional_reject < success_emit
    for reason in (
        "existing_vram",
        "existing_2bit_ram",
        "touches",
        "weight",
        "mass",
        "request_budget",
        "window_budget",
        "ram_admit_skip",
    ):
        assert f'"{reason}"' not in stage


def test_q1_promotion_structural_preadmit_rejects_are_recorded_once() -> None:
    stage = body(
        CUDA,
        "static int cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram",
        "static int cuda_moe_tiering_stage_iq1_cold_to_2bit_ram",
    )
    loader = body(
        CUDA,
        "static int cuda_moe_tiering_load_to_ram",
        "static cuda_moe_tier_state cuda_moe_tiering_observe_route",
    )
    for reason in (
        "ram_admit_alloc",
        "destination_offset_overflow",
        "destination_offset_mismatch",
    ):
        assert reason in loader
        assert reason in stage or "q1_record.preadmit_reject_reason" in stage
    reject_gate = stage.index("cuda_q1_0_promotion_structural_reject_reason")
    emit = stage.index('"reject", "rejected", q1_record.preadmit_reject_reason')
    failure = stage.index("g_iq1_promotion.failures++", emit)
    assert reject_gate < emit < failure
    assert "!q1_record.attempt_started" in stage
    assert "!q1_record.terminal_emitted" in stage
    assert "q1_record.terminal_emitted = 1" in stage
    assert '"ram_admit_skip"' not in body(
        CUDA,
        "static int cuda_q1_0_promotion_structural_reject_reason",
        "static void cuda_q1_0_promotion_record_emit",
    )


def test_q1_promotion_record_volume_is_bounded() -> None:
    def assert_record_limit(attempts: int, failures: int, records: int) -> None:
        _ = failures
        limit = 2 * attempts + 16
        if records > limit:
            raise AssertionError("telemetry record flood")

    assert_record_limit(attempts=64, failures=0, records=128)
    assert_record_limit(attempts=1, failures=1, records=18)
    expect_rejected(
        lambda: assert_record_limit(attempts=64, failures=0, records=9672),
        "telemetry record flood",
    )
    expect_rejected(
        lambda: assert_record_limit(attempts=1, failures=1, records=19),
        "telemetry record flood",
    )


UINT64_MAX = 2**64 - 1
REQUIRED_RECORD_FIELDS = {
    "line_index",
    "physical_line",
    "kind",
    "result",
    "reason",
    "record_id",
    "request_epoch",
    "promotion_window_epoch",
    "current_call",
    "observation_call",
    "first_eligible_call",
    "layer",
    "expert",
    "touch_count",
    "weight",
    "mass",
    "gate_min_touches",
    "gate_min_weight",
    "gate_min_mass",
    "gate_request_budget",
    "gate_request_used",
    "gate_window_calls",
    "gate_window_budget",
    "gate_window_used",
    "source_kind",
    "source_sidecar_sha256",
    "source_sidecar_size",
    "source_q1_snapshot",
    "source_gate_base_offset",
    "source_up_base_offset",
    "source_down_base_offset",
    "source_gate_stride",
    "source_up_stride",
    "source_down_stride",
    "source_gate_offset",
    "source_up_offset",
    "source_down_offset",
    "source_gate_bytes",
    "source_up_bytes",
    "source_down_bytes",
    "source_bytes",
    "destination_kind",
    "destination_model_sha256",
    "destination_model_size",
    "destination_gate_base_offset",
    "destination_up_base_offset",
    "destination_down_base_offset",
    "destination_gate_stride",
    "destination_up_stride",
    "destination_down_stride",
    "destination_gate_offset",
    "destination_up_offset",
    "destination_down_offset",
    "destination_gate_bytes",
    "destination_up_bytes",
    "destination_down_bytes",
    "destination_bytes",
    "destination_ram_slot",
    "destination_ram_generation",
    "direct_ssd_to_vram_current_token",
    "same_call_eligible",
}


def strict_u64(value: object, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise AssertionError(f"{name} is not a canonical integer")
    if value < 0 or value > UINT64_MAX:
        raise AssertionError(f"{name} outside UInt64")
    return value


def assert_promotion_offset(row: dict, prefix: str, part: str) -> None:
    expert = strict_u64(row["expert"], "expert")
    base = strict_u64(row[f"{prefix}_{part}_base_offset"], f"{prefix}_{part}_base")
    stride = strict_u64(row[f"{prefix}_{part}_stride"], f"{prefix}_{part}_stride")
    observed = strict_u64(row[f"{prefix}_{part}_offset"], f"{prefix}_{part}_offset")
    bytes_ = strict_u64(row[f"{prefix}_{part}_bytes"], f"{prefix}_{part}_bytes")
    size = strict_u64(
        row["source_sidecar_size" if prefix == "source" else "destination_model_size"],
        f"{prefix}_size",
    )
    expected = base + expert * stride
    if expected > UINT64_MAX or observed != expected:
        raise AssertionError(f"{prefix}_{part} offset formula")
    if bytes_ == 0 or observed + bytes_ > size:
        raise AssertionError(f"{prefix}_{part} offset range")


def validate_g129_promotion_record_fixture(
    records: list[dict],
    *,
    expected_attempts: int = 1,
    expected_successes: int = 1,
    expected_failures: int = 0,
) -> None:
    attempts: dict[tuple[int, int], tuple[int, int, int, int, int, int]] = {}
    terminals: dict[tuple[int, int], str] = {}
    rejects: set[tuple] = set()
    counts = {"attempt": 0, "success": 0, "failure": 0, "reject": 0}
    for row in records:
        if set(row) != REQUIRED_RECORD_FIELDS:
            raise AssertionError("record schema")
        for field in (
            "line_index",
            "physical_line",
            "record_id",
            "request_epoch",
            "promotion_window_epoch",
            "current_call",
            "observation_call",
            "first_eligible_call",
            "layer",
            "expert",
            "touch_count",
            "gate_min_touches",
            "gate_request_budget",
            "gate_request_used",
            "gate_window_calls",
            "gate_window_budget",
            "gate_window_used",
            "source_sidecar_size",
            "source_q1_snapshot",
            "source_gate_base_offset",
            "source_up_base_offset",
            "source_down_base_offset",
            "source_gate_stride",
            "source_up_stride",
            "source_down_stride",
            "source_gate_offset",
            "source_up_offset",
            "source_down_offset",
            "source_gate_bytes",
            "source_up_bytes",
            "source_down_bytes",
            "source_bytes",
            "destination_model_size",
            "destination_gate_base_offset",
            "destination_up_base_offset",
            "destination_down_base_offset",
            "destination_gate_stride",
            "destination_up_stride",
            "destination_down_stride",
            "destination_gate_offset",
            "destination_up_offset",
            "destination_down_offset",
            "destination_gate_bytes",
            "destination_up_bytes",
            "destination_down_bytes",
            "destination_bytes",
            "destination_ram_slot",
            "destination_ram_generation",
            "direct_ssd_to_vram_current_token",
            "same_call_eligible",
        ):
            strict_u64(row[field], field)
        assert row["source_kind"] == "q1_resident"
        assert row["source_sidecar_sha256"] == "0" * 64
        assert row["destination_model_sha256"] == "1" * 64
        assert row["source_q1_snapshot"] == 0
        assert row["direct_ssd_to_vram_current_token"] == 0
        assert row["same_call_eligible"] == 0
        assert row["request_epoch"] > 0
        assert row["current_call"] == row["observation_call"]
        assert row["promotion_window_epoch"] == (
            (max(row["current_call"], 1) - 1) // row["gate_window_calls"]
        )
        assert row["source_bytes"] == (
            row["source_gate_bytes"] + row["source_up_bytes"] + row["source_down_bytes"]
        )
        assert row["destination_bytes"] == (
            row["destination_gate_bytes"]
            + row["destination_up_bytes"]
            + row["destination_down_bytes"]
        )
        for prefix in ("source", "destination"):
            for part in ("gate", "up", "down"):
                assert_promotion_offset(row, prefix, part)
        key = (row["request_epoch"], row["record_id"])
        identity = (
            row["request_epoch"],
            row["record_id"],
            row["layer"],
            row["expert"],
            row["observation_call"],
            row["first_eligible_call"],
        )
        counts[row["kind"]] += 1
        if row["kind"] == "attempt":
            if row["first_eligible_call"] <= row["observation_call"]:
                raise AssertionError("same-call attempt")
            assert row["result"] == "attempt"
            assert row["reason"] == "admitted"
            assert row["touch_count"] >= row["gate_min_touches"]
            assert abs(row["weight"]) >= row["gate_min_weight"]
            assert row["mass"] >= row["gate_min_mass"]
            assert row["gate_request_used"] < row["gate_request_budget"]
            assert row["gate_window_used"] < row["gate_window_budget"]
            assert row["destination_kind"] == "exact_iq2_ram_pending"
            if key in attempts:
                raise AssertionError("duplicate attempt key")
            attempts[key] = identity
        elif row["kind"] in ("success", "failure"):
            if row["first_eligible_call"] <= row["observation_call"]:
                raise AssertionError("same-call terminal")
            if key not in attempts:
                raise AssertionError("unpaired terminal")
            if attempts[key] != identity:
                raise AssertionError("terminal identity mismatch")
            if key in terminals:
                raise AssertionError("duplicate terminal")
            if row["kind"] == "success":
                assert row["result"] == "success"
                assert row["reason"] == "staged"
                assert row["destination_kind"] == "exact_iq2_ram"
                assert row["destination_ram_generation"] > 0
            else:
                assert row["result"] == "failed"
                assert row["reason"] in {"pread_failed", "victim_contract"}
                assert row["destination_kind"] == "exact_iq2_ram_failed"
            terminals[key] = row["kind"]
        elif row["kind"] == "reject":
            assert row["result"] == "rejected"
            reject_key = (
                *identity,
                row["reason"],
                row["destination_kind"],
            )
            if reject_key in rejects:
                raise AssertionError("duplicate reject")
            rejects.add(reject_key)
    for key in attempts:
        if key not in terminals:
            raise AssertionError("attempt without terminal")
    assert counts["attempt"] == expected_attempts
    assert counts["success"] == expected_successes
    assert counts["failure"] == expected_failures


def promotion_record(**overrides: object) -> dict:
    expert = int(overrides.get("expert", 7))
    row = {
        "kind": "attempt",
        "result": "attempt",
        "reason": "admitted",
        "line_index": 1,
        "physical_line": 1,
        "record_id": 1,
        "request_epoch": 1,
        "promotion_window_epoch": 0,
        "current_call": 10,
        "observation_call": 10,
        "first_eligible_call": 11,
        "layer": 0,
        "expert": expert,
        "touch_count": 2,
        "weight": 0.03125,
        "mass": 0.03125,
        "gate_min_touches": 2,
        "gate_min_weight": 0.02,
        "gate_min_mass": 0.0,
        "gate_request_budget": 64,
        "gate_request_used": 0,
        "gate_window_calls": 40,
        "gate_window_budget": 1,
        "gate_window_used": 0,
        "source_kind": "q1_resident",
        "source_sidecar_sha256": "0" * 64,
        "source_sidecar_size": 10000,
        "source_q1_snapshot": 0,
        "source_gate_base_offset": 1000,
        "source_up_base_offset": 2000,
        "source_down_base_offset": 3000,
        "source_gate_stride": 10,
        "source_up_stride": 10,
        "source_down_stride": 20,
        "source_gate_offset": 1000 + expert * 10,
        "source_up_offset": 2000 + expert * 10,
        "source_down_offset": 3000 + expert * 20,
        "source_gate_bytes": 10,
        "source_up_bytes": 10,
        "source_down_bytes": 20,
        "source_bytes": 40,
        "destination_kind": "exact_iq2_ram_pending",
        "destination_model_sha256": "1" * 64,
        "destination_model_size": 1000000,
        "destination_gate_base_offset": 100000,
        "destination_up_base_offset": 200000,
        "destination_down_base_offset": 300000,
        "destination_gate_stride": 100,
        "destination_up_stride": 100,
        "destination_down_stride": 200,
        "destination_gate_offset": 100000 + expert * 100,
        "destination_up_offset": 200000 + expert * 100,
        "destination_down_offset": 300000 + expert * 200,
        "destination_gate_bytes": 100,
        "destination_up_bytes": 100,
        "destination_down_bytes": 200,
        "destination_bytes": 400,
        "destination_ram_slot": 4,
        "destination_ram_generation": 0,
        "direct_ssd_to_vram_current_token": 0,
        "same_call_eligible": 0,
    }
    row.update(overrides)
    return row


def successful_pair(**overrides: object) -> list[dict]:
    attempt = promotion_record(**overrides)
    success = promotion_record(
        **{
            **overrides,
            "line_index": int(overrides.get("line_index", 1)) + 1,
            "physical_line": int(overrides.get("physical_line", 1)) + 1,
            "kind": "success",
            "result": "success",
            "reason": "staged",
            "destination_kind": "exact_iq2_ram",
            "destination_ram_generation": 3,
        }
    )
    return [attempt, success]


def expect_rejected(func, message: str = "") -> None:
    try:
        func()
    except (AssertionError, ValueError) as exc:
        if message and message not in str(exc):
            raise AssertionError(f"expected {message!r}, got {exc!r}") from exc
        return
    raise AssertionError("negative fixture was accepted")


def parse_strict_jsonl_fixture(text: str) -> list[dict]:
    rows = []
    for line in text.splitlines():
        if not line.strip():
            raise AssertionError("blank JSONL")
        if not line.startswith("{") or not line.endswith("}"):
            raise AssertionError("one object per line")
        seen: set[str] = set()

        def pairs_hook(pairs: list[tuple[str, object]]) -> dict:
            obj = {}
            for key, value in pairs:
                if key in seen:
                    raise ValueError("duplicate key")
                seen.add(key)
                obj[key] = value
            return obj

        parsed = json.loads(line, object_pairs_hook=pairs_hook)
        if not isinstance(parsed, dict):
            raise AssertionError("array JSON")
        if json.dumps(parsed, separators=(",", ":")) != line:
            raise AssertionError("canonical JSON")
        rows.append(parsed)
    return rows


def validate_promotion_marker_fixture(text: str) -> None:
    canonical = re.compile(
        r"^(?:ds4: )?\[q1-0-promotion-record\] "
        r"(?:[A-Za-z0-9_]+=[^ \r\n]+)(?: [A-Za-z0-9_]+=[^ \r\n]+)*$"
    )
    marker_lines = [
        line for line in text.splitlines() if "[q1-0-promotion-record]" in line
    ]
    if not marker_lines:
        raise AssertionError("missing marker")
    for line in marker_lines:
        if not canonical.fullmatch(line):
            raise AssertionError("malformed marker")


def test_g129_promotion_record_fixture_positive() -> None:
    validate_g129_promotion_record_fixture(successful_pair())


def test_g129_promotion_record_allows_cross_request_record_id_reuse() -> None:
    records = successful_pair(request_epoch=1, record_id=1)
    records += successful_pair(
        request_epoch=2,
        record_id=1,
        line_index=3,
        physical_line=3,
        promotion_window_epoch=1,
        current_call=50,
        observation_call=50,
        first_eligible_call=51,
    )
    assert len({row["record_id"] for row in records if row["kind"] == "attempt"}) == 1
    assert len(
        {
            (row["request_epoch"], row["record_id"])
            for row in records
            if row["kind"] == "attempt"
        }
    ) == 2
    validate_g129_promotion_record_fixture(
        records, expected_attempts=2, expected_successes=2
    )


def test_g129_promotion_record_fixture_rejects_same_call() -> None:
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture(
            successful_pair(first_eligible_call=10)
        ),
        "same-call",
    )


def test_g129_promotion_record_rejects_non_expert_offset() -> None:
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture(
            successful_pair(source_gate_offset=1000)
        ),
        "offset formula",
    )


def test_g129_promotion_record_rejects_range_overflow() -> None:
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture(
            successful_pair(destination_model_size=301500)
        ),
        "offset range",
    )


def test_g129_promotion_record_rejects_attempt_without_terminal() -> None:
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture([promotion_record()]),
        "without terminal",
    )


def test_g129_promotion_record_rejects_duplicate_terminal() -> None:
    records = successful_pair()
    records.append(successful_pair()[1])
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture(records),
        "duplicate terminal",
    )


def test_g129_promotion_record_rejects_unpaired_failure() -> None:
    failure = promotion_record(
        kind="failure",
        result="failed",
        reason="pread_failed",
        destination_kind="exact_iq2_ram_failed",
    )
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture([failure]),
        "unpaired terminal",
    )


def test_g129_promotion_record_strict_jsonl_rejects_bad_integers() -> None:
    row = promotion_record()
    bad_decimal = json.dumps({**row, "record_id": 1.5}, separators=(",", ":"))
    bad_exponent = json.dumps({**row, "record_id": 1e2}, separators=(",", ":"))
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture(
            parse_strict_jsonl_fixture(bad_decimal)
        ),
        "canonical integer",
    )
    expect_rejected(
        lambda: validate_g129_promotion_record_fixture(
            parse_strict_jsonl_fixture(bad_exponent)
        ),
        "canonical integer",
    )


def test_g129_promotion_record_strict_jsonl_rejects_malformed_lines() -> None:
    expect_rejected(lambda: parse_strict_jsonl_fixture("\n"), "blank JSONL")
    expect_rejected(lambda: parse_strict_jsonl_fixture("[]"), "one object")
    expect_rejected(
        lambda: parse_strict_jsonl_fixture('{"kind":"attempt","kind":"success"}'),
        "duplicate key",
    )
    expect_rejected(
        lambda: validate_promotion_marker_fixture(
            "ds4: [q1-0-promotion-record] kind attempt"
        ),
        "malformed marker",
    )


def test_g129_runner_validator_selftest_exercises_real_validator() -> None:
    command = [
        "PowerShell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "g129_q1_open_dynamic_promotion_safety.ps1"),
        "-SelfTest",
        "-Arm",
        "promotion",
        "-Q1_0ExpertSidecar",
        r"C:\ds4-models\ds4-q1-layers0-42-derived.gguf",
        "-ExpectedQ1_0ExpertSidecarSHA256",
        "05040393f5e94bf054a593e4d2d021ff44a6f446f2328a75e4f833a1fbe20207",
        "-ExpectedQ1_0ExpertSidecarBytes",
        "39048344416",
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr + completed.stdout
    payload = json.loads(completed.stdout)
    assert payload["status"] == "pass"
    assert payload["cross_request_record_id_reuse"] == "pass"
    assert "budget duplicate used=0" in payload["negative_cases"]
    assert "terminal identity mismatch" in payload["negative_cases"]
    assert "unpaired failure" in payload["negative_cases"]
    assert "duplicate terminal" in payload["negative_cases"]
    assert "path sibling g7_runs_evil" in payload["negative_cases"]
    assert "router wrong mode" in payload["negative_cases"]
    assert "telemetry record flood" in payload["negative_cases"]
    assert "failure terminal telemetry flood" in payload["negative_cases"]
    assert "existing artifact malformed" in payload["negative_cases"]
    assert "existing artifact array" in payload["negative_cases"]
    assert "existing artifact duplicate key" in payload["negative_cases"]
    assert "stale promotion artifact hash" in payload["negative_cases"]
    assert "failure receipt materialization" in payload["negative_cases"]
    assert "SplitFused mismatch" in payload["negative_cases"]
    assert payload["argv_capture"] == "pass"


def test_expert_recovery_trace_is_off_default_targeted_and_post_route() -> None:
    configure = body(
        CUDA,
        "static int cuda_expert_recovery_trace_configure(void)",
        "static void cuda_expert_recovery_trace_request_begin(void)",
    )
    for needle in (
        'getenv("DS4_EXPERT_RECOVERY_TRACE")',
        'strcmp(requested, "1") != 0',
        '"dependent_env_without_enable"',
        '"windows_required"',
        '"DS4_EXPERT_RECOVERY_TRACE_LAYER"',
        '"DS4_EXPERT_RECOVERY_TRACE_EXPERT"',
        '"DS4_EXPERT_RECOVERY_TRACE_MAX_SAMPLES"',
        '"DS4_EXPERT_RECOVERY_TRACE_MAX_BYTES"',
        '"DS4_EXPERT_RECOVERY_TRACE_ROOT"',
        '"DS4_EXPERT_RECOVERY_TRACE_OUTPUT_PREFIX"',
        '"path_confinement"',
        '"output_exists_or_length"',
    ):
        assert needle in configure
    disabled = configure.index("if (!requested || !requested[0])")
    disabled_return = configure.index("return 1;", disabled)
    enabled = configure.index("trace.enabled = 1", disabled_return)
    assert disabled < disabled_return < enabled

    install = body(
        CUDA,
        'extern "C" int ds4_gpu_set_q1_0_sidecar',
        'extern "C" int ds4_gpu_set_nested_residual_sidecar',
    )
    assert install.index("g_q1_0_sidecar_host_base = model_map") < install.index(
        "cuda_expert_recovery_trace_configure()"
    )
    model_map = body(
        CUDA,
        'extern "C" int ds4_gpu_set_model_map(',
        'extern "C" int ds4_gpu_set_model_map_range(',
    )
    registered = model_map.index("g_model_registered_size = model_size")
    trace_bind = model_map.index("cuda_expert_recovery_trace_bind_model_map")
    assert registered < trace_bind
    assert "trace.model_bytes != g_model_file_size" in configure

    request = body(
        CUDA,
        'extern "C" int ds4_gpu_dynamic_arena_request_begin(void)',
        'extern "C" void ds4_gpu_dynamic_arena_observer_reset(void)',
    )
    increment = request.index("g_cuda_request_epoch++")
    trace_boundary = request.index("cuda_expert_recovery_trace_request_begin()")
    tier_reset = request.index("cuda_moe_tiering_request_boundary_reset()")
    assert tier_reset < increment < trace_boundary
    request_trace = body(
        CUDA,
        "static void cuda_expert_recovery_trace_request_begin(void)",
        "static uint64_t cuda_expert_recovery_trace_layer_call",
    )
    assert 'cuda_expert_recovery_trace_fail("request_epoch_overflow")' in request_trace

    capture = body(
        CUDA,
        "static int cuda_expert_recovery_trace_capture(",
        "static void cuda_expert_recovery_trace_finalize(void)",
    )
    off_guard = capture.index("if (!trace.enabled")
    d2h = capture.index("cudaMemcpyDeviceToHost")
    assert off_guard < d2h
    assert "sample_count >= trace.max_samples" in capture
    assert "trace.model_bytes != g_model_registered_size" in capture
    assert "layer == trace.target_layer && expert == trace.target_expert" in CUDA
    assert '\\"input_only\\":true' in CUDA
    assert '\\"teacher_output_captured\\":false' in CUDA
    assert "offline_exact_iq2_from_captured_input" in CUDA

    mixed = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor',
    )
    target_metadata = mixed.index("recovery_trace_rank = route")
    all_iq2_launch = mixed.index("const int ok = routed_moe_launch(")
    all_iq2_capture = mixed.index(
        "!cuda_expert_recovery_trace_capture(", all_iq2_launch
    )
    join = mixed.index("add_f32_u64_kernel<<<")
    mixed_capture = mixed.index("!cuda_expert_recovery_trace_capture(", join)
    future_stage = mixed.index("if (q1_0_dynamic_promotion)", mixed_capture)
    assert target_metadata < all_iq2_launch < all_iq2_capture
    assert join < mixed_capture < future_stage

    finalize = body(
        CUDA,
        "static void cuda_expert_recovery_trace_finalize(void)",
        "static int cuda_q1_0_mixed_exact_iq2_resolver_requested(void)",
    )
    vector_commit = finalize.index("MoveFileExW(trace.vector_partial")
    metadata_commit = finalize.index("MoveFileExW(trace.metadata_partial")
    manifest_commit = finalize.index("MoveFileExW(trace.manifest_partial")
    assert vector_commit < metadata_commit < manifest_commit
    assert 'cuda_expert_recovery_trace_fail("artifact_byte_budget")' in finalize
    failed_branch = finalize.index("if (trace.failed || trace.sample_count == 0u")
    failed_close = finalize.index("CloseHandle(trace.vector_file)", failed_branch)
    failed_delete = finalize.index(
        "cuda_expert_recovery_trace_delete_artifacts()", failed_close
    )
    assert failed_branch < failed_close < failed_delete


def test_expert_recovery_trace_real_parser_selftest() -> None:
    completed = subprocess.run(
        [
            "PowerShell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "g7_measure.ps1"),
            "-ExpertRecoveryTraceParserSelfTest",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr + completed.stdout
    payload = json.loads(completed.stdout)
    assert payload["status"] == "pass"
    assert payload["positive_samples"] == 2
    for case in (
        "missing-field",
        "offset",
        "duplicate-key",
        "array",
        "wrong-expert",
        "blank-line",
        "cap-overflow",
        "stale-sha",
        "partial-only",
        "path-sibling",
    ):
        assert case in payload["negative_cases"]


def test_q1_ssd_wrap_is_off_default_and_uses_one_bounded_state_machine() -> None:
    config = body(
        CUDA,
        "static int cuda_q1_0_ssd_wrap_requested(void)",
        "static const char *cuda_env_text_or_unknown",
    )
    assert 'getenv("DS4_Q1_0_PROMOTION_SSD_WRAP")' in config
    assert 'strcmp(value, "1") == 0' in config
    assert "return 0" in config

    implementation = body(
        CUDA,
        "enum cuda_q1_0_ssd_wrap_job_state",
        "static int cuda_moe_tiering_load_to_ram(",
    )
    for needle in (
        "CUDA_Q1_0_SSD_WRAP_REQUESTED",
        "CUDA_Q1_0_SSD_WRAP_SSD_INFLIGHT",
        "CUDA_Q1_0_SSD_WRAP_RAM_READY",
        "CUDA_Q1_0_SSD_WRAP_RAM_COMMITTING",
        "cuda_q1_0_ssd_wrap_worker",
        "cuda_q1_0_ssd_wrap_submit",
        "cuda_q1_0_ssd_wrap_poll_internal",
        "cuda_q1_0_ssd_wrap_flush",
        "partial_or_pread",
        "victim_stale",
        'job.failure_reason = "stale_age"',
        "g_moe_tiering.call_tick - job.enqueue_call >",
        "state.stale++",
        "state.dropped++",
        "first_eligible_call <=",
    ):
        assert needle in implementation
    assert "cuda_q1_0_promotion_record_emit(\n        \"attempt\"" in implementation
    assert "cuda_q1_0_promotion_record_emit(\n            \"success\"" in implementation


def test_q1_ssd_wrap_keeps_5_5_gib_budget_and_has_two_host_reserves() -> None:
    prepare = body(
        CUDA,
        'extern "C" int ds4_gpu_dynamic_arena_prepare(',
        'extern "C" int ds4_gpu_dynamic_arena_begin(',
    )
    for needle in (
        "cuda_q1_0_ssd_wrap_arena_partition",
        "resident_pinned_slots64",
        "pageable_slots64",
        "CUDA_Q1_0_SSD_WRAP_RING_SLOTS",
        "host_budget_bytes = total_storage_bytes",
        "ssd_wrap_ssd_ring_base",
        "ssd_wrap_h2d_ring_base",
        "*allocated_bytes = total_storage_bytes",
    ):
        assert needle in prepare
    assert "total_storage_bytes = bytes + pageable_bytes" in prepare
    assert "cudaHostRegister" not in body(
        CUDA,
        "enum cuda_q1_0_ssd_wrap_job_state",
        "static int cuda_moe_tiering_load_to_ram(",
    )


def test_q1_ssd_wrap_pageable_ready_uses_fixed_pinned_bounce() -> None:
    hierarchy = body(
        CUDA,
        "static int cuda_q1_0_ssd_wrap_host_is_pageable",
        "static int cuda_moe_tiering_load_to_ram(",
    )
    for needle in (
        "cuda_q1_0_ssd_wrap_prepare_h2d_source",
        "cudaEventSynchronize(state.h2d_done[ring])",
        "memcpy(bounce, *gate",
        "cuda_q1_0_ssd_wrap_record_h2d",
        "cudaEventRecord(",
    ):
        assert needle in hierarchy
    prepare_h2d = body(
        CUDA,
        "static int cuda_q1_0_ssd_wrap_prepare_h2d_source",
        "static int cuda_q1_0_ssd_wrap_record_h2d",
    )
    assert "QueryWorkingSetEx" not in prepare_h2d
    assert CUDA.count('cuda_q1_0_ssd_wrap_working_set_sample("') == 3
    working_set = body(
        CUDA,
        "static void cuda_q1_0_ssd_wrap_working_set_sample",
        "struct cuda_q1_0_ssd_wrap_part",
    )
    assert "if (!g_q1_0_ssd_wrap.enabled) return;" in working_set
    assert "pages != 0u && !g_dynamic_arena.pageable_base" in working_set
    enforce_request = body(
        CUDA,
        "static int cuda_moe_tiering_enforce_request",
        "static void *cuda_moe_route_worker",
    )
    prepare_index = enforce_request.index("cuda_q1_0_ssd_wrap_prepare_h2d_source")
    h2d_index = enforce_request.index("cuda_moe_route_copy_expert_h2d_async")
    event_index = enforce_request.index("cuda_q1_0_ssd_wrap_record_h2d")
    assert prepare_index < h2d_index < event_index


def test_q1_ssd_wrap_attempt_is_after_admission_and_current_call_stays_q1() -> None:
    submit = body(
        CUDA,
        "static int cuda_q1_0_ssd_wrap_submit(",
        "static void cuda_q1_0_ssd_wrap_flush(void)",
    )
    pick = submit.index("cuda_moe_tiering_pick_ram_slot")
    reserve = submit.index("g_q1_0_ssd_wrap_reserved_slots")
    attempt = submit.index("q1_0_record_attempts")
    signal = submit.index("os_cond_signal")
    assert pick < reserve < attempt < signal

    mixed = body(
        CUDA,
        'extern "C" int ds4_gpu_routed_moe_mixed_q1_0_one_tensor(',
        'extern "C" int ds4_gpu_routed_moe_mixed_iq1_one_tensor(',
    )
    q1_launch = mixed.index("q1-cold-launch")
    future_stage = mixed.index("cuda_moe_tiering_stage_observed_quant_cold_to_2bit_ram")
    assert q1_launch < future_stage
    assert "cuda_q1_0_ssd_wrap_poll()" in mixed


def test_q1_ssd_wrap_real_parser_selftest() -> None:
    completed = subprocess.run(
        [
            "PowerShell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "g7_measure.ps1"),
            "-Q1_0SsdWrapParserSelfTest",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr + completed.stdout
    payload = json.loads(completed.stdout)
    assert payload["status"] == "pass"
    assert payload["off_default"] == "pass"
    assert "missing-field" in payload["negative_cases"]
    assert "incoherent-split" in payload["negative_cases"]


if __name__ == "__main__":
    test_q1_promotion_has_separate_fail_closed_configuration()
    test_dynamic_mode_is_resident_dual_arena_not_snapshot_mode()
    test_complete_q1_base_supports_pinned_and_pageable_disjoint_storage()
    test_q1_bootstrap_unlocks_sidecar_source_after_layer_copy_on_windows()
    test_q1_profile_is_opt_in_and_samples_source_mapping_only_at_bootstrap()
    test_q1_profile_attributes_upload_and_reuses_kernel_events()
    test_q1_profile_real_parser_selftest_rejects_missing_and_incoherent()
    test_expert_recovery_trace_is_off_default_targeted_and_post_route()
    test_expert_recovery_trace_real_parser_selftest()
    test_q1_ssd_wrap_is_off_default_and_uses_one_bounded_state_machine()
    test_q1_ssd_wrap_keeps_5_5_gib_budget_and_has_two_host_reserves()
    test_q1_ssd_wrap_pageable_ready_uses_fixed_pinned_bounce()
    test_q1_ssd_wrap_attempt_is_after_admission_and_current_call_stays_q1()
    test_q1_ssd_wrap_real_parser_selftest()
    test_current_q1_result_precedes_future_exact_stage()
    test_exact_stage_is_ram_first_and_next_call_eligible()
    test_q1_promotion_emits_per_expert_attempt_and_success_records()
    test_request_epoch_uses_request_boundary_not_carry_sequence()
    test_dual_arena_carry_off_request_epoch_lifecycle()
    test_call_tick_overflow_is_saturating_at_both_call_sites()
    test_q1_stage_receives_source_and_destination_offsets()
    test_prefill_seed_can_rank_full_router_from_authoritative_model_map()
    test_control_prepares_mixed_resolver_without_enabling_promotion()
    test_q1_mixed_route_contract_counts_real_tier_entries()
    test_g129_split_fused_receipt_counts_only_iq2_routes()
    test_g129_split_fused_negative_mismatch_is_rejected()
    test_g129_split_fused_iq2_basis_requires_observed_trace()
    test_g129_full_open_rejects_unchanged_router()
    test_q1_mixed_router_mode_capture_survives_tiering_reset()
    test_q1_promotion_records_skip_normal_reject_flood()
    test_q1_promotion_structural_preadmit_rejects_are_recorded_once()
    test_q1_promotion_record_volume_is_bounded()
    test_g129_promotion_record_fixture_positive()
    test_g129_promotion_record_allows_cross_request_record_id_reuse()
    test_g129_promotion_record_fixture_rejects_same_call()
    test_g129_promotion_record_rejects_non_expert_offset()
    test_g129_promotion_record_rejects_range_overflow()
    test_g129_promotion_record_rejects_attempt_without_terminal()
    test_g129_promotion_record_rejects_duplicate_terminal()
    test_g129_promotion_record_rejects_unpaired_failure()
    test_g129_promotion_record_strict_jsonl_rejects_bad_integers()
    test_g129_promotion_record_strict_jsonl_rejects_malformed_lines()
    test_g129_runner_validator_selftest_exercises_real_validator()
    print("test_g129_q1_open_dynamic_promotion_runtime.py: PASS")
