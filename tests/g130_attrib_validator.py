#!/usr/bin/env python3
"""Parser and validator for the G130 attribution-v2 stderr contract."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys
from dataclasses import dataclass
from typing import Optional


EPSILON = 1e-6
REQUIRED_SPANS = {
    "mixed_q1_call",
    "h2d_enqueue",
    "existing_stream_sync_wait",
    "mixed_join",
    "promotion_staging",
    "kernel_launch_enqueue",
}

TOKEN_PREFIX = "ds4: [g130-attrib] "
SUMMARY_PREFIX = "ds4: [g130-attrib-summary] "
TOKEN_RE = re.compile(r"^token=(?P<token>\d+)$")
FLOAT_RE = re.compile(
    r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"
)


@dataclass(frozen=True)
class TokenAttribution:
    token: int
    decode_ms: float
    spans_ms: dict[str, float]
    sum_ms: float
    residual_ms: float


@dataclass(frozen=True)
class AttributionSummary:
    tokens: int
    decode_total_s: float
    sum_total_s: float
    residual_total_s: float
    residual_pct: float
    wall_total_s: Optional[float]
    loop_overhead_s: Optional[float]
    span_totals_s: dict[str, float]


@dataclass(frozen=True)
class AttributionReport:
    tokens: list[TokenAttribution]
    summary: AttributionSummary
    computed_decode_total_s: float
    computed_sum_total_s: float
    computed_residual_total_s: float
    computed_residual_pct: float
    computed_span_totals_s: dict[str, float]


class G130AttributionError(ValueError):
    """Raised when stderr does not satisfy the G130 attribution contract."""


def _parse_float(raw: str, field: str, line_no: int) -> float:
    if not FLOAT_RE.match(raw):
        raise G130AttributionError(f"line {line_no}: {field} is not a float")
    value = float(raw)
    if not math.isfinite(value):
        raise G130AttributionError(f"line {line_no}: {field} is not finite")
    return value


def _parse_int(raw: str, field: str, line_no: int) -> int:
    if not re.match(r"^\d+$", raw):
        raise G130AttributionError(f"line {line_no}: {field} is not an integer")
    return int(raw)


def _parse_fields(line: str, prefix: str, line_no: int) -> list[tuple[str, str]]:
    if not line.startswith(prefix):
        raise G130AttributionError(f"line {line_no}: missing {prefix.strip()} prefix")
    fields: list[tuple[str, str]] = []
    seen: set[str] = set()
    for item in line[len(prefix) :].split():
        if "=" not in item:
            raise G130AttributionError(f"line {line_no}: non key/value field {item}")
        key, value = item.split("=", 1)
        if key in seen:
            raise G130AttributionError(f"line {line_no}: duplicate field {key}")
        seen.add(key)
        fields.append((key, value))
    return fields


def _close(actual: float, expected: float) -> bool:
    return abs(actual - expected) <= EPSILON


def _parse_token_line(line: str, line_no: int) -> TokenAttribution:
    fields = _parse_fields(line, TOKEN_PREFIX, line_no)
    if len(fields) < 5:
        raise G130AttributionError(f"line {line_no}: token attribution is incomplete")
    token_match = TOKEN_RE.match("=".join(fields[0]))
    if not token_match:
        raise G130AttributionError(f"line {line_no}: first field must be token=<n>")
    if fields[1][0] != "decode_ms":
        raise G130AttributionError(f"line {line_no}: second field must be decode_ms")
    if fields[-2][0] != "sum_ms" or fields[-1][0] != "residual_ms":
        raise G130AttributionError(f"line {line_no}: sum_ms and residual_ms must close the line")

    spans: dict[str, float] = {}
    for key, raw in fields[2:-2]:
        if not key.startswith("span_") or not key.endswith("_ms"):
            raise G130AttributionError(f"line {line_no}: unexpected field {key}")
        name = key[len("span_") : -len("_ms")]
        spans[name] = _parse_float(raw, key, line_no)

    missing = REQUIRED_SPANS - set(spans)
    if missing:
        raise G130AttributionError(
            f"line {line_no}: missing required span(s): {', '.join(sorted(missing))}"
        )

    decode_ms = _parse_float(fields[1][1], "decode_ms", line_no)
    sum_ms = _parse_float(fields[-2][1], "sum_ms", line_no)
    residual_ms = _parse_float(fields[-1][1], "residual_ms", line_no)
    computed_sum = sum(spans.values())
    if not _close(sum_ms, computed_sum):
        raise G130AttributionError(
            f"line {line_no}: sum mismatch expected {computed_sum:.12g} got {sum_ms:.12g}"
        )
    computed_residual = decode_ms - sum_ms
    if not _close(residual_ms, computed_residual):
        raise G130AttributionError(
            f"line {line_no}: residual mismatch expected {computed_residual:.12g} got {residual_ms:.12g}"
        )

    return TokenAttribution(
        token=_parse_int(token_match.group("token"), "token", line_no),
        decode_ms=decode_ms,
        spans_ms=spans,
        sum_ms=sum_ms,
        residual_ms=residual_ms,
    )


def _parse_summary_line(line: str, line_no: int) -> AttributionSummary:
    fields = _parse_fields(line, SUMMARY_PREFIX, line_no)
    required_order = [
        "tokens",
        "decode_total_s",
        "sum_total_s",
        "residual_total_s",
        "residual_pct",
    ]
    if [key for key, _ in fields[:5]] != required_order:
        raise G130AttributionError(f"line {line_no}: summary header fields are out of order")
    optional_keys = {"wall_total_s", "loop_overhead_s"}
    tail_keys = [key for key, _ in fields[5:]]
    has_optional = any(key in optional_keys for key in tail_keys)
    wall_total_s: Optional[float] = None
    loop_overhead_s: Optional[float] = None
    span_start = 5
    if has_optional:
        if len(fields) < 7 or fields[5][0] != "wall_total_s" or fields[6][0] != "loop_overhead_s":
            raise G130AttributionError(
                f"line {line_no}: wall_total_s and loop_overhead_s must both be present after residual_pct"
            )
        wall_total_s = _parse_float(fields[5][1], "wall_total_s", line_no)
        loop_overhead_s = _parse_float(fields[6][1], "loop_overhead_s", line_no)
        span_start = 7
    span_totals: dict[str, float] = {}
    for key, raw in fields[span_start:]:
        if not key.startswith("span_") or not key.endswith("_total_s"):
            raise G130AttributionError(f"line {line_no}: unexpected summary field {key}")
        name = key[len("span_") : -len("_total_s")]
        span_totals[name] = _parse_float(raw, key, line_no)
    missing = REQUIRED_SPANS - set(span_totals)
    if missing:
        raise G130AttributionError(
            f"line {line_no}: missing required summary span(s): {', '.join(sorted(missing))}"
        )
    return AttributionSummary(
        tokens=_parse_int(fields[0][1], "tokens", line_no),
        decode_total_s=_parse_float(fields[1][1], "decode_total_s", line_no),
        sum_total_s=_parse_float(fields[2][1], "sum_total_s", line_no),
        residual_total_s=_parse_float(fields[3][1], "residual_total_s", line_no),
        residual_pct=_parse_float(fields[4][1], "residual_pct", line_no),
        wall_total_s=wall_total_s,
        loop_overhead_s=loop_overhead_s,
        span_totals_s=span_totals,
    )


def parse_attribution(text: str) -> tuple[list[TokenAttribution], AttributionSummary]:
    token_rows: list[TokenAttribution] = []
    summary_rows: list[AttributionSummary] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        if line.startswith(TOKEN_PREFIX):
            token_rows.append(_parse_token_line(line, line_no))
        elif line.startswith(SUMMARY_PREFIX):
            summary_rows.append(_parse_summary_line(line, line_no))
    if not token_rows:
        raise G130AttributionError("no g130-attrib token lines found")
    if len(summary_rows) != 1:
        raise G130AttributionError(
            f"expected exactly one g130-attrib-summary line, found {len(summary_rows)}"
        )
    return token_rows, summary_rows[0]


def validate_attribution(text: str) -> AttributionReport:
    token_rows, summary = parse_attribution(text)
    seen: set[int] = set()
    previous: int | None = None
    for row in token_rows:
        if row.token in seen:
            raise G130AttributionError(f"duplicate token {row.token}")
        seen.add(row.token)
        if previous is not None and row.token <= previous:
            raise G130AttributionError(
                f"non-monotonic tokens: {row.token} follows {previous}"
            )
        previous = row.token

    if summary.tokens != len(token_rows):
        raise G130AttributionError(
            f"summary token count mismatch expected {len(token_rows)} got {summary.tokens}"
        )

    span_names = set().union(*(row.spans_ms.keys() for row in token_rows))
    computed_span_totals = {
        name: sum(row.spans_ms.get(name, 0.0) for row in token_rows) / 1000.0
        for name in sorted(span_names)
    }
    computed_decode_total = sum(row.decode_ms for row in token_rows) / 1000.0
    computed_sum_total = sum(row.sum_ms for row in token_rows) / 1000.0
    computed_residual_total = sum(row.residual_ms for row in token_rows) / 1000.0
    computed_residual_pct = (
        computed_residual_total / computed_decode_total * 100.0
        if computed_decode_total
        else 0.0
    )

    if not _close(summary.decode_total_s, computed_decode_total):
        raise G130AttributionError("decode_total_s mismatch")
    if not _close(summary.sum_total_s, computed_sum_total):
        raise G130AttributionError("sum_total_s mismatch")
    if not _close(summary.residual_total_s, computed_residual_total):
        raise G130AttributionError("residual_total_s mismatch")
    if not _close(summary.residual_pct, computed_residual_pct):
        raise G130AttributionError("residual_pct mismatch")
    if (summary.wall_total_s is None) != (summary.loop_overhead_s is None):
        raise G130AttributionError("wall_total_s and loop_overhead_s must both be present or absent")
    if summary.wall_total_s is not None and summary.loop_overhead_s is not None:
        computed_loop_overhead = summary.wall_total_s - summary.decode_total_s
        if not _close(summary.loop_overhead_s, computed_loop_overhead):
            raise G130AttributionError("loop_overhead_s mismatch")
        if summary.loop_overhead_s < -EPSILON:
            raise G130AttributionError("loop_overhead_s is negative")
    summary_span_sum = sum(summary.span_totals_s.values())
    if not _close(summary.sum_total_s, summary_span_sum):
        raise G130AttributionError("summary span totals do not sum to sum_total_s")
    summary_residual = summary.decode_total_s - summary.sum_total_s
    if not _close(summary.residual_total_s, summary_residual):
        raise G130AttributionError("summary residual does not close")
    for name in REQUIRED_SPANS:
        if name not in summary.span_totals_s:
            raise G130AttributionError(f"summary missing span {name}")
    for name, computed in computed_span_totals.items():
        if name not in summary.span_totals_s:
            raise G130AttributionError(f"summary missing span {name}")
        if not _close(summary.span_totals_s[name], computed):
            raise G130AttributionError(f"summary span total mismatch: {name}")

    return AttributionReport(
        tokens=token_rows,
        summary=summary,
        computed_decode_total_s=computed_decode_total,
        computed_sum_total_s=computed_sum_total,
        computed_residual_total_s=computed_residual_total,
        computed_residual_pct=computed_residual_pct,
        computed_span_totals_s=computed_span_totals,
    )


def report_to_jsonable(report: AttributionReport) -> dict[str, object]:
    payload: dict[str, object] = {
        "tokens": len(report.tokens),
        "decode_total_s": report.computed_decode_total_s,
        "sum_total_s": report.computed_sum_total_s,
        "residual_total_s": report.computed_residual_total_s,
        "residual_pct": report.computed_residual_pct,
        "span_totals_s": report.computed_span_totals_s,
    }
    if report.summary.wall_total_s is not None and report.summary.loop_overhead_s is not None:
        payload["wall_total_s"] = report.summary.wall_total_s
        payload["loop_overhead_s"] = report.summary.loop_overhead_s
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("stderr_log", type=pathlib.Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        report = validate_attribution(args.stderr_log.read_text(encoding="utf-8"))
    except G130AttributionError as exc:
        print(f"INVALID: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(report_to_jsonable(report), sort_keys=True, separators=(",", ":")))
    else:
        print("VALID")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
