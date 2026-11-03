#!/usr/bin/env python3
"""Automated regression runner for Roblox Studio test suite.

Authoritative contract:
- Runs Play Solo via StudioMCP
- Polls console until explicit completion marker or timeout
- Parses all 19 test suites and validates 0 failures
- Analyzes source-defined tests, runtime executions, and assertions
- Exits nonzero on any failure, timeout, or missing suite
- Saves full raw console output to docs/logs/studio_regression_console.log
"""

import sys
import os
import re
import time
import json
from typing import Dict, List, Tuple

sys.path.append(os.path.abspath("tools/agent"))
import studio

EXPECTED_SUITES = [
    "AppClientIntegration",
    "BS09FastPhone",
    "BS10Recovery",
    "BS11M1Content",
    "BS12WorkerEconomy",
    "BS13HomeStudio",
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
            tests = re.findall(r'(?m)^\s*test\s*\(', content)
            asserts = re.findall(r'\b(?:expect\w*|assert\w*|equal|check|truth)\s*\(', content)
            total_tests += len(tests)
            total_asserts += len(asserts)

    return total_tests, total_asserts


def parse_and_validate_regression_json(
    raw_console: str,
    expected_run_id: str,
    expected_suites: List[str],
) -> Tuple[bool, str, Dict]:
    """Validate BS_REGRESSION_RESULT JSON against runId and expected suites.

    Returns (is_valid, error_or_success_message, parsed_payload).
    Handles missing, stale, malformed, incomplete, and failed outputs.
    """
    pattern = re.compile(r"BS_REGRESSION_RESULT\s+(.*)")
    matches = [m.strip() for m in pattern.findall(raw_console) if m.strip()]
    if not matches:
        return False, "Missing BS_REGRESSION_RESULT JSON in output", {}

    matching_payload = None
    for raw_json in reversed(matches):
        try:
            payload = json.loads(raw_json)
        except Exception:
            continue
        if payload.get("runId") == expected_run_id:
            matching_payload = payload
            break

    if matching_payload is None:
        try:
            latest_payload = json.loads(matches[-1])
            return (
                False,
                f"Stale BS_REGRESSION_RESULT runId: expected {expected_run_id}, got {latest_payload.get('runId')}",
                latest_payload,
            )
        except Exception as e:
            return False, f"Malformed BS_REGRESSION_RESULT JSON: {e}", {}

    payload = matching_payload
    failed_count = payload.get("failed", -1)
    if failed_count != 0:
        return False, f"Structured result reports {failed_count} test failures", payload

    suite_list = payload.get("suites", [])
    if not isinstance(suite_list, list):
        return False, "Malformed BS_REGRESSION_RESULT: 'suites' must be a list", payload

    suite_map = {}
    for item in suite_list:
        if isinstance(item, dict) and "name" in item:
            clean_name = item["name"].replace(".spec", "")
            suite_map[clean_name] = item

    missing_suites = [s for s in expected_suites if s not in suite_map]
    if missing_suites:
        return False, f"Missing required suites in structured result: {missing_suites}", payload

    failed_suites = [s for s, item in suite_map.items() if not item.get("ok", False)]
    if failed_suites:
        return False, f"Failed suites in structured result: {failed_suites}", payload

    return True, f"Structured result verified: runId={expected_run_id}, {len(suite_map)} suites passed", payload


def run_regression_suite(timeout_sec: float = 30.0, studio_id: str = None, log_file: str = LOG_FILE) -> bool:
    def call(name, args):
        return studio.call(name, {**args, **({"studio_id": studio_id} if studio_id else {})})

    print(f"=== Starting Studio Regression Runner (Timeout: {timeout_sec}s) ===")
    source_tests, source_asserts = count_source_metrics()
    print(f"Static Analysis: {len(EXPECTED_SUITES)} spec files, {source_tests} source-defined tests, ~{source_asserts} assertion calls.")

    marker_pattern = re.compile(r"BS01_TESTS_(PASSED|FAILED):([a-fA-F0-9-]+)")
    previous_runs = {run_id for _, run_id in marker_pattern.findall(call("get_console_output", {}))}

    # Start Play Solo
    print("Initiating Play Solo session...")
    call("start_stop_play", {"is_start": True})

    start_time = time.time()
    raw_console = ""
    completed = False
    passed_marker = False
    failed_marker = False
    verified_run_id = ""

    try:
        while time.time() - start_time < timeout_sec:
            time.sleep(1.0)
            raw_console = call("get_console_output", {})

            fresh_markers = [(status, run_id) for status, run_id in marker_pattern.findall(raw_console) if run_id not in previous_runs]
            if fresh_markers:
                status, run_id = fresh_markers[-1]
                completed = True
                passed_marker = status == "PASSED"
                failed_marker = status == "FAILED"
                verified_run_id = run_id
                print(f"Verified fresh completion: {status}:{run_id}")
                try:
                    # Capture complete server LogService history before stopping Play Solo
                    history = []
                    offset = 1
                    while True:
                        code = f'local h=game:GetService("LogService"):GetLogHistory(); local page={{}}; for i={offset},math.min({offset+99},#h) do table.insert(page,{{message=h[i].message,timestamp=h[i].timestamp}}) end; return game:GetService("HttpService"):JSONEncode({{total=#h,messages=page}})'
                        page_res = studio.get_client().call_tool("execute_luau", {"code": code, "datamodel_type": "Server", "studio_id": studio_id})
                        page_text = page_res["content"][0]["text"]
                        page = json.loads(page_text)
                        history.extend(page["messages"])
                        offset += len(page["messages"])
                        if offset > page["total"] or not page["messages"]:
                            break
                    full_server_log = "\n".join(item["message"] for item in history)
                    # Only adopt the LogService history when it actually contains
                    # the fresh run's marker; stale history across play sessions
                    # must never mask the marker stream of a FAILED run.
                    if len(full_server_log) > len(raw_console) and run_id in full_server_log:
                        raw_console = full_server_log
                except Exception as log_err:
                    print(f"Note: LogService page fetch: {log_err}")
                break
    finally:
        # Always terminate Play Solo session back to Edit
        print("Stopping Play Solo session...")
        call("start_stop_play", {"is_start": False})

    elapsed = time.time() - start_time
    print(f"Execution finished in {elapsed:.2f} seconds.")

    # Save raw console output to evidence log
    os.makedirs(os.path.dirname(os.path.abspath(log_file)), exist_ok=True)
    with open(log_file, "w", encoding="utf-8") as f:
        f.write(raw_console)
    print(f"Saved full raw console output ({len(raw_console)} chars) to: {log_file}")

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
    print(f"\n=== Parsed Suite Summary ({len(parsed_suites)}/{len(EXPECTED_SUITES)} found) ===")
    all_ok = True

    for name in EXPECTED_SUITES:
        if name in parsed_suites:
            info = parsed_suites[name]
            st = info["status"]
            det = info["detail"]
            counts = re.search(r"(\d+)/(\d+)\s+passed", det)
            if st != "PASS" or counts is None or counts.group(1) != counts.group(2):
                all_ok = False
            print(f"  [{st}] {name:<24} : {det}")
        else:
            print(f"  [MISSING] {name:<24} : NOT FOUND in console output!")
            all_ok = False

    runtime_tests_executed = sum(int(m.group(1)) for info in parsed_suites.values() if (m := re.search(r"(\d+)/(\d+)\s+passed", info["detail"])))
    print("\n=== Test Metrics Breakdown ===")
    print(f"  - Source-defined test cases : {source_tests}")
    print(f"  - Runtime test executions   : {runtime_tests_executed}")
    print(f"  - Static assertion calls    : ~{source_asserts}")

    # Validate structured BS_REGRESSION_RESULT JSON against verified run ID
    json_ok, json_msg, _ = parse_and_validate_regression_json(raw_console, verified_run_id, EXPECTED_SUITES)
    print("\n=== Structured JSON Verification ===")
    if json_ok:
        print(f"  [PASS] {json_msg}")
    else:
        print(f"  [FAIL] {json_msg}")
        all_ok = False

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
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--studio-id", required=True, help="Explicit isolated test Studio target")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--log-file", default=LOG_FILE)
    args = parser.parse_args()
    success = run_regression_suite(timeout_sec=args.timeout, studio_id=args.studio_id, log_file=args.log_file)
    sys.exit(0 if success else 1)
