#!/usr/bin/env python3
"""CPU/mock/static-only T0 tests for the G130 P0-U1 harness.

The suite never invokes ds4_server, nvidia-smi, either model, or a CUDA build.
All preflight and watchdog inputs are dependency-injected artifacts.
"""

from __future__ import annotations

import copy
import ctypes
import hashlib
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = ROOT / "g130_u1_q1_profile.ps1"
WATCHDOG = ROOT / "g130_u1_watchdog.ps1"
COMMON = ROOT / "g130_u1_common.ps1"
SERVER = ROOT / "ds4_server.c"
BASE = "63de9b23f71993a3d9965355c9e445830c12f81c"
BASE_WORKTREE = pathlib.Path(r"C:\Users\imanu\Documents\Codex\2026-07-20\g130-ds4-work")
FIXTURES = ROOT / "tests" / "fixtures" / "g130_u1"
VALID_PROFILE = FIXTURES / "profile_valid.stderr.log"
LATE_LOAD = FIXTURES / "late_port_bind.json"
RUNTIME_STDERR = FIXTURES / "synthetic_watchdog.stderr.log"
POWERSHELL = shutil.which("powershell.exe") or shutil.which("powershell")


def run_ps(path: pathlib.Path, *args: object, timeout: float = 90) -> subprocess.CompletedProcess[str]:
    assert POWERSHELL
    return subprocess.run(
        [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(path), *map(str, args)],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def run_ps_command(command: str, timeout: float = 90) -> subprocess.CompletedProcess[str]:
    assert POWERSHELL
    return subprocess.run(
        [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def output_json(proc: subprocess.CompletedProcess[str]) -> dict:
    decoder = json.JSONDecoder()
    text = proc.stdout.strip()
    for index, char in enumerate(text):
        if char == "{":
            try:
                value, _ = decoder.raw_decode(text[index:])
                return value
            except json.JSONDecodeError:
                pass
    raise AssertionError(f"JSON missing\nexit={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}")


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(json.dumps(value, separators=(",", ":")), encoding="utf-8")


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot_tree(root: pathlib.Path) -> dict[str, tuple[int, int, str]]:
    result: dict[str, tuple[int, int, str]] = {}
    for path in root.rglob("*"):
        if ".git" in path.parts or not path.is_file():
            continue
        stat = path.stat()
        result[path.relative_to(root).as_posix()] = (stat.st_size, stat.st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())
    return result


def valid_request() -> dict:
    return {
        "model": "ds4",
        "messages": [{"role": "user", "content": "Explain in one concise paragraph why profiling must precede optimization."}],
        "max_tokens": 64,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
        "think": False,
    }


def valid_preflight() -> dict:
    head = "1" * 40
    executable_sha = "2" * 64
    file_identity = {
        "path": r"C:\synthetic\model.gguf",
        "bytes": 86720111488,
        "receipt_path": r"C:\synthetic\model.gguf.receipt.json",
        "receipt_file_sha256": "5" * 64,
        "receipt_sha256": "efc7ed607ff27076e3e501fc3fefefa33c0ed8cf1eff483a2b7fdc0c2e616668",
        "receipt_verified_at": "2026-07-20T00:00:00Z",
        "model_rehashed": False,
    }
    sidecar = copy.deepcopy(file_identity)
    sidecar.update(
        {
            "path": r"C:\synthetic\sidecar.gguf",
            "bytes": 39048344416,
            "receipt_path": r"C:\synthetic\sidecar.gguf.receipt.json",
            "receipt_sha256": "05040393f5e94bf054a593e4d2d021ff44a6f446f2328a75e4f833a1fbe20207",
        }
    )
    names = [
        "app_container", "processes", "system_counters", "gpu", "cpu_temperature", "identity",
        "quiet_window_1", "quiet_window_2", "quiet_window_3", "probe_completeness",
    ]
    return {
        "schema": "g130_u1_preflight_probe_v1",
        "captured_utc": "2026-07-20T00:00:00Z",
        "app_container": False,
        "conflicting_processes": [],
        "background_activity": [],
        "gpu": {"vram_used_mib": 500, "power_w": 32.5, "temperature_c": 45, "utilization_percent": 1, "compute_processes": []},
        "memory": {"available_bytes": 55 * 1024**3, "planned_bytes": 47009759232},
        "paging": {"pages_output_total": 1000000, "page_faults_total": 5000000, "pages_per_sec": 2, "page_reads_per_sec": 1},
        "disk": {"volume": "C:", "queue_length": 0.1, "read_bytes_per_sec": 0, "write_bytes_per_sec": 0, "free_bytes": 20 * 1024**3},
        "process_baseline": {"process_count": 100, "working_set_bytes": 128 * 1024**2},
        "cpu_temperature": {"temperature_c": 48, "provider": "LibreHardwareMonitor", "sensor_id": "/intelcpu/0/temperature/0", "sensor_name": "CPU Package"},
        "quiet_windows": [
            {"index": i, "captured_utc": f"2026-07-20T00:00:0{i}Z", "cpu_percent": 5, "disk_queue_length": 0.1, "gpu_percent": 1, "gpu_power_w": 32.5, "gpu_compute_process_count": 0}
            for i in range(1, 4)
        ],
        "identity": {
            "schema": "g130_u1_build_identity_v2",
            "git": {"head": head, "branch": "g130/u1-harness", "repository_root": r"C:\synthetic\g130-u1-harness-work", "expected_base": BASE, "base_ancestor": True, "dirty": False, "status": [], "status_includes_untracked": True},
            "build": {"manifest_path": r"C:\synthetic\manifest.json", "manifest_sha256": "6" * 64, "schema": "g7_native_windows_build_manifest_v1", "head": head, "configuration": "Release", "worktree_dirty_at_build_start": False, "input_fingerprint_sha256": "3" * 64, "executable_path": r"C:\synthetic\ds4_server.exe", "executable_bytes": 123456, "executable_sha256": executable_sha, "observed_executable_sha256": executable_sha},
            "model": file_identity,
            "sidecar": sidecar,
            "config_path": r"C:\synthetic\config.json",
            "config_sha256": "4" * 64,
        },
        "probe_status": [{"name": name, "status": "ok"} for name in names],
        "probe_errors": [],
    }


def set_path(value: dict, dotted: str, replacement: object) -> None:
    current: object = value
    fields = dotted.split(".")
    for field in fields[:-1]:
        current = current[int(field)] if field.isdigit() else current[field]  # type: ignore[index]
    final = fields[-1]
    if final.isdigit():
        current[int(final)] = replacement  # type: ignore[index]
    else:
        current[final] = replacement  # type: ignore[index]


def preflight_run(value: dict) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as td:
        path = pathlib.Path(td) / "preflight.json"
        write_json(path, value)
        return run_ps(RUNNER, "-PreflightFixturePath", path)


def profile_run(text: str, generated: int = 64) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as td:
        path = pathlib.Path(td) / "profile.stderr.log"
        path.write_text(text, encoding="utf-8")
        return run_ps(RUNNER, "-ParseProfilePath", path, "-GeneratedTokens", generated)


def replace_tag_field(text: str, tag: str, field: str, replacement: str) -> str:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if f"[{tag}]" in line:
            lines[index], count = re.subn(rf"(?<![A-Za-z0-9_]){re.escape(field)}=\S+", f"{field}={replacement}", line, count=1)
            if count != 1:
                raise AssertionError(f"field {field} missing in {tag}")
            break
    else:
        raise AssertionError(f"tag {tag} missing")
    return "\n".join(lines) + "\n"


def watchdog_sample(elapsed: float, **overrides: object) -> dict:
    value = {
        "elapsed_seconds": elapsed,
        "working_set_bytes": 8 * 1024**3,
        "available_ram_bytes": 50 * 1024**3,
        "pages_output_total": 1000000,
        "ready": False,
        "request_started": False,
        "request_complete": False,
        "server_alive": True,
        "stderr_delta": "",
        "stream_text": "",
        "startup_cached_gib": elapsed,
        "startup_loaded_layer": -1,
        "startup_phase": "none",
    }
    value.update(overrides)
    return value


def token_rows(first: int, last: int, seconds_per_token: float) -> str:
    return "\n".join(
        f"ds4: [q1-0-profile-token] schema=g130_u1_profile_token_v1 result=progress final=0 gen={i} decode_elapsed_seconds={i * seconds_per_token:.9f}"
        for i in range(first, last + 1)
    )


def watchdog_replay(samples: list[dict]) -> tuple[subprocess.CompletedProcess[str], dict]:
    value = {
        "schema": "g130_u1_watchdog_replay_fixture_v2",
        "baseline_page_out": 1000000,
        "thresholds": {"wall_cap_seconds": 900, "startup_stall_seconds": 180, "ttft_cap_seconds": 180, "application_data_stall_seconds": 60, "page_out_delta_abort_pages": 100000, "throughput_floor_tps": 0.1025, "throughput_warm_tokens": 16, "throughput_consecutive_tokens": 30},
        "samples": samples,
    }
    with tempfile.TemporaryDirectory() as td:
        path = pathlib.Path(td) / "replay.json"
        write_json(path, value)
        proc = run_ps(WATCHDOG, "-ReplayPath", path)
        return proc, output_json(proc)


def supervision_run(sample: dict) -> tuple[subprocess.CompletedProcess[str], dict]:
    fixture = {"schema": "g130_u1_parent_supervision_fixture_v1", "heartbeat_stall_seconds": 5, "wall_cap_seconds": 900, "samples": [sample]}
    with tempfile.TemporaryDirectory() as td:
        path = pathlib.Path(td) / "parent.json"
        write_json(path, fixture)
        proc = run_ps(RUNNER, "-SupervisionFixturePath", path)
        return proc, output_json(proc)


class OneShotHttpServer:
    def __init__(self, status: int, body: bytes, byte_delay: float = 0.0005):
        self.status = status
        self.body = body
        self.byte_delay = byte_delay
        self.request_body = b""
        self.error: BaseException | None = None
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.port = self.listener.getsockname()[1]
        self.listener.listen(1)
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self.thread.start()

    def _run(self) -> None:
        try:
            conn, _ = self.listener.accept()
            with conn:
                raw = b""
                while b"\r\n\r\n" not in raw:
                    raw += conn.recv(4096)
                header, remainder = raw.split(b"\r\n\r\n", 1)
                match = re.search(br"(?im)^Content-Length:\s*(\d+)\s*$", header)
                expected = int(match.group(1)) if match else 0
                while len(remainder) < expected:
                    remainder += conn.recv(4096)
                self.request_body = remainder[:expected]
                reason = b"OK" if 200 <= self.status < 300 else b"Service Unavailable"
                response = b"HTTP/1.1 " + str(self.status).encode() + b" " + reason + b"\r\nContent-Type: text/event-stream; charset=utf-8\r\nContent-Length: " + str(len(self.body)).encode() + b"\r\nConnection: close\r\n\r\n"
                conn.sendall(response)
                for byte in self.body:
                    conn.sendall(bytes([byte]))
                    if self.byte_delay:
                        time.sleep(self.byte_delay)
        except BaseException as exc:  # pragma: no cover - diagnostic propagation
            self.error = exc
        finally:
            self.listener.close()

    def join(self) -> None:
        self.thread.join(5)
        if self.error:
            raise self.error


def sse_body(done: bool = True, finish: str = "length", tokens: int = 64) -> bytes:
    chunks = [
        {"choices": [{"delta": {"content": "caffè ☕"}, "finish_reason": None}]},
        {"thinking": False, "choices": [{"delta": {}, "finish_reason": None}]},
        {"choices": [{"delta": {}, "finish_reason": finish}]},
        {"choices": [], "usage": {"prompt_tokens": 12, "completion_tokens": tokens, "total_tokens": 12 + tokens}},
    ]
    text = "".join("data: " + json.dumps(chunk, ensure_ascii=False, separators=(",", ":")) + "\r\n\r\n" for chunk in chunks)
    if done:
        text += "data: [DONE]\r\n\r\n"
    return text.encode("utf-8")


def encode_sse_events(events: list[dict | str]) -> bytes:
    return "".join(
        "data: " + (event if isinstance(event, str) else json.dumps(event, ensure_ascii=False, separators=(",", ":"))) + "\r\n\r\n"
        for event in events
    ).encode("utf-8")


def run_http_worker(status: int = 200, body: bytes | None = None) -> tuple[subprocess.CompletedProcess[str], dict, pathlib.Path, OneShotHttpServer, tempfile.TemporaryDirectory[str]]:
    holder: tempfile.TemporaryDirectory[str] = tempfile.TemporaryDirectory()
    root = pathlib.Path(holder.name)
    request_path = root / "request.json"
    request_path.write_text(json.dumps(valid_request(), separators=(",", ":")), encoding="utf-8")
    server = OneShotHttpServer(status, sse_body() if body is None else body)
    manifest = {
        "schema": "g130_u1_http_worker_manifest_v1",
        "uri": f"http://127.0.0.1:{server.port}/v1/chat/completions",
        "request_path": str(request_path),
        "raw_response_path": str(root / "raw.sse"),
        "timing_path": str(root / "timing.jsonl"),
        "result_path": str(root / "result.json"),
        "assistant_path": str(root / "assistant.txt"),
        "expected_request_sha256": sha256(request_path),
        "http_timeout_seconds": 10,
    }
    manifest_path = root / "manifest.json"
    write_json(manifest_path, manifest)
    server.start()
    proc = run_ps(RUNNER, "-HttpWorker", "-WorkerManifestPath", manifest_path, timeout=30)
    server.join()
    result = json.loads((root / "result.json").read_text(encoding="utf-8"))
    return proc, result, root, server, holder


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class SyntaxStaticAndRuntimePatchTests(unittest.TestCase):
    def test_powershell_51_parsefile_zero_errors(self) -> None:
        paths = ",".join("'" + str(path).replace("'", "''") + "'" for path in (COMMON, RUNNER, WATCHDOG))
        command = f"$r=@();foreach($p in @({paths})){{$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)|Out-Null;$r+=@{{path=$p;errors=@($e).Count}}}};[pscustomobject]@{{major=$PSVersionTable.PSVersion.Major;files=$r}}|ConvertTo-Json -Depth 5 -Compress"
        proc = run_ps_command(command)
        self.assertEqual(proc.returncode, 0, (proc.stdout, proc.stderr))
        value = json.loads(proc.stdout)
        self.assertEqual(value["major"], 5)
        self.assertTrue(all(item["errors"] == 0 for item in value["files"]), value)

    def test_exact_forwarding_and_server_switch_mapping(self) -> None:
        plan = output_json(run_ps(RUNNER, "-WhatIf"))
        self.assertEqual(
            plan["server_arguments"],
            ["-m", r"C:\ds4-models\ds4-2bit.gguf", "--cuda", "-c", "256", "-n", "64", "--mtp-draft", "1", "--host", "127.0.0.1", "--port", "<dynamic-loopback-port>"],
        )
        runner = RUNNER.read_text(encoding="utf-8")
        watchdog_params = WATCHDOG.read_text(encoding="utf-8").split("$ErrorActionPreference", 1)[0]
        self.assertIn("[string]$ManifestPath", watchdog_params)
        self.assertRegex(runner, r"Start-G130U1PowerShellChild \$watchdogPath @\('-ManifestPath',\$paths\['watchdog_manifest\.json'\]\)")
        self.assertRegex(runner, r"@\('-HttpWorker','-WorkerManifestPath',\$paths\['http_worker_manifest\.json'\]\)")
        self.assertIn("-EncodedCommand", runner)
        runner_path = str(RUNNER).replace("'", "''"); watchdog_path = str(WATCHDOG).replace("'", "''")
        command = f"$t=$null;$e=$null;$ra=[System.Management.Automation.Language.Parser]::ParseFile('{runner_path}',[ref]$t,[ref]$e);$t=$null;$e=$null;$wa=[System.Management.Automation.Language.Parser]::ParseFile('{watchdog_path}',[ref]$t,[ref]$e);$rp=@($ra.ParamBlock.Parameters|%{{$_.Name.VariablePath.UserPath}});$wp=@($wa.ParamBlock.Parameters|%{{$_.Name.VariablePath.UserPath}});$calls=@($ra.FindAll({{param($n)$n-is[System.Management.Automation.Language.CommandAst]-and$n.GetCommandName()-eq'Start-G130U1PowerShellChild'}},$true)|%{{$_.Extent.Text}});[pscustomobject]@{{runner_params=$rp;watchdog_params=$wp;calls=$calls}}|ConvertTo-Json -Depth 8 -Compress"
        ast = json.loads(run_ps_command(command).stdout)
        self.assertEqual(len(ast["calls"]), 2)
        for extent in ast["calls"]:
            forwarded = set(re.findall(r"'-(\w+)'", extent))
            declared = set(ast["watchdog_params"] if "$watchdogPath" in extent else ast["runner_params"])
            self.assertEqual(forwarded - declared, set())
        self.assertIn("--untracked-files=all", runner)

    def test_decision_only_watchdog_and_worker_parent_only_kill(self) -> None:
        watchdog = WATCHDOG.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        worker = runner.split("function Invoke-G130U1HttpWorker", 1)[1].split("function Start-G130U1PowerShellChild", 1)[0]
        self.assertNotRegex(watchdog, r"(?i)Stop-Process|\.Kill\(")
        self.assertNotRegex(worker, r"(?i)Stop-Process|\.Kill\(")
        self.assertNotIn("Stop-Process", runner)
        self.assertIn("$Process.Kill()", COMMON.read_text(encoding="utf-8"))
        self.assertIn("$worker.Kill()", runner)
        self.assertIn("$watchdog.Kill()", runner)
        source_sample = runner.split("function Get-G130U1ParentSourceSample", 1)[1].split("function Add-G130U1JsonLine", 1)[0]
        self.assertIn("Read-G130U1FileBytes", source_sample)
        self.assertNotIn("Get-Content", source_sample)
        self.assertIn("_offset", source_sample)

    def test_runtime_patch_authenticated_atomic_profile_local_and_no_cuda_api(self) -> None:
        server = SERVER.read_text(encoding="utf-8")
        self.assertIn("getpeername(fd", server)
        self.assertIn("peer.ss_family != AF_INET", server)
        self.assertIn("0x7f000000u", server)
        self.assertIn('getenv("DS4_G130_U1_SHUTDOWN_TOKEN")', server)
        self.assertIn("diff |=", server)
        self.assertIn("server_exchange_listener", server)
        self.assertIn("InterlockedExchangePointer", server)
        self.assertIn("__atomic_exchange_n", server)
        self.assertIn('server_log(DS4_LOG_GENERATION,\n                           "ds4-server: [q1-0-profile-token]', server)
        self.assertIn("static bool server_stop_requested(void)", server)
        self.assertNotRegex(server, r"(?<![A-Za-z_])g_stop_requested(?![A-Za-z_])\s*(?:\)|&&|\|\|)")
        generate = server[server.index("static void generate_job"):server.index("static void append_model_json_values")]
        summary_at = generate.index("result=summary final=1")
        self.assertGreater(summary_at, generate.index("sse_done(j->fd"))
        self.assertIn("j->req.stream && response_ok", generate)
        self.assertEqual(generate.count("result=summary final=1"), 1)
        endpoint = server[server.index('if (!strcmp(hr.method, "POST") && !strcmp(hr.path, "/__g130_u1_shutdown"))'):server.index("request req;", server.index('/__g130_u1_shutdown'))]
        self.assertIn("g130_u1_profile_token_enabled()", endpoint)
        self.assertIn('http_error(fd, 404, "unknown endpoint")', endpoint)
        diff = subprocess.run(["git", "diff", "--unified=0", BASE, "--", "ds4_server.c"], cwd=ROOT, text=True, capture_output=True, check=True).stdout
        added = "\n".join(line[1:] for line in diff.splitlines() if line.startswith("+") and not line.startswith("+++"))
        self.assertIsNone(re.search(r"\b(?:cuda|cu|cublas|cudnn)[A-Z][A-Za-z0-9_]*\s*\(", added))
        cuda_diff = subprocess.run(["git", "diff", BASE, "--", "ds4_cuda.cu"], cwd=ROOT, text=True, capture_output=True, check=True).stdout
        self.assertEqual(cuda_diff, "")

    def test_forbidden_files_and_base_worktree_invariant(self) -> None:
        changed = set(subprocess.run(["git", "diff", "--name-only", BASE], cwd=ROOT, text=True, capture_output=True, check=True).stdout.splitlines())
        self.assertFalse({"ds4.c", "ds4_cuda.cu", "g7_measure.ps1"} & changed)
        self.assertEqual(subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip(), BASE)
        self.assertEqual(subprocess.run(["git", "branch", "--show-current"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip(), "g130/u1-harness")
        self.assertEqual(subprocess.run(["git", "rev-parse", "HEAD"], cwd=BASE_WORKTREE, text=True, capture_output=True, check=True).stdout.strip(), BASE)
        self.assertEqual(subprocess.run(["git", "status", "--porcelain=v1", "--untracked-files=all"], cwd=BASE_WORKTREE, text=True, capture_output=True, check=True).stdout, "")


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class WhatIfConfigurationAndQuotingTests(unittest.TestCase):
    def test_whatif_deterministic_recursive_snapshot_and_exact_contract(self) -> None:
        before = snapshot_tree(ROOT)
        one = run_ps(RUNNER, "-WhatIf")
        middle = snapshot_tree(ROOT)
        two = run_ps(RUNNER, "-WhatIf")
        after = snapshot_tree(ROOT)
        self.assertEqual(one.returncode, 0, one.stderr)
        self.assertEqual(one.stdout, two.stdout)
        self.assertEqual(before, middle)
        self.assertEqual(before, after)
        plan = output_json(one)
        self.assertEqual(plan["schema"], "g130_u1_q1_profile_whatif_v3")
        self.assertEqual(plan["powershell_role_mapping"]["role_count"], 4)
        self.assertEqual(plan["powershell_role_mapping"]["file_count"], 3)
        self.assertEqual(plan["request"], valid_request())
        self.assertEqual(plan["request_contract"]["count"], 1)
        self.assertEqual(plan["request_contract"]["finish_reason"], "length")
        self.assertEqual((plan["request_contract"]["finish_count"], plan["request_contract"]["usage_count"], plan["request_contract"]["done_count"]), (1, 1, 1))
        self.assertEqual(plan["request_contract"]["terminal_order"], ["finish", "usage", "done"])
        self.assertEqual(plan["routing"]["mtp_draft_tokens"], 1)
        self.assertFalse(plan["routing"]["dynamic_promotion"])
        self.assertFalse(plan["routing"]["mixed_trace"])
        self.assertEqual(plan["environment_policy"]["profile_variables_enabled"], ["DS4_Q1_0_PROFILE"])
        self.assertNotIn("DS4_G130_U1_SHUTDOWN_TOKEN", plan["environment_policy"]["enabled"])
        self.assertEqual(plan["lifecycle_thresholds"]["normal_exit"], "DS4_BENCH_EXIT_AFTER_REQUESTS=1")
        self.assertEqual(plan["lifecycle_thresholds"]["authenticated_shutdown_endpoint_use"], "abort-only")

    def test_ram_prereg_profile_basis_and_no_unregistered_threshold(self) -> None:
        plan = output_json(run_ps(RUNNER, "-WhatIf"))
        expected = 11008 * 3538944 + int(5.5 * 1024**3) + 2 * 1024**3
        self.assertEqual(expected, 47009759232)
        self.assertEqual(plan["planned_ram"]["required_available_bytes"], expected)
        prereg = plan["preregistration"]
        self.assertEqual(prereg["predicted_profile_component_seconds_per_token"], {"minimum": 0.2, "maximum": 0.5, "basis": "observed prior full/open diagnostic range"})
        self.assertEqual(prereg["abort_floor_derivation"], "predicted_decode_tps * 0.50")
        self.assertEqual(prereg["abort_floor_tps"], 0.1025)
        self.assertEqual(prereg["page_out_delta_abort_pages"], 100000)
        self.assertEqual((prereg["warm_tokens"], prereg["consecutive_tokens"]), (16, 30))
        self.assertFalse(prereg["p2_authorization"]["device_timers_included"])
        self.assertEqual(prereg["normative_telemetry_substitution"]["replaced"], ["routeprof", "selprof"])
        self.assertEqual(plan["parser_contract"]["measurement_basis"], "profile-on, existing-fence")
        self.assertFalse(plan["parser_contract"]["claim_of_zero_synchronization"])

    def test_default_refuses_live_without_side_effects(self) -> None:
        before = snapshot_tree(ROOT)
        proc = run_ps(RUNNER)
        self.assertEqual(proc.returncode, 19)
        self.assertEqual(output_json(proc)["schema"], "g130_u1_live_refusal_v1")
        self.assertEqual(before, snapshot_tree(ROOT))

    def test_win32_quoting_roundtrip_spaces_quotes_and_metacharacters(self) -> None:
        values = ["", "plain", r"C:\path with spaces\file.json", 'quote"inside', r"trail\\", "&|<>^%!$()`n"]
        with tempfile.TemporaryDirectory() as td:
            fixture = pathlib.Path(td) / "quote.json"
            write_json(fixture, {"values": values})
            proc = run_ps(RUNNER, "-QuoteFixturePath", fixture)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            joined = output_json(proc)["joined"]
        argc = ctypes.c_int()
        ctypes.windll.shell32.CommandLineToArgvW.restype = ctypes.POINTER(ctypes.c_wchar_p)
        argv = ctypes.windll.shell32.CommandLineToArgvW(joined, ctypes.byref(argc))
        try:
            parsed = [argv[i] for i in range(argc.value)]
        finally:
            ctypes.windll.kernel32.LocalFree(argv)
        self.assertEqual(parsed, values)

    def test_approval_binds_future_head_all_hashes_and_worker_mode(self) -> None:
        binding = {
            "schema": "g130_u1_approval_binding_v1", "git_head": "1" * 40,
            "runner_sha256": "2" * 64, "common_sha256": "3" * 64,
            "watchdog_sha256": "4" * 64, "executable_sha256": "5" * 64,
            "build_manifest_sha256": "6" * 64,
            "worker_mode": "parameter_set:HttpWorker@g130_u1_q1_profile.ps1",
        }
        plan_sha = "7" * 64
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td); approval_path = root / "approval.json"; fixture_path = root / "fixture.json"
            def classify(actual: dict) -> subprocess.CompletedProcess[str]:
                write_json(approval_path, {"schema": "g130_u1_live_approval_v2", "approved": True, "scope": "P0-U1-T1-diagnostic", "plan_sha256": plan_sha, "binding": actual, "expires_utc": "2099-01-01T00:00:00Z"})
                write_json(fixture_path, {"schema": "g130_u1_approval_fixture_v1", "approval_path": str(approval_path), "plan_sha256": plan_sha, "binding": binding})
                return run_ps(RUNNER, "-ApprovalFixturePath", fixture_path)
            self.assertEqual(classify(copy.deepcopy(binding)).returncode, 0)
            for field in ("git_head", "runner_sha256", "common_sha256", "watchdog_sha256", "executable_sha256", "build_manifest_sha256", "worker_mode"):
                changed = copy.deepcopy(binding); changed[field] = "mismatch"
                with self.subTest(field=field):
                    self.assertEqual(classify(changed).returncode, 19)


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class PreflightTests(unittest.TestCase):
    def test_valid_schema_and_all_p_gates(self) -> None:
        proc = preflight_run(valid_preflight())
        self.assertEqual(proc.returncode, 0, proc.stderr)
        value = output_json(proc)
        self.assertTrue(value["pass"])
        self.assertEqual([gate["id"] for gate in value["gates"]], [f"P-{i}" for i in range(1, 9)])

    def test_null_denied_zero_fail_closed_for_each_p_gate(self) -> None:
        paths = {
            "P-1": "disk.queue_length",
            "P-2": "gpu.power_w",
            "P-3": "memory.available_bytes",
            "P-4": "process_baseline.working_set_bytes",
            "P-5": "quiet_windows.0.cpu_percent",
            "P-6": "identity.config_sha256",
            "P-7": "cpu_temperature.temperature_c",
            "P-8": "disk.free_bytes",
        }
        for gate, path in paths.items():
            injected_values = (None, "denied", 1.0) if gate == "P-1" else (None, "denied", 0)
            for injected in injected_values:
                with self.subTest(gate=gate, injected=injected):
                    value = valid_preflight()
                    set_path(value, path, injected)
                    proc = preflight_run(value)
                    self.assertEqual(proc.returncode, 20, (gate, injected, proc.stdout, proc.stderr))

    def test_exact_probe_schema_rejects_wrong_missing_duplicate_unknown(self) -> None:
        variants: list[dict] = []
        wrong = valid_preflight(); wrong["schema"] = "g130_u1_preflight_probe_v0"; variants.append(wrong)
        nested = valid_preflight(); nested["identity"]["schema"] = "wrong"; variants.append(nested)
        unknown = valid_preflight(); unknown["unknown"] = 1; variants.append(unknown)
        missing = valid_preflight(); del missing["captured_utc"]; variants.append(missing)
        duplicate = valid_preflight(); duplicate["probe_status"].append(copy.deepcopy(duplicate["probe_status"][0])); variants.append(duplicate)
        unknown_status = valid_preflight(); unknown_status["probe_status"][-1]["name"] = "unexpected"; variants.append(unknown_status)
        missing_status = valid_preflight(); missing_status["probe_status"].pop(); variants.append(missing_status)
        for index, value in enumerate(variants):
            with self.subTest(index=index):
                self.assertEqual(preflight_run(value).returncode, 20)

    def test_appcontainer_disk_free_git_untracked_and_cpu_provider_no_go(self) -> None:
        mutations = [
            ("app_container", True),
            ("disk.free_bytes", 5 * 1024**3 - 1),
            ("identity.git.status_includes_untracked", False),
            ("cpu_temperature.provider", "missing"),
        ]
        for path, replacement in mutations:
            with self.subTest(path=path):
                value = valid_preflight(); set_path(value, path, replacement)
                self.assertEqual(preflight_run(value).returncode, 20)

    def test_paging_manifest_cpu_sensor_and_nested_rows_are_closed_schema(self) -> None:
        variants: list[dict] = []
        for path, replacement in (
            ("paging.pages_per_sec", None),
            ("paging.page_reads_per_sec", "0"),
            ("identity.build.schema", "g7_build_manifest_v2"),
            ("cpu_temperature.sensor_id", "/gpu-nvidia/0/temperature/0"),
        ):
            value = valid_preflight(); set_path(value, path, replacement); variants.append(value)
        conflict = valid_preflight(); conflict["conflicting_processes"] = [{"process_id": 4, "parent_process_id": 0, "name": "ds4_server.exe", "command_line": "", "extra": 1}]; variants.append(conflict)
        gpu = valid_preflight(); gpu["gpu"]["compute_processes"] = [{"pid": "42", "process_name": "mock.exe"}]; variants.append(gpu)
        errors = valid_preflight(); errors["probe_errors"] = [{"name": "gpu", "error": "denied", "extra": 1}]; variants.append(errors)
        status = valid_preflight(); status["identity"]["git"]["status"] = [{"porcelain": "?? new.ps1", "extra": 1}]; variants.append(status)
        wrong_git_bool = valid_preflight(); wrong_git_bool["identity"]["git"]["dirty"] = "false"; variants.append(wrong_git_bool)
        wrong_build_bytes = valid_preflight(); wrong_build_bytes["identity"]["build"]["executable_bytes"] = "123456"; variants.append(wrong_build_bytes)
        wrong_receipt_bool = valid_preflight(); wrong_receipt_bool["identity"]["model"]["model_rehashed"] = "false"; variants.append(wrong_receipt_bool)
        for index, value in enumerate(variants):
            with self.subTest(index=index):
                self.assertEqual(preflight_run(value).returncode, 20)


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class ClosedProfileParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.valid = VALID_PROFILE.read_text(encoding="utf-8")

    def test_valid_runtime_fixture_absolute_cardinality_u3_and_host_only_p2(self) -> None:
        proc = profile_run(self.valid)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        value = output_json(proc)
        self.assertEqual(value["route"]["calls"], "2752")
        self.assertEqual(value["selection"]["requested_routes"], "16512")
        self.assertEqual(value["route_count_expected"], 16512)
        self.assertEqual(value["host_bucket_seconds_per_token"], 230 / 64)
        self.assertEqual(value["device_kernel_seconds_diagnostic"], 9999)
        self.assertFalse(value["host_device_times_summed"])
        self.assertTrue(value["p2_authorized"])
        self.assertGreater(value["u3"]["effective_pageable_h2d_bytes_per_second"], 0)

    def test_device_timer_is_diagnostic_and_never_changes_p2(self) -> None:
        low = output_json(profile_run(replace_tag_field(self.valid, "q1-0-profile-route", "q1_kernel_device_seconds", "0.000000000")))
        high = output_json(profile_run(replace_tag_field(self.valid, "q1-0-profile-route", "q1_kernel_device_seconds", "999999.000000000")))
        self.assertEqual(low["host_bucket_seconds_per_token"], high["host_bucket_seconds_per_token"])
        self.assertEqual(low["p2_authorized"], high["p2_authorized"])

    def test_63_token_profile_is_rejected_before_p2(self) -> None:
        lines = [line for line in self.valid.splitlines() if "result=progress" not in line or " gen=64 " not in line]
        text = "\n".join(lines).replace("generated_tokens=64", "generated_tokens=63").replace("gen=64 decoding", "gen=63 decoding").replace("gen=64 finish", "gen=63 finish") + "\n"
        proc = profile_run(text)
        self.assertEqual(proc.returncode, 23)
        self.assertNotIn("P2_AUTHORIZED", proc.stdout)

    def test_missing_duplicate_malformed_nan_timer_device_gap_and_cardinality_fail(self) -> None:
        variants = []
        variants.append(self.valid.replace(next(line for line in self.valid.splitlines() if "result=progress" in line and " gen=32 " in line) + "\n", ""))
        route = next(line for line in self.valid.splitlines() if "[q1-0-profile-route]" in line)
        variants.append(self.valid.replace(route, route + "\n" + route))
        variants.append(self.valid.replace("calls=2752 completed_calls=2752", "calls=2752 calls=2752 completed_calls=2752", 1))
        variants.append(replace_tag_field(self.valid, "q1-0-profile-route", "call_seconds", "NaN"))
        variants.append(replace_tag_field(self.valid, "q1-0-profile-route", "timer_failures", "1"))
        variants.append(replace_tag_field(self.valid, "q1-0-profile-route", "q1_kernel_device_missing_calls", "1"))
        variants.append(replace_tag_field(self.valid, "q1-0-profile-route", "bucket_gap_seconds", "-0.000002"))
        variants.append(replace_tag_field(self.valid, "q1-0-profile-route", "calls", "2751"))
        variants.append(replace_tag_field(self.valid, "q1-0-profile-selection", "requested_routes", "16511"))
        variants.append(replace_tag_field(self.valid, "q1-0-profile", "pageable_h2d_enqueue_seconds", "0"))
        variants.append(replace_tag_field(self.valid, "q1-0-source-working-set", "resident_bytes", "39048347647"))
        for index, text in enumerate(variants):
            with self.subTest(index=index):
                self.assertEqual(profile_run(text).returncode, 23)

    def test_closed_schema_forbidden_trace_and_promotion_markers(self) -> None:
        variants = [
            self.valid.replace("result=summary final=1 path=mixed_q1 enabled=1 unit=seconds", "result=summary final=1 path=mixed_q1 enabled=1 unit=seconds extra=1", 1),
            self.valid + "ds4: [q1-0-mixed-route] result=trace\n",
            self.valid + "ds4: [routeprof] enabled=1\n",
            self.valid + "ds4: [selprof] enabled=1\n",
            self.valid + "ds4: [request-phase] trace=1\n",
            self.valid + "state.failed=1\n",
            self.valid + "direct dynamic_promotion marker\n",
        ]
        for text in variants:
            self.assertEqual(profile_run(text).returncode, 23)

    def test_intermediate_thinking_flag_and_reasonable_final_monotonic_bound(self) -> None:
        thinking = self.valid.replace("gen=50 decoding", "gen=50 THINKING decoding")
        self.assertEqual(profile_run(thinking).returncode, 0)
        too_late = replace_tag_field(self.valid, "q1-0-profile-token", "decode_elapsed_seconds", "351.000000000")
        # replace_tag_field changes the first progress row; target final explicitly instead.
        too_late = self.valid.replace("generated_tokens=64 decode_elapsed_seconds=321.000000000", "generated_tokens=64 decode_elapsed_seconds=351.000000000")
        self.assertEqual(profile_run(too_late).returncode, 23)

    def test_runtime_timestamp_direct_forms_malformed_prefix_and_unknown_tag(self) -> None:
        self.assertIn("0720 12:34:56 ds4-server: [q1-0-profile-token]", self.valid)
        direct = re.sub(r"^0720 12:34:56 ds4-server: \[q1-0-profile-token\] ", "ds4: [q1-0-profile-token] ", self.valid, flags=re.MULTILINE)
        self.assertEqual(profile_run(direct).returncode, 0)
        malformed = self.valid.replace("0720 12:34:56 ds4-server: [q1-0-profile-token]", "1320 25:99:99 ds4-server: [q1-0-profile-token]", 1)
        bad_prefix = self.valid.replace("0720 12:34:56 ds4-server: [q1-0-profile-token]", "prefix ds4-server: [q1-0-profile-token]", 1)
        unknown = self.valid + "ds4: [q1-0-profile-unknown] result=summary\n"
        for value in (malformed, bad_prefix, unknown):
            self.assertEqual(profile_run(value).returncode, 23)

    def test_resident_raw_cardinality_and_cross_balances_are_enforced(self) -> None:
        resident = next(line for line in self.valid.splitlines() if "[q1-0-resident-arena]" in line)
        extra = self.valid.replace(resident, resident + "\n" + resident.replace("result=bootstrapped", "result=failed"))
        self.assertEqual(profile_run(extra).returncode, 23)
        pinned = 26304970752 + 3538944
        pageable = 12651724800 - 3538944
        cross = self.valid.replace("pinned=26304970752 pageable=12651724800", f"pinned={pinned} pageable={pageable}")
        self.assertEqual(profile_run(cross).returncode, 23)
        shifted = self.valid.replace(
            "pinned=26304970752 pageable=12651724800 pinned_slots=7433 pageable_slots=3575",
            f"pinned={7432 * 3538944} pageable={3576 * 3538944} pinned_slots=7432 pageable_slots=3576",
        )
        self.assertEqual(profile_run(shifted).returncode, 23)

    def test_profile_token_summary_is_strictly_terminal(self) -> None:
        lines = self.valid.splitlines()
        summary_index = next(i for i, line in enumerate(lines) if "[q1-0-profile-token]" in line and "result=summary" in line)
        progress64_index = next(i for i, line in enumerate(lines) if "[q1-0-profile-token]" in line and " gen=64 " in line)
        summary = lines.pop(summary_index)
        lines.insert(progress64_index, summary)
        self.assertEqual(profile_run("\n".join(lines) + "\n").returncode, 23)


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class WatchdogAndParentSupervisionTests(unittest.TestCase):
    def assert_abort(self, samples: list[dict], gate: str, cause: str | None = None) -> dict:
        proc, value = watchdog_replay(samples)
        self.assertEqual(proc.returncode, 21, proc.stderr)
        self.assertTrue(value["abort"])
        self.assertEqual(value["gate"], gate)
        if cause:
            self.assertEqual(value["cause"], cause)
        return value

    def test_a1_pageout_workingset_and_ram(self) -> None:
        self.assert_abort([watchdog_sample(1, pages_output_total=1100001)], "A-1", "A1_PAGE_OUT_DELTA")
        pretrim, pretrim_value = watchdog_replay([watchdog_sample(0, working_set_bytes=50 * 1024**3), watchdog_sample(1, working_set_bytes=40 * 1024**3)])
        self.assertEqual(pretrim.returncode, 0, pretrim.stderr)
        self.assertFalse(pretrim_value["abort"])
        self.assert_abort([watchdog_sample(0, working_set_bytes=50 * 1024**3), watchdog_sample(1, request_started=True, ready=True, working_set_bytes=50 * 1024**3), watchdog_sample(2, request_started=True, ready=True, working_set_bytes=40 * 1024**3)], "A-1", "A1_WORKING_SET_DROP")
        self.assert_abort([watchdog_sample(1, available_ram_bytes=2 * 1024**3 - 1)], "A-1", "A1_RAM_FLOOR")

    def test_a2_uses_exact_profile_token_rows_and_real_gen50_64_cadence(self) -> None:
        slow = watchdog_sample(500, request_started=True, ready=True, startup_cached_gib=-1, stderr_delta=token_rows(1, 50, 10.0))
        value = self.assert_abort([slow], "A-2", "A2_ROLLING_DECODE_FLOOR")
        self.assertEqual(value["tokens_observed"], 50)
        fast_proc, fast = watchdog_replay([watchdog_sample(320, request_started=True, request_complete=True, ready=True, startup_cached_gib=-1, stderr_delta=token_rows(1, 64, 5.0))])
        self.assertEqual(fast_proc.returncode, 0, fast_proc.stderr)
        self.assertEqual(fast["tokens_observed"], 64)
        timestamped = token_rows(1, 1, 5.0).replace("ds4: [q1-0-profile-token]", "0720 12:34:56 ds4-server: [q1-0-profile-token]")
        timestamp_proc, timestamp_value = watchdog_replay([watchdog_sample(5, request_started=True, ready=True, startup_cached_gib=-1, stderr_delta=timestamped)])
        self.assertEqual(timestamp_proc.returncode, 0, timestamp_proc.stderr)
        self.assertEqual(timestamp_value["tokens_observed"], 1)
        self.assert_abort([watchdog_sample(5, request_started=True, ready=True, startup_cached_gib=-1, stderr_delta=timestamped.replace("0720 12:34:56", "1320 25:99:99"))], "A-9", "A9_TOKEN_TELEMETRY_SOURCE_INVALID")
        runtime = RUNTIME_STDERR.read_text(encoding="utf-8")
        self.assertIn("gen=50", runtime)
        self.assertIn("gen=64", runtime)
        self.assertNotIn("gen=46", runtime)

    def test_a3_ttft_is_distinct_from_a9_monitor_liveness(self) -> None:
        self.assert_abort([watchdog_sample(0, request_started=True, ready=True, startup_cached_gib=-1), watchdog_sample(181, request_started=True, ready=True, startup_cached_gib=-1)], "A-3", "A3_TTFT_CAP")
        base = {"elapsed_seconds": 1, "watchdog_alive": False, "heartbeat_age_seconds": 0, "sampler_age_seconds": 0, "heartbeat_rows": 1, "sampler_rows": 1, "heartbeat_offset": 10, "sampler_offset": 10, "source_regression": False, "source_error": ""}
        proc, value = supervision_run(base)
        self.assertEqual(proc.returncode, 21)
        self.assertEqual(value["cause"], "A9_WATCHDOG_EXIT")

    def test_a4_three_100_character_blocks_and_application_stall(self) -> None:
        block = ("Sphinx_of_black_quartz_judge_my_vow_0123456789-" * 3)[:100]
        self.assertEqual(len(block), 100)
        self.assert_abort([watchdog_sample(1, request_started=True, ready=True, stream_text=block * 3)], "A-4", "A4_REPEATED_BLOCK")
        self.assert_abort([
            watchdog_sample(1, request_started=True, ready=True, startup_cached_gib=-1, stderr_delta=token_rows(1, 1, 1.0)),
            watchdog_sample(70, request_started=True, ready=True, startup_cached_gib=-1),
        ], "A-3", "A3_APPLICATION_DATA_STALL")

    def test_a5_a6_a7_real_runtime_markers_and_server_exit(self) -> None:
        for marker in ("CUDA memcpy async failed with error 700", "cudaErrorLaunchFailure", "CUBLAS_STATUS_EXECUTION_FAILED", "device reset", "NVRM: Xid 79"):
            with self.subTest(marker=marker):
                self.assert_abort([watchdog_sample(1, stderr_delta=marker)], "A-5", "A5_CUDA_OR_DEVICE_ERROR")
        self.assert_abort([watchdog_sample(1, server_alive=False)], "A-5", "A5_SERVER_EXIT")
        for marker in ("state.failed=1", "[q1-0-ssd-wrap] result=active", "dynamic_promotion enabled"):
            self.assert_abort([watchdog_sample(1, stderr_delta=marker)], "A-6", "A6_PROMOTION_OR_SSD_WRAP_MARKER")
        for marker in ("forbidden_cold_ssd_to_vram=1", "direct_ssd_to_vram_current_token=1"):
            self.assert_abort([watchdog_sample(1, stderr_delta=marker)], "A-7", "A7_SAME_TOKEN_SSD_TO_VRAM")
        for marker in ("reason=entry-contract", "reason=dynamic-promotion-contract", "reason=cold-one-contract", "reason=route-entry-contract"):
            self.assert_abort([watchdog_sample(1, stderr_delta=marker)], "A-7", "A7_RESIDENCY_CONTRACT_VIOLATION")

    def test_a8_a9_a10_and_progress_aware_late_load(self) -> None:
        self.assert_abort([watchdog_sample(900)], "A-8", "A8_WALL_CAP")
        self.assert_abort([watchdog_sample(1, pages_output_total=999999)], "A-9", "A9_PAGEOUT_COUNTER_REGRESSED")
        self.assert_abort([watchdog_sample(1, stderr_delta=token_rows(1, 1, 1.0) + "\n" + token_rows(3, 3, 1.0))], "A-9", "A9_TOKEN_TELEMETRY_SOURCE_INVALID")
        repeated = self.assert_abort([watchdog_sample(0, startup_cached_gib=10), watchdog_sample(181, startup_cached_gib=10)], "A-10", "A10_STARTUP_PROGRESS_STALL")
        self.assertEqual(repeated["startup_snapshot"]["cached_gib"], 10)
        self.assert_abort([watchdog_sample(0, startup_cached_gib=-1, startup_phase="loading_model_tensors"), watchdog_sample(181, startup_cached_gib=-1, startup_phase="loading_model_tensors")], "A-10", "A10_STARTUP_PROGRESS_STALL")
        late = run_ps(WATCHDOG, "-ReplayPath", LATE_LOAD)
        self.assertEqual(late.returncode, 0, late.stderr)
        self.assertEqual(output_json(late)["samples_consumed"], 4)
        self.assertEqual(output_json(late)["startup_snapshot"]["cached_gib"], 30)

    def test_parent_heartbeat_sampler_wall_and_counter_regression(self) -> None:
        base = {"elapsed_seconds": 1, "watchdog_alive": True, "heartbeat_age_seconds": 0, "sampler_age_seconds": 0, "heartbeat_rows": 2, "sampler_rows": 2, "heartbeat_offset": 10, "sampler_offset": 10, "source_regression": False, "source_error": ""}
        cases = [
            ({**base, "heartbeat_age_seconds": 6}, "A9_WATCHDOG_HEARTBEAT_STALL"),
            ({**base, "sampler_age_seconds": 6}, "A9_SAMPLER_PERSIST_STALL"),
            ({**base, "source_regression": True}, "A9_PARENT_SOURCE_COUNTER_REGRESSION"),
            ({**base, "elapsed_seconds": 900}, "A8_PARENT_WALL_CAP"),
        ]
        for sample, cause in cases:
            proc, value = supervision_run(sample)
            self.assertEqual(proc.returncode, 21)
            self.assertEqual(value["cause"], cause)
        bad_watchdog = watchdog_sample(1); bad_watchdog["unknown"] = 1
        proc, value = watchdog_replay([bad_watchdog])
        self.assertEqual(proc.returncode, 21)
        self.assertIn("schema mismatch", value["error"])
        bad_parent = {**base, "heartbeat_rows": "2"}
        proc, value = supervision_run(bad_parent)
        self.assertEqual(proc.returncode, 21)
        self.assertIn("JSON number", value["error"])

    def test_ownership_validation(self) -> None:
        proc = run_ps(WATCHDOG, "-OwnershipSelfTest")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        value = output_json(proc)
        self.assertTrue(value["valid_identity_accepted"])
        self.assertTrue(value["wrong_start_rejected"])
        self.assertTrue(value["wrong_path_rejected"])
        self.assertTrue(value["decision_only"])


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class Utf8SseHttpAndLateBindTests(unittest.TestCase):
    def test_utf8_incremental_framer_at_every_byte_split_and_invalid_residual(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            good = pathlib.Path(td) / "good.bin"
            good.write_bytes("data: caffè ☕\r\n\r\n".encode("utf-8"))
            common = str(COMMON).replace("'", "''"); path = str(good).replace("'", "''")
            command = f". '{common}';Initialize-G130U1Utf8FramerType;$bytes=[IO.File]::ReadAllBytes('{path}');for($split=0;$split-le$bytes.Length;$split++){{$f=[G130U1Utf8LineFramer]::new();$a=New-Object byte[] $split;[Array]::Copy($bytes,0,$a,0,$split);$b=New-Object byte[] ($bytes.Length-$split);[Array]::Copy($bytes,$split,$b,0,$b.Length);$r=@();$r+=@($f.Push($a,$a.Length));$r+=@($f.Push($b,$b.Length));$r+=@($f.Complete());if($r.Count-ne2-or$r[0]-cne'data: caffè ☕'-or$r[1]-cne''){{exit 8}}}};exit 0"
            proc = run_ps_command(command)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            bad = pathlib.Path(td) / "bad.bin"; bad.write_bytes(b"abc\xc3")
            bad_path = str(bad).replace("'", "''")
            command = f". '{common}';Initialize-G130U1Utf8FramerType;$f=[G130U1Utf8LineFramer]::new();$b=[IO.File]::ReadAllBytes('{bad_path}');try{{$null=$f.Push($b,$b.Length);$null=$f.Complete();exit 0}}catch{{exit 7}}"
            self.assertEqual(run_ps_command(command).returncode, 7)

    def test_true_tcp_worker_fragmented_sse_exact_request_done_finish_usage_and_hashes(self) -> None:
        proc, result, root, server, holder = run_http_worker()
        try:
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(json.loads(server.request_body.decode("utf-8")), valid_request())
            self.assertFalse(json.loads(server.request_body.decode("utf-8"))["think"])
            self.assertEqual(result["http_status"], 200)
            self.assertEqual(result["finish_reason"], "length")
            self.assertTrue(result["done_received"])
            self.assertEqual(result["usage_completion_tokens"], 64)
            self.assertEqual((result["finish_count"], result["usage_count"], result["done_count"], result["post_done_data_count"]), (1, 1, 1, 0))
            self.assertEqual(result["terminal_order"], "finish>usage>done")
            self.assertTrue(result["response_complete"])
            self.assertIsNotNone(result["ttft_seconds"])
            self.assertGreaterEqual(result["wall_seconds"], result["headers_elapsed_seconds"])
            self.assertEqual((root / "assistant.txt").read_text(encoding="utf-8"), "caffè ☕")
            self.assertEqual(result["assistant_text_sha256"], sha256(root / "assistant.txt"))
            self.assertEqual(result["raw_response_sha256"], sha256(root / "raw.sse"))
            self.assertEqual(result["timing_sha256"], sha256(root / "timing.jsonl"))
        finally:
            holder.cleanup()

    def test_worker_non2xx_missing_done_and_contract_failures_are_persisted(self) -> None:
        cases = [(503, sse_body(), 503), (200, sse_body(done=False), 200), (200, sse_body(finish="stop"), 200), (200, sse_body(tokens=63), 200)]
        for status, body, expected_status in cases:
            with self.subTest(status=status, body=len(body)):
                proc, result, _, _, holder = run_http_worker(status, body)
                try:
                    self.assertEqual(proc.returncode, 22)
                    self.assertEqual(result["http_status"], expected_status)
                    self.assertFalse(result["response_complete"])
                    self.assertTrue(result["error"])
                finally:
                    holder.cleanup()

    def test_sse_terminal_cardinality_order_and_post_done_are_fail_closed(self) -> None:
        content = {"choices": [{"delta": {"content": "ok"}, "finish_reason": None}]}
        finish = {"choices": [{"delta": {}, "finish_reason": "length"}]}
        usage = {"choices": [], "usage": {"prompt_tokens": 1, "completion_tokens": 64, "total_tokens": 65}}
        cases = {
            "duplicate_finish": [content, finish, finish, usage, "[DONE]"],
            "duplicate_usage": [content, finish, usage, usage, "[DONE]"],
            "duplicate_done": [content, finish, usage, "[DONE]", "[DONE]"],
            "usage_before_finish": [content, usage, finish, "[DONE]"],
            "done_before_usage": [content, finish, "[DONE]", usage],
            "data_after_done": [content, finish, usage, "[DONE]", content],
            "missing_finish": [content, usage, "[DONE]"],
            "missing_usage": [content, finish, "[DONE]"],
        }
        for name, events in cases.items():
            proc, result, _, _, holder = run_http_worker(200, encode_sse_events(events))
            try:
                with self.subTest(name=name):
                    self.assertEqual(proc.returncode, 22)
                    self.assertFalse(result["response_complete"])
                    self.assertTrue(result["error"])
                    if name == "duplicate_finish": self.assertEqual(result["finish_count"], 2)
                    if name == "duplicate_usage": self.assertEqual(result["usage_count"], 2)
                    if name == "duplicate_done": self.assertEqual((result["done_count"], result["post_done_data_count"]), (2, 1))
                    if name == "data_after_done": self.assertEqual((result["done_count"], result["post_done_data_count"]), (1, 1))
            finally:
                holder.cleanup()

    def test_worker_status_distinct_exit_without_status_partial_mismatch_non2xx_done(self) -> None:
        expected_sha = "a" * 64
        full = {"schema": "g130_u1_request_result_v3", "request_start_utc": "2026-07-20T00:00:00Z", "completed_utc": "2026-07-20T00:00:01Z", "http_status": 200, "success": False, "response_complete": False, "finish_reason": "", "finish_count": 0, "usage_completion_tokens": None, "usage_count": 0, "done_received": False, "done_count": 0, "post_done_data_count": 0, "terminal_order": "finish>usage>done", "content_events": 0, "headers_elapsed_seconds": 0.1, "ttft_seconds": None, "wall_seconds": 1, "request_sha256": expected_sha, "raw_response_sha256": None, "assistant_text_sha256": None, "timing_sha256": None, "error": "partial"}
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td); result = root / "result.json"; fixture = root / "fixture.json"
            def classify(exit_code: int, present: object | None) -> str:
                if present is None:
                    result.unlink(missing_ok=True)
                elif isinstance(present, str):
                    result.write_text(present, encoding="utf-8")
                else:
                    write_json(result, present)
                write_json(fixture, {"schema": "g130_u1_worker_status_fixture_v1", "exit_code": exit_code, "result_path": str(result), "expected_request_sha256": expected_sha})
                return output_json(run_ps(RUNNER, "-WorkerStatusFixturePath", fixture))["cause"]
            self.assertEqual(classify(0, None), "HTTP_WORKER_EXIT_WITHOUT_STATUS")
            self.assertEqual(classify(22, "{"), "HTTP_WORKER_STATUS_PARTIAL_OR_INVALID")
            self.assertEqual(classify(0, full), "HTTP_WORKER_EXIT_STATUS_MISMATCH")
            non2xx = copy.deepcopy(full); non2xx["http_status"] = 503
            self.assertEqual(classify(22, non2xx), "HTTP_NON_2XX")
            self.assertEqual(classify(22, full), "SSE_DONE_MISSING")
            wrong_type = copy.deepcopy(full); wrong_type["http_status"] = "200"
            self.assertEqual(classify(22, wrong_type), "HTTP_WORKER_STATUS_PARTIAL_OR_INVALID")

    def test_true_late_tcp_bind_no_fixed_startup_timeout(self) -> None:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM); probe.bind(("127.0.0.1", 0)); port = probe.getsockname()[1]; probe.close()
        error: list[BaseException] = []
        def late_server() -> None:
            try:
                time.sleep(1.0)
                listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM); listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); listener.bind(("127.0.0.1", port)); listener.listen(1)
                conn, _ = listener.accept(); conn.close(); listener.close()
            except BaseException as exc:
                error.append(exc)
        thread = threading.Thread(target=late_server, daemon=True); thread.start()
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td); fixture = root / "late.json"; heartbeat = root / "heartbeat.jsonl"; sampler = root / "sampler.jsonl"; heartbeat.write_text("", encoding="utf-8"); sampler.write_text("", encoding="utf-8")
            mock = subprocess.Popen([POWERSHELL, "-NoProfile", "-Command", "Start-Sleep -Seconds 10"], cwd=ROOT)
            stop = threading.Event()
            def monitor_writer() -> None:
                sequence = 0
                while not stop.wait(0.08):
                    sequence += 1; captured = "2026-07-20T00:00:00Z"; sample = watchdog_sample(sequence / 10, startup_cached_gib=sequence)
                    decision = {"abort": False, "gate": "", "cause": "", "detail": "", "rolling_decode_tps": None}
                    with heartbeat.open("a", encoding="utf-8") as stream: stream.write(json.dumps({"schema": "g130_u1_watchdog_event_v2", "event": "heartbeat", "run_id": "mock", "sequence": sequence, "captured_utc": captured, "sample": sample, "decision": decision}, separators=(",", ":")) + "\n")
                    with sampler.open("a", encoding="utf-8") as stream: stream.write(json.dumps({"schema": "g130_u1_watchdog_sampler_v2", "sequence": sequence, "captured_utc": captured, "probe_ok": True, "probe_error": "", "available_ram_bytes": 50 * 1024**3, "pages_output_total": 1000000, "working_set_bytes": 8 * 1024**3, "stderr_offset": sequence, "stream_offset": 0}, separators=(",", ":")) + "\n")
            writer = threading.Thread(target=monitor_writer, daemon=True); writer.start()
            write_json(fixture, {"schema": "g130_u1_tcp_wait_fixture_v2", "port": port, "timeout_milliseconds": 3000, "poll_milliseconds": 50, "watchdog_pid": mock.pid, "heartbeat_path": str(heartbeat), "sampler_path": str(sampler), "heartbeat_stall_seconds": 1, "wall_cap_seconds": 5})
            try:
                proc = run_ps(RUNNER, "-TcpWaitFixturePath", fixture, timeout=10)
            finally:
                stop.set(); writer.join(2); mock.terminate(); mock.wait(5)
        thread.join(5)
        if error: raise error[0]
        self.assertEqual(proc.returncode, 0, proc.stderr)
        value = output_json(proc)
        self.assertTrue(value["ready"])
        self.assertGreater(value["attempts"], 1)
        self.assertTrue(value["offset_mode"])
        self.assertGreater(value["heartbeat_rows"], 0)
        self.assertGreater(value["sampler_rows"], 0)

    def test_real_mock_watchdog_process_death_is_detected(self) -> None:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM); probe.bind(("127.0.0.1", 0)); port = probe.getsockname()[1]; probe.close()
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td); heartbeat = root / "heartbeat.jsonl"; sampler = root / "sampler.jsonl"; heartbeat.write_text("", encoding="utf-8"); sampler.write_text("", encoding="utf-8")
            mock = subprocess.Popen([POWERSHELL, "-NoProfile", "-Command", "Start-Sleep -Milliseconds 1500"], cwd=ROOT)
            fixture = root / "dead.json"; write_json(fixture, {"schema": "g130_u1_tcp_wait_fixture_v2", "port": port, "timeout_milliseconds": 3000, "poll_milliseconds": 50, "watchdog_pid": mock.pid, "heartbeat_path": str(heartbeat), "sampler_path": str(sampler), "heartbeat_stall_seconds": 5, "wall_cap_seconds": 5})
            proc = run_ps(RUNNER, "-TcpWaitFixturePath", fixture, timeout=10); mock.wait(5)
        self.assertEqual(proc.returncode, 21)
        self.assertEqual(output_json(proc)["cause"], "A9_WATCHDOG_EXIT", (proc.stdout, proc.stderr))


@unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
class ReceiptLedgerCleanupAndEnvironmentTests(unittest.TestCase):
    def test_receipt_always_hash_ledger_schema_and_cleanup_outcomes(self) -> None:
        scenarios = {"success": 0, "request-failure": 22, "parser-failure": 23, "forced-kill": 24, "cleanup-failure": 24, "pre-configuration-failure": 25}
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            for scenario, exit_code in scenarios.items():
                args: list[object] = ["-MockLifecycleScenario", scenario, "-MockOutputRoot", root]
                if scenario == "success": args += ["-MockProfilePath", VALID_PROFILE]
                proc = run_ps(RUNNER, *args)
                self.assertEqual(proc.returncode, exit_code, (scenario, proc.stdout, proc.stderr))
                run_dir = root / ("mock_" + scenario.replace("-", "_"))
                receipt_path = run_dir / "receipt.json"
                receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                self.assertEqual(receipt["schema"], "g130_u1_final_receipt_v3")
                self.assertEqual(receipt["status"], "complete")
                self.assertFalse(receipt["quotable"])
                self.assertEqual(receipt["measurement_basis"], "profile-on, existing-fence")
                self.assertEqual(receipt["exit_code"], exit_code)
                self.assertTrue((run_dir / "ledger_row.json").is_file())
                digest = (run_dir / "receipt.json.sha256").read_text(encoding="utf-8").split()[0]
                self.assertEqual(digest, sha256(receipt_path))
                row = json.loads((run_dir / "ledger_row.json").read_text(encoding="utf-8"))
                self.assertEqual(row["receipt_sha256"], digest)
                self.assertEqual(row["outcome"], receipt["outcome"])
                for artifact in receipt["artifact_hashes"]:
                    if artifact["exists"]:
                        self.assertEqual(artifact["sha256"], sha256(pathlib.Path(artifact["path"])))
            ledger_rows = [json.loads(line) for line in (root / "g130_u1_ledger.jsonl").read_text(encoding="utf-8").splitlines()]
            self.assertEqual(len(ledger_rows), len(scenarios))

    def test_ledger_failure_is_explicit_in_receipt_and_row(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            proc = run_ps(RUNNER, "-MockLifecycleScenario", "ledger-failure", "-MockOutputRoot", root, "-MockProfilePath", VALID_PROFILE)
            self.assertEqual(proc.returncode, 25, proc.stderr)
            run_dir = root / "mock_ledger_failure"
            receipt = json.loads((run_dir / "receipt.json").read_text(encoding="utf-8"))
            row = json.loads((run_dir / "ledger_row.json").read_text(encoding="utf-8"))
            self.assertTrue(receipt["ledger"]["error"])
            self.assertEqual((receipt["outcome"], receipt["cause"], receipt["exit_code"]), ("NEGATIVE", "LEDGER_APPEND_FAILED", 25))
            self.assertEqual(receipt["intended_result"]["outcome"], "DIAGNOSTIC")
            self.assertEqual(row["state"], "ledger_append_failed")
            self.assertEqual((row["outcome"], row["cause"], row["exit_code"]), ("NEGATIVE", "LEDGER_APPEND_FAILED", 25))
            self.assertNotIn("G130_U1_OUTCOME=DIAGNOSTIC", proc.stdout)

    def test_receipt_initialization_and_finalization_failures_remain_receipted(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            for scenario, cause in (("receipt-init-failure", "RECEIPT_INITIALIZATION_FAILED"), ("receipt-finalization-failure", "EVIDENCE_FINALIZATION_FAILED")):
                proc = run_ps(RUNNER, "-MockLifecycleScenario", scenario, "-MockOutputRoot", root)
                self.assertEqual(proc.returncode, 25, (scenario, proc.stdout, proc.stderr))
                receipt_path = root / ("mock_" + scenario.replace("-", "_")) / "receipt.json"
                self.assertTrue(receipt_path.is_file())
                receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
                self.assertEqual(receipt["outcome"], "NEGATIVE")
                self.assertEqual(receipt["cause"], cause)
                self.assertEqual(receipt["exit_code"], 25)
                self.assertEqual((receipt_path.parent / "receipt.json.sha256").read_text(encoding="utf-8").split()[0], sha256(receipt_path))
                row = json.loads((receipt_path.parent / "ledger_row.json").read_text(encoding="utf-8"))
                self.assertEqual(row["receipt_sha256"], sha256(receipt_path))
                self.assertIn(row["state"], {"complete", "incomplete_evidence"})

    def test_a4_partial_quality_is_unassessed_without_rendering(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            proc = run_ps(RUNNER, "-MockLifecycleScenario", "a4-abort", "-MockOutputRoot", root)
            self.assertEqual(proc.returncode, 21, proc.stderr)
            receipt = json.loads((root / "mock_a4_abort" / "receipt.json").read_text(encoding="utf-8"))
            self.assertEqual(receipt["partial_rendering"]["method"], "unrendered_partial_text_preserved")
            self.assertEqual(receipt["partial_rendering"]["l_grade"], "UNASSESSED")
            self.assertFalse(receipt["partial_rendering"]["final_grade"])

    def test_environment_clear_allowlist_restore_and_trace_absence(self) -> None:
        common = str(COMMON).replace("'", "''")
        command = f". '{common}';[Environment]::SetEnvironmentVariable('DS4_USER_SENTINEL','keep','Process');[Environment]::SetEnvironmentVariable('DS4_REQUEST_PHASE_TRACE','1','Process');$a=Get-G130U1Environment ('a'*64);$s=Enter-G130U1Environment $a;$during=[pscustomobject]@{{sentinel=$env:DS4_USER_SENTINEL;profile=$env:DS4_Q1_0_PROFILE;trace=$env:DS4_REQUEST_PHASE_TRACE;token=$env:DS4_G130_U1_SHUTDOWN_TOKEN}};Exit-G130U1Environment $s;$after=[pscustomobject]@{{sentinel=$env:DS4_USER_SENTINEL;trace=$env:DS4_REQUEST_PHASE_TRACE;token=$env:DS4_G130_U1_SHUTDOWN_TOKEN}};[pscustomobject]@{{during=$during;after=$after}}|ConvertTo-Json -Depth 5 -Compress"
        proc = run_ps_command(command)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        value = json.loads(proc.stdout)
        self.assertIsNone(value["during"]["sentinel"])
        self.assertIsNone(value["during"]["trace"])
        self.assertEqual(value["during"]["profile"], "1")
        self.assertEqual(len(value["during"]["token"]), 64)
        self.assertEqual(value["after"]["sentinel"], "keep")
        self.assertEqual(value["after"]["trace"], "1")
        self.assertIsNone(value["after"]["token"])

    def test_shutdown_403_then_autonomous_exit_is_not_graceful(self) -> None:
        server = OneShotHttpServer(403, b"{}", byte_delay=0)
        server.start()
        common = str(COMMON).replace("'", "''")
        command = (
            f". '{common}';$hostPath=(Get-Process -Id $PID).Path;"
            "$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Milliseconds 1200'));"
            "$p=Start-Process -FilePath $hostPath -ArgumentList ('-NoProfile -EncodedCommand '+$encoded) -PassThru -WindowStyle Hidden;"
            "[void]$p.Handle;$start=$p.StartTime.ToUniversalTime();$path=$p.Path;"
            f"$r=Stop-G130U1OwnedProcessBounded $p $start $path 'http://127.0.0.1:{server.port}' ('a'*64);$r|ConvertTo-Json -Depth 8 -Compress"
        )
        proc = run_ps_command(command, timeout=15)
        server.join()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        value = json.loads(proc.stdout)
        self.assertEqual(value["shutdown_http_status"], 403)
        self.assertFalse(value["graceful_verified"])
        self.assertFalse(value["graceful_succeeded"])
        self.assertTrue(value["spontaneous_exit"])
        self.assertIn("HTTP_NON_2XX", value["shutdown_cause"])

    def test_abort_decision_is_atomic_first_writer_wins(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            target = pathlib.Path(td) / "abort.json"
            common = str(COMMON).replace("'", "''"); escaped = str(target).replace("'", "''")
            command = f". '{common}';$one=Write-G130U1AbortAtomic '{escaped}' ([pscustomobject]@{{cause='first'}});$two=Write-G130U1AbortAtomic '{escaped}' ([pscustomobject]@{{cause='second'}});[pscustomobject]@{{one=$one;two=$two;value=(Get-Content -LiteralPath '{escaped}' -Raw|ConvertFrom-Json);temporary_count=@(Get-ChildItem -LiteralPath '{str(pathlib.Path(td)).replace("'", "''")}' -Filter '.g130-u1-abort-*.tmp').Count}}|ConvertTo-Json -Depth 5 -Compress"
            proc = run_ps_command(command)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            value = json.loads(proc.stdout)
            self.assertTrue(value["one"])
            self.assertFalse(value["two"])
            self.assertEqual(value["value"]["cause"], "first")
            self.assertEqual(value["temporary_count"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
