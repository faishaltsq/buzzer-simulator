--!strict
-- Buzzer Simulator — BS-12 spec: First Workstation, Trainee 1, and Banked Passive Income.
-- Validates:
-- 1. Desk 1 gating: requires PC Rumah + Tier 1 + 180 Cuan. Phone or Tier 0 refused (NOT_READY).
-- 2. Desk 1 exact price: 180 Cuan debited, balance drops, lifetime untouched. 179 refused.
-- 3. Desk 1 duplicate refused (ALREADY_DONE).
-- 4. Desk 2 locked in BS-12 (NOT_READY).
-- 5. Trainee 1 gating: requires Desk 1 + Tier 1 + PC Rumah + 500 Cuan. Without Desk 1 refused (NOT_READY).
-- 6. Trainee 1 exact price: 500 debited, 499 refused (INSUFFICIENT_FUNDS).
-- 7. Trainee 1 duplicate refused (ALREADY_DONE).
-- 8. Trainee 2 locked in BS-12 (NOT_READY).
-- 9. Single worker accrual: exactly 1.5 Cuan/s online.
-- 10. Fractional carry: 0.5 residual carry across ticks without loss.
-- 11. Zero workers accrual: 0 workers produce 0 Cuan.
-- 12. Rate scaling: 2 workers produce 3.0 Cuan/s.
-- 13. WorldService.SyncWorkers mounts WorkerDesk1 at WorkerDeskSlot1 and Trainee1 at WorkerSeat1.
-- 14. WorldService budget: room with PC + Phone + Desk1 + Trainee1 strictly <= 350 BaseParts.
-- 15. Workers UI projection: accurate phases and block reasons.
-- 16. ClientState mutation validation: BuyDesk and HireWorker payloads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog")) :: any
local Rules = require(Shared:WaitForChild("Rules")) :: any

local EconomyService = require(ServerStorage:WaitForChild("EconomyService")) :: any
local SessionService = require(ServerStorage:WaitForChild("SessionService")) :: any
local WorldService = require(ServerStorage:WaitForChild("WorldService")) :: any

local spScripts = StarterPlayer:WaitForChild("StarterPlayerScripts", 10) :: any
local ClientState = require(spScripts:WaitForChild("ClientState", 10)) :: any
local uiFolder = spScripts:WaitForChild("ui", 10) :: any
local Workers = require(uiFolder:WaitForChild("Workers", 10)) :: any

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`, 0)
	end
end

local function expectTrue(cond: boolean, label: string)
	if not cond then
		error(label, 0)
	end
end

local function expectFalse(cond: boolean, label: string)
	if cond then
		error(label, 0)
	end
end

local function freshProfile(): any
	return {
		schemaVersion = 1,
		balance = 0,
		lifetimeEarned = 0,
		completedMissions = 0,
		tier = 0,
		deviceId = "phone_cheap",
		ownedDesks = {},
		workers = {},
		fractionalIncome = 0,
		nextOrganicContextId = "organic_snack",
		activeMission = nil,
		pendingPost = nil,
		ownPosts = {},
		recentOutcomes = {},
		saveStatus = "healthy",
	}
end

local function pcTier1Profile(): any
	local p = freshProfile()
	p.deviceId = "pc_rumah"
	p.lifetimeEarned = 350
	p.completedMissions = 3
	p.tier = 1
	p.balance = 1000
	return p
end

-- 1. Desk 1 gating: requires PC Rumah, Tier 1, and funds
test("Desk 1 gating requires PC Rumah and Tier 1", function()
	local pPhone = pcTier1Profile()
	pPhone.deviceId = "phone_fast"
	local rPhone = EconomyService.buyDesk(pPhone, 1)
	expectEqual(rPhone.ok, false, "phone cannot buy desk")
	expectEqual(rPhone.code, "NOT_READY", "code is NOT_READY")

	local pTier0 = pcTier1Profile()
	pTier0.lifetimeEarned = 250
	pTier0.completedMissions = 2
	pTier0.tier = 0
	local rTier0 = EconomyService.buyDesk(pTier0, 1)
	expectEqual(rTier0.ok, false, "tier 0 cannot buy desk")
	expectEqual(rTier0.code, "NOT_READY", "code is NOT_READY")
end)

-- 2. Desk 1 exact price: 180 Cuan debited, 179 refused
test("Desk 1 exact price is 180 Cuan and debits correctly", function()
	local pShort = pcTier1Profile()
	pShort.balance = 179
	local rShort = EconomyService.buyDesk(pShort, 1)
	expectEqual(rShort.ok, false, "179 cuan insufficient")
	expectEqual(rShort.code, "INSUFFICIENT_FUNDS", "code is INSUFFICIENT_FUNDS")

	local pExact = pcTier1Profile()
	pExact.balance = 180
	pExact.lifetimeEarned = 400
	local rExact = EconomyService.buyDesk(pExact, 1)
	expectEqual(rExact.ok, true, "180 cuan succeeds")
	expectEqual(rExact.profile.balance, 0, "balance reduced to 0")
	expectEqual(rExact.profile.lifetimeEarned, 400, "lifetime earned untouched")
	expectEqual(#rExact.profile.ownedDesks, 1, "desk 1 owned")
	expectEqual(rExact.profile.ownedDesks[1], 1, "slot index is 1")
end)

-- 3. Duplicate Desk 1 purchase refused
test("Duplicate Desk 1 purchase is refused with ALREADY_DONE", function()
	local p = pcTier1Profile()
	local r1 = EconomyService.buyDesk(p, 1)
	expectEqual(r1.ok, true, "first purchase succeeds")
	local r2 = EconomyService.buyDesk(r1.profile, 1)
	expectEqual(r2.ok, false, "second purchase refused")
	expectEqual(r2.code, "ALREADY_DONE", "code is ALREADY_DONE")
end)

-- 4. Desk 2 locked in BS-12
test("Desk 2 is locked in BS-12 because maxShippedDeskSlot is 1 and requires Tier 2", function()
	local p = pcTier1Profile()
	local r1 = EconomyService.buyDesk(p, 1)
	expectEqual(r1.ok, true, "desk 1 purchased")
	local r2 = EconomyService.buyDesk(r1.profile, 2)
	expectEqual(r2.ok, false, "desk 2 refused in M1/BS-12")
	expectEqual(r2.code, "NOT_READY", "desk 2 requires Tier 2")
end)

-- 5. Trainee 1 gating: requires Desk 1, PC Rumah, Tier 1, and funds
test("Trainee 1 gating requires Desk 1 owned first", function()
	local pNoDesk = pcTier1Profile()
	local rNoDesk = EconomyService.hireWorker(pNoDesk, 1, "trainee")
	expectEqual(rNoDesk.ok, false, "hiring without desk refused")
	expectEqual(rNoDesk.code, "NOT_READY", "code is NOT_READY")

	local pDesk = EconomyService.buyDesk(pcTier1Profile(), 1).profile
	pDesk.deviceId = "phone_fast"
	local rPhone = EconomyService.hireWorker(pDesk, 1, "trainee")
	expectEqual(rPhone.ok, false, "hiring without PC refused")
	expectEqual(rPhone.code, "NOT_READY", "code is NOT_READY")
end)

-- 6. Trainee 1 exact price: 500 debited, 499 refused
test("Trainee 1 exact price is 500 Cuan and debits correctly", function()
	local pDesk = EconomyService.buyDesk(pcTier1Profile(), 1).profile

	local pShort = EconomyService._deepCopy(pDesk)
	pShort.balance = 499
	local rShort = EconomyService.hireWorker(pShort, 1, "trainee")
	expectEqual(rShort.ok, false, "499 cuan insufficient")
	expectEqual(rShort.code, "INSUFFICIENT_FUNDS", "code is INSUFFICIENT_FUNDS")

	local pExact = EconomyService._deepCopy(pDesk)
	pExact.balance = 500
	pExact.lifetimeEarned = 500
	local rExact = EconomyService.hireWorker(pExact, 1, "trainee")
	expectEqual(rExact.ok, true, "500 cuan succeeds")
	expectEqual(rExact.profile.balance, 0, "balance reduced to 0")
	expectEqual(rExact.profile.lifetimeEarned, 500, "lifetime earned untouched")
	expectEqual(#rExact.profile.workers, 1, "worker hired")
	expectEqual(rExact.profile.workers[1].slotIndex, 1, "slot is 1")
	expectEqual(rExact.profile.workers[1].roleId, "trainee", "role is trainee")
end)

-- 7. Duplicate Trainee 1 hire refused
test("Duplicate Trainee 1 hire is refused with ALREADY_DONE", function()
	local pDesk = EconomyService.buyDesk(pcTier1Profile(), 1).profile
	local r1 = EconomyService.hireWorker(pDesk, 1, "trainee")
	expectEqual(r1.ok, true, "first hire succeeds")
	local r2 = EconomyService.hireWorker(r1.profile, 1, "trainee")
	expectEqual(r2.ok, false, "duplicate hire refused")
	expectEqual(r2.code, "ALREADY_DONE", "code is ALREADY_DONE")
end)

-- 8. Trainee 2 locked in BS-12
test("Trainee 2 is locked in BS-12 because slot 2 is not shipped and requires Tier 2", function()
	local pDesk = EconomyService.buyDesk(pcTier1Profile(), 1).profile
	local r1 = EconomyService.hireWorker(pDesk, 1, "trainee")
	expectEqual(r1.ok, true, "trainee 1 hired")
	local r2 = EconomyService.hireWorker(r1.profile, 2, "trainee")
	expectEqual(r2.ok, false, "trainee 2 refused")
	expectEqual(r2.code, "NOT_READY", "code is NOT_READY")
end)

-- 9. Single worker accrual: 1.5 Cuan/second
test("Single worker accrues exactly 1.5 Cuan/s online", function()
	local pDesk = EconomyService.buyDesk(pcTier1Profile(), 1).profile
	local pHired = EconomyService.hireWorker(pDesk, 1, "trainee").profile
	pHired.balance = 0
	pHired.fractionalIncome = 0

	local r = EconomyService.tick(pHired, 10)
	expectEqual(r.ok, true, "tick 10s succeeds")
	expectEqual(r.earned, 15, "10s * 1.5 Cuan/s = 15 Cuan")
	expectEqual(r.profile.balance, 15, "balance updated to 15")
	expectEqual(r.profile.fractionalIncome, 0, "residual is 0")
end)

-- 10. Fractional carry: 0.5 residual carry across ticks
test("Fractional income carries remainder [0, 1) without rounding error", function()
	local pDesk = EconomyService.buyDesk(pcTier1Profile(), 1).profile
	local pHired = EconomyService.hireWorker(pDesk, 1, "trainee").profile
	pHired.balance = 0
	pHired.fractionalIncome = 0

	-- 1 second at 1.5 Cuan/s: 1 credited, 0.5 carried
	local r1 = EconomyService.tick(pHired, 1)
	expectEqual(r1.earned, 1, "1 Cuan earned on first tick")
	expectEqual(r1.profile.balance, 1, "balance is 1")
	expectEqual(r1.profile.fractionalIncome, 0.5, "fractional residual is 0.5")

	-- Next 1 second at 1.5 Cuan/s: 0.5 + 1.5 = 2.0 credited, 0.0 carried
	local r2 = EconomyService.tick(r1.profile, 1)
	expectEqual(r2.earned, 2, "2 Cuan earned on second tick from carry")
	expectEqual(r2.profile.balance, 3, "cumulative balance is 3")
	expectEqual(r2.profile.fractionalIncome, 0.0, "fractional residual is 0.0")
end)

-- 11. Zero workers produce 0 Cuan
test("Zero workers produce 0 Cuan over time", function()
	local p = pcTier1Profile()
	p.balance = 100
	p.fractionalIncome = 0.25
	local r = EconomyService.tick(p, 60)
	expectEqual(r.ok, true, "tick succeeds")
	expectEqual(r.earned, nil, "no earnings")
	expectEqual(r.profile.balance, 100, "balance unchanged")
	expectEqual(r.profile.fractionalIncome, 0.25, "fractional income unchanged")
end)

-- 12. Rate scaling: 2 workers produce 3.0 Cuan/s
test("Two workers produce 3.0 Cuan/s via tickAtRate and incomePerSecond", function()
	local p = pcTier1Profile()
	table.insert(p.workers, { slotIndex = 1, roleId = "trainee" })
	table.insert(p.workers, { slotIndex = 2, roleId = "trainee" })
	expectEqual(EconomyService.incomePerSecond(p), 3.0, "two workers rate is 3.0")

	p.balance = 0
	p.fractionalIncome = 0
	local r = EconomyService.tick(p, 5)
	expectEqual(r.earned, 15, "5s * 3.0 Cuan/s = 15 Cuan")
	expectEqual(r.profile.balance, 15, "balance is 15")
end)

-- 13. WorldService.SyncWorkers mounts WorkerDesk1 and Trainee1
test("WorldService.SyncWorkers mounts WorkerDesk1 and Trainee1 at correct anchors", function()
	local fakePlayer = { UserId = 2001, Name = "BS12World" } :: any
	local p = pcTier1Profile()
	p.ownedDesks = { 1 }
	p.workers = { { slotIndex = 1, roleId = "trainee" } }

	local okSpawn, errSpawn = WorldService.Spawn(fakePlayer, p)
	expectTrue(okSpawn, `Spawn succeeds: {tostring(errSpawn)}`)

	local roomFolder = WorldService.GetRoom(fakePlayer)
	expectTrue(roomFolder ~= nil, "room folder exists")

	local deskSlot1 = WorldService.GetAnchor(fakePlayer, "WorkerDeskSlot1")
	expectTrue(deskSlot1 ~= nil, "WorkerDeskSlot1 anchor exists")
	local deskModel = deskSlot1:FindFirstChild("WorkerDesk1")
	expectTrue(deskModel ~= nil, "WorkerDesk1 mounted at WorkerDeskSlot1")

	local seat1 = WorldService.GetAnchor(fakePlayer, "WorkerSeat1")
	expectTrue(seat1 ~= nil, "WorkerSeat1 anchor exists")
	local traineeModel = seat1:FindFirstChild("Trainee1")
	expectTrue(traineeModel ~= nil, "Trainee1 mounted at WorkerSeat1")

	-- Clean removal
	WorldService.Remove(fakePlayer)
	expectTrue(WorldService.GetRoom(fakePlayer) == nil, "room cleaned up")
end)

-- 14. WorldService physical budget: <= 350 BaseParts total
test("Room with PCRumah, PhoneFast, WorkerDesk1, Trainee1 is strictly <= 350 BaseParts", function()
	local fakePlayer = { UserId = 2002, Name = "BS12Budget" } :: any
	local p = pcTier1Profile()
	p.deviceId = "pc_rumah"
	p.ownedDesks = { 1 }
	p.workers = { { slotIndex = 1, roleId = "trainee" } }

	WorldService.Spawn(fakePlayer, p)
	local partCount = WorldService.CountInRoom(fakePlayer, "BasePart")
	WorldService.Remove(fakePlayer)

	expectTrue(partCount <= 350, `total parts {partCount} must be <= 350`)
	expectTrue(partCount > 200, `total parts {partCount} must reflect full studio furnishing`)
end)

-- 15. Workers UI projection: accurate phases and block reasons
test("Workers.projectState projects correct operational phases", function()
	local stateLocked = {
		snapshot = freshProfile(),
	}
	local pLocked = Workers.projectState(stateLocked)
	expectEqual(pLocked.desk1Phase, "need_pc", "desk 1 needs PC Rumah when phone is starter")
	expectEqual(pLocked.trainee1Phase, "need_pc", "trainee 1 needs PC Rumah")

	local stateTier1NoMoney = {
		snapshot = pcTier1Profile(),
	}
	stateTier1NoMoney.snapshot.balance = 50
	local pNoMoney = Workers.projectState(stateTier1NoMoney)
	expectEqual(pNoMoney.desk1Phase, "locked", "desk 1 locked due to funds")
	expectEqual(pNoMoney.trainee1Phase, "need_desk", "trainee 1 needs desk first")

	local stateAffordable = {
		snapshot = pcTier1Profile(),
	}
	stateAffordable.snapshot.balance = 1000
	local pAffordable = Workers.projectState(stateAffordable)
	expectEqual(pAffordable.desk1Phase, "affordable", "desk 1 is affordable")
	expectEqual(pAffordable.trainee1Phase, "need_desk", "trainee 1 still needs desk")

	local stateDeskOwned = {
		snapshot = pcTier1Profile(),
	}
	stateDeskOwned.snapshot.balance = 600
	stateDeskOwned.snapshot.ownedDesks = { 1 }
	local pDeskOwned = Workers.projectState(stateDeskOwned)
	expectEqual(pDeskOwned.desk1Phase, "owned", "desk 1 is owned")
	expectEqual(pDeskOwned.trainee1Phase, "affordable", "trainee 1 is affordable")

	local stateHired = {
		snapshot = pcTier1Profile(),
	}
	stateHired.snapshot.ownedDesks = { 1 }
	stateHired.snapshot.workers = { { slotIndex = 1, roleId = "trainee" } }
	local pHired = Workers.projectState(stateHired)
	expectEqual(pHired.desk1Phase, "owned", "desk 1 is owned")
	expectEqual(pHired.trainee1Phase, "hired", "trainee 1 is hired")
end)

-- 16. ClientState mutation validation for BuyDesk and HireWorker
test("ClientState admits valid BuyDesk and HireWorker mutations and rejects invalid", function()
	local pDesk = pcTier1Profile()
	pDesk.balance = 1000
	pDesk.revision = 1
	pDesk.serverTime = 100
	local cState = ClientState.new(pDesk)
	cState:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "dash_test_12",
		state = pDesk,
		serverTime = 100,
		expiresAt = 9999,
	}, 100)
	cState:OnCameraOpened()

	-- Valid BuyDesk command
	local cmdDesk = cState:BeginMutation("BuyDesk", { slotIndex = 1 }, 100)
	expectTrue(cmdDesk ~= nil, "BuyDesk admitted")
	expectEqual(cmdDesk.action, "BuyDesk", "action matches")
	expectEqual(cmdDesk.payload.slotIndex, 1, "slotIndex matches")

	-- Simulate confirmed Desk purchase in state
	pDesk.ownedDesks = { 1 }
	pDesk.balance = 820
	pDesk.revision = 2
	cState:ApplyReply({ requestId = cmdDesk.requestId, ok = true, code = "OK", revision = 2, serverTime = 101 }, 101)
	cState:ApplyStateSnapshot(pDesk)

	-- Valid HireWorker command
	local cmdHire = cState:BeginMutation("HireWorker", { slotIndex = 1, roleId = "trainee" }, 101)
	expectTrue(cmdHire ~= nil, "HireWorker admitted")
	expectEqual(cmdHire.action, "HireWorker", "action matches")
	expectEqual(cmdHire.payload.slotIndex, 1, "slotIndex matches")
	expectEqual(cmdHire.payload.roleId, "trainee", "roleId matches")

	pDesk.revision = 3
	pDesk.workers = { { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 } }
	cState:ApplyReply({ requestId = cmdHire.requestId, ok = true, code = "OK", revision = 3, serverTime = 102 }, 102)
	cState:ApplyStateSnapshot(pDesk)

	-- Invalid slot 2 rejected
	local cmdSlot2 = cState:BeginMutation("BuyDesk", { slotIndex = 2 }, 102)
	expectTrue(cmdSlot2 == nil, "BuyDesk slot 2 rejected in BS-12")

	-- Invalid role rejected
	local cmdBoss = cState:BeginMutation("HireWorker", { slotIndex = 1, roleId = "boss" }, 103)
	expectTrue(cmdBoss == nil, "HireWorker invalid role rejected")
end)

test("Home follows shipped cheap fast and PC progression", function()
	local Desktop = require(uiFolder:WaitForChild("Desktop")) :: any
	local parent = Instance.new("Folder")
	local desktop = Desktop.new({ parent = parent, playerName = "Review", onClose = function() end, onTabSelected = function() end, getBlockReason = function() return nil end })
	local p = pcTier1Profile()
	p.deviceId = "phone_cheap"
	desktop:Update({ snapshot = p })
	expectTrue(string.find(desktop._homeUpgradeDesc.Text, "HP Cepat", 1, true) ~= nil, "cheap targets fast")
	p.deviceId = "phone_fast"
	desktop:Update({ snapshot = p })
	expectTrue(string.find(desktop._homeUpgradeDesc.Text, "PC Rumah", 1, true) ~= nil, "fast targets shipped PC")
	p.deviceId = "pc_rumah"
	desktop:Update({ snapshot = p })
	expectTrue(string.find(desktop._homeDeviceName.Text, "PC Rumah", 1, true) ~= nil, "PC equipped")
	expectTrue(string.find(desktop._homeDeviceNote.Text, "PC Rumah produces", 1, true) ~= nil, "PC is productive")
	expectEqual(string.find(desktop._homeUpgradeDesc.Text, "later milestone", 1, true), nil, "no stale future PC")
	desktop:Destroy()
	parent:Destroy()
end)

test("Workers pending accrual cannot fund purchases and reconciles only on snapshot", function()
	local parent = Instance.new("Folder")
	local view = Workers.new({ parent = parent, onAction = function() end })
	local p = pcTier1Profile()
	p.balance = 100
	p.pendingWorkerCuan = 1000
	p.incomePerSecond = 1.5
	view:Update({ snapshot = p })
	expectTrue(view._buyDeskButton.Size.Y.Offset >= 44 and view._hireWorkerButton.Size.Y.Offset >= 44, "worker action touch heights")
	expectEqual(view._projected.balance, 100, "pending excluded from wallet")
	expectEqual(view._projected.desk1Phase, "locked", "pending cannot buy desk")
	local before = view._overviewStats.Text
	view:Tick(100000)
	expectEqual(view._overviewStats.Text, before, "no local income prediction")
	expectTrue(string.find(before, "not spendable", 1, true) ~= nil, "pending distinction explicit")
	p.balance = 190
	p.pendingWorkerCuan = 0
	view:Update({ snapshot = p })
	expectEqual(view._projected.balance, 190, "confirmed bank reconciled")
	expectEqual(view._projected.pendingWorkerCuan, 0, "pending clears from server")
	expectEqual(view._projected.desk1Phase, "affordable", "confirmed funds buy desk")
	view:Destroy()
	parent:Destroy()
end)

test("Shipped slot caps reject Tier 2 eligible server requests", function()
	local cap = Catalog.Shipped.maxShippedTier
	Catalog.Shipped.maxShippedTier = 2
	local ok, err = pcall(function()
		local p = pcTier1Profile()
		p.lifetimeEarned = 2000
		p.completedMissions = 3
		p.balance = 10000
		p.ownedDesks = { 1 }
		p.workers = { { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 } }
		expectEqual(Rules.eligibleTier(p.lifetimeEarned, p.completedMissions, 2), 2, "fixture really qualifies for Tier 2")
		expectEqual(EconomyService.buyDesk(p, 2).code, "NOT_READY", "server rejects unshipped desk independently of tier")
		p.ownedDesks = { 1, 2 }
		expectEqual(EconomyService.hireWorker(p, 2, "trainee").code, "NOT_READY", "server rejects unshipped worker with all prerequisites")
		expectEqual(p.balance, 10000, "rejection cannot spend")
		expectEqual(#p.workers, 1, "rejection cannot hire")
	end)
	Catalog.Shipped.maxShippedTier = cap
	if not ok then error(err, 0) end
end)

test("Confirmed world sync preserves identities and removes revoked workers", function()
	local player = { Name = "BS12Sync", UserId = 2003 } :: any
	local p = pcTier1Profile()
	expectTrue(WorldService.Spawn(player, p), "spawn empty")
	p.ownedDesks = { 1 }
	p.workers = { { slotIndex = 1, roleId = "trainee" } }
	expectTrue(WorldService.Spawn(player, p), "existing room resync")
	local desk = WorldService.GetAnchor(player, "WorkerDeskSlot1"):FindFirstChild("WorkerDesk1")
	local seat = WorldService.GetAnchor(player, "WorkerSeat1")
	local marker = seat:FindFirstChild("Trainee1")
	expectTrue(desk ~= nil and marker ~= nil, "confirmed desk and worker mounted")
	expectTrue(marker:IsA("Folder"), "server only mounts a marker, not a simulated rig")
	expectTrue(WorldService.SyncWorkers(player, p.ownedDesks, p.workers), "sync repeated")
	expectEqual(seat:FindFirstChild("Trainee1"), marker, "same marker reused")
	expectEqual(WorldService.GetAnchor(player, "WorkerDeskSlot1"):FindFirstChild("WorkerDesk1"), desk, "same desk reused")
	expectTrue(WorldService.SyncWorkers(player, {}, {}), "remove revoked state")
	expectEqual(seat:FindFirstChild("Trainee1"), nil, "worker removed")
	WorldService.Remove(player)
end)

test("R15 cosmetic typing and head motion clean up without orphan rigs", function()
	local Controller = require(spScripts:WaitForChild("WorkerAnimationController")) :: any
	local prefab = ReplicatedStorage:WaitForChild("WorkerPrefabs"):WaitForChild("Trainee1") :: Model
	expectEqual(prefab:FindFirstChildOfClass("Humanoid").RigType, Enum.HumanoidRigType.R15, "real R15 rig")
	local motors = 0
	for _, child in ipairs(prefab:GetDescendants()) do if child:IsA("Motor6D") then motors += 1; expectTrue(child.Part0 ~= nil and child.Part1 ~= nil, "connected joint") end end
	expectEqual(motors, 15, "R15 articulated topology")
	for _, side in ipairs({ "Left", "Right" }) do
		local upper = prefab:FindFirstChild(side .. "UpperArm") :: BasePart
		local lower = prefab:FindFirstChild(side .. "LowerArm") :: BasePart
		local elbowA = upper.CFrame:PointToWorldSpace(Vector3.new(0, upper.Size.Y / 2, 0))
		local elbowB = lower.CFrame:PointToWorldSpace(Vector3.new(0, -lower.Size.Y / 2, 0))
		expectTrue((elbowA - elbowB).Magnitude < 0.02, "arm segments meet naturally")
	end
	local root = Instance.new("Folder")
	local seat = Instance.new("Part")
	seat.Parent = root
	local marker = Instance.new("Folder")
	marker.Name = "Trainee1"
	marker:SetAttribute("WorkerCosmetic", true)
	marker.Parent = seat
	local reduced = false
	local controller = Controller.new(root, prefab, function() return reduced end)
	local record = controller._records[marker]
	expectTrue(record ~= nil, "existing markers restored on start")
	local wrist = record.joints.RightWrist
	local neck = record.joints.Neck
	controller:Step(0.1)
	expectTrue(wrist.motor.C0 ~= wrist.base, "subtle typing moves wrist")
	controller:Step(9)
	expectTrue(neck.motor.C0 ~= neck.base, "occasional head glance")
	reduced = true
	controller:Step(0.1)
	expectEqual(wrist.motor.C0, wrist.base, "reduced motion restores pose")
	marker:Destroy()
	controller:Step(0)
	expectEqual(next(controller._records), nil, "removed marker frees record")
	controller:Destroy()
	controller:Destroy()
	expectEqual(#controller._connections, 0, "listeners disconnected idempotently")
	root:Destroy()
end)

-- Execute all tests in suite
local passed = 0
for _, t in ipairs(tests) do
	local ok, err = pcall(t.fn)
	if not ok then
		error(`[FAIL] {t.name}: {tostring(err)}`, 0)
	end
	passed += 1
end

return `{passed}/{#tests} passed`
