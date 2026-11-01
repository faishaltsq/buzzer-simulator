import sys
import os
import time
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio

client = studio.get_client()
sid = studio.get_studio_id()

print("=================================================================")
print("LIVE IN-EXPERIENCE GAMEPLAY SMOKE TEST")
print("Target Player: galonnaquaaa (UserId: 7554478273)")
print("Development Universe: 10774181892, Place: 100558697471228")
print("=================================================================")

# Pre-check: Reset galonnaquaaa's dev DataStore key to start fresh
print("\n[Step 0] Initializing fresh profile for galonnaquaaa in dev DataStore...")
reset_code = """
local DataStoreService = game:GetService("DataStoreService")
local ds = DataStoreService:GetDataStore("PlayerData")
local ok, err = pcall(function()
    ds:RemoveAsync("Player_7554478273")
end)
return ok
"""
reset_ok = studio.luau(reset_code, "Edit")
print("DataStore reset result:", reset_ok)
time.sleep(2)

# Step 1: Join with fresh profile
print("\n[Step 1] Starting Play Solo (Fresh Join)...")
client.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
time.sleep(6) # wait for world, character, and session startup

join_check_code = """
local HttpService = game:GetService("HttpService")
local lp = game:GetService("Players").LocalPlayer
local pgui = lp:WaitForChild("PlayerGui")
local desktopGui = pgui:WaitForChild("BuzzerOSDesktop")
local bridge = desktopGui:WaitForChild("StudioClientBridge")

local state = bridge:Invoke("GetState")
local camera = workspace.CurrentCamera

return HttpService:JSONEncode({
    playerName = lp.Name,
    userId = lp.UserId,
    ready = lp:GetAttribute("BuzzerReady"),
    initialBalance = state and state.snapshot and state.snapshot.balance,
    initialDevice = state and state.snapshot and state.snapshot.deviceId,
    status = bridge:Invoke("GetStatus"),
    cameraType = tostring(camera.CameraType),
    cameraSubject = camera.CameraSubject and camera.CameraSubject.Name
})
"""
join_res = json.loads(studio.luau(join_check_code, "Client"))
print("Fresh Join Verified:", join_res)

# Step 2: Open CRT
print("\n[Step 2] Triggering CRT Proximity Prompt...")
server_prompt_code = """
local sss = game:GetService("ServerScriptService")
local prompt = workspace:FindFirstChild("DashboardPrompt", true)
local pBridge = sss:WaitForChild("StudioPromptBridge")
local player = game:GetService("Players"):GetPlayers()[1]
return pBridge:Invoke(prompt, player)
"""
prompt_res = studio.luau(server_prompt_code, "Server")
print("Prompt Invoked:", prompt_res)
time.sleep(2) # wait for camera transition tween

open_check_code = """
local HttpService = game:GetService("HttpService")
local camera = workspace.CurrentCamera
local lp = game:GetService("Players").LocalPlayer
local bridge = lp.PlayerGui.BuzzerOSDesktop.StudioClientBridge

return HttpService:JSONEncode({
    status = bridge:Invoke("GetStatus"),
    desktopVisible = bridge:Invoke("IsDesktopVisible"),
    cameraType = tostring(camera.CameraType),
    cameraSubject = camera.CameraSubject and camera.CameraSubject.Name
})
"""
open_res = json.loads(studio.luau(open_check_code, "Client"))
print("CRT Opened Verified:", open_res)

# Step 3: Publish Organic Post & Confirm Reward
print("\n[Step 3] Publishing Organic Post ('snack_meme') from Client...")
publish_code = """
local HttpService = game:GetService("HttpService")
local lp = game:GetService("Players").LocalPlayer
local bridge = lp.PlayerGui.BuzzerOSDesktop.StudioClientBridge

local actResult = bridge:Invoke("Action", {
    action = "PublishOrganic",
    payload = { templateId = "snack_meme" }
})

local state = bridge:Invoke("GetState")
return HttpService:JSONEncode({
    actionDispatched = actResult,
    pendingPostActive = state and state.snapshot and (state.snapshot.pendingPost ~= nil),
    balanceBeforeReveal = state and state.snapshot and state.snapshot.balance
})
"""
pub_res = json.loads(studio.luau(publish_code, "Client"))
print("Publish Action Dispatched:", pub_res)

print("Waiting 20 seconds for reveal duration (18s) and server settlement pump...")
time.sleep(20)

settle_check_code = """
local HttpService = game:GetService("HttpService")
local lp = game:GetService("Players").LocalPlayer
local bridge = lp.PlayerGui.BuzzerOSDesktop.StudioClientBridge
local state = bridge:Invoke("GetState")

return HttpService:JSONEncode({
    balanceAfterSettlement = state and state.snapshot and state.snapshot.balance,
    pendingPostActive = state and state.snapshot and (state.snapshot.pendingPost ~= nil),
    status = bridge:Invoke("GetStatus")
})
"""
settle_res = json.loads(studio.luau(settle_check_code, "Client"))
print("Post Settled & Reward Confirmed:", settle_res)

# Step 4: Close CRT and Verify Camera Restoration
print("\n[Step 4] Closing CRT Terminal & Verifying Camera Restoration...")
close_and_verify_code = """
local HttpService = game:GetService("HttpService")
local lp = game:GetService("Players").LocalPlayer
local bridge = lp.PlayerGui.BuzzerOSDesktop.StudioClientBridge

local closeOk = bridge:Invoke("Close")
task.wait(1.5) -- wait for camera restoration and tween/control release

local camera = workspace.CurrentCamera
return HttpService:JSONEncode({
    closeInvoked = closeOk,
    status = bridge:Invoke("GetStatus"),
    desktopVisible = bridge:Invoke("IsDesktopVisible"),
    cameraType = tostring(camera.CameraType),
    cameraSubject = camera.CameraSubject and camera.CameraSubject.Name
})
"""
restore_res = json.loads(studio.luau(close_and_verify_code, "Client"))
print("CRT Closed & Camera Restored Verified:", restore_res)

# Step 5: Leave Experience (Stop Play Solo)
print("\n[Step 5] Leaving Experience (Stop Play Solo to save session)...")
client.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
time.sleep(3)

# Step 6: Rejoin Experience
print("\n[Step 6] Rejoining Experience (Start Play Solo to verify cloud persistence)...")
client.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
time.sleep(6) # wait for startup & cloud load

rejoin_check_code = """
local HttpService = game:GetService("HttpService")
local lp = game:GetService("Players").LocalPlayer
local bridge = lp.PlayerGui.BuzzerOSDesktop.StudioClientBridge
local state = bridge:Invoke("GetState")
local camera = workspace.CurrentCamera

return HttpService:JSONEncode({
    playerName = lp.Name,
    userId = lp.UserId,
    ready = lp:GetAttribute("BuzzerReady"),
    rejoinBalance = state and state.snapshot and state.snapshot.balance,
    rejoinDevice = state and state.snapshot and state.snapshot.deviceId,
    status = bridge:Invoke("GetStatus"),
    cameraType = tostring(camera.CameraType),
    cameraSubject = camera.CameraSubject and camera.CameraSubject.Name
})
"""
rejoin_res = json.loads(studio.luau(rejoin_check_code, "Client"))
print("Rejoin Cloud Persistence Verified:", rejoin_res)

# Stop play mode
client.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
time.sleep(2)

# Evaluation of all invariants
all_passed = (
    join_res.get("ready") == True
    and join_res.get("initialBalance") == 0
    and join_res.get("initialDevice") == "phone_cheap"
    and open_res.get("cameraType") == "Enum.CameraType.Scriptable"
    and open_res.get("desktopVisible") == True
    and pub_res.get("actionDispatched") == True
    and settle_res.get("balanceAfterSettlement") == 15
    and settle_res.get("pendingPostActive") == False
    and restore_res.get("cameraType") == "Enum.CameraType.Custom"
    and restore_res.get("cameraSubject") == "Humanoid"
    and restore_res.get("desktopVisible") == False
    and rejoin_res.get("ready") == True
    and rejoin_res.get("rejoinBalance") == 15
    and rejoin_res.get("rejoinDevice") == "phone_cheap"
)

summary = {
    "testPlayer": "galonnaquaaa",
    "userId": 7554478273,
    "universeId": 10774181892,
    "placeId": 100558697471228,
    "pass": all_passed,
    "steps": {
        "step1_freshJoin": join_res,
        "step2_crtOpen": open_res,
        "step3_publish": pub_res,
        "step3_settlement": settle_res,
        "step4_crtClose": restore_res,
        "step6_rejoin": rejoin_res
    }
}

os.makedirs("docs/evidence/bs10", exist_ok=True)
with open("docs/evidence/bs10/gameplay_smoke_results.json", "w") as f:
    json.dump(summary, f, indent=2)

print("\n=================================================================")
print(f"GAMEPLAY SMOKE TEST OVERALL STATUS: {'PASS' if all_passed else 'FAIL'}")
print("Evidence saved to docs/evidence/bs10/gameplay_smoke_results.json")
print("=================================================================")
