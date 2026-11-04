"""BS-14 RC-1 connected idle gate.

Establishes a real 2-desk / 2-worker profile through the shipped client path
(StudioClientBridge -> NetRouter -> SessionService), then holds ONE connected
session for 20 real minutes, sampling server-built snapshots every 30s.

Produces:
  docs/evidence/bs14-remediation/02-idle-20min-raw.log
  docs/evidence/bs14-remediation/02-idle-20min-metrics.json

Design notes:
- No clock fast-forward: wall clock and server monotonic both recorded.
- BeginMutation refusal is retried with backoff and diagnosed, because the
  previous harness treated a transient lane-busy refusal as fatal.
- Every sample is appended to the raw log immediately, so a crash still
  leaves chronological evidence rather than a rewritten summary.
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
import studio  # noqa: E402
from client import StudioClient  # noqa: E402

OUT_DIR = os.path.join("docs", "evidence", "bs14-remediation")
RAW_LOG = os.path.join(OUT_DIR, "02-idle-20min-raw.log")
METRICS = os.path.join(OUT_DIR, "02-idle-20min-metrics.json")

IDLE_SECONDS = 20 * 60
SAMPLE_SECONDS = 30
EXPECTED_RATE = 3.0

os.makedirs(OUT_DIR, exist_ok=True)
# Opened lazily on the first live log line. A module-level open(..., "w") here
# truncated the committed evidence log on any import, including --self-test,
# which only reads the recorded fixture.
_log_handle = None


def log(msg):
    global _log_handle
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[{stamp}] {msg}"
    print(line, flush=True)
    if _log_handle is None:
        _log_handle = open(RAW_LOG, "w", encoding="utf-8")
    _log_handle.write(line + "\n")
    _log_handle.flush()


class Runner:
    def __init__(self):
        self.client = studio.get_client()
        self.sid = os.environ.get("BUZZER_SID") or studio.get_studio_id()
        if not self.sid:
            raise SystemExit("no Studio instance visible")

    def cluau(self, code):
        res = self.client.call_tool(
            "execute_luau",
            {"studio_id": self.sid, "datamodel_type": "Client", "code": code},
        )
        if isinstance(res, dict) and res.get("isError"):
            raise RuntimeError(res["content"][0]["text"][:400])
        return self._decode(res["content"][0]["text"])

    def sluau(self, code):
        res = self.client.call_tool(
            "execute_luau",
            {"studio_id": self.sid, "datamodel_type": "Server", "code": code},
        )
        if isinstance(res, dict) and res.get("isError"):
            raise RuntimeError(res["content"][0]["text"][:400])
        return self._decode(res["content"][0]["text"])

    @staticmethod
    def _decode(text):
        try:
            return json.loads(text)
        except Exception:
            return text

    def console(self):
        res = self.client.call_tool("get_console_output", {"studio_id": self.sid})
        return res["content"][0]["text"]


BRIDGE = """
local lp = game:GetService('Players').LocalPlayer
local bridge = lp:WaitForChild('PlayerGui'):WaitForChild('BuzzerOSDesktop'):WaitForChild('StudioClientBridge')
local HttpService = game:GetService('HttpService')
local function snap() return bridge:Invoke('GetState').snapshot end
"""

# Server-side truth: read the live session through the router when reachable.
# Guarded with pcall so a shape change degrades to "unavailable" instead of
# aborting the run; the client snapshot is the primary evidence path.
SERVER_SNAP = """
local HttpService = game:GetService('HttpService')
local ok, payload = pcall(function()
  local runtime = shared.BuzzerRuntime
  if runtime == nil then return { error = 'no runtime' } end
  local player = game:GetService('Players'):GetPlayers()[1]
  local record = runtime._router and runtime._router._records[player]
  if record == nil then return { error = 'no session record' } end
  local res = record.session:ReadSnapshot()
  if not res or not res.ok then return { error = tostring(res and res.code) } end
  return res.snapshot
end)
if not ok then return HttpService:JSONEncode({ error = 'server probe failed: ' .. tostring(payload) }) end
return HttpService:JSONEncode(payload)
"""

OPEN_PROMPT = """
local pBridge = game:GetService('ServerScriptService'):WaitForChild('StudioPromptBridge', 5)
if pBridge == nil then return 'MISSING:StudioPromptBridge' end
local player = game:GetService('Players'):GetPlayers()[1]
if player == nil then return 'MISSING:player' end
local prompt = workspace:FindFirstChild('DashboardPrompt', true)
if prompt == nil then
  for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA('ProximityPrompt') then prompt = d break end
  end
end
if prompt == nil then return 'MISSING:DashboardPrompt' end
local ok, r = pcall(function() return pBridge:Invoke(prompt, player) end)
task.wait(2)
return 'invoked-' .. tostring(ok) .. ':' .. tostring(r)
"""


def act(runner, action, payload, predicate, label, attempts=12, settle=0.4):
    """Send one client action; retry transient lane refusals with backoff."""
    refusals = []
    for attempt in range(1, attempts + 1):
        code = BRIDGE + f"""
local payload = HttpService:JSONDecode('{json.dumps(payload)}')
local sent = bridge:Invoke('Action', {{ action = '{action}', payload = payload }})
local st = bridge:Invoke('GetState')
return HttpService:JSONEncode({{
  sent = sent,
  status = st.status,
  lastCode = st.lastResult and st.lastResult.code,
  outcomes = st.snapshot and st.snapshot.recentMutationOutcomes,
}})
"""
        res = runner.cluau(code)
        if res.get("sent"):
            for _ in range(40):
                time.sleep(settle)
                snap = runner.cluau(BRIDGE + "return HttpService:JSONEncode(snap())")
                if predicate(snap):
                    log(f"  [{label}] applied on attempt {attempt}: {json.dumps(snap)[:220]}")
                    return snap
            raise RuntimeError(f"{label}: sent but effect never observed")
        refusals.append(res)
        log(f"  [{label}] BeginMutation refused (attempt {attempt}): {json.dumps(res)[:220]}")
        time.sleep(1.5 * attempt)
    raise RuntimeError(f"{label}: refused {attempts} times; last={json.dumps(refusals[-1])[:400]}")


def grind(runner, budget_posts, min_life=0, min_bal=0, label="grind"):
    """Publish organically, waiting for the reveal gate between posts.

    A post cannot start while the previous one is still revealing (13-18s), so
    polling pendingPost is required; a fixed 2.15s cadence is refused ~90% of
    the time.
    """
    code = BRIDGE + f"""
local templates = {{ 'snack_meme', 'snack_thread', 'snack_honest', 'demo_bit', 'specs_breakdown', 'daily_driver', 'weekend_vlog_text', 'chill_spot_recs', 'local_roundup' }}
local minLife, minBal = {min_life}, {min_bal}
local n, rejected, tries = 0, 0, 0
while n < {budget_posts} do
  local p = snap()
  if p.lifetimeEarned >= minLife and p.balance >= minBal then break end
  tries += 1
  if tries > {budget_posts * 40} then break end
  if p.pendingPost ~= nil then task.wait(1) continue end
  local tpl = templates[(os.clock() * 7) % 9 // 1 + 1]
  n += 1
  if not bridge:Invoke('Action', {{ action = 'PublishOrganic', payload = {{ templateId = tpl }} }}) then
    rejected += 1
    task.wait(1)
  else
    -- wait for this post to settle before the next attempt
    local deadline = os.clock() + 25
    while os.clock() < deadline and snap().pendingPost ~= nil do task.wait(1) end
  end
end
local p = snap()
return HttpService:JSONEncode({{ posts = n, rejected = rejected, balance = p.balance, lifetime = p.lifetimeEarned, claims = p.completedMissions, tier = p.tier }})
"""
    res = runner.cluau(code)
    log(f"  [{label}] {json.dumps(res)}")
    return res


def run_mission(runner, mission_id, templates):
    code = BRIDGE + f"""
local mid = '{mission_id}'
local tpls = HttpService:JSONDecode('{json.dumps(templates)}')
if snap().activeMission == nil then
  if not bridge:Invoke('Action', {{ action = 'AcceptMission', payload = {{ missionId = mid }} }}) then return 'ACCEPT-BUSY' end
  task.wait(1)
end
local p = snap()
local runId = p.activeMission and p.activeMission.runId
if runId == nil then return HttpService:JSONEncode({{ err = 'no runId' }}) end
for _, tpl in ipairs(tpls) do
  for at = 1, 8 do
    if bridge:Invoke('Action', {{ action = 'PublishPost', payload = {{ runId = runId, templateId = tpl }} }}) then break end
    task.wait(1.2)
  end
  task.wait(2.2)
end
for at = 1, 8 do
  if bridge:Invoke('Action', {{ action = 'ClaimMission', payload = {{ runId = runId }} }}) then break end
  task.wait(1.2)
end
local deadline = os.clock() + 12
while os.clock() < deadline and snap().activeMission ~= nil do task.wait(0.5) end
local q = snap()
return HttpService:JSONEncode({{ mission = mid, balance = q.balance, lifetime = q.lifetimeEarned, claims = q.completedMissions, tier = q.tier }})
"""
    res = runner.cluau(code)
    log(f"  [mission {mission_id}] {json.dumps(res)}")
    return res


def sample(runner, label, extra=None):
    client_snap = runner.cluau(BRIDGE + "return HttpService:JSONEncode(snap())")
    try:
        server_snap = runner.sluau(SERVER_SNAP)
    except Exception as exc:  # server read is supporting evidence, not the gate
        server_snap = {"error": str(exc)[:200]}
    record = {
        "label": label,
        "wall_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "client_snapshot": client_snap,
        "server_snapshot": server_snap,
    }
    if extra:
        record.update(extra)
    log(f"  sample {label}: {json.dumps(record)[:600]}")
    return record


def attribute_income(baseline, final):
    """Split an idle window's earnings into their actual sources.

    The wallet delta cannot be read as worker income: an organic post pending
    at the start credits the wallet when it settles mid-window, and
    `pendingWorkerCuan` is worker income that has accrued but not yet been
    banked. Both must be separated or the worker check silently absorbs them.

    `lifetimeEarned` is the spend-immune total-earned measure, so worker
    attribution is derived from it; the balance delta is reported alongside
    because it also falls by any purchase made during the window.

    Returns plain ints/floats so the result is directly JSON-serialisable.
    """
    base_pending_post = baseline.get("pendingPost") or {}
    final_pending_post = final.get("pendingPost") or {}
    base_worker_pending = baseline.get("pendingWorkerCuan") or 0
    final_worker_pending = final.get("pendingWorkerCuan") or 0

    balance_delta = round(final.get("balance", 0) - baseline.get("balance", 0), 3)
    lifetime_delta = round(final.get("lifetimeEarned", 0) - baseline.get("lifetimeEarned", 0), 3)

    # Organic settlement: a post pending at baseline that is gone at the end.
    organic_settled = 0
    organic_source = None
    if base_pending_post and not final_pending_post:
        organic_settled = base_pending_post.get("organicCuan") or 0
        organic_source = {
            "postId": base_pending_post.get("postId"),
            "templateId": base_pending_post.get("templateId"),
            "organicCuan": organic_settled,
            "settleAt": base_pending_post.get("settleAt"),
            "baseline_serverTime": baseline.get("serverTime"),
        }

    banked_worker = lifetime_delta - organic_settled
    unbanked_worker = final_worker_pending - base_worker_pending
    worker_total = banked_worker + unbanked_worker

    elapsed = (final.get("serverTime") or 0) - (baseline.get("serverTime") or 0)

    return {
        "balance_delta": balance_delta,
        "lifetime_delta": lifetime_delta,
        "organic_post_settled": organic_source,
        "organic_post_cuan": organic_settled,
        "banked_worker_income": banked_worker,
        "unbanked_worker_income": unbanked_worker,
        "worker_income_total": worker_total,
        "server_elapsed_seconds": round(elapsed, 6),
    }


def expected_worker_income(elapsed_seconds, rate):
    """Authoritative expectation from serverTime, not harness wall clock."""
    return round(elapsed_seconds * rate, 3)


def detect_mutations(baseline, final):
    """Report anything that changed state during an 'idle' window.

    An idle gate only proves the accrual path if nothing else moved: a mission
    claimed, a post published, a device bought or a worker hired during the
    window contaminates the income attribution.

    Two transitions are expected and are NOT mutations:
    - `pendingWorkerCuan` rising (accrued-but-unbanked worker income, already
      attributed separately as `unbanked_worker_income`);
    - the baseline pending post leaving `pendingPost` and joining `ownPosts`
      (that is the settlement being attributed as `organic_post_cuan`).

    A post that appears in `ownPosts` without having been pending at baseline
    WAS published during the window and is reported.
    """
    findings = []

    def compare(field, label):
        before, after = baseline.get(field), final.get(field)
        if before != after:
            findings.append({"field": field, "label": label, "before": before, "after": after})

    compare("completedMissions", "missions completed")
    compare("activeMission", "active mission")
    compare("ownedDesks", "owned desks")
    compare("workers", "hired workers")
    compare("deviceId", "owned device")
    compare("tier", "tier")
    compare("incomePerSecond", "income rate")

    base_pending_id = (baseline.get("pendingPost") or {}).get("postId")
    base_post_ids = {p.get("postId") for p in (baseline.get("ownPosts") or [])}
    base_post_ids.add(base_pending_id)  # the settling post is expected in ownPosts
    final_posts = [p.get("postId") for p in (final.get("ownPosts") or [])]
    new_posts = [p for p in final_posts if p not in base_post_ids]
    if new_posts:
        findings.append({
            "field": "ownPosts",
            "label": "posts published during window (not pending at baseline)",
            "new_posts": new_posts,
        })

    if final.get("pendingPost"):
        findings.append({"field": "pendingPost", "label": "post still pending at end", "after": final.get("pendingPost")})

    return findings


def self_test():
    """Run income attribution against the recorded fixture. No Studio needed.

    Guards the arithmetic that the director review corrected: the wallet delta
    is NOT worker income, and the organic post settled mid-window must be
    attributed separately.
    """
    if not os.path.exists(METRICS):
        raise SystemExit(f"fixture missing: {METRICS} (run the idle gate first)")
    with open(METRICS, encoding="utf-8") as handle:
        fixture = json.load(handle)

    base, final = fixture["baseline"], fixture["final"]
    got = attribute_income(base, final)

    checks = [
        ("balance delta is not worker income", got["balance_delta"] == 3615 and got["banked_worker_income"] == 3578),
        ("organic post settlement is attributed", got["organic_post_cuan"] == 37),
        ("unbanked worker income is separated", got["unbanked_worker_income"] == 21),
        ("total worker income excludes organic", got["worker_income_total"] == 3599),
        ("serverTime is the elapsed authority", abs(got["server_elapsed_seconds"] - 1199.81865) < 0.001),
        ("expected uses serverTime not wall clock", expected_worker_income(got["server_elapsed_seconds"], 3.0) == 3599.456),
        ("worker total matches expectation within 1 Cuan", abs(got["worker_income_total"] - 3599.456) <= 1.0),
        ("idle window had no contaminating mutations", detect_mutations(base, final) == []),
    ]

    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    if failed:
        raise SystemExit(f"attribution self-test failed: {failed}")
    print(f"attribution self-test: {len(checks)}/{len(checks)} passed against {os.path.basename(METRICS)}")


def main():
    runner = Runner()
    log(f"=== BS-14 RC-1 connected idle gate ===")
    log(f"studio={runner.sid} idle_seconds={IDLE_SECONDS} sample_seconds={SAMPLE_SECONDS}")

    log("[1] restart Play Solo for a clean session")
    runner.client.call_tool("start_stop_play", {"studio_id": runner.sid, "is_start": False})
    time.sleep(3)
    runner.client.call_tool("start_stop_play", {"studio_id": runner.sid, "is_start": True})
    time.sleep(12)

    ready = None
    for attempt in range(24):
        try:
            # Before the dashboard opens there is no snapshot; probe the bridge only.
            ready = runner.cluau(
                BRIDGE + "return HttpService:JSONEncode({ bridge = true, visible = bridge:Invoke('IsDesktopVisible'), status = bridge:Invoke('GetState').status })"
            )
            if isinstance(ready, dict):
                break
        except Exception as exc:
            log(f"  wait {attempt}: {str(exc)[:160]}")
        time.sleep(3)
    if not isinstance(ready, dict):
        raise SystemExit("client bridge never became ready")
    log(f"  client ready: {json.dumps(ready)}")

    log("[2] open dashboard through the real proximity prompt")
    opened = str(runner.sluau(OPEN_PROMPT))
    log("  " + opened)
    if "MISSING:" in opened:
        raise SystemExit(f"place is not the gameplay build: {opened}")
    time.sleep(1.5)
    visible = runner.cluau(BRIDGE + "return bridge:Invoke('IsDesktopVisible')")
    log(f"  desktop visible: {visible}")
    if not visible:
        raise SystemExit("dashboard did not open")

    for attempt in range(20):
        has_snapshot = runner.cluau(
            BRIDGE + "local st = bridge:Invoke('GetState') return st.snapshot ~= nil"
        )
        if has_snapshot is True:
            log(f"  snapshot available after {attempt} polls")
            break
        time.sleep(1)
    else:
        raise SystemExit("no server snapshot after dashboard open")

    log("[3] tier-1 mission ladder")
    ladder = [
        ("food_stall_launch", ["meal_meme", "queue_thread", "late_night_quip"]),
        ("fictional_gadget", ["demo_joke", "collector_thread", "setup_thread"]),
        ("neon_market", ["event_thread", "price_list", "food_map"]),
        ("brand_remix", ["comparison_thread", "nostalgia_story", "review_thread"]),
    ]
    for mission_id, templates in ladder:
        run_mission(runner, mission_id, templates)

    state = runner.cluau(BRIDGE + "return HttpService:JSONEncode(snap())")
    log(f"  post-ladder state: {json.dumps(state)[:300]}")

    log("[4] device ladder in catalog order: phone_fast -> pc_rumah, then desk 1 + trainee 1")
    state = runner.cluau(BRIDGE + "return HttpService:JSONEncode(snap())")
    log(f"  balance before purchases: {state.get('balance')}")
    # Catalog order is enforced client and server side: only the exact next
    # device is purchasable, so phone_fast must precede pc_rumah.
    act(runner, "BuyDevice", {"deviceId": "phone_fast"}, lambda s: s.get("deviceId") == "phone_fast", "phone_fast")
    act(runner, "BuyDevice", {"deviceId": "pc_rumah"}, lambda s: s.get("deviceId") == "pc_rumah", "pc_rumah")
    act(runner, "BuyDesk", {"slotIndex": 1}, lambda s: 1 in (s.get("ownedDesks") or []), "desk1")
    for _ in range(30):
        state = grind(runner, 12, 0, 500, "fund-hire1")
        if state.get("balance", 0) >= 500:
            break
    act(runner, "HireWorker", {"slotIndex": 1, "roleId": "trainee"}, lambda s: len(s.get("workers") or []) >= 1, "hire1")

    log("[5] grind to tier 2 funding")
    for _ in range(40):
        state = grind(runner, 12, 1600, 1000, "fund-tier2")
        if state.get("lifetime", 0) >= 1600 and state.get("balance", 0) >= 1000:
            break
    log(f"  pre-desk2 state: {json.dumps(state)[:300]}")

    log("[6] desk 2 + trainee 2")
    act(runner, "BuyDesk", {"slotIndex": 2}, lambda s: 2 in (s.get("ownedDesks") or []), "desk2")
    act(runner, "HireWorker", {"slotIndex": 2, "roleId": "trainee"}, lambda s: len(s.get("workers") or []) >= 2, "hire2")

    baseline = sample(runner, "baseline")
    rate = (baseline.get("client_snapshot") or {}).get("incomePerSecond")
    log(f"  baseline rate={rate}")
    if rate != EXPECTED_RATE:
        raise SystemExit(f"rate is {rate}, expected {EXPECTED_RATE}; not a valid idle baseline")

    # Clean baseline (option A): a post pending at the start would settle into
    # the wallet mid-window and contaminate the worker attribution, so wait it
    # out before measuring. Only the baseline post is waited on; anything that
    # appears during the window is reported by detect_mutations.
    base_snap = baseline.get("client_snapshot") or {}
    for attempt in range(40):
        pending = base_snap.get("pendingPost")
        if not pending:
            break
        log(f"  waiting for baseline post {pending.get('postId')} to settle ({pending.get('organicCuan')} Cuan) before measuring")
        time.sleep(2)
        base_snap = runner.cluau(BRIDGE + "return HttpService:JSONEncode(snap())")
    if (base_snap.get("pendingPost") or None):
        raise SystemExit("baseline post never settled; rerun for a clean idle window")
    if base_snap != (baseline.get("client_snapshot") or {}):
        baseline["client_snapshot"] = base_snap
        samples[0] = baseline
        log(f"  clean baseline after settle: balance={base_snap.get('balance')} lifetime={base_snap.get('lifetimeEarned')} pendingWorkerCuan={base_snap.get('pendingWorkerCuan')}")

    log("[7] begin 20 real minutes of connected idle")
    started = time.time()
    samples = [baseline]
    index = 0
    while time.time() - started < IDLE_SECONDS:
        target = started + (index + 1) * SAMPLE_SECONDS
        sleep_for = target - time.time()
        if sleep_for > 0:
            time.sleep(sleep_for)
        index += 1
        elapsed = round(time.time() - started, 1)
        samples.append(sample(runner, f"t+{elapsed}s", {"elapsed_seconds": elapsed}))
        if index % 10 == 0:
            console_tail = runner.console()[-1500:]
            log(f"  console tail @ {elapsed}s: {console_tail!r}")

    log("[8] stop Play Solo and record teardown")
    teardown = runner.client.call_tool("start_stop_play", {"studio_id": runner.sid, "is_start": False})
    log(f"  stop result: {str(teardown)[:200]}")

    final = samples[-1].get("client_snapshot") or {}
    base = baseline.get("client_snapshot") or {}
    deltas = []
    previous = base.get("lifetimeEarned", 0)
    for rec in samples[1:]:
        snap = rec.get("client_snapshot") or {}
        current = snap.get("lifetimeEarned", 0)
        deltas.append(round(current - previous, 3))
        previous = current

    # Income attribution: never read the wallet delta as worker earnings.
    attribution = attribute_income(base, final)
    mutations = detect_mutations(base, final)
    server_elapsed = attribution["server_elapsed_seconds"]
    expected_worker = expected_worker_income(server_elapsed, EXPECTED_RATE)

    metrics = {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "studio_id": runner.sid,
        "idle_seconds_requested": IDLE_SECONDS,
        "idle_seconds_observed": round(time.time() - started, 1),
        "server_elapsed_seconds": server_elapsed,
        "sample_interval_seconds": SAMPLE_SECONDS,
        "sample_count": len(samples),
        "expected_rate_per_second": EXPECTED_RATE,
        "expected_gross": EXPECTED_RATE * IDLE_SECONDS,
        "expected_worker_income": expected_worker,
        "baseline": base,
        "final": final,
        "observed_lifetime_delta": attribution["lifetime_delta"],
        "observed_balance_delta": attribution["balance_delta"],
        "income_attribution": attribution,
        "mutations_during_window": mutations,
        "sample_lifetime_deltas": deltas,
        "deltas_out_of_band": [d for d in deltas if d < 0 or d > 100],
        "revision_baseline": base.get("revision"),
        "revision_final": final.get("revision"),
        "revision_increments": (final.get("revision") or 0) - (base.get("revision") or 0),
        "final_save_status": final.get("saveStatus"),
        "samples": samples,
    }
    with open(METRICS, "w", encoding="utf-8") as handle:
        json.dump(metrics, handle, indent=2)
    log(f"[9] metrics written to {METRICS}")
    log(f"  server elapsed {server_elapsed}s (harness wall {metrics['idle_seconds_observed']}s)")
    log(f"  balance delta {attribution['balance_delta']} = organic {attribution['organic_post_cuan']} + banked worker {attribution['banked_worker_income']}")
    log(f"  worker income total {attribution['worker_income_total']} (unbanked {attribution['unbanked_worker_income']}) vs expected {expected_worker}")
    log(f"  mutations during window: {mutations}")
    log("=== idle gate complete ===")
    _log_handle.close()


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        main()
