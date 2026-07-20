from __future__ import annotations

import hashlib
import json
import subprocess
import time
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "g73_live_html_b_end_to_end.ps1"
MOCK = ROOT / "tests" / "g73_live_html_b_mock_server.py"
PROTOCOL = ROOT / "G73_LIVE_HTML_B_MOCK_INTEGRATION_PROTOCOL.md"
OUT_ROOT = ROOT / "r"
POWERSHELL = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")

SYSTEM_PROMPT = "You are a coding assistant. Follow the user instructions exactly."
PROMPT1 = (
    "Create a complete single-file HTML landing page for a cyberpunk AI programming "
    "shop. Include CSS, navigation, hero, request form, and a JavaScript confirmation "
    "popup. Return only the HTML document."
)
PROMPT2 = (
    "Rendi il sito appena creato completamente dark mantenendo struttura e funzionalità. "
    "Usa uno sfondo quasi nero, contrasto accessibile e accenti neon ciano e magenta; "
    "aggiorna coerentemente tutto il CSS e restituisci l'intero documento HTML "
    "modificato, senza spiegazioni."
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run_runner(*args: str, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(POWERSHELL),
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(RUNNER),
            "-MockIntegration",
            *args,
        ],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def new_tag(scenario: str) -> str:
    return f"m_{scenario[:2]}_{uuid.uuid4().hex[:8]}"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def run_scenario(scenario: str) -> tuple[subprocess.CompletedProcess[str], Path, dict]:
    tag = new_tag(scenario)
    result = run_runner("-MockScenario", scenario, "-Tag", tag)
    out_dir = OUT_ROOT / tag
    summary_path = out_dir / "summary.json"
    assert summary_path.is_file(), f"summary missing for {scenario}: {result.stdout}\n{result.stderr}"
    return result, out_dir, load_json(summary_path)


def assert_no_mock_process() -> None:
    probe = subprocess.run(
        [
            str(POWERSHELL),
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | "
            "Where-Object {$_.Name -like 'python*' -and "
            "$_.CommandLine -like '*g73_live_html_b_mock_server.py*'}).Count",
        ],
        text=True,
        capture_output=True,
        timeout=15,
        check=False,
    )
    if probe.returncode == 0 and probe.stdout.strip():
        assert probe.stdout.strip().splitlines()[-1] == "0", probe.stdout


def test_static_contract() -> None:
    text = RUNNER.read_text(encoding="ascii")
    for token in (
        "[switch]$MockIntegration",
        "exit-before-readiness",
        "malformed-turn1",
        "tensor-reload-abort",
        "unsafe-tier-abort",
        "Get-MockCaptureValidation",
        "mock_validation_receipt.json",
        "Mock mode must not access the DS4 model or executable",
    ):
        assert token in text
    assert MOCK.is_file()
    assert PROTOCOL.is_file()


def test_runner_static_and_whatif() -> None:
    static = run_runner("-StaticCheckOnly")
    assert static.returncode == 0, static.stdout + static.stderr
    lifecycle = run_runner("-LifecycleSelfTest")
    assert lifecycle.returncode == 0, lifecycle.stdout + lifecycle.stderr
    parser = run_runner("-ParserSelfTest")
    assert parser.returncode == 0, parser.stdout + parser.stderr
    tag = new_tag("whatif")
    whatif = run_runner("-MockScenario", "success", "-Tag", tag, "-WhatIf")
    assert whatif.returncode == 0, whatif.stdout + whatif.stderr
    assert not (OUT_ROOT / tag).exists()


def test_success_two_turn_byte_exact() -> None:
    result, out_dir, summary = run_scenario("success")
    assert result.returncode == 0, result.stdout + result.stderr
    assert summary["status"] == "pass"
    assert summary["mock"]["validation"]["pass"] is True
    assert summary["mock"]["synthetic_quality_claim"] == "L2-contract-only"
    assert len(summary["requests"]) == 2
    turn2_quality = next(q for q in summary["quality_gates"] if q["turn"] == "turn2")
    assert turn2_quality["pass"] is True
    assert "dark_almost_black" in turn2_quality["advisory_only"]
    assert turn2_quality["dark_almost_black"] is True
    assert turn2_quality["contrast_heuristic"] is True
    assert turn2_quality["wcag_contrast_ratio"] >= 4.5
    assert turn2_quality["has_popup"] is True
    quality_gate_names = {gate["name"] for gate in summary["gates"]}
    assert "mock_turn2_html_document_contract" in quality_gate_names
    assert "mock_turn2_dark_structural_contract" not in quality_gate_names

    metrics = summary["log_summary"]["server_request_metrics"]
    assert len(metrics) == 2
    assert metrics[0]["prefill_chunks"][0]["avg_tps"] == 120.0
    assert metrics[0]["last_decode_tokens"] == 16
    assert metrics[0]["last_decode_avg_tps"] == 40.0
    assert metrics[0]["finish_tokens"] == 32

    capture = out_dir / "c"
    request1_raw = (capture / "request1.raw.json").read_bytes()
    request2_raw = (capture / "request2.raw.json").read_bytes()
    request1 = json.loads(request1_raw.decode("utf-8"))
    request2 = json.loads(request2_raw.decode("utf-8"))
    assistant1 = (out_dir / "request1.raw_assistant.txt").read_bytes()

    assert [message["role"] for message in request1["messages"]] == ["system", "user"]
    assert [message["role"] for message in request2["messages"]] == [
        "system",
        "user",
        "assistant",
        "user",
    ]
    assert request2["messages"][0]["content"] == SYSTEM_PROMPT
    assert request2["messages"][1]["content"] == PROMPT1
    assert request2["messages"][2]["content"].encode("utf-8") == assistant1
    assert request2["messages"][3]["content"] == PROMPT2
    assert request1["stop"] == "</html>" and request2["stop"] == "</html>"
    assert request1["temperature"] == 0 and request2["temperature"] == 0
    assert request1["think"] is False and request2["think"] is False

    validation = summary["mock"]["validation"]
    assert validation["assistant1_byte_exact_in_request2"] is True
    assert validation["request2_roles_exact"] is True
    assert validation["request2_assistant_sha256"] == sha256(assistant1)
    receipt = load_json(out_dir / "mock_validation_receipt.json")
    assert receipt["pass"] is True
    assert receipt["capture"]["request1"]["raw_sha256"] == sha256(request1_raw)
    assert receipt["capture"]["request2"]["raw_sha256"] == sha256(request2_raw)
    assert not (out_dir / "failure_receipt.json").exists()
    assert_no_mock_process()


def test_exit_before_readiness_fails_closed() -> None:
    result, out_dir, summary = run_scenario("exit-before-readiness")
    assert result.returncode != 0
    assert summary["status"] == "failed"
    assert summary["failure_stage"] == "server-readiness"
    assert summary["lifecycle"]["vanished_pid_detected"] is True
    assert summary["server_exit"]["exit_code"] == 23
    assert len(summary["requests"]) == 0
    assert (out_dir / "failure_receipt.json").is_file()
    assert (out_dir / "mock_validation_receipt.json").is_file()
    assert_no_mock_process()


def test_malformed_turn1_blocks_turn2() -> None:
    result, out_dir, summary = run_scenario("malformed-turn1")
    assert result.returncode != 0
    assert summary["status"] == "failed"
    assert len(summary["requests"]) == 1
    assert summary["turn1_readiness_for_turn2"]["pass"] is False
    capture = out_dir / "c"
    assert (capture / "request1.raw.json").is_file()
    assert not (capture / "request2.raw.json").exists()
    assert (out_dir / "failure_receipt.json").is_file()
    validation = summary["mock"]["validation"]
    assert validation["request_count"] == 1
    assert validation["request2_present"] is False
    assert_no_mock_process()


def test_tensor_reload_abort_parser_path() -> None:
    result, out_dir, summary = run_scenario("tensor-reload-abort")
    assert result.returncode != 0
    assert summary["status"] == "aborted"
    assert summary["failure_stage"] == "request1"
    assert "Model tensor cache reload" in summary["failure"]
    assert len(summary["requests"]) == 0
    assert summary["mock"]["validation"]["pass"] is True
    assert summary["mock"]["validation"]["request_count"] == 1
    reloads = summary["log_summary"]["runtime_model_tensor_progress"]
    assert len(reloads) == 1
    assert reloads[0]["request_index"] == 1
    assert reloads[0]["cached_gib"] == 1.25
    assert (out_dir / "failure_receipt.json").is_file()
    assert_no_mock_process()


def test_unsafe_tier_abort_parser_path() -> None:
    result, out_dir, summary = run_scenario("unsafe-tier-abort")
    assert result.returncode != 0
    assert summary["status"] == "aborted"
    assert summary["failure_stage"] == "request1"
    assert "Unsafe tier/backing" in summary["failure"]
    assert len(summary["requests"]) == 0
    assert summary["mock"]["validation"]["pass"] is True
    assert summary["mock"]["validation"]["request_count"] == 1
    unsafe = summary["log_summary"]["unsafe_tier"]
    assert len(unsafe) == 1
    assert unsafe[0]["snapshot_backing_misses"] == "1"
    assert unsafe[0]["ssd_bytes"] == "4096"
    assert (out_dir / "failure_receipt.json").is_file()
    assert_no_mock_process()


def main() -> int:
    tests = (
        test_static_contract,
        test_runner_static_and_whatif,
        test_success_two_turn_byte_exact,
        test_exit_before_readiness_fails_closed,
        test_malformed_turn1_blocks_turn2,
        test_tensor_reload_abort_parser_path,
        test_unsafe_tier_abort_parser_path,
    )
    for test in tests:
        started = time.monotonic()
        test()
        print(f"PASS {test.__name__} {time.monotonic() - started:.3f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
