#!/usr/bin/env python3
"""Automated regression runner for Roblox Studio test suite.

Authoritative contract:
- Runs Play Solo via StudioMCP
- Polls console until explicit completion marker or timeout
- Parses all 18 test suites and validates 0 failures
- Analyzes source-defined tests, runtime executions, and assertions
- Exits nonzero on any failure, timeout, or missing suite
- Saves full raw console output to docs/logs/studio_regression_console.log
"""

import sys
import os
import re
import time
from typing import Dict, List, Tuple

sys.path.append(os.path.abspath("tools/agent"))
import studio

EXPECTED_SUITES = [
    "AppClientIntegration",
    "BS09FastPhone",
    "BS10Recovery",
    "BS11M1Content",
    "Bootstrap",
    "ClientState",
    "ComposerIntegration",
    "EconomyService",
    "FeedService",
    "MissionService",
    "NetRouter",
    "PostingState",
    "Presentation",
    "ProfileStore",
    "Rules",
    "SessionIntegration",
    "SessionService",
    "WorldService",
]

LOG_FILE = "docs/logs/studio_regression_console.log"


def count_source_metrics() -> Tuple[int, int]:
    """Inspect tests/Specs to count source-defined test functions and expect calls."""
    specs_dir = "tests/Specs"
    total_tests = 0
    total_asserts = 0

    if not os.path.exists(specs_dir):
        return 0, 0

    for f in sorted(os.listdir(specs_dir)):
        if f.endswith(".spec.luau"):
            path = os.path.join(specs_dir, f)
            with open(path, "r", encoding="utf-8") as file:
                content = file.read()
            tests = re.findall(r'(?:^|\s)test\s*\(\s*["\']', content)
            asserts = re.findall(r'expect(?:Equal|True|False|NotNil|Nil|WithinTolerance|Error|Match)\s*\(', content)
            total_tests += len(tests)
            total_asserts += len(asserts)

    return total_tests, total_asserts


def run_regression_suite(timeout_sec: float = 30.0) -> bool:
    print(f"=== Starting Studio Regression Runner (Timeout: {timeout_sec}s) ===")
    source_tests, source_asserts = count_source_metrics()
    print(f"Static Analysis: {len(EXPECTED_SUITES)} spec files, {source_tests} source-defined tests, ~{source_asserts} assertion calls.")

    # Start Play Solo
    print("Initiating Play Solo session...")
    studio.call("start_stop_play", {"is_start": True})

    start_time = time.time()
    raw_console = ""
    completed = False
    passed_marker = False
    failed_marker = False

    try:
        while time.time() - start_time < timeout_sec:
            time.sleep(1.0)
            raw_console = studio.call("get_console_output", {})

            if "BS01_TESTS_PASSED" in raw_console:
                completed = True
                passed_marker = True
                break
            elif "BS01_TESTS_FAILED" in raw_console:
                completed = True
                failed_marker = True
                break
    finally:
        # Always terminate Play Solo session back to Edit
        print("Stopping Play Solo session...")
        studio.call("start_stop_play", {"is_start": False})

    elapsed = time.time() - start_time
    print(f"Execution finished in {elapsed:.2f} seconds.")

    # Save raw console output to evidence log
    os.makedirs(os.path.dirname(os.path.abspath(LOG_FILE)), exist_ok=True)
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write(raw_console)
    print(f"Saved full raw console output ({len(raw_console)} chars) to: {LOG_FILE}")

    if not completed:
        print(f"\n[FATAL ERROR] Test suite execution timed out after {timeout_sec}s without completion marker!")
        return False

    # Parse individual suite outcomes
    parsed_suites: Dict[str, Dict[str, str]] = {}
    runtime_tests_executed = 0

    suite_pattern = re.compile(r"\[(SUITE PASS|SUITE FAIL)\]\s+([A-Za-z0-9_]+)(?:\.spec)?:\s+(.*)")
    for line in raw_console.splitlines():
        match = suite_pattern.search(line)
        if match:
            status_str, raw_suite_name, detail = match.groups()
            suite_name = raw_suite_name.replace(".spec", "")
            parsed_suites[suite_name] = {
                "status": "PASS" if status_str == "SUITE PASS" else "FAIL",
                "detail": detail.strip(),
            }
            # Attempt to extract test counts e.g. "X/Y passed" or "X/X passed"
            cnt_match = re.search(r"(\d+)/(\d+)\s+passed", detail)
            if cnt_match:
                runtime_tests_executed += int(cnt_match.group(2))

    print(f"\n=== Parsed Suite Summary ({len(parsed_suites)}/{len(EXPECTED_SUITES)} found) ===")
    all_ok = True

    for name in EXPECTED_SUITES:
        if name in parsed_suites:
            info = parsed_suites[name]
            st = info["status"]
            det = info["detail"]
            if st != "PASS":
                all_ok = False
            print(f"  [{st}] {name:<24} : {det}")
        else:
            print(f"  [MISSING] {name:<24} : NOT FOUND in console output!")
            all_ok = False

    print("\n=== Test Metrics Breakdown ===")
    print(f"  - Source-defined test cases : {source_tests}")
    print(f"  - Runtime test executions   : {runtime_tests_executed}")
    print(f"  - Static assertion calls    : ~{source_asserts}")

    if failed_marker or not passed_marker:
        print("\n[FAIL] Console contains failure marker BS01_TESTS_FAILED or missing BS01_TESTS_PASSED.")
        all_ok = False

    if len(parsed_suites) < len(EXPECTED_SUITES):
        print(f"\n[FAIL] Missing required suites: expected {len(EXPECTED_SUITES)}, found {len(parsed_suites)}.")
        all_ok = False

    if all_ok:
        print(f"\n[SUCCESS] ALL {len(EXPECTED_SUITES)} SUITES PASSED CLEANLY ({runtime_tests_executed} runtime tests verified).")
        return True
    else:
        print("\n[FAILURE] Regression suite failed verification.")
        return False


if __name__ == "__main__":
    success = run_regression_suite(timeout_sec=30.0)
    sys.exit(0 if success else 1)
