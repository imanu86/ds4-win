$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$core = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4.c')
$header = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4.h')
$cli = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4_cli.c')
$server = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4_server.c')
$gpuHeader = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4_gpu.h')
$cuda = Get-Content -Raw -LiteralPath (Join-Path $repo 'ds4_cuda.cu')

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

function Slice-Between([string]$Text, [string]$Start, [string]$End) {
    $a = $Text.IndexOf($Start)
    if ($a -lt 0) { throw "G134 specdec static contract missing slice start: $Start" }
    $b = $Text.IndexOf($End, $a + $Start.Length)
    if ($b -lt 0) { throw "G134 specdec static contract missing slice end: $End" }
    return $Text.Substring($a, $b - $a)
}

Require-Literal $core 'getenv("DS4_G134_SPECDEC")' 'named opt-in flag'
Require-Literal $core 'strcmp(env, "1") == 0' 'strict OFF-default value'
Require-Literal $core 'const bool enable_spec_state = enable_mtp || enable_specdec;' 'flag-scoped scratch'
Require-Literal $core 'if (enable_specdec) {' 'prefix-2 allocation only under G134'

Require-Literal $core 'DS4_G134_DRAFT_K = 2' 'fixed k=2'
Require-Literal $core 'DS4_G134_VERIFY_MAX = DS4_G134_DRAFT_K + 1' 'two drafts plus bonus position'
Require-Literal $core 'g134_prompt_lookup_n2k2' 'host n=2 lookup'
Require-Literal $core 'for (int i = logical_len - 3; i >= 0; i--)' 'most-recent suffix match'
Require-Literal $core 'g134_greedy_accept_prefix(synthetic_drafts, 2, accept0) != 0' 'host acceptance-0 self-test'
Require-Literal $core 'g134_greedy_accept_prefix(synthetic_drafts, 2, accept1) != 1' 'host acceptance-1 self-test'
Require-Literal $core 'g134_greedy_accept_prefix(synthetic_drafts, 2, accept2) != 2' 'host acceptance-2 self-test'
Require-Literal $core 'g134_committed_draft_prefix(synthetic_drafts, 2, 5,' 'host EOS truncation self-test'
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

$verifier = Slice-Between $core 'static bool metal_graph_verify_g134_exact(' `
    '/* Pick a raw SWA cache size for Metal.'
Require-Literal $verifier 'epochs[j].speculative_position = j + 1u;' 'verifier speculative marks'
if ($verifier.Contains('ds4_gpu_g133_decode_position_begin()')) {
    throw 'G134 verifier must not allocate committed G133 epochs'
}

$g134Eval = Slice-Between $core 'int ds4_session_eval_g134_specdec_argmax(' `
    '/* Speculative decode state machine:'
Require-Literal $g134Eval 'accepted_drafts = g134_committed_draft_prefix(' 'EOS excluded from commit count'
Require-Literal $g134Eval 'if (accepted_eos) accepted[committed_inputs] = eos_token;' 'EOS returned only as stop signal'
Require-Regex $g134Eval 'for \(int i = 0; i < accepted_drafts; i\+\+\)\s*\{\s*accepted\[i \+ 1\] = drafts\[i\];\s*token_vec_push' 'checkpoint contains only pre-EOS drafts'
Require-Literal $g134Eval 'ds4_gpu_speculative_observation_finish(' 'accepted observation commit'

$fallback = Slice-Between $core 'static int ds4_session_g134_fallback(' `
    '#ifndef DS4_NO_GPU'
Require-Literal $fallback 'ds4_session_eval_internal(s, first_token, false' 'single-drafter fallback'
if ($fallback.Contains('ds4_session_eval(s, first_token')) {
    throw 'G134 fallback must not invoke native-MTP-probing ds4_session_eval'
}

Require-Literal $gpuHeader 'uint32_t speculative_position;' 'speculative position mark'
Require-Literal $gpuHeader 'ds4_gpu_speculative_observation_begin' 'deferred observation begin API'
Require-Literal $gpuHeader 'ds4_gpu_speculative_observation_finish' 'deferred observation finish API'
Require-Literal $cuda 'cuda_speculative_observation_record_route(' 'route observation buffer'
Require-Literal $cuda 'cuda_speculative_observation_record_iq1_stage(' 'IQ1 tier action buffer'
Require-Literal $cuda 'for (uint32_t position = 1u; position <= committed_positions; position++)' 'accepted-only position-major flush'
Require-Regex $cuda 'cuda_speculative_epoch_valid\(g133_epoch\)\)\s*\{\s*cuda_speculative_observation_record_route[\s\S]*?return prior;' 'speculative tier observation deferral'

Require-Literal $core 'getenv("DS4_G134_SPECDEC_VERIFY")' 'behavioral verify gate'
Require-Literal $core 'g134_behavioral_verify_replay' 'plain-decode replay verifier'
Require-Literal $core 'metal_graph_eval_token_raw_swa(&s->graph' 'normal decode recomputation'
Require-Literal $core 'memcmp(plain_logits, verifier_logits' 'final-logits identity assertion'
Require-Literal $core 'acceptance-shape coverage is runtime-dependent' 'honest runtime coverage label'

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
Require-Literal $cli 'cli_g134_specdec_requested()' 'one-shot normal-config session dispatch'
Require-Regex $cli 'cli_g134_specdec_requested\(\)\)\s*\{\s*rc = run_sampled_generation' 'one-shot G134 reachability'

Write-Output 'G134 specdec static contract: PASS (host acceptance/EOS covered; GPU acceptance, rollback, and context shapes remain runtime-gated by DS4_G134_SPECDEC_VERIFY=1)'
