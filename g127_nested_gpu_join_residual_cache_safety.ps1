# G127 fail-closed n=1 structural safety for GPU-join residual cache.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g127_nested_gpu_join_residual_cache_safety',
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root 'g7_measure.ps1'
$bootstrap = Join-Path $root 'g7_harness_bootstrap.ps1'
$runs = Join-Path $root 'g7_runs'
$exe = Join-Path $root 'build\Release\ds4_server.exe'
$buildManifest = Join-Path $root 'build\Release\g7_build_manifest.json'
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelSHA = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
$sidecar = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr'
$sidecarReceipt = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.receipt.json'
$sidecarBytes = [UInt64]3221226880
$sidecarSHA = '07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9'
$payloadSHA = '02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8'
$g125SafetyReceipt = Join-Path $runs `
    'g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json'
$g125SafetyReceiptSHA =
    'ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb'
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$expectedOutputReceipt = Join-Path $root `
    'tests\receipts\g123_equal_host_budget_expected_output.json'
$expectedOutputReceiptSHA =
    '4a9fa0d8d6dcee288a5b3e63903c3a978ddbce4a6e517aaf28c83f139aad793b'
$arenaGiB = 25.828125
$hostBudgetGiB = 30.0

function Get-G127Sha256Text {
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

function Get-G127ExpectedContentSHA {
    if (-not (Test-Path -LiteralPath $expectedOutputReceipt -PathType Leaf)) {
        throw 'G127 canonical expected-output receipt is missing'
    }
    $receiptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        $expectedOutputReceipt).Hash.ToLowerInvariant()
    if ($receiptHash -ne $expectedOutputReceiptSHA) {
        throw 'G127 canonical expected-output receipt SHA-256 mismatch'
    }
    try {
        $json = Get-Content -LiteralPath $expectedOutputReceipt -Raw |
            ConvertFrom-Json
    } catch {
        throw 'G127 canonical expected-output receipt is invalid JSON'
    }
    if ([string]$json.schema -ne 'ds4_g123_expected_output_receipt_v1' -or
        [string]$json.status -ne 'pass_n3_exact_full_open' -or
        [string]$json.claim_scope -ne 'expected_output_provenance_only' -or
        [string]$json.source_result_sha256 -ne
            '4af183d77f7f9b31c4808e5129261528bb397c68da4dd58677ad1df5ca4ab8cb' -or
        [string]$json.prompt -ne $prompt -or
        [string]$json.prompt_sha256 -ne $promptSHA -or
        [string]$json.model_sha256 -ne $modelSHA -or
        [string]$json.sidecar_sha256 -ne $sidecarSHA -or
        [string]$json.sidecar_payload_sha256 -ne $payloadSHA -or
        [string]$json.gate_kind -ne 'benchmark' -or
        [string]$json.router_semantics -ne 'full/open' -or
        [bool]$json.reap_or_static_mask -or
        [int]$json.max_tokens -ne 64 -or
        [int]$json.context -ne 256 -or
        [double]$json.host_budget_gib -ne $hostBudgetGiB -or
        [int]$json.control_count -ne 3 -or
        [int]$json.candidate_count -ne 3 -or
        -not [bool]$json.all_rows_exact -or
        -not [bool]$json.all_rows_uncontaminated -or
        [string]$json.expected_content_sha256 -notmatch
            '^[0-9a-fA-F]{64}$') {
        throw 'G127 canonical expected-output receipt contract mismatch'
    }
    return ([string]$json.expected_content_sha256).ToLowerInvariant()
}

function Get-G127ConfigurationSHA {
    param([Parameter(Mandatory=$true)][string]$ExpectedContentSHA)

    $contract = @(
        'schema=g127_nested_gpu_join_residual_cache_config_v1',
        "model_sha256=$modelSHA",
        "sidecar_sha256=$sidecarSHA",
        "sidecar_payload_sha256=$payloadSHA",
        "prompt_sha256=$promptSHA",
        "expected_content_sha256=$ExpectedContentSHA",
        'temperature=0',
        'nothink=1',
        'max_tokens=64',
        'context=256',
        'dynamic_arena_gib=25.828125',
        'expert_cache_n=320',
        'nested_residual_cache_experts=64',
        'nested_residual_gpu_cache=1',
        'nested_residual_gpu_join=1',
        'nested_residual_gpu_join_residual_cache=1',
        'nested_residual_verify_reconstruction=1',
        'router=full/open',
        'reap_or_static_mask=0',
        'host_budget_gib=30.0'
    ) -join "`n"
    return Get-G127Sha256Text -Text ($contract + "`n")
}

function Assert-G127MachineQuiescence {
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
        throw 'G127 safety machine-quiescence gate failed'
    }
    return [pscustomobject]@{
        ready_to_launch = $true
        skipped = $false
        preflight_failures = 0
        runtime_contamination_consecutive_peak = 0
    }
}

function Assert-G127SafetyResult {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$ExpectedContentSHA,
        [Parameter(Mandatory=$true)][string]$StderrPath
    )

    $samples = @($Result.results)
    if ([string]$Result.gate_kind -ne 'structural-safety' -or
        [bool]$Result.quality_eligible -or
        [bool]$Result.sota_eligible -or
        [int]$Result.repeats -ne 1 -or
        $samples.Count -ne 1 -or
        [bool]$Result.warmup -or
        [int]$Result.server_exit_code -ne 0 -or
        -not [bool]$Result.outputs_identical -or
        [int]$Result.requested_max_tokens -ne 64 -or
        [int]$Result.context_requested -ne 256 -or
        [double]$Result.dynamic_arena_gib_requested -ne $arenaGiB -or
        [int]$Result.expert_cache_requested -ne 320 -or
        [string]$Result.prompt_sha256 -ne $promptSHA -or
        [string]$Result.expected_content_sha256 -ne $ExpectedContentSHA -or
        [string]$samples[0].content_sha256 -ne $ExpectedContentSHA) {
        throw 'G127 safety request/exact-output contract failed'
    }
    if ([string]$Result.model_sha256 -ine $modelSHA -or
        [string]$Result.nested_residual_sidecar_sha256 -ine $sidecarSHA -or
        [string]$Result.nested_residual_expected_source_sha256 -ine
            $modelSHA -or
        [string]$Result.nested_residual_expected_payload_sha256 -ine
            $payloadSHA) {
        throw 'G127 safety model/sidecar provenance failed'
    }
    if (-not [bool]$Result.compose_prefill_mass_open_router_requested -or
        [int]$Result.expert_tiering.compose_router_open -ne 1 -or
        [string]$Result.prefill_mass_wrap_router -ne 'unbiased' -or
        [string]$Result.prefill_mass_wrap_mask -ne 'request-scoped-open' -or
        [string]$Result.prefill_mass_compose_mask_semantics -ne
            'request-scoped-open' -or
        [string]$Result.reap_mask_file_requested -or
        [bool]$Result.embedded_bake_mask_observed) {
        throw 'G127 safety full/open routing contract failed'
    }
    if (-not [bool]$Result.nested_residual_verify_reconstruction -or
        -not [bool]$Result.nested_residual_gpu_cache_requested -or
        -not [bool]$Result.nested_residual_gpu_join_requested -or
        -not [bool]$Result.nested_residual_gpu_join_observed -or
        [UInt64]$Result.nested_residual_gpu_join_calls -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_verify_calls -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_verify_bytes -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_failures -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [UInt64]$Result.nested_residual_mismatches -ne 0 -or
        [UInt64]$Result.nested_residual_failures -ne 0 -or
        [UInt64]$Result.nested_residual_vram_failures -ne 0) {
        throw 'G127 safety exact reconstruction/GPU-join contract failed'
    }
    if (-not [bool]$Result.nested_residual_gpu_join_residual_cache_requested -or
        -not [bool]$Result.nested_residual_gpu_join_residual_cache_observed -or
        [int]$Result.nested_residual_gpu_join_residual_cache_enabled_runtime -ne 1 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_hits -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_misses -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_capacity -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_entries -gt
            [UInt64]$Result.nested_residual_gpu_join_residual_cache_capacity -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_pread_bytes_avoided -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_cached_join_calls -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_cache_invariant_failures -ne 0) {
        throw 'G127 safety residual-cache counter contract failed'
    }
    if ([UInt64]$Result.moe_overlapped_io_fallbacks -ne 0) {
        throw 'G127 safety selected-load fallback counter is nonzero'
    }
    if (-not (Test-Path -LiteralPath $StderrPath -PathType Leaf)) {
        throw 'G127 safety stderr log is missing'
    }
    $stderrText = Get-Content -LiteralPath $StderrPath -Raw
    $fallbackMarkers = [regex]::Matches(
        $stderrText,
        '(?im)(nested residual[^\r\n]*fallback|selected-load fallback requested)').Count
    if ($fallbackMarkers -ne 0) {
        throw 'G127 safety fallback marker observed'
    }
    return [pscustomobject]@{
        fallback_markers = 0
        machine_quiescence = Assert-G127MachineQuiescence -Result $Result
    }
}

foreach ($path in @($harness, $bootstrap, $expectedOutputReceipt)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G127 safety required script/receipt missing: $path"
    }
}
if ((Get-G127Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G127 safety prompt SHA-256 mismatch'
}

$expectedContentSHA = Get-G127ExpectedContentSHA
$configurationSHA = Get-G127ConfigurationSHA `
    -ExpectedContentSHA $expectedContentSHA
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
    '-Repeats', '1',
    '-Context', '256',
    '-BudgetGB', '2',
    '-ReserveMB', '1024',
    '-DynamicArenaGiB', ([string]$arenaGiB),
    '-ArenaWrapTrustWorkerChecksum',
    '-ArenaWrapSourceParts',
    '-ArenaWrapUnlockSourceRanges',
    '-ArenaWrapUnlockWaveGiB', '4',
    '-DisableQ8F16Cache',
    '-EmbedRowStaging',
    '-ReapPrefetchThreads', '8',
    '-PrefillMassWrap',
    '-ComposePrefillMassTiering',
    '-ComposePrefillMassOpenRouter',
    '-ForceOpenRouter',
    '-ComposePrefillMassReserveSlots', '32',
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
    '-NestedResidualCacheExperts', '64',
    '-NestedResidualStructuralN1',
    '-NestedResidualVerifyReconstruction',
    '-NestedResidualGpuCache',
    '-NestedResidualGpuJoin',
    '-NestedResidualGpuJoinResidualCache',
    '-RuntimeMinimumAvailableGiB', '1',
    '-RuntimeMaximumDiskQueueLength', '8',
    '-RuntimeContaminationSamples', '3',
    '-QuiescenceCooldownSec', '10',
    '-TimeoutSec', [string]$TimeoutSec,
    '-Tag', $childTag
)
$bootstrapArguments = @{
    HarnessPath = $harness
    RepoRoot = $root
    HarnessArguments = $arguments
}

if ($WhatIf) {
    [pscustomobject]@{
        schema = 'g127_nested_gpu_join_residual_cache_safety_plan_v1'
        status = 'whatif_no_runtime'
        tag = $childTag
        expected_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        configuration_sha256 = $configurationSHA
        g125_prerequisite_receipt = $g125SafetyReceipt
        g125_prerequisite_receipt_sha256 = $g125SafetyReceiptSHA
        n = 1
        claim_scope =
            'structural_safety_only_no_sota_no_quality_verdict'
        harness_arguments = @($arguments)
    } | ConvertTo-Json -Depth 8
    $bootstrapArguments.WhatIf = $true
    & $bootstrap @bootstrapArguments
    exit 0
}

foreach ($path in @($model, "$model.receipt.json", $sidecar,
        $sidecarReceipt, $g125SafetyReceipt, $exe, $buildManifest)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G127 safety required file missing: $path"
    }
}
if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
    throw 'G127 safety sidecar size mismatch'
}
$observedG125SHA = (Get-FileHash -LiteralPath $g125SafetyReceipt `
    -Algorithm SHA256).Hash.ToLowerInvariant()
if ($observedG125SHA -ine $g125SafetyReceiptSHA) {
    throw 'G127 historical G125 safety receipt SHA mismatch'
}

$modelLock = $null
$sidecarLock = $null
$g125Lock = $null
try {
    $modelLock = [IO.File]::Open(
        $model, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sidecarLock = [IO.File]::Open(
        $sidecar, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $g125Lock = [IO.File]::Open(
        $g125SafetyReceipt, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)

    & $bootstrap @bootstrapArguments
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "G127 safety child failed with exit code $LASTEXITCODE"
    }

    $resultPath = Join-Path $runs ('g7_' + $childTag + '_result.json')
    $stderrPath = Join-Path $runs ('g7_' + $childTag + '_stderr.log')
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G127 safety result missing: $resultPath"
    }
    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
    $assertion = Assert-G127SafetyResult -Result $result `
        -ExpectedContentSHA $expectedContentSHA -StderrPath $stderrPath

    $resultSHA = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $receipt = [ordered]@{
        schema = 'ds4_g127_nested_gpu_join_residual_cache_safety_v1'
        status = 'pass_structural_n1_no_performance_or_quality_verdict'
        claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
        tag = $childTag
        result_path = $resultPath
        result_sha256 = $resultSHA
        exact_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        configuration_sha256 = $configurationSHA
        model = [ordered]@{
            path = $model
            sha256 = $modelSHA
        }
        sidecar = [ordered]@{
            path = $sidecar
            bytes = $sidecarBytes
            sha256 = $sidecarSHA
            source_sha256 = $modelSHA
            payload_sha256 = $payloadSHA
        }
        g125_prerequisite = [ordered]@{
            receipt_path = $g125SafetyReceipt
            receipt_sha256 = $g125SafetyReceiptSHA
        }
        build = [ordered]@{
            executable_path = [string]$result.executable
            executable_sha256 = [string]$result.executable_sha256
            build_manifest_path = [string]$result.build_manifest_path
            build_manifest_sha256 = [string]$result.build_manifest_sha256
            build_manifest_input_fingerprint_sha256 =
                [string]$result.build_manifest_input_fingerprint_sha256
            build_manifest_head = [string]$result.build_manifest_head
            ds4_cuda_sha256 = [string]$result.ds4_cuda_sha256
            harness_path = $harness
            harness_sha256 = [string]$result.harness_sha256
            bootstrap_path = $bootstrap
            bootstrap_sha256 = (Get-FileHash -LiteralPath $bootstrap `
                -Algorithm SHA256).Hash.ToLowerInvariant()
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
        residual_cache = [ordered]@{
            enabled =
                [int]$result.nested_residual_gpu_join_residual_cache_enabled_runtime
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
            pread_bytes =
                [UInt64]$result.nested_residual_gpu_join_residual_cache_pread_bytes
            pread_bytes_avoided =
                [UInt64]$result.nested_residual_gpu_join_residual_cache_pread_bytes_avoided
            h2d_bytes =
                [UInt64]$result.nested_residual_gpu_join_residual_cache_h2d_bytes
            cached_join_calls =
                [UInt64]$result.nested_residual_gpu_join_residual_cache_cached_join_calls
            invariant_failures =
                [UInt64]$result.nested_residual_gpu_join_residual_cache_invariant_failures
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
            fallback_markers = [int]$assertion.fallback_markers
        }
        machine_quiescence = $assertion.machine_quiescence
        routing_contract =
            'full/open routing preserved; no REAP/static/closed masks'
    }
    $receiptPath = Join-Path $runs ('g7_' + $childTag + '_receipt.json')
    if (Test-Path -LiteralPath $receiptPath) {
        throw "G127 immutable safety receipt already exists: $receiptPath"
    }
    $receipt | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $receiptPath -Encoding UTF8
    $receiptSHA = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    Write-Output ('G127_SAFETY_RECEIPT=' + $receiptPath)
    Write-Output ('G127_SAFETY_RECEIPT_SHA256=' + $receiptSHA)
} finally {
    if ($null -ne $g125Lock) { $g125Lock.Dispose() }
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}
