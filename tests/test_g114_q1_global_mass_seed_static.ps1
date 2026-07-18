$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$cuda = Get-Content -LiteralPath (Join-Path $root "ds4_cuda.cu") -Raw
$harness = Get-Content -LiteralPath (Join-Path $root "g7_measure.ps1") -Raw
$runner = Get-Content -LiteralPath (Join-Path $root "g114_q1_iq2_global_mass_safety.ps1") -Raw

function Require-Text([string]$Text, [string]$Needle, [string]$Label) {
    if (-not $Text.Contains($Needle)) {
        throw "missing $Label"
    }
}

Require-Text $cuda "DS4_CUDA_PREFILL_VRAM_SEED_TOTAL" "global seed env"
Require-Text $cuda "DS4_CUDA_PREFILL_VRAM_SEED_FLOOR_PER_LAYER" "global floor env"
Require-Text $cuda "request-scoped-global-mass" "global mass semantics"
Require-Text $cuda "ranked.begin() + layer_floor" "floor exclusion from global candidates"
Require-Text $cuda "a.prior_mass > b.prior_mass" "descending mass rank"
Require-Text $cuda "prefill VRAM seed mode/budget contract invalid" "runtime fail-closed contract"
Require-Text $harness '[ValidateRange(0, 512)][int]$PrefillVramSeedTotal' "harness total parameter"
Require-Text $harness "PrefillVramSeedTotal is mutually exclusive with PrefillVramSeedPerLayer" "harness mode isolation"
Require-Text $harness "prefill-vram-seed-global" "global telemetry parser"
Require-Text $harness "request-scoped-global-mass" "global telemetry validation"
Require-Text $runner '"-PrefillVramSeedTotal"' "runner total argument"
Require-Text $runner '"-PrefillVramSeedFloorPerLayer"' "runner floor argument"
Require-Text $runner '"-ExpertCacheN", ([string]$SeedTotal)' "cache equals total budget"
Require-Text $runner '[UInt64]$mixed.iq2_ssd_bytes -ne 0' "zero SSD gate"
Require-Text $runner '[UInt64]$result.q1_0_resident_misses -ne 0' "zero Q1 miss gate"

Write-Host "test_g114_q1_global_mass_seed_static: PASS"
