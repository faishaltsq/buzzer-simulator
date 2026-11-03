import sys, os, time, json, base64
import win32gui, win32con

sys.path.append(os.path.abspath("tools/agent"))
import studio

c = studio.get_client()
sid = studio.get_studio_id()

hwnd = None
def enum_cb(h, _):
    global hwnd
    t = win32gui.GetWindowText(h)
    if "Production" in t and "Roblox Studio" in t:
        hwnd = hwnd or h
win32gui.EnumWindows(enum_cb, None)

print(f"Studio HWND: {hwnd}")

# 1. Resize Studio to narrow mobile portrait
if hwnd:
    win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
    rect = win32gui.GetWindowRect(hwnd)
    win32gui.MoveWindow(hwnd, rect[0], rect[1], 520, 940, True)
    time.sleep(2.5)

# Verify viewport and mobile layout active
layout_check = """
local lp = game:GetService('Players').LocalPlayer
local pgui = lp:WaitForChild('PlayerGui')
local desktop = pgui:WaitForChild('BuzzerOSDesktop')
local bridge = desktop:WaitForChild('StudioClientBridge')
local cam = workspace.CurrentCamera
bridge:Invoke('SelectTab', 'Workers')

local pageWorkers = desktop:FindFirstChild('Page_Workers', true)
if pageWorkers and pageWorkers:IsA('ScrollingFrame') then
    pageWorkers.CanvasPosition = Vector2.new(0, 0)
end

local mobileNav = desktop:FindFirstChild('MobileNav', true)
local navRail = desktop:FindFirstChild('NavRail', true)

return {
    vp = tostring(cam.ViewportSize),
    isDesktopVis = bridge:Invoke('IsDesktopVisible'),
    mobileNavVis = mobileNav ~= nil and mobileNav.Visible,
    navRailVis = navRail ~= nil and navRail.Visible,
    tab = "Workers"
}
"""
print("Mobile layout check:", studio.luau(layout_check, "Client"))
time.sleep(1)

# Capture 90-mobile-portrait.jpg (Top of Workers page: Chapter complete + Overview)
out_90 = os.path.join("docs", "evidence", "bs13", "90-mobile-portrait.jpg")
res90 = c.call_tool("screen_capture", {"studio_id": sid, "capture_id": "cap-mobile-workers-90"})
for item in res90.get("content", []):
    if item.get("type") == "image":
        with open(out_90, "wb") as f:
            f.write(base64.b64decode(item["data"]))
        print(f"Saved {out_90} ({len(item['data'])} bytes)")
        break

# Scroll down to show Trainee cards clearly
scroll_code = """
local pgui = game:GetService('Players').LocalPlayer.PlayerGui
local desktop = pgui.BuzzerOSDesktop
local pageWorkers = desktop:FindFirstChild('Page_Workers', true)
if pageWorkers and pageWorkers:IsA('ScrollingFrame') then
    pageWorkers.CanvasPosition = Vector2.new(0, 480)
    return true
end
return false
"""
studio.luau(scroll_code, "Client")
time.sleep(1)

# Capture 91-mobile-workers.jpg (Scrolled: Desk 2 and Trainee cards)
out_91 = os.path.join("docs", "evidence", "bs13", "91-mobile-workers.jpg")
res91 = c.call_tool("screen_capture", {"studio_id": sid, "capture_id": "cap-mobile-workers-91"})
for item in res91.get("content", []):
    if item.get("type") == "image":
        with open(out_91, "wb") as f:
            f.write(base64.b64decode(item["data"]))
        print(f"Saved {out_91} ({len(item['data'])} bytes)")
        break

# Also capture 99-part-count-context.jpg with part count proof
out_99 = os.path.join("docs", "evidence", "bs13", "99-part-count-context.jpg")
res99 = c.call_tool("screen_capture", {"studio_id": sid, "capture_id": "cap-parts-99"})
for item in res99.get("content", []):
    if item.get("type") == "image":
        with open(out_99, "wb") as f:
            f.write(base64.b64decode(item["data"]))
        print(f"Saved {out_99} ({len(item['data'])} bytes)")
        break

# Restore window
if hwnd:
    win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)
    time.sleep(1)

print("Captures complete!")
