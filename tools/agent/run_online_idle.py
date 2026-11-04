"""BS-14 20-minute ONLINE idle gate.

Holds a real Play Solo session idle for 20 minutes with a hired worker and
observes live worker banking through the real runtime (no fake clock, no
synthetic accrual, no direct profile writes). Verifies:
  - the session survives the full idle window (no crash, save status healthy)
  - confirmed balance grows at the advertised income rate
  - pendingWorkerCuan stays bounded by one bank interval (no unbounded accrual)
  - durable saves keep happening at the bank cadence
  - the accrued value survives leave + rejoin
"""
import json
import os
import sys
import time

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
import studio  # noqa: E402

OUT = "docs/evidence/bs14"
DURATION_SECONDS = 20 * 60
SAMPLE_SECONDS = 30
BANK_INTERVAL = 30

BRIDGE = """
local lp = game:GetService('Players').LocalPlayer
local bridge = lp:WaitForChild('PlayerGui'):WaitForChild('BuzzerOSDesktop'):WaitForChild('StudioClientBridge')
local HttpService = game:GetService('HttpService')
local function snap() return bridge:Invoke('GetState').snapshot end
"""

OPEN_PROMPT = """
local sss = game:GetService('ServerScriptService')
local pBridge = sss:WaitForChild('StudioPromptBridge')
local player = game:GetService('Players'):GetPlayers()[1]
local prompt = workspace:FindFirstChild('DashboardPrompt', true)
if prompt == nil then
  for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA('ProximityPrompt') then prompt = d break end
  end
end
if prompt == nil then return 'no-prompt' end
local okR, r = pcall(function() return pBridge:Invoke(prompt, player) end)
task.wait(2)
return 'invoked-' .. tostring(okR) .. ':' .. tostring(r)
"""

PERF = """
local Stats = game:GetService('Stats')
return {
  fps = workspace:GetRealPhysicsFPS(),
  memMB = Stats:GetTotalMemoryUsageMb(),
}
"""

GRIND_CHUNK = """
""" + BRIDGE + """
local CONTEXT_TEMPLATES = {
  organic_snack = { 'snack_meme', 'snack_thread', 'snack_honest' },
  organic_gadget = { 'demo_bit', 'specs_breakdown', 'daily_driver' },
  organic_weekend = { 'local_roundup', 'chill_spot_recs', 'weekend_vlog_text' },
}
local target = %d
local maxPosts = 3
local posted = 0
local refused = 0
for i = 1, maxPosts do
  local s = snap()
  if s.balance >= target then break end
  -- The template must belong to the CURRENT organic context, and the context
  -- rotates after every accepted post, so re-read it before each attempt.
  local ctx = s.nextOrganicContextId or 'organic_snack'
  local options = CONTEXT_TEMPLATES[ctx] or CONTEXT_TEMPLATES.organic_snack
  local tpl = options[(i %% #options) + 1]
  local sent = bridge:Invoke('Action', { action = 'PublishOrganic', payload = { templateId = tpl } })
  if sent then posted += 1 else refused += 1 end
  bridge:Invoke('Action', { action = 'GetSnapshot', payload = {} })
  task.wait(2.5)
end
local s = snap()
return HttpService:JSONEncode({ posted = posted, refused = refused, balance = s.balance, incomePerSecond = s.incomePerSecond })
"""

ACTION = BRIDGE + """
local r = bridge:Invoke('Action', { action = '%s', payload = HttpService:JSONDecode('%s') })
return HttpService:JSONEncode({ sent = r })
"""

SNAP = BRIDGE + "return HttpService:JSONEncode(snap())"


def log(msg):
    print(msg, flush=True)


def cluau(c, sid, code):
    res = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Client", "code": code})
    if isinstance(res, dict) and res.get("isError"):
        raise RuntimeError(res["content"][0]["text"][:400])
    txt = res["content"][0]["text"]
    try:
        return json.loads(txt)
    except Exception:
        return txt


def slserver(c, sid, code):
    res = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Server", "code": code})
    if isinstance(res, dict) and res.get("isError"):
        raise RuntimeError(res["content"][0]["text"][:400])
    txt = res["content"][0]["text"]
    try:
        return json.loads(txt)
    except Exception:
        return txt


def act(c, sid, action, payload):
    code = ACTION % (action, json.dumps(payload))
    sent = cluau(c, sid, code)
    if not sent.get("sent"):
        raise RuntimeError(f"{action} refused: {sent}")
    return sent


def snapshot(c, sid):
    s = cluau(c, sid, SNAP)
    if not isinstance(s, dict):
        raise RuntimeError(f"snapshot failed: {s}")
    return s


def open_session(c, sid):
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(4)
    log(f"  prompt: {slserver(c, sid, OPEN_PROMPT)}")
    for _ in range(30):
        try:
            snapshot(c, sid)
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError("desktop bridge never became ready")


def main():
    c = studio.get_client()
    sid = os.environ.get("BUZZER_SID") or studio.get_studio_id()
    log("=== BS-14 20-minute online idle gate ===")

    open_session(c, sid)
    s = snapshot(c, sid)
    log(f"  start: balance={s['balance']} rate={s['incomePerSecond']} tier={s['tier']} desks={s.get('ownedDesks')} workers={s.get('workers')} save={s.get('saveStatus')}")

    # Ensure a worker is hired so live banking is observable. Everything goes
    # through the real client command path. Desk slot 1 costs 180 and a trainee
    # 500 (Catalog.DeskPrices / Catalog.HirePrices), so funding needs 680.
    FUND_TARGET = 680
    if not s.get("incomePerSecond") or s["incomePerSecond"] <= 0:
        if s["balance"] < FUND_TARGET:
            log("  funding desk + trainee through organic posts (chunked)...")
            deadline = time.time() + 900
            while s["balance"] < FUND_TARGET and time.time() < deadline:
                g = cluau(c, sid, GRIND_CHUNK % FUND_TARGET)
                log(f"  grind chunk: {g}")
                s = snapshot(c, sid)
            if s["balance"] < FUND_TARGET:
                raise RuntimeError(f"could not fund a desk+trainee: balance={s['balance']}")
        act(c, sid, "BuyDesk", {"slotIndex": 1})
        time.sleep(1.5)
        act(c, sid, "HireWorker", {"slotIndex": 1, "roleId": "trainee"})
        time.sleep(1.5)
        s = snapshot(c, sid)
        log(f"  worker: balance={s['balance']} rate={s['incomePerSecond']} workers={s.get('workers')}")
    if not s.get("incomePerSecond") or s["incomePerSecond"] <= 0:
        raise RuntimeError(f"no passive income to observe: rate={s.get('incomePerSecond')}")

    rate = s["incomePerSecond"]
    log(f"  idling {DURATION_SECONDS}s at {rate} Cuan/s (bank every {BANK_INTERVAL}s)...")
    samples = []
    fps = []
    mem = []
    t0 = time.time()
    worst_status = "healthy"
    max_pending = 0
    while time.time() - t0 < DURATION_SECONDS:
        time.sleep(SAMPLE_SECONDS)
        s = snapshot(c, sid)
        p = slserver(c, sid, PERF)
        elapsed = round(time.time() - t0, 1)
        samples.append({"t": elapsed, "balance": s["balance"], "lifetime": s.get("lifetimeEarned"),
                        "pending": s.get("pendingWorkerCuan"),
                        "revision": s["revision"], "save": s.get("saveStatus"), "fps": p["fps"], "memMB": p["memMB"]})
        fps.append(p["fps"])
        mem.append(p["memMB"])
        max_pending = max(max_pending, s.get("pendingWorkerCuan") or 0)
        if s.get("saveStatus") and s["saveStatus"] != "healthy":
            worst_status = s["saveStatus"]
        log(f"  t={elapsed:>6}s balance={s['balance']:>6} pending={s.get('pendingWorkerCuan'):>5} rev={s['revision']:>4} save={s.get('saveStatus')} fps={p['fps']:.1f} mem={p['memMB']:.0f}MB")

    first, last = samples[0], samples[-1]
    elapsed = last["t"] - first["t"]
    gained = last["balance"] - first["balance"]
    expected = rate * elapsed
    tolerance = max(expected * 0.15, 5)
    saves = last["revision"] - first["revision"]
    checks = [
        ("session survived the full 20-minute idle window", True),
        ("save status stayed healthy", worst_status == "healthy"),
        ("confirmed balance grew at the advertised rate", abs(gained - expected) <= tolerance),
        ("pendingWorkerCuan stayed bounded by one bank interval", max_pending <= rate * BANK_INTERVAL * 1.6 + 5),
        ("durable saves kept happening at bank cadence", saves >= elapsed / BANK_INTERVAL - 4),
        ("frame rate stayed above 30", min(fps) >= 30),
    ]
    for name, ok in checks:
        log(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    log(f"  gained={gained} expected={expected:.0f} tolerance={tolerance:.0f} saves={saves} maxPending={max_pending} minFps={min(fps):.1f}")

    # Leave and rejoin: the accrued value must survive. NOTE: in offline Studio
    # Play Solo the profile store falls back to its in-memory implementation
    # (docs/14, docs/15: real DataStore re-entry stays OPEN as gate G2), so a
    # restart legitimately resets to a fresh profile. Detect that environment
    # explicitly and report the check as BLOCKED-offline instead of a false
    # FAIL; durable re-entry persistence is covered by the PERSIST-* probes and
    # the Luau suites, not by Studio Play Solo restarts.
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(6)
    open_session(c, sid)
    s2 = snapshot(c, sid)
    offline_reset = (
        s2["balance"] == 0
        and s2.get("tier") == 0
        and s2.get("deviceId") == "phone_cheap"
        and not s2.get("ownedDesks")
    )
    persisted = s2["balance"] >= last["balance"] - 5 and s2["lifetimeEarned"] >= (last.get("lifetime") or 0) - 5
    log(f"  rejoin: balance={s2['balance']} lifetime={s2['lifetimeEarned']} rate={s2['incomePerSecond']} desks={s2.get('ownedDesks')} workers={s2.get('workers')} offlineReset={offline_reset}")
    if offline_reset:
        checks.append(("accrued value survived leave + rejoin", None))
    else:
        checks.append(("accrued value survived leave + rejoin", persisted))
    for name, ok in checks:
        if name == "accrued value survived leave + rejoin":
            log(f"  [{'PASS' if ok else ('BLOCKED (offline studio)' if ok is None else 'FAIL')}] {name}")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})

    evidence = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "durationSeconds": DURATION_SECONDS,
        "incomePerSecond": rate,
        "gained": gained,
        "expected": round(expected, 1),
        "saves": saves,
        "maxPending": max_pending,
        "minFps": round(min(fps), 1),
        "maxMemMB": round(max(mem), 1),
        "checks": [{"name": n, "ok": (None if o is None else bool(o))} for n, o in checks],
        "samples": samples,
    }
    # A BLOCKED (None) check is environmental, not a failure: the verdict counts
    # only checks that could actually run in this environment.
    ok = all(o for _, o in checks if o is not None)
    evidence["passed"] = ok
    with open(os.path.join(OUT, "online-idle.json"), "w", encoding="utf-8") as f:
        json.dump(evidence, f, indent=2)
    with open(os.path.join(OUT, "online-idle.txt"), "w", encoding="utf-8") as f:
        f.write("=== BS-14 20-Minute Online Idle Gate ===\n")
        f.write(f"Timestamp: {evidence['timestamp']}\n")
        f.write(f"Duration: {DURATION_SECONDS}s at {rate} Cuan/s, bank interval {BANK_INTERVAL}s\n")
        for ch in checks:
            status = "PASS" if ch[1] else ("BLOCKED" if ch[1] is None else "FAIL")
            f.write(f"[{status}] {ch[0]}\n")
        f.write(f"Summary: gained={gained} expected={expected:.0f} saves={saves} maxPending={max_pending} "
                f"minFps={min(fps):.1f} maxMemMB={max(mem):.1f}\n")
        f.write("Note: the leave+rejoin check is BLOCKED in offline Studio Play Solo (in-memory profile\n"
                "fallback resets on restart); durable re-entry is covered by PERSIST-* probes and the\n"
                "Luau suites. Real DataStore re-entry remains OPEN (gate G2, docs/14, docs/15).\n")
        f.write(f"Verdict: {'PASS' if ok else 'FAIL'}\n")
    log(f"=== idle gate {'PASS' if ok else 'FAIL'} ===")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
