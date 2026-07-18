# G125 fail-closed n=1 structural safety for nested residual GPU join.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g125_nested_gpu_join_safety',
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
$sidecar = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr'
$sidecarReceipt = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.receipt.json'
$sidecarSHA = '07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9'
$payloadSHA = '02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8'
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$expectedOutputReceipt = Join-Path $root `
    'tests\receipts\g123_equal_host_budget_expected_output.json'
$expectedOutputReceiptSHA =
    '4a9fa0d8d6dcee288a5b3e63903c3a978ddbce4a6e517aaf28c83f139aad793b'

function Get-G125Sha256Text {
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

function Get-G125ExpectedContentSHA {
    if (-not (Test-Path -LiteralPath $expectedOutputReceipt -PathType Leaf)) {
        throw 'G125 canonical expected-output receipt is missing'
    }
    $receiptHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        $expectedOutputReceipt).Hash.ToLowerInvariant()
    if ($receiptHash -ne $expectedOutputReceiptSHA) {
        throw 'G125 canonical expected-output receipt SHA-256 mismatch'
    }
    try {
        $json = Get-Content -LiteralPath $expectedOutputReceipt -Raw |
            ConvertFrom-Json
    } catch {
        throw 'G125 canonical expected-output receipt is invalid JSON'
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
        [double]$json.host_budget_gib -ne 30.0 -or
        [int]$json.control_count -ne 3 -or
        [int]$json.candidate_count -ne 3 -or
        -not [bool]$json.all_rows_exact -or
        -not [bool]$json.all_rows_uncontaminated -or
        [string]$json.expected_content_sha256 -notmatch
            '^[0-9a-fA-F]{64}$') {
        throw 'G125 canonical expected-output receipt contract mismatch'
    }
    return ([string]$json.expected_content_sha256).ToLowerInvariant()
}

function Assert-G125SafetyResult {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$ExpectedContentSHA
    )

    $samples = @($Result.results)
    if ([int]$Result.repeats -ne 1 -or $samples.Count -ne 1) {
        throw 'G125 is n=1 structural only; child repeats/results contract failed'
    }
    if ([string]$Result.gate_kind -ne 'structural-safety') {
        throw 'G125 child must run GateKind=structural-safety'
    }
    if ([string]$Result.prompt_sha256 -ne $promptSHA) {
        throw 'G125 prompt SHA mismatch'
    }
    if ([string]$Result.expected_content_sha256 -ne $ExpectedContentSHA -or
        [string]$samples[0].content_sha256 -ne $ExpectedContentSHA) {
        throw 'G125 exact content SHA mismatch'
    }
    if (-not [bool]$Result.nested_residual_verify_reconstruction) {
        throw 'G125 reconstruction verification was not enabled'
    }
    if (-not [bool]$Result.nested_residual_gpu_cache_requested -or
        -not [bool]$Result.nested_residual_vram_runtime_observed -or
        [UInt64]$Result.nested_residual_vram_misses -eq 0 -or
        [UInt64]$Result.nested_residual_vram_host_fills -ne 0 -or
        [UInt64]$Result.nested_residual_vram_host_bytes -ne 0 -or
        [UInt64]$Result.nested_residual_vram_h2d_bytes -eq 0 -or
        [UInt64]$Result.nested_residual_vram_h2d_bytes -ne
            ([UInt64]$Result.nested_residual_vram_misses * [UInt64]7077888) -or
        [UInt64]$Result.nested_residual_vram_failures -ne 0) {
        throw 'G125 nested residual GPU-cache route counters failed'
    }
    if (-not [bool]$Result.nested_residual_gpu_join_requested -or
        -not [bool]$Result.nested_residual_gpu_join_observed -or
        [int]$Result.nested_residual_gpu_join_requested_runtime -ne 1 -or
        [int]$Result.nested_residual_gpu_join_observed_runtime -ne 1 -or
        [UInt64]$Result.nested_residual_gpu_join_calls -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_blocks -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_base_h2d_bytes -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_residual_h2d_bytes -eq 0 -or
        [UInt64]$Result.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [double]$Result.nested_residual_gpu_join_wait_seconds -lt 0.0 -or
        [double]$Result.nested_residual_gpu_join_verify_seconds -lt 0.0 -or
        [UInt64]$Result.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$Result.nested_residual_gpu_join_failures -ne 0) {
        throw 'G125 nested residual GPU join safety counters failed'
    }
    if (-not [bool]$Result.compose_prefill_mass_open_router_requested -or
        [int]$Result.expert_tiering.compose_router_open -ne 1 -or
        [string]$Result.expert_tiering_requested -ne 'enforce' -or
        [string]$Result.expert_tier_policy_requested -ne 'mass-lfru' -or
        $Result.reap_mask_file) {
        throw 'G125 full/open routing contract failed'
    }
    if ([UInt64]$Result.nested_residual_mismatches -ne 0 -or
        [UInt64]$Result.nested_residual_failures -ne 0) {
        throw 'G125 nested residual exactness counters failed'
    }
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G125 required script missing: $path"
    }
}
if ((Get-G125Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G125 prompt SHA-256 mismatch'
}

$expectedContentSHA = Get-G125ExpectedContentSHA
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
    '-DynamicArenaGiB', '25.828125',
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
        schema = 'g125_nested_gpu_join_safety_plan_v1'
        status = 'whatif_no_runtime'
        tag = $childTag
        expected_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        n = 1
        claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
        harness_arguments = @($arguments)
    } | ConvertTo-Json -Depth 8
    $bootstrapArguments.WhatIf = $true
    & $bootstrap @bootstrapArguments
    exit 0
}

foreach ($path in @($model, "$model.receipt.json", $sidecar, $sidecarReceipt)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G125 required file missing: $path"
    }
}

$modelLock = $null
$sidecarLock = $null
try {
    $modelLock = [IO.File]::Open(
        $model, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sidecarLock = [IO.File]::Open(
        $sidecar, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)

    & $bootstrap @bootstrapArguments
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "G125 child failed with exit code $LASTEXITCODE"
    }

    $resultPath = Join-Path $runs ('g7_' + $childTag + '_result.json')
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw "G125 result missing: $resultPath"
    }
    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
    Assert-G125SafetyResult -Result $result -ExpectedContentSHA $expectedContentSHA

    $candidateSeconds = [double]$result.results[0].seconds
    $joinSeconds = [double]$result.nested_residual_gpu_join_seconds
    $joinWaitSeconds = [double]$result.nested_residual_gpu_join_wait_seconds
    $verifySeconds = [double]$result.nested_residual_gpu_join_verify_seconds
    $receipt = [ordered]@{
        schema = 'ds4_g125_nested_gpu_join_safety_v1'
        status = 'pass_structural_n1_no_performance_or_quality_verdict'
        tag = $childTag
        result_path = $resultPath
        exact_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
        verification_mode = 'exact output SHA plus runtime reconstruction verify; verification overhead reported separately'
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
            seconds = $joinSeconds
            wait_calls =
                [UInt64]$result.nested_residual_gpu_join_wait_calls
            wait_seconds = $joinWaitSeconds
            verify_calls =
                [UInt64]$result.nested_residual_gpu_join_verify_calls
            verify_bytes =
                [UInt64]$result.nested_residual_gpu_join_verify_bytes
            verify_seconds = $verifySeconds
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
        timing = [ordered]@{
            candidate_request_seconds = $candidateSeconds
            gpu_join_candidate_seconds = $joinSeconds
            gpu_join_wait_seconds = $joinWaitSeconds
            verification_overhead_seconds = $verifySeconds
            timing_claim_scope =
                'diagnostic only; gpu_join_seconds is enqueue-side, wait_seconds is scratch/event completion pressure, timers may overlap and must not be summed into a claim'
        }
        routing_contract =
            'full/open routing preserved; no REAP/static/closed masks'
    }
    $receiptPath = Join-Path $runs ('g7_' + $childTag + '_receipt.json')
    $receipt | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Output ("G125_SAFETY_RECEIPT=" + $receiptPath)
} finally {
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}
