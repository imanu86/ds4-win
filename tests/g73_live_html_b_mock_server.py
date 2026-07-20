#!/usr/bin/env python3
"""CPU-only OpenAI-compatible mock for the G73 live HTML runner."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


TURN1_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Neon Forge AI</title>
<style>
body { margin: 0; background: #f4f7fb; color: #151823; font-family: Arial, sans-serif; }
nav { display: flex; justify-content: space-between; padding: 18px 7vw; background: #ffffff; }
.hero { min-height: 58vh; padding: 72px 7vw; background: #dff8ff; }
.accent { color: #006f88; }
form { display: grid; gap: 12px; max-width: 520px; padding: 24px 7vw 64px; }
input, textarea, button { padding: 12px; font: inherit; }
</style>
</head>
<body>
<nav><strong>NEON FORGE AI</strong><a href="#request">Request build</a></nav>
<main class="hero"><h1>Cyberpunk AI programming, forged to ship.</h1><p class="accent">Agents, tools, and custom automation for ambitious teams.</p></main>
<form id="request"><label>Name <input name="name" required></label><label>Project <textarea name="project" required></textarea></label><button type="submit">Transmit request</button></form>
<script>document.getElementById('request').addEventListener('submit',function(event){event.preventDefault();alert('Request received by Neon Forge AI.');});</script>
</body>
</html>"""

TURN2_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Neon Forge AI</title>
<style>
:root { --bg: #050505; --panel: #0d0d12; --text: #f7fbff; --cyan: #00ffff; --magenta: #ff00ff; }
body { margin: 0; background: var(--bg); color: var(--text); font-family: Arial, sans-serif; }
nav { display: flex; justify-content: space-between; padding: 18px 7vw; background: var(--panel); border-bottom: 1px solid var(--cyan); }
nav a, .accent { color: var(--cyan); }
.hero { min-height: 58vh; padding: 72px 7vw; background: #08080d; }
h1 { text-shadow: 2px 2px 0 var(--magenta); }
form { display: grid; gap: 12px; max-width: 520px; padding: 24px 7vw 64px; }
input, textarea { padding: 12px; background: #111118; color: #ffffff; border: 1px solid var(--cyan); }
button { padding: 12px; background: var(--magenta); color: #ffffff; border: 0; }
</style>
</head>
<body>
<nav><strong>NEON FORGE AI</strong><a href="#request">Request build</a></nav>
<main class="hero"><h1>Cyberpunk AI programming, forged to ship.</h1><p class="accent">Agents, tools, and custom automation for ambitious teams.</p></main>
<form id="request"><label>Name <input name="name" required></label><label>Project <textarea name="project" required></textarea></label><button type="submit">Transmit request</button></form>
<script>document.getElementById('request').addEventListener('submit',function(event){event.preventDefault();alert('Request received by Neon Forge AI.');});</script>
</body>
</html>"""

MALFORMED_TURN1 = "```html\n<html><body><h1>cut off"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class MockState:
    def __init__(self, capture_dir: Path, scenario: str) -> None:
        self.capture_dir = capture_dir
        self.scenario = scenario
        self.requests = 0
        self.lock = threading.Lock()

    def record_request(self, raw: bytes) -> tuple[int, dict]:
        text = raw.decode("utf-8", errors="strict")
        payload = json.loads(text)
        with self.lock:
            self.requests += 1
            index = self.requests
        raw_path = self.capture_dir / f"request{index}.raw.json"
        canonical_path = self.capture_dir / f"request{index}.canonical.json"
        raw_path.write_bytes(raw)
        canonical = json.dumps(
            payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        canonical_path.write_bytes(canonical)
        receipt = {
            "index": index,
            "raw_path": str(raw_path),
            "raw_sha256": sha256_bytes(raw),
            "raw_bytes": len(raw),
            "canonical_path": str(canonical_path),
            "canonical_sha256": sha256_bytes(canonical),
            "canonical_bytes": len(canonical),
            "roles": [message.get("role") for message in payload.get("messages", [])],
        }
        (self.capture_dir / f"request{index}.capture.json").write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return index, payload


class Handler(BaseHTTPRequestHandler):
    server_version = "G73LiveMock/1.0"

    @property
    def state(self) -> MockState:
        return self.server.mock_state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stdout.write("[mock-http] " + (fmt % args) + "\n")
        sys.stdout.flush()

    def send_json(self, status: int, value: dict) -> None:
        body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self.send_json(200, {"status": "ready", "scenario": self.state.scenario})
            return
        self.send_json(404, {"error": "not-found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/chat/completions":
            self.send_json(404, {"error": "not-found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            index, _payload = self.state.record_request(raw)
        except Exception as exc:  # pragma: no cover - fail closed for runner diagnostics
            self.send_json(400, {"error": f"invalid-request:{exc}"})
            return

        if self.state.scenario == "malformed-turn1":
            content = MALFORMED_TURN1
            finish_reason = "stop"
        elif index == 1:
            content = TURN1_HTML
            finish_reason = "stop"
        elif index == 2:
            content = TURN2_HTML
            finish_reason = "stop"
        else:
            self.send_json(409, {"error": "unexpected-request-count"})
            return

        assistant_path = self.state.capture_dir / f"response{index}.assistant.txt"
        assistant_path.write_bytes(content.encode("utf-8"))
        response = {
            "id": f"g73-mock-{index}",
            "object": "chat.completion",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": finish_reason,
                }
            ],
            "usage": {
                "prompt_tokens": 100 + index,
                "completion_tokens": len(content.split()),
                "total_tokens": 100 + index + len(content.split()),
            },
        }
        self.send_json(200, response)
        if self.state.scenario == "success" and index == 2:
            threading.Thread(target=self.server.shutdown, daemon=True).start()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument(
        "--scenario",
        choices=("success", "exit-before-readiness", "malformed-turn1"),
        required=True,
    )
    parser.add_argument("--capture-dir", type=Path, required=True)
    args = parser.parse_args()
    args.capture_dir.mkdir(parents=True, exist_ok=True)

    if args.scenario == "exit-before-readiness":
        (args.capture_dir / "mock_server_state.json").write_text(
            json.dumps({"status": "intentional-exit-before-readiness", "exit_code": 23}),
            encoding="utf-8",
        )
        return 23

    state = MockState(args.capture_dir, args.scenario)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.mock_state = state  # type: ignore[attr-defined]
    (args.capture_dir / "mock_server_state.json").write_text(
        json.dumps({"status": "ready", "port": args.port, "scenario": args.scenario}),
        encoding="utf-8",
    )
    print(f"[mock-http] ready port={args.port} scenario={args.scenario}", flush=True)
    try:
        server.serve_forever(poll_interval=0.05)
    finally:
        server.server_close()
        (args.capture_dir / "mock_server_final.json").write_text(
            json.dumps({"status": "closed", "requests": state.requests}), encoding="utf-8"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
