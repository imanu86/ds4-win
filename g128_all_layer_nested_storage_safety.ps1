# G128 fail-closed n=1 structural safety for all-layer nested storage.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g128_all_layer_nested_storage_safety',
    [Parameter(Mandatory=$true)][string]$NestedResidualSidecar,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedNestedResidualSidecarSHA256,
    [Parameter(Mandatory=$true)]
    [UInt64]$ExpectedNestedResidualSidecarBytes,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedNestedResidualPayloadSHA256,
    [ValidateRange(0.25, 12.0)][double]$DynamicArenaGiB = 2.0,
    [ValidateRange(0.25, 30.0)]
    [double]$NestedResidualBasePinnedGiB = 28.0,
    [ValidateRange(40, 4096)][int]$NestedResidualCacheExperts = 320,
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root 'g7_measure.ps1'
$bootstrap = Join-Path $root 'g7_harness_bootstrap.ps1'
$runs = Join-Path $root 'g7_runs'
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelSHA = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
$sidecar = $NestedResidualSidecar
$sidecarBytes = $ExpectedNestedResidualSidecarBytes
$sidecarSHA = $ExpectedNestedResidualSidecarSHA256.ToLowerInvariant()
$payloadSHA = $ExpectedNestedResidualPayloadSHA256.ToLowerInvariant()
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$expectedContentSHA = 'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510'
$arenaGiB = $DynamicArenaGiB
$expectedBaseHostGiB = 37.5
$expectedResidualCacheHostGiB =
    ([double]$NestedResidualCacheExperts * 3.0) / 1024.0
$expectedHostAllocationGiB =
    $expectedBaseHostGiB + $expectedResidualCacheHostGiB + $arenaGiB
$expectedOutputReceiptPath = Join-Path $root `
    'tests\receipts\g123_equal_host_budget_expected_output.json'
$expectedOutputReceiptSHA =
    '4a9fa0d8d6dcee288a5b3e63903c3a978ddbce4a6e517aaf28c83f139aad793b'

if ($ExpectedNestedResidualSidecarBytes -eq 0) {
    throw 'G128 expected nested residual sidecar bytes must be positive'
}
if (($NestedResidualBasePinnedGiB + $arenaGiB) -gt 30.0) {
    throw 'G128 nested base pinned GiB plus dynamic arena GiB must be <= 30'
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
        "dynamic_arena_gib=$arenaGiB",
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
    ) -join "`n"
    return Get-G128Sha256Text -Text ($contract + "`n")
}

function Get-G128BuildContract {
    $exe = Join-Path $root 'build\Release\ds4_server.exe'
    $manifestPath = Join-Path $root 'build\Release\g7_build_manifest.json'
    foreach ($path in @($exe, $manifestPath, $harness, $bootstrap)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G128 current-build input missing: $path"
        }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw |
        ConvertFrom-Json
    $exeSHA = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ([string]$manifest.schema -ne 'g7_native_windows_build_manifest_v1' -or
        [string]$manifest.executable_sha256 -ine $exeSHA) {
        throw 'G128 current build manifest contract mismatch'
    }
    return [pscustomobject]@{
        executable_path = $exe
        executable_sha256 = $exeSHA
        build_manifest_path = $manifestPath
        build_manifest_sha256 =
            (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).
                Hash.ToLowerInvariant()
        build_manifest_input_fingerprint_sha256 =
            ([string]$manifest.input_fingerprint_sha256).ToLowerInvariant()
        harness_path = $harness
        harness_sha256 =
            (Get-FileHash -LiteralPath $harness -Algorithm SHA256).
                Hash.ToLowerInvariant()
        bootstrap_path = $bootstrap
        bootstrap_sha256 =
            (Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256).
                Hash.ToLowerInvariant()
    }
}

function Get-G128U64 {
    param([object]$Object, [string[]]$Names, [string]$Label)

    foreach ($name in $Names) {
        if ($null -ne $Object.PSObject.Properties[$name]) {
            return [UInt64]$Object.$name
        }
    }
    throw "G128 required counter missing: $Label"
}

function Assert-G128MachineQuiescence {
    param([Parameter(Mandatory=$true)][object]$Result)

    $preflight = $Result.system_quiescence_preflight
    $failures = @()
    if ($null -ne $preflight -and $null -ne $preflight.failures) {
        $failures = @($preflight.failures)
    }
    $runtimePeak = 0
    if ($null -ne $Result.runtime_telemetry -and
        $null -ne $Result.runtime_telemetry.contamination_consecutive_peak) {
        $runtimePeak =
            [int]$Result.runtime_telemetry.contamination_consecutive_peak
    }
    if ($null -eq $preflight -or
        -not [bool]$preflight.ready_to_launch -or
        [bool]$preflight.skipped -or
        $failures.Count -ne 0 -or
        $runtimePeak -ne 0) {
        throw 'G128 safety machine-quiescence gate failed'
    }
    return [pscustomobject]@{
        ready_to_launch = $true
        skipped = $false
        preflight_failures = 0
        runtime_contamination_consecutive_peak = 0
    }
}

function Assert-G128SafetyResult {
    param([Parameter(Mandatory=$true)][object]$Result)

    $samples = @($Result.results)
    if ([string]$Result.gate_kind -ne 'structural-safety' -or
        [int]$Result.repeats -ne 1 -or
        $samples.Count -ne 1 -or
        [bool]$Result.warmup -or
        [int]$Result.server_exit_code -ne 0 -or
        [bool]$Result.quality_eligible -or
        [bool]$Result.sota_eligible -or
        [string]$samples[0].content_sha256 -ine $expectedContentSHA -or
        [string]$Result.expected_content_sha256 -ine $expectedContentSHA) {
        throw 'G128 safety n=1 exact-output contract failed'
    }
    if (-not [bool]$Result.compose_prefill_mass_open_router_requested -or
        [int]$Result.expert_tiering.compose_router_open -ne 1 -or
        [string]$Result.reap_mask_file_requested -or
        [bool]$Result.embedded_bake_mask_observed) {
        throw 'G128 safety full/open routing contract failed'
    }
    if (-not [bool]$Result.nested_residual_verify_reconstruction -or
        -not [bool]$Result.nested_residual_gpu_cache_requested -or
        -not [bool]$Result.nested_residual_gpu_join_requested -or
        -not [bool]$Result.nested_residual_gpu_join_observed -or
        [UInt64]$Result.nested_residual_gpu_join_verify_calls -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_verify_bytes -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$Result.nested_residual_mismatches -ne 0 -or
        [UInt64]$Result.nested_residual_failures -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_failures -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [UInt64]$Result.moe_overlapped_io_fallbacks -ne 0) {
        throw 'G128 safety exact reconstruction/GPU-join contract failed'
    }
    if ([int]$Result.nested_residual_all_layer_first_layer -ne 3 -or
        [int]$Result.nested_residual_all_layer_last_layer -ne 42 -or
        [int]$Result.nested_residual_all_layer_count -ne 40 -or
        -not [bool]$Result.nested_residual_pageable_base_requested -or
        -not [bool]$Result.nested_residual_cache_pageable_requested) {
        throw 'G128 safety all-layer/pageable coverage contract failed'
    }
    if ([string]$Result.model_sha256 -ine $modelSHA -or
        [string]$Result.prompt_sha256 -ine $promptSHA -or
        [string]$Result.nested_residual_sidecar -ine $sidecar -or
        [UInt64]$Result.nested_residual_sidecar_bytes -ne $sidecarBytes -or
        [string]$Result.nested_residual_sidecar_sha256 -ine $sidecarSHA -or
        [string]$Result.nested_residual_expected_source_sha256 -ine
            $modelSHA -or
        [string]$Result.nested_residual_expected_payload_sha256 -ine
            $payloadSHA -or
        [double]$Result.dynamic_arena_gib_requested -ne $arenaGiB -or
        [double]$Result.nested_residual_base_pinned_gib_requested -ne
            $NestedResidualBasePinnedGiB -or
        [double]$Result.nested_residual_expected_base_host_gib -ne
            $expectedBaseHostGiB -or
        [double]$Result.nested_residual_expected_residual_cache_host_gib -ne
            $expectedResidualCacheHostGiB -or
        [double]$Result.nested_residual_expected_host_allocation_gib -ne
            $expectedHostAllocationGiB) {
        throw 'G128 safety model/sidecar/memory provenance contract failed'
    }
    $baseInvariant = Get-G128U64 $Result @(
        'nested_residual_storage_invariant_failures') 'base invariant'
    $residualInvariant = Get-G128U64 $Result @(
        'nested_residual_gpu_join_residual_cache_invariant_failures') `
        'residual-cache invariant'
    $pageableResidualInvariant = Get-G128U64 $Result @(
        'nested_residual_cache_pageable_invariant_failures') `
        'pageable residual-cache invariant'
    $partitioned = Get-G128U64 $Result @(
        'nested_residual_cache_layer_partitioned') `
        'residual-cache partitioned'
    $layerSlotsMin = Get-G128U64 $Result @(
        'nested_residual_cache_layer_slots_min') `
        'residual-cache layer slots min'
    $layerSlotsMax = Get-G128U64 $Result @(
        'nested_residual_cache_layer_slots_max') `
        'residual-cache layer slots max'
    if ($baseInvariant -ne 0 -or $residualInvariant -ne 0 -or
        $pageableResidualInvariant -ne 0 -or
        $partitioned -ne 1 -or $layerSlotsMin -le 0 -or
        $layerSlotsMax -lt $layerSlotsMin -or
        $layerSlotsMax -gt ($layerSlotsMin + [UInt64]1)) {
        throw 'G128 safety storage invariant/partition contract failed'
    }
    return [pscustomobject]@{
        machine_quiescence = Assert-G128MachineQuiescence -Result $Result
    }
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G128 safety required script missing: $path"
    }
}
if ((Get-G128Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G128 safety prompt SHA-256 mismatch'
}
if (-not (Test-Path -LiteralPath $expectedOutputReceiptPath -PathType Leaf) -or
    (Get-FileHash -LiteralPath $expectedOutputReceiptPath -Algorithm SHA256).
        Hash.ToLowerInvariant() -ne $expectedOutputReceiptSHA) {
    throw 'G128 expected-output provenance receipt mismatch'
}
$expectedOutputReceipt = Get-Content -LiteralPath $expectedOutputReceiptPath `
    -Raw | ConvertFrom-Json
if ([string]$expectedOutputReceipt.schema -ne
        'ds4_g123_expected_output_receipt_v1' -or
    [string]$expectedOutputReceipt.status -ne 'pass_n3_exact_full_open' -or
    [string]$expectedOutputReceipt.prompt_sha256 -ine $promptSHA -or
    [string]$expectedOutputReceipt.expected_content_sha256 -ine
        $expectedContentSHA -or
    [string]$expectedOutputReceipt.model_sha256 -ine $modelSHA -or
    [int]$expectedOutputReceipt.control_count -lt 3 -or
    [int]$expectedOutputReceipt.candidate_count -lt 3 -or
    -not [bool]$expectedOutputReceipt.all_rows_exact -or
    -not [bool]$expectedOutputReceipt.all_rows_uncontaminated) {
    throw 'G128 expected-output provenance contract failed'
}
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G128 safety required file missing: $path"
        }
    }
    $sidecar = (Resolve-Path -LiteralPath $sidecar).Path
    if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne
        $sidecarBytes) {
        throw 'G128 safety sidecar size mismatch'
    }
}

$configurationSHA = Get-G128ConfigurationSHA
$suffix = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
    '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$childTag = $Tag + '_' + $suffix
$arguments = @(
    '-GateKind', 'structural-safety',
    '-ModelPath', $model,
    '-ExpectedModelSHA256', $modelSHA,
    '-ReuseVerifiedModelReceipt',
    '-Prompt', $prompt,
    '-ExpectedContentSHA256', $expectedContentSHA,
    '-MaxTokens', '64',
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
    '-DynamicArenaGiB', ([string]$arenaGiB),
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
    '-NestedResidualSidecar', $sidecar,
    '-ExpectedNestedResidualSidecarSHA256', $sidecarSHA,
    '-ExpectedNestedResidualSourceSHA256', $modelSHA,
    '-ExpectedNestedResidualPayloadSHA256', $payloadSHA,
    '-NestedResidualStructuralN1',
    '-NestedResidualVerifyReconstruction',
    '-NestedResidualGpuCache',
    '-NestedResidualGpuJoin',
    '-NestedResidualGpuJoinResidualCache',
    '-NestedResidualPageableBase',
    '-NestedResidualBasePinnedGiB', ([string]$NestedResidualBasePinnedGiB),
    '-NestedResidualCachePageable',
    '-NestedResidualCacheExperts', ([string]$NestedResidualCacheExperts),
    '-RuntimeMinimumAvailableGiB', '2',
    '-RuntimeHardMinimumAvailableGiB', '1',
    '-RuntimeMaximumDiskQueueLength', '8',
    '-RuntimeContaminationSamples', '3',
    '-QuiescenceCooldownSec', '10',
    '-TimeoutSec', [string]$TimeoutSec,
    '-Tag', $childTag
)

if ($WhatIf) {
    [pscustomobject]@{
        schema = 'g128_all_layer_nested_storage_safety_plan_v1'
        status = 'whatif_no_runtime'
        tag = $childTag
        n = 1
        claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
        receipt_schema = 'ds4_g128_all_layer_nested_storage_safety_v1'
        expected_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        configuration_sha256 = $configurationSHA
        expected_output_provenance = [ordered]@{
            path = $expectedOutputReceiptPath
            sha256 = $expectedOutputReceiptSHA
        }
        all_layer = [ordered]@{ first = 3; last = 42; count = 40 }
        base_storage = [ordered]@{
            pageable_enabled = $true
            pinned_gib_requested = [double]$NestedResidualBasePinnedGiB
            expected_base_host_gib = $expectedBaseHostGiB
            expected_total_host_allocation_gib = $expectedHostAllocationGiB
        }
        residual_cache = [ordered]@{
            pageable_enabled = $true
            experts = $NestedResidualCacheExperts
            partitioned = 1
        }
        harness_arguments = @($arguments)
    } | ConvertTo-Json -Depth 8
    exit 0
}

$build = Get-G128BuildContract
$bootstrapArguments = @{
    HarnessPath = $harness
    RepoRoot = $root
    HarnessArguments = $arguments
}
& $bootstrap @bootstrapArguments
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
    throw "G128 safety child failed with exit code $LASTEXITCODE"
}

$resultPath = Join-Path $runs ('g7_' + $childTag + '_result.json')
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "G128 safety result missing: $resultPath"
}
$result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
$assertion = Assert-G128SafetyResult -Result $result
$resultSHA = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).
    Hash.ToLowerInvariant()

$receipt = [ordered]@{
    schema = 'ds4_g128_all_layer_nested_storage_safety_v1'
    status = 'pass_structural_n1_no_performance_or_quality_verdict'
    claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
    tag = $childTag
    result_path = $resultPath
    result_sha256 = $resultSHA
    exact_content_sha256 = $expectedContentSHA
    prompt_sha256 = $promptSHA
    configuration_sha256 = $configurationSHA
    expected_output_provenance = [ordered]@{
        path = $expectedOutputReceiptPath
        sha256 = $expectedOutputReceiptSHA
        source_result_sha256 =
            [string]$expectedOutputReceipt.source_result_sha256
    }
    model = [ordered]@{ path = $model; sha256 = $modelSHA }
    sidecar = [ordered]@{
        path = $sidecar
        bytes = $sidecarBytes
        sha256 = $sidecarSHA
        source_sha256 = $modelSHA
        payload_sha256 = $payloadSHA
    }
    build = $build
    all_layer = [ordered]@{
        first = [int]$result.nested_residual_all_layer_first_layer
        last = [int]$result.nested_residual_all_layer_last_layer
        count = [int]$result.nested_residual_all_layer_count
    }
    base_storage = [ordered]@{
        pageable_enabled = $true
        pinned_gib_requested = [double]$NestedResidualBasePinnedGiB
        dynamic_arena_gib = $arenaGiB
        expected_base_host_gib = $expectedBaseHostGiB
        expected_residual_cache_host_gib =
            $expectedResidualCacheHostGiB
        expected_total_host_allocation_gib = $expectedHostAllocationGiB
        pinned_entries = Get-G128U64 $result @(
            'nested_residual_base_pinned_entries') 'base pinned entries'
        pinned_bytes = Get-G128U64 $result @(
            'nested_residual_base_pinned_bytes') 'base pinned bytes'
        pinned_hits = Get-G128U64 $result @(
            'nested_residual_base_pinned_hits') 'base pinned hits'
        pinned_h2d_bytes = Get-G128U64 $result @(
            'nested_residual_base_pinned_h2d_bytes') `
            'base pinned h2d'
        pageable_entries = Get-G128U64 $result @(
            'nested_residual_base_pageable_entries') `
            'base pageable entries'
        pageable_bytes = Get-G128U64 $result @(
            'nested_residual_base_pageable_bytes') `
            'base pageable bytes'
        pageable_hits = Get-G128U64 $result @(
            'nested_residual_base_pageable_hits') `
            'base pageable hits'
        pageable_h2d_bytes = Get-G128U64 $result @(
            'nested_residual_base_pageable_h2d_bytes') `
            'base pageable h2d'
        invariant_failures = Get-G128U64 $result @(
            'nested_residual_storage_invariant_failures') `
            'base invariant failures'
    }
    residual_cache = [ordered]@{
        enabled =
            [int]$result.nested_residual_gpu_join_residual_cache_enabled_runtime
        pageable_enabled = $true
        hits =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_hits
        misses =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_misses
        evictions =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_evictions
        entries =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_entries
        capacity =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_capacity
        pinned_entries = Get-G128U64 $result @(
            'nested_residual_cache_pinned_entries') `
            'residual pinned entries'
        pinned_bytes = Get-G128U64 $result @(
            'nested_residual_cache_pinned_bytes') `
            'residual pinned bytes'
        pinned_hits = Get-G128U64 $result @(
            'nested_residual_cache_pinned_hits') `
            'residual pinned hits'
        pinned_h2d_bytes = Get-G128U64 $result @(
            'nested_residual_cache_pinned_h2d_bytes') `
            'residual pinned h2d'
        pageable_entries = Get-G128U64 $result @(
            'nested_residual_cache_pageable_entries') `
            'residual pageable entries'
        pageable_bytes = Get-G128U64 $result @(
            'nested_residual_cache_pageable_bytes') `
            'residual pageable bytes'
        pageable_hits = Get-G128U64 $result @(
            'nested_residual_cache_pageable_hits') `
            'residual pageable hits'
        pageable_h2d_bytes = Get-G128U64 $result @(
            'nested_residual_cache_pageable_h2d_bytes') `
            'residual pageable h2d'
        pread_bytes =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_pread_bytes
        pread_bytes_avoided =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_pread_bytes_avoided
        h2d_bytes =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_h2d_bytes
        cached_join_calls =
            [UInt64]$result.nested_residual_gpu_join_residual_cache_cached_join_calls
        invariant_failures = Get-G128U64 $result @(
            'nested_residual_gpu_join_residual_cache_invariant_failures') `
            'residual invariant failures'
        pageable_invariant_failures = Get-G128U64 $result @(
            'nested_residual_cache_pageable_invariant_failures') `
            'pageable residual invariant failures'
        partitioned = Get-G128U64 $result @(
            'nested_residual_cache_layer_partitioned') `
            'residual cache partitioned'
        layer_slots_min = Get-G128U64 $result @(
            'nested_residual_cache_layer_slots_min') `
            'residual layer slots min'
        layer_slots_max = Get-G128U64 $result @(
            'nested_residual_cache_layer_slots_max') `
            'residual layer slots max'
    }
    gpu_join = [ordered]@{
        requested = [bool]$result.nested_residual_gpu_join_requested
        observed = [bool]$result.nested_residual_gpu_join_observed
        calls = [UInt64]$result.nested_residual_gpu_join_calls
        blocks = [UInt64]$result.nested_residual_gpu_join_blocks
        base_h2d_bytes =
            [UInt64]$result.nested_residual_gpu_join_base_h2d_bytes
        residual_h2d_bytes =
            [UInt64]$result.nested_residual_gpu_join_residual_h2d_bytes
        native_h2d_bytes =
            [UInt64]$result.nested_residual_gpu_join_native_h2d_bytes
        verify_calls =
            [UInt64]$result.nested_residual_gpu_join_verify_calls
        verify_bytes =
            [UInt64]$result.nested_residual_gpu_join_verify_bytes
        verify_mismatches =
            [UInt64]$result.nested_residual_gpu_join_verify_mismatches
        failures = [UInt64]$result.nested_residual_gpu_join_failures
        cpu_reconstruct_calls =
            [UInt64]$result.nested_residual_gpu_join_cpu_reconstruct_calls
    }
    gpu_cache = [ordered]@{
        requested = [bool]$result.nested_residual_gpu_cache_requested
        observed = [bool]$result.nested_residual_vram_runtime_observed
        route_calls = [UInt64]$result.nested_residual_vram_route_calls
        hits = [UInt64]$result.nested_residual_vram_hits
        misses = [UInt64]$result.nested_residual_vram_misses
        host_fills = [UInt64]$result.nested_residual_vram_host_fills
        host_bytes = [UInt64]$result.nested_residual_vram_host_bytes
        h2d_bytes = [UInt64]$result.nested_residual_vram_h2d_bytes
        failures = [UInt64]$result.nested_residual_vram_failures
    }
    exactness = [ordered]@{
        reconstruction_verify = $true
        verify_calls =
            [UInt64]$result.nested_residual_gpu_join_verify_calls
        verify_bytes =
            [UInt64]$result.nested_residual_gpu_join_verify_bytes
        verify_mismatches =
            [UInt64]$result.nested_residual_gpu_join_verify_mismatches
        nested_mismatches = [UInt64]$result.nested_residual_mismatches
        nested_failures = [UInt64]$result.nested_residual_failures
        gpu_join_failures =
            [UInt64]$result.nested_residual_gpu_join_failures
        cpu_reconstruct_calls =
            [UInt64]$result.nested_residual_gpu_join_cpu_reconstruct_calls
        native_h2d_bytes =
            [UInt64]$result.nested_residual_gpu_join_native_h2d_bytes
        selected_load_fallbacks =
            [UInt64]$result.moe_overlapped_io_fallbacks
        fallback_markers = 0
    }
    machine_quiescence = $assertion.machine_quiescence
    routing_contract =
        'full/open routing preserved; no REAP/static/closed masks'
}
$receiptPath = Join-Path $runs ('g7_' + $childTag + '_receipt.json')
if (Test-Path -LiteralPath $receiptPath) {
    throw "G128 immutable safety receipt already exists: $receiptPath"
}
$receipt | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $receiptPath -Encoding UTF8
$receiptSHA = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).
    Hash.ToLowerInvariant()
Write-Output ('G128_SAFETY_RECEIPT=' + $receiptPath)
Write-Output ('G128_SAFETY_RECEIPT_SHA256=' + $receiptSHA)
