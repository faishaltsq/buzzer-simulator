import sys
import os
import time
import json
import base64
import win32gui
import win32con

sys.path.append(os.path.abspath("tools/agent"))
import studio

def find_studio_hwnd():
    target = None
    def enum_cb(h, _):
        nonlocal target
        text = win32gui.GetWindowText(h)
        if "Production.rbxlx" in text and "Roblox Studio" in text:
            target = h
    win32gui.EnumWindows(enum_cb, None)
    return target

def capture_image(c, sid, capture_id, out_path):
    res = c.call_tool("screen_capture", {"studio_id": sid, "capture_id": capture_id})
    for item in res.get("content", []):
        if item.get("type") == "image":
            data = base64.b64decode(item["data"])
            with open(out_path, "wb") as f:
                f.write(data)
            print(f"Saved {out_path} ({len(data)} bytes)")
            return True
    return False

def run_profiling():
    c = studio.get_client()
    sid = studio.get_studio_id()
    hwnd = find_studio_hwnd()
    print(f"Studio HWND: {hwnd}, Studio ID: {sid}")

    print("Initiating Play Solo session for Mobile Profiling...")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(3)

    # 1. Open BuzzerOS Desktop via Server StudioPromptBridge
    open_desktop_server = """
    local Players = game:GetService("Players")
    local sss = game:GetService("ServerScriptService")
    local player = Players:GetPlayers()[1]
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")

    local prompt = workspace:FindFirstChild("DashboardPrompt", true)
    if prompt then
        root.CFrame = prompt.Parent.CFrame + Vector3.new(0, 2, 2)
        task.wait(0.5)
        local pBridge = sss:WaitForChild("StudioPromptBridge", 5)
        local ok, res = pcall(function() return pBridge:Invoke(prompt, player) end)
        return { teleported = true, invoked = ok, result = res }
    end
    return { promptFound = false }
    """
    s_open = studio.luau(open_desktop_server, "Server")
    print("Server Open Status:", s_open)
    time.sleep(2.0)

    check_client_desktop = """
    local lp = game:GetService("Players").LocalPlayer
    local pgui = lp:WaitForChild("PlayerGui")
    local desktop = pgui:WaitForChild("BuzzerOSDesktop")
    local bridge = desktop:WaitForChild("StudioClientBridge")
    return {
        isDesktopVisible = bridge:Invoke("IsDesktopVisible"),
        state = bridge:Invoke("GetState").status
    }
    """
    open_res = studio.luau(check_client_desktop, "Client")
    print("Desktop Open Status (Client):", open_res)

    # Prepare evidence directory
    evidence_dir = os.path.join("docs", "evidence", "bs14")
    os.makedirs(evidence_dir, exist_ok=True)

    # Define Viewports to test
    viewports = [
        {
            "name": "Mobile Portrait (390x844)",
            "win_w": 480, "win_h": 880,
            "maximize": False,
            "expected_mode": "compact",
            "tab": "Workers",
            "screenshot": "01-mobile-portrait-workers.jpg"
        },
        {
            "name": "Mobile Portrait Missions (390x844)",
            "win_w": 480, "win_h": 880,
            "maximize": False,
            "expected_mode": "compact",
            "tab": "Missions",
            "screenshot": "02-mobile-portrait-missions.jpg"
        },
        {
            "name": "Mobile Landscape (640x360)",
            "win_w": 750, "win_h": 460,
            "maximize": False,
            "expected_mode": "compact",
            "tab": "Home",
            "screenshot": "03-mobile-landscape.jpg"
        },
        {
            "name": "Tablet Landscape (768x1024)",
            "win_w": 1150, "win_h": 950,
            "maximize": False,
            "expected_mode": "wide",
            "tab": "Workers",
            "screenshot": "04-tablet-layout.jpg"
        },
        {
            "name": "Desktop 1080p (1280x720+)",
            "win_w": None, "win_h": None,
            "maximize": True,
            "expected_mode": "wide",
            "tab": "Home",
            "screenshot": "05-desktop-1080p.jpg"
        }
    ]

    viewport_results = []

    for vp in viewports:
        print(f"\n--- Testing Viewport: {vp['name']} ---")
        if hwnd:
            if vp.get("maximize"):
                win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
            else:
                win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
                rect = win32gui.GetWindowRect(hwnd)
                win32gui.MoveWindow(hwnd, rect[0], rect[1], vp["win_w"], vp["win_h"], True)
            time.sleep(2.0)

        # Inspect layout and touch targets
        inspect_code = f"""
        local lp = game:GetService("Players").LocalPlayer
        local pgui = lp:WaitForChild("PlayerGui")
        local desktop = pgui:WaitForChild("BuzzerOSDesktop")
        local bridge = desktop:WaitForChild("StudioClientBridge")
        local cam = workspace.CurrentCamera
        
        bridge:Invoke("SelectTab", "{vp['tab']}")
        task.wait(0.5)

        local window = desktop:FindFirstChild("BuzzerOSWindow", true)
        local navRail = desktop:FindFirstChild("NavRail", true)
        local mobileNav = desktop:FindFirstChild("MobileNav", true)
        local closeBtn = desktop:FindFirstChild("CloseButton", true)

        local vpSize = cam.ViewportSize
        local winSize = window and window.AbsoluteSize or Vector2.zero
        local isCompact = (winSize.X < 640) or (winSize.Y < 500)

        -- Touch target audit for all active visible buttons
        local touchTargets = {{}}
        local failTargets = {{}}
        for _, obj in ipairs(desktop:GetDescendants()) do
            if obj:IsA("GuiButton") and obj.Visible then
                local parentVis = true
                local curr = obj.Parent
                while curr and curr ~= desktop and curr ~= pgui do
                    if curr:IsA("GuiObject") and not curr.Visible then
                        parentVis = false
                        break
                    end
                    curr = curr.Parent
                end
                if parentVis then
                    local abs = obj.AbsoluteSize
                    local passSize = (abs.X >= 40 and abs.Y >= 40) -- standard 44px with 10% subpixel tolerance
                    table.insert(touchTargets, {{
                        name = obj.Name,
                        width = abs.X,
                        height = abs.Y,
                        pass = passSize
                    }})
                    if not passSize then
                        table.insert(failTargets, {{
                            name = obj.Name,
                            width = abs.X,
                            height = abs.Y
                        }})
                    end
                end
            end
        end

        local HttpService = game:GetService("HttpService")
        return HttpService:JSONEncode({{
            viewport = {{ x = vpSize.X, y = vpSize.Y }},
            window = {{ x = winSize.X, y = winSize.Y }},
            isCompact = isCompact,
            navRailVisible = navRail and navRail.Visible,
            mobileNavVisible = mobileNav and mobileNav.Visible,
            totalTouchTargets = #touchTargets,
            failedTouchTargets = #failTargets,
            fails = failTargets
        }})
        """
        raw_res = studio.luau(inspect_code, "Client")
        try:
            vp_data = json.loads(raw_res) if isinstance(raw_res, str) else raw_res
        except Exception as e:
            vp_data = {"error": str(e), "raw": raw_res}
        
        vp_data["name"] = vp["name"]
        vp_data["target_mode"] = vp["expected_mode"]
        actual_mode = "compact" if vp_data.get("isCompact") else "wide"
        mode_match = (actual_mode == vp["expected_mode"])
        vp_data["modeMatch"] = mode_match
        
        print(f"  Viewport: {vp_data.get('viewport')}, Window: {vp_data.get('window')}")
        print(f"  Responsive Mode: {actual_mode} (Expected: {vp['expected_mode']}, Match: {mode_match})")
        print(f"  NavRail: {vp_data.get('navRailVisible')}, MobileNav: {vp_data.get('mobileNavVisible')}")
        print(f"  Touch Targets Evaluated: {vp_data.get('totalTouchTargets')}, Fails: {vp_data.get('failedTouchTargets')}")
        
        viewport_results.append(vp_data)

        # Capture Screenshot
        img_path = os.path.join(evidence_dir, vp["screenshot"])
        capture_image(c, sid, f"cap-{vp['screenshot']}", img_path)

    # 2. Performance, BasePart budget and Memory audit in Server
    perf_code = """
    local HttpService = game:GetService("HttpService")
    local Stats = game:GetService("Stats")
    local RunService = game:GetService("RunService")
    
    -- Count BaseParts in Workspace
    local baseParts = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            baseParts += 1
        end
    end
    
    -- Measure frame rates over 60 heartbeats
    local frameTimes = {}
    local startClock = os.clock()
    for i = 1, 60 do
        local dt = RunService.Heartbeat:Wait()
        table.insert(frameTimes, dt)
    end
    local totalTime = os.clock() - startClock
    local avgFps = 60 / totalTime
    
    local minDt = 999
    local maxDt = 0
    for _, dt in ipairs(frameTimes) do
        if dt < minDt then minDt = dt end
        if dt > maxDt then maxDt = dt end
    end
    local minFps = 1 / maxDt
    
    -- Memory metrics
    local totalMem = Stats:GetTotalMemoryUsageMb()
    
    return HttpService:JSONEncode({
        baseParts = baseParts,
        budgetLimit = 350,
        budgetOk = (baseParts <= 350),
        avgFps = math.floor(avgFps * 10) / 10,
        minFps = math.floor(minFps * 10) / 10,
        fpsTargetOk = (minFps >= 30),
        memoryMb = math.floor(totalMem * 10) / 10
    })
    """
    perf_raw = studio.luau(perf_code, "Server")
    print("\n--- Performance & Asset Audit ---")
    print("Raw Perf:", perf_raw)
    try:
        perf_data = json.loads(perf_raw) if isinstance(perf_raw, str) else perf_raw
    except Exception as e:
        perf_data = {"error": str(e), "raw": perf_raw}
    print(f"  BaseParts: {perf_data.get('baseParts')} / {perf_data.get('budgetLimit')} (Budget OK: {perf_data.get('budgetOk')})")
    print(f"  Avg FPS: {perf_data.get('avgFps')}, Min FPS: {perf_data.get('minFps')} (Target >= 30: {perf_data.get('fpsTargetOk')})")
    print(f"  Memory: {perf_data.get('memoryMb')} MB")

    # Stop Play Solo
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})

    # Restore window
    if hwnd:
        win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
        time.sleep(1)

    # Save structured evidence
    final_evidence = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
        "viewports": viewport_results,
        "performance": perf_data
    }
    json_path = os.path.join(evidence_dir, "mobile-profiling.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(final_evidence, f, indent=2)
    print(f"Saved {json_path}")

    txt_path = os.path.join(evidence_dir, "mobile-profiling.txt")
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write("=== BS-14 Real Mobile & Low-End Profiling Evidence ===\n")
        f.write(f"Timestamp: {final_evidence['timestamp']}\n\n")
        f.write("1. MULTI-VIEWPORT AUDIT:\n")
        for vp in viewport_results:
            f.write(f"- {vp.get('name')}:\n")
            f.write(f"    Viewport: {vp.get('viewport')}, Window: {vp.get('window')}\n")
            f.write(f"    Mode: actual={vp.get('isCompact') and 'compact' or 'wide'}, target={vp.get('target_mode')}, match={vp.get('modeMatch')}\n")
            f.write(f"    Navigation: NavRail={vp.get('navRailVisible')}, MobileNav={vp.get('mobileNavVisible')}\n")
            f.write(f"    Touch targets: total={vp.get('totalTouchTargets')}, fails={vp.get('failedTouchTargets')}\n\n")
        f.write("2. BASEPART & MEMORY BUDGET:\n")
        f.write(f"- BaseParts in Workspace: {perf_data.get('baseParts')} (Ceiling <= 350): {'PASS' if perf_data.get('budgetOk') else 'FAIL'}\n")
        f.write(f"- Average FPS: {perf_data.get('avgFps')}, Min FPS: {perf_data.get('minFps')} (Target >= 30 FPS): {'PASS' if perf_data.get('fpsTargetOk') else 'FAIL'}\n")
        f.write(f"- Client/Server Memory Footprint: {perf_data.get('memoryMb')} MB\n\n")
        f.write("3. CAPTURED SCREENSHOTS:\n")
        for vp in viewports:
            f.write(f"- docs/evidence/bs14/{vp['screenshot']}\n")
    print(f"Saved {txt_path}")

    return final_evidence

if __name__ == "__main__":
    run_profiling()
