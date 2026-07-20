# G73 Live HTML B CPU Mock Integration Protocol

## Scope

This protocol validates the dedicated live runner lifecycle and two-turn HTTP
conversation without loading DS4, the model, CUDA, or the native build. It does
not validate G73 mask behavior, model quality, or performance.

The owned files are:

- `g73_live_html_b_end_to_end.ps1`
- `tests/g73_live_html_b_mock_server.py`
- `tests/test_g73_live_html_b_mock_integration.py`
- this protocol

The canonical `g73_split_fused_ab.ps1` and all runtime sources remain unchanged.

## Explicit mode

Use `-MockIntegration -MockScenario <scenario>`. Mock mode must:

- launch only the Python standard-library mock server;
- skip model, executable, build-manifest, CUDA, and GPU-sampler access;
- use HTTP `GET /health` for readiness;
- send `stop` as exactly `</html>`, temperature `0`, and `think=false`;
- preserve the first assistant content in memory and insert that exact UTF-8 text
  into request 2;
- write native summary and a mock validation receipt;
- use the same owned-process, timeout, lock, and cleanup implementation as live mode.

The successful request roles are exactly:

- request 1: `system`, `user`
- request 2: `system`, `user`, `assistant`, `user`

Request 2 contains the canonical system text, prompt 1, the live mock response 1
without normalization, and prompt 2. The mock captures raw HTTP JSON bytes and a
separate canonical JSON encoding for each request.

## Scenarios

`success` returns two deterministic complete HTML documents. Turn 1 must pass the
synthetic structural L2 contract, then turn 2 must pass the dark structural gate.
This label is test-fixture terminology and is not a model quality claim.

`exit-before-readiness` exits with code 23 before binding. The runner must detect
the real child exit, write failure artifacts, remove its lock, and send no request.

`malformed-turn1` returns fenced and incomplete HTML. The runner must write turn 1
artifacts, fail the readiness-for-turn-2 gate, send no second request, clean up the
mock, and write failure artifacts.

## Commands

```powershell
powershell -NoProfile -File .\g73_live_html_b_end_to_end.ps1 -MockIntegration -StaticCheckOnly
powershell -NoProfile -File .\g73_live_html_b_end_to_end.ps1 -MockIntegration -LifecycleSelfTest
powershell -NoProfile -File .\g73_live_html_b_end_to_end.ps1 -MockIntegration -MockScenario success -WhatIf
$python = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $python .\tests\test_g73_live_html_b_mock_integration.py
```

All three scenarios are n=1 CPU tests. They must run sequentially and leave no
mock process or current runner lock.
