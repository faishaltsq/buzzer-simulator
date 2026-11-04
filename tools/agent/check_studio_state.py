import sys, os, time, json
sys.path.append(os.path.abspath("tools/agent"))
import studio

code = """
local lp = game:GetService('Players').LocalPlayer
local bridge = lp:WaitForChild('PlayerGui'):WaitForChild('BuzzerOSDesktop'):WaitForChild('StudioClientBridge')
local HttpService = game:GetService('HttpService')
local function snap() return bridge:Invoke('GetState').snapshot end

local s = snap()
return HttpService:JSONEncode({
    balance = s.balance,
    lifetime = s.lifetimeEarned,
    claims = s.completedMissions,
    tier = s.tier,
    workers = #s.workers,
    desks = s.ownedDesks,
    rate = s.incomePerSecond,
    device = s.deviceId
})
"""
print(studio.luau(code, "Client"))
