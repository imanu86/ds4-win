# G101 raw/result binding regression test (PowerShell 5.1, ASCII).
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runner = Join-Path $root "g101_iq1_promotion_combined_ba.ps1"

. $runner -StaticCheckOnly | Out-Null

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
