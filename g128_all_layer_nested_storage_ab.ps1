# G128 n>=3 A/B runner for all-layer nested storage.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g128_all_layer_nested_storage_ab',
    [ValidatePattern('^$|^[A-Za-z0-9_-]+$')]
    [string]$ResumeBatchTag = '',
    [Parameter(Mandatory=$true)]
    [string]$G128SafetyReceipt,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedG128SafetyReceiptSHA256,
    [Parameter(Mandatory=$true)]
    [string]$NestedResidualSidecar,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedNestedResidualSidecarSHA256,
    [Parameter(Mandatory=$true)]
    [UInt64]$ExpectedNestedResidualSidecarBytes,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedNestedResidualPayloadSHA256,
    [ValidateRange(3, 20)][int]$Repeats = 3,
    [ValidateRange(1.0, 30.0)][double]$ControlDynamicArenaGiB = 30.0,
    [ValidateRange(0.25, 12.0)][double]$CandidateDynamicArenaGiB = 2.0,
    [ValidateRange(0.25, 30.0)][double]$NestedResidualBasePinnedGiB = 28.0,
    [ValidateRange(40, 4096)][int]$NestedResidualCacheExperts = 320,
    [ValidateRange(0, 600)][int]$InterChildCooldownSec = 30,
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root 'g7_measure.ps1'
$bootstrap = Join-Path $root 'g7_harness_bootstrap.ps1'
$runs = Join-Path $root 'g7_runs'
$exe = Join-Path $root 'build\Release\ds4_server.exe'
$buildManifestPath = Join-Path $root 'build\Release\g7_build_manifest.json'
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelSHA = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
$sidecar = $NestedResidualSidecar
$sidecarBytes = $ExpectedNestedResidualSidecarBytes
$sidecarSHA = $ExpectedNestedResidualSidecarSHA256.ToLowerInvariant()
$payloadSHA = $ExpectedNestedResidualPayloadSHA256.ToLowerInvariant()
$expectedContentSHA = 'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510'
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$expectedBaseHostGiB = 37.5
$expectedResidualCacheHostGiB =
    ([double]$NestedResidualCacheExperts * 3.0) / 1024.0
$expectedCandidateHostAllocationGiB =
    $expectedBaseHostGiB + $expectedResidualCacheHostGiB +
        $CandidateDynamicArenaGiB

if ($ExpectedNestedResidualSidecarBytes -eq 0) {
    throw 'G128 expected nested residual sidecar bytes must be positive'
}
if (($NestedResidualBasePinnedGiB + $CandidateDynamicArenaGiB) -gt 30.0) {
    throw 'G128 nested base pinned GiB plus candidate dynamic arena GiB must be <= 30'
}

function Get-G128Sha256Text {
    param([Parameter(Mandatory=$true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return [BitConverter]::ToString(
            $sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-G128ConfigurationSHA {
    $contract = @(
        'schema=g128_all_layer_nested_storage_config_v1',
        "model_sha256=$modelSHA",
        "sidecar_sha256=$sidecarSHA",
        "sidecar_payload_sha256=$payloadSHA",
        "prompt_sha256=$promptSHA",
        "expected_content_sha256=$expectedContentSHA",
        'temperature=0',
        'nothink=1',
        'max_tokens=64',
        'context=256',
        "dynamic_arena_gib=$CandidateDynamicArenaGiB",
        'nested_residual_pageable_base=1',
        "nested_residual_base_pinned_gib=$NestedResidualBasePinnedGiB",
        'nested_residual_cache_pageable=1',
        "nested_residual_cache_experts=$NestedResidualCacheExperts",
        'nested_residual_gpu_cache=1',
        'nested_residual_gpu_join=1',
        'nested_residual_gpu_join_residual_cache=1',
        'nested_residual_verify_reconstruction=0',
        'router=full/open',
        'layer_first=3',
        'layer_last=42',
        'layer_count=40'
    ) -join "`n"
    return Get-G128Sha256Text -Text ($contract + "`n")
}

function Get-G128CurrentBuildContract {
    foreach ($path in @($exe, $buildManifestPath, $harness, $bootstrap)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G128 current-build input missing: $path"
        }
    }
    $manifest = Get-Content -LiteralPath $buildManifestPath -Raw |
        ConvertFrom-Json
    $exeSHA = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $manifestSHA = (Get-FileHash -LiteralPath $buildManifestPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$manifest.schema -ne 'g7_native_windows_build_manifest_v1' -or
        [string]$manifest.executable_sha256 -ine $exeSHA -or
        [string]$manifest.input_fingerprint_sha256 -notmatch
            '^[0-9a-fA-F]{64}$') {
        throw 'G128 current build manifest contract mismatch'
    }
    return [pscustomobject]@{
        executable_sha256 = $exeSHA
        manifest_sha256 = $manifestSHA
        input_fingerprint_sha256 =
            ([string]$manifest.input_fingerprint_sha256).ToLowerInvariant()
        harness_sha256 = (Get-FileHash -LiteralPath $harness `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        bootstrap_sha256 = (Get-FileHash -LiteralPath $bootstrap `
            -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-G128SafetyReceipt {
    param(
        [Parameter(Mandatory=$true)][string]$ReceiptPath,
        [Parameter(Mandatory=$true)][string]$ExpectedReceiptSHA,
        [Parameter(Mandatory=$true)][object]$CurrentBuild
    )

    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) {
        throw "G128 safety receipt is missing: $ReceiptPath"
    }
    $resolvedReceipt = (Resolve-Path -LiteralPath $ReceiptPath).Path
    $receiptSHA = (Get-FileHash -LiteralPath $resolvedReceipt `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($receiptSHA -ine $ExpectedReceiptSHA) {
        throw 'G128 safety receipt SHA-256 mismatch'
    }
    $receipt = Get-Content -LiteralPath $resolvedReceipt -Raw |
        ConvertFrom-Json
    $expectedSafetyConfig = Get-G128Sha256Text -Text ((@(
        'schema=g128_all_layer_nested_storage_config_v1',
        "model_sha256=$modelSHA",
        "sidecar_sha256=$sidecarSHA",
        "sidecar_payload_sha256=$payloadSHA",
        "prompt_sha256=$promptSHA",
        "expected_content_sha256=$expectedContentSHA",
        'temperature=0',
        'nothink=1',
        'max_tokens=64',
        'context=256',
        "dynamic_arena_gib=$CandidateDynamicArenaGiB",
        'nested_residual_pageable_base=1',
        "nested_residual_base_pinned_gib=$NestedResidualBasePinnedGiB",
        'nested_residual_cache_pageable=1',
        "nested_residual_cache_experts=$NestedResidualCacheExperts",
        'nested_residual_gpu_cache=1',
        'nested_residual_gpu_join=1',
        'nested_residual_gpu_join_residual_cache=1',
        'nested_residual_verify_reconstruction=1',
        'router=full/open',
        'layer_first=3',
        'layer_last=42',
        'layer_count=40'
    ) -join "`n") + "`n")
    if ([string]$receipt.schema -ne
            'ds4_g128_all_layer_nested_storage_safety_v1' -or
        [string]$receipt.status -ne
            'pass_structural_n1_no_performance_or_quality_verdict' -or
        [string]$receipt.claim_scope -ne
            'structural_safety_only_no_sota_no_quality_verdict' -or
        [string]$receipt.result_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [string]$receipt.exact_content_sha256 -ine $expectedContentSHA -or
        [string]$receipt.prompt_sha256 -ine $promptSHA -or
        [string]$receipt.configuration_sha256 -ine $expectedSafetyConfig) {
        throw 'G128 safety receipt top-level contract mismatch'
    }
    if ([int]$receipt.all_layer.first -ne 3 -or
        [int]$receipt.all_layer.last -ne 42 -or
        [int]$receipt.all_layer.count -ne 40) {
        throw 'G128 safety receipt all-layer coverage mismatch'
    }
    if ([IO.Path]::GetFullPath([string]$receipt.sidecar.path) -ine
            [IO.Path]::GetFullPath($sidecar) -or
        [UInt64]$receipt.sidecar.bytes -ne $sidecarBytes -or
        [string]$receipt.sidecar.sha256 -ine $sidecarSHA -or
        [string]$receipt.sidecar.source_sha256 -ine $modelSHA -or
        [string]$receipt.sidecar.payload_sha256 -ine $payloadSHA) {
        throw 'G128 safety receipt sidecar provenance mismatch'
    }
    if (-not [bool]$receipt.base_storage.pageable_enabled -or
        [double]$receipt.base_storage.pinned_gib_requested -ne
            [double]$NestedResidualBasePinnedGiB -or
        [UInt64]$receipt.base_storage.pinned_entries -eq 0 -or
        [UInt64]$receipt.base_storage.pinned_bytes -eq 0 -or
        [UInt64]$receipt.base_storage.pinned_hits -eq 0 -or
        [UInt64]$receipt.base_storage.pinned_h2d_bytes -eq 0 -or
        [UInt64]$receipt.base_storage.pageable_entries -eq 0 -or
        [UInt64]$receipt.base_storage.pageable_bytes -eq 0 -or
        [UInt64]$receipt.base_storage.pageable_hits -eq 0 -or
        [UInt64]$receipt.base_storage.pageable_h2d_bytes -eq 0 -or
        [UInt64]$receipt.base_storage.invariant_failures -ne 0) {
        throw 'G128 safety receipt base-storage counters failed'
    }
    if (-not [bool]$receipt.residual_cache.pageable_enabled -or
        [UInt64]$receipt.residual_cache.capacity -ne
            [UInt64]$NestedResidualCacheExperts -or
        [UInt64]$receipt.residual_cache.pinned_entries -ne 0 -or
        [UInt64]$receipt.residual_cache.pinned_bytes -ne 0 -or
        [UInt64]$receipt.residual_cache.pinned_hits -ne 0 -or
        [UInt64]$receipt.residual_cache.pinned_h2d_bytes -ne 0 -or
        [UInt64]$receipt.residual_cache.pageable_entries -eq 0 -or
        [UInt64]$receipt.residual_cache.pageable_bytes -eq 0 -or
        [UInt64]$receipt.residual_cache.pageable_hits -eq 0 -or
        [UInt64]$receipt.residual_cache.pageable_h2d_bytes -eq 0 -or
        [int]$receipt.residual_cache.partitioned -ne 1 -or
        [UInt64]$receipt.residual_cache.layer_slots_min -le 0 -or
        [UInt64]$receipt.residual_cache.layer_slots_max -lt
            [UInt64]$receipt.residual_cache.layer_slots_min -or
        [UInt64]$receipt.residual_cache.layer_slots_max -gt
            ([UInt64]$receipt.residual_cache.layer_slots_min + [UInt64]1) -or
        [UInt64]$receipt.residual_cache.invariant_failures -ne 0 -or
        [UInt64]$receipt.residual_cache.pageable_invariant_failures -ne 0) {
        throw 'G128 safety receipt residual-cache pageable counters failed'
    }
    if (-not [bool]$receipt.exactness.reconstruction_verify -or
        [UInt64]$receipt.exactness.verify_calls -eq 0 -or
        [UInt64]$receipt.exactness.verify_bytes -eq 0 -or
        [UInt64]$receipt.exactness.verify_mismatches -ne 0 -or
        [UInt64]$receipt.exactness.nested_mismatches -ne 0 -or
        [UInt64]$receipt.exactness.nested_failures -ne 0 -or
        [UInt64]$receipt.exactness.gpu_join_failures -ne 0 -or
        [UInt64]$receipt.exactness.cpu_reconstruct_calls -ne 0 -or
        [UInt64]$receipt.exactness.native_h2d_bytes -ne 0 -or
        [UInt64]$receipt.exactness.selected_load_fallbacks -ne 0 -or
        -not [bool]$receipt.gpu_join.requested -or
        -not [bool]$receipt.gpu_join.observed -or
        -not [bool]$receipt.gpu_cache.requested -or
        -not [bool]$receipt.machine_quiescence.ready_to_launch -or
        [bool]$receipt.machine_quiescence.skipped -or
        [int]$receipt.machine_quiescence.preflight_failures -ne 0 -or
        [int]$receipt.machine_quiescence.runtime_contamination_consecutive_peak -ne 0) {
        throw 'G128 safety receipt exactness/cache/quiescence contract failed'
    }
    if ([string]$receipt.build.executable_sha256 -ine
            $CurrentBuild.executable_sha256 -or
        [string]$receipt.build.build_manifest_sha256 -ine
            $CurrentBuild.manifest_sha256 -or
        [string]$receipt.build.build_manifest_input_fingerprint_sha256 -ine
            $CurrentBuild.input_fingerprint_sha256 -or
        [string]$receipt.build.harness_sha256 -ine $CurrentBuild.harness_sha256 -or
        [string]$receipt.build.bootstrap_sha256 -ine
            $CurrentBuild.bootstrap_sha256) {
        throw 'G128 safety receipt is not from the current build/harness'
    }
    if (-not (Test-Path -LiteralPath ([string]$receipt.result_path) `
            -PathType Leaf)) {
        throw 'G128 safety result referenced by receipt is missing'
    }
    $resultSHA = (Get-FileHash -LiteralPath ([string]$receipt.result_path) `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($resultSHA -ine [string]$receipt.result_sha256) {
        throw 'G128 safety result SHA-256 mismatch'
    }
    $safetyResult = Get-Content -LiteralPath ([string]$receipt.result_path) -Raw |
        ConvertFrom-Json
    if ([IO.Path]::GetFullPath(
            [string]$safetyResult.nested_residual_sidecar) -ine
            [IO.Path]::GetFullPath($sidecar) -or
        [UInt64]$safetyResult.nested_residual_sidecar_bytes -ne $sidecarBytes -or
        [string]$safetyResult.nested_residual_sidecar_sha256 -ine
            $sidecarSHA -or
        [string]$safetyResult.nested_residual_expected_source_sha256 -ine
            $modelSHA -or
        [string]$safetyResult.nested_residual_expected_payload_sha256 -ine
            $payloadSHA -or
        [double]$safetyResult.dynamic_arena_gib_requested -ne
            $CandidateDynamicArenaGiB -or
        [double]$safetyResult.nested_residual_base_pinned_gib_requested -ne
            $NestedResidualBasePinnedGiB -or
        [double]$safetyResult.nested_residual_expected_host_allocation_gib -ne
            $expectedCandidateHostAllocationGiB) {
        throw 'G128 safety result sidecar provenance mismatch'
    }
    return [pscustomobject]@{
        receipt_path = $resolvedReceipt
        receipt_sha256 = $receiptSHA
        result_path = [string]$receipt.result_path
        result_sha256 = [string]$receipt.result_sha256
        configuration_sha256 = [string]$receipt.configuration_sha256
    }
}

function Get-G128Mean {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    return (($Values | Measure-Object -Average).Average)
}

function Get-G128Median {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $mid = [int]($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$mid] }
    return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2.0
}

function New-G128Suffix {
    return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
        '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
}

function New-G128ChildPlan {
    param(
        [ValidateSet('control', 'candidate')][string]$Arm,
        [int]$RepeatIndex,
        [string]$BatchTag
    )
    $childTag = $BatchTag + '_' + $Arm + '_' + $RepeatIndex
    $childArenaGiB = if ($Arm -eq 'control') {
        $ControlDynamicArenaGiB
    } else {
        $CandidateDynamicArenaGiB
    }
    $args = @(
        '-GateKind', 'benchmark',
        '-ModelPath', $model,
        '-ExpectedModelSHA256', $modelSHA,
        '-ReuseVerifiedModelReceipt',
        '-AllowBenchmarkVerifiedReceiptReuse',
        '-Prompt', $prompt,
        '-ExpectedContentSHA256', $expectedContentSHA,
        '-MaxTokens', '64',
        '-Repeats', '1',
        '-Context', '256',
        '-Temperature', '0',
        '-NoThink',
        '-NoWarmup',
        '-BudgetGB', '2',
        '-ReserveMB', '1024',
        '-ForceOpenRouter',
        '-PrefillMassWrap',
        '-ComposePrefillMassTiering',
        '-ComposePrefillMassOpenRouter',
        '-ComposePrefillMassReserveSlots', '32',
        '-DynamicArenaGiB', ([string]$childArenaGiB),
        '-ArenaWrapTrustWorkerChecksum',
        '-ArenaWrapSourceParts',
        '-ArenaWrapUnlockSourceRanges',
        '-ArenaWrapUnlockWaveGiB', '4',
        '-DisableQ8F16Cache',
        '-EmbedRowStaging',
        '-ReapPrefetchThreads', '8',
        '-ExpertCacheN', '320',
        '-ExpertCacheReserveGB', '0.125',
        '-ExpertCachePolicy', 'lru',
        '-GpuResidentRoutes',
        '-RouteNoDefaultSync',
        '-ExpertTiering', 'enforce',
        '-ExpertTierPolicy', 'mass-lfru',
        '-ExpertTierClockCalls', '430',
        '-ExpertTierReplacementBudget', '32',
        '-ExpertTierMinFrequency', '3',
        '-ExpertTierHysteresis', '1.25',
        '-SplitFused',
        '-RuntimeMinimumAvailableGiB', '2',
        '-RuntimeHardMinimumAvailableGiB', '1',
        '-RuntimeMaximumDiskQueueLength', '8',
        '-RuntimeContaminationSamples', '3',
        '-QuiescenceCooldownSec', '10',
        '-TimeoutSec', [string]$TimeoutSec,
        '-Tag', $childTag
    )
    if ($Arm -eq 'candidate') {
        $args += @(
            '-NestedResidualSidecar', $sidecar,
            '-ExpectedNestedResidualSidecarSHA256', $sidecarSHA,
            '-ExpectedNestedResidualSourceSHA256', $modelSHA,
            '-ExpectedNestedResidualPayloadSHA256', $payloadSHA,
            '-NestedResidualGpuCache',
            '-NestedResidualGpuJoin',
            '-NestedResidualGpuJoinResidualCache',
            '-NestedResidualPageableBase',
            '-NestedResidualBasePinnedGiB',
                ([string]$NestedResidualBasePinnedGiB),
            '-NestedResidualCachePageable',
            '-NestedResidualCacheExperts',
                ([string]$NestedResidualCacheExperts),
            '-AllowNestedResidualBenchmarkSuite',
            '-OuterNestedResidualBenchmarkProcessCount', ([string]$Repeats),
            '-NestedResidualGpuJoinSafetyReceipt', $G128SafetyReceipt,
            '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
                $ExpectedG128SafetyReceiptSHA256.ToLowerInvariant()
        )
    }
    return [pscustomobject]@{
        arm = $Arm
        repeat_index = $RepeatIndex
        tag = $childTag
        result_path = Join-Path $runs ('g7_' + $childTag + '_result.json')
        harness_arguments = @($args)
    }
}

function Invoke-G128Child {
    param([Parameter(Mandatory=$true)][object]$Plan)

    if ($WhatIf) { return }
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $bootstrap,
        '-HarnessPath', $harness,
        '-RepoRoot', $root
    )
    foreach ($arg in @($Plan.harness_arguments)) {
        $argList += @('-HarnessArgument', $arg)
    }
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList `
        -WindowStyle Hidden -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "G128 child failed with exit code $($proc.ExitCode): $($Plan.tag)"
    }
    if ($InterChildCooldownSec -gt 0) {
        Start-Sleep -Seconds $InterChildCooldownSec
    }
}

function Read-G128ChildResult {
    param([Parameter(Mandatory=$true)][object]$Plan)

    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G128 child result missing: $($Plan.result_path)"
    }
    $json = Get-Content -LiteralPath $Plan.result_path -Raw |
        ConvertFrom-Json
    $samples = @($json.results)
    $expectedArenaGiB = if ($Plan.arm -eq 'control') {
        $ControlDynamicArenaGiB
    } else {
        $CandidateDynamicArenaGiB
    }
    if ([string]$json.gate_kind -ne 'benchmark' -or
        $samples.Count -ne 1 -or [int]$json.repeats -ne 1 -or
        [bool]$json.warmup -or [int]$json.server_exit_code -ne 0) {
        throw "G128 child result shape mismatch for $($Plan.tag)"
    }
    if ([string]$json.model_sha256 -ine $modelSHA -or
        [string]$json.prompt_sha256 -ine $promptSHA -or
        [int]$json.requested_max_tokens -ne 64 -or
        [int]$json.context_requested -ne 256 -or
        [double]$json.dynamic_arena_gib_requested -ne $expectedArenaGiB -or
        [int]$json.expert_cache_requested -ne 320 -or
        -not [bool]$json.compose_prefill_mass_open_router_requested -or
        [int]$json.expert_tiering.compose_router_open -ne 1 -or
        -not [bool]$json.gpu_resident_routes_requested -or
        -not [bool]$json.route_no_default_sync_requested -or
        -not [bool]$json.split_fused_requested -or
        [string]$json.reap_mask_file_requested -or
        [bool]$json.embedded_bake_mask_observed) {
        throw "G128 child common full/open SOTA contract failed for $($Plan.tag)"
    }
    $sample = $samples[0]
    $runtimePeak = 0
    if ($null -ne $json.runtime_telemetry -and
        $null -ne $json.runtime_telemetry.contamination_consecutive_peak) {
        $runtimePeak =
            [int]$json.runtime_telemetry.contamination_consecutive_peak
    }
    $exact = ([string]$sample.content_sha256 -ieq $expectedContentSHA)
    if (-not $exact) {
        throw "G128 child exact output mismatch for $($Plan.tag)"
    }
    if ($runtimePeak -ne 0) {
        throw "G128 child contamination gate failed for $($Plan.tag)"
    }
    if ($Plan.arm -eq 'control') {
        if ([bool]$json.nested_residual_enabled -or
            [bool]$json.nested_residual_pageable_base_requested -or
            [bool]$json.nested_residual_cache_pageable_requested -or
            [bool]$json.nested_residual_gpu_join_requested -or
            [bool]$json.nested_residual_gpu_cache_requested -or
            [bool]$json.allow_nested_residual_benchmark_suite_requested -or
            [bool]$json.nested_residual_benchmark_member -or
            [string]$json.nested_residual_gpu_join_safety_receipt_path) {
            throw "G128 control unexpectedly enabled nested-residual runtime"
        }
    } else {
        if (-not [bool]$json.nested_residual_enabled -or
            [IO.Path]::GetFullPath(
                [string]$json.nested_residual_sidecar) -ine
                [IO.Path]::GetFullPath($sidecar) -or
            [UInt64]$json.nested_residual_sidecar_bytes -ne $sidecarBytes -or
            [string]$json.nested_residual_sidecar_sha256 -ine $sidecarSHA -or
            [string]$json.nested_residual_expected_payload_sha256 -ine
                $payloadSHA -or
            -not [bool]$json.nested_residual_pageable_base_requested -or
            -not [bool]$json.nested_residual_cache_pageable_requested -or
            -not [bool]$json.nested_residual_gpu_join_requested -or
            -not [bool]$json.nested_residual_gpu_cache_requested -or
            -not [bool]$json.allow_nested_residual_benchmark_suite_requested -or
            [int]$json.outer_nested_residual_benchmark_process_count_requested -ne
                $Repeats -or
            -not [bool]$json.nested_residual_benchmark_member -or
            -not [bool]$json.nested_residual_gpu_join_safety_receipt_validated -or
            [bool]$json.nested_residual_verify_reconstruction -or
            [int]$json.nested_residual_all_layer_first_layer -ne 3 -or
            [int]$json.nested_residual_all_layer_last_layer -ne 42 -or
            [int]$json.nested_residual_all_layer_count -ne 40 -or
            [UInt64]$json.nested_residual_base_pinned_entries -eq 0 -or
            [UInt64]$json.nested_residual_base_pinned_bytes -eq 0 -or
            [UInt64]$json.nested_residual_base_pinned_hits -eq 0 -or
            [UInt64]$json.nested_residual_base_pinned_h2d_bytes -eq 0 -or
            [UInt64]$json.nested_residual_base_pageable_entries -eq 0 -or
            [UInt64]$json.nested_residual_base_pageable_bytes -eq 0 -or
            [UInt64]$json.nested_residual_base_pageable_hits -eq 0 -or
            [UInt64]$json.nested_residual_base_pageable_h2d_bytes -eq 0 -or
            [UInt64]$json.nested_residual_storage_invariant_failures -ne 0 -or
            [UInt64]$json.nested_residual_cache_pinned_entries -ne 0 -or
            [UInt64]$json.nested_residual_cache_pinned_bytes -ne 0 -or
            [UInt64]$json.nested_residual_cache_pinned_hits -ne 0 -or
            [UInt64]$json.nested_residual_cache_pinned_h2d_bytes -ne 0 -or
            [UInt64]$json.nested_residual_cache_pageable_entries -eq 0 -or
            [UInt64]$json.nested_residual_cache_pageable_bytes -eq 0 -or
            [UInt64]$json.nested_residual_cache_pageable_hits -eq 0 -or
            [UInt64]$json.nested_residual_cache_pageable_h2d_bytes -eq 0 -or
            [int]$json.nested_residual_cache_layer_partitioned -ne 1 -or
            [UInt64]$json.nested_residual_cache_layer_slots_min -le 0 -or
            [UInt64]$json.nested_residual_cache_layer_slots_max -lt
                [UInt64]$json.nested_residual_cache_layer_slots_min -or
            [UInt64]$json.nested_residual_cache_layer_slots_max -gt
                ([UInt64]$json.nested_residual_cache_layer_slots_min +
                    [UInt64]1) -or
            [UInt64]$json.nested_residual_cache_pageable_invariant_failures -ne 0 -or
            [double]$json.nested_residual_expected_base_host_gib -ne
                $expectedBaseHostGiB -or
            [double]$json.nested_residual_expected_residual_cache_host_gib -ne
                $expectedResidualCacheHostGiB -or
            [double]$json.nested_residual_expected_host_allocation_gib -ne
                $expectedCandidateHostAllocationGiB -or
            [UInt64]$json.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_failures -ne 0) {
            throw "G128 candidate storage/runtime contract failed for $($Plan.tag)"
        }
    }
    return [pscustomobject]@{
        arm = $Plan.arm
        repeat_index = $Plan.repeat_index
        tag = $Plan.tag
        result_path = $Plan.result_path
        exact = $true
        uncontaminated = $true
        tokens_per_second = [double]$sample.tokens_per_second
        server_decode_mean_tokens_per_second =
            [double]$json.server_decode_mean_tokens_per_second
        server_prefill_ttft_mean_seconds =
            [double]$json.server_prefill_ttft_mean_seconds
        prefill_seconds = [double]$json.server_prefill_mean_seconds
        nested_residual_enabled = [bool]$json.nested_residual_enabled
        nested_residual_cache_layer_partitioned =
            [int]$json.nested_residual_cache_layer_partitioned
        nested_residual_cache_layer_slots_min =
            [UInt64]$json.nested_residual_cache_layer_slots_min
        nested_residual_cache_layer_slots_max =
            [UInt64]$json.nested_residual_cache_layer_slots_max
        contamination_peak = $runtimePeak
        dynamic_arena_gib = $expectedArenaGiB
        expected_host_allocation_gib =
            [double]$json.nested_residual_expected_host_allocation_gib
    }
}

function New-G128ArmSummary {
    param([object[]]$Rows)

    $e2e = [double[]]@($Rows | ForEach-Object { $_.tokens_per_second })
    $decode = [double[]]@(
        $Rows | ForEach-Object { $_.server_decode_mean_tokens_per_second })
    $ttft = [double[]]@(
        $Rows | ForEach-Object { $_.server_prefill_ttft_mean_seconds })
    $prefill = [double[]]@($Rows | ForEach-Object { $_.prefill_seconds })
    return [pscustomobject]@{
        count = $Rows.Count
        e2e_tps_mean = Get-G128Mean $e2e
        e2e_tps_median = Get-G128Median $e2e
        server_decode_tps_mean = Get-G128Mean $decode
        server_decode_tps_median = Get-G128Median $decode
        ttft_seconds_mean = Get-G128Mean $ttft
        ttft_seconds_median = Get-G128Median $ttft
        prefill_seconds_mean = Get-G128Mean $prefill
        prefill_seconds_median = Get-G128Median $prefill
    }
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G128 required script missing: $path"
    }
}
if ((Get-G128Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G128 prompt SHA-256 mismatch'
}

$currentBuild = $null
$g128SafetyContract = $null
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar,
            $G128SafetyReceipt)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G128 required file missing: $path"
        }
    }
    if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
        throw 'G128 sidecar size mismatch'
    }
    $observedSidecarSHA = (Get-FileHash -LiteralPath $sidecar `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($observedSidecarSHA -ine $sidecarSHA) {
        throw 'G128 sidecar SHA-256 mismatch'
    }
    $currentBuild = Get-G128CurrentBuildContract
    $g128SafetyContract = Assert-G128SafetyReceipt `
        -ReceiptPath $G128SafetyReceipt `
        -ExpectedReceiptSHA $ExpectedG128SafetyReceiptSHA256 `
        -CurrentBuild $currentBuild
}

$batchTag = if ($ResumeBatchTag) {
    $ResumeBatchTag
} else {
    $Tag + '_' + (New-G128Suffix)
}
$plans = @()
$position = 0
for ($i = 1; $i -le $Repeats; $i++) {
    foreach ($arm in @('control', 'candidate')) {
        $position += 1
        $plan = New-G128ChildPlan -Arm $arm -RepeatIndex $i `
            -BatchTag $batchTag
        $plan | Add-Member -NotePropertyName order_position `
            -NotePropertyValue $position
        $plans += $plan
    }
}

if ($WhatIf) {
    [pscustomobject]@{
        schema = 'g128_all_layer_nested_storage_ab_plan_v1'
        batch_tag = $batchTag
        resume_batch_tag = $ResumeBatchTag
        repeats_per_arm = $Repeats
        child_count = $plans.Count
        no_warmup = $true
        independent_processes = $true
        expected_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        g128_safety_receipt = $G128SafetyReceipt
        g128_safety_receipt_sha256 =
            $ExpectedG128SafetyReceiptSHA256.ToLowerInvariant()
        nested_residual_sidecar = $sidecar
        nested_residual_sidecar_bytes = $sidecarBytes
        nested_residual_sidecar_sha256 = $sidecarSHA
        nested_residual_payload_sha256 = $payloadSHA
        control_dynamic_arena_gib = $ControlDynamicArenaGiB
        candidate_dynamic_arena_gib = $CandidateDynamicArenaGiB
        nested_residual_base_pinned_gib = $NestedResidualBasePinnedGiB
        candidate_expected_base_host_gib = $expectedBaseHostGiB
        candidate_expected_residual_cache_host_gib =
            $expectedResidualCacheHostGiB
        candidate_expected_host_allocation_gib =
            $expectedCandidateHostAllocationGiB
        configuration_sha256 = Get-G128ConfigurationSHA
        children = @($plans | ForEach-Object {
            [pscustomobject]@{
                order_position = $_.order_position
                arm = $_.arm
                repeat_index = $_.repeat_index
                tag = $_.tag
                result_path = $_.result_path
                harness_arguments = @($_.harness_arguments)
            }
        })
    } | ConvertTo-Json -Depth 8
    return
}

$lockedBuild = Get-G128CurrentBuildContract
$lockedSafety = Assert-G128SafetyReceipt `
    -ReceiptPath $g128SafetyContract.receipt_path `
    -ExpectedReceiptSHA $g128SafetyContract.receipt_sha256 `
    -CurrentBuild $lockedBuild
if ($lockedSafety.result_sha256 -ine $g128SafetyContract.result_sha256 -or
    $lockedSafety.configuration_sha256 -ine
        $g128SafetyContract.configuration_sha256) {
    throw 'G128 safety/build contract changed before A/B planning'
}
$g128SafetyContract = $lockedSafety

foreach ($plan in $plans) { Invoke-G128Child -Plan $plan }
$rows = @()
foreach ($plan in $plans) { $rows += Read-G128ChildResult -Plan $plan }
$controlRows = @($rows | Where-Object { $_.arm -eq 'control' })
$candidateRows = @($rows | Where-Object { $_.arm -eq 'candidate' })
if ($controlRows.Count -lt 3 -or $candidateRows.Count -lt 3) {
    throw 'G128 did not collect n>=3 control and candidate rows'
}
$allValid = (@($rows | Where-Object {
            -not $_.exact -or -not $_.uncontaminated
        }).Count -eq 0)
if (-not $allValid) {
    throw 'G128 n>=3 aggregate invalid: exactness or contamination failed'
}

$controlSummary = New-G128ArmSummary -Rows $controlRows
$candidateSummary = New-G128ArmSummary -Rows $candidateRows
$resultPath = Join-Path $runs ('g7_' + $batchTag + '_result.json')
$result = [ordered]@{
    schema = 'g128_all_layer_nested_storage_ab_result_v1'
    batch_tag = $batchTag
    status = 'pass'
    claim_scope = 'n_ge_3_ab_only_no_claim_from_n1'
    n1_claims_forbidden = $true
    repeats_per_arm = $Repeats
    expected_content_sha256 = $expectedContentSHA
    prompt = $prompt
    prompt_sha256 = $promptSHA
    model = $model
    model_sha256 = $modelSHA
    sidecar = $sidecar
    sidecar_sha256 = $sidecarSHA
    sidecar_payload_sha256 = $payloadSHA
    control_dynamic_arena_gib = $ControlDynamicArenaGiB
    candidate_dynamic_arena_gib = $CandidateDynamicArenaGiB
    nested_residual_base_pinned_gib = $NestedResidualBasePinnedGiB
    candidate_expected_base_host_gib = $expectedBaseHostGiB
    candidate_expected_residual_cache_host_gib =
        $expectedResidualCacheHostGiB
    candidate_expected_host_allocation_gib =
        $expectedCandidateHostAllocationGiB
    g128_safety_receipt = $g128SafetyContract.receipt_path
    g128_safety_receipt_sha256 = $g128SafetyContract.receipt_sha256
    g128_safety_result = $g128SafetyContract.result_path
    g128_safety_result_sha256 = $g128SafetyContract.result_sha256
    g128_safety_configuration_sha256 =
        $g128SafetyContract.configuration_sha256
    exactness = [ordered]@{
        all_rows_exact = $true
        expected_content_sha256 = $expectedContentSHA
    }
    contamination = [ordered]@{
        all_rows_uncontaminated = $true
        max_runtime_contamination_consecutive_peak = 0
    }
    control = $controlSummary
    candidate = $candidateSummary
    rows = @($rows)
}
$result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ('[g128] PASS aggregate=' + $resultPath)
