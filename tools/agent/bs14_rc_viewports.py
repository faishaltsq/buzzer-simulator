"""BS-14 RC-1 Studio viewport audit.

Measures the shipped UI at requested window sizes on this host, but reports
rows by the viewport that was ACTUALLY measured: the previous audit labelled
rows with the requested resolution while recording a different viewport, which
made the tablet row unreproducible.

Records per profile:
  - requested window size and actual Studio window rect
  - camera ViewportSize (what the UI actually lays out against)
  - dashboard window AbsoluteSize and AbsolutePosition
  - responsive mode decision and the inputs that produced it
  - every visible GuiButton with its real AbsoluteSize, flagging < 40x40

Output: docs/evidence/bs14-remediation/04-studio-viewport-audit.json
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
import studio  # noqa: E402

OUT = os.path.join("docs", "evidence", "bs14-remediation", "04-studio-viewport-audit.json")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

PROFILES = [
    # label, window w, h, tab
    ("phone-portrait-360x640", 360, 640, "Feed"),
    ("phone-portrait-390x844", 390, 844, "Feed"),
    ("phone-landscape-640x360", 640, 360, "Feed"),
    ("tablet-portrait-768x1024", 768, 1024, "Feed"),
    ("desktop-1280x720", 1280, 720, "Feed"),
    ("desktop-1920x1080", 1920, 1080, "Feed"),
]

OPEN_PROMPT = """
local pBridge = game:GetService('ServerScriptService'):WaitForChild('StudioPromptBridge', 5)
if pBridge == nil then return 'MISSING:StudioPromptBridge' end
local player = game:GetService('Players'):GetPlayers()[1]
local prompt = workspace:FindFirstChild('DashboardPrompt', true)
if prompt == nil then
  for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA('ProximityPrompt') then prompt = d break end
  end
end
if prompt == nil then return 'MISSING:DashboardPrompt' end
return tostring(pcall(function() return pBridge:Invoke(prompt, player) end))
"""

INSPECT = """
local HttpService = game:GetService('HttpService')
local lp = game:GetService('Players').LocalPlayer
local desktop = lp.PlayerGui:WaitForChild('BuzzerOSDesktop')
local bridge = desktop:WaitForChild('StudioClientBridge')
bridge:Invoke('SelectTab', 'TAB_NAME')
task.wait(0.6)
local cam = workspace.CurrentCamera
local window = desktop:FindFirstChild('BuzzerOSWindow', true)
local navRail = desktop:FindFirstChild('NavRail', true)
local mobileNav = desktop:FindFirstChild('MobileNav', true)
local winSize = window and window.AbsoluteSize or Vector2.zero
local winPos = window and window.AbsolutePosition or Vector2.zero
local targets, failures = {}, {}
for _, obj in ipairs(desktop:GetDescendants()) do
  if obj:IsA('GuiButton') and obj.Visible then
    local parentVisible = true
    local cursor = obj.Parent
    while cursor and cursor ~= desktop and cursor ~= lp.PlayerGui do
      if cursor:IsA('GuiObject') and not cursor.Visible then parentVisible = false break end
      cursor = cursor.Parent
    end
    if parentVisible then
      local abs = obj.AbsoluteSize
      local entry = { name = obj.Name, w = math.floor(abs.X + 0.5), h = math.floor(abs.Y + 0.5) }
      table.insert(targets, entry)
      if abs.X < 40 or abs.Y < 40 then table.insert(failures, entry) end
    end
  end
end
return HttpService:JSONEncode({
  viewport = { x = math.floor(cam.ViewportSize.X + 0.5), y = math.floor(cam.ViewportSize.Y + 0.5) },
  windowSize = { x = math.floor(winSize.X + 0.5), y = math.floor(winSize.Y + 0.5) },
  windowPosition = { x = math.floor(winPos.X + 0.5), y = math.floor(winPos.Y + 0.5) },
  isCompact = (winSize.X < 640) or (winSize.Y < 500),
  navRailVisible = navRail and navRail.Visible or false,
  mobileNavVisible = mobileNav and mobileNav.Visible or false,
  touchTargets = targets,
  touchFailures = failures,
})
"""


def main():
    client = studio.get_client()
    sid = os.environ.get("BUZZER_SID") or studio.get_studio_id()
    if not sid:
        raise SystemExit("no Studio instance visible")
    print(f"studio={sid}", flush=True)

    client.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    time.sleep(2)
    client.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(10)

    opened = studio.luau(OPEN_PROMPT, "Server")
    print(f"open prompt: {opened}", flush=True)
    if "MISSING" in str(opened):
        raise SystemExit(f"not the gameplay build: {opened}")
    time.sleep(2)

    try:
        import win32con
        import win32gui
    except ImportError:
        raise SystemExit("pywin32 unavailable; cannot resize the Studio window")

    hwnd = None

    def enum_cb(handle, _):
        nonlocal hwnd
        title = win32gui.GetWindowText(handle)
        if "Roblox Studio" in title and "Buzzer" in title:
            hwnd = hwnd or handle

    win32gui.EnumWindows(enum_cb, None)
    if hwnd is None:
        raise SystemExit("Studio window not found")
    win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
    time.sleep(1)

    results = []
    for label, width, height, tab in PROFILES:
        rect = win32gui.GetWindowRect(hwnd)
        win32gui.MoveWindow(hwnd, rect[0], rect[1], width, height, True)
        time.sleep(2.5)
        actual_rect = win32gui.GetWindowRect(hwnd)
        measured = studio.luau(INSPECT.replace("TAB_NAME", tab), "Client")
        try:
            data = json.loads(measured) if isinstance(measured, str) else measured
        except Exception as exc:
            data = {"error": str(exc), "raw": str(measured)[:400]}
        results.append(
            {
                "label": label,
                "requested": {"window": f"{width}x{height}", "tab": tab},
                "actualWindowRect": {
                    "x": actual_rect[0],
                    "y": actual_rect[1],
                    "w": actual_rect[2] - actual_rect[0],
                    "h": actual_rect[3] - actual_rect[1],
                },
                "measured": data,
                "labelMatchedActualViewport": (
                    data.get("viewport", {}).get("x") == width and data.get("viewport", {}).get("y") == height
                ),
            }
        )
        window_vp = data.get("viewport", {})
        print(f"{label}: window={actual_rect[2]-actual_rect[0]}x{actual_rect[3]-actual_rect[1]} "
              f"viewport={window_vp.get('x')}x{window_vp.get('y')} "
              f"compact={data.get('isCompact')} fails={len(data.get('touchFailures') or [])}", flush=True)

    client.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
    win32gui.ShowWindow(hwnd, win32con.SW_MAXIMIZE)

    payload = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "studio_id": sid,
        "host_screen_note": "Studio window resized with MoveWindow; UI lays out against camera ViewportSize",
        "profiles": results,
    }
    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
    print(f"written: {OUT}", flush=True)


if __name__ == "__main__":
    main()
