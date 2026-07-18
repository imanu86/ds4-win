# G126 nested residual n=3 A/B: CPU reconstruction join vs exact GPU join.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g126_nested_gpu_join_ab',
    [ValidatePattern('^$|^[A-Za-z0-9_-]+$')]
    [string]$ResumeBatchTag = '',
    [ValidateRange(0, 600)][int]$InterChildCooldownSec = 30,
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
$sidecarBytes = [UInt64]3221226880
$sidecarSHA = '07199bc5503aa6e2dea10f702c1ca9e8f05a5bf466a56cbed031f6a5fca4bdf9'
$payloadSHA = '02c8cb248a8184e365e2e486653484165db39402fd28320ba621fb4fdb3f7bd8'
$safetyReceipt = Join-Path $runs 'g7_g125_nested_gpu_join_safety_current_build_clean_20260718T182935501Z_eb824ebedb_receipt.json'
$safetyReceiptSHA = 'ae15a6d3d3bc35e75b46befd8d18d7886f571e47d93561d146ada3ccf20f58fb'
$expectedContentSHA = 'fd6c4522975a71e252b90199d49cfe3236310e2a7285dc0fc4d0e9d0e4885510'
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$arenaGiB = 25.828125
$nestedBaseGiB = 3.75
$nestedExactCacheGiB = 0.421875
$hostBudgetGiB = 30.0

function Get-G126Sha256Text {
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

function New-G126Suffix {
    return ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
        '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
}

function Get-G126Mean {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sum = 0.0
    foreach ($value in $Values) { $sum += [double]$value }
    return $sum / [double]$Values.Count
}

function Get-G126Median {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function New-G126CommonHarnessArguments {
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

function New-G126ChildPlan {
    param(
        [ValidateSet('cpu_join', 'gpu_join')][string]$Arm,
        [int]$RepeatIndex,
        [string]$BatchTag
    )

    $childTag = $BatchTag + '_' + $Arm + '_r' + $RepeatIndex
    $args = @(New-G126CommonHarnessArguments -ChildTag $childTag)
    if ($Arm -eq 'gpu_join') {
        $args += @(
            '-NestedResidualGpuJoin',
            '-NestedResidualGpuJoinSafetyReceipt', $safetyReceipt,
            '-ExpectedNestedResidualGpuJoinSafetyReceiptSHA256',
                $safetyReceiptSHA
        )
    }

    return [pscustomobject]@{
        arm = $Arm
        repeat_index = $RepeatIndex
        tag = $childTag
        result_path = (Join-Path $runs ('g7_' + $childTag + '_result.json'))
        harness_arguments = @($args)
    }
}

function Invoke-G126Child {
    param([Parameter(Mandatory=$true)][object]$Plan)

    $bootstrapArgs = @{
        HarnessPath = $harness
        RepoRoot = $root
        HarnessArguments = @($Plan.harness_arguments)
    }
    if ($WhatIf) {
        $bootstrapArgs.WhatIf = $true
        Write-Host ('[g126] WHATIF child=' + $Plan.tag + ' arm=' + $Plan.arm)
        & $bootstrap @bootstrapArgs
        return
    }

    if (Test-Path -LiteralPath $Plan.result_path -PathType Leaf) {
        if ($ResumeBatchTag) {
            Write-Host ('[g126] reuse completed child=' + $Plan.tag)
            return
        }
        throw "G126 child result already exists for immutable tag: $($Plan.result_path)"
    }
    if ($InterChildCooldownSec -gt 0) {
        Write-Host ('[g126] cooldown seconds=' + $InterChildCooldownSec +
            ' before child=' + $Plan.tag)
        Start-Sleep -Seconds $InterChildCooldownSec
    }
    Write-Host ('[g126] launch child=' + $Plan.tag + ' arm=' + $Plan.arm)
    & $bootstrap @bootstrapArgs
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw ('G126 child failed with exit code ' + $LASTEXITCODE + ': ' +
            $Plan.tag)
    }
    if (-not (Test-Path -LiteralPath $Plan.result_path -PathType Leaf)) {
        throw "G126 child result missing: $($Plan.result_path)"
    }
}

function Read-G126ChildResult {
    param([Parameter(Mandatory=$true)][object]$Plan)

    $json = Get-Content -LiteralPath $Plan.result_path -Raw | ConvertFrom-Json
    $samples = @($json.results)
    if ([int]$json.repeats -ne 1 -or $samples.Count -ne 1) {
        throw "G126 child must be exactly one independent request: $($Plan.tag)"
    }
    $sample = $samples[0]
    if ([string]$sample.content_sha256 -ne $expectedContentSHA -or
        [string]$json.expected_content_sha256 -ne $expectedContentSHA -or
        [string]$json.prompt_sha256 -ne $promptSHA) {
        throw "G126 exact prompt/output contract mismatch for $($Plan.tag)"
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
        throw "G126 nested residual benchmark contract mismatch for $($Plan.tag)"
    }

    if ($Plan.arm -eq 'gpu_join') {
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
                $safetyReceiptSHA -or
            [string]$json.nested_residual_gpu_join_safety_receipt_path -ine
                $safetyReceipt -or
            [UInt64]$json.nested_residual_vram_host_fills -ne 0 -or
            [UInt64]$json.nested_residual_vram_host_bytes -ne 0 -or
            [UInt64]$json.nested_residual_vram_h2d_bytes -ne
                ([UInt64]$json.nested_residual_vram_misses * [UInt64]7077888)) {
            throw "G126 GPU-join contract mismatch for $($Plan.tag)"
        }
    } else {
        if ([bool]$json.nested_residual_gpu_join_requested -or
            [bool]$json.nested_residual_gpu_join_observed -or
            [int]$json.nested_residual_gpu_join_requested_runtime -ne 0 -or
            [int]$json.nested_residual_gpu_join_observed_runtime -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_calls -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_blocks -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_base_h2d_bytes -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_residual_h2d_bytes -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_native_h2d_bytes -ne 0 -or
            [double]$json.nested_residual_gpu_join_seconds -ne 0.0 -or
            [UInt64]$json.nested_residual_gpu_join_wait_calls -ne 0 -or
            [double]$json.nested_residual_gpu_join_wait_seconds -ne 0.0 -or
            [UInt64]$json.nested_residual_gpu_join_verify_calls -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_verify_bytes -ne 0 -or
            [double]$json.nested_residual_gpu_join_verify_seconds -ne 0.0 -or
            [UInt64]$json.nested_residual_gpu_join_verify_mismatches -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_failures -ne 0 -or
            [UInt64]$json.nested_residual_gpu_join_cpu_reconstruct_calls -ne 0 -or
            [bool]$json.nested_residual_gpu_join_safety_receipt_validated -or
            [string]$json.nested_residual_gpu_join_safety_receipt_sha256 -or
            [UInt64]$json.nested_residual_vram_host_fills -ne
                [UInt64]$json.nested_residual_vram_misses -or
            [UInt64]$json.nested_residual_vram_host_bytes -ne
                ([UInt64]$json.nested_residual_vram_misses * [UInt64]7077888) -or
            [UInt64]$json.nested_residual_vram_h2d_bytes -ne
                ([UInt64]$json.nested_residual_vram_misses * [UInt64]7077888)) {
            throw "G126 CPU-join contract mismatch for $($Plan.tag)"
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
        aggregate_disk_read_gib =
            [math]::Round(
                [double]$json.runtime_telemetry.aggregate_disk_read_bytes_estimated /
                    1GB, 6)
        contamination_peak = $runtimePeak
        preflight_failures = $failures.Count
    }
}

function New-G126ArmSummary {
    param([Parameter(Mandatory=$true)][object[]]$Rows)

    $e2e = [double[]]@($Rows | ForEach-Object { $_.tokens_per_second })
    $decode = [double[]]@(
        $Rows | ForEach-Object { $_.server_decode_mean_tokens_per_second })
    $ttft = [double[]]@(
        $Rows | ForEach-Object { $_.server_prefill_ttft_mean_seconds })
    return [pscustomobject]@{
        count = $Rows.Count
        e2e_tps_mean = Get-G126Mean $e2e
        e2e_tps_median = Get-G126Median $e2e
        server_decode_tps_mean = Get-G126Mean $decode
        server_decode_tps_median = Get-G126Median $decode
        ttft_seconds_mean = Get-G126Mean $ttft
        ttft_seconds_median = Get-G126Median $ttft
    }
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G126 required script missing: $path"
    }
}
if ((Get-G126Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G126 prompt SHA-256 mismatch'
}
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar,
            $sidecarReceipt, $safetyReceipt)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G126 required file missing: $path"
        }
    }
    if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne $sidecarBytes) {
        throw 'G126 sidecar size mismatch'
    }
    $observedSafetySHA =
        (Get-FileHash -LiteralPath $safetyReceipt -Algorithm SHA256).
            Hash.ToLowerInvariant()
    if ($observedSafetySHA -ine $safetyReceiptSHA) {
        throw 'G126 G125 safety receipt SHA mismatch'
    }
}

$modelLock = $null
$sidecarLock = $null
$safetyLock = $null
try {
    if (-not $WhatIf) {
        $modelLock = [IO.File]::Open(
            $model, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $sidecarLock = [IO.File]::Open(
            $sidecar, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $safetyLock = [IO.File]::Open(
            $safetyReceipt, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read)
    }

    $batchTag = if ($ResumeBatchTag) {
        $ResumeBatchTag
    } else {
        $Tag + '_' + (New-G126Suffix)
    }
    $order = @(
        [pscustomobject]@{ arm = 'cpu_join'; repeat_index = 1 },
        [pscustomobject]@{ arm = 'gpu_join'; repeat_index = 1 },
        [pscustomobject]@{ arm = 'gpu_join'; repeat_index = 2 },
        [pscustomobject]@{ arm = 'cpu_join'; repeat_index = 2 },
        [pscustomobject]@{ arm = 'cpu_join'; repeat_index = 3 },
        [pscustomobject]@{ arm = 'gpu_join'; repeat_index = 3 }
    )
    $plans = @()
    $position = 0
    foreach ($entry in $order) {
        $position += 1
        $plan = New-G126ChildPlan -Arm $entry.arm `
            -RepeatIndex $entry.repeat_index -BatchTag $batchTag
        $plan | Add-Member -NotePropertyName order_position `
            -NotePropertyValue $position
        $plans += $plan
    }

    if ($WhatIf) {
        [pscustomobject]@{
            schema = 'g126_nested_gpu_join_ab_plan_v1'
            batch_tag = $batchTag
            resume_batch_tag = $ResumeBatchTag
            inter_child_cooldown_seconds = $InterChildCooldownSec
            expected_content_sha256 = $expectedContentSHA
            prompt_sha256 = $promptSHA
            g125_safety_receipt = $safetyReceipt
            g125_safety_receipt_sha256 = $safetyReceiptSHA
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
        foreach ($plan in $plans) { Invoke-G126Child -Plan $plan }
        return
    }

    foreach ($plan in $plans) { Invoke-G126Child -Plan $plan }

    $rows = @()
    foreach ($plan in $plans) { $rows += Read-G126ChildResult -Plan $plan }
    $cpuRows = @($rows | Where-Object { $_.arm -eq 'cpu_join' })
    $gpuRows = @($rows | Where-Object { $_.arm -eq 'gpu_join' })
    if ($cpuRows.Count -ne 3 -or $gpuRows.Count -ne 3) {
        throw 'G126 did not collect exactly 3 CPU and 3 GPU rows'
    }
    $allValid = (@($rows | Where-Object {
                -not $_.exact -or -not $_.uncontaminated
            }).Count -eq 0)
    if (-not $allValid) {
        throw 'G126 n>=3 verdict invalid: exactness or contamination gate failed'
    }

    $cpuSummary = New-G126ArmSummary -Rows $cpuRows
    $gpuSummary = New-G126ArmSummary -Rows $gpuRows
    $deltaE2E =
        ([double]$gpuSummary.e2e_tps_mean /
         [double]$cpuSummary.e2e_tps_mean) - 1.0
    $deltaDecode =
        ([double]$gpuSummary.server_decode_tps_mean /
         [double]$cpuSummary.server_decode_tps_mean) - 1.0

    $resultPath = Join-Path $runs ('g7_' + $batchTag + '_result.json')
    $result = [ordered]@{
        schema = 'g126_nested_gpu_join_ab_result_v1'
        batch_tag = $batchTag
        status = 'pass'
        claim_scope = 'n3_nested_residual_cpu_join_vs_gpu_join_ab'
        n3_valid = $true
        expected_content_sha256 = $expectedContentSHA
        prompt = $prompt
        prompt_sha256 = $promptSHA
        model = $model
        model_sha256 = $modelSHA
        sidecar = $sidecar
        sidecar_sha256 = $sidecarSHA
        sidecar_payload_sha256 = $payloadSHA
        g125_safety_receipt = $safetyReceipt
        g125_safety_receipt_sha256 = $safetyReceiptSHA
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
        cpu_join = $cpuSummary
        gpu_join = $gpuSummary
        relative_delta = [ordered]@{
            e2e_tps_mean = $deltaE2E
            server_decode_tps_mean = $deltaDecode
        }
        rows = @($rows)
    }
    $result | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host ('[g126] PASS result=' + $resultPath +
        ' e2e_delta=' + [math]::Round($deltaE2E * 100.0, 3) + '%' +
        ' decode_delta=' + [math]::Round($deltaDecode * 100.0, 3) + '%')
} finally {
    if ($null -ne $safetyLock) { $safetyLock.Dispose() }
    if ($null -ne $sidecarLock) { $sidecarLock.Dispose() }
    if ($null -ne $modelLock) { $modelLock.Dispose() }
}
