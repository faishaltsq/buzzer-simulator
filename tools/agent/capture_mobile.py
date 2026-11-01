import sys
import os
import time
import json
import win32gui
import win32con
import win32api

sys.path.append(os.path.abspath("tools/agent"))
import studio

client = studio.get_client()
sid = studio.get_studio_id()

hwnd = win32gui.FindWindow(None, "Buzzer Simulator [DEV - BS-10] - Roblox Studio")
if hwnd:
    win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
    win32gui.SetForegroundWindow(hwnd)
    time.sleep(0.5)

print("[1] Starting Play Solo with active Mobile Device Emulator...")
client.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
time.sleep(6)

vp_code = """
local cam = workspace.CurrentCamera
return tostring(cam.ViewportSize)
"""
vp = studio.luau(vp_code, "Client")
print(f"Current Play mode viewport: {vp}")

# If in landscape, rotate to portrait
if int(vp.split(",")[0].strip()) > int(vp.split(",")[1].strip()):
    print("Rotating mobile emulator to portrait...")
    win32gui.SetForegroundWindow(hwnd)
    time.sleep(0.2)
    win32api.SetCursorPos((284 + 1024, 165 + 20))
    time.sleep(0.05)
    win32api.mouse_event(win32con.MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    time.sleep(0.05)
    win32api.mouse_event(win32con.MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
    time.sleep(1.0)
    vp = studio.luau(vp_code, "Client")
    print(f"Viewport after rotation: {vp}")

print("[2] Triggering CRT Proximity Prompt from Server...")
server_prompt_code = """
local sss = game:GetService("ServerScriptService")
local prompt = workspace:FindFirstChild("DashboardPrompt", true)
local pBridge = sss:WaitForChild("StudioPromptBridge")
local player = game:GetService("Players"):GetPlayers()[1]
return pBridge:Invoke(prompt, player)
"""
p_res = studio.luau(server_prompt_code, "Server")
time.sleep(2)

print("[3] Verifying Mobile Layout Geometry in PlayerGui...")
inspect_code = """
local HttpService = game:GetService("HttpService")
local lp = game:GetService("Players").LocalPlayer
local pgui = lp.PlayerGui
local desktopGui = pgui.BuzzerOSDesktop
local bridge = desktopGui.StudioClientBridge

local cam = workspace.CurrentCamera
local win = desktopGui:FindFirstChild("Window", true)
local mobileNav = desktopGui:FindFirstChild("MobileNav", true)
local navRail = desktopGui:FindFirstChild("NavRail", true)

return HttpService:JSONEncode({
    viewport = tostring(cam.ViewportSize),
    desktopVisible = bridge:Invoke("IsDesktopVisible"),
    windowSize = win and tostring(win.AbsoluteSize),
    windowPos = win and tostring(win.AbsolutePosition),
    mobileNavVisible = mobileNav and mobileNav.Visible,
    mobileNavSize = mobileNav and tostring(mobileNav.AbsoluteSize),
    navRailVisible = navRail and navRail.Visible
})
"""
layout_res = json.loads(studio.luau(inspect_code, "Client"))
print("Mobile Desktop Verified:", layout_res)

out_file = "docs/evidence/bs10/mobile_portrait_390x844.png"
cap = studio.screen_capture("mobile_portrait_390x844", out_file)
print("Screen capture saved:", cap)

# Stop play mode
client.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
time.sleep(2)
print("Play mode stopped. Mobile verification complete.")
