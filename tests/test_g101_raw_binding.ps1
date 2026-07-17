# G101 raw/result binding regression test (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runner = Join-Path $root "g101_iq1_promotion_combined_ba.ps1"

$defaultStatic = . $runner -StaticCheckOnly
$defaultMetadata = $defaultStatic | ConvertFrom-Json
$reverseStatic = . $runner -StaticCheckOnly `
    -ExecutionOrder "legacy-then-combined"
$reverseMetadata = $reverseStatic | ConvertFrom-Json

if ([string]$defaultMetadata.execution_order -ne "combined-then-legacy" -or
    [string]$reverseMetadata.execution_order -ne "legacy-then-combined") {
    throw "G101 static check did not preserve default and reverse execution order"
}
if (-not [bool]$defaultMetadata.both_execution_orders_static_checked -or
    -not [bool]$reverseMetadata.both_execution_orders_static_checked) {
    throw "G101 static check did not verify both execution plans"
}
if ([string]$defaultMetadata.pair_member -ne "BA" -or
    [string]$reverseMetadata.pair_member -ne "AB" -or
    -not [bool]$defaultMetadata.counterbalanced_pair_intent -or
    -not [bool]$reverseMetadata.counterbalanced_pair_intent) {
    throw "G101 counterbalanced-pair intent metadata is incomplete"
}
if ([string]$defaultMetadata.final_performance_verdict -ne
        "withheld_single_order_counterbalanced_pair_member" -or
    [string]$reverseMetadata.final_performance_verdict -ne
        "withheld_single_order_counterbalanced_pair_member") {
    throw "G101 single-order verdict is not withheld"
}

$defaultDefinition =
    Get-G101ExecutionDefinition -Order "combined-then-legacy"
$reverseDefinition =
    Get-G101ExecutionDefinition -Order "legacy-then-combined"
$defaultTags = @($defaultDefinition.arms | ForEach-Object { [string]$_.Tag })
$reverseTags = @($reverseDefinition.arms | ForEach-Object { [string]$_.Tag })
if (($defaultTags -join "|") -ne
    "g101_iq1_promotion_combined_gate_n3|g101_iq1_promotion_legacy_gate_n3") {
    throw "G101 default tags changed"
}
if ((@($defaultDefinition.arms | ForEach-Object { [string]$_.Arm }) -join
        "|") -ne "candidate-combined-gate|control-legacy-gate" -or
    (@($reverseDefinition.arms | ForEach-Object { [string]$_.Arm }) -join
        "|") -ne "control-legacy-gate|candidate-combined-gate") {
    throw "G101 default/reverse arm order is wrong"
}
foreach ($tag in $defaultTags) {
    if ($reverseTags -contains $tag) {
        throw "G101 default/reverse tag collision: $tag"
    }
}
$defaultArtifacts = @(
    [string]$defaultDefinition.summary_file,
    [string]$defaultDefinition.suite_receipt_file,
    [string]$defaultDefinition.execution_receipt_file)
$reverseArtifacts = @(
    [string]$reverseDefinition.summary_file,
    [string]$reverseDefinition.suite_receipt_file,
    [string]$reverseDefinition.execution_receipt_file)
if ($defaultArtifacts[0] -ne "g101_iq1_promotion_combined_ba_result.json") {
    throw "G101 default summary path changed"
}
foreach ($path in $defaultArtifacts) {
    if ($reverseArtifacts -contains $path) {
        throw "G101 default/reverse artifact collision: $path"
    }
}

$hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$lockProof = [pscustomobject]@{
    required = $true
    observed = $true
}
$results = @(
    [pscustomobject]@{ content_sha256 = $hash },
    [pscustomobject]@{ content_sha256 = $hash },
    [pscustomobject]@{ content_sha256 = $hash }
)
$shared = [ordered]@{
    tag = "g101_binding_test"
    gate_kind = "benchmark"
    contamination_reason = ""
    head = "0123456789abcdef"
    executable_sha256 = $hash
    ds4_cuda_sha256 = $hash
    model_sha256 = $hash
    iq1_s_sidecar_sha256 = $hash
    prompt_sha256 = $hash
    system_prompt_sha256 = $hash
    model_iq1_suite_receipt_path = "suite.json"
    model_iq1_suite_receipt_sha256 = $hash
    model_iq1_suite_receipt_schema = "g7_model_iq1_suite_receipt_v1"
    model_iq1_suite_full_hash_verified = $true
    model_iq1_suite_lock_proof = $lockProof
    results = $results
}
$raw = [pscustomobject]([ordered]@{
    schema = "g7_raw_outputs_v1"
} + $shared + [ordered]@{
    output_hashes = @($hash)
})
$result = [pscustomobject]$shared
$plan = [pscustomobject]@{ Tag = "g101_binding_test" }

Assert-G101RawBinding -Raw $raw -Result $result -Plan $plan

$badRaw = $raw | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$badRaw.output_hashes = @(
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)
$failedClosed = $false
try {
    Assert-G101RawBinding -Raw $badRaw -Result $result -Plan $plan
} catch {
    if ($_.Exception.Message -match "raw/result output hash mismatch") {
        $failedClosed = $true
    } else {
        throw
    }
}
if (-not $failedClosed) {
    throw "G101 raw binding accepted an altered unique output hash"
}

$tempPreflight = Join-Path ([IO.Path]::GetTempPath()) (
    "g101_quiescence_" + [Guid]::NewGuid().ToString("n") + ".json")
try {
    [IO.File]::WriteAllText($tempPreflight, (@{
        schema = "g7_system_quiescence_preflight_v1"
        skipped = $false
        ready_to_launch = $false
        failures = @("disk-io-median-above-threshold")
    } | ConvertTo-Json), [Text.Encoding]::UTF8)
    if (-not (Test-G101RetryableQuiescenceFailure $tempPreflight)) {
        throw "G101 rejected a valid retryable quiescence failure"
    }
    [IO.File]::WriteAllText($tempPreflight, (@{
        schema = "g7_system_quiescence_preflight_v1"
        skipped = $false
        ready_to_launch = $true
        failures = @()
    } | ConvertTo-Json), [Text.Encoding]::UTF8)
    if (Test-G101RetryableQuiescenceFailure $tempPreflight) {
        throw "G101 retried an already clean quiescence preflight"
    }
} finally {
    Remove-Item -LiteralPath $tempPreflight -Force -ErrorAction SilentlyContinue
}

Write-Host "G101 raw binding tests PASS"
