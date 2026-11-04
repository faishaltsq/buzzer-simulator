import sys, time, json
sys.path.append('tools/agent')
import studio

print(studio.call("start_stop_play", {"is_start": True}))
time.sleep(2)
# poll console for terminal marker
marker = None
console = ""
for i in range(40):
    time.sleep(3)
    console = studio.call("get_console_output", {})
    if "BS01_TESTS_PASSED:" in console or "BS01_TESTS_FAILED:" in console:
        marker = console
        break
if marker is None:
    print("NO MARKER within timeout")
    print(console[-4000:])
    sys.exit(2)
# extract structured JSON line
lines = console.splitlines()
jsonline = [l for l in lines if l.startswith("BS_REGRESSION_RESULT ")]
print("MARKER:", [l for l in lines if "BS01_TESTS" in l])
if jsonline:
    payload = json.loads(jsonline[-1][len("BS_REGRESSION_RESULT "):])
    print("RUN_ID:", payload["runId"])
    print("FAILED:", payload["failed"])
    for s in payload["suites"]:
        print(("PASS " if s["ok"] else "FAIL ") + s["name"] + " :: " + s["detail"])
    with open("docs/evidence/bs14/g0-regression-raw.txt", "w", encoding="utf-8") as f:
        f.write(console)
    with open("docs/evidence/bs14/g0-regression.json", "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
print(studio.call("start_stop_play", {"is_start": False}))
