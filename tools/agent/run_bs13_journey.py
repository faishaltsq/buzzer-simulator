"""BS-13 gameplay journey: drives the LIVE runtime session end-to-end through
the real client path (StudioClientBridge Action -> NetRouter -> session),
captures genuine Studio evidence per docs/evidence/bs13/README.md."""
import base64
import json
import os
import sys
import time

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
import studio  # noqa: E402
from client import StudioClient  # noqa: E402

OUT = "docs/evidence/bs13"
os.makedirs(OUT, exist_ok=True)
EVIDENCE = {}
WORKER_BANK_INTERVAL = 30


def log(msg):
    print(msg, flush=True)


def cli():
    c = studio.get_client()
    sid = os.environ.get("BUZZER_SID") or studio.get_studio_id()
    return c, sid


def cluau(c, sid, code, timeout_ms=120000):
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
local okR, r = pcall(function() return pBridge:Invoke(prompt, player) end)
task.wait(2)
return 'invoked-' .. tostring(okR) .. ':' .. tostring(r)
"""

COUNT_PARTS = """
local n = 0
for _, d in ipairs(workspace:GetDescendants()) do
  if d:IsA('BasePart') then n += 1 end
end
return n
"""

FIND_INSTANCES = """
local HttpService = game:GetService('HttpService')
local found = { WorkerDesk2 = 0, Trainee1 = 0, Trainee2 = 0, WorkerDesk1 = 0, PCRumah = 0 }
for _, d in ipairs(workspace:GetDescendants()) do
  if found[d.Name] ~= nil then found[d.Name] += 1 end
end
return HttpService:JSONEncode(found)
"""


def wait_world(c, sid, name, want, tries=30, delay=1.0):
    got = {}
    for i in range(tries):
        got = slserver(c, sid, FIND_INSTANCES)
        if not isinstance(got, dict):
            got = json.loads(got)
        if got.get(name, 0) >= want:
            return got
        time.sleep(delay)
    return got


def act(c, sid, action, payload, check, tries=40, delay=0.35, expect_ok=True):
    """Send one real client action, poll until `check(snapshot)` holds."""
    code = BRIDGE + f"""
local r = bridge:Invoke('Action', {{ action = '{action}', payload = HttpService:JSONDecode('{json.dumps(payload)}') }})
return HttpService:JSONEncode({{ sent = r }})
"""
    sent = json.loads(c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Client", "code": code})["content"][0]["text"])
    if not sent.get("sent"):
        raise RuntimeError(f"{action}: BeginMutation refused (busy/blocked): {sent}")
    for _ in range(tries):
        s = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode(snap())")
        if check(s):
            return s
        time.sleep(delay)
    dump = cluau(c, sid, BRIDGE + """
local st = bridge:Invoke('GetState')
return HttpService:JSONEncode({ status = st.status, recent = st.snapshot and st.snapshot.recentMutationOutcomes })
""")
    raise RuntimeError(f"{action}: effect not observed. sent={sent} dump={json.dumps(dump)[:600]}")


def grind_chunk(c, sid, budget_posts, min_life=0, min_bal=0):
    """Run up to budget_posts organic publishes in ONE client-loop call."""
    code = BRIDGE + f"""
local templates = {{ 'snack_meme', 'snack_thread', 'snack_honest', 'demo_bit', 'specs_breakdown', 'daily_driver', 'weekend_vlog_text', 'chill_spot_recs', 'local_roundup' }}
local minLife = {min_life}
local minBal = {min_bal}
local n = 0
local rejected = 0
while n < {budget_posts} do
  local p = snap()
  if p.lifetimeEarned >= minLife and p.balance >= minBal then break end
  local tpl = templates[(os.clock() * 7) % 9 // 1 + 1]
  n += 1
  local ok = bridge:Invoke('Action', {{ action = 'PublishOrganic', payload = {{ templateId = tpl }} }})
  if not ok then rejected += 1 task.wait(1) end
  task.wait(2.15)
end
local p = snap()
return HttpService:JSONEncode({{ posts = n, rejected = rejected, balance = p.balance, lifetime = p.lifetimeEarned, claims = p.completedMissions, tier = p.tier }})
"""
    res = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Client", "code": code})
    if isinstance(res, dict) and res.get("isError"):
        raise RuntimeError(res["content"][0]["text"][:300])
    return json.loads(res["content"][0]["text"])


def purchase(c, sid, action, payload, check, label):
    s = act(c, sid, action, payload, check)
    log(f"  [{label}] ok: {json.dumps(s)}")
    EVIDENCE[label] = s
    return s


def cap(c, capture_id, out_name, cam=None, look=None):
    out_path = os.path.join(OUT, out_name)
    args = {"studio_id": sid_global[0], "capture_id": capture_id}
    if cam:
        args["camera_position"] = cam
    if look:
        args["look_at_position"] = look
    try:
        res = c.call_tool("screen_capture", args)
        for item in res.get("content", []):
            if item.get("type") == "image":
                with open(out_path, "wb") as f:
                    f.write(base64.b64decode(item["data"]))
                log(f"  [cap] {out_name}")
                return True
        log(f"  [cap-FAIL] {out_name}: {str(res)[:150]}")
        return False
    except Exception as e:
        log(f"  [cap-ERROR] {out_name}: {e}")
        return False


sid_global = [None]


def maximize_window():
    try:
        import win32con
        import win32gui
        hwnd = None

        def enum_cb(h, _):
            nonlocal hwnd
            t = win32gui.GetWindowText(h)
            if "Roblox Studio" in t and "BuzzerSimulator" in t:
                hwnd = hwnd or h
        win32gui.EnumWindows(enum_cb, None)
        if hwnd:
            win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
            time.sleep(1.5)
            return True
    except Exception as e:
        log(f"  maximize skipped: {e}")
    return False


def main():
    c, sid = cli()
    sid_global[0] = sid
    log(f"Studio: {sid}")
    maximize_window()

    log("[1] (Re)start Play Solo")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(3)
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(12)

    # Wait for client bootstrap + bridge
    for i in range(24):
        try:
            vis = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode({ s = bridge:Invoke('IsDesktopVisible') , t = snap().tier, b = snap().balance })")
            log(f"  client up: {vis}")
            EVIDENCE["fresh"] = vis
            break
        except Exception as e:
            log(f"  wait {i}: {str(e)[:90]}")
            time.sleep(3)
    else:
        raise SystemExit("client never became ready")

    log("[2] Open dashboard via real prompt")
    log("  " + slserver(c, sid, OPEN_PROMPT))
    time.sleep(1.5)
    vis = cluau(c, sid, BRIDGE + "return bridge:Invoke('IsDesktopVisible')")
    log(f"  desktop visible: {vis}")
    if not vis:
        raise SystemExit("dashboard did not open")

    # ---- ladder: 3 missions -> tier 1 ----
    MISSIONS = [
        ("food_stall_launch", ["meal_meme", "queue_thread", "late_night_quip"]),
        ("fictional_gadget", ["demo_joke", "collector_thread", "setup_thread"]),
        ("neon_market", ["event_thread", "price_list", "food_map"]),
    ]
    log("[3] Mission claims x3 (tier 1 ladder)")
    for mid, tpls in MISSIONS:
        code = BRIDGE + f"""
local mid = '{mid}'
local tpls = HttpService:JSONDecode('{json.dumps(tpls)}')  -- 2s publish cooldown enforced server-side
if snap().activeMission == nil then
  if not bridge:Invoke('Action', {{ action = 'AcceptMission', payload = {{ missionId = mid }} }}) then return 'ACCEPT-BUSY' end
  task.wait(1)
end
local p = snap()
local runId = p.activeMission and p.activeMission.runId
if runId == nil then return HttpService:JSONEncode({{ err = 'no runId', snap = p }}) end
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
while os.clock() < deadline do
  local q = snap()
  if q.activeMission == nil and q.balance >= 0 then break end
  task.wait(0.5)
end
local q = snap()
return HttpService:JSONEncode({{ mission = mid, balance = q.balance, lifetime = q.lifetimeEarned, claims = q.completedMissions, active = q.activeMission ~= nil }})
"""
        res = cluau(c, sid, code)
        log(f"  {res}")
        if isinstance(res, dict) and res.get("claims") is not None:
            EVIDENCE[f"mission_{mid}"] = res

    s = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode(snap())")
    EVIDENCE["after_tier1"] = {k: s.get(k) for k in ("balance", "lifetimeEarned", "completedMissions", "tier")}
    log(f"  state: {EVIDENCE['after_tier1']}")

    # ---- brand_remix (4th claim) ----
    log("[4] brand_remix claim")
    code = BRIDGE + """
if snap().activeMission ~= nil then return 'BUSY' end
if not bridge:Invoke('Action', { action = 'AcceptMission', payload = { missionId = 'brand_remix' } }) then return 'ACCEPT-BUSY' end
task.wait(1.2)
local runId = snap().activeMission.runId
for _, tpl in ipairs({ 'comparison_thread', 'nostalgia_story', 'review_thread' }) do
  for at = 1, 8 do
    if bridge:Invoke('Action', { action = 'PublishPost', payload = { runId = runId, templateId = tpl } }) then break end
    task.wait(1.2)
  end
  task.wait(2.2)
end
for at = 1, 8 do
  if bridge:Invoke('Action', { action = 'ClaimMission', payload = { runId = runId } }) then break end
  task.wait(1.2)
end
local deadline = os.clock() + 12
while os.clock() < deadline and snap().activeMission ~= nil do task.wait(0.5) end
local q = snap()
return HttpService:JSONEncode({ balance = q.balance, lifetime = q.lifetimeEarned, claims = q.completedMissions })
"""
    EVIDENCE["brand_remix"] = cluau(c, sid, code)
    log(f"  {EVIDENCE['brand_remix']}")

    # ---- devices + desk-1 ladder with funded mini-grinds ----
    def mini_grind(min_life, min_bal, label, max_chunks=30):
        total = 0
        r = None
        for chunk in range(max_chunks):
            r = grind_chunk(c, sid, 12, min_life, min_bal)
            total += r.get("posts", 0) or 0
            log(f"  [{label}] chunk {chunk}: {json.dumps(r)}")
            if r.get("lifetime", 0) >= min_life and r.get("balance", 0) >= min_bal:
                break
        return r, total

    log("[5] Mini-grind funds for phone_fast")
    mini_grind(0, 130, "fund-phone", max_chunks=8)
    log("[5a] BuyDevice phone_fast")
    purchase(c, sid, "BuyDevice", {"deviceId": "phone_fast"},
             lambda s: s.get("deviceId") == "phone_fast", "buy_phone_fast")

    log("[6] Mini-grind funds for PC + desk 1 + trainee 1 (target 950)")
    mini_grind(0, 950, "fund-pc")
    log("[6a] BuyDevice pc_rumah")
    purchase(c, sid, "BuyDevice", {"deviceId": "pc_rumah"},
             lambda s: s.get("deviceId") == "pc_rumah", "buy_pc")

    log("[6b] BuyDesk slot 1")
    purchase(c, sid, "BuyDesk", {"slotIndex": 1},
             lambda s: any(d == 1 for d in (s.get("ownedDesks") or [])), "buy_desk1")

    log("[6c] HireWorker slot 1")
    purchase(c, sid, "HireWorker", {"slotIndex": 1, "roleId": "trainee"},
             lambda s: len(s.get("workers") or []) >= 1, "hire_worker1")

    # ---- organic grind to tier2 + funds (trainee 1 accrues meanwhile) ----
    log("[7] Organic grind chunks (target lifetime>=1700, balance>=1400)")
    r, total_posts = mini_grind(1700, 1400, "main-grind")

    EVIDENCE["grind"] = {"posts": total_posts, **{k: v for k, v in r.items() if k != "posts"}}
    st = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode(snap())")
    EVIDENCE["grind_final"] = {k: st.get(k) for k in ("balance", "lifetimeEarned", "completedMissions", "tier", "deviceId")}
    log(f"  final: {EVIDENCE['grind_final']}")
    assert st.get("tier", 0) >= 2, f"tier 2 not reached: {EVIDENCE['grind_final']}"

    # ---- EVIDENCE 10: tier 2 unlock (Workers tab chapter steps) ----
    log("[8] Capture 10-tier2-unlock.png (Workers tab)")
    cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return true")
    time.sleep(1.5)
    cap(c, "cap-tier2", "10-tier2-unlock.png")

    # ---- desk 2, before hire ----
    log("[9] BuyDesk slot 2")
    purchase(c, sid, "BuyDesk", {"slotIndex": 2},
             lambda s: any(d == 2 for d in (s.get("ownedDesks") or [])), "buy_desk2")
    time.sleep(1.0)
    cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return true")
    time.sleep(1.2)
    cap(c, "cap-desk2-before-hire", "20-desk2-before-hire.png")

    log("[10] HireWorker slot 2")
    purchase(c, sid, "HireWorker", {"slotIndex": 2, "roleId": "trainee"},
             lambda s: len(s.get("workers") or []) >= 2, "hire_worker2")

    # rate check from confirmed projection
    s = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode({ ips = snap().incomePerSecond, workers = #snap().workers })")
    log(f"  incomePerSecond projection: {s}")
    assert s.get("ips") in (3, 3.0), f"rate != 3.0: {s}"

    # world mounts
    log("[11] World verification (desk 2 + both trainees)")
    w = wait_world(c, sid, "Trainee2", 1)
    log(f"  world: {json.dumps(w)}")
    EVIDENCE["world"] = w
    assert w.get("WorkerDesk2", 0) >= 1 and w.get("Trainee1", 0) >= 1 and w.get("Trainee2", 0) >= 1

    # ---- world captures ----
    log("[12] World captures (dashboard closed)")
    cluau(c, sid, BRIDGE + "bridge:Invoke('Close') return true")
    time.sleep(2)
    # frame both trainee seats via desk positions from the live world
    pos = json.loads(slserver(c, sid, """
local HttpService = game:GetService('HttpService')
local d1, d2 = workspace:FindFirstChild('WorkerDesk1', true), workspace:FindFirstChild('WorkerDesk2', true)
local p1 = d1 and d1:GetPivot().Position or Vector3.new(0, 3, 0)
local p2 = d2 and d2:GetPivot().Position or p1
return HttpService:JSONEncode({ c = { (p1 + p2).X / 2, (p1 + p2).Y + 2, (p1 + p2).Z / 2 }, d1 = { p1.X, p1.Y, p1.Z }, d2 = { p2.X, p2.Y, p2.Z } })
"""))
    cx = (pos["d1"][0] + pos["d2"][0]) / 2
    cz = (pos["d1"][2] + pos["d2"][2]) / 2
    cap(c, "cap-both-trainees", "30-both-trainees.png",
        cam=[cx + 6, pos["c"][1] + 5, cz + 8], look=pos["c"])
    cap(c, "cap-full-room", "40-full-studio-room.png",
        cam=[cx + 10, pos["c"][1] + 9, cz + 13], look=pos["c"])
    cap(c, "cap-alt-camera", "95-alt-camera.png",
        cam=[cx - 8, pos["c"][1] + 4, cz - 9], look=pos["c"])

    # ---- reopen dashboard: 50/60/80 ----
    log("[13] Workers captures 2/2, rate, chapter complete")
    slserver(c, sid, OPEN_PROMPT)
    time.sleep(2)
    cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return true")
    time.sleep(1.5)
    cap(c, "cap-workers-2of2", "50-workers-2of2.png")

    # 60: rate line (+3.0 Cuan/s) — capture the workers view with banked balance fresh
    # wait one full bank so balance reflects 90 Cuan at 3.0/s
    log("[14] 30s bank -> +90")
    s0 = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode({ b = snap().balance, pend = snap().pendingWorkerCuan })")
    log(f"  before bank: {s0}")
    EVIDENCE["pre_bank"] = s0
    t_start = time.time()
    pend_peak = 0
    while time.time() - t_start < WORKER_BANK_INTERVAL + 12:
        time.sleep(2)
        cur = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode({ b = snap().balance, pend = snap().pendingWorkerCuan })")
        pend_peak = max(pend_peak, cur.get("pend", 0) or 0)
        if cur.get("b", 0) - s0.get("b", 0) >= 90:
            break
    EVIDENCE["bank30"] = {"before_balance": s0.get("b"), "pending_peak": pend_peak,
                          "after_balance": cur.get("b"), "delta": (cur.get("b", 0) - s0.get("b", 0))}
    log(f"  bank: {EVIDENCE['bank30']}")
    cap(c, "cap-rate", "60-rate-3-point-0.png")
    cap(c, "cap-pending-vs-spendable", "70-pending-vs-spendable.png")

    cap(c, "cap-chapter-complete", "80-chapter-complete.png")

    # ---- mobile portrait: narrow real viewport ----
    log("[15] Mobile portrait (real narrow viewport)")
    try:
        import win32con
        import win32gui
        hwnd = win32gui.FindWindow(None, None)
        hwnd = None
        def enum_cb(h, _):
            nonlocal hwnd
            t = win32gui.GetWindowText(h)
            if "Roblox Studio" in t and "BuzzerSimulator" in t:
                hwnd = hwnd or h
        win32gui.EnumWindows(enum_cb, None)
        if hwnd:
            win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
            old = win32gui.GetWindowRect(hwnd)
            win32gui.MoveWindow(hwnd, old[0], old[1], 520, 940, True)
            time.sleep(2.5)
            # dashboard still open? if closed, reopen
            vis = cluau(c, sid, BRIDGE + "return bridge:Invoke('IsDesktopVisible')")
            if not vis:
                slserver(c, sid, OPEN_PROMPT)
                time.sleep(2)
            cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Home') return true")
            time.sleep(1.2)
            cap(c, "cap-mobile", "90-mobile-portrait.png")
            # restore
            win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
            time.sleep(1.5)
        else:
            log("  [mobile-FAIL] no window handle")
    except Exception as e:
        log(f"  [mobile-ERROR] {e}")

    # ---- part budget check ----
    log("[16] Part budget check")
    parts = int(slserver(c, sid, COUNT_PARTS))
    EVIDENCE["parts"] = parts
    log(f"  live parts: {parts} (budget 350)")
    cap(c, "cap-part-proof", "99-part-count-context.png")

    # ---- persistence gate (expected BLOCKED offline) ----
    log("[17] Persistence gate (offline studio, in-memory store)")
    cluau(c, sid, BRIDGE + "bridge:Invoke('Close') return true")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(5)
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(12)
    try:
        pj = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode({ vis = bridge:Invoke('IsDesktopVisible'), s = snap() })")
        EVIDENCE["rejoin"] = {"expected_gate": "G2 BLOCKED (offline studioDEV fallback in-memory)",
                              "snapshot": {k: pj.get("s", {}).get(k) for k in ("balance", "tier", "deviceId")}}
        log(f"  rejoin: {EVIDENCE['rejoin']['snapshot']}")
        slserver(c, sid, OPEN_PROMPT)
        time.sleep(2)
        cap(c, "cap-rejoin", "97-rejoin-fresh-session.png")
    except Exception as e:
        EVIDENCE["rejoin"] = {"expected_gate": "G2 BLOCKED", "error": str(e)[:200]}
        log(f"  rejoin note: {e}")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(3)

    with open(os.path.join(OUT, "journey-evidence.json"), "w", encoding="utf-8") as f:
        json.dump(EVIDENCE, f, indent=2, default=str)
    log("=== journey complete; journey-evidence.json saved ===")


if __name__ == "__main__":
    main()
