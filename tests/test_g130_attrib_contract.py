#!/usr/bin/env python3
"""EXECUTED tests for the G130 attribution-v2 stderr contract."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "tests" / "g130_attrib_validator.py"
FIXTURES = ROOT / "tests" / "fixtures" / "g130_attrib"


def run_validator(path: pathlib.Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(path), "--json"],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )


class G130AttributionContractTests(unittest.TestCase):
    def test_valid_fixture_executes_and_reports_computed_totals(self) -> None:
        proc = run_validator(FIXTURES / "valid.stderr.log")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(proc.stdout)
        self.assertEqual(report["tokens"], 3)
        self.assertAlmostEqual(report["decode_total_s"], 0.032000, places=9)
        self.assertAlmostEqual(report["sum_total_s"], 0.027300, places=9)
        self.assertAlmostEqual(report["residual_total_s"], 0.004700, places=9)
        self.assertAlmostEqual(report["residual_pct"], 14.687500, places=9)
        self.assertEqual(
            set(report["span_totals_s"]),
            {
                "mixed_q1_call",
                "h2d_enqueue",
                "existing_stream_sync_wait",
                "mixed_join",
                "promotion_staging",
                "kernel_launch_enqueue",
            },
        )

    def test_valid_fixture_with_loop_overhead_executes(self) -> None:
        proc = run_validator(FIXTURES / "valid_with_loop_overhead.stderr.log")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        report = json.loads(proc.stdout)
        self.assertAlmostEqual(report["decode_total_s"], 0.032000, places=9)
        self.assertAlmostEqual(report["wall_total_s"], 0.035000, places=9)
        self.assertAlmostEqual(report["loop_overhead_s"], 0.003000, places=9)

    def test_invalid_fixtures_execute_and_reject_with_reasons(self) -> None:
        cases = {
            "missing_span.stderr.log": "missing required span",
            "sum_mismatch.stderr.log": "sum mismatch",
            "duplicate_token.stderr.log": "duplicate token",
            "summary_token_count_mismatch.stderr.log": "summary token count mismatch",
            "non_monotonic_tokens.stderr.log": "non-monotonic tokens",
            "loop_overhead_mismatch.stderr.log": "loop_overhead_s mismatch",
            "loop_overhead_only_one_field.stderr.log": "wall_total_s and loop_overhead_s must both be present",
        }
        for name, reason in cases.items():
            with self.subTest(name=name):
                proc = run_validator(FIXTURES / name)
                self.assertNotEqual(proc.returncode, 0, proc.stdout)
                self.assertIn("INVALID:", proc.stderr)
                self.assertIn(reason, proc.stderr)

    def test_every_fixture_is_executed_by_the_contract_suite(self) -> None:
        expected = {
            "valid.stderr.log",
            "valid_with_loop_overhead.stderr.log",
            "missing_span.stderr.log",
            "sum_mismatch.stderr.log",
            "duplicate_token.stderr.log",
            "summary_token_count_mismatch.stderr.log",
            "non_monotonic_tokens.stderr.log",
            "loop_overhead_mismatch.stderr.log",
            "loop_overhead_only_one_field.stderr.log",
        }
        self.assertEqual({path.name for path in FIXTURES.glob("*.stderr.log")}, expected)


if __name__ == "__main__":
    unittest.main()
