# G129 fail-closed n=1 safety runner for full/open Q1_0 dynamic promotion.
param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Tag = 'g129_q1_open_dynamic_promotion_safety',
    [Parameter(Mandatory=$true)][string]$Q1_0ExpertSidecar,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedQ1_0ExpertSidecarSHA256,
    [Parameter(Mandatory=$true)]
    [UInt64]$ExpectedQ1_0ExpertSidecarBytes,
    [ValidateSet('promotion', 'control')]
    [string]$Arm = 'promotion',
    [switch]$Q1_0PromotionSsdWrap,
    [ValidateRange(0.125, 5.5)][double]$Q1_0Iq2PinnedGiB = 1.5,
    [ValidateRange(600, 7200)][int]$TimeoutSec = 2400,
    [switch]$WhatIf,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$harness = Join-Path $root 'g7_measure.ps1'
$bootstrap = Join-Path $root 'g7_harness_bootstrap.ps1'
$runs = Join-Path $root 'g7_runs'
$model = 'C:\ds4-models\ds4-2bit.gguf'
$modelSHA = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'
$sidecar = $Q1_0ExpertSidecar
$sidecarSHA = $ExpectedQ1_0ExpertSidecarSHA256.ToLowerInvariant()
$prompt = 'Create a complete single-file HTML landing page for a cyberpunk AI programming shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation popup. Return only the HTML document.'
$promptSHA = '38f6ec5ee5403f59dd2418eb5d9a5a94a0f0da19df015060383bb1ae46003bb6'
$q1ArenaGB = 24.5
$primaryArenaGB = 5.5
$q1ArenaGBText = $q1ArenaGB.ToString(
    "0.###", [Globalization.CultureInfo]::InvariantCulture)
$primaryArenaGBText = $primaryArenaGB.ToString(
    "0.###", [Globalization.CultureInfo]::InvariantCulture)
$reserveSlots = 64
$cacheSlots = 320
$tierReplacementBudget = 32
$promotionEnabled = $Arm -eq 'promotion'
$promotionRecordBoundedExceptionLimit = [UInt64]16

function Get-G129Sha256Text {
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

function Get-G129ConfigurationSHA {
    $contract = @(
        'schema=g129_q1_open_dynamic_promotion_config_v1',
        "model_sha256=$modelSHA",
        "q1_0_sidecar_sha256=$sidecarSHA",
        "prompt_sha256=$promptSHA",
        'temperature=0',
        'nothink=1',
        'max_tokens=64',
        'context=256',
        "arm=$Arm",
        'router=full/open',
        "primary_iq2_dynamic_arena_gib=$primaryArenaGB",
        "q1_0_dynamic_arena_gb=$q1ArenaGB",
        "q1_0_dynamic_promotion=$([int]$promotionEnabled)",
        "reserve_slots=$reserveSlots",
        "probation_slots=$reserveSlots",
        "expert_cache_slots=$cacheSlots",
        "tier_replacement_budget=$tierReplacementBudget",
        'prefill_vram_seed_total=320',
        'prefill_vram_seed_floor_per_layer=4',
        'claim_scope=structural_safety_only_no_sota_no_quality_verdict'
    )
    if ($promotionEnabled) {
        $contract += @(
            'promotion_min_touches=2',
            'promotion_min_weight=0.02',
            'promotion_min_mass=0',
            'promotion_request_budget=64',
            'promotion_window_calls=40',
            'promotion_window_budget=1'
        )
        if ($Q1_0PromotionSsdWrap) {
            $contract += @(
                'q1_0_promotion_ssd_wrap=1',
                "q1_0_iq2_pinned_gib=$($Q1_0Iq2PinnedGiB.ToString('R', [Globalization.CultureInfo]::InvariantCulture))"
            )
        }
    } else {
        $contract += 'promotion_gate=disabled'
    }
    $contract = $contract -join "`n"
    return Get-G129Sha256Text -Text ($contract + "`n")
}

$configurationSHA = Get-G129ConfigurationSHA

function Assert-G129U64Positive {
    param([object]$Object, [string]$Name, [string]$Label)

    if ($null -eq $Object.PSObject.Properties[$Name] -or
        [UInt64]$Object.$Name -eq 0) {
        throw "G129 required positive counter missing or zero: $Label"
    }
}

function Get-G129RequiredProperty {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object.PSObject.Properties[$Name]) {
        throw "G129 required result property missing: $Name"
    }
    return $Object.$Name
}

function Convert-G129StrictUInt64 {
    param([Parameter(Mandatory=$true)][object]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -is [string] -or $Value -is [double] -or
        $Value -is [single] -or $Value -is [decimal] -or
        $Value -is [bool]) {
        throw "G129 strict UInt64 parse rejected $Name=$Value"
    }
    $text = [Convert]::ToString(
        $Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($text -notmatch '^(0|[1-9][0-9]*)$') {
        throw "G129 strict UInt64 parse rejected $Name=$text"
    }
    try {
        return [UInt64]::Parse(
            $text, [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "G129 strict UInt64 parse overflow for $Name=$text"
    }
}

function Convert-G129StrictUInt32 {
    param([Parameter(Mandatory=$true)][object]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    $parsed = Convert-G129StrictUInt64 $Value $Name
    if ($parsed -gt [UInt64][UInt32]::MaxValue) {
        throw "G129 strict UInt32 parse overflow for $Name=$Value"
    }
    return [UInt32]$parsed
}

function Convert-G129StrictFlag01 {
    param([Parameter(Mandatory=$true)][object]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -is [string] -or $Value -is [double] -or
        $Value -is [single] -or $Value -is [decimal] -or
        $Value -is [bool]) {
        throw "G129 strict flag parse rejected $Name=$Value"
    }
    $text = [Convert]::ToString(
        $Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($text -notmatch '^[01]$') {
        throw "G129 strict flag parse rejected $Name=$text"
    }
    return [int]$text
}

function Convert-G129StrictDouble {
    param([Parameter(Mandatory=$true)][object]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -is [string] -or $Value -is [bool]) {
        throw "G129 strict double parse rejected $Name=$Value"
    }
    $text = [Convert]::ToString(
        $Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($text -notmatch '^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$') {
        throw "G129 strict double parse rejected $Name=$text"
    }
    $parsed = [double]::Parse(
        $text, [Globalization.CultureInfo]::InvariantCulture)
    if ([double]::IsNaN($parsed) -or [double]::IsInfinity($parsed)) {
        throw "G129 strict double parse rejected non-finite $Name=$text"
    }
    return $parsed
}

function Assert-G129U64Sum3 {
    param([UInt64]$A, [UInt64]$B, [UInt64]$C, [UInt64]$Expected,
          [string]$Label)

    $sum = [decimal]$A + [decimal]$B + [decimal]$C
    if ($sum -gt [decimal][UInt64]::MaxValue -or
        [UInt64]$sum -ne $Expected) {
        throw "G129 Q1_0 promotion $Label byte sum is invalid"
    }
}

function Assert-G129PromotionOffsetFormula {
    param(
        [UInt64]$BaseOffset,
        [UInt64]$Stride,
        [UInt32]$Expert,
        [UInt64]$Bytes,
        [UInt64]$ObservedOffset,
        [UInt64]$ModelSize,
        [string]$Label
    )

    $expected = [decimal]$BaseOffset + ([decimal]$Expert * [decimal]$Stride)
    $end = [decimal]$ObservedOffset + [decimal]$Bytes
    if ($Stride -eq 0 -or $Bytes -eq 0 -or $ModelSize -eq 0 -or
        $expected -gt [decimal][UInt64]::MaxValue -or
        [UInt64]$expected -ne $ObservedOffset -or
        $end -gt [decimal]$ModelSize) {
        throw "G129 Q1_0 promotion $Label offset formula/range is invalid"
    }
}

function Get-G129PromotionRecordKey {
    param([Parameter(Mandatory=$true)][object]$Record)

    return ("{0}:{1}" -f
        (Convert-G129StrictUInt64 $Record.request_epoch 'request_epoch'),
        (Convert-G129StrictUInt64 $Record.record_id 'record_id'))
}

function Get-G129PromotionRecordIdentity {
    param([Parameter(Mandatory=$true)][object]$Record)

    return ("{0}:{1}:{2}:{3}:{4}:{5}" -f
        (Convert-G129StrictUInt64 $Record.request_epoch 'request_epoch'),
        (Convert-G129StrictUInt64 $Record.record_id 'record_id'),
        (Convert-G129StrictUInt32 $Record.layer 'layer'),
        (Convert-G129StrictUInt32 $Record.expert 'expert'),
        (Convert-G129StrictUInt64 $Record.observation_call 'observation_call'),
        (Convert-G129StrictUInt64 $Record.first_eligible_call 'first_eligible_call'))
}

function Get-G129PromotionRecordImmutableIdentity {
    param([Parameter(Mandatory=$true)][object]$Record)

    $mutable = @{
        line_index = $true
        physical_line = $true
        kind = $true
        result = $true
        reason = $true
        destination_kind = $true
        destination_ram_slot = $true
        destination_ram_generation = $true
    }
    $parts = @()
    foreach ($property in @($Record.PSObject.Properties.Name | Sort-Object)) {
        if ($mutable.ContainsKey($property)) { continue }
        $value = $Record.PSObject.Properties[$property].Value
        $parts += ('{0}={1}' -f $property, [Convert]::ToString(
            $value, [Globalization.CultureInfo]::InvariantCulture))
    }
    return ($parts -join "`n")
}

function Test-G129PathInsideDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $resolvedPath = [IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $Path).Path)
    $resolvedDirectory = [IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $Directory).Path)
    $resolvedDirectory = $resolvedDirectory.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith(
            $resolvedDirectory,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped g7_runs"
    }
    $item = Get-Item -LiteralPath $resolvedPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label uses a reparse point"
    }
    return $resolvedPath
}

function Read-G129PromotionRecordArtifact {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ExpectedSHA256,
        [Parameter(Mandatory=$true)][UInt64]$ExpectedCount
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        $ExpectedSHA256 -notmatch '^[0-9a-fA-F]{64}$' -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'G129 Q1_0 promotion record artifact missing or unhashed'
    }
    $resolvedPath = Test-G129PathInsideDirectory `
        -Path $Path `
        -Directory $runs `
        -Label 'G129 Q1_0 promotion record artifact'
    $observedSHA256 = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($observedSHA256 -ine $ExpectedSHA256) {
        throw 'G129 Q1_0 promotion record artifact SHA-256 mismatch'
    }
    $rows = @()
    $lines = @([IO.File]::ReadAllLines($resolvedPath))
    if ([UInt64]$lines.Count -ne $ExpectedCount) {
        throw 'G129 Q1_0 promotion record artifact physical-line count mismatch'
    }
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        if ([string]::IsNullOrWhiteSpace($line)) {
            throw 'G129 Q1_0 promotion record artifact contains a blank physical line'
        }
        if (-not $line.StartsWith('{') -or -not $line.EndsWith('}')) {
            throw 'G129 Q1_0 promotion record artifact line is not one JSON object'
        }
        $keyMatches = [regex]::Matches(
            $line, '"([^"\\]*(?:\\.[^"\\]*)*)"\s*:');
        $keys = @{}
        foreach ($keyMatch in $keyMatches) {
            $key = [string]$keyMatch.Groups[1].Value
            if ($keys.ContainsKey($key)) {
                throw 'G129 Q1_0 promotion record artifact duplicate JSON key'
            }
            $keys[$key] = $true
        }
        $parsed = $line | ConvertFrom-Json
        if ($parsed -is [array]) {
            throw 'G129 Q1_0 promotion record artifact arrays are forbidden'
        }
        $canonical = $parsed | ConvertTo-Json -Compress -Depth 8
        if ($canonical -ne $line) {
            throw 'G129 Q1_0 promotion record artifact is not canonical JSONL'
        }
        $rows += $parsed
    }
    if ([UInt64]$rows.Count -ne $ExpectedCount) {
        throw 'G129 Q1_0 promotion record artifact count mismatch'
    }
    return $rows
}

function Assert-G129PromotionRecords {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][bool]$PromotionEnabled,
        [switch]$AllowZeroSuccess
    )

    if (-not $PromotionEnabled) {
        if ([bool](Get-G129RequiredProperty $Result 'q1_0_promotion_records_observed') -or
            [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_records_count') -ne 0 -or
            [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_records_physical_line_count') -ne 0 -or
            [string](Get-G129RequiredProperty $Result 'q1_0_promotion_records_path')) {
            throw 'G129 control observed Q1_0 promotion record artifact'
        }
        return [pscustomobject]@{
            observed = $false
            path = ''
            sha256 = ''
            count = [UInt64]0
            physical_line_count = [UInt64]0
            attempts = [UInt64]0
            successes = [UInt64]0
            rejects = [UInt64]0
            failures = [UInt64]0
        }
    }

    if (-not [bool](Get-G129RequiredProperty $Result 'q1_0_promotion_records_observed')) {
        throw 'G129 promotion missing Q1_0 per-expert record artifact'
    }
    $recordCount = [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_records_count')
    $physicalLineCount = [UInt64](
        Get-G129RequiredProperty $Result 'q1_0_promotion_records_physical_line_count')
    $attemptCount = [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_record_attempt_count')
    $successCount = [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_record_success_count')
    $rejectCount = [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_record_reject_count')
    $failureCount = [UInt64](Get-G129RequiredProperty $Result 'q1_0_promotion_record_failure_count')
    $boundedExceptionLimit = [UInt64](
        Get-G129RequiredProperty $Result 'q1_0_promotion_record_bounded_exception_limit')
    $reportedRecordLimit = [UInt64](
        Get-G129RequiredProperty $Result 'q1_0_promotion_telemetry_record_limit')
    $recordLimitDecimal =
        ([decimal]$attemptCount * [decimal]2) +
        [decimal]$boundedExceptionLimit
    if ($recordLimitDecimal -gt [decimal][UInt64]::MaxValue) {
        throw 'G129 promotion telemetry record limit overflow'
    }
    $recordLimit = [UInt64]$recordLimitDecimal
    if ($recordCount -gt $recordLimit) {
        throw "G129 promotion telemetry record flood: count=$recordCount limit=$recordLimit"
    }
    if ($recordCount -eq 0 -or
        $physicalLineCount -ne $recordCount -or
        $boundedExceptionLimit -ne $promotionRecordBoundedExceptionLimit -or
        $reportedRecordLimit -ne $recordLimit -or
        $attemptCount -ne [UInt64]$Result.iq1_promotion_q1_0_stage_attempts -or
        $successCount -ne [UInt64]$Result.iq1_promotion_q1_0_stage_successes -or
        $successCount -ne [UInt64]$Result.iq1_promotion_q1_0_next_call_guards -or
        ([decimal]$failureCount + [decimal]$rejectCount) -ne
            [decimal][UInt64]$Result.iq1_promotion_failures -or
        (-not $AllowZeroSuccess -and
         ($attemptCount -eq 0 -or $successCount -eq 0))) {
        throw 'G129 promotion record summary counters are inconsistent'
    }
    if ([UInt64](Get-G129RequiredProperty $Result 'iq1_promotion_q1_0_record_attempts') -ne
            $attemptCount -or
        [UInt64](Get-G129RequiredProperty $Result 'iq1_promotion_q1_0_record_successes') -ne
            $successCount -or
        [UInt64](Get-G129RequiredProperty $Result 'iq1_promotion_q1_0_record_rejects') -ne
            $rejectCount -or
        [UInt64](Get-G129RequiredProperty $Result 'iq1_promotion_q1_0_record_failures') -ne
            $failureCount) {
        throw 'G129 promotion final counters do not match record counters'
    }

    $artifactPath = [string](Get-G129RequiredProperty $Result 'q1_0_promotion_records_path')
    $artifactSHA256 = [string](Get-G129RequiredProperty $Result 'q1_0_promotion_records_sha256')
    $records = @(Read-G129PromotionRecordArtifact `
        -Path $artifactPath `
        -ExpectedSHA256 $artifactSHA256 `
        -ExpectedCount $recordCount)
    $attempts = @($records | Where-Object { [string]$_.kind -eq 'attempt' })
    $successes = @($records | Where-Object { [string]$_.kind -eq 'success' })
    $rejects = @($records | Where-Object { [string]$_.kind -eq 'reject' })
    $failures = @($records | Where-Object { [string]$_.kind -eq 'failure' })
    if ([UInt64]$attempts.Count -ne $attemptCount -or
        [UInt64]$successes.Count -ne $successCount -or
        [UInt64]$rejects.Count -ne $rejectCount -or
        [UInt64]$failures.Count -ne $failureCount) {
        throw 'G129 promotion record artifact counts do not match result'
    }

    $requiredRecordFields = @(
        'line_index', 'physical_line', 'kind', 'result', 'reason',
        'record_id', 'request_epoch', 'promotion_window_epoch',
        'current_call', 'observation_call', 'first_eligible_call',
        'layer', 'expert', 'touch_count', 'weight', 'mass',
        'gate_min_touches', 'gate_min_weight', 'gate_min_mass',
        'gate_request_budget', 'gate_request_used', 'gate_window_calls',
        'gate_window_budget', 'gate_window_used', 'source_kind',
        'source_sidecar_sha256', 'source_sidecar_size',
        'source_q1_snapshot', 'source_gate_base_offset',
        'source_up_base_offset', 'source_down_base_offset',
        'source_gate_stride', 'source_up_stride', 'source_down_stride',
        'source_gate_offset', 'source_up_offset', 'source_down_offset',
        'source_gate_bytes', 'source_up_bytes', 'source_down_bytes',
        'source_bytes', 'destination_kind', 'destination_model_sha256',
        'destination_model_size', 'destination_gate_base_offset',
        'destination_up_base_offset', 'destination_down_base_offset',
        'destination_gate_stride', 'destination_up_stride',
        'destination_down_stride', 'destination_gate_offset',
        'destination_up_offset', 'destination_down_offset',
        'destination_gate_bytes', 'destination_up_bytes',
        'destination_down_bytes', 'destination_bytes',
        'destination_ram_slot', 'destination_ram_generation',
        'direct_ssd_to_vram_current_token', 'same_call_eligible')
    $requiredRecordFieldMap = @{}
    foreach ($field in $requiredRecordFields) {
        $requiredRecordFieldMap[$field] = $true
    }
    $attemptByKey = @{}
    $attemptIdentities = @{}
    $terminalByKey = @{}
    $rejectKeys = @{}
    $requestBudgetNextByEpoch = @{}
    $windowBudgetNextByEpoch = @{}
    foreach ($record in $records) {
        foreach ($property in @($record.PSObject.Properties.Name)) {
            if (-not $requiredRecordFieldMap.ContainsKey($property)) {
                throw "G129 promotion record unexpected field: $property"
            }
        }
        foreach ($field in $requiredRecordFields) {
            if ($null -eq $record.PSObject.Properties[$field]) {
                throw "G129 promotion record missing field: $field"
            }
        }
        $kind = [string]$record.kind
        $lineIndex = Convert-G129StrictUInt64 $record.line_index 'line_index'
        $physicalLine = Convert-G129StrictUInt64 `
            $record.physical_line 'physical_line'
        $recordId = Convert-G129StrictUInt64 $record.record_id 'record_id'
        $requestEpoch = Convert-G129StrictUInt64 $record.request_epoch 'request_epoch'
        $promotionWindowEpoch = Convert-G129StrictUInt64 `
            $record.promotion_window_epoch 'promotion_window_epoch'
        $currentCall = Convert-G129StrictUInt64 $record.current_call 'current_call'
        $observationCall = Convert-G129StrictUInt64 `
            $record.observation_call 'observation_call'
        $firstEligibleCall = Convert-G129StrictUInt64 `
            $record.first_eligible_call 'first_eligible_call'
        $layer = Convert-G129StrictUInt32 $record.layer 'layer'
        $expert = Convert-G129StrictUInt32 $record.expert 'expert'
        $touchCount = Convert-G129StrictUInt64 $record.touch_count 'touch_count'
        $weight = Convert-G129StrictDouble $record.weight 'weight'
        $mass = Convert-G129StrictDouble $record.mass 'mass'
        $gateMinTouches = Convert-G129StrictUInt64 `
            $record.gate_min_touches 'gate_min_touches'
        $gateMinWeight = Convert-G129StrictDouble `
            $record.gate_min_weight 'gate_min_weight'
        $gateMinMass = Convert-G129StrictDouble `
            $record.gate_min_mass 'gate_min_mass'
        $gateRequestBudget = Convert-G129StrictUInt64 `
            $record.gate_request_budget 'gate_request_budget'
        $gateRequestUsed = Convert-G129StrictUInt64 `
            $record.gate_request_used 'gate_request_used'
        $gateWindowCalls = Convert-G129StrictUInt64 `
            $record.gate_window_calls 'gate_window_calls'
        $gateWindowBudget = Convert-G129StrictUInt64 `
            $record.gate_window_budget 'gate_window_budget'
        $gateWindowUsed = Convert-G129StrictUInt64 `
            $record.gate_window_used 'gate_window_used'
        $sourceSidecarSize = Convert-G129StrictUInt64 `
            $record.source_sidecar_size 'source_sidecar_size'
        $sourceQ1Snapshot = Convert-G129StrictFlag01 `
            $record.source_q1_snapshot 'source_q1_snapshot'
        $sourceGateBase = Convert-G129StrictUInt64 `
            $record.source_gate_base_offset 'source_gate_base_offset'
        $sourceUpBase = Convert-G129StrictUInt64 `
            $record.source_up_base_offset 'source_up_base_offset'
        $sourceDownBase = Convert-G129StrictUInt64 `
            $record.source_down_base_offset 'source_down_base_offset'
        $sourceGateStride = Convert-G129StrictUInt64 `
            $record.source_gate_stride 'source_gate_stride'
        $sourceUpStride = Convert-G129StrictUInt64 `
            $record.source_up_stride 'source_up_stride'
        $sourceDownStride = Convert-G129StrictUInt64 `
            $record.source_down_stride 'source_down_stride'
        $sourceGateOffset = Convert-G129StrictUInt64 `
            $record.source_gate_offset 'source_gate_offset'
        $sourceUpOffset = Convert-G129StrictUInt64 `
            $record.source_up_offset 'source_up_offset'
        $sourceDownOffset = Convert-G129StrictUInt64 `
            $record.source_down_offset 'source_down_offset'
        $sourceGateBytes = Convert-G129StrictUInt64 `
            $record.source_gate_bytes 'source_gate_bytes'
        $sourceUpBytes = Convert-G129StrictUInt64 `
            $record.source_up_bytes 'source_up_bytes'
        $sourceDownBytes = Convert-G129StrictUInt64 `
            $record.source_down_bytes 'source_down_bytes'
        $sourceBytes = Convert-G129StrictUInt64 $record.source_bytes 'source_bytes'
        $destinationModelSize = Convert-G129StrictUInt64 `
            $record.destination_model_size 'destination_model_size'
        $destinationGateBase = Convert-G129StrictUInt64 `
            $record.destination_gate_base_offset 'destination_gate_base_offset'
        $destinationUpBase = Convert-G129StrictUInt64 `
            $record.destination_up_base_offset 'destination_up_base_offset'
        $destinationDownBase = Convert-G129StrictUInt64 `
            $record.destination_down_base_offset 'destination_down_base_offset'
        $destinationGateStride = Convert-G129StrictUInt64 `
            $record.destination_gate_stride 'destination_gate_stride'
        $destinationUpStride = Convert-G129StrictUInt64 `
            $record.destination_up_stride 'destination_up_stride'
        $destinationDownStride = Convert-G129StrictUInt64 `
            $record.destination_down_stride 'destination_down_stride'
        $destinationGateOffset = Convert-G129StrictUInt64 `
            $record.destination_gate_offset 'destination_gate_offset'
        $destinationUpOffset = Convert-G129StrictUInt64 `
            $record.destination_up_offset 'destination_up_offset'
        $destinationDownOffset = Convert-G129StrictUInt64 `
            $record.destination_down_offset 'destination_down_offset'
        $destinationGateBytes = Convert-G129StrictUInt64 `
            $record.destination_gate_bytes 'destination_gate_bytes'
        $destinationUpBytes = Convert-G129StrictUInt64 `
            $record.destination_up_bytes 'destination_up_bytes'
        $destinationDownBytes = Convert-G129StrictUInt64 `
            $record.destination_down_bytes 'destination_down_bytes'
        $destinationBytes = Convert-G129StrictUInt64 `
            $record.destination_bytes 'destination_bytes'
        $destinationRamSlot = Convert-G129StrictUInt64 `
            $record.destination_ram_slot 'destination_ram_slot'
        $destinationRamGeneration = Convert-G129StrictUInt64 `
            $record.destination_ram_generation 'destination_ram_generation'
        $directSsdToVram = Convert-G129StrictFlag01 `
            $record.direct_ssd_to_vram_current_token `
            'direct_ssd_to_vram_current_token'
        $sameCallEligible = Convert-G129StrictFlag01 `
            $record.same_call_eligible 'same_call_eligible'
        Assert-G129U64Sum3 `
            $sourceGateBytes $sourceUpBytes $sourceDownBytes `
            $sourceBytes 'source'
        Assert-G129U64Sum3 `
            $destinationGateBytes $destinationUpBytes $destinationDownBytes `
            $destinationBytes 'destination'
        Assert-G129PromotionOffsetFormula `
            $sourceGateBase $sourceGateStride $expert $sourceGateBytes `
            $sourceGateOffset $sourceSidecarSize 'source_gate'
        Assert-G129PromotionOffsetFormula `
            $sourceUpBase $sourceUpStride $expert $sourceUpBytes `
            $sourceUpOffset $sourceSidecarSize 'source_up'
        Assert-G129PromotionOffsetFormula `
            $sourceDownBase $sourceDownStride $expert $sourceDownBytes `
            $sourceDownOffset $sourceSidecarSize 'source_down'
        Assert-G129PromotionOffsetFormula `
            $destinationGateBase $destinationGateStride $expert `
            $destinationGateBytes $destinationGateOffset `
            $destinationModelSize 'destination_gate'
        Assert-G129PromotionOffsetFormula `
            $destinationUpBase $destinationUpStride $expert `
            $destinationUpBytes $destinationUpOffset `
            $destinationModelSize 'destination_up'
        Assert-G129PromotionOffsetFormula `
            $destinationDownBase $destinationDownStride $expert `
            $destinationDownBytes $destinationDownOffset `
            $destinationModelSize 'destination_down'
        $expectedWindowEpoch = [UInt64]0
        if ($gateWindowCalls -ne [UInt64]0) {
            $tickForWindow = if ($currentCall -eq [UInt64]0) {
                [UInt64]1
            } else {
                $currentCall
            }
            $expectedWindowEpoch = [UInt64]([decimal]::Floor(
                ([decimal]$tickForWindow - [decimal]1) /
                [decimal]$gateWindowCalls))
        }
        if ($kind -notin @('reject', 'attempt', 'success', 'failure') -or
            $lineIndex -eq [UInt64]0 -or
            $physicalLine -eq [UInt64]0 -or
            $requestEpoch -eq [UInt64]0 -or
            $currentCall -ne $observationCall -or
            ($currentCall -eq [UInt64]::MaxValue -and
             [string]$record.reason -ne 'call_tick_overflow') -or
            $promotionWindowEpoch -ne $expectedWindowEpoch -or
            $sameCallEligible -ne 0 -or
            $directSsdToVram -ne 0 -or
            [string]$record.source_kind -ne 'q1_resident' -or
            $sourceQ1Snapshot -ne 0 -or
            [string]$record.source_sidecar_sha256 -ine $sidecarSHA -or
            $sourceSidecarSize -ne $ExpectedQ1_0ExpertSidecarBytes -or
            [string]$record.destination_model_sha256 -ine $modelSHA -or
            $destinationModelSize -ne [UInt64]$Result.model_bytes -or
            $layer -gt 42 -or $expert -ge 256 -or
            $gateMinTouches -ne [UInt64]2 -or
            [math]::Abs($gateMinWeight - 0.02) -gt 0.000000000001 -or
            [math]::Abs($gateMinMass - 0.0) -gt 0.000000000001 -or
            $gateRequestBudget -ne [UInt64]64 -or
            $gateWindowCalls -ne [UInt64]40 -or
            $gateWindowBudget -ne [UInt64]1) {
            throw 'G129 promotion record provenance invariant failed'
        }
        $key = Get-G129PromotionRecordKey $record
        $identity = Get-G129PromotionRecordImmutableIdentity $record
        if ($kind -eq 'attempt') {
            if ([string]$record.result -ne 'attempt' -or
                [string]$record.reason -ne 'admitted' -or
                $firstEligibleCall -le $observationCall -or
                $touchCount -lt $gateMinTouches -or
                [math]::Abs($weight) -lt $gateMinWeight -or
                $mass -lt $gateMinMass -or
                ($gateRequestBudget -ne [UInt64]0 -and
                 $gateRequestUsed -ge $gateRequestBudget) -or
                ($gateWindowBudget -ne [UInt64]0 -and
                 $gateWindowUsed -ge $gateWindowBudget) -or
                [string]$record.destination_kind -ne 'exact_iq2_ram_pending' -or
                $attemptByKey.ContainsKey($key) -or
                $attemptIdentities.ContainsKey($identity)) {
                throw 'G129 promotion attempt record failed'
            }
            if ($gateRequestBudget -ne [UInt64]0) {
                $requestScope = [string]$requestEpoch
                $expectedRequestUsed = if ($requestBudgetNextByEpoch.ContainsKey(
                        $requestScope)) {
                    [UInt64]$requestBudgetNextByEpoch[$requestScope]
                } else {
                    [UInt64]0
                }
                if ($gateRequestUsed -ne $expectedRequestUsed -or
                    $expectedRequestUsed -ge $gateRequestBudget) {
                    throw 'G129 promotion request budget sequence failed'
                }
                $requestBudgetNextByEpoch[$requestScope] =
                    [UInt64]($expectedRequestUsed + [UInt64]1)
            }
            if ($gateWindowBudget -ne [UInt64]0) {
                $windowScope = ('{0}:{1}' -f
                    $requestEpoch, $promotionWindowEpoch)
                $expectedWindowUsed = if ($windowBudgetNextByEpoch.ContainsKey(
                        $windowScope)) {
                    [UInt64]$windowBudgetNextByEpoch[$windowScope]
                } else {
                    [UInt64]0
                }
                if ($gateWindowUsed -ne $expectedWindowUsed -or
                    $expectedWindowUsed -ge $gateWindowBudget) {
                    throw 'G129 promotion window budget sequence failed'
                }
                $windowBudgetNextByEpoch[$windowScope] =
                    [UInt64]($expectedWindowUsed + [UInt64]1)
            }
            $attemptByKey[$key] = $identity
            $attemptIdentities[$identity] = $true
        } elseif ($kind -eq 'success') {
            if ([string]$record.result -ne 'success' -or
                [string]$record.reason -ne 'staged' -or
                $firstEligibleCall -le $observationCall -or
                [string]$record.destination_kind -ne 'exact_iq2_ram' -or
                $destinationRamSlot -eq [UInt64]4294967295 -or
                $destinationRamGeneration -eq 0 -or
                -not $attemptByKey.ContainsKey($key) -or
                [string]$attemptByKey[$key] -ne $identity -or
                $terminalByKey.ContainsKey($key)) {
                throw 'G129 promotion success record failed'
            }
            $terminalByKey[$key] = 'success'
        } elseif ($kind -eq 'reject') {
            if ([string]$record.result -ne 'rejected' -or
                [string]$record.reason -notin @(
                    'request_epoch_missing', 'call_tick_overflow',
                    'offset_overflow', 'ram_admit_alloc', 'entry_contract',
                    'destination_offset_overflow',
                    'destination_offset_mismatch')) {
                throw 'G129 promotion reject record failed'
            }
            if (([string]$record.reason -eq 'call_tick_overflow' -and
                 ($currentCall -ne [UInt64]::MaxValue -or
                  $firstEligibleCall -ne [UInt64]0))) {
                throw 'G129 promotion reject predicate failed'
            }
            $rejectKey = "${identity}:$($record.reason):$($record.destination_kind)"
            if ($rejectKeys.ContainsKey($rejectKey)) {
                throw 'G129 promotion duplicate reject record failed'
            }
            $rejectKeys[$rejectKey] = $true
        } else {
            if ([string]$record.result -ne 'failed' -or
                [string]$record.reason -notin @('pread_failed', 'victim_contract') -or
                $firstEligibleCall -le $observationCall -or
                [string]$record.destination_kind -ne 'exact_iq2_ram_failed' -or
                -not $attemptByKey.ContainsKey($key) -or
                [string]$attemptByKey[$key] -ne $identity -or
                $terminalByKey.ContainsKey($key)) {
                throw 'G129 promotion failure record failed'
            }
            $terminalByKey[$key] = 'failure'
        }
    }
    foreach ($attemptKey in @($attemptByKey.Keys)) {
        if (-not $terminalByKey.ContainsKey($attemptKey)) {
            throw 'G129 promotion attempt missing terminal record'
        }
    }
    return [pscustomobject]@{
        observed = $true
        path = $artifactPath
        sha256 = $artifactSHA256.ToLowerInvariant()
        count = $recordCount
        physical_line_count = $physicalLineCount
        attempts = $attemptCount
        successes = $successCount
        rejects = $rejectCount
        failures = $failureCount
    }
}

function Assert-G129SafetyResult {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][bool]$PromotionEnabled
    )

    $samples = @($Result.results)
    if ([string]$Result.gate_kind -ne 'structural-safety' -or
        [int]$Result.repeats -ne 1 -or
        $samples.Count -ne 1 -or
        [bool]$Result.warmup -or
        [int]$Result.server_exit_code -ne 0 -or
        [bool]$Result.quality_eligible -or
        [bool]$Result.sota_eligible) {
        throw 'G129 safety n=1 structural-only contract failed'
    }
    if (-not [bool]$Result.force_open_router_requested -or
        -not [bool]$Result.compose_prefill_mass_open_router_requested -or
        [int]$Result.expert_tiering.compose_router_open -ne 1 -or
        [string]$Result.reap_mask_file_requested -or
        [bool]$Result.embedded_bake_mask_observed) {
        throw 'G129 safety full/open no-mask router contract failed'
    }
    if ([double]$Result.dynamic_arena_gib_requested -ne $primaryArenaGB -or
        [double]$Result.q1_0_dynamic_arena_gb_requested -ne $q1ArenaGB -or
        [bool]$Result.q1_0_dynamic_promotion_requested -ne
            $PromotionEnabled -or
        -not [bool]$Result.q1_0_dual_arena_requested -or
        -not [bool]$Result.q1_0_dual_arena_runtime_observed -or
        [bool]$Result.q1_0_snapshot_backing_requested -or
        -not [bool]$Result.q1_0_pageable_overflow_requested) {
        throw 'G129 safety dual-arena Q1 storage contract failed'
    }
    Assert-G129U64Positive $Result 'q1_0_bootstrap_pinned_bytes' 'Q1 pinned bytes'
    Assert-G129U64Positive $Result 'q1_0_bootstrap_pageable_bytes' 'Q1 pageable bytes'
    Assert-G129U64Positive $Result 'q1_0_bootstrap_pinned_slots' 'Q1 pinned slots'
    Assert-G129U64Positive $Result 'q1_0_bootstrap_pageable_slots' 'Q1 pageable slots'
    if ([UInt64]$Result.q1_0_bootstrap_entries -ne 11008 -or
        [UInt64]$Result.q1_0_bootstrap_total_slots -ne 11008 -or
        [UInt64]$Result.q1_0_bootstrap_layer_first -ne 0 -or
        [UInt64]$Result.q1_0_bootstrap_layer_last -ne 42 -or
        [UInt64]$Result.q1_0_layer_first_requested -ne 0 -or
        [UInt64]$Result.q1_0_layer_last_requested -ne 42 -or
        [UInt64]$Result.q1_0_resident_entries_expected -ne 11008 -or
        [UInt64]$Result.q1_0_bootstrap_total_bytes -ne
            ([UInt64]$Result.q1_0_bootstrap_pinned_bytes +
             [UInt64]$Result.q1_0_bootstrap_pageable_bytes)) {
        throw 'G129 safety complete Q1 resident base contract failed'
    }
    if (-not [bool]$Result.q1_0_source_unlock_observed -or
        [string]$Result.q1_0_source_unlock_result -ne 'complete' -or
        [int]$Result.q1_0_source_unlock_windows -ne 1 -or
        [int]$Result.q1_0_source_unlock_page_aligned -ne 1 -or
        [int]$Result.q1_0_source_unlock_destination_unchanged -ne 1 -or
        [UInt64]$Result.q1_0_source_unlock_layers -ne 43 -or
        [UInt64]$Result.q1_0_source_unlock_ranges_attempted -ne 129 -or
        [UInt64]$Result.q1_0_source_unlock_calls -ne 129 -or
        [UInt64]$Result.q1_0_source_unlock_calls -ne
            ([UInt64]$Result.q1_0_source_unlock_success +
             [UInt64]$Result.q1_0_source_unlock_not_locked +
             [UInt64]$Result.q1_0_source_unlock_failed) -or
        [UInt64]$Result.q1_0_source_unlock_bytes_attempted -eq 0) {
        throw 'G129 safety Q1 source mmap unlock telemetry contract failed'
    }
    if ([int]$Result.expert_tiering.replacement_budget_base -ne
            $tierReplacementBudget -or
        [int]$Result.expert_tiering.min_frequency -ne 3 -or
        [double]$Result.expert_tiering.hysteresis -ne 1.25) {
        throw 'G129 safety tier replacement policy contract failed'
    }
    if ([UInt64]$Result.q1_0_mixed.q1_resident -eq 0 -or
        ([UInt64]$Result.q1_0_mixed.iq2_vram +
         [UInt64]$Result.q1_0_mixed.iq2_snapshot_ram +
         [UInt64]$Result.q1_0_mixed.iq2_tier_ram) -eq 0 -or
        [UInt64]$Result.q1_0_mixed.failures -ne 0 -or
        [UInt64]$Result.q1_0_mixed.iq2_ssd_bytes -ne 0 -or
         [UInt64]$Result.q1_0_mixed.iq2_ssd_violations -ne 0) {
        throw 'G129 safety Q1 plus exact-IQ2 route contract failed'
    }
    if (-not [bool]$Result.q1_0_mixed_resolver_required -or
        -not [bool]$Result.q1_0_mixed_trace_requested -or
        [string]$Result.q1_0_mixed_expected_router -ne 'open' -or
        [string]$Result.q1_0_mixed.router_mode -ne 'open' -or
        [UInt64]$Result.q1_0_mixed.trace_rows -eq 0 -or
        [UInt64]$Result.q1_0_mixed.tier_route_entries -ne
            [UInt64]$Result.q1_0_mixed.trace_rows) {
        throw 'G129 safety Q1 mixed route-entry contract failed'
    }
    $q1MixedIq2Routes =
        [UInt64]$Result.q1_0_mixed.iq2_vram +
        [UInt64]$Result.q1_0_mixed.iq2_snapshot_ram +
        [UInt64]$Result.q1_0_mixed.iq2_tier_ram
    $q1MixedAccountedRoutes =
        [UInt64]$Result.q1_0_mixed.q1_resident +
        [UInt64]$q1MixedIq2Routes
    if ([UInt64]$Result.q1_0_mixed.trace_rows -ne
            [UInt64]$q1MixedAccountedRoutes -or
        [UInt64]$Result.q1_0_mixed_iq2_routes -ne
            [UInt64]$q1MixedIq2Routes -or
        [UInt64]$Result.q1_0_mixed_accounted_routes -ne
            [UInt64]$q1MixedAccountedRoutes -or
        [string]$Result.split_fused_primary_route_basis -ne
            'q1-0-mixed-iq2-routes' -or
        [UInt64]$Result.split_fused_primary_routes_expected -ne
            [UInt64]$q1MixedIq2Routes -or
        [UInt64]$Result.split_fused_primary_routes_observed -ne
            [UInt64]$q1MixedIq2Routes -or
        [UInt64]$Result.split_fused_q1_resident_routes_excluded -ne
            [UInt64]$Result.q1_0_mixed.q1_resident) {
        throw 'G129 safety SplitFused primary-route denominator contract failed'
    }
    if ($PromotionEnabled -and
        (-not [bool]$Result.iq1_promotion_runtime_observed -or
        [UInt64]$Result.iq1_promotion_q1_0_observed -eq 0 -or
        [UInt64]$Result.iq1_promotion_q1_0_stage_attempts -eq 0 -or
        [UInt64]$Result.iq1_promotion_q1_0_stage_successes -eq 0 -or
        [UInt64]$Result.iq1_promotion_q1_0_stage_successes -gt
            [UInt64]$Result.iq1_promotion_q1_0_stage_attempts -or
        [UInt64]$Result.iq1_promotion_q1_0_next_call_guards -ne
            [UInt64]$Result.iq1_promotion_q1_0_stage_successes -or
        [UInt64]$Result.iq1_promotion_failures -ne 0 -or
        [UInt64]$Result.iq1_promotion_direct_ssd_to_vram_rejected -ne 0)) {
        throw 'G129 safety dynamic promotion telemetry contract failed'
    }
    if (-not $PromotionEnabled -and
        ([bool]$Result.iq1_promotion_runtime_observed -or
         [UInt64]$Result.iq1_promotion_q1_0_observed -ne 0 -or
         [UInt64]$Result.iq1_promotion_q1_0_stage_attempts -ne 0 -or
         [UInt64]$Result.iq1_promotion_q1_0_stage_successes -ne 0 -or
         [UInt64]$Result.iq1_promotion_q1_0_next_call_guards -ne 0)) {
        throw 'G129 control observed dynamic promotion activity'
    }
    if ([UInt64]$Result.expert_tiering.forbidden_cold_ssd_to_vram -ne 0) {
        throw 'G129 safety forbidden direct SSD-to-VRAM transition observed'
    }
    return Assert-G129PromotionRecords `
        -Result $Result `
        -PromotionEnabled $PromotionEnabled
}

function New-G129SelfTestPromotionRecord {
    param(
        [Parameter(Mandatory=$true)][UInt64]$Line,
        [Parameter(Mandatory=$true)][string]$Kind,
        [UInt64]$RequestEpoch = 1,
        [UInt64]$PromotionWindowEpoch = 0,
        [UInt64]$RecordId = 1,
        [UInt64]$CurrentCall = 7,
        [UInt64]$FirstEligibleCall = 8,
        [UInt32]$Layer = 3,
        [UInt32]$Expert = 2,
        [UInt64]$GateRequestUsed = 0,
        [UInt64]$GateWindowUsed = 0,
        [double]$Weight = 0.03,
        [double]$Mass = 0.3,
        [UInt64]$TouchCount = 2,
        [string]$Reason = ''
    )

    $sourceGateBase = [UInt64]1000
    $sourceUpBase = [UInt64]2000
    $sourceDownBase = [UInt64]3000
    $sourceGateStride = [UInt64]100
    $sourceUpStride = [UInt64]100
    $sourceDownStride = [UInt64]200
    $sourceGateBytes = [UInt64]10
    $sourceUpBytes = [UInt64]10
    $sourceDownBytes = [UInt64]20
    $destinationGateBase = [UInt64]5000
    $destinationUpBase = [UInt64]7000
    $destinationDownBase = [UInt64]9000
    $destinationGateStride = [UInt64]100
    $destinationUpStride = [UInt64]100
    $destinationDownStride = [UInt64]200
    $destinationGateBytes = [UInt64]10
    $destinationUpBytes = [UInt64]10
    $destinationDownBytes = [UInt64]20
    $result = 'rejected'
    $destinationKind = 'none'
    $destinationSlot = [UInt64]4294967295
    $destinationGeneration = [UInt64]0
    if ($Kind -eq 'attempt') {
        $result = 'attempt'
        $Reason = if ($Reason) { $Reason } else { 'admitted' }
        $destinationKind = 'exact_iq2_ram_pending'
        $destinationSlot = [UInt64]7
    } elseif ($Kind -eq 'success') {
        $result = 'success'
        $Reason = if ($Reason) { $Reason } else { 'staged' }
        $destinationKind = 'exact_iq2_ram'
        $destinationSlot = [UInt64]7
        $destinationGeneration = [UInt64]99
    } elseif ($Kind -eq 'failure') {
        $result = 'failed'
        $Reason = if ($Reason) { $Reason } else { 'pread_failed' }
        $destinationKind = 'exact_iq2_ram_failed'
    } else {
        $Reason = if ($Reason) { $Reason } else { 'touches' }
    }

    [ordered]@{
        line_index = $Line
        physical_line = $Line
        kind = $Kind
        result = $result
        reason = $Reason
        record_id = $RecordId
        request_epoch = $RequestEpoch
        promotion_window_epoch = $PromotionWindowEpoch
        current_call = $CurrentCall
        observation_call = $CurrentCall
        first_eligible_call = $FirstEligibleCall
        layer = $Layer
        expert = $Expert
        touch_count = $TouchCount
        weight = $Weight
        mass = $Mass
        gate_min_touches = [UInt64]2
        gate_min_weight = 0.02
        gate_min_mass = 0.0
        gate_request_budget = [UInt64]64
        gate_request_used = $GateRequestUsed
        gate_window_calls = [UInt64]40
        gate_window_budget = [UInt64]1
        gate_window_used = $GateWindowUsed
        source_kind = 'q1_resident'
        source_sidecar_sha256 = $sidecarSHA
        source_sidecar_size = $ExpectedQ1_0ExpertSidecarBytes
        source_q1_snapshot = 0
        source_gate_base_offset = $sourceGateBase
        source_up_base_offset = $sourceUpBase
        source_down_base_offset = $sourceDownBase
        source_gate_stride = $sourceGateStride
        source_up_stride = $sourceUpStride
        source_down_stride = $sourceDownStride
        source_gate_offset = [UInt64](
            [decimal]$sourceGateBase + [decimal]$Expert * [decimal]$sourceGateStride)
        source_up_offset = [UInt64](
            [decimal]$sourceUpBase + [decimal]$Expert * [decimal]$sourceUpStride)
        source_down_offset = [UInt64](
            [decimal]$sourceDownBase + [decimal]$Expert * [decimal]$sourceDownStride)
        source_gate_bytes = $sourceGateBytes
        source_up_bytes = $sourceUpBytes
        source_down_bytes = $sourceDownBytes
        source_bytes = [UInt64]40
        destination_kind = $destinationKind
        destination_model_sha256 = $modelSHA
        destination_model_size = [UInt64]86720111488
        destination_gate_base_offset = $destinationGateBase
        destination_up_base_offset = $destinationUpBase
        destination_down_base_offset = $destinationDownBase
        destination_gate_stride = $destinationGateStride
        destination_up_stride = $destinationUpStride
        destination_down_stride = $destinationDownStride
        destination_gate_offset = [UInt64](
            [decimal]$destinationGateBase + [decimal]$Expert *
            [decimal]$destinationGateStride)
        destination_up_offset = [UInt64](
            [decimal]$destinationUpBase + [decimal]$Expert *
            [decimal]$destinationUpStride)
        destination_down_offset = [UInt64](
            [decimal]$destinationDownBase + [decimal]$Expert *
            [decimal]$destinationDownStride)
        destination_gate_bytes = $destinationGateBytes
        destination_up_bytes = $destinationUpBytes
        destination_down_bytes = $destinationDownBytes
        destination_bytes = [UInt64]40
        destination_ram_slot = $destinationSlot
        destination_ram_generation = $destinationGeneration
        direct_ssd_to_vram_current_token = 0
        same_call_eligible = 0
    }
}

function Write-G129SelfTestArtifact {
    param(
        [Parameter(Mandatory=$true)][object[]]$Records,
        [Parameter(Mandatory=$true)][string]$Name
    )

    New-Item -ItemType Directory -Force -Path $runs | Out-Null
    $path = Join-Path $runs (
        'g129_validator_selftest_' + $Name + '_' +
        [Guid]::NewGuid().ToString('N') + '.jsonl')
    $lines = @()
    for ($index = 0; $index -lt $Records.Count; $index++) {
        $Records[$index].line_index = [UInt64]($index + 1)
        $Records[$index].physical_line = [UInt64]($index + 1)
        $lines += ($Records[$index] | ConvertTo-Json -Compress -Depth 8)
    }
    $lines | Set-Content -LiteralPath $path -Encoding ASCII
    return [pscustomobject]@{
        path = $path
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).
            Hash.ToLowerInvariant()
        count = [UInt64]$Records.Count
    }
}

function New-G129SelfTestPromotionResult {
    param([Parameter(Mandatory=$true)][object]$Artifact,
          [UInt64]$Attempts = 1,
          [UInt64]$Successes = 1,
          [UInt64]$Rejects = 0,
          [UInt64]$Failures = 0)

    [pscustomobject]@{
        q1_0_promotion_records_observed = $true
        q1_0_promotion_records_count = $Artifact.count
        q1_0_promotion_records_physical_line_count = $Artifact.count
        q1_0_promotion_record_attempt_count = $Attempts
        q1_0_promotion_record_success_count = $Successes
        q1_0_promotion_record_reject_count = $Rejects
        q1_0_promotion_record_failure_count = $Failures
        q1_0_promotion_record_bounded_exception_limit =
            $promotionRecordBoundedExceptionLimit
        q1_0_promotion_telemetry_record_limit = [UInt64](
            ([decimal]$Attempts * [decimal]2) +
            [decimal]$promotionRecordBoundedExceptionLimit)
        iq1_promotion_q1_0_stage_attempts = $Attempts
        iq1_promotion_q1_0_stage_successes = $Successes
        iq1_promotion_q1_0_next_call_guards = $Successes
        iq1_promotion_failures = [UInt64](
            [decimal]$Failures + [decimal]$Rejects)
        iq1_promotion_q1_0_record_attempts = $Attempts
        iq1_promotion_q1_0_record_successes = $Successes
        iq1_promotion_q1_0_record_rejects = $Rejects
        iq1_promotion_q1_0_record_failures = $Failures
        q1_0_promotion_records_path = $Artifact.path
        q1_0_promotion_records_sha256 = $Artifact.sha256
        model_bytes = [UInt64]86720111488
    }
}

function New-G129SelfTestSafetyResult {
    param(
        [string]$Router = 'unchanged',
        [string]$RouterMode = 'open',
        [UInt64]$SplitObserved = 3
    )

    [pscustomobject]@{
        gate_kind = 'structural-safety'
        repeats = 1
        results = @([pscustomobject]@{ ok = $true })
        warmup = $false
        server_exit_code = 0
        quality_eligible = $false
        sota_eligible = $false
        force_open_router_requested = $true
        compose_prefill_mass_open_router_requested = $true
        expert_tiering = [pscustomobject]@{
            compose_router_open = 1
            replacement_budget_base = 32
            min_frequency = 3
            hysteresis = 1.25
            forbidden_cold_ssd_to_vram = 0
        }
        reap_mask_file_requested = ''
        embedded_bake_mask_observed = $false
        dynamic_arena_gib_requested = 5.5
        q1_0_dynamic_arena_gb_requested = 24.5
        q1_0_dynamic_promotion_requested = $false
        q1_0_dual_arena_requested = $true
        q1_0_dual_arena_runtime_observed = $true
        q1_0_snapshot_backing_requested = $false
        q1_0_pageable_overflow_requested = $true
        q1_0_bootstrap_pinned_bytes = [UInt64]1
        q1_0_bootstrap_pageable_bytes = [UInt64]1
        q1_0_bootstrap_pinned_slots = [UInt64]1
        q1_0_bootstrap_pageable_slots = [UInt64]1
        q1_0_bootstrap_entries = [UInt64]11008
        q1_0_bootstrap_total_slots = [UInt64]11008
        q1_0_bootstrap_layer_first = [UInt64]0
        q1_0_bootstrap_layer_last = [UInt64]42
        q1_0_layer_first_requested = [UInt64]0
        q1_0_layer_last_requested = [UInt64]42
        q1_0_resident_entries_expected = [UInt64]11008
        q1_0_bootstrap_total_bytes = [UInt64]2
        q1_0_source_unlock_observed = $true
        q1_0_source_unlock_result = 'complete'
        q1_0_source_unlock_windows = 1
        q1_0_source_unlock_page_aligned = 1
        q1_0_source_unlock_destination_unchanged = 1
        q1_0_source_unlock_layers = [UInt64]43
        q1_0_source_unlock_ranges_attempted = [UInt64]129
        q1_0_source_unlock_calls = [UInt64]129
        q1_0_source_unlock_success = [UInt64]0
        q1_0_source_unlock_not_locked = [UInt64]129
        q1_0_source_unlock_failed = [UInt64]0
        q1_0_source_unlock_bytes_attempted = [UInt64]1
        q1_0_mixed = [pscustomobject]@{
            q1_resident = [UInt64]3
            iq2_vram = [UInt64]2
            iq2_snapshot_ram = [UInt64]1
            iq2_tier_ram = [UInt64]0
            failures = [UInt64]0
            iq2_ssd_bytes = [UInt64]0
            iq2_ssd_violations = [UInt64]0
            trace_rows = [UInt64]6
            tier_route_entries = [UInt64]6
            router = $Router
            router_mode = $RouterMode
        }
        q1_0_mixed_resolver_required = $true
        q1_0_mixed_trace_requested = $true
        q1_0_mixed_expected_router = 'open'
        q1_0_mixed_iq2_routes = [UInt64]3
        q1_0_mixed_accounted_routes = [UInt64]6
        split_fused_primary_route_basis = 'q1-0-mixed-iq2-routes'
        split_fused_primary_routes_expected = [UInt64]3
        split_fused_primary_routes_observed = $SplitObserved
        split_fused_q1_resident_routes_excluded = [UInt64]3
        iq1_promotion_runtime_observed = $false
        iq1_promotion_q1_0_observed = [UInt64]0
        iq1_promotion_q1_0_stage_attempts = [UInt64]0
        iq1_promotion_q1_0_stage_successes = [UInt64]0
        iq1_promotion_q1_0_next_call_guards = [UInt64]0
        iq1_promotion_failures = [UInt64]0
        iq1_promotion_direct_ssd_to_vram_rejected = [UInt64]0
        q1_0_promotion_records_observed = $false
        q1_0_promotion_records_count = [UInt64]0
        q1_0_promotion_records_physical_line_count = [UInt64]0
        q1_0_promotion_records_path = ''
    }
}

function Invoke-G129ExpectFailure {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Body,
        [Parameter(Mandatory=$true)][string]$Expected,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        & $Body | Out-Null
    } catch {
        if ($_.Exception.Message -like "*$Expected*") {
            return
        }
        throw "G129 validator self-test $Name failed with wrong reason: $($_.Exception.Message)"
    }
    throw "G129 validator self-test $Name did not fail"
}

function Invoke-G129ValidatorSelfTest {
    $created = @()
    $evilDir = $null
    $createdEvilDir = $false
    try {
        $positiveArtifact = Write-G129SelfTestArtifact `
            -Name 'positive' `
            -Records @(
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'))
        $created += $positiveArtifact.path
        Assert-G129PromotionRecords `
            -Result (New-G129SelfTestPromotionResult -Artifact $positiveArtifact) `
            -PromotionEnabled $true | Out-Null

        $crossArtifact = Write-G129SelfTestArtifact `
            -Name 'cross_request' `
            -Records @(
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt' `
                    -RequestEpoch 1 -RecordId 1),
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success' `
                    -RequestEpoch 1 -RecordId 1),
                (New-G129SelfTestPromotionRecord -Line 3 -Kind 'attempt' `
                    -RequestEpoch 2 -RecordId 1),
                (New-G129SelfTestPromotionRecord -Line 4 -Kind 'success' `
                    -RequestEpoch 2 -RecordId 1))
        $created += $crossArtifact.path
        Assert-G129PromotionRecords `
            -Result (New-G129SelfTestPromotionResult `
                -Artifact $crossArtifact -Attempts 2 -Successes 2) `
            -PromotionEnabled $true | Out-Null

        $budgetArtifact = Write-G129SelfTestArtifact `
            -Name 'budget_duplicate' `
            -Records @(
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'),
                (New-G129SelfTestPromotionRecord -Line 3 -Kind 'attempt' `
                    -RecordId 2 -GateRequestUsed 1 -GateWindowUsed 0),
                (New-G129SelfTestPromotionRecord -Line 4 -Kind 'success' `
                    -RecordId 2 -GateRequestUsed 1 -GateWindowUsed 0))
        $created += $budgetArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'budget duplicate used=0' `
            -Expected 'window budget sequence failed' `
            -Body {
                Assert-G129PromotionRecords `
                    -Result (New-G129SelfTestPromotionResult `
                        -Artifact $budgetArtifact -Attempts 2 -Successes 2) `
                    -PromotionEnabled $true
            }

        $attempt = New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'
        $badSuccess = New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'
        $badSuccess.weight = 0.04
        $identityArtifact = Write-G129SelfTestArtifact `
            -Name 'identity_mismatch' `
            -Records @($attempt, $badSuccess)
        $created += $identityArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'terminal identity mismatch' `
            -Expected 'success record failed' `
            -Body {
                Assert-G129PromotionRecords `
                    -Result (New-G129SelfTestPromotionResult `
                        -Artifact $identityArtifact) `
                    -PromotionEnabled $true
            }

        $unpairedFailureArtifact = Write-G129SelfTestArtifact `
            -Name 'unpaired_failure' `
            -Records @(
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'),
                (New-G129SelfTestPromotionRecord -Line 3 -Kind 'failure' `
                    -RecordId 2))
        $created += $unpairedFailureArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'unpaired failure' `
            -Expected 'failure record failed' `
            -Body {
                Assert-G129PromotionRecords `
                    -Result (New-G129SelfTestPromotionResult `
                        -Artifact $unpairedFailureArtifact `
                        -Attempts 1 -Successes 1 -Failures 1) `
                    -PromotionEnabled $true
            }

        $duplicateTerminalArtifact = Write-G129SelfTestArtifact `
            -Name 'duplicate_terminal' `
            -Records @(
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'),
                (New-G129SelfTestPromotionRecord -Line 3 -Kind 'failure'))
        $created += $duplicateTerminalArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'duplicate terminal' `
            -Expected 'failure record failed' `
            -Body {
                Assert-G129PromotionRecords `
                    -Result (New-G129SelfTestPromotionResult `
                        -Artifact $duplicateTerminalArtifact `
                        -Attempts 1 -Successes 1 -Failures 1) `
                    -PromotionEnabled $true
            }

        $evilDir = Join-Path $root 'g7_runs_evil'
        if (-not (Test-Path -LiteralPath $evilDir)) {
            New-Item -ItemType Directory -Path $evilDir | Out-Null
            $createdEvilDir = $true
        }
        $evilPath = Join-Path $evilDir (
            'promotion_records_' + [Guid]::NewGuid().ToString('N') + '.jsonl')
        '{}' | Set-Content -LiteralPath $evilPath -Encoding ASCII
        $created += $evilPath
        $evilHash = (Get-FileHash -LiteralPath $evilPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
        Invoke-G129ExpectFailure `
            -Name 'path sibling g7_runs_evil' `
            -Expected 'escaped g7_runs' `
            -Body {
                Read-G129PromotionRecordArtifact `
                    -Path $evilPath -ExpectedSHA256 $evilHash -ExpectedCount 1
            }

        Invoke-G129ExpectFailure `
            -Name 'router wrong mode' `
            -Expected 'Q1 mixed route-entry contract failed' `
            -Body {
                Assert-G129SafetyResult `
                    -Result (New-G129SelfTestSafetyResult -RouterMode 'closed') `
                    -PromotionEnabled $false
            }
        $floodRecords = @(
            (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
            (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'))
        for ($i = 0; $i -lt 20; $i++) {
            $floodRecords += New-G129SelfTestPromotionRecord `
                -Line ([UInt64]($i + 3)) `
                -Kind 'reject' `
                -RecordId ([UInt64]($i + 2)) `
                -Reason 'offset_overflow'
        }
        $floodArtifact = Write-G129SelfTestArtifact `
            -Name 'telemetry_flood' `
            -Records $floodRecords
        $created += $floodArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'telemetry record flood' `
            -Expected 'telemetry record flood' `
            -Body {
                Assert-G129PromotionRecords `
                    -Result (New-G129SelfTestPromotionResult `
                        -Artifact $floodArtifact -Rejects 20) `
                    -PromotionEnabled $true
            }
        $failureFloodRecords = @(
            (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
            (New-G129SelfTestPromotionRecord -Line 2 -Kind 'failure'))
        for ($i = 0; $i -lt 17; $i++) {
            $failureFloodRecords += New-G129SelfTestPromotionRecord `
                -Line ([UInt64]($i + 3)) `
                -Kind 'reject' `
                -RecordId ([UInt64]($i + 2)) `
                -Reason 'offset_overflow'
        }
        $failureFloodArtifact = Write-G129SelfTestArtifact `
            -Name 'failure_terminal_flood' `
            -Records $failureFloodRecords
        $created += $failureFloodArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'failure terminal telemetry flood' `
            -Expected 'telemetry record flood' `
            -Body {
                Assert-G129PromotionRecords `
                    -Result (New-G129SelfTestPromotionResult `
                        -Artifact $failureFloodArtifact `
                        -Attempts 1 -Successes 0 -Failures 1 -Rejects 17) `
                    -PromotionEnabled $true `
                    -AllowZeroSuccess
            }

        $strictExistingStderrPath = Join-Path $runs (
            'g129_validator_selftest_existing_stderr_' +
            [Guid]::NewGuid().ToString('N') + '.log')
        @(
            (Convert-G129SelfTestPromotionRecordToMarkerLine `
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt')),
            (Convert-G129SelfTestPromotionRecordToMarkerLine `
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'))
        ) | Set-Content -LiteralPath $strictExistingStderrPath -Encoding ASCII
        $created += $strictExistingStderrPath
        foreach ($case in @(
                @{ name = 'malformed'; content = 'not-json' },
                @{ name = 'array'; content = '[]' },
                @{ name = 'duplicate_key'; content = '{"kind":"attempt","kind":"success"}' })) {
            $strictExistingArtifactPath = Join-Path $runs (
                'g129_validator_selftest_existing_' + $case.name + '_' +
                [Guid]::NewGuid().ToString('N') + '.jsonl')
            [string]$case.content |
                Set-Content -LiteralPath $strictExistingArtifactPath -Encoding ASCII
            $created += $strictExistingArtifactPath
            $strictExistingArtifact = Export-G129PromotionRecordArtifactFromStderr `
                -StderrPath $strictExistingStderrPath `
                -ArtifactPath $strictExistingArtifactPath
            if ([UInt64]$strictExistingArtifact.count -ne 2 -or
                -not $strictExistingArtifact.PSObject.Properties[
                    'materialization_note']) {
                throw "G129 validator self-test existing artifact $($case.name) was not regenerated"
            }
        }
        $staleHashArtifact = Write-G129SelfTestArtifact `
            -Name 'stale_hash' `
            -Records @(
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt'),
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success'))
        $created += $staleHashArtifact.path
        Invoke-G129ExpectFailure `
            -Name 'stale promotion artifact hash' `
            -Expected 'SHA-256 mismatch' `
            -Body {
                Read-G129PromotionRecordArtifact `
                    -Path $staleHashArtifact.path `
                    -ExpectedSHA256 ('0' * 64) `
                    -ExpectedCount $staleHashArtifact.count
            }

        $script:childTag = 'g129_validator_selftest_failure_' +
            [Guid]::NewGuid().ToString('N')
        New-Item -ItemType Directory -Force -Path $runs | Out-Null
        $selftestStderrPath = Join-Path $runs (
            'g7_' + $script:childTag + '_stderr.log')
        $selftestStdoutPath = Join-Path $runs (
            'g7_' + $script:childTag + '_stdout.log')
        $selftestFailurePath = Join-Path $runs (
            'g7_' + $script:childTag + '_failure.json')
        $selftestRawPath = Join-Path $runs (
            'g7_' + $script:childTag + '_raw_outputs.json')
        $selftestTelemetryPath = Join-Path $runs (
            'g7_' + $script:childTag + '_runtime_telemetry.jsonl')
        @(
            'synthetic stderr before record',
            (Convert-G129SelfTestPromotionRecordToMarkerLine `
                (New-G129SelfTestPromotionRecord -Line 1 -Kind 'attempt')),
            (Convert-G129SelfTestPromotionRecordToMarkerLine `
                (New-G129SelfTestPromotionRecord -Line 2 -Kind 'success')),
            'synthetic stderr after record'
        ) | Set-Content -LiteralPath $selftestStderrPath -Encoding ASCII
        'synthetic stdout' |
            Set-Content -LiteralPath $selftestStdoutPath -Encoding ASCII
        [ordered]@{
            schema = 'g129_validator_selftest_failure_v1'
            reason = 'router_mismatch'
        } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath $selftestFailurePath -Encoding ASCII
        [ordered]@{
            schema = 'g129_validator_selftest_raw_outputs_v1'
            result = 'router_mismatch'
        } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath $selftestRawPath -Encoding ASCII
        '{"schema":"g129_validator_selftest_runtime_telemetry_v1"}' |
            Set-Content -LiteralPath $selftestTelemetryPath -Encoding ASCII
        $created += @(
            $selftestStderrPath,
            $selftestStdoutPath,
            $selftestFailurePath,
            $selftestRawPath,
            $selftestTelemetryPath)
        $selftestReceiptInfo = Write-G129SafetyFailureReceipt `
            -Reason 'result-contract-failed' `
            -Detail 'router mismatch selftest' `
            -ChildExitCode 1
        $created += @(
            $selftestReceiptInfo.receipt_path,
            $selftestReceiptInfo.index_path)
        $selftestReceipt = Get-Content `
            -LiteralPath $selftestReceiptInfo.receipt_path -Raw |
            ConvertFrom-Json
        $selftestReceiptIndex = Get-Content `
            -LiteralPath $selftestReceiptInfo.index_path -Raw |
            ConvertFrom-Json
        if (-not [bool]$selftestReceipt.q1_0_promotion_records_observed -or
            [UInt64]$selftestReceipt.q1_0_promotion_records_count -ne 2 -or
            [UInt64]$selftestReceipt.q1_0_promotion_records_physical_line_count -ne 2 -or
            -not [string]$selftestReceipt.q1_0_promotion_records_sha256 -or
            [string]$selftestReceipt.q1_0_promotion_records_materialization_error -or
            [string]$selftestReceipt.PSObject.Properties['receipt_sha256'] -or
            -not [string]$selftestReceipt.failure_sha256 -or
            -not [string]$selftestReceipt.stderr_sha256 -or
            -not [string]$selftestReceipt.raw_outputs_sha256 -or
            -not [string]$selftestReceipt.runtime_telemetry_sha256 -or
            [string]$selftestReceiptIndex.receipt_path -ne
                [string]$selftestReceiptInfo.receipt_path -or
            [string]$selftestReceiptIndex.receipt_sha256 -ne
                [string]$selftestReceiptInfo.receipt_sha256) {
            throw 'G129 validator self-test failure receipt materialization failed'
        }
        $created += [string]$selftestReceipt.q1_0_promotion_records_path
        Invoke-G129ExpectFailure `
            -Name 'SplitFused mismatch' `
            -Expected 'SplitFused primary-route denominator contract failed' `
            -Body {
                Assert-G129SafetyResult `
                    -Result (New-G129SelfTestSafetyResult -SplitObserved 4) `
                    -PromotionEnabled $false
            }

        $argvCapture = Invoke-G129BootstrapChild `
            -HarnessArguments @(
                '-GateKind', 'structural-safety',
                '-Tag', 'g129_argv_capture',
                '-Prompt', 'value with spaces') `
            -BootstrapWhatIf `
            -CaptureOutput
        if ([int]$argvCapture.exit_code -ne 0) {
            throw 'G129 validator self-test argv capture child failed'
        }
        $argvPayload = (($argvCapture.output | ForEach-Object {
                [string]$_
            }) -join [Environment]::NewLine) | ConvertFrom-Json
        $expectedArgv = @(
            '-GateKind', 'structural-safety',
            '-Tag', 'g129_argv_capture',
            '-Prompt', 'value with spaces')
        $actualArgv = @($argvPayload.harness_arguments)
        $stopParsingLiteral = '--' + '%'
        if ($actualArgv.Count -ne $expectedArgv.Count -or
            ($actualArgv -contains '--') -or
            ($actualArgv -contains $stopParsingLiteral)) {
            throw 'G129 validator self-test argv delimiter was forwarded'
        }
        for ($i = 0; $i -lt $expectedArgv.Count; $i++) {
            if ([string]$actualArgv[$i] -ne [string]$expectedArgv[$i]) {
                throw 'G129 validator self-test argv order was not preserved'
            }
        }
        $nonCaptureExit = Invoke-G129BootstrapChild `
            -HarnessArguments @(
                '-GateKind', 'structural-safety',
                '-Tag', 'g129_argv_noncapture',
                '-Prompt', 'multi line whatif output') `
            -BootstrapWhatIf 6>$null
        if (@($nonCaptureExit).Count -ne 1 -or
            $nonCaptureExit -is [array] -or
            $nonCaptureExit -isnot [int] -or
            [int]$nonCaptureExit -ne 0) {
            throw 'G129 validator self-test bootstrap non-capture exit code was not scalar Int32'
        }

        [pscustomobject]@{
            schema = 'g129_validator_selftest_v1'
            status = 'pass'
            positive_records = 2
            cross_request_record_id_reuse = 'pass'
            argv_capture = 'pass'
            argv_non_capture_scalar = 'pass'
            negative_cases = @(
                'budget duplicate used=0',
                'terminal identity mismatch',
                'unpaired failure',
                'duplicate terminal',
                'path sibling g7_runs_evil',
                'router wrong mode',
                'telemetry record flood',
                'failure terminal telemetry flood',
                'existing artifact malformed',
                'existing artifact array',
                'existing artifact duplicate key',
                'stale promotion artifact hash',
                'failure receipt materialization',
                'SplitFused mismatch')
        } | ConvertTo-Json -Depth 5
    } finally {
        foreach ($path in $created) {
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                Remove-Item -LiteralPath $path -Force
            }
        }
        if ($createdEvilDir -and $evilDir -and
            (Test-Path -LiteralPath $evilDir -PathType Container)) {
            Remove-Item -LiteralPath ([string]$evilDir) -Force -Recurse
        }
    }
}

function Get-G129PromotionMarkerFields {
    @(
        'kind', 'result', 'reason', 'record_id', 'request_epoch',
        'promotion_window_epoch', 'current_call', 'observation_call',
        'first_eligible_call',
        'layer', 'expert', 'touch_count', 'weight', 'mass',
        'gate_min_touches', 'gate_min_weight', 'gate_min_mass',
        'gate_request_budget', 'gate_request_used', 'gate_window_calls',
        'gate_window_budget', 'gate_window_used', 'source_kind',
        'source_sidecar_sha256', 'source_sidecar_size',
        'source_q1_snapshot', 'source_gate_base_offset',
        'source_up_base_offset', 'source_down_base_offset',
        'source_gate_stride', 'source_up_stride', 'source_down_stride',
        'source_gate_offset', 'source_up_offset', 'source_down_offset',
        'source_gate_bytes', 'source_up_bytes', 'source_down_bytes',
        'source_bytes', 'destination_kind', 'destination_model_sha256',
        'destination_model_size', 'destination_gate_base_offset',
        'destination_up_base_offset', 'destination_down_base_offset',
        'destination_gate_stride', 'destination_up_stride',
        'destination_down_stride', 'destination_gate_offset',
        'destination_up_offset', 'destination_down_offset',
        'destination_gate_bytes', 'destination_up_bytes',
        'destination_down_bytes', 'destination_bytes',
        'destination_ram_slot', 'destination_ram_generation',
        'direct_ssd_to_vram_current_token', 'same_call_eligible'
    )
}

function Convert-G129MarkerUInt64 {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -notmatch '^(0|[1-9][0-9]*)$') {
        throw "G129 marker strict UInt64 parse rejected $Name=$Value"
    }
    try {
        return [UInt64]::Parse(
            $Value, [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "G129 marker strict UInt64 parse overflow for $Name=$Value"
    }
}

function Convert-G129MarkerUInt32 {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    $parsed = Convert-G129MarkerUInt64 $Value $Name
    if ($parsed -gt [UInt64][UInt32]::MaxValue) {
        throw "G129 marker strict UInt32 parse overflow for $Name=$Value"
    }
    return [UInt32]$parsed
}

function Convert-G129MarkerFlag01 {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -notmatch '^[01]$') {
        throw "G129 marker strict flag parse rejected $Name=$Value"
    }
    return [int]$Value
}

function Convert-G129MarkerDouble {
    param([Parameter(Mandatory=$true)][string]$Value,
          [Parameter(Mandatory=$true)][string]$Name)

    if ($Value -notmatch '^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$') {
        throw "G129 marker strict double parse rejected $Name=$Value"
    }
    $parsed = [double]::Parse(
        $Value, [Globalization.CultureInfo]::InvariantCulture)
    if ([double]::IsNaN($parsed) -or [double]::IsInfinity($parsed)) {
        throw "G129 marker strict double parse rejected non-finite $Name=$Value"
    }
    return $parsed
}

function Convert-G129PromotionMarkerLineToRecord {
    param(
        [Parameter(Mandatory=$true)][string]$Line,
        [Parameter(Mandatory=$true)][UInt64]$LineIndex,
        [Parameter(Mandatory=$true)][UInt64]$PhysicalLine
    )

    $lineMatch = [regex]::Match(
        $Line,
        '^(?:ds4: )?\[q1-0-promotion-record\] (?<kv>(?:[A-Za-z0-9_]+=[^ \r\n]+)(?: [A-Za-z0-9_]+=[^ \r\n]+)*)$')
    if (-not $lineMatch.Success) {
        throw "G129 promotion malformed marker at physical line $PhysicalLine"
    }
    $required = Get-G129PromotionMarkerFields
    $allowed = @{}
    foreach ($field in $required) { $allowed[$field] = $true }
    $fields = @{}
    foreach ($part in @($lineMatch.Groups['kv'].Value -split ' ')) {
        if ($part -notmatch '^([A-Za-z0-9_]+)=([^ \r\n]+)$') {
            throw "G129 promotion malformed key/value token at physical line ${PhysicalLine}: $part"
        }
        $key = $Matches[1]
        $value = $Matches[2]
        if (-not $allowed.ContainsKey($key)) {
            throw "G129 promotion unexpected telemetry key at physical line ${PhysicalLine}: $key"
        }
        if ($fields.ContainsKey($key)) {
            throw "G129 promotion duplicate telemetry key at physical line ${PhysicalLine}: $key"
        }
        $fields[$key] = $value
    }
    foreach ($requiredField in $required) {
        if (-not $fields.ContainsKey($requiredField)) {
            throw "G129 promotion omitted $requiredField at physical line $PhysicalLine"
        }
    }

    $doubleFields = @{
        weight = $true; mass = $true
        gate_min_weight = $true; gate_min_mass = $true
    }
    $uint32Fields = @{ layer = $true; expert = $true }
    $flagFields = @{
        source_q1_snapshot = $true
        direct_ssd_to_vram_current_token = $true
        same_call_eligible = $true
    }
    $stringFields = @{
        kind = $true; result = $true; reason = $true
        source_kind = $true; source_sidecar_sha256 = $true
        destination_kind = $true; destination_model_sha256 = $true
    }
    $row = [ordered]@{
        line_index = $LineIndex
        physical_line = $PhysicalLine
    }
    foreach ($field in $required) {
        if ($stringFields.ContainsKey($field)) {
            $value = [string]$fields[$field]
            if ($field -like '*sha256') {
                $value = $value.ToLowerInvariant()
            }
            $row[$field] = $value
        } elseif ($doubleFields.ContainsKey($field)) {
            $row[$field] = Convert-G129MarkerDouble $fields[$field] $field
        } elseif ($uint32Fields.ContainsKey($field)) {
            $row[$field] = Convert-G129MarkerUInt32 $fields[$field] $field
        } elseif ($flagFields.ContainsKey($field)) {
            $row[$field] = Convert-G129MarkerFlag01 $fields[$field] $field
        } else {
            $row[$field] = Convert-G129MarkerUInt64 $fields[$field] $field
        }
    }
    return [pscustomobject]$row
}

function Convert-G129SelfTestPromotionRecordToMarkerLine {
    param([Parameter(Mandatory=$true)][object]$Record)

    $parts = @()
    foreach ($field in Get-G129PromotionMarkerFields) {
        $value = $Record.$field
        if ($value -is [double]) {
            $text = $value.ToString(
                'G17', [Globalization.CultureInfo]::InvariantCulture)
        } else {
            $text = [Convert]::ToString(
                $value, [Globalization.CultureInfo]::InvariantCulture)
        }
        $parts += ($field + '=' + $text)
    }
    return 'ds4: [q1-0-promotion-record] ' + ($parts -join ' ')
}

function Get-G129ArtifactReceipt {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            present = $false
            path = $Path
            sha256 = ''
            bytes = [UInt64]0
        }
    }
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        present = $true
        path = $Path
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).
            Hash.ToLowerInvariant()
        bytes = [UInt64]$item.Length
    }
}

function Get-G129PromotionRecordArtifactSummary {
    param([Parameter(Mandatory=$true)][string]$Path)

    $lines = [IO.File]::ReadAllLines($Path)
    return [pscustomobject][ordered]@{
        observed = [bool]($lines.Count -gt 0)
        path = $Path
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).
            Hash.ToLowerInvariant()
        count = [UInt64]$lines.Count
        physical_line_count = [UInt64]$lines.Count
    }
}

function New-G129PromotionRecordValidationResult {
    param([Parameter(Mandatory=$true)][object]$Artifact)

    $records = @(Read-G129PromotionRecordArtifact `
        -Path $Artifact.path `
        -ExpectedSHA256 $Artifact.sha256 `
        -ExpectedCount $Artifact.count)
    $attempts = [UInt64](
        @($records | Where-Object { [string]$_.kind -eq 'attempt' }).Count)
    $successes = [UInt64](
        @($records | Where-Object { [string]$_.kind -eq 'success' }).Count)
    $rejects = [UInt64](
        @($records | Where-Object { [string]$_.kind -eq 'reject' }).Count)
    $failures = [UInt64](
        @($records | Where-Object { [string]$_.kind -eq 'failure' }).Count)
    return [pscustomobject][ordered]@{
        q1_0_promotion_records_observed = $Artifact.observed
        q1_0_promotion_records_count = $Artifact.count
        q1_0_promotion_records_physical_line_count =
            $Artifact.physical_line_count
        q1_0_promotion_record_attempt_count = $attempts
        q1_0_promotion_record_success_count = $successes
        q1_0_promotion_record_reject_count = $rejects
        q1_0_promotion_record_failure_count = $failures
        q1_0_promotion_record_bounded_exception_limit =
            $promotionRecordBoundedExceptionLimit
        q1_0_promotion_telemetry_record_limit = [UInt64](
            ([decimal]$attempts * [decimal]2) +
            [decimal]$promotionRecordBoundedExceptionLimit)
        iq1_promotion_q1_0_stage_attempts = $attempts
        iq1_promotion_q1_0_stage_successes = $successes
        iq1_promotion_q1_0_next_call_guards = $successes
        iq1_promotion_failures = [UInt64](
            [decimal]$failures + [decimal]$rejects)
        iq1_promotion_q1_0_record_attempts = $attempts
        iq1_promotion_q1_0_record_successes = $successes
        iq1_promotion_q1_0_record_rejects = $rejects
        iq1_promotion_q1_0_record_failures = $failures
        q1_0_promotion_records_path = $Artifact.path
        q1_0_promotion_records_sha256 = $Artifact.sha256
        model_bytes = [UInt64]86720111488
    }
}

function Assert-G129PromotionRecordArtifactStrict {
    param([Parameter(Mandatory=$true)][object]$Artifact)

    $validationResult = New-G129PromotionRecordValidationResult `
        -Artifact $Artifact
    return Assert-G129PromotionRecords `
        -Result $validationResult `
        -PromotionEnabled $true `
        -AllowZeroSuccess
}

function Export-G129PromotionRecordArtifactFromStderr {
    param(
        [Parameter(Mandatory=$true)][string]$StderrPath,
        [Parameter(Mandatory=$true)][string]$ArtifactPath
    )

    $existingArtifactError = ''
    if (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) {
        try {
            $existingArtifact = Get-G129PromotionRecordArtifactSummary `
                -Path $ArtifactPath
            Assert-G129PromotionRecordArtifactStrict `
                -Artifact $existingArtifact | Out-Null
            return $existingArtifact
        } catch {
            $existingArtifactError = $_.Exception.Message
        }
    }
    if (-not (Test-Path -LiteralPath $StderrPath -PathType Leaf)) {
        if ($existingArtifactError) {
            throw "G129 existing promotion artifact invalid and stderr missing: $existingArtifactError"
        }
        return [pscustomobject][ordered]@{
            observed = $false
            path = ''
            sha256 = ''
            count = [UInt64]0
            physical_line_count = [UInt64]0
        }
    }
    $stderrLines = [IO.File]::ReadAllLines($StderrPath)
    $records = @()
    for ($index = 0; $index -lt $stderrLines.Count; $index++) {
        $line = [string]$stderrLines[$index]
        if (-not $line.Contains('[q1-0-promotion-record]')) {
            continue
        }
        $records += Convert-G129PromotionMarkerLineToRecord `
            -Line $line `
            -LineIndex ([UInt64]($records.Count + 1)) `
            -PhysicalLine ([UInt64]($index + 1))
    }
    if ($records.Count -eq 0) {
        if ($existingArtifactError) {
            throw "G129 existing promotion artifact invalid and stderr has no canonical records: $existingArtifactError"
        }
        return [pscustomobject][ordered]@{
            observed = $false
            path = ''
            sha256 = ''
            count = [UInt64]0
            physical_line_count = [UInt64]0
        }
    }
    $jsonLines = @($records | ForEach-Object {
        $_ | ConvertTo-Json -Compress -Depth 8
    })
    $jsonLines | Set-Content -LiteralPath $ArtifactPath -Encoding ASCII
    $artifact = Get-G129PromotionRecordArtifactSummary -Path $ArtifactPath
    Assert-G129PromotionRecordArtifactStrict -Artifact $artifact | Out-Null
    if ($existingArtifactError) {
        $artifact | Add-Member -NotePropertyName materialization_note `
            -NotePropertyValue (
                'regenerated_from_stderr_after_invalid_existing=' +
                $existingArtifactError)
    }
    return $artifact
}

function Write-G129SafetyFailureReceiptIndex {
    param([Parameter(Mandatory=$true)][string]$ReceiptPath)

    $receiptItem = Get-Item -LiteralPath $ReceiptPath -Force
    $receiptSHA256 = (Get-FileHash -LiteralPath $ReceiptPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    $indexPath = Join-Path $runs (
        'g7_' + $childTag + '_safety_failure_receipt_index.json')
    [ordered]@{
        schema = 'ds4_g129_q1_open_dynamic_promotion_safety_failure_index_v1'
        tag = $childTag
        receipt_path = $ReceiptPath
        receipt_sha256 = $receiptSHA256
        receipt_bytes = [UInt64]$receiptItem.Length
    } | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $indexPath -Encoding UTF8
    return [pscustomobject][ordered]@{
        receipt_path = $ReceiptPath
        receipt_sha256 = $receiptSHA256
        receipt_bytes = [UInt64]$receiptItem.Length
        index_path = $indexPath
        index_sha256 = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
    }
}

function Write-G129SafetyFailureReceipt {
    param(
        [Parameter(Mandatory=$true)][string]$Reason,
        [string]$Detail = '',
        [int]$ChildExitCode = 0
    )

    $resultPath = Join-Path $runs ('g7_' + $childTag + '_result.json')
    $failurePath = Join-Path $runs ('g7_' + $childTag + '_failure.json')
    $stderrPath = Join-Path $runs ('g7_' + $childTag + '_stderr.log')
    $stdoutPath = Join-Path $runs ('g7_' + $childTag + '_stdout.log')
    $rawOutputsPath = Join-Path $runs ('g7_' + $childTag + '_raw_outputs.json')
    $memoryPreflightPath = Join-Path $runs (
        'g7_' + $childTag + '_memory_preflight.json')
    $processIsolationPath = Join-Path $runs (
        'g7_' + $childTag + '_process_isolation_preflight.json')
    $systemQuiescencePath = Join-Path $runs (
        'g7_' + $childTag + '_system_quiescence_preflight.json')
    $runtimeTelemetryPath = Join-Path $runs (
        'g7_' + $childTag + '_runtime_telemetry.jsonl')
    $promotionRecordsPath = Join-Path $runs (
        'g7_' + $childTag + '_q1_0_promotion_records.jsonl')
    $receiptPath = Join-Path $runs (
        'g7_' + $childTag + '_safety_failure_receipt.json')
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        return Write-G129SafetyFailureReceiptIndex -ReceiptPath $receiptPath
    }
    $promotionArtifactError = ''
    try {
        $promotionArtifact = Export-G129PromotionRecordArtifactFromStderr `
            -StderrPath $stderrPath `
            -ArtifactPath $promotionRecordsPath
    } catch {
        $promotionArtifactError = $_.Exception.Message
        $promotionArtifact = [pscustomobject][ordered]@{
            observed = $false
            path = ''
            sha256 = ''
            count = [UInt64]0
            physical_line_count = [UInt64]0
        }
    }
    $resultArtifact = Get-G129ArtifactReceipt -Path $resultPath
    $failureArtifact = Get-G129ArtifactReceipt -Path $failurePath
    $stderrArtifact = Get-G129ArtifactReceipt -Path $stderrPath
    $stdoutArtifact = Get-G129ArtifactReceipt -Path $stdoutPath
    $rawOutputsArtifact = Get-G129ArtifactReceipt -Path $rawOutputsPath
    $memoryPreflightArtifact = Get-G129ArtifactReceipt -Path $memoryPreflightPath
    $processIsolationArtifact = Get-G129ArtifactReceipt -Path $processIsolationPath
    $systemQuiescenceArtifact = Get-G129ArtifactReceipt -Path $systemQuiescencePath
    $runtimeTelemetryArtifact = Get-G129ArtifactReceipt -Path $runtimeTelemetryPath
    [ordered]@{
        schema = 'ds4_g129_q1_open_dynamic_promotion_safety_failure_v1'
        status = 'failed_structural_n1_no_performance_or_quality_verdict'
        claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
        tag = $childTag
        arm = $Arm
        reason = $Reason
        detail = $Detail
        child_exit_code = $ChildExitCode
        result_path = $resultPath
        result_sha256 = $resultArtifact.sha256
        failure_path = $failurePath
        failure_sha256 = $failureArtifact.sha256
        stderr_path = $stderrPath
        stderr_sha256 = $stderrArtifact.sha256
        stdout_path = $stdoutPath
        stdout_sha256 = $stdoutArtifact.sha256
        raw_outputs_path = $rawOutputsPath
        raw_outputs_sha256 = $rawOutputsArtifact.sha256
        runtime_telemetry_path = $runtimeTelemetryPath
        runtime_telemetry_sha256 = $runtimeTelemetryArtifact.sha256
        memory_preflight_path = $memoryPreflightPath
        memory_preflight_sha256 = $memoryPreflightArtifact.sha256
        process_isolation_preflight_path = $processIsolationPath
        process_isolation_preflight_sha256 = $processIsolationArtifact.sha256
        system_quiescence_preflight_path = $systemQuiescencePath
        system_quiescence_preflight_sha256 = $systemQuiescenceArtifact.sha256
        q1_0_promotion_records_observed = $promotionArtifact.observed
        q1_0_promotion_records_path = $promotionArtifact.path
        q1_0_promotion_records_sha256 = $promotionArtifact.sha256
        q1_0_promotion_records_count = $promotionArtifact.count
        q1_0_promotion_records_physical_line_count =
            $promotionArtifact.physical_line_count
        q1_0_promotion_records_materialization_error =
            $promotionArtifactError
        q1_0_promotion_records_materialization_note =
            $(if ($promotionArtifact.PSObject.Properties['materialization_note']) {
                [string]$promotionArtifact.materialization_note
            } else {
                ''
            })
        prompt_sha256 = $promptSHA
        configuration_sha256 = $configurationSHA
        routing_contract = 'full/open routing preserved; no masks or closed router'
        dynamic_promotion = $promotionEnabled
        artifacts = [ordered]@{
            result = $resultArtifact
            failure = $failureArtifact
            stderr = $stderrArtifact
            stdout = $stdoutArtifact
            raw_outputs = $rawOutputsArtifact
            runtime_telemetry = $runtimeTelemetryArtifact
            memory_preflight = $memoryPreflightArtifact
            process_isolation_preflight = $processIsolationArtifact
            system_quiescence_preflight = $systemQuiescenceArtifact
            q1_0_promotion_records = $promotionArtifact
        }
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $receiptPath -Encoding UTF8
    return Write-G129SafetyFailureReceiptIndex -ReceiptPath $receiptPath
}

function Get-G129PowerShellHost {
    $hostPath = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
        $hostPath = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    return $hostPath
}

function Invoke-G129BootstrapChild {
    param(
        [Parameter(Mandatory=$true)][string[]]$HarnessArguments,
        [switch]$BootstrapWhatIf,
        [switch]$CaptureOutput
    )

    $payload = [ordered]@{
        bootstrap_path = $bootstrap
        harness_path = $harness
        repo_root = $root
        bootstrap_what_if = [bool]$BootstrapWhatIf
        harness_arguments = @('--') + @($HarnessArguments)
    }
    $payloadJson = $payload | ConvertTo-Json -Compress -Depth 8
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes($payloadJson)
    $payloadBase64 = [Convert]::ToBase64String($payloadBytes)
    $childScript = @"
`$ErrorActionPreference = 'Stop'
`$payloadJson = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String('$payloadBase64'))
`$payload = `$payloadJson | ConvertFrom-Json
`$bootstrapArgs = @{
    HarnessPath = [string]`$payload.harness_path
    RepoRoot = [string]`$payload.repo_root
    HarnessArguments = @(`$payload.harness_arguments)
}
if ([bool]`$payload.bootstrap_what_if) {
    `$bootstrapArgs['WhatIf'] = `$true
}
& ([string]`$payload.bootstrap_path) @bootstrapArgs
if (`$LASTEXITCODE -ne `$null) {
    exit [int]`$LASTEXITCODE
}
exit 0
"@
    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($childScript))
    $powershellHost = Get-G129PowerShellHost
    if ($CaptureOutput) {
        $output = & $powershellHost -NoLogo -NoProfile `
            -ExecutionPolicy Bypass -EncodedCommand $encodedCommand 2>&1
        $exitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
        return [pscustomobject][ordered]@{
            exit_code = $exitCode
            output = @($output)
        }
    }
    $output = & $powershellHost -NoLogo -NoProfile `
        -ExecutionPolicy Bypass -EncodedCommand $encodedCommand 2>&1
    foreach ($line in @($output)) {
        Write-Host $line
    }
    $exitCode = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
    return [int]$exitCode
}

if ($SelfTest) {
    Invoke-G129ValidatorSelfTest
    exit 0
}

foreach ($path in @($harness, $bootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "G129 safety required script missing: $path"
    }
}
if ((Get-G129Sha256Text -Text $prompt) -ne $promptSHA) {
    throw 'G129 safety prompt SHA-256 mismatch'
}
if (-not $WhatIf) {
    foreach ($path in @($model, "$model.receipt.json", $sidecar)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "G129 safety required file missing: $path"
        }
    }
    $sidecar = (Resolve-Path -LiteralPath $sidecar).Path
    if ([UInt64](Get-Item -LiteralPath $sidecar).Length -ne
        $ExpectedQ1_0ExpertSidecarBytes) {
        throw 'G129 safety Q1_0 sidecar size mismatch'
    }
}

$suffix = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
    '_' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$childTag = $Tag + '_' + $suffix
$arguments = @(
    '-GateKind', 'structural-safety',
    '-ModelPath', $model,
    '-ExpectedModelSHA256', $modelSHA,
    '-ReuseVerifiedModelReceipt',
    '-Prompt', $prompt,
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
    '-ComposePrefillMassReserveSlots', [string]$reserveSlots,
    '-DynamicArenaGiB', $primaryArenaGBText,
    '-Q1_0ExpertSidecar', $sidecar,
    '-ExpectedQ1_0ExpertSidecarSHA256', $sidecarSHA,
    '-ExpectedQ1_0ExpertSidecarBytes', ([string]$ExpectedQ1_0ExpertSidecarBytes),
    '-ReuseVerifiedQ1_0Receipt',
    '-Q1_0SelectedLoad',
    '-Q1_0ResidentArena',
    '-Q1_0DualArena',
    '-Q1_0PageableOverflow',
    '-Q1_0ArenaGB', $q1ArenaGBText,
    '-Q1_0LayerFirst', '0',
    '-Q1_0LayerLast', '42',
    '-ExpectedQ1_0ResidentEntries', '11008',
    '-Q1_0MixedTrace',
    '-DisableQ8F16Cache',
    '-EmbedRowStaging',
    '-ReapPrefetchThreads', '8',
    '-ExpertCacheN', [string]$cacheSlots,
    '-ExpertCacheReserveGB', '0.125',
    '-ExpertCachePolicy', 'lru',
    '-GpuResidentRoutes',
    '-RouteNoDefaultSync',
    '-ExpertTiering', 'enforce',
    '-ExpertTierPolicy', 'mass-lfru',
    '-ExpertTierClockCalls', '430',
    '-ExpertTierReplacementBudget', [string]$tierReplacementBudget,
    '-ExpertTierMinFrequency', '3',
    '-ExpertTierHysteresis', '1.25',
    '-PrefillVramSeedTotal', '320',
    '-PrefillVramSeedFloorPerLayer', '4',
    '-SplitFused',
    '-RuntimeMinimumAvailableGiB', '2',
    '-RuntimeHardMinimumAvailableGiB', '1',
    '-RuntimeMaximumDiskQueueLength', '8',
    '-RuntimeContaminationSamples', '3',
    '-QuiescenceCooldownSec', '10',
    '-TimeoutSec', [string]$TimeoutSec,
    '-Tag', $childTag
)
if ($promotionEnabled) {
    $arguments += @(
        '-Q1_0DynamicPromotion',
        '-Q1_0PromotionProbationSlots', [string]$reserveSlots,
        '-Q1_0PromotionMinTouches', '2',
        '-Q1_0PromotionMinWeight', '0.02',
        '-Q1_0PromotionMinMass', '0',
        '-Q1_0PromotionRequestBudget', '64',
        '-Q1_0PromotionWindowCalls', '40',
        '-Q1_0PromotionWindowBudget', '1'
    )
    if ($Q1_0PromotionSsdWrap) {
        $arguments += @(
            '-Q1_0PromotionSsdWrap',
            '-Q1_0Iq2PinnedGiB',
            $Q1_0Iq2PinnedGiB.ToString(
                'R', [Globalization.CultureInfo]::InvariantCulture)
        )
    }
} elseif ($Q1_0PromotionSsdWrap) {
    throw 'Q1_0PromotionSsdWrap is valid only for the promotion arm'
}

if ($WhatIf) {
    [pscustomobject]@{
        schema = 'g129_q1_open_dynamic_promotion_safety_plan_v1'
        status = 'whatif_no_runtime'
        arm = $Arm
        tag = $childTag
        n = 1
        claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
        configuration_sha256 = $configurationSHA
        dynamic_promotion = $promotionEnabled
        q1_0_promotion_ssd_wrap = [bool]$Q1_0PromotionSsdWrap
        q1_0_iq2_pinned_gib = $Q1_0Iq2PinnedGiB
        q1_0_storage = [ordered]@{
            dynamic_arena_gb = $q1ArenaGB
            pageable_overflow = $true
            expected_entries = 11008
        }
        exact_iq2_storage = [ordered]@{
            primary_dynamic_arena_gib = $primaryArenaGB
            open_router_reserve_slots = $reserveSlots
            vram_cache_slots = $cacheSlots
            tier_replacement_budget = $tierReplacementBudget
            mixed_resolver = $true
        }
        promotion_gate = [ordered]@{
            enabled = $promotionEnabled
            min_touches = $(if ($promotionEnabled) { 2 } else { 0 })
            min_weight = $(if ($promotionEnabled) { 0.02 } else { 0 })
            min_mass = 0
            request_budget = $(if ($promotionEnabled) { 64 } else { 0 })
            window_calls = $(if ($promotionEnabled) { 40 } else { 0 })
            window_budget = $(if ($promotionEnabled) { 1 } else { 0 })
        }
        harness_arguments = @($arguments)
    } | ConvertTo-Json -Depth 8
    exit 0
}

$childExitCode = 0
try {
    $childExitCode = [int](Invoke-G129BootstrapChild `
        -HarnessArguments $arguments)
} catch {
    if ($LASTEXITCODE -ne $null) {
        $childExitCode = [int]$LASTEXITCODE
    }
    $failureReceiptInfo = Write-G129SafetyFailureReceipt `
        -Reason 'child-exception' `
        -Detail $_.Exception.Message `
        -ChildExitCode $childExitCode
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT=' + $failureReceiptInfo.receipt_path)
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT_SHA256=' + $failureReceiptInfo.receipt_sha256)
    throw
}
if ($childExitCode -ne 0) {
    $failureReceiptInfo = Write-G129SafetyFailureReceipt `
        -Reason 'child-exit-nonzero' `
        -Detail ('exit_code=' + $childExitCode) `
        -ChildExitCode $childExitCode
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT=' + $failureReceiptInfo.receipt_path)
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT_SHA256=' + $failureReceiptInfo.receipt_sha256)
    throw "G129 safety child failed with exit code $childExitCode"
}

$resultPath = Join-Path $runs ('g7_' + $childTag + '_result.json')
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    $failureReceiptInfo = Write-G129SafetyFailureReceipt `
        -Reason 'result-missing' `
        -Detail $resultPath `
        -ChildExitCode $childExitCode
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT=' + $failureReceiptInfo.receipt_path)
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT_SHA256=' + $failureReceiptInfo.receipt_sha256)
    throw "G129 safety result missing: $resultPath"
}
$result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
$promotionRecordArtifact = $null
try {
    $promotionRecordArtifact = Assert-G129SafetyResult `
        -Result $result `
        -PromotionEnabled $promotionEnabled
} catch {
    $failureReceiptInfo = Write-G129SafetyFailureReceipt `
        -Reason 'result-contract-failed' `
        -Detail $_.Exception.Message `
        -ChildExitCode $childExitCode
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT=' + $failureReceiptInfo.receipt_path)
    Write-Output ('G129_SAFETY_FAILURE_RECEIPT_SHA256=' + $failureReceiptInfo.receipt_sha256)
    throw
}
$resultSHA = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).
    Hash.ToLowerInvariant()

$receipt = [ordered]@{
    schema = 'ds4_g129_q1_open_dynamic_promotion_safety_v1'
    status = 'pass_structural_n1_no_performance_or_quality_verdict'
    claim_scope = 'structural_safety_only_no_sota_no_quality_verdict'
    tag = $childTag
    result_path = $resultPath
    result_sha256 = $resultSHA
    prompt_sha256 = $promptSHA
    configuration_sha256 = $configurationSHA
    routing_contract = 'full/open routing preserved; no masks or closed router'
    q1_0_promotion_record_artifact = $promotionRecordArtifact
}
$receiptPath = Join-Path $runs ('g7_' + $childTag + '_receipt.json')
if (Test-Path -LiteralPath $receiptPath) {
    throw "G129 immutable safety receipt already exists: $receiptPath"
}
$receipt | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $receiptPath -Encoding UTF8
$receiptSHA = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).
    Hash.ToLowerInvariant()
Write-Output ('G129_SAFETY_RECEIPT=' + $receiptPath)
Write-Output ('G129_SAFETY_RECEIPT_SHA256=' + $receiptSHA)
