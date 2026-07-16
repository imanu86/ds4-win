# G70 G46 wave reclaim A/B runner (PowerShell 5.1, ASCII).
param(
    [switch]$Resume,
    [switch]$SummarizeExisting
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$summaryPath = Join-Path $outdir "g70_g46_wave_reclaim_ab_result.json"
$waveGiB = 4.0
$arenaGiB = 30.0
$expectedArenaSlots = 4551
$expectedCacheCapacity = 320

function Get-G70Mean {
    param([object[]]$Rows, [string]$Property)
    if ($Rows.Count -eq 0) { return $null }
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Get-G70Median {
    param([object[]]$Rows, [string]$Property)
    $values = @($Rows | ForEach-Object { [double]($_.$Property) } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($values.Count / 2.0)
    if (($values.Count % 2) -eq 1) {
        return [math]::Round($values[$middle], 6)
    }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2.0, 6)
}

function Get-G70ResultPath {
    param([string]$Tag)
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G70PropertyValue {
    param([object]$Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Test-G70CapacityFailure {
    param([string]$Message, [string]$Tag)

    $resultPath = Get-G70ResultPath $Tag
    if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            $arenaCapped = [bool](Get-G70PropertyValue -Object $result `
                -Name "dynamic_arena_cap_capped" -Default $false)
            $arenaSlots = [int](Get-G70PropertyValue -Object $result `
                -Name "dynamic_arena_allocated_slots" -Default 0)
            $runtimeAborted = [bool](Get-G70PropertyValue `
                -Object $result.runtime_telemetry `
                -Name "contamination_abort_observed" -Default $false)
            $runtimeAvailable = [uint64](Get-G70PropertyValue `
                -Object $result.runtime_telemetry `
                -Name "windows_available_min_bytes" -Default ([uint64]::MaxValue))
            if ($arenaCapped -or $arenaSlots -lt $expectedArenaSlots -or
                ($runtimeAborted -and $runtimeAvailable -lt 2GB)) {
                return $true
            }
        } catch {
            # Fall through to the primary preflight/runtime artifacts.
        }
    }

    $memoryPath = Join-Path $outdir ("g7_" + $Tag + "_memory_preflight.json")
    if (Test-Path -LiteralPath $memoryPath -PathType Leaf) {
        try {
            $memory = Get-Content -LiteralPath $memoryPath -Raw | ConvertFrom-Json
            if (-not $memory.ready_to_launch -and
                [string]$memory.failure_message -match "memory|available|RAM") {
                return $true
            }
        } catch {
            # A malformed artifact is a generic failure, never a capacity claim.
        }
    }

    $runtimePath = Join-Path $outdir ("g7_" + $Tag + "_runtime_telemetry.jsonl")
    if (Test-Path -LiteralPath $runtimePath -PathType Leaf) {
        try {
            $abort = Get-Content -LiteralPath $runtimePath | ForEach-Object {
                $sample = $_ | ConvertFrom-Json
                if ($sample.contamination_abort -and
                    [uint64]$sample.windows_available_bytes -lt 2GB) {
                    $sample
                }
            } | Select-Object -Last 1
            if ($null -ne $abort) { return $true }
        } catch {
            # Do not infer capacity from an unreadable telemetry stream.
        }
    }

    if (-not $Message) { return $false }
    return ($Message -match "Memory preflight refused launch:.*(memory|available|RAM)" -or
            $Message -match "Runtime telemetry aborted.*low RAM" -or
            $Message -match "arena-cap.*(allocation|capacity|memory|guard)" -or
            $Message -match "dynamic arena.*(allocation|capacity|memory|guard)")
}

function Assert-G70CommonContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("legacy","candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][bool]$Safety
    )

    $tier = $Result.expert_tiering
    $expectedUnlock = ($Arm -eq "candidate")
    $maxWaveBytes = [uint64]([double]$waveGiB * 1GB)

    if (-not $Result.outputs_identical -or
        $Result.expected_content_sha256 -ne $expected -or
        $Result.results.Count -ne 1 -or
        $Result.results[0].content_sha256 -ne $expected -or
        $Result.requested_max_tokens -ne 64 -or
        $Result.context_requested -ne 256 -or
        $Result.reserve_mb -ne 1024 -or
        [math]::Abs([double]$Result.dynamic_arena_gib_requested - $arenaGiB) -gt 0.001 -or
        $Result.dynamic_arena_allocated_slots -ne $expectedArenaSlots -or
        $Result.expert_cache_requested -ne $expectedCacheCapacity -or
        $Result.expert_cache_capacity -ne $expectedCacheCapacity -or
        $Result.expert_cache_reserve_gb -ne 0.125 -or
        -not $Result.gpu_resident_routes_requested -or
        -not $Result.gpu_resident_routes_observed -or
        -not $Result.route_no_default_sync_requested -or
        $Result.gpu_resident_routes_default_sync_calls -ne 0 -or
        $Result.gpu_resident_routes_no_default_sync_calls -ne $Result.gpu_resident_routes_calls -or
        $Result.gpu_resident_routes_errors -ne 0 -or
        $Result.split_hit_miss_requested -or
        -not $Result.prefill_mass_wrap_observed -or
        $Result.prefill_mass_wrap_result -ne "published" -or
        $Result.prefill_mass_wrap_mask -ne "request-scoped-closed" -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        $tier.states_vram -ne $expectedCacheCapacity -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        -not $Result.memory_preflight.ready_to_launch -or
        -not $Result.process_isolation_preflight.ready_to_launch -or
        -not $Result.system_quiescence_preflight.ready_to_launch) {
        throw "G70 contract mismatch: tag=$Tag"
    }

    if ([bool]$Result.arena_wrap_unlock_source_ranges_requested -ne $expectedUnlock) {
        throw "G70 reclaim request mismatch: tag=$Tag"
    }

    if ($expectedUnlock) {
        if (-not $Result.arena_wrap_unlock_source_ranges_observed -or
            -not $Result.arena_wrap_unlock_source_ranges_summary_observed -or
            $Result.arena_wrap_unlock_source_ranges_summary_result -ne "complete" -or
            $Result.arena_wrap_unlock_source_ranges_summary_phases -ne 3 -or
            $Result.arena_wrap_unlock_source_ranges_summary_failed -ne 0 -or
            $Result.arena_wrap_unlock_source_ranges_summary_max_wave_bytes -gt $maxWaveBytes -or
            [math]::Abs([double]$Result.arena_wrap_unlock_wave_gib_observed - $waveGiB) -gt 0.000001 -or
            ($Result.arena_wrap_unlock_source_ranges_summary_true +
             $Result.arena_wrap_unlock_source_ranges_summary_error_not_locked) -ne
                $Result.arena_wrap_unlock_source_ranges_summary_calls) {
            throw "G70 candidate reclaim contract mismatch: tag=$Tag"
        }
    } elseif ($Result.arena_wrap_unlock_source_ranges_observed) {
        throw "G70 legacy unexpectedly reclaimed source ranges: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        safety = $Safety
        result_path = Get-G70ResultPath $Tag
        head = $Result.head
        executable_sha256 = $Result.executable_sha256
        ds4_cuda_sha256 = $Result.ds4_cuda_sha256
        ds4_c_sha256 = $Result.ds4_c_sha256
        build_manifest_sha256 = $Result.build_manifest_sha256
        build_input_fingerprint_sha256 = $Result.build_manifest_input_fingerprint_sha256
        harness_sha256 = $Result.harness_sha256
        model = $Result.model
        model_bytes = $Result.model_bytes
        model_last_write_utc = $Result.model_last_write_utc
        memory_preflight_available_gib = [math]::Round([double]$Result.memory_preflight.after.available_bytes / 1GB, 6)
        quiescence_cpu_median = $Result.system_quiescence_preflight.cpu_median_percent
        quiescence_disk_median = $Result.system_quiescence_preflight.disk_median_percent
        quiescence_disk_io_mibps_median = $Result.system_quiescence_preflight.disk_io_median_mib_per_second
        quiescence_gpu_median = $Result.system_quiescence_preflight.gpu_median_percent
        arena_slots = [int]$Result.dynamic_arena_allocated_slots
        arena_bytes = [uint64]$Result.dynamic_arena_allocated_bytes
        cache_capacity = [int]$Result.expert_cache_capacity
        ttft_seconds = [double]$Result.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$Result.prefill_mass_wrap_seconds
        ttft_minus_wrap_seconds = [math]::Round([double]$Result.server_prefill_ttft_mean_seconds - [double]$Result.prefill_mass_wrap_seconds, 6)
        decode_tokens_per_second = [double]$Result.server_decode_mean_tokens_per_second
        decode_seconds = [double]$Result.server_runs[0].server_decode_seconds
        route_calls = [uint64]$Result.gpu_resident_routes_calls
        default_sync_calls = [uint64]$Result.gpu_resident_routes_default_sync_calls
        no_default_sync_calls = [uint64]$Result.gpu_resident_routes_no_default_sync_calls
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = [math]::Round([uint64]$tier.ram_h2d_bytes / 1GB, 6)
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
        unlock_phases = [int]$Result.arena_wrap_unlock_source_ranges_summary_phases
        unlock_waves = [int]$Result.arena_wrap_unlock_source_ranges_summary_waves
        unlock_max_wave_bytes = [uint64]$Result.arena_wrap_unlock_source_ranges_summary_max_wave_bytes
        unlock_bytes_requested = [uint64]$Result.arena_wrap_unlock_source_ranges_summary_bytes_requested
        unlock_failed = [uint64]$Result.arena_wrap_unlock_source_ranges_summary_failed
        vram_peak_mib = [uint64]$Result.runtime_telemetry.vram_used_peak_mib
        available_min_gib = [math]::Round([uint64]$Result.runtime_telemetry.windows_available_min_bytes / 1GB, 6)
        disk_read_gib = [math]::Round([uint64](Get-G70PropertyValue $Result.runtime_telemetry "aggregate_disk_read_bytes_estimated" 0) / 1GB, 6)
        process_read_gib = [math]::Round([uint64]$Result.runtime_telemetry.win32_process_read_transfer_delta_bytes / 1GB, 6)
    }
}

function Invoke-G70Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("legacy","candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][bool]$Safety
    )

    $resultPath = Get-G70ResultPath $Tag
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1800",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync", "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru", "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "16", "-ExpertTierMinFrequency", "3",
        "-ExpertTierHysteresis", "1.25"
    )
    if ($Arm -eq "candidate") {
        $args += "-ArenaWrapUnlockSourceRanges"
        $args += "-ArenaWrapUnlockWaveGiB"
        $args += "4"
    }

    try {
        if ($Resume -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            Write-Host ("[g70] resume tag=" + $Tag + " arm=" + $Arm)
        } elseif ($SummarizeExisting) {
            throw "SummarizeExisting result missing: tag=$Tag"
        } else {
            Write-Host ("[g70] start tag=" + $Tag + " arm=" + $Arm)
            $nativeOutput = New-Object 'System.Collections.Generic.List[string]'
            & powershell.exe @args 2>&1 | ForEach-Object {
                $line = [string]$_
                $nativeOutput.Add($line)
                Write-Host $line
            }
            if ($LASTEXITCODE -ne 0) {
                $tail = [string]::Join(" | ", @($nativeOutput | Select-Object -Last 8))
                throw "G70 harness failed: tag=$Tag exit=$LASTEXITCODE output=$tail"
            }
        }

        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            throw "G70 result missing: tag=$Tag"
        }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        return Assert-G70CommonContract -Result $result -Tag $Tag -Arm $Arm -Safety $Safety
    } catch {
        $message = $_.Exception.Message
        [pscustomobject]@{
            tag = $Tag
            arm = $Arm
            safety = $Safety
            failed = $true
            capacity_failure = (Test-G70CapacityFailure -Message $message -Tag $Tag)
            message = $message
            result_path = $resultPath
        }
    }
}

function Assert-G70SameProvenance {
    param([object[]]$Rows)
    $provenanceFields = @(
        "head", "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
        "build_manifest_sha256", "build_input_fingerprint_sha256",
        "harness_sha256", "model", "model_bytes", "model_last_write_utc"
    )
    foreach ($field in $provenanceFields) {
        $values = @($Rows | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
        if ($values.Count -ne 1) { throw "G70 mixed provenance: field=$field" }
    }
}

function Test-G70Outlier {
    param([object[]]$Rows)
    foreach ($property in @("decode_tokens_per_second", "ttft_minus_wrap_seconds")) {
        foreach ($arm in @("legacy", "candidate")) {
            $armRows = @($Rows | Where-Object { $_.arm -eq $arm -and -not $_.safety })
            if ($armRows.Count -eq 0) { continue }
            if ($armRows.Count -lt 3) { return $false }
            $values = @($armRows | ForEach-Object { [double]($_.$property) } | Sort-Object)
            if ($values[0] -le 0.0) { return $true }
            if (($values[-1] / $values[0]) -gt 1.20) { return $true }
        }
    }
    return $false
}

function New-G70ArmSummary {
    param([object[]]$Rows)
    $summaries = @()
    foreach ($arm in @("legacy", "candidate")) {
        $armRows = @($Rows | Where-Object { $_.arm -eq $arm -and -not $_.safety })
        $summaries += [pscustomobject]@{
            arm = $arm
            independent_processes = $armRows.Count
            decode_tokens_per_second_mean = Get-G70Mean $armRows "decode_tokens_per_second"
            decode_tokens_per_second_median = Get-G70Median $armRows "decode_tokens_per_second"
            decode_seconds_mean = Get-G70Mean $armRows "decode_seconds"
            decode_seconds_median = Get-G70Median $armRows "decode_seconds"
            ttft_mean_seconds = Get-G70Mean $armRows "ttft_seconds"
            ttft_median_seconds = Get-G70Median $armRows "ttft_seconds"
            wrap_mean_seconds = Get-G70Mean $armRows "wrap_seconds"
            wrap_median_seconds = Get-G70Median $armRows "wrap_seconds"
            ttft_minus_wrap_mean_seconds = Get-G70Mean $armRows "ttft_minus_wrap_seconds"
            ram_h2d_gib_mean = Get-G70Mean $armRows "ram_h2d_gib"
            available_min_gib_min = if ($armRows.Count) { [math]::Round(($armRows | Measure-Object -Property available_min_gib -Minimum).Minimum, 6) } else { $null }
            process_read_gib_mean = Get-G70Mean $armRows "process_read_gib"
            disk_read_gib_mean = Get-G70Mean $armRows "disk_read_gib"
            snapshot_misses_sum = ($armRows | Measure-Object -Property snapshot_misses -Sum).Sum
            ssd_bytes_sum = ($armRows | Measure-Object -Property ssd_bytes -Sum).Sum
            failures_sum = ($armRows | Measure-Object -Property failures -Sum).Sum
        }
    }
    $summaries
}

function Write-G70Summary {
    param(
        [object[]]$Rows,
        [string]$Status,
        [string]$StopReason,
        [bool]$CapacityAsymmetry,
        [bool]$OutlierExtensionTriggered
    )
    $successful = @($Rows | Where-Object { -not $_.failed })
    $matrix = @($successful | Where-Object { -not $_.safety })
    if ($successful.Count -gt 0) { Assert-G70SameProvenance $successful }

    $summary = [pscustomobject]@{
        schema = "g70_g46_wave_reclaim_ab_v1"
        status = $Status
        stop_reason = $StopReason
        capacity_asymmetry_recorded = $CapacityAsymmetry
        performance_claim_allowed = ($Status -eq "matrix_complete" -and -not $CapacityAsymmetry -and $matrix.Count -ge 6)
        outlier_extension_triggered = $OutlierExtensionTriggered
        outlier_rule = "If either arm has >20% max/min spread in decode_tokens_per_second or ttft_minus_wrap_seconds after n=3, run exactly three additional independent processes per arm before any verdict."
        prompt = $prompt
        expected_content_sha256 = $expected
        model = $model
        context = 256
        max_tokens = 64
        arena_gib = $arenaGiB
        expected_arena_slots = $expectedArenaSlots
        expert_cache_capacity = $expectedCacheCapacity
        candidate_reclaim = [pscustomobject]@{
            arena_wrap_unlock_source_ranges = $true
            arena_wrap_unlock_wave_gib = $waveGiB
        }
        stop_conditions = @(
            "legacy_safety_capacity_failure => record capacity asymmetry; run candidate-only safety plus n=3; no A/B or causal performance claim",
            "legacy_safety_contract_failure => stop immediately; no matrix",
            "candidate_safety_failure => stop immediately; no matrix",
            "any matrix run contract/preflight/provenance mismatch => stop and mark invalid",
            "any expected content SHA mismatch => stop and mark invalid",
            "never issue a verdict from n=1 safety timing"
        )
        order = @($Rows | ForEach-Object { $_.tag })
        runs = $Rows
        arm_summary = New-G70ArmSummary $successful
        provenance = if ($successful.Count -gt 0) {
            [pscustomobject]@{
                head = $successful[0].head
                executable_sha256 = $successful[0].executable_sha256
                ds4_cuda_sha256 = $successful[0].ds4_cuda_sha256
                ds4_c_sha256 = $successful[0].ds4_c_sha256
                build_manifest_sha256 = $successful[0].build_manifest_sha256
                build_input_fingerprint_sha256 = $successful[0].build_input_fingerprint_sha256
                harness_sha256 = $successful[0].harness_sha256
                model = $successful[0].model
                model_bytes = $successful[0].model_bytes
                model_last_write_utc = $successful[0].model_last_write_utc
                runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } else { $null }
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $summaryPath
    Write-Host ("[g70] summary: " + $summaryPath)
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
$runs = @()
$outlierExtensionTriggered = $false

$legacySafety = Invoke-G70Run -Tag "g70_legacy_safety_exact" -Arm "legacy" -Safety $true
$runs += $legacySafety
$capacityAsymmetry = $false
if ($legacySafety.failed) {
    $capacityAsymmetry = [bool]$legacySafety.capacity_failure
    if (-not $capacityAsymmetry) {
        Write-G70Summary -Rows $runs -Status "stopped" -StopReason "legacy_safety_failed" -CapacityAsymmetry $false -OutlierExtensionTriggered $false
        exit 1
    }
    Write-Host "[g70] legacy capacity asymmetry recorded; candidate-only path remains descriptive"
}

$candidateSafety = Invoke-G70Run -Tag "g70_candidate_wave4_safety_exact" -Arm "candidate" -Safety $true
$runs += $candidateSafety
if ($candidateSafety.failed) {
    Write-G70Summary -Rows $runs -Status "stopped" -StopReason "candidate_safety_failed" -CapacityAsymmetry $capacityAsymmetry -OutlierExtensionTriggered $false
    exit 1
}

if ($capacityAsymmetry) {
    foreach ($suffix in @("a", "b", "c")) {
        $row = Invoke-G70Run -Tag ("g70_candidate_capacity_" + $suffix) -Arm "candidate" -Safety $false
        $runs += $row
        if ($row.failed) {
            Write-G70Summary -Rows $runs -Status "invalid" -StopReason ("candidate_only_run_failed:" + $row.tag) -CapacityAsymmetry $true -OutlierExtensionTriggered $outlierExtensionTriggered
            exit 1
        }
    }
    if (Test-G70Outlier @($runs | Where-Object { -not $_.failed })) {
        $outlierExtensionTriggered = $true
        foreach ($suffix in @("x1", "x2", "x3")) {
            $row = Invoke-G70Run -Tag ("g70_candidate_capacity_" + $suffix) -Arm "candidate" -Safety $false
            $runs += $row
            if ($row.failed) {
                Write-G70Summary -Rows $runs -Status "invalid" -StopReason ("candidate_only_extension_failed:" + $row.tag) -CapacityAsymmetry $true -OutlierExtensionTriggered $true
                exit 1
            }
        }
    }
    Write-G70Summary -Rows $runs -Status "candidate_only_complete" -StopReason "legacy_capacity_asymmetry_candidate_n3_descriptive" -CapacityAsymmetry $true -OutlierExtensionTriggered $outlierExtensionTriggered
    exit 0
}

$matrixPlan = @(
    @("g70_legacy_a", "legacy"),
    @("g70_candidate_a", "candidate"),
    @("g70_legacy_b", "legacy"),
    @("g70_candidate_b", "candidate"),
    @("g70_legacy_c", "legacy"),
    @("g70_candidate_c", "candidate")
)

foreach ($entry in $matrixPlan) {
    $row = Invoke-G70Run -Tag $entry[0] -Arm $entry[1] -Safety $false
    $runs += $row
    if ($row.failed) {
        Write-G70Summary -Rows $runs -Status "invalid" -StopReason ("matrix_run_failed:" + $row.tag) -CapacityAsymmetry $false -OutlierExtensionTriggered $outlierExtensionTriggered
        exit 1
    }
}

if (Test-G70Outlier @($runs | Where-Object { -not $_.failed })) {
    $outlierExtensionTriggered = $true
    $extensionPlan = @(
        @("g70_legacy_x1", "legacy"),
        @("g70_candidate_x1", "candidate"),
        @("g70_legacy_x2", "legacy"),
        @("g70_candidate_x2", "candidate"),
        @("g70_legacy_x3", "legacy"),
        @("g70_candidate_x3", "candidate")
    )
    foreach ($entry in $extensionPlan) {
        $row = Invoke-G70Run -Tag $entry[0] -Arm $entry[1] -Safety $false
        $runs += $row
        if ($row.failed) {
            Write-G70Summary -Rows $runs -Status "invalid" -StopReason ("outlier_extension_run_failed:" + $row.tag) -CapacityAsymmetry $false -OutlierExtensionTriggered $outlierExtensionTriggered
            exit 1
        }
    }
}

Write-G70Summary -Rows $runs -Status "matrix_complete" -StopReason "completed_preregistered_sequence" -CapacityAsymmetry $false -OutlierExtensionTriggered $outlierExtensionTriggered
