# G127 nested residual n=3 A/B: GPU join residual pread vs residual-cache.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g127_nested_gpu_join_residual_cache_ab',
    [ValidatePattern('^$|^[A-Za-z0-9_-]+$')]
    [string]$ResumeBatchTag = '',
    [Parameter(Mandatory=$true)]
    [string]$G127SafetyReceipt,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedG127SafetyReceiptSHA256,
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
$sidecar = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.ds4nr'
$sidecarReceipt = 'C:\ds4-models\ds4-nested-residual-layers3-16-29-42.receipt.json'
$sidecarBytes = [UInt64]3221226880
$sidecarSHA = '07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9'
$payloadSHA = '02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8'
$g125SafetyReceipt = Join-Path $runs 'g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json'
$g125SafetyReceiptSHA = 'ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb'
$expectedContentSHA = 'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510'
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$arenaGiB = 25.828125
$nestedBaseGiB = 3.75
$nestedExactCacheGiB = 0.421875
$hostBudgetGiB = 30.0
$g127SafetyReceiptForChildren = $G127SafetyReceipt
$g127SafetyReceiptSHAForChildren =
    $ExpectedG127SafetyReceiptSHA256.ToLowerInvariant()

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

function Get-G127ConfigurationSHA {
    $contract = @(
        'schema=g127_nested_gpu_join_residual_cache_config_v1',
        "model_sha256=$modelSHA",
        "sidecar_sha256=$sidecarSHA",
        "sidecar_payload_sha256=$payloadSHA",
        "prompt_sha256=$promptSHA",
        "expected_content_sha256=$expectedContentSHA",
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

function Get-G127CurrentBuildContract {
    foreach ($path in @($exe, $buildManifestPath, $harness, $bootstrap)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G127 current-build input missing: $path"
        }
    }
    try {
        $manifest = Get-Content -LiteralPath $buildManifestPath -Raw |
            ConvertFrom-Json
    } catch {
        throw 'G127 current build manifest is invalid JSON'
    }
    $exeSHA = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $manifestSHA = (Get-FileHash -LiteralPath $buildManifestPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$manifest.schema -ne 'g7_native_windows_build_manifest_v1' -or
        [string]$manifest.executable_sha256 -ine $exeSHA -or
        [string]$manifest.input_fingerprint_sha256 -notmatch
            '^[0-9a-fA-F]{64}$') {
        throw 'G127 current build manifest contract mismatch'
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

function Assert-G127SafetyReceipt {
    param(
        [Parameter(Mandatory=$true)][string]$ReceiptPath,
        [Parameter(Mandatory=$true)][string]$ExpectedReceiptSHA,
        [Parameter(Mandatory=$true)][object]$CurrentBuild
    )

    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) {
        throw "G127 safety receipt is missing: $ReceiptPath"
    }
    $resolvedReceipt = (Resolve-Path -LiteralPath $ReceiptPath).Path
    $receiptSHA = (Get-FileHash -LiteralPath $resolvedReceipt `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($receiptSHA -ine $ExpectedReceiptSHA) {
        throw 'G127 safety receipt SHA-256 mismatch'
    }
    try {
        $receipt = Get-Content -LiteralPath $resolvedReceipt -Raw |
            ConvertFrom-Json
    } catch {
        throw 'G127 safety receipt is invalid JSON'
    }
    $configurationSHA = Get-G127ConfigurationSHA
    if ([string]$receipt.schema -ne
            'ds4_g127_nested_gpu_join_residual_cache_safety_v1' -or
        [string]$receipt.status -ne
            'pass_structural_n1_no_performance_or_quality_verdict' -or
        [string]$receipt.claim_scope -ne
            'structural_safety_only_no_sota_no_quality_verdict' -or
        [string]$receipt.exact_content_sha256 -ine $expectedContentSHA -or
        [string]$receipt.prompt_sha256 -ine $promptSHA -or
        [string]$receipt.configuration_sha256 -ine $configurationSHA -or
        [string]$receipt.routing_contract -ne
            'full/open routing preserved; no REAP/static/closed masks') {
        throw 'G127 safety receipt top-level contract mismatch'
    }
    if ([string]$receipt.model.path -ine $model -or
        [string]$receipt.model.sha256 -ine $modelSHA -or
        [string]$receipt.sidecar.path -ine $sidecar -or
        [UInt64]$receipt.sidecar.bytes -ne $sidecarBytes -or
        [string]$receipt.sidecar.sha256 -ine $sidecarSHA -or
        [string]$receipt.sidecar.source_sha256 -ine $modelSHA -or
        [string]$receipt.sidecar.payload_sha256 -ine $payloadSHA -or
        [string]$receipt.g125_prerequisite.receipt_path -ine
            $g125SafetyReceipt -or
        [string]$receipt.g125_prerequisite.receipt_sha256 -ine
            $g125SafetyReceiptSHA) {
        throw 'G127 safety receipt model/sidecar/G125 provenance mismatch'
    }
    if ([string]$receipt.build.executable_sha256 -ine
            $CurrentBuild.executable_sha256 -or
        [string]$receipt.build.build_manifest_sha256 -ine
            $CurrentBuild.manifest_sha256 -or
        [string]$receipt.build.build_manifest_input_fingerprint_sha256 -ine
            $CurrentBuild.input_fingerprint_sha256 -or
        [string]$receipt.build.harness_sha256 -ine
            $CurrentBuild.harness_sha256 -or
        [string]$receipt.build.bootstrap_sha256 -ine
            $CurrentBuild.bootstrap_sha256) {
        throw 'G127 safety receipt is not from the current build/harness'
    }
    if ([int]$receipt.residual_cache.enabled -ne 1 -or
        [UInt64]$receipt.residual_cache.hits -eq 0 -or
        [UInt64]$receipt.residual_cache.misses -eq 0 -or
        [UInt64]$receipt.residual_cache.capacity -eq 0 -or
        [UInt64]$receipt.residual_cache.entries -gt
            [UInt64]$receipt.residual_cache.capacity -or
        [UInt64]$receipt.residual_cache.pread_bytes_avoided -eq 0 -or
        [UInt64]$receipt.residual_cache.cached_join_calls -eq 0 -or
        [UInt64]$receipt.residual_cache.invariant_failures -ne 0) {
        throw 'G127 safety receipt residual-cache counters failed'
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
        [UInt64]$receipt.exactness.fallback_markers -ne 0 -or
        -not [bool]$receipt.machine_quiescence.ready_to_launch -or
        [bool]$receipt.machine_quiescence.skipped -or
        [int]$receipt.machine_quiescence.preflight_failures -ne 0 -or
        [int]$receipt.machine_quiescence.runtime_contamination_consecutive_peak -ne 0) {
        throw 'G127 safety receipt exactness/quiescence contract failed'
    }
    $resultPath = [string]$receipt.result_path
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'G127 safety result referenced by receipt is missing'
    }
    $resultSHA = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($resultSHA -ine [string]$receipt.result_sha256) {
        throw 'G127 safety result SHA-256 mismatch'
    }
    try {
        $result = Get-Content -LiteralPath $resultPath -Raw |
            ConvertFrom-Json
    } catch {
        throw 'G127 safety result is invalid JSON'
    }
    $samples = @($result.results)
    $resultPreflight = $result.system_quiescence_preflight
    $resultPreflightFailures = @()
    if ($null -ne $resultPreflight -and
        $null -ne $resultPreflight.failures) {
        $resultPreflightFailures = @($resultPreflight.failures)
    }
    $resultContaminationPeak = 0
    if ($null -ne $result.runtime_telemetry -and
        $null -ne
            $result.runtime_telemetry.contamination_consecutive_peak) {
        $resultContaminationPeak =
            [int]$result.runtime_telemetry.contamination_consecutive_peak
    }
    if ([string]$result.gate_kind -ne 'structural-safety' -or
        [bool]$result.quality_eligible -or
        [bool]$result.sota_eligible -or
        [int]$result.repeats -ne 1 -or
        $samples.Count -ne 1 -or
        [int]$result.server_exit_code -ne 0 -or
        [string]$result.executable_sha256 -ine
            $CurrentBuild.executable_sha256 -or
        [string]$result.build_manifest_sha256 -ine
            $CurrentBuild.manifest_sha256 -or
        [string]$result.build_manifest_input_fingerprint_sha256 -ine
            $CurrentBuild.input_fingerprint_sha256 -or
        [string]$result.harness_sha256 -ine $CurrentBuild.harness_sha256 -or
        [string]$result.model_sha256 -ine $modelSHA -or
        [string]$result.nested_residual_sidecar_sha256 -ine $sidecarSHA -or
        [string]$result.nested_residual_expected_source_sha256 -ine
            $modelSHA -or
        [string]$result.nested_residual_expected_payload_sha256 -ine
            $payloadSHA -or
        [string]$result.prompt_sha256 -ine $promptSHA -or
        [string]$result.expected_content_sha256 -ine $expectedContentSHA -or
        [string]$samples[0].content_sha256 -ine $expectedContentSHA -or
        [int]$result.requested_max_tokens -ne 64 -or
        [int]$result.context_requested -ne 256 -or
        [double]$result.dynamic_arena_gib_requested -ne $arenaGiB -or
        [int]$result.expert_cache_requested -ne 320 -or
        [int]$result.nested_residual_cache_experts_requested -ne 64 -or
        -not [bool]$result.nested_residual_verify_reconstruction -or
        -not [bool]$result.nested_residual_gpu_cache_requested -or
        -not [bool]$result.nested_residual_gpu_join_requested -or
        -not [bool]$result.nested_residual_gpu_join_residual_cache_observed -or
        [int]$result.nested_residual_gpu_join_residual_cache_enabled_runtime -ne 1 -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_hits -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_misses -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_capacity -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_entries -gt
            [UInt64]$result.nested_residual_gpu_join_residual_cache_capacity -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_pread_bytes_avoided -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_cached_join_calls -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_residual_cache_invariant_failures -ne 0 -or
        [UInt64]$result.nested_residual_gpu_join_verify_calls -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_verify_bytes -eq 0 -or
        [UInt64]$result.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$result.nested_residual_gpu_join_failures -ne 0 -or
        [UInt64]$result.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        [UInt64]$result.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [UInt64]$result.nested_residual_mismatches -ne 0 -or
        [UInt64]$result.nested_residual_failures -ne 0 -or
        [UInt64]$result.moe_overlapped_io_fallbacks -ne 0 -or
        -not [bool]$result.compose_prefill_mass_open_router_requested -or
        [int]$result.expert_tiering.compose_router_open -ne 1 -or
        [string]$result.reap_mask_file_requested -or
        [bool]$result.embedded_bake_mask_observed -or
        $null -eq $resultPreflight -or
        -not [bool]$resultPreflight.ready_to_launch -or
        [bool]$resultPreflight.skipped -or
        $resultPreflightFailures.Count -ne 0 -or
        $resultContaminationPeak -ne 0) {
        throw 'G127 safety result cross-check failed'
    }
    return [pscustomobject]@{
        receipt_path = $resolvedReceipt
        receipt_sha256 = $receiptSHA
        result_path = (Resolve-Path -LiteralPath $resultPath).Path
        result_sha256 = $resultSHA
        configuration_sha256 = $configurationSHA
    }
}

function New-G127Suffix {
    return ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
        '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
}

function Get-G127Mean {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sum = 0.0
    foreach ($value in $Values) { $sum += [double]$value }
    return $sum / [double]$Values.Count
}

function Get-G127Median {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function New-G127CommonHarnessArguments {
    param([Parameter(Mandatory=$true)][string]$ChildTag)

    return @(
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
        '-NestedResidualGpuCache',
        '-AllowNestedResidualBenchmarkSuite',
        '-OuterNestedResidualBenchmarkProcessCount', '3',
        '-RuntimeMinimumAvailableGiB', '1',
        '-RuntimeMaximumDiskQueueLength', '8',
        '-RuntimeContaminationSamples', '3',
        '-QuiescenceCooldownSec', '10',
        '-TimeoutSec', ([string]$TimeoutSec),
        '-Tag', $ChildTag
    )
}

function New-G127ChildPlan {
    param(
        [ValidateSet('control', 'candidate')][string]$Arm,
        [int]$RepeatIndex,
        [string]$BatchTag
    )

    $childTag = $BatchTag + '_' + $Arm + '_r' + $RepeatIndex
    $args = @(New-G127CommonHarnessArguments -ChildTag $childTag)
    $args += @(
        '-NestedResidualGpuJoin',
        '-NestedResidualGpuJoinSafetyReceipt',
            $g127SafetyReceiptForChildren,
        '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
            $g127SafetyReceiptSHAForChildren
    )
    if ($Arm -eq 'candidate') {
        $args += @('-NestedResidualGpuJoinResidualCache')
    }

    return [pscustomobject]@{
        arm = $Arm
        repeat_index = $RepeatIndex
        tag = $childTag
        result_path = (Join-Path $runs ('g7_' + $childTag + '_result.json'))
        harness_arguments = @($args)
    }
}

function Invoke-G127Child {
    param([Parameter(Mandatory=$true)][object]$Plan)

    $bootstrapArgs = @{
        HarnessPath = $harness
        RepoRoot = $root
        HarnessArguments = @($Plan.harness_arguments)
    }
    if ($WhatIf) {
        $bootstrapArgs.WhatIf = $true
        Write-Host ('[g127] WHATIF child=' + $Plan.tag + ' arm=' + $Plan.arm)
        & $bootstrap @bootstrapArgs
        return
    }

    if (Test-Path -LiteralPath $Plan.result_path -PathType Leaf) {
        if ($ResumeBatchTag) {
            Write-Host ('[g127] reuse completed child=' + $Plan.tag)
            return
        }
        throw "G127 child result already exists for immutable tag: $($Plan.result_path)"
    }
    if ($InterChildCooldownSec -gt 0) {
        Write-Host ('[g127] cooldown seconds=' + $InterChildCooldownSec +
            ' before child=' + $Plan.tag)
        Start-Sleep -Seconds $InterChildCooldownSec
    }
    Write-Host ('[g127] launch child=' + $Plan.tag + ' arm=' + $Plan.arm)
    & $bootstrap @bootstrapArgs
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw ('G127 child failed with exit code ' + $LASTEXITCODE + ': ' +
            $Plan.tag)
    }
    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G127 child result missing: $($Plan.result_path)"
    }
}

function Read-G127ChildResult {
    param([Parameter(Mandatory=$true)][object]$Plan)

    $json = Get-Content -LiteralPath $Plan.result_path -Raw | ConvertFrom-Json
    $samples = @($json.results)
    if ([int]$json.repeats -ne 1 -or $samples.Count -ne 1) {
        throw "G127 child must be exactly one independent request: $($Plan.tag)"
    }
    $sample = $samples[0]
    if ([string]$sample.content_sha256 -ne $expectedContentSHA -or
        [string]$json.expected_content_sha256 -ne $expectedContentSHA -or
        [string]$json.prompt_sha256 -ne $promptSHA) {
        throw "G127 exact prompt/output contract mismatch for $($Plan.tag)"
    }
    if ([string]$json.gate_kind -ne 'benchmark' -or
        [int]$json.requested_max_tokens -ne 64 -or
        [int]$json.context_requested -ne 256 -or
        [double]$json.dynamic_arena_gib_requested -ne $arenaGiB -or
        [int]$json.expert_cache_requested -ne 320 -or
        -not [bool]$json.allow_nested_residual_benchmark_suite_requested -or
        [int]$json.outer_nested_residual_benchmark_process_count_requested -ne 3 -or
        -not [bool]$json.nested_residual_benchmark_member -or
        -not [bool]$json.nested_residual_enabled -or
        -not [bool]$json.nested_residual_gpu_cache_requested -or
        -not [bool]$json.nested_residual_runtime_observed -or
        -not [bool]$json.nested_residual_vram_runtime_observed -or
        [UInt64]$json.nested_residual_failures -ne 0 -or
        [UInt64]$json.nested_residual_mismatches -ne 0 -or
        [UInt64]$json.nested_residual_vram_failures -ne 0 -or
        [string]$json.nested_residual_sidecar_sha256 -ine $sidecarSHA -or
        [string]$json.nested_residual_expected_payload_sha256 -ine
            $payloadSHA -or
        -not [bool]$json.compose_prefill_mass_open_router_requested -or
        [int]$json.expert_tiering.compose_router_open -ne 1 -or
        [string]$json.prefill_mass_wrap_router -ne 'unbiased' -or
        [string]$json.prefill_mass_wrap_mask -ne 'request-scoped-open' -or
        [string]$json.prefill_mass_compose_mask_semantics -ne
            'request-scoped-open' -or
        [string]$json.reap_mask_file_requested -or
        [bool]$json.embedded_bake_mask_observed) {
        throw "G127 nested residual benchmark contract mismatch for $($Plan.tag)"
    }

    if (-not [bool]$json.nested_residual_gpu_join_requested -or
        -not [bool]$json.nested_residual_gpu_join_observed -or
        [int]$json.nested_residual_gpu_join_requested_runtime -ne 1 -or
        [int]$json.nested_residual_gpu_join_observed_runtime -ne 1 -or
        [UInt64]$json.nested_residual_gpu_join_calls -eq 0 -or
        [UInt64]$json.nested_residual_gpu_join_base_h2d_bytes -eq 0 -or
        [UInt64]$json.nested_residual_gpu_join_residual_h2d_bytes -eq 0 -or
        [UInt64]$json.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [UInt64]$json.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        [UInt64]$json.nested_residual_gpu_join_verify_calls -ne 0 -or
        [UInt64]$json.nested_residual_gpu_join_verify_bytes -ne 0 -or
        [double]$json.nested_residual_gpu_join_verify_seconds -ne 0.0 -or
        [UInt64]$json.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$json.nested_residual_gpu_join_failures -ne 0 -or
        -not [bool]$json.nested_residual_gpu_join_safety_receipt_validated -or
        [string]$json.nested_residual_gpu_join_safety_receipt_sha256 -ine
            $g127SafetyReceiptSHAForChildren -or
        [string]$json.nested_residual_gpu_join_safety_receipt_path -ine
            $g127SafetyReceiptForChildren -or
        [UInt64]$json.moe_overlapped_io_fallbacks -ne 0 -or
        [UInt64]$json.nested_residual_vram_host_fills -ne 0 -or
        [UInt64]$json.nested_residual_vram_host_bytes -ne 0 -or
        [UInt64]$json.nested_residual_vram_h2d_bytes -ne
            ([UInt64]$json.nested_residual_vram_misses * [UInt64]7077888)) {
        throw "G127 GPU-join base contract mismatch for $($Plan.tag)"
    }

    if ($Plan.arm -eq 'candidate') {
        if (-not [bool]$json.nested_residual_gpu_join_residual_cache_requested -or
            -not [bool]$json.nested_residual_gpu_join_residual_cache_observed -or
            [int]$json.nested_residual_gpu_join_residual_cache_enabled_runtime -ne 1 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_hits -eq 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_misses -eq 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_capacity -eq 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_entries -gt
                [UInt64]$json.nested_residual_gpu_join_residual_cache_capacity -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_pread_bytes_avoided -eq 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_cached_join_calls -eq 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_invariant_failures -ne 0) {
            throw "G127 candidate residual-cache contract mismatch for $($Plan.tag)"
        }
    } else {
        if ([bool]$json.nested_residual_gpu_join_residual_cache_requested -or
            [bool]$json.nested_residual_gpu_join_residual_cache_observed -or
            [int]$json.nested_residual_gpu_join_residual_cache_enabled_runtime -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_hits -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_misses -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_pread_bytes_avoided -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_cached_join_calls -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_cache_invariant_failures -ne 0) {
            throw "G127 control residual-cache contract mismatch for $($Plan.tag)"
        }
    }

    $preflight = $json.system_quiescence_preflight
    $failures = @()
    if ($null -ne $preflight -and $null -ne $preflight.failures) {
        $failures = @($preflight.failures)
    }
    $runtimePeak = 0
    if ($null -ne $json.runtime_telemetry -and
        $null -ne $json.runtime_telemetry.contamination_consecutive_peak) {
        $runtimePeak = [int]$json.runtime_telemetry.contamination_consecutive_peak
    }
    $uncontaminated = ($null -ne $preflight) -and
        [bool]$preflight.ready_to_launch -and
        (-not [bool]$preflight.skipped) -and
        $failures.Count -eq 0 -and
        $runtimePeak -eq 0

    return [pscustomobject]@{
        arm = $Plan.arm
        order_position = [int]$Plan.order_position
        repeat_index = $Plan.repeat_index
        tag = $Plan.tag
        result_path = $Plan.result_path
        exact = $true
        uncontaminated = $uncontaminated
        seconds = [double]$sample.seconds
        tokens_per_second = [double]$sample.tokens_per_second
        completion_tokens = [int]$sample.completion_tokens
        server_decode_mean_tokens_per_second =
            [double]$json.server_decode_mean_tokens_per_second
        server_prefill_ttft_mean_seconds =
            [double]$json.server_prefill_ttft_mean_seconds
        load_seconds = [double]$json.load_seconds
        nested_hits = [UInt64]$json.nested_residual_vram_hits
        nested_misses = [UInt64]$json.nested_residual_vram_misses
        nested_host_fills = [UInt64]$json.nested_residual_vram_host_fills
        nested_h2d_bytes = [UInt64]$json.nested_residual_vram_h2d_bytes
        gpu_join_calls = [UInt64]$json.nested_residual_gpu_join_calls
        gpu_join_seconds = [double]$json.nested_residual_gpu_join_seconds
        gpu_join_wait_seconds =
            [double]$json.nested_residual_gpu_join_wait_seconds
        residual_cache_requested =
            [bool]$json.nested_residual_gpu_join_residual_cache_requested
        residual_cache_observed =
            [bool]$json.nested_residual_gpu_join_residual_cache_observed
        residual_cache_enabled_runtime =
            [int]$json.nested_residual_gpu_join_residual_cache_enabled_runtime
        residual_cache_hits =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_hits
        residual_cache_misses =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_misses
        residual_cache_pread_bytes =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_pread_bytes
        residual_cache_pread_bytes_avoided =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_pread_bytes_avoided
        residual_cache_h2d_bytes =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_h2d_bytes
        residual_cache_cached_join_calls =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_cached_join_calls
        residual_cache_invariant_failures =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_invariant_failures
        nested_residual_preads = [UInt64]$json.nested_residual_preads
        nested_residual_bytes = [UInt64]$json.nested_residual_bytes
        aggregate_disk_read_gib =
            [math]::Round(
                [double]$json.runtime_telemetry.aggregate_disk_read_bytes_estimated /
                    1GB, 6)
        contamination_peak = $runtimePeak
        preflight_failures = $failures.Count
    }
}

function New-G127ArmSummary {
    param([Parameter(Mandatory=$true)][object[]]$Rows)

    $e2e = [double[]]@($Rows | ForEach-Object { $_.tokens_per_second })
    $decode = [double[]]@(
        $Rows | ForEach-Object { $_.server_decode_mean_tokens_per_second })
    $ttft = [double[]]@(
        $Rows | ForEach-Object { $_.server_prefill_ttft_mean_seconds })
    return [pscustomobject]@{
        count = $Rows.Count
        e2e_tps_mean = Get-G127Mean $e2e
        e2e_tps_median = Get-G127Median $e2e
        server_decode_tps_mean = Get-G127Mean $decode
        server_decode_tps_median = Get-G127Median $decode
        ttft_seconds_mean = Get-G127Mean $ttft
        ttft_seconds_median = Get-G127Median $ttft
    }
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G127 required script missing: $path"
    }
}
if ((Get-G127Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G127 prompt SHA-256 mismatch'
}
$g127SafetyContract = $null
$currentBuild = $null
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar,
            $sidecarReceipt, $g125SafetyReceipt, $G127SafetyReceipt)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G127 required file missing: $path"
        }
    }
    if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
        throw 'G127 sidecar size mismatch'
    }
    $observedG125SafetySHA =
        (Get-FileHash -LiteralPath $g125SafetyReceipt -Algorithm SHA256).
            Hash.ToLowerInvariant()
    if ($observedG125SafetySHA -ine $g125SafetyReceiptSHA) {
        throw 'G127 G125 safety receipt SHA mismatch'
    }
    $currentBuild = Get-G127CurrentBuildContract
    $g127SafetyContract = Assert-G127SafetyReceipt `
        -ReceiptPath $G127SafetyReceipt `
        -ExpectedReceiptSHA $ExpectedG127SafetyReceiptSHA256 `
        -CurrentBuild $currentBuild
    $g127SafetyReceiptForChildren = $g127SafetyContract.receipt_path
    $g127SafetyReceiptSHAForChildren =
        $g127SafetyContract.receipt_sha256
}

$modelLock = $null
$sidecarLock = $null
$g125SafetyLock = $null
$g127SafetyLock = $null
$g127SafetyResultLock = $null
$exeLock = $null
$buildManifestLock = $null
$harnessLock = $null
$bootstrapLock = $null
try {
    if (-not $WhatIf) {
        $modelLock = [IO.File]::Open(
            $model, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $sidecarLock = [IO.File]::Open(
            $sidecar, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $g125SafetyLock = [IO.File]::Open(
            $g125SafetyReceipt, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $g127SafetyLock = [IO.File]::Open(
            $g127SafetyContract.receipt_path, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $g127SafetyResultLock = [IO.File]::Open(
            $g127SafetyContract.result_path, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $exeLock = [IO.File]::Open(
            $exe, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $buildManifestLock = [IO.File]::Open(
            $buildManifestPath, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $harnessLock = [IO.File]::Open(
            $harness, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $bootstrapLock = [IO.File]::Open(
            $bootstrap, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)

        $lockedBuild = Get-G127CurrentBuildContract
        $lockedSafetyContract = Assert-G127SafetyReceipt `
            -ReceiptPath $g127SafetyContract.receipt_path `
            -ExpectedReceiptSHA $g127SafetyContract.receipt_sha256 `
            -CurrentBuild $lockedBuild
        if ($lockedSafetyContract.result_sha256 -ine
                $g127SafetyContract.result_sha256 -or
            $lockedSafetyContract.configuration_sha256 -ine
                $g127SafetyContract.configuration_sha256) {
            throw 'G127 safety/build contract changed before A/B planning'
        }
        $g127SafetyContract = $lockedSafetyContract
    }

    $batchTag = if ($ResumeBatchTag) {
        $ResumeBatchTag
    } else {
        $Tag + '_' + (New-G127Suffix)
    }
    $order = @(
        [pscustomobject]@{ arm = 'control'; repeat_index = 1 },
        [pscustomobject]@{ arm = 'candidate'; repeat_index = 1 },
        [pscustomobject]@{ arm = 'candidate'; repeat_index = 2 },
        [pscustomobject]@{ arm = 'control'; repeat_index = 2 },
        [pscustomobject]@{ arm = 'control'; repeat_index = 3 },
        [pscustomobject]@{ arm = 'candidate'; repeat_index = 3 }
    )
    $plans = @()
    $position = 0
    foreach ($entry in $order) {
        $position += 1
        $plan = New-G127ChildPlan -Arm $entry.arm `
            -RepeatIndex $entry.repeat_index -BatchTag $batchTag
        $plan | Add-Member -NotePropertyName order_position `
            -NotePropertyValue $position
        $plans += $plan
    }

    if ($WhatIf) {
        [pscustomobject]@{
            schema = 'g127_nested_gpu_join_residual_cache_ab_plan_v1'
            batch_tag = $batchTag
            resume_batch_tag = $ResumeBatchTag
            inter_child_cooldown_seconds = $InterChildCooldownSec
            expected_content_sha256 = $expectedContentSHA
            prompt_sha256 = $promptSHA
            g125_safety_receipt = $g125SafetyReceipt
            g125_safety_receipt_sha256 = $g125SafetyReceiptSHA
            g127_safety_receipt = $G127SafetyReceipt
            g127_safety_receipt_sha256 =
                $ExpectedG127SafetyReceiptSHA256.ToLowerInvariant()
            child_count = $plans.Count
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
        foreach ($plan in $plans) { Invoke-G127Child -Plan $plan }
        return
    }

    foreach ($plan in $plans) { Invoke-G127Child -Plan $plan }

    $rows = @()
    foreach ($plan in $plans) { $rows += Read-G127ChildResult -Plan $plan }
    $controlRows = @($rows | Where-Object { $_.arm -eq 'control' })
    $candidateRows = @($rows | Where-Object { $_.arm -eq 'candidate' })
    if ($controlRows.Count -ne 3 -or $candidateRows.Count -ne 3) {
        throw 'G127 did not collect exactly 3 control and 3 candidate rows'
    }
    $allValid = (@($rows | Where-Object {
                -not $_.exact -or -not $_.uncontaminated
            }).Count -eq 0)
    if (-not $allValid) {
        throw 'G127 n>=3 verdict invalid: exactness or contamination gate failed'
    }

    $controlSummary = New-G127ArmSummary -Rows $controlRows
    $candidateSummary = New-G127ArmSummary -Rows $candidateRows
    $deltaE2E =
        ([double]$candidateSummary.e2e_tps_mean /
         [double]$controlSummary.e2e_tps_mean) - 1.0
    $deltaDecode =
        ([double]$candidateSummary.server_decode_tps_mean /
         [double]$controlSummary.server_decode_tps_mean) - 1.0
    $controlPreads = [UInt64](($controlRows |
        Measure-Object -Property nested_residual_preads -Sum).Sum)
    $candidatePreads = [UInt64](($candidateRows |
        Measure-Object -Property nested_residual_preads -Sum).Sum)
    $controlResidualBytes = [UInt64](($controlRows |
        Measure-Object -Property nested_residual_bytes -Sum).Sum)
    $candidateResidualBytes = [UInt64](($candidateRows |
        Measure-Object -Property nested_residual_bytes -Sum).Sum)
    $candidateAvoided = [UInt64](($candidateRows |
        Measure-Object -Property residual_cache_pread_bytes_avoided -Sum).Sum)
    if ($candidatePreads -ge $controlPreads -or
        $candidateResidualBytes -ge $controlResidualBytes -or
        $candidateAvoided -eq 0) {
        throw 'G127 residual-cache candidate failed transport-reduction gate'
    }

    $resultPath = Join-Path $runs ('g7_' + $batchTag + '_result.json')
    $result = [ordered]@{
        schema = 'g127_nested_gpu_join_residual_cache_ab_result_v1'
        batch_tag = $batchTag
        status = 'pass'
        claim_scope = 'n3_nested_residual_gpu_join_residual_cache_ab'
        n3_valid = $true
        expected_content_sha256 = $expectedContentSHA
        prompt = $prompt
        prompt_sha256 = $promptSHA
        model = $model
        model_sha256 = $modelSHA
        sidecar = $sidecar
        sidecar_sha256 = $sidecarSHA
        sidecar_payload_sha256 = $payloadSHA
        g125_safety_receipt = $g125SafetyReceipt
        g125_safety_receipt_sha256 = $g125SafetyReceiptSHA
        g127_safety_receipt = $g127SafetyContract.receipt_path
        g127_safety_receipt_sha256 =
            $g127SafetyContract.receipt_sha256
        g127_safety_result = $g127SafetyContract.result_path
        g127_safety_result_sha256 = $g127SafetyContract.result_sha256
        g127_safety_configuration_sha256 =
            $g127SafetyContract.configuration_sha256
        order = @($plans | ForEach-Object {
            [pscustomobject]@{
                order_position = $_.order_position
                arm = $_.arm
                repeat_index = $_.repeat_index
                tag = $_.tag
            }
        })
        host_budget_gib = [ordered]@{
            primary_arena = $arenaGiB
            nested_base = $nestedBaseGiB
            exact_cache = $nestedExactCacheGiB
            total = $hostBudgetGiB
        }
        control = $controlSummary
        candidate = $candidateSummary
        transport_reduction = [ordered]@{
            control_residual_preads = $controlPreads
            candidate_residual_preads = $candidatePreads
            control_residual_bytes = $controlResidualBytes
            candidate_residual_bytes = $candidateResidualBytes
            candidate_pread_bytes_avoided = $candidateAvoided
        }
        relative_delta = [ordered]@{
            e2e_tps_mean = $deltaE2E
            server_decode_tps_mean = $deltaDecode
        }
        rows = @($rows)
    }
    $result | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host ('[g127] PASS result=' + $resultPath +
        ' e2e_delta=' + [math]::Round($deltaE2E * 100.0, 3) + '%' +
        ' decode_delta=' + [math]::Round($deltaDecode * 100.0, 3) + '%')
} finally {
    if ($null -ne $bootstrapLock) { $bootstrapLock.Dispose() }
    if ($null -ne $harnessLock) { $harnessLock.Dispose() }
    if ($null -ne $buildManifestLock) { $buildManifestLock.Dispose() }
    if ($null -ne $exeLock) { $exeLock.Dispose() }
    if ($null -ne $g127SafetyResultLock) {
        $g127SafetyResultLock.Dispose()
    }
    if ($null -ne $g127SafetyLock) { $g127SafetyLock.Dispose() }
    if ($null -ne $g125SafetyLock) { $g125SafetyLock.Dispose() }
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}

