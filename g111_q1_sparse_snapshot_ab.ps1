# G111 Q1_0 sparse-snapshot A/B runner (PowerShell 5.1, ASCII).
param(
    [switch]$StaticCheckOnly,
    [switch]$SafetyOnly,
    [switch]$Resume,
    [switch]$LongCyberpunk,
    [string]$ModelPath = "C:\ds4-models\ds4-2bit.gguf",
    [string]$ExpectedModelSHA256 = "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668",
    [Parameter(Mandatory=$true)][string]$Q1SidecarPath,
    [Parameter(Mandatory=$true)][string]$ExpectedQ1SidecarSHA256,
    [Parameter(Mandatory=$true)][UInt64]$ExpectedQ1SidecarBytes,
    [ValidatePattern('^[A-Za-z0-9_-]*$')][string]$RunLabel = "",
    [ValidateRange(600, 86400)][int]$TimeoutSec = 7200,
    [ValidateRange(0, 3600)][int]$QuiescenceCooldownSec = 90
)

$ErrorActionPreference = "Stop"
$runnerPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $runnerPath
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$modeName = if ($LongCyberpunk) { "long_cyberpunk_full_q1" } else { "short64" }
$summaryPath = Join-Path $outdir $(if ($LongCyberpunk) {
    "g111_q1_sparse_snapshot_long_cyberpunk_result.json"
} else {
    "g111_q1_sparse_snapshot_ab_result.json"
})
$safetySummaryPath = Join-Path $outdir $(if ($LongCyberpunk) {
    "g111_q1_sparse_snapshot_long_cyberpunk_safety_result.json"
} else {
    "g111_q1_sparse_snapshot_safety_result.json"
})
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expectedPromptSHA256 = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"
$shortExpectedControlContentSHA256 = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$context = if ($LongCyberpunk) { 8192 } else { 256 }
$prefillChunk = 256
$maxTokens = if ($LongCyberpunk) { 4000 } else { 64 }
$stopSequence = if ($LongCyberpunk) { "</html>" } else { "" }
$processesPerArm = 3
$extraProcessesPerArm = 3
$outlierRatio = 1.20
$seedPerLayer = if ($LongCyberpunk) { 7 } else { 8 }
$seedTag = "seed$seedPerLayer"
$controlName = if ($LongCyberpunk) {
    "historical G73 external reference only"
} else {
    "current-build IQ2 snapshot $seedTag (G73-derived)"
}
$controlArenaGiB = 30.0
$candidateArenaGiB = if ($LongCyberpunk) { 30.0 } else { 15.0 }
$controlArenaSlots = 4551
$candidateArenaSlots = if ($LongCyberpunk) { 11008 } else { 4551 }
$matrixOrder = if ($LongCyberpunk) {
    "candidate,candidate,candidate"
} else {
    "control,candidate,candidate,control,control,candidate"
}
$expectedCacheCapacity = $seedPerLayer * 40
$runtimeMinimumAvailableGiB = 1.0
$waveGiB = 4.0
$script:g111ControlContentSHA256 = if ($LongCyberpunk) {
    ""
} else {
    $shortExpectedControlContentSHA256
}
$script:g111CandidateContentSHA256 = ""
$script:g111ModelReceiptSHA256 = ""
$script:g111Q1ReceiptSHA256 = ""

function Get-G111StringSHA256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G111FileSHA256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G111Property {
    param([object]$Object, [string]$Name, $Default = $null)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) {
        return $Default
    }
    $Object.PSObject.Properties[$Name].Value
}

function Get-G111ResultPath {
    param([Parameter(Mandatory=$true)][string]$Tag)
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G111RawPath {
    param([Parameter(Mandatory=$true)][string]$Tag)
    Join-Path $outdir ("g7_" + $Tag + "_raw_outputs.json")
}

function Get-G111Mean {
    param([object[]]$Rows, [string]$Property)
    if ($Rows.Count -eq 0) { return $null }
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Get-G111Median {
    param([object[]]$Rows, [string]$Property)
    $values = @($Rows | ForEach-Object { [double]$_.$Property } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($values.Count / 2)
    if (($values.Count % 2) -eq 1) { return [math]::Round($values[$middle], 6) }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2, 6)
}

function Test-G111HarnessParameter {
    param([Parameter(Mandatory=$true)][string]$Name)
    $script:g111HarnessText -match ("\$" + [regex]::Escape($Name) + "(\s|=|,|\))")
}

function Assert-G111StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G111 harness missing: $harness"
    }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "G111 runner AST parse failed: $($errors[0].Message)"
    }
    if ((Get-G111StringSHA256 $prompt) -ne $expectedPromptSHA256) {
        throw "G111 prompt hash mismatch"
    }
    foreach ($hash in @($ExpectedModelSHA256, $ExpectedQ1SidecarSHA256)) {
        if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "G111 expected SHA256 values must contain 64 hex characters"
        }
    }
    if ($ExpectedQ1SidecarBytes -eq 0) {
        throw "G111 Q1 sidecar byte count must be positive"
    }
    if ($Q1SidecarPath -like (([char]68) + ":\*")) {
        throw "G111 Q1 sidecar must be on C: for benchmark validity"
    }
    $script:g111HarnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($parameter in @(
        "ExpectedContentSHA256", "ExpectedModelSHA256", "ReuseVerifiedModelReceipt",
        "Q1_0ExpertSidecar", "ExpectedQ1_0ExpertSidecarSHA256",
        "ExpectedQ1_0ExpertSidecarBytes", "ReuseVerifiedQ1_0Receipt",
        "Q1_0LayerFirst", "Q1_0LayerLast", "Q1_0SelectedLoad",
        "Q1_0SnapshotBacking", "Q1_0PageableOverflow", "DynamicArenaGiB", "PrefillMassWrap",
        "ComposePrefillMassTiering", "PrefillVramSeedPerLayer",
        "GateKind", "SplitFused", "StopSequence",
        "RuntimeMinimumAvailableGiB", "QuiescenceCooldownSec")) {
        if (-not (Test-G111HarnessParameter $parameter)) {
            throw "G111 harness lacks -$parameter"
        }
    }
    foreach ($marker in @(
        "q1_0_resident_misses", "q1_0_direct_pread_fallbacks",
        "q1_0_direct_pread_bytes", "snapshot_backing_misses",
        "forbidden_cold_ssd_to_vram", '$env:DS4_Q1_0_SNAPSHOT_BACKING = "1"',
        '$env:DS4_Q1_0_PAGEABLE_OVERFLOW = "1"',
        'g7_raw_response_checkpoint_v1',
        '[ValidateRange(0, 11008)][int]$ExpectedQ1_0SnapshotEntries')) {
        if ($script:g111HarnessText -notmatch [regex]::Escape($marker)) {
            throw "G111 harness marker missing: $marker"
        }
    }
}

function New-G111StaticReceipt {
    [pscustomobject][ordered]@{
        schema = $(if ($LongCyberpunk) {
            "g111_q1_sparse_snapshot_long_cyberpunk_static_v1"
        } else {
            "g111_q1_sparse_snapshot_ab_static_v1"
        })
        static_check_only = [bool]$StaticCheckOnly
        mode = $modeName
        context_requested = $context
        prefill_chunk_requested = $prefillChunk
        max_tokens_requested = $maxTokens
        stop_sequence = $stopSequence
        temperature = 0
        think = $false
        no_model_presence_required = [bool]$StaticCheckOnly
        no_build_gpu_or_ds4_launch = [bool]$StaticCheckOnly
        runnable = $true
        protocol = [ordered]@{
            safety_candidate_n1_exactness_only = $true
            safety_performance_claim_allowed = $false
            safety_quality_claim_allowed = $false
            matrix_order = $matrixOrder
            independent_processes_per_arm = $processesPerArm
            candidate_hash_frozen_from_safety = $true
            control_hash_frozen_from_safety = $false
            quality_grading_required_for_sota_claim = "L0-L3"
        }
        control = [ordered]@{
            name = $controlName
            dynamic_arena_gib = $controlArenaGiB
            prefill_vram_seed_per_layer = $seedPerLayer
            q1_0_snapshot_backing = $false
            historical_g73_reference_only = $true
            historical_g73_decode_tps = 4.986667
            historical_g73_direct_comparison_eligible = $false
        }
        candidate = [ordered]@{
            name = "G111 Q1_0 sparse snapshot backing"
            q1_sidecar_path = $Q1SidecarPath
            q1_sidecar_sha256 = $ExpectedQ1SidecarSHA256.ToLowerInvariant()
            q1_sidecar_bytes = $ExpectedQ1SidecarBytes
            layers = "0..42"
            dynamic_arena_gib = $candidateArenaGiB
            expected_snapshot_entries = $candidateArenaSlots
            full_q1_routed_residency = [bool]$LongCyberpunk
            q1_0_snapshot_backing = $true
            q1_0_pageable_overflow = [bool]$LongCyberpunk
            prefill_mass_wrap = $true
            compose_prefill_mass_tiering = $true
            prefill_vram_seed_per_layer = $seedPerLayer
            exact_iq2_vram_seed_required = $true
            zero_iq2_vram_cache_miss_required = $true
            closed_router = $true
            zero_q1_miss_required = $true
            zero_direct_pread_required = $true
            zero_ssd_required = $true
        }
    }
}

function Open-G111ReadLock {
    param([Parameter(Mandatory=$true)][string]$Path)
    [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
}

function Assert-G111RuntimeInputs {
    foreach ($path in @($ModelPath, $Q1SidecarPath, "$ModelPath.receipt.json", "$Q1SidecarPath.receipt.json")) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G111 required file missing: $path"
        }
    }
    if ([UInt64](Get-Item -LiteralPath $Q1SidecarPath).Length -ne $ExpectedQ1SidecarBytes) {
        throw "G111 Q1 sidecar byte count mismatch"
    }
    $script:g111ModelReceiptSHA256 = Get-G111FileSHA256 "$ModelPath.receipt.json"
    $script:g111Q1ReceiptSHA256 = Get-G111FileSHA256 "$Q1SidecarPath.receipt.json"
}

function New-G111MeasureArgs {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("benchmark", "structural-safety")][string]$GateKind,
        [AllowEmptyString()][string]$ExpectedContentSHA256
    )
    $arenaGiB = if ($Arm -eq "candidate") { $candidateArenaGiB } else { $controlArenaGiB }
    $args = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-Tag", $Tag, "-GateKind", $GateKind,
        "-ModelPath", $ModelPath, "-ExpectedModelSHA256", $ExpectedModelSHA256,
        "-ReuseVerifiedModelReceipt", "-Prompt", $prompt,
        "-MaxTokens", ([string]$maxTokens), "-Repeats", "1", "-Context", ([string]$context),
        "-PrefillChunk", ([string]$prefillChunk),
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", $arenaGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
        "-ArenaWrapTrustWorkerChecksum", "-ArenaWrapSourceParts",
        "-ArenaWrapUnlockSourceRanges", "-ArenaWrapUnlockWaveGiB",
        $waveGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
        "-DisableQ8F16Cache", "-EmbedRowStaging", "-ReapPrefetchThreads", "8",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-PrefillVramSeedPerLayer", ([string]$seedPerLayer),
        "-ExpertCacheN", ([string]$expectedCacheCapacity), "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-ExpertTiering", "enforce", "-ExpertTierPolicy", "mass-lfru",
        "-ExpertTierClockCalls", "430", "-ExpertTierReplacementBudget", "32",
        "-ExpertTierMinFrequency", "3", "-ExpertTierHysteresis", "1.25",
        "-RuntimeMinimumAvailableGiB",
        $runtimeMinimumAvailableGiB.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture),
        "-RuntimeMaximumDiskQueueLength", "8", "-RuntimeContaminationSamples", "3",
        "-QuiescenceCooldownSec", ([string]$QuiescenceCooldownSec),
        "-TimeoutSec", ([string]$TimeoutSec)
    )
    if ($ExpectedContentSHA256) {
        $args += @("-ExpectedContentSHA256", $ExpectedContentSHA256)
    }
    if ($stopSequence) {
        $args += @("-StopSequence", $stopSequence)
    }
    if ($GateKind -eq "benchmark") {
        $args += "-AllowBenchmarkVerifiedReceiptReuse"
    }
    if ($Arm -eq "control") {
        $args += @("-RouteNoDefaultSync", "-SplitFused")
    }
    if ($Arm -eq "candidate") {
        $args += @(
            "-Q1_0ExpertSidecar", $Q1SidecarPath,
            "-ExpectedQ1_0ExpertSidecarSHA256", $ExpectedQ1SidecarSHA256,
            "-ExpectedQ1_0ExpertSidecarBytes", ([string]$ExpectedQ1SidecarBytes),
            "-ReuseVerifiedQ1_0Receipt", "-Q1_0LayerFirst", "0", "-Q1_0LayerLast", "42",
            "-Q1_0SelectedLoad", "-Q1_0SnapshotBacking",
            "-ExpectedQ1_0SnapshotEntries", ([string]$candidateArenaSlots)
        )
        if ($LongCyberpunk) {
            $args += "-Q1_0PageableOverflow"
        }
    }
    $args
}

function Assert-G111CommonContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [AllowEmptyString()][string]$ExpectedContentSHA256,
        [Parameter(Mandatory=$true)][bool]$Safety
    )
    $tier = $Result.expert_tiering
    $expectedArenaGiB = if ($Arm -eq "candidate") { $candidateArenaGiB } else { $controlArenaGiB }
    $expectedArenaSlots = if ($Arm -eq "candidate") { $candidateArenaSlots } else { $controlArenaSlots }
    $expectedEligibilityReason = if ($Safety) { "structural-safety-gate-not-quality-eligible" } else { "repeats-less-than-3-not-quality-eligible" }
    $sample = @($Result.results)[0]
    $server = @($Result.server_runs)[0]
    $routeContractFailed = if ($Arm -eq "control") {
        -not [bool]$Result.gpu_resident_routes_requested -or
        -not [bool]$Result.route_no_default_sync_requested -or
        [UInt64]$Result.gpu_resident_routes_default_sync_calls -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_no_default_sync_calls -ne [UInt64]$Result.gpu_resident_routes_calls -or
        [UInt64]$Result.gpu_resident_routes_errors -ne 0 -or
        -not [bool]$Result.split_fused_requested -or
        -not [bool](Get-G111Property $Result "split_fused_observed" $false) -or
        [UInt64](Get-G111Property $Result "split_fused_calls" 0) -ne [UInt64]$Result.gpu_resident_routes_calls -or
        ([UInt64](Get-G111Property $Result "split_fused_hits" 0) + [UInt64](Get-G111Property $Result "split_fused_misses" 0)) -ne [UInt64]$tier.selected -or
        [UInt64](Get-G111Property $Result "split_fused_miss_scratch_bytes_avoided" 0) -le 0 -or
        [UInt64](Get-G111Property $Result "split_fused_sum_read_bytes_avoided" 0) -le 0
    } else {
        -not [bool]$Result.gpu_resident_routes_requested -or
        [bool]$Result.route_no_default_sync_requested -or
        -not [bool]$Result.gpu_resident_routes_observed -or
        [UInt64]$Result.gpu_resident_routes_calls -le 0 -or
        [UInt64]$Result.gpu_resident_routes_default_sync_calls -ne
            [UInt64]$Result.gpu_resident_routes_calls -or
        [UInt64]$Result.gpu_resident_routes_no_default_sync_calls -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_errors -ne 0 -or
        [int]$Result.gpu_resident_routes_cache_count -ne $expectedCacheCapacity -or
        [UInt64]$Result.gpu_resident_routes_cache_hits -le 0 -or
        [UInt64]$Result.gpu_resident_routes_cache_misses -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_cache_admissions -ne
            [UInt64]$expectedCacheCapacity -or
        [UInt64]$Result.gpu_resident_routes_cache_evictions -ne 0 -or
        [UInt64]$Result.gpu_resident_routes_cache_direct_loads -ne 0 -or
        [bool]$Result.split_fused_requested -or
        [bool](Get-G111Property $Result "split_fused_observed" $false) -or
        [UInt64](Get-G111Property $Result "split_fused_calls" 0) -ne 0
    }
    if (@($Result.results).Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$sample.content) -or
        [string]$sample.content_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [int]$sample.completion_tokens -le 0 -or
        [string]$server.finish_reason -notin @("stop", "length") -or
        ($LongCyberpunk -and [string]$server.finish_reason -ne "stop") -or
        [bool]$Result.quality_eligible -or [bool]$Result.sota_eligible -or
        [string]$Result.contamination_reason -ne $expectedEligibilityReason -or
        [string]$Result.prompt_sha256 -ine $expectedPromptSHA256 -or
        [int]$Result.requested_max_tokens -ne $maxTokens -or
        [int]$Result.context_requested -ne $context -or
        [int]$Result.prefill_chunk_requested -ne $prefillChunk -or
        [int]$Result.prefill_chunk_observed -ne $prefillChunk -or
        [string]$Result.requested_stop_sequence -ne $stopSequence -or
        [string]$Result.model -ine ([IO.Path]::GetFullPath($ModelPath)) -or
        [string]$Result.model_sha256 -ine $ExpectedModelSHA256 -or
        [string]$Result.model_hash_method -ne "verified_receipt_reuse" -or
        [string]$Result.model_receipt_sha256 -ine $script:g111ModelReceiptSHA256 -or
        [math]::Abs([double]$Result.dynamic_arena_gib_requested - $expectedArenaGiB) -gt 0.001 -or
        [bool](Get-G111Property $Result "dynamic_arena_cap_capped" $false) -or
        [int]$Result.dynamic_arena_allocated_slots -ne $expectedArenaSlots -or
        [int]$Result.expert_cache_capacity -ne $expectedCacheCapacity -or
        [double]$Result.expert_cache_reserve_gb -ne 0.125 -or
        [string]$Result.expert_cache_policy -ne "lru" -or
        -not [bool]$Result.q8_f16_cache_disabled -or
        -not [bool]$Result.embed_row_staging_requested -or
        -not [bool]$Result.arena_wrap_trust_worker_checksum_requested -or
        [string]$Result.arena_wrap_schedule_requested -ne "source-parts" -or
        [string]$Result.arena_wrap_schedule_observed -ne "source-parts" -or
        -not [bool]$Result.arena_wrap_unlock_source_ranges_requested -or
        -not [bool]$Result.arena_wrap_unlock_source_ranges_observed -or
        [UInt64]$Result.arena_wrap_unlock_source_ranges_summary_failed -ne 0 -or
        -not [bool]$Result.prefill_mass_wrap_observed -or
        [string]$Result.prefill_mass_wrap_result -ne "published" -or
        [string]$Result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not [bool]$Result.compose_prefill_mass_tiering_requested -or
        -not [bool]$tier.compose_prefill_mass_tiering_observed -or
        [string]$tier.requested_mode -ne "enforce" -or
        [string]$tier.requested_policy -ne "mass-lfru" -or
        [int]$tier.replacement_budget -ne 32 -or
        [int]$tier.min_frequency -ne 3 -or
        [math]::Abs([double]$tier.hysteresis - 1.25) -gt 0.000001 -or
        [int]$tier.states_vram -ne $expectedCacheCapacity -or
        [UInt64]$tier.snapshot_backing_misses -ne 0 -or
        [UInt64]$tier.ssd_bytes -ne 0 -or [UInt64]$tier.failures -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        (-not $Safety -and
         (-not [bool]$Result.benchmark_verified_receipt_reuse_allowed -or
          -not [bool]$Result.benchmark_verified_receipt_lock_proof_required -or
          -not [bool]$Result.benchmark_verified_receipt_lock_proof_observed)) -or
        $routeContractFailed -or
        -not [bool]$Result.memory_preflight.ready_to_launch -or
        -not [bool]$Result.process_isolation_preflight.ready_to_launch -or
        -not [bool]$Result.system_quiescence_preflight.ready_to_launch -or
        [bool]$Result.system_quiescence_preflight.skipped -or
        [bool]$Result.runtime_telemetry.contamination_abort_observed) {
        throw "G111 common G73 contract mismatch: tag=$($Result.tag)"
    }
    if ($ExpectedContentSHA256) {
        if ([string]$Result.expected_content_sha256 -ine $ExpectedContentSHA256 -or
            [string]$sample.content_sha256 -ine $ExpectedContentSHA256 -or
            -not [bool]$Result.outputs_identical) {
            throw "G111 exact content contract mismatch: tag=$($Result.tag)"
        }
    } elseif ([string]$Result.expected_content_sha256 -ne "") {
        throw "G111 safety must observe rather than preregister candidate hash"
    }
}

function Assert-G111ArmContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [AllowEmptyString()][string]$ExpectedContentSHA256,
        [Parameter(Mandatory=$true)][bool]$Safety
    )
    Assert-G111CommonContract -Result $Result -Arm $Arm -ExpectedContentSHA256 $ExpectedContentSHA256 -Safety $Safety
    if ($Arm -eq "control") {
        if ([bool]$Result.q1_0_sidecar_enabled -or
            [bool]$Result.q1_0_selected_load_requested -or
            [int]$Result.q1_0_resident_mode -ne 0 -or
            [UInt64]$Result.q1_0_resident_hits -ne 0 -or
            [UInt64]$Result.q1_0_resident_misses -ne 0 -or
            [UInt64]$Result.q1_0_direct_pread_bytes -ne 0 -or
            [string](Get-G111Property $Result.effective_ds4_environment "DS4_Q1_0_SNAPSHOT_BACKING" "") -ne "") {
            throw "G111 control unexpectedly enabled Q1_0"
        }
        return
    }
    $tier = $Result.expert_tiering
    if (-not [bool]$Result.q1_0_sidecar_enabled -or
        -not [bool]$Result.q1_0_selected_load_requested -or
        [string]$Result.q1_0_sidecar -ine ([IO.Path]::GetFullPath($Q1SidecarPath)) -or
        [UInt64]$Result.q1_0_sidecar_bytes -ne $ExpectedQ1SidecarBytes -or
        [string]$Result.q1_0_sidecar_sha256 -ine $ExpectedQ1SidecarSHA256 -or
        [string]$Result.q1_0_sidecar_hash_method -ne "verified_receipt_reuse" -or
        [string]$Result.q1_0_sidecar_receipt_sha256 -ine $script:g111Q1ReceiptSHA256 -or
        -not [bool]$Result.q1_0_sidecar_provenance_verified -or
        -not [bool]$Result.q1_0_sidecar_runtime_observed -or
        [int]$Result.q1_0_layer_first_requested -ne 0 -or [int]$Result.q1_0_layer_last_requested -ne 42 -or
        [UInt64]$Result.q1_0_sidecar_route_calls -le 0 -or
        [UInt64]$Result.q1_0_sidecar_selected_loads -ne [UInt64]$Result.q1_0_sidecar_route_calls -or
        [UInt64]$Result.q1_0_sidecar_failures -ne 0 -or
        [int]$Result.q1_0_resident_mode -ne 1 -or
        [UInt64]$Result.q1_0_resident_hits -le 0 -or
        [UInt64]$Result.q1_0_resident_misses -ne 0 -or
        [UInt64]$Result.q1_0_resident_h2d_bytes -le 0 -or
        [UInt64]$Result.q1_0_direct_pread_fallbacks -ne 0 -or
        [UInt64]$Result.q1_0_direct_pread_bytes -ne 0 -or
        [UInt64]$Result.q1_0_bootstrap_entries -ne [UInt64]$expectedArenaSlots -or
        -not [bool]$Result.q1_0_mixed.observed -or
        [UInt64]$Result.q1_0_mixed.calls -eq 0 -or
        [UInt64]$Result.q1_0_mixed.q1_resident -eq 0 -or
        [UInt64]$Result.q1_0_mixed.failures -ne 0 -or
        [UInt64]$Result.q1_0_mixed.iq2_ssd_violations -ne 0 -or
        [UInt64]$Result.q1_0_mixed.iq2_ssd_bytes -ne 0 -or
        [UInt64]$tier.snapshot_backing_entries -ne [UInt64]$expectedArenaSlots -or
        [UInt64]$tier.snapshot_backing_hits -le 0 -or
        [UInt64]$tier.snapshot_backing_misses -ne 0 -or
        [UInt64]$tier.ssd_bytes -ne 0 -or
        [UInt64]$tier.forbidden_cold_ssd_to_vram -ne 0 -or
        [string](Get-G111Property $Result.effective_ds4_environment "DS4_Q1_0_SNAPSHOT_BACKING" "") -ne "1" -or
        [int]$Result.effective_ds4_environment.DS4_Q1_0_LAYER_FIRST -ne 0 -or
        [int]$Result.effective_ds4_environment.DS4_Q1_0_LAYER_LAST -ne 42) {
        throw "G111 candidate Q1_0 sparse snapshot contract mismatch: tag=$($Result.tag)"
    }
    if ($LongCyberpunk -and
        ([UInt64]$Result.prefill_mass_wrap_candidate_entries -ne 11008 -or
         [UInt64]$Result.prefill_mass_compose_hash_layers -ne 3 -or
         [UInt64]$Result.prefill_mass_compose_hash_seed_entries -ne 768 -or
         [UInt64]$Result.prefill_mass_compose_ranked_entries -ne 10240 -or
         [UInt64]$Result.prefill_mass_compose_total_candidate -ne 11008 -or
         [double]$Result.prefill_mass_coverage -lt 0.999999 -or
         -not [bool]$Result.q1_0_pageable_overflow_requested -or
         [string](Get-G111Property $Result.effective_ds4_environment "DS4_Q1_0_PAGEABLE_OVERFLOW" "") -ne "1" -or
         [UInt64]$Result.dynamic_arena_allocated_slots -ne 11008 -or
         [UInt64]$Result.dynamic_arena_allocated_pinned_slots -ne 9102 -or
         [UInt64]$Result.dynamic_arena_allocated_pageable_slots -ne 1906 -or
         [UInt64]$Result.dynamic_arena_allocated_total_bytes -ne 38956695552)) {
        throw "G111 full-Q1 residency coverage contract mismatch: tag=$($Result.tag)"
    }
}

function Invoke-G111Arm {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("control", "candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("benchmark", "structural-safety")][string]$GateKind,
        [AllowEmptyString()][string]$ExpectedContentSHA256,
        [Parameter(Mandatory=$true)][bool]$Safety
    )
    $resultPath = Get-G111ResultPath $Tag
    $rawPath = Get-G111RawPath $Tag
    try {
        if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            Write-Host "[g111] resume arm=$Arm tag=$Tag"
        } else {
            $args = @(New-G111MeasureArgs -Arm $Arm -Tag $Tag -GateKind $GateKind -ExpectedContentSHA256 $ExpectedContentSHA256)
            Write-Host "[g111] start arm=$Arm tag=$Tag"
            & powershell.exe @args | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "G111 harness failed: arm=$Arm tag=$Tag exit=$LASTEXITCODE"
            }
        }
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            throw "G111 result missing: $resultPath"
        }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        Assert-G111ArmContract -Result $result -Arm $Arm -ExpectedContentSHA256 $ExpectedContentSHA256 -Safety $Safety
        $tier = $result.expert_tiering
        [pscustomobject][ordered]@{
            arm = $Arm
            tag = $Tag
            safety = $Safety
            failed = $false
            result_path = $resultPath
            result_sha256 = Get-G111FileSHA256 $resultPath
            raw_outputs_path = $rawPath
            raw_outputs_sha256 = $(if (Test-Path -LiteralPath $rawPath -PathType Leaf) { Get-G111FileSHA256 $rawPath } else { "" })
            content_sha256 = [string]$result.results[0].content_sha256
            decode_tokens_per_second = [double]$result.server_decode_mean_tokens_per_second
            end_to_end_tokens_per_second = [double]$result.mean_tokens_per_second
            completion_tokens = [int]$result.results[0].completion_tokens
            finish_reason = [string]$result.server_runs[0].finish_reason
            ttft_seconds = [double]$result.server_prefill_ttft_mean_seconds
            wrap_seconds = [double]$result.prefill_mass_wrap_seconds
            head = [string]$result.head
            executable_sha256 = [string]$result.executable_sha256
            ds4_cuda_sha256 = [string]$result.ds4_cuda_sha256
            ds4_c_sha256 = [string]$result.ds4_c_sha256
            ds4_gpu_h_sha256 = [string]$result.ds4_gpu_h_sha256
            build_manifest_sha256 = [string]$result.build_manifest_sha256
            build_input_fingerprint_sha256 = [string]$result.build_manifest_input_fingerprint_sha256
            harness_sha256 = [string]$result.harness_sha256
            model_sha256 = [string]$result.model_sha256
            prompt_sha256 = [string]$result.prompt_sha256
            arena_gib = [double]$result.dynamic_arena_gib_requested
            arena_slots = [int]$result.dynamic_arena_allocated_slots
            arena_pinned_slots = [int]$result.dynamic_arena_allocated_pinned_slots
            arena_pageable_slots = [int]$result.dynamic_arena_allocated_pageable_slots
            arena_pageable_hits = [UInt64]$result.dynamic_arena_final_pageable_hits
            snapshot_backing_entries = [UInt64]$tier.snapshot_backing_entries
            snapshot_backing_hits = [UInt64]$tier.snapshot_backing_hits
            snapshot_backing_misses = [UInt64]$tier.snapshot_backing_misses
            ssd_bytes = [UInt64]$tier.ssd_bytes
            q1_resident_hits = [UInt64]$result.q1_0_resident_hits
            q1_resident_misses = [UInt64]$result.q1_0_resident_misses
            q1_direct_pread_fallbacks = [UInt64]$result.q1_0_direct_pread_fallbacks
            q1_direct_pread_bytes = [UInt64]$result.q1_0_direct_pread_bytes
            available_min_gib = [math]::Round([UInt64]$result.runtime_telemetry.windows_available_min_bytes / 1GB, 6)
        }
    } catch {
        [pscustomobject][ordered]@{
            arm = $Arm
            tag = $Tag
            safety = $Safety
            failed = $true
            message = $_.Exception.Message
            result_path = $resultPath
        }
    }
}

function Assert-G111Aggregate {
    param([object[]]$Rows)
    $matrix = @($Rows | Where-Object { -not $_.safety -and -not $_.failed })
    $control = @($matrix | Where-Object { $_.arm -eq "control" })
    $candidate = @($matrix | Where-Object { $_.arm -eq "candidate" })
    if (($LongCyberpunk -and $candidate.Count -lt 3) -or
        (-not $LongCyberpunk -and
         ($control.Count -lt 3 -or $candidate.Count -lt 3))) {
        throw "G111 aggregate does not satisfy the preregistered n>=3 contract"
    }
    $controlHashes = @($control.content_sha256 | Select-Object -Unique)
    $candidateHashes = @($candidate.content_sha256 | Select-Object -Unique)
    if (-not $LongCyberpunk -and
        ($controlHashes.Count -ne 1 -or
         [string]$controlHashes[0] -ine $script:g111ControlContentSHA256)) {
        throw "G111 control aggregate exactness failed"
    }
    if ($candidateHashes.Count -ne 1 -or [string]$candidateHashes[0] -ine $script:g111CandidateContentSHA256) {
        throw "G111 candidate aggregate exactness failed"
    }
    foreach ($field in @(
        "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
        "ds4_gpu_h_sha256", "build_manifest_sha256",
        "build_input_fingerprint_sha256", "harness_sha256",
        "model_sha256", "prompt_sha256")) {
        $values = @($matrix | ForEach-Object { [string]$_.$field } | Select-Object -Unique)
        if ($values.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$values[0])) {
            throw "G111 mixed or missing provenance: field=$field"
        }
    }
}

function Test-G111Outlier {
    param([object[]]$Rows)
    $arms = if ($LongCyberpunk) { @("candidate") } else { @("control", "candidate") }
    foreach ($arm in $arms) {
        $armRows = @($Rows | Where-Object { $_.arm -eq $arm -and -not $_.safety -and -not $_.failed })
        if ($armRows.Count -lt 3) { return $false }
        foreach ($field in @("decode_tokens_per_second", "end_to_end_tokens_per_second", "ttft_seconds", "wrap_seconds")) {
            $values = @($armRows | ForEach-Object { [double]$_.$field } | Where-Object { $_ -gt 0 } | Sort-Object)
            if ($values.Count -ge 3 -and ($values[-1] / $values[0]) -gt $outlierRatio) {
                return $true
            }
        }
    }
    $false
}

function New-G111ArmSummary {
    param([object[]]$Rows)
    $summaries = @()
    foreach ($arm in @("control", "candidate")) {
        $armRows = @($Rows | Where-Object { $_.arm -eq $arm -and -not $_.safety -and -not $_.failed })
        $summaries += [pscustomobject][ordered]@{
            arm = $arm
            independent_processes = $armRows.Count
            n3_timing_eligible = ($armRows.Count -ge 3)
            decode_tokens_per_second_mean = Get-G111Mean $armRows "decode_tokens_per_second"
            decode_tokens_per_second_median = Get-G111Median $armRows "decode_tokens_per_second"
            end_to_end_tokens_per_second_mean = Get-G111Mean $armRows "end_to_end_tokens_per_second"
            end_to_end_tokens_per_second_median = Get-G111Median $armRows "end_to_end_tokens_per_second"
            completion_tokens_mean = Get-G111Mean $armRows "completion_tokens"
            ttft_mean_seconds = Get-G111Mean $armRows "ttft_seconds"
            wrap_mean_seconds = Get-G111Mean $armRows "wrap_seconds"
            snapshot_backing_hits_mean = Get-G111Mean $armRows "snapshot_backing_hits"
            q1_resident_hits_mean = Get-G111Mean $armRows "q1_resident_hits"
            available_min_gib_min = $(if ($armRows.Count) {
                [math]::Round(($armRows | Measure-Object -Property available_min_gib -Minimum).Minimum, 6)
            } else { $null })
        }
    }
    $summaries
}

function Write-G111Summary {
    param([object[]]$Rows, [string]$Status, [string]$StopReason, [bool]$OutlierExtensionTriggered)
    New-Item -ItemType Directory -Force -Path $outdir | Out-Null
    $matrix = @($Rows | Where-Object { -not $_.safety -and -not $_.failed })
    $control = @($matrix | Where-Object { $_.arm -eq "control" })
    $candidate = @($matrix | Where-Object { $_.arm -eq "candidate" })
    $summary = [pscustomobject][ordered]@{
        schema = $(if ($LongCyberpunk) {
            "g111_q1_sparse_snapshot_long_cyberpunk_v1"
        } else {
            "g111_q1_sparse_snapshot_ab_v1"
        })
        measured_utc = [DateTime]::UtcNow.ToString("o")
        mode = $modeName
        context_requested = $context
        prefill_chunk_requested = $prefillChunk
        max_tokens_requested = $maxTokens
        stop_sequence = $stopSequence
        temperature = 0
        think = $false
        status = $Status
        stop_reason = $StopReason
        preregistered = $true
        safety_n1_structural_exactness_only = $true
        safety_performance_claim_allowed = $false
        safety_quality_claim_allowed = $false
        matrix_n3_complete = $(if ($LongCyberpunk) {
            $candidate.Count -ge 3
        } else {
            $control.Count -ge 3 -and $candidate.Count -ge 3
        })
        candidate_n3_timing_eligible = ($Status -eq "matrix_complete" -and $candidate.Count -ge 3)
        timing_comparison_eligible = (-not $LongCyberpunk -and
            $Status -eq "matrix_complete" -and
            $control.Count -ge 3 -and $candidate.Count -ge 3)
        control_name = $controlName
        control_is_canonical_g73 = $false
        historical_g73_reference_only = $true
        historical_g73_decode_tps = 4.986667
        historical_g73_direct_comparison_eligible = $false
        current_control_additional_levers = $(if ($LongCyberpunk) { @() } else {
            @("post-G73 packed route H2D runtime", "prefill VRAM $seedTag")
        })
        quality_grade = ""
        quality_claim_allowed = $false
        sota_claim_allowed = $false
        candidate_expected_content_sha256 = $script:g111CandidateContentSHA256
        control_expected_content_sha256 = $script:g111ControlContentSHA256
        prompt_sha256 = $expectedPromptSHA256
        model_path = [IO.Path]::GetFullPath($ModelPath)
        model_sha256 = $ExpectedModelSHA256.ToLowerInvariant()
        q1_sidecar_path = [IO.Path]::GetFullPath($Q1SidecarPath)
        q1_sidecar_sha256 = $ExpectedQ1SidecarSHA256.ToLowerInvariant()
        q1_sidecar_bytes = $ExpectedQ1SidecarBytes
        q1_layers = "0..42"
        control_dynamic_arena_gib = $controlArenaGiB
        candidate_dynamic_arena_gib = $candidateArenaGiB
        control_expected_arena_slots = $controlArenaSlots
        candidate_expected_arena_slots = $candidateArenaSlots
        expert_cache_capacity = $expectedCacheCapacity
        matrix_order = $matrixOrder
        outlier_extension_triggered = $OutlierExtensionTriggered
        outlier_rule = "If either arm exceeds 20% max/min spread after n=3, run exactly three additional clean processes per arm before interpretation."
        stop_conditions = @(
            "candidate safety failure stops the matrix",
            "any provenance, exactness, quiescence or runtime contract mismatch invalidates the matrix",
            "candidate Q1 miss, direct pread fallback/byte, tier SSD byte or snapshot miss invalidates the run",
            "n=1 safety never supports timing, quality or SOTA claims",
            "SOTA claim remains blocked until external L0-L3 grading"
        )
        arm_summary = New-G111ArmSummary $Rows
        rows = $Rows
        provenance = $(if ($matrix.Count) {
            [pscustomobject][ordered]@{
                head = $matrix[0].head
                executable_sha256 = $matrix[0].executable_sha256
                ds4_cuda_sha256 = $matrix[0].ds4_cuda_sha256
                ds4_c_sha256 = $matrix[0].ds4_c_sha256
                ds4_gpu_h_sha256 = $matrix[0].ds4_gpu_h_sha256
                build_manifest_sha256 = $matrix[0].build_manifest_sha256
                build_input_fingerprint_sha256 = $matrix[0].build_input_fingerprint_sha256
                harness_sha256 = $matrix[0].harness_sha256
                runner_sha256 = Get-G111FileSHA256 $runnerPath
                model_receipt_sha256 = $script:g111ModelReceiptSHA256
                q1_receipt_sha256 = $script:g111Q1ReceiptSHA256
            }
        } else { $null })
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding ASCII
    $summary
}

Assert-G111StaticContract
if ($StaticCheckOnly) {
    New-G111StaticReceipt | ConvertTo-Json -Depth 8
    exit 0
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G111RuntimeInputs
$locks = New-Object 'System.Collections.Generic.List[System.IDisposable]'
$rows = @()
$outlierExtensionTriggered = $false
try {
    foreach ($path in @($ModelPath, $Q1SidecarPath, "$ModelPath.receipt.json", "$Q1SidecarPath.receipt.json")) {
        $locks.Add((Open-G111ReadLock $path))
    }
    $tagPrefix = if ($LongCyberpunk) { "g111_long" } else { "g111" }
    $safetyTag = "${tagPrefix}_candidate_q1_sparse_snapshot_safety_n1"
    if (-not [string]::IsNullOrWhiteSpace($RunLabel)) {
        $safetyTag = "${safetyTag}_$RunLabel"
    }
    $safety = Invoke-G111Arm -Arm "candidate" -Tag $safetyTag -GateKind "structural-safety" -ExpectedContentSHA256 "" -Safety $true
    $rows += $safety
    if ($safety.failed) {
        Write-G111Summary -Rows $rows -Status "stopped" -StopReason "candidate_safety_failed" -OutlierExtensionTriggered $false | ConvertTo-Json -Depth 12
        exit 1
    }
    $script:g111CandidateContentSHA256 = $safety.content_sha256
    if ($SafetyOnly) {
        $safetySummary = [pscustomobject][ordered]@{
            schema = $(if ($LongCyberpunk) {
                "g111_q1_sparse_snapshot_long_cyberpunk_safety_v1"
            } else {
                "g111_q1_sparse_snapshot_safety_v1"
            })
            measured_utc = [DateTime]::UtcNow.ToString("o")
            mode = $modeName
            context_requested = $context
            prefill_chunk_requested = $prefillChunk
            max_tokens_requested = $maxTokens
            stop_sequence = $stopSequence
            structural_exactness_only = $true
            performance_claim_allowed = $false
            quality_claim_allowed = $false
            control_observed_content_sha256 = $script:g111ControlContentSHA256
            candidate_observed_content_sha256 = $script:g111CandidateContentSHA256
            result = $safety
        }
        $safetySummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $safetySummaryPath -Encoding ASCII
        $safetySummary | ConvertTo-Json -Depth 10
        exit 0
    }
    $matrixPlan = if ($LongCyberpunk) {
        @(
            @("${tagPrefix}_candidate_q1_full_p1", "candidate"),
            @("${tagPrefix}_candidate_q1_full_p2", "candidate"),
            @("${tagPrefix}_candidate_q1_full_p3", "candidate")
        )
    } else {
        @(
            @("${tagPrefix}_control_iq2_${seedTag}_p1", "control"),
            @("${tagPrefix}_candidate_q1_snapshot_p1", "candidate"),
            @("${tagPrefix}_candidate_q1_snapshot_p2", "candidate"),
            @("${tagPrefix}_control_iq2_${seedTag}_p2", "control"),
            @("${tagPrefix}_control_iq2_${seedTag}_p3", "control"),
            @("${tagPrefix}_candidate_q1_snapshot_p3", "candidate")
        )
    }
    foreach ($entry in $matrixPlan) {
        $expectedHash = if ($entry[1] -eq "control") { $script:g111ControlContentSHA256 } else { $script:g111CandidateContentSHA256 }
        $row = Invoke-G111Arm -Arm $entry[1] -Tag $entry[0] -GateKind "benchmark" -ExpectedContentSHA256 $expectedHash -Safety $false
        $rows += $row
        if ($row.failed) {
            Write-G111Summary -Rows $rows -Status "invalid" -StopReason ("matrix_run_failed:" + $row.tag) -OutlierExtensionTriggered $outlierExtensionTriggered | ConvertTo-Json -Depth 12
            exit 1
        }
    }
    if (Test-G111Outlier $rows) {
        $outlierExtensionTriggered = $true
        $extensionPlan = if ($LongCyberpunk) {
            @(
                @("${tagPrefix}_candidate_q1_full_x1", "candidate"),
                @("${tagPrefix}_candidate_q1_full_x2", "candidate"),
                @("${tagPrefix}_candidate_q1_full_x3", "candidate")
            )
        } else {
            @(
                @("${tagPrefix}_candidate_q1_snapshot_x1", "candidate"),
                @("${tagPrefix}_control_iq2_${seedTag}_x1", "control"),
                @("${tagPrefix}_control_iq2_${seedTag}_x2", "control"),
                @("${tagPrefix}_candidate_q1_snapshot_x2", "candidate"),
                @("${tagPrefix}_candidate_q1_snapshot_x3", "candidate"),
                @("${tagPrefix}_control_iq2_${seedTag}_x3", "control")
            )
        }
        foreach ($entry in $extensionPlan) {
            $expectedHash = if ($entry[1] -eq "control") { $script:g111ControlContentSHA256 } else { $script:g111CandidateContentSHA256 }
            $row = Invoke-G111Arm -Arm $entry[1] -Tag $entry[0] -GateKind "benchmark" -ExpectedContentSHA256 $expectedHash -Safety $false
            $rows += $row
            if ($row.failed) {
                Write-G111Summary -Rows $rows -Status "invalid" -StopReason ("outlier_extension_failed:" + $row.tag) -OutlierExtensionTriggered $true | ConvertTo-Json -Depth 12
                exit 1
            }
        }
    }
    Assert-G111Aggregate $rows
    $completedReason = if ($LongCyberpunk) {
        "completed_preregistered_full_q1_n3"
    } else {
        "completed_preregistered_counterbalanced_sequence"
    }
    Write-G111Summary -Rows $rows -Status "matrix_complete" -StopReason $completedReason -OutlierExtensionTriggered $outlierExtensionTriggered | ConvertTo-Json -Depth 12
} finally {
    foreach ($lock in $locks) {
        try { $lock.Dispose() } catch {}
    }
}
