#!/usr/bin/env python3
"""Unit tests for the regression checker's structured JSON validation.

Tests the following edge cases:
1. Valid JSON matching the unique fresh completion runId and all required suites.
2. Missing JSON marker in console output.
3. Stale JSON (runId does not match the active verified runId).
4. Malformed JSON (syntax error / invalid JSON string).
5. Failed output reported in JSON (failed > 0 or suite ok=False).
6. Missing required suites in the JSON suites list.
"""

import json
import unittest
import sys
import os

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from check_all_suites import parse_and_validate_regression_json, count_source_metrics, EXPECTED_SUITES


class TestRegressionChecker(unittest.TestCase):
    def setUp(self):
        self.sample_run_id = "test-run-uuid-12345"
        self.valid_suites = [
            {"ok": True, "name": f"{suite}.spec", "detail": f"{suite}: all passed"}
            for suite in EXPECTED_SUITES
        ]
        self.valid_payload = {
            "runId": self.sample_run_id,
            "failed": 0,
            "suites": self.valid_suites,
        }

    def test_valid_json_matching_run_id(self):
        console = (
            "Some previous logs...\n"
            f"BS_REGRESSION_RESULT {json.dumps(self.valid_payload)}\n"
            f"BS01_TESTS_PASSED:{self.sample_run_id}\n"
        )
        ok, msg, payload = parse_and_validate_regression_json(console, self.sample_run_id, EXPECTED_SUITES)
        self.assertTrue(ok, f"Expected validation success, got: {msg}")
        self.assertEqual(payload.get("failed"), 0)
        self.assertEqual(payload.get("runId"), self.sample_run_id)

    def test_missing_json(self):
        console = (
            "Some logs without structured JSON marker...\n"
            f"BS01_TESTS_PASSED:{self.sample_run_id}\n"
        )
        ok, msg, _ = parse_and_validate_regression_json(console, self.sample_run_id, EXPECTED_SUITES)
        self.assertFalse(ok)
        self.assertIn("Missing BS_REGRESSION_RESULT", msg)

    def test_stale_json(self):
        stale_payload = dict(self.valid_payload)
        stale_payload["runId"] = "stale-old-run-id-99999"
        console = f"BS_REGRESSION_RESULT {json.dumps(stale_payload)}\n"
        ok, msg, _ = parse_and_validate_regression_json(console, self.sample_run_id, EXPECTED_SUITES)
        self.assertFalse(ok)
        self.assertIn("Stale BS_REGRESSION_RESULT runId", msg)
        self.assertIn(self.sample_run_id, msg)

    def test_malformed_json(self):
        console = "BS_REGRESSION_RESULT {not-valid-json: true, unterminated\n"
        ok, msg, _ = parse_and_validate_regression_json(console, self.sample_run_id, EXPECTED_SUITES)
        self.assertFalse(ok)
        self.assertIn("Malformed BS_REGRESSION_RESULT JSON", msg)

    def test_failed_output_in_json(self):
        failed_payload = dict(self.valid_payload)
        failed_payload["failed"] = 1
        failed_payload["suites"] = [
            {"ok": s["name"] != "EconomyService.spec", "name": s["name"], "detail": s["detail"]}
            for s in self.valid_suites
        ]
        console = f"BS_REGRESSION_RESULT {json.dumps(failed_payload)}\n"
        ok, msg, _ = parse_and_validate_regression_json(console, self.sample_run_id, EXPECTED_SUITES)
        self.assertFalse(ok)
        self.assertIn("test failures", msg)

    def test_missing_required_suites_in_json(self):
        incomplete_payload = dict(self.valid_payload)
        # Drop WorldService
        incomplete_payload["suites"] = [s for s in self.valid_suites if "WorldService" not in s["name"]]
        console = f"BS_REGRESSION_RESULT {json.dumps(incomplete_payload)}\n"
        ok, msg, _ = parse_and_validate_regression_json(console, self.sample_run_id, EXPECTED_SUITES)
        self.assertFalse(ok)
        self.assertIn("Missing required suites", msg)
        self.assertIn("WorldService", msg)

    def test_count_source_metrics_valid(self):
        tests, asserts = count_source_metrics()
        self.assertGreater(tests, 600)
        self.assertGreater(asserts, 3000)

    def test_count_source_metrics_missing_dir_fails_closed(self):
        with self.assertRaises(FileNotFoundError):
            count_source_metrics("/non/existent/path/for/sure")


if __name__ == "__main__":
    unittest.main()
