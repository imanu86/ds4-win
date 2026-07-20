from pathlib import Path


ROOT = Path(__file__).resolve().parent
HARNESS = (ROOT / "g7_measure.ps1").read_text(encoding="utf-8-sig")
RUNNER = (ROOT / "g129_q1_open_dynamic_promotion_safety.ps1").read_text(
    encoding="utf-8-sig"
)
PROTOCOL = (
    ROOT / "G129_Q1_OPEN_DYNAMIC_PROMOTION_PROTOCOL.md"
).read_text(encoding="utf-8-sig")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise AssertionError(f"forbidden {label}: {needle}")


def test_protocol_is_g129_authority() -> None:
    for needle in (
        "full/open Q1_0 base with dynamic exact-IQ2 promotion",
        "exact IQ2 open-router reserve: 64 expert slots",
        "exact IQ2 VRAM cache: 320 expert slots",
        "mass-LFRU tier replacement budget: 32 entries per policy epoch",
        "minimum touches: 2",
        "minimum absolute router weight: 0.02",
        "window: 40 routed-layer calls",
        "window budget: 1 promotion",
        "direct SSD-to-VRAM promotion",
        "structured per-expert",
        "request_epoch",
        "promotion_window_epoch",
        "authoritative request-boundary telemetry",
        "not the carry-specific `g_dynamic_arena.request_sequence`",
        "reason=call_tick_overflow",
        "budget counters must be unique",
        "g7_runs_evil",
        "base/stride/effective",
        "JSONL artifact",
        "physical-line count",
        "request_epoch + record_id",
        "Aggregate attempts",
        "G129-control",
        "dynamic promotion OFF",
        "G129-promotion",
        "dynamic promotion ON",
        "mixed resolver ON",
        "tier-route entries",
        "SplitFused accounting",
        "primary-model exact-IQ2 transport denominator",
        "trace_rows == q1_resident + iq2_vram + iq2_snapshot_ram + iq2_tier_ram",
        "split_fused_hits + split_fused_misses == iq2_vram + iq2_snapshot_ram +",
        "Windows Q1_0 sidecar mmap source unlock ranges",
        "Windows reclaimed file-backed source pages",
        "DS4_Q1_0_PROFILE=1",
        "QueryWorkingSetEx",
        "post-unlock-settle",
        "DS4_EXPERT_RECOVERY_TRACE=1",
        "input-only activation recovery",
        "offline exact-IQ2",
        "256 samples",
        "atomic commit marker",
        "failure.json",
        "safety failure receipt",
    ):
        require(PROTOCOL, needle, "protocol contract")


def test_harness_env_plumbing_and_result_contract() -> None:
    for needle in (
        "[ValidateRange(0.0, 64.0)][double]$Q1_0ArenaGB = 0.0",
        "[switch]$Q1_0DynamicPromotion",
        "[ValidateRange(1, 512)][int]$Q1_0PromotionProbationSlots = 16",
        "[ValidateRange(1, 1000000)][int]$Q1_0PromotionMinTouches = 1",
        "[ValidateRange(0.0, 1000000.0)][double]$Q1_0PromotionMinWeight = 0.0",
        "[ValidateRange(0.0, 1000000.0)][double]$Q1_0PromotionMinMass = 0.0",
        "[ValidateRange(0, 1000000)][int]$Q1_0PromotionRequestBudget = 0",
        "[ValidateRange(0, 1000000)][int]$Q1_0PromotionWindowCalls = 0",
        "[ValidateRange(0, 1000000)][int]$Q1_0PromotionWindowBudget = 0",
        "DS4_Q1_0_DYNAMIC_ARENA_GB",
        "DS4_Q1_0_DYNAMIC_PROMOTION",
        "DS4_Q1_0_PROMOTION_PROBATION_SLOTS",
        "DS4_Q1_0_PROMOTION_MIN_TOUCHES",
        "DS4_Q1_0_PROMOTION_MIN_WEIGHT",
        "DS4_Q1_0_PROMOTION_MIN_MASS",
        "DS4_Q1_0_PROMOTION_REQUEST_BUDGET",
        "DS4_Q1_0_PROMOTION_WINDOW_CALLS",
        "DS4_Q1_0_PROMOTION_WINDOW_BUDGET",
        "Q1_0DynamicPromotion requires Q1_0DualArena",
        "Q1_0DynamicPromotion forbids Q1_0SnapshotBacking",
        "Q1_0DynamicPromotion requires Q1_0PageableOverflow",
        "Q1_0DynamicPromotion is isolated from legacy Iq1Promotion",
        "ExpectedQ1_0ResidentEntries requires non-snapshot Q1_0ResidentArena",
        "ds4_q1_0_dynamic_arena_gb",
        "ds4_q1_0_dynamic_promotion",
        "q1_0_dynamic_arena_gb_requested",
        "q1_0_dynamic_promotion_requested",
        "q1_0_promotion_requested_config",
        "q1_0_promotion_probation_slots_requested",
        "q1_0_promotion_min_touches_requested",
        "q1_0_promotion_min_weight_requested",
        "q1_0_promotion_min_mass_requested",
        "q1_0_promotion_request_budget_requested",
        "q1_0_promotion_window_calls_requested",
        "q1_0_promotion_window_budget_requested",
        "q1_0_bootstrap_pinned_bytes",
        "q1_0_bootstrap_pageable_bytes",
        "q1_0_bootstrap_pinned_slots",
        "q1_0_bootstrap_pageable_slots",
        "q1_0_bootstrap_total_slots",
        "q1_0_bootstrap_total_bytes",
        "q1_0_bootstrap_layer_first",
        "q1_0_bootstrap_layer_last",
        "q1_0_source_unlock_observed",
        "q1_0_source_unlock_ranges_attempted",
        "q1_0_source_unlock_bytes_attempted",
        "q1_0_source_unlock_not_locked",
        "Q1_0 source unlock telemetry missing",
        "q1_0_mixed_resolver_required",
        "q1_0_mixed_expected_router",
        "router_mode",
        "q1_0_mixed_route_trace",
        "allowed_iq2_representations",
        "q1_0_mixed_iq2_routes",
        "q1_0_mixed_accounted_routes",
        "q1-0-mixed-iq2-routes",
        "split_fused_primary_route_basis",
        "split_fused_primary_routes_expected",
        "split_fused_primary_routes_observed",
        "split_fused_q1_resident_routes_excluded",
        "Q1_0 mixed route trace used unknown ",
        "representation: $($match.Groups[5].Value)",
        "Q1_0 mixed route trace accounting does not match the summary",
        "tier_route_entries",
        "q1_0_observed",
        "q1_0_stage_attempts",
        "q1_0_stage_successes",
        "iq1_promotion_q1_0_observed",
        "iq1_promotion_q1_0_stage_attempts",
        "iq1_promotion_q1_0_stage_successes",
        "iq1_promotion_q1_0_next_call_guards",
        "iq1_promotion_q1_0_record_attempts",
        "iq1_promotion_q1_0_record_successes",
        "q1_0_promotion_records_path",
        "q1_0_promotion_records_sha256",
        "q1_0_promotion_records_physical_line_count",
        "q1_0_promotion_record_bounded_exception_limit",
        "q1_0_promotion_telemetry_record_limit",
        "Q1_0 promotion telemetry record flood",
        "q1_0_promotion_record_attempt_count",
        "promotion_window_epoch",
        "Get-G7PromotionRecordImmutableIdentity",
        "Q1_0 promotion request budget sequence failed",
        "Q1_0 promotion window budget sequence failed",
        "source_gate_base_offset",
        "source_gate_stride",
        "destination_gate_base_offset",
        "destination_gate_stride",
        "Convert-G7StrictUInt64",
        "Get-G7PromotionRecordKey",
        "Q1_0 dynamic promotion requires per-expert promotion records",
        "Q1_0 promotion attempt missing terminal record",
        "Q1_0 promotion record counts do not match final promotion counters",
        "Write-G7MeasurementFailure",
        "runtime-invariant-preparse",
    ):
        require(HARNESS, needle, "harness G129 plumbing")


def test_full_open_q1_requires_mixed_telemetry_without_promotion() -> None:
    normalized = " ".join(HARNESS.split())
    require(
        normalized,
        "$q1_0MixedResolverRequired = [bool]( $Q1_0SnapshotBacking -or "
        "$Q1_0MixedColdOne -or $Q1_0DynamicPromotion -or "
        "($Q1_0ExpertSidecar -and $Q1_0ResidentArena -and "
        "$Q1_0DualArena -and -not $Q1_0DualSparseCompanion))",
        "full-open mixed telemetry requirement",
    )
    require(
        normalized,
        "-Required $q1_0MixedResolverRequired",
        "mixed telemetry is required through resolver contract",
    )
    require(
        normalized,
        "-ExpectedRouter $q1_0MixedExpectedRouter",
        "mixed telemetry expected router mode",
    )
    require(
        normalized,
        "$q1_0MixedTelemetry.tier_route_entries -ne "
        "[UInt64]$q1_0MixedTelemetry.trace_rows",
        "route-entry coverage assertion",
    )
    require(
        normalized,
        "$q1_0MixedAccountedRoutes -ne "
        "[UInt64]$q1_0MixedTelemetry.trace_rows",
        "summary category coverage assertion",
    )
    require(
        normalized,
        "$q1_0MixedRouteTraceTelemetry.iq2_vram -ne "
        "[UInt64]$q1_0MixedTelemetry.iq2_vram",
        "trace-to-summary IQ2 VRAM assertion",
    )


def test_g129_split_fused_counts_only_iq2_transport_routes() -> None:
    normalized = " ".join(HARNESS.split())
    require(
        normalized,
        '$splitFusedPrimaryRouteBasis = "gpu-resident-route-population"',
        "legacy SplitFused denominator default",
    )
    require(
        normalized,
        '$splitFusedPrimaryRouteBasis = "q1-0-mixed-iq2-routes"',
        "G129 SplitFused denominator basis",
    )
    require(
        normalized,
        "$splitFusedExpectedPrimaryRoutes = [UInt64]$q1_0MixedIq2Routes",
        "G129 SplitFused IQ2 denominator",
    )
    require(
        normalized,
        "$splitFusedQ1ResidentRoutesExcluded = "
        "[UInt64]$q1_0MixedTelemetry.q1_resident",
        "Q1 resident routes excluded after trace proof",
    )
    require(
        normalized,
        "$q1_0MixedRouteTraceRequired -and "
        "[bool]$q1_0MixedRouteTraceTelemetry.observed",
        "G129 SplitFused denominator requires observed mixed trace",
    )
    require(
        normalized,
        "$splitFusedObservedPrimaryRoutes -ne "
        "$splitFusedExpectedPrimaryRoutes",
        "SplitFused observed-vs-expected assertion",
    )


def test_q1_profile_harness_is_opt_in_and_fail_closed() -> None:
    for needle in (
        "[switch]$Q1_0Profile",
        "DS4_Q1_0_PROFILE",
        "Read-G7Q1_0ProfileTelemetry",
        "Q1_0 profile summary required exactly once",
        "Q1_0 profile pinned/pageable accounting is inconsistent",
        "Q1_0 profile source working-set phases required exactly three times",
        "q1_0_profile_requested",
        "q1_0_profile = $q1_0ProfileTelemetry",
        "Q1_0Profile requires Q1_0SelectedLoad and Q1_0ResidentArena",
        "Q1_0 profile telemetry appeared while Q1_0Profile was disabled",
        "[switch]$Q1_0ProfileParserSelfTest",
        "missing field: pageable_h2d_bytes",
        "incoherent pinned/pageable split",
    ):
        require(HARNESS, needle, "Q1 profile harness contract")


def test_expert_recovery_trace_harness_is_bounded_and_fail_closed() -> None:
    for needle in (
        "[switch]$ExpertRecoveryTrace",
        "[ValidateRange(0, 42)][int]$ExpertRecoveryTraceLayer",
        "[ValidateRange(0, 255)][int]$ExpertRecoveryTraceExpert",
        "[ValidateRange(1, 256)][int]$ExpertRecoveryTraceMaxSamples",
        "DS4_EXPERT_RECOVERY_TRACE",
        "DS4_EXPERT_RECOVERY_TRACE_OUTPUT_PREFIX",
        "DS4_EXPERT_RECOVERY_BUILD_MANIFEST_SHA256",
        "ExpertRecoveryTrace requires the G129 resident dual-arena mixed resolver",
        "ExpertRecoveryTrace requires one structural-safety request and no warmup",
        "ExpertRecoveryTrace requires authoritative full/open routing",
        "Get-G7ExpertRecoveryConfinedPaths",
        "Read-G7ExpertRecoveryTraceArtifact",
        "Expert recovery partial artifact is not acceptable",
        "Expert recovery JSONL physical-line count is inconsistent",
        "Expert recovery sample $i contract is inconsistent",
        "artifact_bytes_total",
        "expert-recovery-trace-diagnostic-only",
        "expert_recovery_trace_requested",
        "expert_recovery_trace = $expertRecoveryTraceArtifact",
        "expert_recovery_trace_performance_eligible = $false",
        "[switch]$ExpertRecoveryTraceParserSelfTest",
    ):
        require(HARNESS, needle, "expert recovery harness contract")


def test_runner_fail_closed_contract() -> None:
    for needle in (
        "g129_q1_open_dynamic_promotion_safety",
        "whatif_no_runtime",
        "structural_safety_only_no_sota_no_quality_verdict",
        "[ValidateSet('promotion', 'control')]",
        "$promotionEnabled = $Arm -eq 'promotion'",
        "-GateKind', 'structural-safety'",
        "-ForceOpenRouter",
        "-ComposePrefillMassOpenRouter",
        "-ComposePrefillMassReserveSlots', [string]$reserveSlots",
        "-DynamicArenaGiB', $primaryArenaGBText",
        "$primaryArenaGB = 5.5",
        "$q1ArenaGB = 24.5",
        "$reserveSlots = 64",
        "$cacheSlots = 320",
        "$tierReplacementBudget = 32",
        "-ExpertTierReplacementBudget', [string]$tierReplacementBudget",
        "-Q1_0DualArena",
        "-Q1_0PageableOverflow",
        "-Q1_0ArenaGB', $q1ArenaGBText",
        "-Q1_0DynamicPromotion",
        "-Q1_0LayerFirst', '0'",
        "-Q1_0LayerLast', '42'",
        "-ExpectedQ1_0ResidentEntries', '11008'",
        "-ExpertCacheN', [string]$cacheSlots",
        "-PrefillVramSeedTotal', '320'",
        "-PrefillVramSeedFloorPerLayer', '4'",
        "-Q1_0PromotionProbationSlots', [string]$reserveSlots",
        "-Q1_0PromotionMinTouches', '2'",
        "-Q1_0PromotionMinWeight', '0.02'",
        "-Q1_0PromotionMinMass', '0'",
        "-Q1_0PromotionRequestBudget', '64'",
        "-Q1_0PromotionWindowCalls', '40'",
        "-Q1_0PromotionWindowBudget', '1'",
        "-Temperature', '0'",
        "-NoThink",
        "embedded_bake_mask_observed",
        "q1_0_dual_arena_runtime_observed",
        "q1_0_bootstrap_pinned_bytes",
        "q1_0_bootstrap_pageable_bytes",
        "q1_0_bootstrap_total_slots",
        "q1_0_bootstrap_total_bytes",
        "q1_0_bootstrap_layer_first",
        "q1_0_bootstrap_layer_last",
        "q1_0_source_unlock_observed",
        "q1_0_source_unlock_result",
        "q1_0_source_unlock_ranges_attempted",
        "q1_0_source_unlock_calls",
        "q1_0_source_unlock_not_locked",
        "q1_0_source_unlock_failed",
        "promotion_gate=disabled",
        "q1_0_mixed.q1_resident",
        "q1_0_mixed.tier_route_entries",
        "q1_0_mixed_iq2_routes",
        "q1_0_mixed_accounted_routes",
        "split_fused_primary_route_basis",
        "split_fused_primary_routes_expected",
        "split_fused_primary_routes_observed",
        "split_fused_q1_resident_routes_excluded",
        "G129 safety SplitFused primary-route denominator contract failed",
        "q1_0_mixed_resolver_required",
        "q1_0_mixed_expected_router",
        "q1_0_mixed.router_mode",
        "q1_0_mixed.iq2_ssd_violations",
        "iq1_promotion_runtime_observed",
        "iq1_promotion_q1_0_observed",
        "iq1_promotion_q1_0_stage_successes",
        "iq1_promotion_q1_0_next_call_guards",
        "iq1_promotion_q1_0_record_attempts",
        "iq1_promotion_q1_0_record_successes",
        "q1_0_promotion_records_path",
        "q1_0_promotion_records_sha256",
        "q1_0_promotion_records_physical_line_count",
        "q1_0_promotion_records_materialization_error",
        "[switch]$SelfTest",
        "Invoke-G129ValidatorSelfTest",
        "Test-G129PathInsideDirectory",
        "[IO.Path]::DirectorySeparatorChar",
        "Get-G129PromotionRecordImmutableIdentity",
        "G129 promotion request budget sequence failed",
        "G129 promotion window budget sequence failed",
        "q1_0_promotion_record_attempt_count",
        "Convert-G129StrictUInt64",
        "Get-G129PromotionRecordKey",
        "source_gate_base_offset",
        "destination_gate_base_offset",
        "promotion_window_epoch",
        "physical-line count mismatch",
        "duplicate JSON key",
        "Read-G129PromotionRecordArtifact",
        "Assert-G129PromotionRecords",
        "G129 promotion missing Q1_0 per-expert record artifact",
        "G129 promotion attempt record failed",
        "G129 promotion success record failed",
        "G129 validator self-test",
        "path sibling g7_runs_evil",
        "budget duplicate used=0",
        "unpaired failure",
        "duplicate terminal",
        "iq1_promotion_direct_ssd_to_vram_rejected",
        "forbidden_cold_ssd_to_vram",
        "Write-G129SafetyFailureReceipt",
        "Write-G129SafetyFailureReceiptIndex",
        "Export-G129PromotionRecordArtifactFromStderr",
        "Assert-G129PromotionRecordArtifactStrict",
        "Get-G129PromotionRecordArtifactSummary",
        "Invoke-G129BootstrapChild",
        "-EncodedCommand",
        "harness_arguments = @('--')",
        "G129_SAFETY_FAILURE_RECEIPT_SHA256",
        "safety_failure_receipt_index.json",
        "q1_0_promotion_records_materialization_note",
        "telemetry record flood",
        "failure terminal telemetry flood",
        "existing artifact malformed",
        "existing artifact array",
        "existing artifact duplicate key",
        "stale promotion artifact hash",
        "argv_capture",
        "failure receipt materialization",
        "safety_failure_receipt.json",
        "receipt_sha256",
        "failure_sha256",
        "stderr_sha256",
        "raw_outputs_sha256",
        "runtime_telemetry_sha256",
        "q1_0_promotion_records_sha256",
    ):
        require(RUNNER, needle, "runner fail-closed contract")
    forbid(RUNNER, "'--%'", "runner bootstrap argv")
    for needle in (
        "-Q1_0SnapshotBacking",
        "-ExpectedQ1_0SnapshotEntries",
        "-Iq1Promotion",
        "-Iq1PromotionProbationSlots",
        "-Iq1PromotionMinTouches",
        "-Iq1PromotionMinWeight",
        "-Iq1PromotionMinMass",
        "-Iq1PromotionRequestBudget",
        "-Iq1PromotionWindowCalls",
        "-Iq1PromotionWindowBudget",
    ):
        forbid(RUNNER, needle, "legacy IQ1 runner knob")


def test_ssd_wrap_contract_is_opt_in_fixed_budget_and_fail_closed() -> None:
    for needle in (
        "[switch]$Q1_0PromotionSsdWrap",
        "[ValidateRange(0.125, 5.5)][double]$Q1_0Iq2PinnedGiB = 1.5",
        "DS4_Q1_0_PROMOTION_SSD_WRAP",
        "DS4_Q1_0_IQ2_PINNED_GIB",
        "Q1_0PromotionSsdWrap requires Q1_0DynamicPromotion",
        "unchanged 5.5 GiB exact-IQ2 host budget",
        "Read-G7Q1_0SsdWrapTelemetry",
        "Invoke-G7Q1_0SsdWrapParserSelfTest",
        "host budget accounting is inconsistent",
        "pinned/pageable split is inconsistent",
        "wave totals are inconsistent",
        "working-set phase missing",
        "SSD-WRAP counters do not match promotion records",
        "q1_0_ssd_wrap = $q1_0SsdWrapTelemetry",
    ):
        require(HARNESS, needle, "SSD-WRAP harness contract")
    for needle in (
        "[switch]$Q1_0PromotionSsdWrap",
        "-Q1_0PromotionSsdWrap",
        "-Q1_0Iq2PinnedGiB",
        "q1_0_promotion_ssd_wrap",
    ):
        require(RUNNER, needle, "SSD-WRAP runner contract")
    for needle in (
        "SSD-WRAP exact-IQ2 host hierarchy",
        "REQUESTED -> SSD_INFLIGHT -> RAM_READY",
        "5.5 GiB",
        "all-pinned control",
        "1.5 GiB pinned / 4.0 GiB pageable",
        "2.0 GiB pinned / 3.5 GiB pageable",
        "OFF by default",
    ):
        require(PROTOCOL, needle, "SSD-WRAP protocol contract")


if __name__ == "__main__":
    test_protocol_is_g129_authority()
    test_harness_env_plumbing_and_result_contract()
    test_full_open_q1_requires_mixed_telemetry_without_promotion()
    test_g129_split_fused_counts_only_iq2_transport_routes()
    test_q1_profile_harness_is_opt_in_and_fail_closed()
    test_expert_recovery_trace_harness_is_bounded_and_fail_closed()
    test_runner_fail_closed_contract()
    test_ssd_wrap_contract_is_opt_in_fixed_budget_and_fail_closed()
    print("test_g129_q1_open_dynamic_promotion_contract.py: PASS")
