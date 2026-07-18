# G127P protocol runner: G127 residual-cache control vs hetero route packed copy.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g127p_hetero_route_packed_copy_ab',
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
$outerRunner = $MyInvocation.MyCommand.Path
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
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$expectedContentSHA = 'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510'
$arenaGiB = 25.828125
$g127SafetyReceiptForChildren = $G127SafetyReceipt
$g127SafetyReceiptSHAForChildren =
    $ExpectedG127SafetyReceiptSHA256.ToLowerInvariant()

function Get-G127PSha256Text {
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

function Get-G127PCurrentBuildContract {
    foreach ($path in @($exe, $buildManifestPath, $harness, $bootstrap,
            $outerRunner)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G127P current-build input missing: $path"
        }
    }
    try {
        $manifest = Get-Content -LiteralPath $buildManifestPath -Raw |
            ConvertFrom-Json
    } catch {
        throw 'G127P current build manifest is invalid JSON'
    }
    $exeSHA = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $manifestSHA = (Get-FileHash -LiteralPath $buildManifestPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$manifest.schema -ne 'g7_native_windows_build_manifest_v1' -or
        [string]$manifest.executable_sha256 -ine $exeSHA -or
        [string]$manifest.head -notmatch '^[0-9a-fA-F]{40}$' -or
        $null -eq $manifest.PSObject.Properties[
            'worktree_dirty_at_build_start'] -or
        [string]$manifest.input_fingerprint_sha256 -notmatch
            '^[0-9a-fA-F]{64}$') {
        throw 'G127P current build manifest contract mismatch'
    }
    return [pscustomobject]@{
        build_head = ([string]$manifest.head).ToLowerInvariant()
        build_worktree_dirty_at_build_start =
            [bool]$manifest.worktree_dirty_at_build_start
        executable_sha256 = $exeSHA
        manifest_sha256 = $manifestSHA
        input_fingerprint_sha256 =
            ([string]$manifest.input_fingerprint_sha256).ToLowerInvariant()
        harness_sha256 = (Get-FileHash -LiteralPath $harness `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        bootstrap_sha256 = (Get-FileHash -LiteralPath $bootstrap `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        outer_runner_sha256 = (Get-FileHash -LiteralPath $outerRunner `
            -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-G127PSafetyReceipt {
    param(
        [Parameter(Mandatory=$true)][string]$ReceiptPath,
        [Parameter(Mandatory=$true)][string]$ExpectedReceiptSHA,
        [Parameter(Mandatory=$true)][object]$CurrentBuild
    )

    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) {
        throw "G127P base G127 safety receipt is missing: $ReceiptPath"
    }
    $resolvedReceipt = (Resolve-Path -LiteralPath $ReceiptPath).Path
    $receiptSHA = (Get-FileHash -LiteralPath $resolvedReceipt `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($receiptSHA -ine $ExpectedReceiptSHA) {
        throw 'G127P base G127 safety receipt SHA-256 mismatch'
    }
    $receipt = Get-Content -LiteralPath $resolvedReceipt -Raw |
        ConvertFrom-Json
    if ([string]$receipt.schema -ne
            'ds4_g127_nested_gpu_join_residual_cache_safety_v1' -or
        [string]$receipt.status -ne
            'pass_structural_n1_no_performance_or_quality_verdict' -or
        [string]$receipt.exact_content_sha256 -ine $expectedContentSHA -or
        [string]$receipt.prompt_sha256 -ine $promptSHA -or
        [string]$receipt.routing_contract -ne
            'full/open routing preserved; no REAP/static/closed masks' -or
        [string]$receipt.model.path -ine $model -or
        [string]$receipt.model.sha256 -ine $modelSHA -or
        [string]$receipt.sidecar.path -ine $sidecar -or
        [UInt64]$receipt.sidecar.bytes -ne $sidecarBytes -or
        [string]$receipt.sidecar.sha256 -ine $sidecarSHA -or
        [string]$receipt.sidecar.payload_sha256 -ine $payloadSHA) {
        throw 'G127P base G127 safety receipt contract mismatch'
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
        throw 'G127P base G127 safety receipt is not current-build bound'
    }
    if ([int]$receipt.residual_cache.enabled -ne 1 -or
        [UInt64]$receipt.residual_cache.hits -eq 0 -or
        [UInt64]$receipt.residual_cache.misses -eq 0 -or
        [UInt64]$receipt.residual_cache.invariant_failures -ne 0 -or
        [UInt64]$receipt.exactness.gpu_join_failures -ne 0 -or
        [UInt64]$receipt.exactness.cpu_reconstruct_calls -ne 0 -or
        [UInt64]$receipt.exactness.native_h2d_bytes -ne 0 -or
        [UInt64]$receipt.exactness.selected_load_fallbacks -ne 0 -or
        -not [bool]$receipt.machine_quiescence.ready_to_launch -or
        [bool]$receipt.machine_quiescence.skipped -or
        [int]$receipt.machine_quiescence.preflight_failures -ne 0 -or
        [int]$receipt.machine_quiescence.runtime_contamination_consecutive_peak -ne 0) {
        throw 'G127P base G127 safety receipt exactness/quiescence failed'
    }
    if (-not (Test-Path -LiteralPath ([string]$receipt.result_path) `
            -PathType Leaf)) {
        throw 'G127P base G127 linked safety result is missing'
    }
    $resultSHA = (Get-FileHash -LiteralPath ([string]$receipt.result_path) `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($resultSHA -ine [string]$receipt.result_sha256) {
        throw 'G127P base G127 linked safety result SHA-256 mismatch'
    }
    return [pscustomobject]@{
        receipt_path = $resolvedReceipt
        receipt_sha256 = $receiptSHA
        result_path = (Resolve-Path -LiteralPath ([string]$receipt.result_path)).Path
        result_sha256 = $resultSHA
        configuration_sha256 = ([string]$receipt.configuration_sha256)
    }
}

function Assert-G127PAggregateProvenance {
    param(
        [Parameter(Mandatory=$true)][object]$ExpectedBuild,
        [Parameter(Mandatory=$true)][object]$ExpectedSafety,
        [Parameter(Mandatory=$true)][string]$Phase
    )

    $observedBuild = Get-G127PCurrentBuildContract
    foreach ($field in @(
            'build_head',
            'executable_sha256',
            'manifest_sha256',
            'input_fingerprint_sha256',
            'harness_sha256',
            'bootstrap_sha256',
            'outer_runner_sha256')) {
        if ([string]$observedBuild.$field -ine
                [string]$ExpectedBuild.$field) {
            throw "G127P aggregate provenance changed at $Phase`: $field"
        }
    }
    if ([bool]$observedBuild.build_worktree_dirty_at_build_start -ne
            [bool]$ExpectedBuild.build_worktree_dirty_at_build_start) {
        throw "G127P aggregate provenance changed at $Phase`: build dirty"
    }

    $observedSafety = Assert-G127PSafetyReceipt `
        -ReceiptPath $ExpectedSafety.receipt_path `
        -ExpectedReceiptSHA $ExpectedSafety.receipt_sha256 `
        -CurrentBuild $observedBuild
    if ($observedSafety.receipt_sha256 -ine
            $ExpectedSafety.receipt_sha256 -or
        $observedSafety.result_sha256 -ine
            $ExpectedSafety.result_sha256 -or
        $observedSafety.configuration_sha256 -ine
            $ExpectedSafety.configuration_sha256) {
        throw "G127P G127 safety provenance changed at $Phase"
    }
}

function New-G127PSuffix {
    return ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
        '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
}

function New-G127PCommonHarnessArguments {
    param(
        [Parameter(Mandatory=$true)][string]$ChildTag,
        [Parameter(Mandatory=$true)]
        [ValidateSet('structural-safety', 'benchmark')]
        [string]$GateKind
    )

    $args = @(
        '-GateKind', $GateKind,
        '-ModelPath', $model,
        '-ExpectedModelSHA256', $modelSHA,
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
        '-NestedResidualGpuJoin',
        '-NestedResidualGpuJoinResidualCache',
        '-RuntimeMinimumAvailableGiB', '1',
        '-RuntimeMaximumDiskQueueLength', '8',
        '-RuntimeContaminationSamples', '3',
        '-QuiescenceCooldownSec', '10',
        '-TimeoutSec', ([string]$TimeoutSec),
        '-Tag', $ChildTag
    )
    if ($GateKind -eq 'benchmark') {
        $args += @(
            '-NestedResidualGpuJoinSafetyReceipt',
                $g127SafetyReceiptForChildren,
            '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
                $g127SafetyReceiptSHAForChildren,
            '-AllowNestedResidualBenchmarkSuite',
            '-OuterNestedResidualBenchmarkProcessCount', '3'
        )
    } else {
        $args += @(
            '-ReuseVerifiedModelReceipt',
            '-NestedResidualStructuralN1',
            '-NestedResidualVerifyReconstruction'
        )
    }
    return $args
}

function New-G127PChildPlan {
    param(
        [ValidateSet('safety', 'control', 'candidate')][string]$Arm,
        [int]$RepeatIndex,
        [string]$BatchTag
    )

    $gateKind = if ($Arm -eq 'safety') {
        'structural-safety'
    } else {
        'benchmark'
    }
    $childTag = if ($Arm -eq 'safety') {
        $BatchTag + '_candidate_safety'
    } else {
        $BatchTag + '_' + $Arm + '_r' + $RepeatIndex
    }
    $args = @(New-G127PCommonHarnessArguments -ChildTag $childTag `
        -GateKind $gateKind)
    if ($Arm -ne 'control') {
        $args += @('-RoutePackedCopy')
    }

    return [pscustomobject]@{
        arm = $Arm
        repeat_index = $RepeatIndex
        tag = $childTag
        gate_kind = $gateKind
        result_path = (Join-Path $runs ('g7_' + $childTag + '_result.json'))
        harness_arguments = @($args)
    }
}

function Invoke-G127PChild {
    param([Parameter(Mandatory=$true)][object]$Plan)

    $bootstrapArgs = @{
        HarnessPath = $harness
        RepoRoot = $root
        HarnessArguments = @($Plan.harness_arguments)
    }
    if ($WhatIf) {
        $bootstrapArgs.WhatIf = $true
        Write-Host ('[g127p] WHATIF child=' + $Plan.tag +
            ' arm=' + $Plan.arm)
        & $bootstrap @bootstrapArgs
        return
    }
    $resultExists = Test-Path -LiteralPath $Plan.result_path -PathType Leaf
    if ($ResumeBatchTag -and $Plan.arm -eq 'safety') {
        if (-not $resultExists) {
            throw ('G127P resume requires existing candidate safety result: ' +
                $Plan.result_path)
        }
        Write-Host ('[g127p] reuse and validate completed safety=' + $Plan.tag)
        return
    }
    if ($resultExists) {
        if ($ResumeBatchTag) {
            Write-Host ('[g127p] reuse completed child=' + $Plan.tag)
            return
        }
        throw "G127P child result already exists: $($Plan.result_path)"
    }
    if ($InterChildCooldownSec -gt 0) {
        Start-Sleep -Seconds $InterChildCooldownSec
    }
    Write-Host ('[g127p] launch child=' + $Plan.tag +
        ' arm=' + $Plan.arm)
    & $bootstrap @bootstrapArgs
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw ('G127P child failed with exit code ' + $LASTEXITCODE +
            ': ' + $Plan.tag)
    }
    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G127P child result missing: $($Plan.result_path)"
    }
}

function Assert-G127PSharedResult {
    param(
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][object]$Json
    )

    $samples = @($Json.results)
    if ([int]$Json.repeats -ne 1 -or $samples.Count -ne 1 -or
        [string]$Json.gate_kind -ne $Plan.gate_kind -or
        [int]$Json.server_exit_code -ne 0 -or
        [string]$samples[0].content_sha256 -ine $expectedContentSHA -or
        [string]$Json.expected_content_sha256 -ine $expectedContentSHA -or
        [string]$Json.prompt_sha256 -ine $promptSHA -or
        [string]$Json.model_sha256 -ine $modelSHA -or
        [string]$Json.nested_residual_sidecar_sha256 -ine $sidecarSHA -or
        [string]$Json.nested_residual_expected_payload_sha256 -ine
            $payloadSHA -or
        [int]$Json.requested_max_tokens -ne 64 -or
        [int]$Json.context_requested -ne 256 -or
        [double]$Json.dynamic_arena_gib_requested -ne $arenaGiB -or
        [int]$Json.expert_cache_requested -ne 320 -or
        -not [bool]$Json.compose_prefill_mass_open_router_requested -or
        [int]$Json.expert_tiering.compose_router_open -ne 1 -or
        [string]$Json.reap_mask_file_requested -or
        [bool]$Json.embedded_bake_mask_observed) {
        throw "G127P shared exact/provenance/open-router gate failed: $($Plan.tag)"
    }
    if ([string]$Json.head -ine $currentBuild.build_head -or
        [string]$Json.executable_sha256 -ine
            $currentBuild.executable_sha256 -or
        [string]$Json.build_manifest_sha256 -ine
            $currentBuild.manifest_sha256 -or
        [string]$Json.build_manifest_input_fingerprint_sha256 -ine
            $currentBuild.input_fingerprint_sha256 -or
        [string]$Json.build_manifest_head -ine $currentBuild.build_head -or
        [bool]$Json.build_manifest_worktree_dirty_at_build_start -ne
            [bool]$currentBuild.build_worktree_dirty_at_build_start -or
        [string]$Json.harness_sha256 -ine $currentBuild.harness_sha256) {
        throw "G127P child build provenance gate failed: $($Plan.tag)"
    }
    if ($Plan.gate_kind -eq 'benchmark') {
        if ([string]$Json.nested_residual_gpu_join_safety_receipt_sha256 -ine
                $g127SafetyContract.receipt_sha256 -or
            [string]$Json.nested_residual_gpu_join_safety_result_sha256 -ine
                $g127SafetyContract.result_sha256 -or
            -not [bool]$Json.nested_residual_gpu_join_safety_receipt_validated) {
            throw "G127P child G127 safety provenance gate failed: $($Plan.tag)"
        }
    } elseif ([string]$Json.nested_residual_gpu_join_safety_receipt_sha256 -or
        [bool]$Json.nested_residual_gpu_join_safety_receipt_validated) {
        throw "G127P structural safety unexpectedly reused G127 receipt: $($Plan.tag)"
    }
    if (-not [bool]$Json.nested_residual_gpu_join_requested -or
        -not [bool]$Json.nested_residual_gpu_join_observed -or
        [UInt64]$Json.nested_residual_gpu_join_calls -eq 0 -or
        [UInt64]$Json.nested_residual_gpu_join_failures -ne 0 -or
        [UInt64]$Json.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
        [UInt64]$Json.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
        [UInt64]$Json.nested_residual_gpu_join_verify_mismatches -ne 0 -or
        [UInt64]$Json.nested_residual_failures -ne 0 -or
        [UInt64]$Json.nested_residual_mismatches -ne 0 -or
        [UInt64]$Json.nested_residual_vram_failures -ne 0 -or
        [UInt64]$Json.moe_overlapped_io_fallbacks -ne 0 -or
        -not [bool]$Json.nested_residual_gpu_join_residual_cache_requested -or
        -not [bool]$Json.nested_residual_gpu_join_residual_cache_observed -or
        [int]$Json.nested_residual_gpu_join_residual_cache_enabled_runtime -ne 1 -or
        [UInt64]$Json.nested_residual_gpu_join_residual_cache_invariant_failures -ne 0) {
        throw "G127P nested GPU-join/residual-cache gate failed: $($Plan.tag)"
    }
    $preflight = $Json.system_quiescence_preflight
    $failures = @()
    if ($null -ne $preflight -and $null -ne $preflight.failures) {
        $failures = @($preflight.failures)
    }
    $runtimePeak = 0
    if ($null -ne $Json.runtime_telemetry -and
        $null -ne $Json.runtime_telemetry.contamination_consecutive_peak) {
        $runtimePeak =
            [int]$Json.runtime_telemetry.contamination_consecutive_peak
    }
    if ($null -eq $preflight -or
        -not [bool]$preflight.ready_to_launch -or
        [bool]$preflight.skipped -or
        $failures.Count -ne 0 -or
        $runtimePeak -ne 0) {
        throw "G127P quiescence gate failed: $($Plan.tag)"
    }
}

function Assert-G127PRoutePackedCopy {
    param(
        [Parameter(Mandatory=$true)][object]$Plan,
        [Parameter(Mandatory=$true)][object]$Json
    )

    if ($Plan.arm -eq 'control') {
        if ([bool]$Json.route_packed_copy_requested -or
            [bool]$Json.route_packed_copy_observed -or
            [int]$Json.route_packed_copy_runtime_requested -ne 0 -or
            [UInt64]$Json.route_packed_copy_experts -ne 0 -or
            [UInt64]$Json.route_packed_copy_submissions -ne 0 -or
            [UInt64]$Json.route_packed_copy_bytes -ne 0 -or
            [UInt64]$Json.route_packed_copy_legacy_submissions -eq 0) {
            throw "G127P control packed-copy gate failed: $($Plan.tag)"
        }
        return
    }

    $experts = [UInt64]$Json.route_packed_copy_experts
    $submissions = [UInt64]$Json.route_packed_copy_submissions
    $missExperts = [UInt64]$Json.gpu_resident_routes_miss_experts
    $nestedMisses = [UInt64]$Json.nested_residual_vram_misses
    if ($missExperts -lt $nestedMisses) {
        throw "G127P candidate packed-copy underflow gate failed: $($Plan.tag)"
    }
    $expectedPackedExperts = $missExperts - $nestedMisses
    if (-not [bool]$Json.route_packed_copy_requested -or
        -not [bool]$Json.route_packed_copy_observed -or
        [int]$Json.route_packed_copy_runtime_requested -ne 1 -or
        $experts -eq 0 -or
        $submissions -ne (2 * $experts) -or
        [UInt64]$Json.route_packed_copy_bytes -eq 0 -or
        [UInt64]$Json.route_packed_copy_legacy_submissions -ne 0 -or
        $expectedPackedExperts -ne $experts) {
        throw "G127P candidate hetero packed-copy gate failed: $($Plan.tag)"
    }
}

function Read-G127PChildResult {
    param([Parameter(Mandatory=$true)][object]$Plan)

    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G127P child result missing during validation: $($Plan.result_path)"
    }
    $resolvedResult = (Resolve-Path -LiteralPath $Plan.result_path).Path
    $resultSHA = (Get-FileHash -LiteralPath $resolvedResult `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    $json = Get-Content -LiteralPath $resolvedResult -Raw |
        ConvertFrom-Json
    $resultSHAAfterRead = (Get-FileHash -LiteralPath $resolvedResult `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($resultSHAAfterRead -ine $resultSHA) {
        throw "G127P child result changed while validating: $($Plan.tag)"
    }
    Assert-G127PSharedResult -Plan $Plan -Json $json
    Assert-G127PRoutePackedCopy -Plan $Plan -Json $json
    $sample = @($json.results)[0]
    return [pscustomobject]@{
        arm = $Plan.arm
        order_position = [int]$Plan.order_position
        repeat_index = [int]$Plan.repeat_index
        tag = $Plan.tag
        gate_kind = $Plan.gate_kind
        result_path = $resolvedResult
        result_sha256 = $resultSHA
        exact = $true
        uncontaminated = $true
        tokens_per_second = [double]$sample.tokens_per_second
        server_decode_mean_tokens_per_second =
            [double]$json.server_decode_mean_tokens_per_second
        server_prefill_ttft_mean_seconds =
            [double]$json.server_prefill_ttft_mean_seconds
        route_packed_copy_requested =
            [bool]$json.route_packed_copy_requested
        route_packed_copy_observed = [bool]$json.route_packed_copy_observed
        route_packed_copy_experts =
            [UInt64]$json.route_packed_copy_experts
        route_packed_copy_submissions =
            [UInt64]$json.route_packed_copy_submissions
        route_packed_copy_bytes =
            [UInt64]$json.route_packed_copy_bytes
        route_packed_copy_legacy_submissions =
            [UInt64]$json.route_packed_copy_legacy_submissions
        gpu_resident_routes_miss_experts =
            [UInt64]$json.gpu_resident_routes_miss_experts
        nested_residual_vram_misses =
            [UInt64]$json.nested_residual_vram_misses
        nested_residual_gpu_join_calls =
            [UInt64]$json.nested_residual_gpu_join_calls
        residual_cache_hits =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_hits
        residual_cache_misses =
            [UInt64]$json.nested_residual_gpu_join_residual_cache_misses
    }
}

function Get-G127PMean {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return $null }
    return ([double](($Values | Measure-Object -Sum).Sum) /
        [double]$Values.Count)
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G127P required script missing: $path"
    }
}
if ((Get-G127PSha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G127P prompt SHA-256 mismatch'
}

$currentBuild = $null
$g127SafetyContract = $null
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar,
            $sidecarReceipt, $G127SafetyReceipt, $exe,
            $buildManifestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G127P required file missing: $path"
        }
    }
    $currentBuild = Get-G127PCurrentBuildContract
    $g127SafetyContract = Assert-G127PSafetyReceipt `
        -ReceiptPath $G127SafetyReceipt `
        -ExpectedReceiptSHA $ExpectedG127SafetyReceiptSHA256 `
        -CurrentBuild $currentBuild
    $g127SafetyReceiptForChildren = $g127SafetyContract.receipt_path
    $g127SafetyReceiptSHAForChildren =
        $g127SafetyContract.receipt_sha256
}

$batchTag = if ($ResumeBatchTag) {
    $ResumeBatchTag
} else {
    $Tag + '_' + (New-G127PSuffix)
}
$order = @(
    [pscustomobject]@{ arm = 'safety'; repeat_index = 0 },
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
    $plan = New-G127PChildPlan -Arm $entry.arm `
        -RepeatIndex $entry.repeat_index -BatchTag $batchTag
    $plan | Add-Member -NotePropertyName order_position `
        -NotePropertyValue $position
    $plans += $plan
}

if ($WhatIf) {
    [pscustomobject]@{
        schema = 'g127p_hetero_route_packed_copy_ab_plan_v1'
        status = 'whatif_no_runtime'
        batch_tag = $batchTag
        resume_batch_tag = $ResumeBatchTag
        expected_content_sha256 = $expectedContentSHA
        prompt_sha256 = $promptSHA
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
                gate_kind = $_.gate_kind
                result_path = $_.result_path
                harness_arguments = @($_.harness_arguments)
            }
        })
    } | ConvertTo-Json -Depth 8
    foreach ($plan in $plans) { Invoke-G127PChild -Plan $plan }
    return
}

$rows = @()
$safetyPlan = @($plans | Where-Object { $_.arm -eq 'safety' })[0]
Invoke-G127PChild -Plan $safetyPlan
$rows += Read-G127PChildResult -Plan $safetyPlan
Assert-G127PAggregateProvenance -ExpectedBuild $currentBuild `
    -ExpectedSafety $g127SafetyContract -Phase 'before benchmark launch'

$benchmarkPlans = @($plans | Where-Object { $_.arm -ne 'safety' })
foreach ($plan in $benchmarkPlans) {
    Invoke-G127PChild -Plan $plan
    $rows += Read-G127PChildResult -Plan $plan
}
Assert-G127PAggregateProvenance -ExpectedBuild $currentBuild `
    -ExpectedSafety $g127SafetyContract -Phase 'final aggregate'
$safetyRows = @($rows | Where-Object { $_.arm -eq 'safety' })
$controlRows = @($rows | Where-Object { $_.arm -eq 'control' })
$candidateRows = @($rows | Where-Object { $_.arm -eq 'candidate' })
if ($safetyRows.Count -ne 1 -or
    $controlRows.Count -ne 3 -or
    $candidateRows.Count -ne 3) {
    throw 'G127P did not collect safety + n3 per arm'
}

$controlDecode = [double[]]@(
    $controlRows | ForEach-Object { $_.server_decode_mean_tokens_per_second })
$candidateDecode = [double[]]@(
    $candidateRows | ForEach-Object { $_.server_decode_mean_tokens_per_second })
$controlMean = Get-G127PMean $controlDecode
$candidateMean = Get-G127PMean $candidateDecode
$decodeRatio = $candidateMean / $controlMean
$controlSpread = ([double](($controlDecode | Measure-Object -Maximum).Maximum) /
    [double](($controlDecode | Measure-Object -Minimum).Minimum))
$candidateSpread = ([double](($candidateDecode | Measure-Object -Maximum).Maximum) /
    [double](($candidateDecode | Measure-Object -Minimum).Minimum))
$needsOutlierExtension = ($controlSpread -gt 1.20 -or
    $candidateSpread -gt 1.20)

$resultPath = Join-Path $runs ('g7_' + $batchTag + '_result.json')
$result = [ordered]@{
    schema = 'g127p_hetero_route_packed_copy_ab_result_v1'
    batch_tag = $batchTag
    status = if ($needsOutlierExtension) {
        'needs_outlier_extension'
    } else {
        'pass_n3_no_quality_verdict'
    }
    claim_scope = 'g127_full_open_residual_cache_plus_hetero_route_packed_copy'
    n3_valid = (-not $needsOutlierExtension)
    expected_content_sha256 = $expectedContentSHA
    prompt_sha256 = $promptSHA
    model_sha256 = $modelSHA
    sidecar_sha256 = $sidecarSHA
    sidecar_payload_sha256 = $payloadSHA
    g127_safety_receipt = $g127SafetyContract.receipt_path
    g127_safety_receipt_sha256 = $g127SafetyContract.receipt_sha256
    g127_safety_result = $g127SafetyContract.result_path
    g127_safety_result_sha256 = $g127SafetyContract.result_sha256
    g127_safety_configuration_sha256 =
        $g127SafetyContract.configuration_sha256
    aggregate_provenance = [ordered]@{
        build_head = $currentBuild.build_head
        build_worktree_dirty_at_build_start =
            $currentBuild.build_worktree_dirty_at_build_start
        executable_sha256 = $currentBuild.executable_sha256
        build_manifest_sha256 = $currentBuild.manifest_sha256
        build_manifest_input_fingerprint_sha256 =
            $currentBuild.input_fingerprint_sha256
        harness_sha256 = $currentBuild.harness_sha256
        bootstrap_sha256 = $currentBuild.bootstrap_sha256
        outer_runner_sha256 = $currentBuild.outer_runner_sha256
        g127_safety_receipt_sha256 =
            $g127SafetyContract.receipt_sha256
        pre_benchmark_verified = $true
        final_verified = $true
    }
    order = @($plans | ForEach-Object {
        [pscustomobject]@{
            order_position = $_.order_position
            arm = $_.arm
            repeat_index = $_.repeat_index
            tag = $_.tag
            gate_kind = $_.gate_kind
        }
    })
    control_decode_tps_mean = $controlMean
    candidate_decode_tps_mean = $candidateMean
    relative_delta_decode_mean = ($decodeRatio - 1.0)
    outlier_rule = [ordered]@{
        threshold_ratio = 1.20
        control_max_min_ratio = $controlSpread
        candidate_max_min_ratio = $candidateSpread
        extension_required = $needsOutlierExtension
    }
    rows = @($rows)
}
$result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Host ('[g127p] result=' + $resultPath +
    ' status=' + $result.status)
