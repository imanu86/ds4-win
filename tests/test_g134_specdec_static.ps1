$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$core = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4.c')
$header = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4.h')
$cli = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4_cli.c')
$server = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4_server.c')

function Require-Literal([string]$Text, [string]$Needle, [string]$Contract) {
    if (-not $Text.Contains($Needle)) {
        throw "G134 specdec static contract missing ($Contract): $Needle"
    }
}

function Require-Regex([string]$Text, [string]$Pattern, [string]$Contract) {
    if ($Text -notmatch $Pattern) {
        throw "G134 specdec static contract mismatch ($Contract): $Pattern"
    }
}

Require-Literal $core 'getenv("DS4_G134_SPECDEC")' 'named opt-in flag'
Require-Literal $core 'strcmp(env, "1") == 0' 'strict OFF-default value'
Require-Literal $core 'const bool enable_spec_state = enable_mtp || enable_specdec;' 'flag-scoped scratch'
Require-Literal $core 'if (enable_specdec) {' 'prefix-2 allocation only under G134'

Require-Literal $core 'DS4_G134_DRAFT_K = 2' 'fixed k=2'
Require-Literal $core 'DS4_G134_VERIFY_MAX = DS4_G134_DRAFT_K + 1' 'two drafts plus bonus position'
Require-Literal $core 'g134_prompt_lookup_n2k2' 'host n=2 lookup'
Require-Literal $core 'for (int i = logical_len - 3; i >= 0; i--)' 'most-recent suffix match'
Require-Literal $core 'return g134_greedy_accept_prefix(synthetic_drafts, 2,' 'synthetic exactness self-test'
Require-Literal $core 'G134 prompt-lookup self-test failed; refusing opt-in' 'fail-closed startup self-test'

Require-Literal $core 'metal_graph_verify_g134_exact' 'n2k2 exact verifier'
Require-Literal $core 'metal_graph_encode_decode_layer(g,' 'normal exact decode machinery reuse'
Require-Literal $core 'metal_graph_encode_output_head(g, model, weights,' 'normal exact output-head reuse'
Require-Literal $core 'g->spec_logits' 'multi-position logits reuse'
Require-Literal $core 'metal_graph_capture_prefix1_attn_state' 'bonus-only frontier capture'
Require-Literal $core 'metal_graph_capture_prefix2_attn_state' 'bonus-plus-one frontier capture'
Require-Literal $core 'spec_frontier_commit_prefix1(s)' 'zero-draft rollback'
Require-Literal $core 'spec_frontier_commit_prefix2(s)' 'one-draft rollback'
Require-Literal $core 'spec_frontier_restore(&frontier, s)' 'failure rollback'
Require-Literal $core '(uint64_t)visible_raw + n_inputs > s->graph.raw_cap' 'strict raw-ring exactness gate'

Require-Literal $core 'spec_pass_count=%" PRIu64' 'spec pass attribution'
foreach ($field in @('drafted=%', 'accepted=%', 'bonus=%', 'fallback_passes=%', 'accept_rate=%.6f')) {
    Require-Literal $core $field "attribution $field"
}

Require-Literal $header 'ds4_session_eval_g134_specdec_argmax' 'public session API'
Require-Literal $cli 'ds4_session_g134_specdec_enabled(session)' 'CLI temp-0 dispatch'
Require-Literal $cli 'ds4_session_g134_specdec_enabled(chat->session)' 'REPL temp-0 dispatch'
Require-Literal $server 'ds4_session_g134_specdec_enabled(s->session)' 'server temp-0 dispatch'
Require-Regex $cli 'temperature <= 0\.0f\s*&&\s*ds4_session_g134_specdec_enabled' 'CLI greedy-only gate'
Require-Regex $server 'temperature <= 0\.0f\s*&&\s*ds4_session_g134_specdec_enabled' 'server greedy-only gate'

Write-Output 'G134 specdec static contract: PASS'
