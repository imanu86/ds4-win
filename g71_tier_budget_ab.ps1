# G71 tier replacement-budget A/B runner (PowerShell 5.1, ASCII).
param(
    [switch]$Resume,
    [switch]$SummarizeExisting,
    [switch]$StaticCheckOnly
)

$ErrorActionPreference = "Stop"
$runnerPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root "g7_measure.ps1"
$outdir = Join-Path $root "g7_runs"
$model = "C:\ds4-models\ds4-2bit.gguf"
$prompt = "Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document."
$expected = "31cbc6504dcb57d42aeff9dbceb3aed943bcb32dae19a2edbf552e9fd2f52eb8"
$expectedPromptSha256 = "38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6"
$summaryPath = Join-Path $outdir "g71_tier_budget_ab_result.json"
$waveGiB = 4.0
$arenaGiB = 30.0
$expectedArenaSlots = 4551
$expectedCacheCapacity = 320
$controlBudget = 16
$candidateBudget = 32

function Get-G71Mean {
    param([object[]]$Rows, [string]$Property)
    if ($Rows.Count -eq 0) { return $null }
    [math]::Round(($Rows | Measure-Object -Property $Property -Average).Average, 6)
}

function Get-G71Median {
    param([object[]]$Rows, [string]$Property)
    $values = @($Rows | ForEach-Object { [double]($_.$Property) } | Sort-Object)
    if ($values.Count -eq 0) { return $null }
    $middle = [int][math]::Floor($values.Count / 2.0)
    if (($values.Count % 2) -eq 1) { return [math]::Round($values[$middle], 6) }
    [math]::Round(($values[$middle - 1] + $values[$middle]) / 2.0, 6)
}

function Get-G71ResultPath {
    param([string]$Tag)
    Join-Path $outdir ("g7_" + $Tag + "_result.json")
}

function Get-G71PropertyValue {
    param([object]$Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Get-G71Budget {
    param([Parameter(Mandatory=$true)][ValidateSet("control","candidate")][string]$Arm)
    if ($Arm -eq "candidate") { return $candidateBudget }
    return $controlBudget
}

function Assert-G71StaticContract {
    if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
        throw "G71 static check failed: harness missing: $harness"
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $runnerPath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("G71 static check failed: runner AST errors: " +
            (($errors | ForEach-Object { $_.Message }) -join " | "))
    }
    $harnessText = Get-Content -LiteralPath $harness -Raw
    foreach ($needle in @(
            "ExpertTierReplacementBudget",
            "ArenaWrapUnlockSourceRanges",
            "ComposePrefillMassTiering",
            "RouteNoDefaultSync")) {
        if ($harnessText -notmatch [regex]::Escape($needle)) {
            throw "G71 static check failed: harness lacks $needle"
        }
    }
}

function Test-G71CapacityFailure {
    param([string]$Message, [string]$Tag)

    $resultPath = Get-G71ResultPath $Tag
    if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            $arenaCapped = [bool](Get-G71PropertyValue -Object $result `
                -Name "dynamic_arena_cap_capped" -Default $false)
            $arenaSlots = [int](Get-G71PropertyValue -Object $result `
                -Name "dynamic_arena_allocated_slots" -Default 0)
            $runtimeAborted = [bool](Get-G71PropertyValue `
                -Object $result.runtime_telemetry `
                -Name "contamination_abort_observed" -Default $false)
            $runtimeAvailable = [uint64](Get-G71PropertyValue `
                -Object $result.runtime_telemetry `
                -Name "windows_available_min_bytes" -Default ([uint64]::MaxValue))
            if ($arenaCapped -or $arenaSlots -lt $expectedArenaSlots -or
                ($runtimeAborted -and $runtimeAvailable -lt 2GB)) {
                return $true
            }
        } catch {
            # Fall through to preflight/runtime artifacts.
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
            # Malformed telemetry is not capacity evidence.
        }
    }

    if (-not $Message) { return $false }
    return ($Message -match "Memory preflight refused launch:.*(memory|available|RAM)" -or
            $Message -match "Runtime telemetry aborted.*low RAM" -or
            $Message -match "arena-cap.*(allocation|capacity|memory|guard)" -or
            $Message -match "dynamic arena.*(allocation|capacity|memory|guard)")
}

function Assert-G71CommonContract {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("control","candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][bool]$Safety
    )

    $budget = Get-G71Budget -Arm $Arm
    $tier = $Result.expert_tiering
    $maxWaveBytes = [uint64]([double]$waveGiB * 1GB)

    if (-not $Result.outputs_identical -or
        $Result.expected_content_sha256 -ne $expected -or
        $Result.prompt_sha256 -ne $expectedPromptSha256 -or
        $Result.results.Count -ne 1 -or
        $Result.results[0].content_sha256 -ne $expected -or
        $Result.model -ne $model -or
        $Result.requested_max_tokens -ne 64 -or
        $Result.context_requested -ne 256 -or
        $Result.reserve_mb -ne 1024 -or
        [math]::Abs([double]$Result.dynamic_arena_gib_requested - $arenaGiB) -gt 0.001 -or
        $Result.dynamic_arena_allocated_slots -ne $expectedArenaSlots -or
        $Result.expert_cache_requested -ne $expectedCacheCapacity -or
        $Result.expert_cache_capacity -ne $expectedCacheCapacity -or
        $Result.expert_cache_reserve_gb -ne 0.125 -or
        $Result.expert_cache_policy -ne "lru" -or
        -not $Result.q8_f16_cache_disabled -or
        -not $Result.embed_row_staging_requested -or
        -not $Result.arena_wrap_trust_worker_checksum_requested -or
        $Result.arena_wrap_schedule_requested -ne "source-parts" -or
        $Result.arena_wrap_schedule_observed -ne "source-parts" -or
        $Result.arena_wrap_checksum_observed -ne "fnv1a64-worker-only" -or
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
        $tier.requested_mode -ne "enforce" -or
        $tier.requested_policy -ne "mass-lfru" -or
        $tier.mode -ne "enforce" -or
        $tier.policy -ne "mass-lfru" -or
        -not $tier.compose_prefill_mass_tiering_observed -or
        $tier.clock_calls -ne 430 -or
        $tier.replacement_budget -ne $budget -or
        $tier.min_frequency -ne 3 -or
        [math]::Abs([double]$tier.hysteresis - 1.25) -gt 0.000001 -or
        $tier.states_vram -ne $expectedCacheCapacity -or
        $tier.snapshot_backing_misses -ne 0 -or
        $tier.ssd_bytes -ne 0 -or
        $tier.failures -ne 0 -or
        $tier.forbidden_cold_ssd_to_vram -ne 0 -or
        -not $Result.memory_preflight.ready_to_launch -or
        -not $Result.process_isolation_preflight.ready_to_launch -or
        -not $Result.system_quiescence_preflight.ready_to_launch) {
        throw "G71 contract mismatch: tag=$Tag"
    }

    if (-not $Result.arena_wrap_unlock_source_ranges_requested -or
        -not $Result.arena_wrap_unlock_source_ranges_observed -or
        -not $Result.arena_wrap_unlock_source_ranges_summary_observed -or
        $Result.arena_wrap_unlock_source_ranges_summary_result -ne "complete" -or
        $Result.arena_wrap_unlock_source_ranges_summary_phases -ne 3 -or
        $Result.arena_wrap_unlock_source_ranges_summary_waves -ne 9 -or
        $Result.arena_wrap_unlock_source_ranges_summary_failed -ne 0 -or
        $Result.arena_wrap_unlock_source_ranges_summary_max_wave_bytes -gt $maxWaveBytes -or
        [math]::Abs([double]$Result.arena_wrap_unlock_wave_gib_observed - $waveGiB) -gt 0.000001 -or
        ($Result.arena_wrap_unlock_source_ranges_summary_true +
         $Result.arena_wrap_unlock_source_ranges_summary_error_not_locked) -ne
            $Result.arena_wrap_unlock_source_ranges_summary_calls) {
        throw "G71 source reclaim contract mismatch: tag=$Tag"
    }

    [pscustomobject]@{
        tag = $Tag
        arm = $Arm
        safety = $Safety
        replacement_budget = $budget
        result_path = Get-G71ResultPath $Tag
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
        prompt_sha256 = $Result.prompt_sha256
        memory_preflight_available_gib = [math]::Round([double]$Result.memory_preflight.after.available_bytes / 1GB, 6)
        quiescence_cpu_median = $Result.system_quiescence_preflight.cpu_median_percent
        quiescence_disk_median = $Result.system_quiescence_preflight.disk_median_percent
        quiescence_disk_io_mibps_median = $Result.system_quiescence_preflight.disk_io_median_mib_per_second
        quiescence_gpu_median = $Result.system_quiescence_preflight.gpu_median_percent
        arena_slots = [int]$Result.dynamic_arena_allocated_slots
        arena_bytes = [uint64]$Result.dynamic_arena_allocated_bytes
        cache_capacity = [int]$Result.expert_cache_capacity
        states_vram = [int]$tier.states_vram
        ttft_seconds = [double]$Result.server_prefill_ttft_mean_seconds
        wrap_seconds = [double]$Result.prefill_mass_wrap_seconds
        ttft_minus_wrap_seconds = [math]::Round([double]$Result.server_prefill_ttft_mean_seconds - [double]$Result.prefill_mass_wrap_seconds, 6)
        decode_tokens_per_second = [double]$Result.server_decode_mean_tokens_per_second
        decode_seconds = [double]$Result.server_runs[0].server_decode_seconds
        route_calls = [uint64]$Result.gpu_resident_routes_calls
        default_sync_calls = [uint64]$Result.gpu_resident_routes_default_sync_calls
        no_default_sync_calls = [uint64]$Result.gpu_resident_routes_no_default_sync_calls
        route_worker_jobs = [uint64]$Result.gpu_resident_routes_worker_jobs
        route_worker_ms_per_job = [double]$Result.gpu_resident_routes_worker_ms_per_job
        route_wait_ms_per_call = [double]$Result.gpu_resident_routes_wait_ms_per_call
        vram_hits = [uint64]$tier.vram_hits
        ram_hits = [uint64]$tier.ram_hits
        ram_h2d_gib = [math]::Round([uint64]$tier.ram_h2d_bytes / 1GB, 6)
        vram_promotions = [uint64]$tier.vram_promotions
        vram_demotions = [uint64]$tier.vram_demotions
        ram_evictions = [uint64]$tier.ram_evictions
        ram_admit_skips = [uint64]$tier.ram_admit_skips
        policy_free_promotions = [uint64]$tier.policy_free_promotions
        policy_replacements = [uint64]$tier.policy_replacements
        policy_min_frequency_skips = [uint64]$tier.policy_min_frequency_skips
        policy_budget_skips = [uint64]$tier.policy_budget_skips
        policy_score_skips = [uint64]$tier.policy_score_skips
        gpu_route_cache_admissions = [uint64]$Result.gpu_resident_routes_cache_admissions
        gpu_route_cache_evictions = [uint64]$Result.gpu_resident_routes_cache_evictions
        snapshot_misses = [uint64]$tier.snapshot_backing_misses
        ssd_bytes = [uint64]$tier.ssd_bytes
        failures = [uint64]$tier.failures
        unlock_phases = [int]$Result.arena_wrap_unlock_source_ranges_summary_phases
        unlock_waves = [int]$Result.arena_wrap_unlock_source_ranges_summary_waves
        unlock_max_wave_bytes = [uint64]$Result.arena_wrap_unlock_source_ranges_summary_max_wave_bytes
        unlock_failed = [uint64]$Result.arena_wrap_unlock_source_ranges_summary_failed
        vram_peak_mib = [uint64]$Result.runtime_telemetry.vram_used_peak_mib
        available_min_gib = [math]::Round([uint64]$Result.runtime_telemetry.windows_available_min_bytes / 1GB, 6)
        disk_read_gib = [math]::Round([uint64](Get-G71PropertyValue $Result.runtime_telemetry "aggregate_disk_read_bytes_estimated" 0) / 1GB, 6)
        process_read_gib = [math]::Round([uint64]$Result.runtime_telemetry.win32_process_read_transfer_delta_bytes / 1GB, 6)
    }
}

function Invoke-G71Run {
    param(
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][ValidateSet("control","candidate")][string]$Arm,
        [Parameter(Mandatory=$true)][bool]$Safety
    )

    $budget = Get-G71Budget -Arm $Arm
    $resultPath = Get-G71ResultPath $Tag
    $args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $harness,
        "-MaxTokens", "64", "-Repeats", "1",
        "-Tag", $Tag, "-Prompt", $prompt, "-Context", "256",
        "-BudgetGB", "2", "-ReserveMB", "1024",
        "-DynamicArenaGiB", "30", "-ArenaWrapTrustWorkerChecksum",
        "-ArenaWrapSourceParts", "-ArenaWrapUnlockSourceRanges",
        "-ArenaWrapUnlockWaveGiB", "4",
        "-DisableQ8F16Cache", "-EmbedRowStaging",
        "-ReapPrefetchThreads", "8", "-ExpectedContentSHA256", $expected,
        "-ModelPath", $model, "-TimeoutSec", "1800",
        "-PrefillMassWrap", "-ComposePrefillMassTiering",
        "-ExpertCacheN", "320", "-ExpertCacheReserveGB", "0.125",
        "-ExpertCachePolicy", "lru", "-GpuResidentRoutes",
        "-RouteNoDefaultSync", "-ExpertTiering", "enforce",
        "-ExpertTierPolicy", "mass-lfru", "-ExpertTierClockCalls", "430",
        "-ExpertTierReplacementBudget", "$budget",
        "-ExpertTierMinFrequency", "3", "-ExpertTierHysteresis", "1.25"
    )

    try {
        if (($Resume -or $SummarizeExisting) -and
            (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            Write-Host ("[g71] resume tag=" + $Tag + " arm=" + $Arm + " budget=" + $budget)
        } elseif ($SummarizeExisting) {
            throw "SummarizeExisting result missing: tag=$Tag"
        } else {
            Write-Host ("[g71] start tag=" + $Tag + " arm=" + $Arm + " budget=" + $budget)
            $nativeOutput = New-Object 'System.Collections.Generic.List[string]'
            & powershell.exe @args 2>&1 | ForEach-Object {
                $line = [string]$_
                $nativeOutput.Add($line)
                Write-Host $line
            }
            if ($LASTEXITCODE -ne 0) {
                $tail = [string]::Join(" | ", @($nativeOutput | Select-Object -Last 8))
                throw "G71 harness failed: tag=$Tag exit=$LASTEXITCODE output=$tail"
            }
        }

        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            throw "G71 result missing: tag=$Tag"
        }
        $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        return Assert-G71CommonContract -Result $result -Tag $Tag -Arm $Arm -Safety $Safety
    } catch {
        $message = $_.Exception.Message
        [pscustomobject]@{
            tag = $Tag
            arm = $Arm
            safety = $Safety
            replacement_budget = $budget
            failed = $true
            capacity_failure = (Test-G71CapacityFailure -Message $message -Tag $Tag)
            message = $message
            result_path = $resultPath
        }
    }
}

function Assert-G71SameProvenance {
    param([object[]]$Rows, [bool]$RequireHead = $true)
    $provenanceFields = @(
        "executable_sha256", "ds4_cuda_sha256", "ds4_c_sha256",
        "build_manifest_sha256", "build_input_fingerprint_sha256",
        "harness_sha256", "model", "model_bytes", "model_last_write_utc",
        "prompt_sha256"
    )
    if ($RequireHead) { $provenanceFields = @("head") + $provenanceFields }
    foreach ($field in $provenanceFields) {
        $values = @($Rows | ForEach-Object { [string]($_.$field) } | Select-Object -Unique)
        if ($values.Count -ne 1) { throw "G71 mixed provenance: field=$field" }
    }
}

function Test-G71Outlier {
    param([object[]]$Rows)
    foreach ($property in @(
            "decode_tokens_per_second", "wrap_seconds",
            "ttft_minus_wrap_seconds")) {
        foreach ($arm in @("control", "candidate")) {
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

function New-G71ArmSummary {
    param([object[]]$Rows)
    $summaries = @()
    foreach ($arm in @("control", "candidate")) {
        $armRows = @($Rows | Where-Object { $_.arm -eq $arm -and -not $_.safety })
        $summaries += [pscustomobject]@{
            arm = $arm
            replacement_budget = Get-G71Budget -Arm $arm
            independent_processes = $armRows.Count
            decode_tokens_per_second_mean = Get-G71Mean $armRows "decode_tokens_per_second"
            decode_tokens_per_second_median = Get-G71Median $armRows "decode_tokens_per_second"
            decode_seconds_mean = Get-G71Mean $armRows "decode_seconds"
            ttft_mean_seconds = Get-G71Mean $armRows "ttft_seconds"
            wrap_mean_seconds = Get-G71Mean $armRows "wrap_seconds"
            ttft_minus_wrap_mean_seconds = Get-G71Mean $armRows "ttft_minus_wrap_seconds"
            ram_hits_mean = Get-G71Mean $armRows "ram_hits"
            ram_h2d_gib_mean = Get-G71Mean $armRows "ram_h2d_gib"
            vram_promotions_mean = Get-G71Mean $armRows "vram_promotions"
            policy_free_promotions_mean = Get-G71Mean $armRows "policy_free_promotions"
            policy_replacements_mean = Get-G71Mean $armRows "policy_replacements"
            policy_budget_skips_mean = Get-G71Mean $armRows "policy_budget_skips"
            ram_evictions_mean = Get-G71Mean $armRows "ram_evictions"
            gpu_route_cache_admissions_mean = Get-G71Mean $armRows "gpu_route_cache_admissions"
            gpu_route_cache_evictions_mean = Get-G71Mean $armRows "gpu_route_cache_evictions"
            route_wait_ms_per_call_mean = Get-G71Mean $armRows "route_wait_ms_per_call"
            route_worker_ms_per_job_mean = Get-G71Mean $armRows "route_worker_ms_per_job"
            available_min_gib_min = if ($armRows.Count) { [math]::Round(($armRows | Measure-Object -Property available_min_gib -Minimum).Minimum, 6) } else { $null }
            snapshot_misses_sum = ($armRows | Measure-Object -Property snapshot_misses -Sum).Sum
            ssd_bytes_sum = ($armRows | Measure-Object -Property ssd_bytes -Sum).Sum
            failures_sum = ($armRows | Measure-Object -Property failures -Sum).Sum
        }
    }
    $summaries
}

function Write-G71Summary {
    param(
        [object[]]$Rows,
        [string]$Status,
        [string]$StopReason,
        [bool]$OutlierExtensionTriggered
    )
    $successful = @($Rows | Where-Object { -not $_.failed })
    $matrix = @($successful | Where-Object { -not $_.safety })
    if ($successful.Count -gt 0) { Assert-G71SameProvenance -Rows $successful -RequireHead $false }
    if ($matrix.Count -gt 0) { Assert-G71SameProvenance -Rows $matrix -RequireHead $true }

    $summary = [pscustomobject]@{
        schema = "g71_tier_budget_ab_v1"
        status = $Status
        stop_reason = $StopReason
        performance_claim_allowed = ($Status -eq "matrix_complete" -and $matrix.Count -ge 6)
        outlier_extension_triggered = $OutlierExtensionTriggered
        outlier_rule = "If either arm has >20% max/min spread in decode_tokens_per_second, wrap_seconds or ttft_minus_wrap_seconds after n=3, run exactly three additional independent processes per arm before any verdict."
        prompt = $prompt
        prompt_sha256 = $expectedPromptSha256
        expected_content_sha256 = $expected
        model = $model
        context = 256
        max_tokens = 64
        arena_gib = $arenaGiB
        expected_arena_slots = $expectedArenaSlots
        expert_cache_capacity = $expectedCacheCapacity
        common_reclaim = [pscustomobject]@{
            arena_wrap_unlock_source_ranges = $true
            arena_wrap_unlock_wave_gib = $waveGiB
            required_phases = 3
            required_waves = 9
            required_failures = 0
        }
        arms = @(
            [pscustomobject]@{ arm = "control"; replacement_budget = $controlBudget },
            [pscustomobject]@{ arm = "candidate"; replacement_budget = $candidateBudget }
        )
        stop_conditions = @(
            "candidate32_safety_failure => stop immediately; no matrix",
            "any matrix run contract/preflight/provenance mismatch => stop and mark invalid",
            "any expected content SHA mismatch => stop and mark invalid",
            "any source reclaim phase/wave/failure mismatch => stop and mark invalid",
            "any backing miss, SSD byte, tier failure, arena/cache/state mismatch or default-sync call => stop and mark invalid",
            "never issue a verdict from n=1 safety timing"
        )
        order = @($Rows | ForEach-Object { $_.tag })
        runs = $Rows
        primary_run_tags = @($matrix | ForEach-Object { $_.tag })
        arm_summary = New-G71ArmSummary $matrix
        provenance = if ($matrix.Count -gt 0) {
            [pscustomobject]@{
                head = $matrix[0].head
                executable_sha256 = $matrix[0].executable_sha256
                ds4_cuda_sha256 = $matrix[0].ds4_cuda_sha256
                ds4_c_sha256 = $matrix[0].ds4_c_sha256
                build_manifest_sha256 = $matrix[0].build_manifest_sha256
                build_input_fingerprint_sha256 = $matrix[0].build_input_fingerprint_sha256
                harness_sha256 = $matrix[0].harness_sha256
                model = $matrix[0].model
                model_bytes = $matrix[0].model_bytes
                model_last_write_utc = $matrix[0].model_last_write_utc
                prompt_sha256 = $matrix[0].prompt_sha256
                summary_runner_sha256 = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } else { $null }
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $summaryPath
    Write-Host ("[g71] summary: " + $summaryPath)
}

New-Item -ItemType Directory -Force -Path $outdir | Out-Null
Assert-G71StaticContract
if ($StaticCheckOnly) {
    Write-Host "[g71] static check passed"
    exit 0
}

$runs = @()
$outlierExtensionTriggered = $false

$candidateSafety = Invoke-G71Run -Tag "g71_candidate32_safety_exact" -Arm "candidate" -Safety $true
$runs += $candidateSafety
if ($candidateSafety.failed) {
    Write-G71Summary -Rows $runs -Status "stopped" -StopReason "candidate32_safety_failed" -OutlierExtensionTriggered $false
    exit 1
}

$matrixPlan = @(
    @("g71_control_a", "control"),
    @("g71_candidate_a", "candidate"),
    @("g71_candidate_b", "candidate"),
    @("g71_control_b", "control"),
    @("g71_control_c", "control"),
    @("g71_candidate_c", "candidate")
)

foreach ($entry in $matrixPlan) {
    $row = Invoke-G71Run -Tag $entry[0] -Arm $entry[1] -Safety $false
    $runs += $row
    if ($row.failed) {
        Write-G71Summary -Rows $runs -Status "invalid" -StopReason ("matrix_run_failed:" + $row.tag) -OutlierExtensionTriggered $outlierExtensionTriggered
        exit 1
    }
}

if (Test-G71Outlier @($runs | Where-Object { -not $_.failed })) {
    $outlierExtensionTriggered = $true
    $extensionPlan = @(
        @("g71_control_x1", "control"),
        @("g71_candidate_x1", "candidate"),
        @("g71_control_x2", "control"),
        @("g71_candidate_x2", "candidate"),
        @("g71_control_x3", "control"),
        @("g71_candidate_x3", "candidate")
    )
    foreach ($entry in $extensionPlan) {
        $row = Invoke-G71Run -Tag $entry[0] -Arm $entry[1] -Safety $false
        $runs += $row
        if ($row.failed) {
            Write-G71Summary -Rows $runs -Status "invalid" -StopReason ("outlier_extension_run_failed:" + $row.tag) -OutlierExtensionTriggered $outlierExtensionTriggered
            exit 1
        }
    }
}

Write-G71Summary -Rows $runs -Status "matrix_complete" -StopReason "completed_preregistered_sequence" -OutlierExtensionTriggered $outlierExtensionTriggered
