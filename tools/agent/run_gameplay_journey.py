#!/usr/bin/env python3
"""In-Engine Integration Harness: Gameplay Domain & Service Verification.

NOTICE & EVIDENCE LABEL:
This script executes real Luau code inside Roblox Studio Server DataModel,
verifying domain logic across SessionService, ProfileStore, MissionService,
EconomyService, Catalog, Rules, and WorldService.
It uses an in-memory FakeStore and simulated player identity for isolated,
fast-forwarded deterministic verification without requiring live external
network access. It does NOT provide proof of live Roblox DataStore API
cloud persistence. Real player UI and DataStore checks are handled separately.
"""

import sys
import os
import time

sys.path.append(os.path.abspath("tools/agent"))
import studio

code = """
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local SessionService = require(ServerStorage:WaitForChild("SessionService"))
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))
local MissionService = require(ServerStorage:WaitForChild("MissionService"))
local EconomyService = require(ServerStorage:WaitForChild("EconomyService"))
local WorldService = require(ServerStorage:WaitForChild("WorldService"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rules = require(Shared:WaitForChild("Rules"))

local logs = {}
local function log(msg)
    table.insert(logs, msg)
    print("[JOURNEY] " .. msg)
end

local copy = ProfileStore._deepCopy
local guid = 0
local http: any = {}
function http:GenerateGUID()
    guid += 1
    return "journey-guid-" .. guid
end
function http:JSONEncode(v)
    return game:GetService("HttpService"):JSONEncode(v)
end

-- In-memory persistent DataStore simulating Roblox DataStore across rejoins
local DataStore = {}

local FakeStore: any = {}
FakeStore.__index = FakeStore
function FakeStore.new()
    return setmetatable({}, FakeStore)
end
function FakeStore:GetAsync(key)
    return copy(DataStore[key])
end
function FakeStore:UpdateAsync(key, transform)
    local cur = copy(DataStore[key])
    local nextVal = transform(cur)
    if nextVal ~= nil then
        DataStore[key] = copy(nextVal)
    end
    return copy(nextVal)
end

local wallClock = 1000
local function now() return wallClock end

-- Step 1: Initialize Player 1234 Session (First spawn)
log("Step 1: Spawning Player 1234 with starter profile (Cheap Phone + OldCRT)")
local session = SessionService.new({
    userId = 1234,
    store = FakeStore.new(),
    httpService = http,
    jobId = "server-job-1",
    now = now,
    noCacheOptions = function() return { UseCache = false } end,
})

local startRes = session:Start()
if not startRes.ok and startRes.code == "NOT_READY" then
    local initRes = session:InitializeStarter()
    assert(initRes.ok, "InitializeStarter must succeed: " .. tostring(initRes.detail))
else
    assert(startRes.ok, "Session start must succeed")
end

local snap1 = session:Snapshot().snapshot
assert(snap1.deviceId == "phone_cheap", "Starter device must be phone_cheap")
assert(snap1.balance == 0, "Starter balance must be 0")
log("  -> Confirmed starter device: " .. snap1.deviceId .. ", balance: " .. snap1.balance)

-- WorldService check: OldCRT at TerminalSlot
local fakePlayer = { UserId = 1234, Name = "BuzzerTester" }
WorldService.Spawn(fakePlayer, snap1)
local room = WorldService.GetRoom(fakePlayer)
assert(room ~= nil, "Room must spawn")
local terminalSlot = WorldService.GetAnchor(fakePlayer, "TerminalSlot")
local oldCRT = terminalSlot:FindFirstChild("OldCRT")
assert(oldCRT ~= nil, "OldCRT must be mounted at TerminalSlot")
local phoneSlot = WorldService.GetAnchor(fakePlayer, "PhoneSlot")
local phoneProp = phoneSlot:FindFirstChild("PhoneCheap")
assert(phoneProp ~= nil, "PhoneCheap prop must be mounted at PhoneSlot")
log("  -> WorldService verified: OldCRT at TerminalSlot, PhoneCheap at PhoneSlot")

-- Step 2: Publish organic content and receive confirmed Cuan
log("Step 2: Publishing organic post on Cheap Phone")
local pubOrg = session:Mutate({
    requestId = "req-org-1",
    action = "PublishOrganic",
    payload = { templateId = "snack_meme" },
})
assert(pubOrg.ok, "PublishOrganic must succeed: " .. tostring(pubOrg.detail))
local snapAfterPub = session:Snapshot().snapshot
local pending = snapAfterPub.pendingPost
assert(pending ~= nil, "Pending post must exist")
assert(pending.settleAt - pending.publishedAt == 18, "Cheap phone reveal must be 18s")
assert(pending.organicCuan == 15, "Cheap phone strong organic payout must be 15")
log("  -> Organic post pending: revealSeconds=" .. (pending.settleAt - pending.publishedAt) .. ", payout=" .. pending.organicCuan)

-- Settle organic post by advancing time and reading snapshot (server auto-settles due post)
wallClock += 19
local snapAfterSettle = session:Snapshot().snapshot
assert(snapAfterSettle.balance == 15, "Balance must be 15 Cuan")
log("  -> Settled organic post: Confirmed balance = " .. snapAfterSettle.balance .. " Cuan")

-- Step 3: Accept, complete, and claim a mission (food_stall_launch)
log("Step 3: Accepting and claiming mission food_stall_launch")
local accMis = session:Mutate({
    requestId = "req-accept-1",
    action = "AcceptMission",
    payload = { missionId = "food_stall_launch" },
})
assert(accMis.ok, "AcceptMission must succeed: " .. tostring(accMis.detail))
local snapAfterAcc = session:Snapshot().snapshot
assert(snapAfterAcc.activeMission ~= nil, "Active mission must exist")
local runId1 = snapAfterAcc.activeMission.runId

local pubMis = session:Mutate({
    requestId = "req-pub-mis-1",
    action = "PublishPost",
    payload = { runId = runId1, templateId = "meal_meme" },
})
assert(pubMis.ok, "PublishPost must succeed: " .. tostring(pubMis.detail))

wallClock += 19
session:Snapshot()

local claimMis = session:Mutate({
    requestId = "req-claim-1",
    action = "ClaimMission",
    payload = { runId = runId1 },
})
assert(claimMis.ok, "ClaimMission must succeed: " .. tostring(claimMis.detail))
local snapAfterClaim = session:Snapshot().snapshot
-- Balance was 15 + 15 (organic) + 80 (bonus) = 110 Cuan
assert(snapAfterClaim.balance == 110, "Balance must be 110 Cuan (15 + 15 + 80)")
assert(snapAfterClaim.completedMissions == 1, "Completed missions must be 1")
log("  -> Mission claimed: Confirmed balance = " .. snapAfterClaim.balance .. " Cuan, completed=" .. snapAfterClaim.completedMissions)

-- Step 4: Purchase Fast Phone for 50 Cuan
log("Step 4: Purchasing Fast Phone for 50 Cuan")
local buyFast = session:Mutate({
    requestId = "req-buy-fast",
    action = "BuyDevice",
    payload = { deviceId = "phone_fast" },
})
assert(buyFast.ok, "BuyDevice phone_fast must succeed: " .. tostring(buyFast.detail))
local snapAfterFast = session:Snapshot().snapshot
assert(snapAfterFast.balance == 60, "Balance must be 60 Cuan (110 - 50)")
assert(snapAfterFast.deviceId == "phone_fast", "Device must be phone_fast")
log("  -> Purchased phone_fast: Balance = " .. snapAfterFast.balance .. " Cuan")

-- WorldService check: PhoneFast prop at PhoneSlot
WorldService.Spawn(fakePlayer, snapAfterFast)
local phoneFastProp = phoneSlot:FindFirstChild("PhoneFast")
assert(phoneFastProp ~= nil, "PhoneFast prop mounted at PhoneSlot")
log("  -> WorldService verified: PhoneFast equipped at PhoneSlot")

-- Step 5: Progress through M1 mission content
log("Step 5: Progressing through fictional_gadget and neon_market")
-- fictional_gadget (reward 100)
local accG = session:Mutate({ requestId = "req-acc-gadget", action = "AcceptMission", payload = { missionId = "fictional_gadget" } })
assert(accG.ok, "Accept fictional_gadget failed: code=" .. tostring(accG.code) .. " detail=" .. tostring(accG.detail))
local runIdG = session:Snapshot().snapshot.activeMission.runId
session:Mutate({ requestId = "req-pub-gadget", action = "PublishPost", payload = { runId = runIdG, templateId = "demo_joke" } })
wallClock += 17
session:Snapshot()
local claimGadget = session:Mutate({ requestId = "req-clm-gadget", action = "ClaimMission", payload = { runId = runIdG } })
assert(claimGadget.ok, "Claim fictional_gadget ok")
local snapGadget = session:Snapshot().snapshot
-- Balance: 60 + 24 (organic) + 100 (bonus) = 184
assert(snapGadget.balance == 184, "Balance must be 184")
log("  -> fictional_gadget claimed: Balance = " .. snapGadget.balance)

-- neon_market (reward 120)
local accM = session:Mutate({ requestId = "req-acc-market", action = "AcceptMission", payload = { missionId = "neon_market" } })
assert(accM.ok, "Accept neon_market ok")
local runIdM = session:Snapshot().snapshot.activeMission.runId
session:Mutate({ requestId = "req-pub-market", action = "PublishPost", payload = { runId = runIdM, templateId = "event_thread" } })
wallClock += 17
session:Snapshot()
local claimMarket = session:Mutate({ requestId = "req-clm-market", action = "ClaimMission", payload = { runId = runIdM } })
assert(claimMarket.ok, "Claim neon_market ok")
local snapMarket = session:Snapshot().snapshot
-- Balance: 184 + 24 (organic) + 120 (bonus) = 328 Cuan. Lifetime = 378 Cuan. Claims = 3.
assert(snapMarket.balance == 328, "Balance must be 328 Cuan")
assert(snapMarket.lifetimeEarned == 378, "Lifetime must be 378 Cuan")
assert(snapMarket.completedMissions == 3, "Claims must be 3 (Tier 1 reached!)")
log("  -> neon_market claimed: Balance = " .. snapMarket.balance .. ", Lifetime = " .. snapMarket.lifetimeEarned .. " (Tier 1 reached)")

-- Step 6: Purchase PC Rumah for exactly 220 Cuan
log("Step 6: Purchasing PC Rumah for 220 Cuan")
local buyPC = session:Mutate({
    requestId = "req-buy-pc",
    action = "BuyDevice",
    payload = { deviceId = "pc_rumah" },
})
assert(buyPC.ok, "BuyDevice pc_rumah must succeed: " .. tostring(buyPC.detail))
local snapPC = session:Snapshot().snapshot
assert(snapPC.balance == 108, "Balance must be 108 Cuan (328 - 220)")
assert(snapPC.deviceId == "pc_rumah", "Device must be pc_rumah")
log("  -> PC Rumah purchased! Balance = 108 Cuan, Device = pc_rumah")

-- Step 7: Confirm PC strong/weak payouts (37 / 22 Cuan) and reveal (13 seconds)
log("Step 7: Confirming PC payouts and reveal duration")
local dev: any = nil
for _, d in ipairs(Catalog.Devices) do
    if d.id == "pc_rumah" then
        dev = d
        break
    end
end
assert(dev ~= nil, "pc_rumah in catalog")
assert(dev.price == 220, "PC price 220")
assert(dev.deviceYield == 2.50, "PC yield 2.50x")
assert(dev.revealSeconds == 13, "PC reveal 13s")

local strongPayout = Rules.organicCuan("strong", dev.deviceYield)
local weakPayout = Rules.organicCuan("weak", dev.deviceYield)
assert(strongPayout == 37, "PC strong payout must be 37")
assert(weakPayout == 22, "PC weak payout must be 22")
log("  -> PC specs confirmed: Yield=2.50x, Reveal=13s, Strong Payout=37, Weak Payout=22")

-- Step 8: WorldService verification: PC Rumah replaces OldCRT at TerminalSlot
log("Step 8: Verifying PC Rumah replaces OldCRT at TerminalSlot")
WorldService.Spawn(fakePlayer, snapPC)
local pcModel = terminalSlot:FindFirstChild("PCRumah")
assert(pcModel ~= nil, "PCRumah must be mounted at TerminalSlot")
local crtModel = terminalSlot:FindFirstChild("OldCRT")
assert(crtModel == nil, "OldCRT must be removed from TerminalSlot")
local inertPhone = phoneSlot:FindFirstChild("PhoneFast")
assert(inertPhone ~= nil, "PhoneFast must remain at PhoneSlot as inert desk prop")
log("  -> WorldService verified: PCRumah present at TerminalSlot, OldCRT removed, PhoneFast remains inert")

-- Step 9: Yield does not stack; sole productive device is pc_rumah
log("Step 9: Verifying no yield stacking via organic post on PC Rumah (organic sequence 1: organic_gadget, winning template demo_bit)")
local pcPub = session:Mutate({
    requestId = "req-pc-pub",
    action = "PublishOrganic",
    payload = { templateId = "demo_bit" },
})
assert(pcPub.ok, "PublishOrganic on PC must succeed: " .. tostring(pcPub.detail))
local snapPCPending = session:Snapshot().snapshot.pendingPost
assert(snapPCPending ~= nil, "PC pending post exists")
assert(snapPCPending.organicCuan == 37, "Sole active yield must produce exactly 37 Cuan for strong post (never stacked)")
assert(snapPCPending.settleAt - snapPCPending.publishedAt == 13, "PC reveal must be exactly 13s")
wallClock += 14
session:Snapshot() -- settles the post
local expectedBal = 108 + 37 -- 145 Cuan
local expectedLife = 378 + 37 -- 415 Cuan
log("  -> Confirmed sole active yield = 2.50x (organic payout=37, reveal=13s, no yield stacking, confirmed bal=145)")

-- Step 10: Retries, idempotency, duplicate requests, illegal skips
log("Step 10: Testing idempotency and illegal state rejections")
-- Re-buying pc_rumah
local rebuyPC = session:Mutate({
    requestId = "req-buy-pc-again",
    action = "BuyDevice",
    payload = { deviceId = "pc_rumah" },
})
assert(rebuyPC.ok == false, "Re-buying pc_rumah must fail")
assert(rebuyPC.code == "ALREADY_DONE", "Code must be ALREADY_DONE")

-- Duplicate request id
local dupRes = session:Mutate({
    requestId = "req-buy-pc",
    action = "BuyDevice",
    payload = { deviceId = "pc_rumah" },
})
assert(dupRes.ok, "Duplicate request ID must return cached success outcome")
local snapDup = session:Snapshot().snapshot
assert(snapDup.balance == expectedBal, "Balance must NOT be deducted twice")
log("  -> Duplicate request ID safely returned cached outcome without double-charge")

-- Step 11: Rejoin simulation across session shutdown
log("Step 11: Simulating disconnect and player rejoin through DataStore")
local stopRes = session:Stop()
assert(stopRes.ok, "Session clean stop must succeed")
log("  -> Session 1 cleanly stopped and flushed to persistent store")

-- Rejoin player in new session instance
local session2 = SessionService.new({
    userId = 1234,
    store = FakeStore.new(),
    httpService = http,
    jobId = "server-job-2",
    now = function() return wallClock + 100 end,
    noCacheOptions = function() return { UseCache = false } end,
})
local startRes2 = session2:Start()
assert(startRes2.ok, "Session 2 start must succeed on restored profile")
local snap2 = session2:Snapshot().snapshot
assert(snap2.deviceId == "pc_rumah", "Restored deviceId must be pc_rumah")
assert(snap2.balance == expectedBal, "Restored balance must be " .. expectedBal .. " Cuan")
assert(snap2.completedMissions == 3, "Restored completed missions must be 3")
assert(snap2.lifetimeEarned == expectedLife, "Restored lifetimeEarned must be " .. expectedLife)
log("  -> Session 2 restore SUCCESS: device=pc_rumah, balance=" .. expectedBal .. ", lifetime=" .. expectedLife .. ", claims=3")

WorldService.Remove(fakePlayer)
log("JOURNEY_ALL_PASSED")
return table.concat(logs, "\\n")
"""

studio.call('start_stop_play', {'is_start': True})
time.sleep(2.0)
try:
    print("=== [IN-ENGINE INTEGRATION HARNESS: In-Memory FakeStore & Simulated Player] ===")
    res = studio.call("execute_luau", {"code": code, "datamodel_type": "Server"})
    print("Gameplay Journey Execution Result:")
    print(res)
finally:
    studio.call('start_stop_play', {'is_start': False})
    time.sleep(1.0)
