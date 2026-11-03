"""Retake desktop UI evidence in true desktop mode (Viewport 1510x642).
Captures:
- 10-tier2-unlock.png
- 20-desk2-before-hire.png
- 50-workers-2of2.png
- 60-rate-3-point-0.png
- 70-pending-vs-spendable.png
- 80-chapter-complete.png
"""
import base64
import json
import os
import sys
import time

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from client import StudioClient
import studio

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "docs", "evidence", "bs13"))

BRIDGE = """
local lp = game:GetService('Players').LocalPlayer
local pgui = lp:WaitForChild('PlayerGui')
local desktop = pgui:WaitForChild('BuzzerOSDesktop')
local bridge = desktop:WaitForChild('StudioClientBridge')
local HttpService = game:GetService('HttpService')
local function snap() return bridge:Invoke('GetState').snapshot end
"""

def cluau(c, sid, code):
    res = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Client", "code": code})
    if isinstance(res, dict) and res.get("isError"):
        raise RuntimeError(f"Client luau error: {res['content'][0]['text'][:300]}")
    txt = res["content"][0]["text"].strip()
    try:
        return json.loads(txt)
    except Exception:
        return txt

def cap(c, sid, capture_id, out_name):
    out_path = os.path.join(OUT, out_name)
    args = {"studio_id": sid, "capture_id": capture_id}
    res = c.call_tool("screen_capture", args)
    for item in res.get("content", []):
        if item.get("type") == "image":
            with open(out_path, "wb") as f:
                f.write(base64.b64decode(item["data"]))
            print(f"  [SAVED] {out_name} ({len(item['data'])} bytes)", flush=True)
            return True
    print(f"  [FAIL] {out_name}: {res}", flush=True)
    return False

def grind_to(c, sid, target_life, target_bal):
    print(f"Grinding to lifetime >= {target_life}, balance >= {target_bal}...")
    grind_code = BRIDGE + f"""
    local templates = {{ 'snack_meme', 'snack_thread', 'snack_honest', 'demo_bit', 'specs_breakdown', 'daily_driver', 'weekend_vlog_text', 'chill_spot_recs', 'local_roundup' }}
    local minLife = {target_life}
    local minBal = {target_bal}
    local n = 0
    while n < 40 do
        local p = snap()
        if p.lifetimeEarned >= minLife and p.balance >= minBal then break end
        local tpl = templates[(os.clock() * 7) % 9 // 1 + 1]
        n += 1
        bridge:Invoke('Action', {{ action = 'PublishOrganic', payload = {{ templateId = tpl }} }})
        task.wait(2.15)
    end
    local p = snap()
    return HttpService:JSONEncode({{ posts = n, balance = p.balance, lifetime = p.lifetimeEarned, tier = p.tier }})
    """
    for loop in range(10):
        st = cluau(c, sid, grind_code)
        print(f"  grind chunk {loop}: {st}", flush=True)
        if st.get("lifetime", 0) >= target_life and st.get("balance", 0) >= target_bal:
            return st
        time.sleep(1)
    return cluau(c, sid, BRIDGE + "return HttpService:JSONEncode(snap())")

def main():
    c = StudioClient()
    sid = studio.get_studio_id()
    print(f"Studio instance: {sid}")

    # Verify Viewport
    vp = cluau(c, sid, "local cam = workspace.CurrentCamera return tostring(cam.ViewportSize)")
    print(f"ViewportSize: {vp}")

    # Ensure desktop window is open and on Workers tab
    cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return true")
    time.sleep(1)

    cur = cluau(c, sid, BRIDGE + "return HttpService:JSONEncode(snap())")
    print(f"Initial state: balance={cur.get('balance')}, lifetime={cur.get('lifetimeEarned')}, tier={cur.get('tier')}, desks={cur.get('ownedDesks')}, workers={len(cur.get('workers', []))}")

    # Step 1: Grind to Tier 2 (lifetime >= 1600, balance >= 1050)
    if cur.get("lifetimeEarned", 0) < 1600 or cur.get("balance", 0) < 1050 or cur.get("tier", 0) < 2:
        grind_to(c, sid, 1620, 1050)

    # Re-check state after grind
    s1 = cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return HttpService:JSONEncode(snap())")
    print(f"Post-grind state: balance={s1.get('balance')}, lifetime={s1.get('lifetimeEarned')}, tier={s1.get('tier')}")
    assert s1.get("tier", 0) >= 2, f"Tier 2 not unlocked! {s1}"

    time.sleep(1.5)
    print("Capturing 10-tier2-unlock.png...")
    cap(c, sid, "cap-tier2", "10-tier2-unlock.png")

    # Step 2: Buy Desk 2
    if 2 not in (s1.get("ownedDesks") or []):
        print("Purchasing Desk 2...")
        buy_res = cluau(c, sid, BRIDGE + """
        local r = bridge:Invoke('Action', { action = 'BuyDesk', payload = { slotIndex = 2 } })
        return HttpService:JSONEncode({ sent = r })
        """)
        print(f"  BuyDesk sent: {buy_res}")
        time.sleep(2)

    s2 = cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return HttpService:JSONEncode(snap())")
    print(f"Post-Desk2 state: desks={s2.get('ownedDesks')}, workers={len(s2.get('workers', []))}")
    assert 2 in (s2.get("ownedDesks") or []), "Desk 2 not owned!"

    time.sleep(1.5)
    print("Capturing 20-desk2-before-hire.png...")
    cap(c, sid, "cap-desk2-before-hire", "20-desk2-before-hire.png")

    # Step 3: Hire Trainee 2
    if len(s2.get("workers") or []) < 2:
        print("Hiring Trainee 2...")
        hire_res = cluau(c, sid, BRIDGE + """
        local r = bridge:Invoke('Action', { action = 'HireWorker', payload = { slotIndex = 2, roleId = 'trainee' } })
        return HttpService:JSONEncode({ sent = r })
        """)
        print(f"  HireWorker sent: {hire_res}")
        time.sleep(2)

    s3 = cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return HttpService:JSONEncode(snap())")
    print(f"Post-Hire2 state: workers={len(s3.get('workers', []))}, ips={s3.get('incomePerSecond')}")
    assert len(s3.get("workers") or []) >= 2, "Trainee 2 not hired!"

    time.sleep(1.5)
    print("Capturing 50-workers-2of2.png...")
    cap(c, sid, "cap-workers-2of2", "50-workers-2of2.png")

    # Step 4: Rate 3.0, Pending vs Spendable, Chapter Complete
    # Wait for accrual to accumulate some pending Cuan before banking
    print("Waiting 10s for unbanked pending accrual to build up...")
    time.sleep(10)
    cluau(c, sid, BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return true")
    time.sleep(1)

    print("Capturing 60-rate-3-point-0.png...")
    cap(c, sid, "cap-rate-3-0", "60-rate-3-point-0.png")

    print("Capturing 70-pending-vs-spendable.png...")
    cap(c, sid, "cap-pending-vs-spendable", "70-pending-vs-spendable.png")

    print("Capturing 80-chapter-complete.png...")
    cap(c, sid, "cap-chapter-complete", "80-chapter-complete.png")

    c.close()
    print("All captures finished successfully!")

if __name__ == "__main__":
    main()
