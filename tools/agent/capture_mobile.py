import sys
import os
import time

sys.path.append(os.path.abspath("tools/agent"))
import studio

code = """
local StarterPlayer = game:GetService("StarterPlayer")
local spScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local uiFolder = spScripts:WaitForChild("ui")
local Desktop = require(uiFolder:WaitForChild("Desktop"))

local player = game:GetService("Players"):GetPlayers()[1]
local pgui = player and player:FindFirstChild("PlayerGui") or game:GetService("CoreGui")

local desktop = Desktop.new({
    parent = pgui,
    playerName = "galonnaquaaa",
    onClose = function() end,
    onTabSelected = function() end,
    onAction = function() end,
    getBlockReason = function() return nil end
})

desktop._gui.Enabled = true
desktop._window.AnchorPoint = Vector2.new(0, 0)
desktop._window.Position = UDim2.new(0, 40, 0, 40)
desktop._window.Size = UDim2.new(0, 390, 0, 720)
desktop:SetVisible(true, true)

desktop:Update({
    status = "Open",
    tab = "home",
    snapshot = {
        balance = 15,
        lifetimeEarned = 15,
        deviceId = "phone_cheap",
        propertyId = "bedroom",
        nextOrganicContextId = "snack_review",
        completedMissions = 0
    }
})

-- Store global ref so it remains rendered during capture
_G.__MobileTestDesktop = desktop
return true
"""

res = studio.luau(code, "Edit")
print("Mobile UI mounted:", res)
time.sleep(1)

out_file = "docs/evidence/bs10/mobile_portrait_390x844.png"
cap_res = studio.screen_capture("mobile_view", out_file)
print("Screen capture result:", cap_res)

clean_code = """
if _G.__MobileTestDesktop then
    _G.__MobileTestDesktop:Destroy()
    _G.__MobileTestDesktop = nil
end
return true
"""
studio.luau(clean_code, "Edit")
print("Cleaned up.")
