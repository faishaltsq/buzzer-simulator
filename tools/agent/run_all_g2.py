import sys
import os
import json
import time

sys.path.append(os.path.abspath("tools/agent"))
import studio

code = """
local HttpService = game:GetService("HttpService")
local sss = game:GetService("ServerScriptService")
local rep = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local SessionService = require(sss:WaitForChild("SessionService"))
local ProfileStore = require(sss:WaitForChild("ProfileStore"))
local Catalog = require(rep:WaitForChild("Shared"):WaitForChild("Catalog"))
local spScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local ClientState = require(spScripts:WaitForChild("ClientState"))
local uiFolder = spScripts:WaitForChild("ui")
local Desktop = require(uiFolder:WaitForChild("Desktop"))

local devUserId = 88005001
local results = {}

-- =========================================================================
-- G2-01: Fresh Account
-- =========================================================================
local g1_s1 = SessionService.new({ userId = devUserId, jobId = "job-g201-1" })
local g1_start1 = g1_s1:Start()
if not g1_start1.ok and g1_start1.code == "NOT_READY" then
    g1_start1 = g1_s1:InitializeStarter()
end
local g1_prof1 = g1_s1:GetConfirmedProfile()
local g1_rev1 = g1_s1:GetRevision()
local g1_stop1 = g1_s1:Stop()

local g1_s2 = SessionService.new({ userId = devUserId, jobId = "job-g201-2" })
local g1_start2 = g1_s2:Start()
local g1_prof2 = g1_s2:GetConfirmedProfile()
local g1_rev2 = g1_s2:GetRevision()
local g1_stop2 = g1_s2:Stop()

local g2_01_pass = (g1_prof1.balance == 0)
    and (g1_prof1.deviceId == "phone_cheap")
    and (g1_prof2.balance == 0)
    and (g1_prof2.deviceId == "phone_cheap")
    and (g1_rev2 >= g1_rev1)

results["G2-01"] = {
    testId = "G2-01",
    pass = g2_01_pass,
    initialBalance = g1_prof1.balance,
    initialDevice = g1_prof1.deviceId,
    initialRevision = g1_rev1,
    rejoinBalance = g1_prof2.balance,
    rejoinDevice = g1_prof2.deviceId,
    rejoinRevision = g1_rev2,
}

-- =========================================================================
-- G2-02: Organic Pending Recovery
-- =========================================================================
local g2_s1 = SessionService.new({ userId = devUserId, jobId = "job-g202-1" })
g2_s1:Start()
g2_s1:Snapshot()
g2_s1:Mutate({
    requestId = "g202-pub-1",
    action = "PublishOrganic",
    payload = { templateId = "snack_meme" }
})
task.wait(1)
g2_s1:Stop()

-- Wait 18s reveal duration
task.wait(18)

local g2_s2 = SessionService.new({ userId = devUserId, jobId = "job-g202-2" })
g2_s2:Start()
g2_s2:Snapshot() -- triggers _settleDue()
local g2_prof = g2_s2:GetConfirmedProfile()
local g2_rev = g2_s2:GetRevision()
g2_s2:Stop()

-- Rejoin to verify no duplicate
local g2_s3 = SessionService.new({ userId = devUserId, jobId = "job-g202-3" })
g2_s3:Start()
g2_s3:Snapshot()
local g2_profRepeat = g2_s3:GetConfirmedProfile()
g2_s3:Stop()

local g2_02_pass = (g2_prof.balance == 15)
    and (g2_prof.pendingPost == nil)
    and (g2_profRepeat.balance == 15)

results["G2-02"] = {
    testId = "G2-02",
    pass = g2_02_pass,
    settledBalance = g2_prof.balance,
    repeatBalance = g2_profRepeat.balance,
    revision = g2_rev,
}

-- =========================================================================
-- G2-03: Campaign Pending Recovery
-- =========================================================================
local g3_s1 = SessionService.new({ userId = devUserId, jobId = "job-g203-1" })
g3_s1:Start()
g3_s1:Snapshot()
g3_s1:Mutate({
    requestId = "g203-acc-1",
    action = "AcceptMission",
    payload = { missionId = "food_stall_launch" }
})
local runId = g3_s1:GetConfirmedProfile().activeMission.runId
g3_s1:Mutate({
    requestId = "g203-pub-1",
    action = "PublishPost",
    payload = { runId = runId, templateId = "meal_meme" }
})
task.wait(1)
g3_s1:Stop()

-- Wait 18s reveal duration
task.wait(18)

local g3_s2 = SessionService.new({ userId = devUserId, jobId = "job-g203-2" })
g3_s2:Start()
g3_s2:Snapshot()
local g3_prof = g3_s2:GetConfirmedProfile()
local g3_active = g3_prof.activeMission
local g3_rev = g3_s2:GetRevision()
g3_s2:Stop()

local g2_03_pass = (g3_prof.balance == 30)
    and (g3_active ~= nil)
    and (g3_active.runId == runId)
    and (g3_active.status == "readyToClaim")
    and (g3_active.postCount == 1)

results["G2-03"] = {
    testId = "G2-03",
    pass = g2_03_pass,
    runId = runId,
    balance = g3_prof.balance,
    missionStatus = g3_active and g3_active.status,
    postCount = g3_active and g3_active.postCount,
    revision = g3_rev,
}

-- =========================================================================
-- G2-04: Claim Persistence
-- =========================================================================
local g4_s1 = SessionService.new({ userId = devUserId, jobId = "job-g204-1" })
g4_s1:Start()
g4_s1:Snapshot()
local g4_clm = g4_s1:Mutate({
    requestId = "g204-clm-1",
    action = "ClaimMission",
    payload = { runId = runId }
})
local g4_prof1 = g4_s1:GetConfirmedProfile()
g4_s1:Stop()

local g4_s2 = SessionService.new({ userId = devUserId, jobId = "job-g204-2" })
g4_s2:Start()
g4_s2:Snapshot()
local g4_prof2 = g4_s2:GetConfirmedProfile()
local g4_dup = g4_s2:Mutate({
    requestId = "g204-clm-dup",
    action = "ClaimMission",
    payload = { runId = runId }
})
local g4_prof3 = g4_s2:GetConfirmedProfile()
local g4_rev = g4_s2:GetRevision()
g4_s2:Stop()

local g2_04_pass = (g4_clm.ok == true)
    and (g4_prof1.balance == 110)
    and (g4_prof2.balance == 110)
    and (g4_prof2.activeMission == nil)
    and (not g4_dup.ok or g4_dup.code == "ALREADY_DONE" or g4_dup.code == "NO_ACTIVE_MISSION")
    and (g4_prof3.balance == 110)

results["G2-04"] = {
    testId = "G2-04",
    pass = g2_04_pass,
    claimedBalance = g4_prof1.balance,
    rejoinBalance = g4_prof2.balance,
    balanceAfterDup = g4_prof3.balance,
    completedMissions = g4_prof2.completedMissions,
    revision = g4_rev,
}

-- =========================================================================
-- G2-05: Fast Phone Purchase Persistence
-- =========================================================================
local g5_s1 = SessionService.new({ userId = devUserId, jobId = "job-g205-1" })
g5_s1:Start()
g5_s1:Snapshot()
local g5_buy = g5_s1:Mutate({
    requestId = "g205-buy-1",
    action = "BuyDevice",
    payload = { deviceId = "phone_fast" }
})
local g5_prof1 = g5_s1:GetConfirmedProfile()
g5_s1:Stop()

local g5_s2 = SessionService.new({ userId = devUserId, jobId = "job-g205-2" })
g5_s2:Start()
g5_s2:Snapshot()
local g5_prof2 = g5_s2:GetConfirmedProfile()
local g5_dup = g5_s2:Mutate({
    requestId = "g205-buy-dup",
    action = "BuyDevice",
    payload = { deviceId = "phone_fast" }
})
local g5_prof3 = g5_s2:GetConfirmedProfile()
local g5_rev = g5_s2:GetRevision()
g5_s2:Stop()

local g2_05_pass = (g5_buy.ok == true)
    and (g5_prof1.balance == 60)
    and (g5_prof1.deviceId == "phone_fast")
    and (g5_prof2.balance == 60)
    and (g5_prof2.deviceId == "phone_fast")
    and (not g5_dup.ok or g5_dup.code == "ALREADY_DONE")
    and (g5_prof3.balance == 60)

results["G2-05"] = {
    testId = "G2-05",
    pass = g2_05_pass,
    boughtBalance = g5_prof1.balance,
    boughtDevice = g5_prof1.deviceId,
    rejoinBalance = g5_prof2.balance,
    rejoinDevice = g5_prof2.deviceId,
    balanceAfterDup = g5_prof3.balance,
    revision = g5_rev,
}

-- =========================================================================
-- G2-06: Post-Upgrade Payout
-- =========================================================================
local g6_s1 = SessionService.new({ userId = devUserId, jobId = "job-g206-1" })
g6_s1:Start()
g6_s1:Snapshot()
g6_s1:Mutate({
    requestId = "g206-pub-1",
    action = "PublishOrganic",
    payload = { templateId = "snack_meme" }
})
task.wait(18) -- Fast phone reveal is 16s + 2s buffer
g6_s1:Snapshot()
local g6_prof1 = g6_s1:GetConfirmedProfile()
g6_s1:Stop()

local g6_s2 = SessionService.new({ userId = devUserId, jobId = "job-g206-2" })
g6_s2:Start()
g6_s2:Snapshot()
local g6_prof2 = g6_s2:GetConfirmedProfile()
local g6_rev = g6_s2:GetRevision()
g6_s2:Stop()

local g2_06_pass = (g6_prof1.balance == 84)
    and (g6_prof2.balance == 84)
    and (g6_prof2.deviceId == "phone_fast")

results["G2-06"] = {
    testId = "G2-06",
    pass = g2_06_pass,
    settledBalance = g6_prof1.balance,
    rejoinBalance = g6_prof2.balance,
    payout = g6_prof1.balance - 60,
    device = g6_prof2.deviceId,
    revision = g6_rev,
}

-- =========================================================================
-- G2-07: Lease Behavior
-- =========================================================================
local g7_sA = SessionService.new({ userId = devUserId, jobId = "job-g207-A" })
g7_sA:Start()
g7_sA:Snapshot()

local g7_sB = SessionService.new({ userId = devUserId, jobId = "job-g207-B" })
local g7_startB = g7_sB:Start() -- expected LOCKED
local g7_locked = (not g7_startB.ok and g7_startB.code == "LOCKED")

g7_sA:Stop()

local g7_startB2 = g7_sB:Start()
g7_sB:Snapshot()
local g7_profB = g7_sB:GetConfirmedProfile()
local g7_rev = g7_sB:GetRevision()
g7_sB:Stop()

local g2_07_pass = g7_locked
    and (g7_startB2.ok == true)
    and (g7_profB.balance == 84)

results["G2-07"] = {
    testId = "G2-07",
    pass = g2_07_pass,
    competingCode = g7_startB.code,
    handoffOk = g7_startB2.ok,
    confirmedBalance = g7_profB.balance,
    revision = g7_rev,
}

-- =========================================================================
-- G2-08: Failure Recovery
-- =========================================================================
local devUserFail = 88005002
local g8_s = SessionService.new({ userId = devUserFail, jobId = "job-g208-1" })
local g8_start = g8_s:Start()
if not g8_start.ok and g8_start.code == "NOT_READY" then
    g8_start = g8_s:InitializeStarter()
end

local g8_mut1 = g8_s:Mutate({
    requestId = "g208-req-1",
    action = "PublishOrganic",
    payload = { templateId = "snack_meme" }
})
local g8_rev1 = g8_s:GetRevision()

local g8_mutRetry = g8_s:Mutate({
    requestId = "g208-req-1",
    action = "PublishOrganic",
    payload = { templateId = "snack_meme" }
})
local g8_rev2 = g8_s:GetRevision()
local g8_replayNoBump = (g8_rev2 == g8_rev1)

local g8_spoof = g8_s:Mutate({
    requestId = "g208-req-1",
    action = "PublishOrganic",
    payload = { templateId = "tampered_payload" }
})
local g8_spoofRejected = (not g8_spoof.ok and g8_spoof.code == "INVALID_INPUT")

local g8_badBuy = g8_s:Mutate({
    requestId = "g208-req-badbuy",
    action = "BuyDevice",
    payload = { deviceId = "phone_fast" }
})
local g8_badBuyRejected = (not g8_badBuy.ok and g8_badBuy.code == "INSUFFICIENT_FUNDS")
local g8_balanceAfterBadBuy = g8_s:GetConfirmedProfile().balance

local failingStore = {
    GetAsync = function() error("Simulated DS connection failure", 0) end,
    UpdateAsync = function() error("Simulated DS write failure", 0) end,
    RemoveAsync = function() end,
}
local failingPs = ProfileStore.new(9999991, { store = failingStore })
local failedLoad = failingPs:Load()
local g8_readFailedSafe = (not failedLoad.ok and failedLoad.code == "SAVE_UNAVAILABLE" and failingPs:GetConfirmedEnvelope() == nil)

g8_s:Stop()

local g2_08_pass = g8_replayNoBump
    and g8_spoofRejected
    and g8_badBuyRejected
    and (g8_balanceAfterBadBuy == 0)
    and g8_readFailedSafe

results["G2-08"] = {
    testId = "G2-08",
    pass = g2_08_pass,
    replayNoRevisionBump = g8_replayNoBump,
    spoofRejected = g8_spoofRejected,
    badBuyRejected = g8_badBuyRejected,
    balanceAfterBadBuy = g8_balanceAfterBadBuy,
    readFailedSafe = g8_readFailedSafe,
}

-- =========================================================================
-- G2-09: Client and Device Recovery
-- =========================================================================
local clientSnap = {
    revision = 11,
    serverTime = 1000,
    balance = 84,
    pendingWorkerCuan = 0,
    incomePerSecond = 0,
    tier = 0,
    deviceId = "phone_fast",
    completedMissions = 1,
    nextOrganicContextId = "organic_snack",
    saveStatus = "healthy",
    workers = {},
    missions = {},
    recentMutationOutcomes = {},
    ownPosts = {},
}
local cState = ClientState.new(clientSnap)

cState:ApplyOpenComputer({
    kind = "OpenComputer",
    dashboardSessionId = "g209-sess-1",
    expiresAt = 1240,
    serverTime = 1000,
    state = clientSnap,
}, 1000)
local c_opening = cState:GetStatus()
cState:OnCameraOpened()
local c_open = cState:GetStatus()

local c_closeCmd = cState:CloseLocally()
local c_closing = cState:GetStatus()
cState:OnCameraRestored()
local c_closed = cState:GetStatus()

cState:ApplyOpenComputer({
    kind = "OpenComputer",
    dashboardSessionId = "g209-sess-2",
    expiresAt = 1240,
    serverTime = 1000,
    state = clientSnap,
}, 1000)
cState:OnCameraOpened()
local c_deathHandled = cState:OnCharacterLost()
local c_statusAfterDeath = cState:GetStatus()
local c_sessCleared = (cState:Get().dashboardSessionId == nil)

cState:ApplyOpenComputer({
    kind = "OpenComputer",
    dashboardSessionId = "g209-sess-3",
    expiresAt = 1240,
    serverTime = 1000,
    state = clientSnap,
}, 1000)
cState:OnCameraOpened()
local c_cmd = cState:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
local c_timeoutFired = cState:CheckTimeouts(1007)
local c_isUncertain = (c_cmd ~= nil) and (cState:Get().uncertainMutations[c_cmd.requestId] ~= nil)
local c_isBlocked = (cState:MutationBlockReason() ~= nil)

local testGui = Instance.new("ScreenGui")
testGui.Name = "G209FullRunGui"
testGui.Parent = game:GetService("CoreGui")

local dFrame = Instance.new("Frame")
dFrame.Size = UDim2.fromOffset(1280, 720)
dFrame.Parent = testGui
local dUi = Desktop.new({ parent = dFrame, playerName = "Tester", onClose = function() end, onTabSelected = function() end })
dUi:Update(cState:Get())
local dOk = (#dFrame:GetChildren() > 0)

local mFrame = Instance.new("Frame")
mFrame.Size = UDim2.fromOffset(390, 844)
mFrame.Parent = testGui
local mUi = Desktop.new({ parent = mFrame, playerName = "Tester", onClose = function() end, onTabSelected = function() end })
mUi:Update(cState:Get())
local mOk = (#mFrame:GetChildren() > 0)

dUi:Destroy()
mUi:Destroy()
testGui:Destroy()

local g2_09_pass = (c_opening == "Opening")
    and (c_open == "Open")
    and (c_closing == "Closing")
    and (c_closed == "Closed")
    and (c_closeCmd ~= nil)
    and c_deathHandled
    and (c_statusAfterDeath == "Closed")
    and c_sessCleared
    and (#c_timeoutFired > 0)
    and c_isUncertain
    and c_isBlocked
    and dOk
    and mOk

results["G2-09"] = {
    testId = "G2-09",
    pass = g2_09_pass,
    statusLifecycle = c_opening .. "->" .. c_open .. "->" .. c_closing .. "->" .. c_closed,
    characterDeathHandled = c_deathHandled,
    uncertainTracked = c_isUncertain,
    desktopLayout = dOk,
    mobileLayout = mOk,
}

return HttpService:JSONEncode(results)
"""

print("Executing Complete G2 Suite on Live DataStore (approx 45 seconds total)...")
t0 = time.time()
res = studio.luau(code, "Edit")
print("Total Elapsed:", time.time() - t0)
print("Complete G2 Results:", res)
with open("docs/evidence/bs10/g2_live_results.json", "w") as f:
    f.write(res)
print("Saved to docs/evidence/bs10/g2_live_results.json")
