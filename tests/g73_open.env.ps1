# G73-OPEN phase-1 preset. Dot-source this file before starting ds4-server.
# Frozen G73 values come from g73_split_fused_ab.ps1:367-384 and ledger row
# WIN-G7-G73-SPLIT-FUSED-N3. The open/rotator delta is marked below.

# Frozen G73 transport: 30 GiB yields 4,551 resident slots at 7,077,888 B/slot.
$env:DS4_CUDA_STREAM_RESERVE_MB = '1024'
$env:DS4_CUDA_DYNAMIC_ARENA_GB = '30'
$env:DS4_CUDA_ARENA_WRAP_TRUST_WORKER_CHECKSUM = '1'
$env:DS4_CUDA_ARENA_WRAP_SCHEDULE = 'source-parts'
$env:DS4_CUDA_ARENA_WRAP_UNLOCK_SOURCE_RANGES = '1'
$env:DS4_CUDA_ARENA_WRAP_UNLOCK_WAVE_GIB = '4'
$env:DS4_CUDA_NO_Q8_F16_CACHE = '1'
$env:DS4_CUDA_EMBED_ROW_STAGING = '1'
$env:DS4_REAP_PREFETCH_THREADS = '8'
$env:DS4_CUDA_PREFILL_MASS_OBSERVE = '1'
$env:DS4_CUDA_PREFILL_MASS_WRAP = '1'
$env:DS4_CUDA_PREFILL_TIER_COMPOSE = '1'
$env:DS4_CUDA_STREAMING_EXPERT_CACHE_N = '320'
$env:DS4_CUDA_STREAMING_EXPERT_CACHE_RESERVE_GB = '0.125'
$env:DS4_CUDA_MOE_CACHE_POLICY = 'lru'
$env:DS4_CUDA_MOE_GPU_RESIDENT_ROUTES = '1'
$env:DS4_CUDA_MOE_ROUTE_NO_DEFAULT_SYNC = '1'
$env:DS4_EXPERT_TIERING = 'enforce'
$env:DS4_EXPERT_TIER_POLICY = 'mass-lfru'
$env:DS4_EXPERT_TIER_CLOCK_CALLS = '430'
$env:DS4_EXPERT_TIER_REPLACEMENT_BUDGET = '32'
$env:DS4_EXPERT_TIER_MIN_FREQUENCY = '3'
$env:DS4_EXPERT_TIER_HYSTERESIS = '1.25'

# G73-OPEN delta: unbiased router, exact transient escape, and a 64-slot
# rotating part of the same pinned arena. SSD-wrap uses four extra ring slots,
# so the ledger's 4,551 resident-slot capacity is unchanged.
$env:DS4_G73_OPEN = '1'
$env:DS4_CUDA_PREFILL_TIER_ROUTER = 'open'
$env:DS4_CUDA_PREFILL_TIER_RESERVE_SLOTS = '64'
$env:DS4_G133_TIER = '1'
$env:DS4_G133_KNOCK_X = '3'
$env:DS4_G133_KNOCK_Y = '5'
$env:DS4_G133_DECAY = '0.98'
$env:DS4_G133_SEED_DYNAMIC = '1'
$env:DS4_G133_PROMOTE_BUDGET = '8'
$env:DS4_G133_TRANSIENT_IO_TIMEOUT_S = '0.25'
$env:DS4_G130_U1_ATTRIBUTION = '1'
$env:DS4_MODEL_SHA256 = 'efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668'

# Phase 1 keeps the exact fail-open selected-load fallback simple by disabling
# split dispatch. Re-enable only after its partial-launch failure path can replay.
$env:DS4_CUDA_MOE_SPLIT_HIT_MISS = '0'
$env:DS4_CUDA_MOE_SPLIT_FUSED = '0'

# Q1/IQ1 are neither serving tiers nor shadow substitutes in this preset.
Remove-Item Env:\DS4_Q1_0_MIXED_COLD_ONE -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_IQ1_S_MIXED_COLD_K -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_Q1_0_SNAPSHOT_BACKING -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_Q1_0_DYNAMIC_PROMOTION -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_Q1_0_SELECTED_LOAD -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_Q1_0_EXPERT_SIDECAR -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_IQ1_S_EXPERT_SIDECAR -ErrorAction SilentlyContinue
Remove-Item Env:\DS4_REAP_MASK_FILE -ErrorAction SilentlyContinue
