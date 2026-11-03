"""Rescue continuation: completes BS-13 evidence steps [11]-[17] against the
LIVE play session (economy ladder already completed by run_bs13_journey.py)."""
import base64
import json
import os
import sys
import time

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
sys.path.append(os.path.abspath("."))
import run_bs13_journey as J  # noqa: E402

OUT = J.OUT
EVIDENCE = {}
sid_holder = [None]


def cap(c, capture_id, out_name, cam=None, look=None):
    args = {"studio_id": sid_holder[0], "capture_id": capture_id}
    if cam:
        args["camera_position"] = cam
    if look:
        args["look_at_position"] = look
    try:
        res = c.call_tool("screen_capture", args)
        for item in res.get("content", []):
            if item.get("type") == "image":
                with open(os.path.join(OUT, out_name), "wb") as f:
                    f.write(base64.b64decode(item["data"]))
                print(f"  [cap] {out_name}", flush=True)
                return True
        print(f"  [cap-FAIL] {out_name}: {str(res)[:150]}", flush=True)
        return False
    except Exception as e:
        print(f"  [cap-ERROR] {out_name}: {e}", flush=True)
        return False


def main():
    c, sid = J.cli()
    sid_holder[0] = sid
    print(f"Studio: {sid}")

    # ---- [11] world verification ----
    print("[11] World verification (desk 2 + both trainees)")
    w = J.wait_world(c, sid, "Trainee2", 1)
    print(f"  world: {json.dumps(w)}")
    EVIDENCE["world"] = w
    assert w.get("WorkerDesk2", 0) >= 1, "desk 2 never mounted"
    assert w.get("Trainee1", 0) >= 1 and w.get("Trainee2", 0) >= 1, "trainee rigs missing"

    # ---- [12] world captures ----
    print("[12] World captures")
    J.cluau(c, sid, J.BRIDGE + "bridge:Invoke('Close') return true")
    time.sleep(2)
    pos = J.slserver(c, sid, """
local HttpService = game:GetService('HttpService')
local d1, d2 = workspace:FindFirstChild('WorkerDesk1', true), workspace:FindFirstChild('WorkerDesk2', true)
local p1 = d1 and d1:GetPivot().Position or Vector3.new(0, 3, 0)
local p2 = d2 and d2:GetPivot().Position or p1
return HttpService:JSONEncode({ c = { (p1 + p2).X / 2, (p1 + p2).Y + 2, (p1 + p2).Z / 2 }, d1 = { p1.X, p1.Y, p1.Z }, d2 = { p2.X, p2.Y, p2.Z } })
""")
    cx = (pos["d1"][0] + pos["d2"][0]) / 2
    cz = (pos["d1"][2] + pos["d2"][2]) / 2
    cap(c, "cap-both-trainees", "30-both-trainees.png",
        cam=[cx + 6, pos["c"][1] + 5, cz + 8], look=pos["c"])
    cap(c, "cap-full-room", "40-full-studio-room.png",
        cam=[cx + 10, pos["c"][1] + 9, cz + 13], look=pos["c"])
    cap(c, "cap-alt-camera", "95-alt-camera.png",
        cam=[cx - 8, pos["c"][1] + 4, cz - 9], look=pos["c"])

    # ---- [13] workers captures ----
    print("[13] Workers captures 2/2, rate, chapter complete")
    print("  " + str(J.slserver(c, sid, J.OPEN_PROMPT)))
    time.sleep(2)
    J.cluau(c, sid, J.BRIDGE + "bridge:Invoke('SelectTab', 'Workers') return true")
    time.sleep(1.5)
    cap(c, "cap-workers-2of2", "50-workers-2of2.png")

    # ---- [14] 30s bank -> +90 ----
    print("[14] 30s bank")
    s0 = J.cluau(c, sid, J.BRIDGE + "return HttpService:JSONEncode({ b = snap().balance, pend = snap().pendingWorkerCuan })")
    print(f"  before: {s0}")
    EVIDENCE["pre_bank"] = s0
    t0 = time.time()
    cur, pend_peak = s0, 0
    while time.time() - t0 < 42:
        time.sleep(2)
        cur = J.cluau(c, sid, J.BRIDGE + "return HttpService:JSONEncode({ b = snap().balance, pend = snap().pendingWorkerCuan })")
        pend_peak = max(pend_peak, cur.get("pend", 0) or 0)
        if cur.get("b", 0) - s0.get("b", 0) >= 90:
            break
    EVIDENCE["bank30"] = {"before_balance": s0.get("b"), "pending_peak": pend_peak,
                          "after_balance": cur.get("b"), "delta": (cur.get("b", 0) - s0.get("b", 0))}
    print(f"  bank: {EVIDENCE['bank30']}")
    cap(c, "cap-rate", "60-rate-3-point-0.png")
    cap(c, "cap-pending-vs-spendable", "70-pending-vs-spendable.png")
    cap(c, "cap-chapter-complete", "80-chapter-complete.png")

    # ---- [15] mobile portrait ----
    print("[15] Mobile portrait (real narrow viewport)")
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
            win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
            old = win32gui.GetWindowRect(hwnd)
            win32gui.MoveWindow(hwnd, old[0], old[1], 520, 940, True)
            time.sleep(2.5)
            vis = J.cluau(c, sid, J.BRIDGE + "return bridge:Invoke('IsDesktopVisible')")
            if not vis:
                J.slserver(c, sid, J.OPEN_PROMPT)
                time.sleep(2)
            J.cluau(c, sid, J.BRIDGE + "bridge:Invoke('SelectTab', 'Home') return true")
            time.sleep(1.2)
            cap(c, "cap-mobile", "90-mobile-portrait.png")
            win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
            time.sleep(1.5)
        else:
            print("  [mobile-FAIL] no window handle")
    except Exception as e:
        print(f"  [mobile-ERROR] {e}")

    # ---- [16] part budget ----
    print("[16] Part budget check")
    parts_txt = J.slserver(c, sid, J.COUNT_PARTS)
    parts = int(parts_txt) if isinstance(parts_txt, (str, int)) else int(parts_txt.get("n", 0))
    EVIDENCE["parts"] = parts
    print(f"  live parts: {parts} (budget 350)")
    cap(c, "cap-part-proof", "99-part-count-context.png")

    # ---- [17] persistence gate (expected G2 BLOCKED offline) ----
    print("[17] Persistence gate (offline studio)")
    J.cluau(c, sid, J.BRIDGE + "bridge:Invoke('Close') return true")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(5)
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(12)
    try:
        pj = J.cluau(c, sid, J.BRIDGE + "return HttpService:JSONEncode({ vis = bridge:Invoke('IsDesktopVisible'), b = snap().balance, t = snap().tier })")
        EVIDENCE["rejoin"] = {"expected_gate": "G2 BLOCKED (offline studio, in-memory DEV fallback)",
                              "observed": pj}
        print(f"  rejoin: {pj}")
        J.slserver(c, sid, J.OPEN_PROMPT)
        time.sleep(2)
        cap(c, "cap-rejoin", "97-rejoin-fresh-session.png")
    except Exception as e:
        EVIDENCE["rejoin"] = {"expected_gate": "G2 BLOCKED", "error": str(e)[:200]}
        print(f"  rejoin note: {e}")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(3)

    # merge with prior evidence json if present
    prior = {}
    ev_path = os.path.join(OUT, "journey-evidence.json")
    if os.path.exists(ev_path):
        try:
            with open(ev_path, encoding="utf-8") as f:
                prior = json.load(f)
        except Exception:
            prior = {}
    prior.update(EVIDENCE)
    with open(ev_path, "w", encoding="utf-8") as f:
        json.dump(prior, f, indent=2, default=str)
    print("=== rescue complete; journey-evidence.json merged ===")


if __name__ == "__main__":
    main()
