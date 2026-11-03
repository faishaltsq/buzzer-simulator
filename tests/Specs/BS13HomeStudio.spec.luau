--!strict
-- Buzzer Simulator — BS-13 spec: Second Workstation, Trainee 2, Home Studio chapter.
-- Validates (docs/04, BS-13 milestone):
-- Server economy
-- 1. Tier 2 requires lifetime >= 1600.
-- 2. Tier 2 still requires 3 claims.
-- 3. Slot 2 is shipped (caps 2/2/2) while V0/M1 baselines stay untouched.
-- 4. Desk 2 without Desk 1 refused (NOT_READY).
-- 5. Desk 2 without Trainee 1 refused (NOT_READY).
-- 6. Desk 2 before Tier 2 refused (NOT_READY).
-- 7. Desk 2 with 249 Cuan refused (INSUFFICIENT_FUNDS).
-- 8. Desk 2 purchase debits exactly 250.
-- 9. Duplicate Desk 2 refused (ALREADY_DONE).
-- 10. Trainee 2 without Desk 2 refused (NOT_READY).
-- 11. Trainee 2 with 749 Cuan refused (INSUFFICIENT_FUNDS).
-- 12. Trainee 2 hire debits exactly 750 and lifts incomePerSecond to 3.0.
-- 13. Duplicate Trainee 2 hire refused (ALREADY_DONE).
-- 14. A third worker is refused.
-- 15. Invalid role refused (INVALID_INPUT).
-- 16. Out-of-range slots refused (INVALID_INPUT).
-- Worker income
-- 17. One worker accrues exactly 1.5 Cuan/s.
-- 18. Two workers accrue exactly 3.0 Cuan/s.
-- 19. A healthy 30-second two-worker interval banks exactly 90 Cuan.
-- 20. Mixed one/two-worker intervals never re-rate earlier time (15 + 60 = 75).
-- 21. Fractional carry stays exact at the two-worker rate.
-- 22. No wall-clock/offline income: pending stays 0 without connected Advance.
-- 23. A failed bank write leaves confirmed balance untouched (nonspendable).
-- 24. Successive banks credit each 30s window exactly once.
-- 25. An ambiguous committed bank never duplicates the credit.
-- 26. Rejoin preserves both hires, ownership, tier and confirmed balance.
-- World presentation
-- 27. Desk 2 mounts at WorkerDeskSlot2.
-- 28. Trainee 2 marker mounts at WorkerSeat2.
-- 29. SyncWorkers is idempotent (same instances reused).
-- 30. Repeated Spawn never duplicates markers or desks.
-- 31. Removed presentation is recreated from confirmed state.
-- 32. Client cosmetic rigs mount independently per slot and clean up.
-- 33. Both cosmetic rigs stay separate and pivot-aligned to their seats.
-- 34. Full two-worker studio stays <= 350 server BaseParts.
-- UI / progression
-- 35. Desk 2 shows locked before Tier 2 with prerequisites met.
-- 36. Desk 2 shows affordable when Tier 2 unlocks.
-- 37. Trainee 2 shows need_desk before Desk 2.
-- 38. Confirmed wallet deduction surfaces after purchase.
-- 39. Pending accrual stays nonspendable in desk projections.
-- 40. Overview shows "2 / 2" staff and "+3.0 Cuan/s".
-- 41. Chapter incomplete before Trainee 2.
-- 42. Chapter completes after confirmed Trainee 2.
-- 43. Post-completion state keeps earning and closes repeat purchases.
-- 44. Touch targets >= 44px and wrapped labels for mobile.

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
		propertyId = "bedroom",
		ownedDesks = {},
		workers = {},
		fractionalIncome = 0,
		claimedRunIdsWindow = {},
		recentMutationOutcomes = {},
		missionVariantCounters = {},
		nextOrganicSequence = 0,
		nextPostSequence = 1,
		activeMission = nil,
		pendingPost = nil,
		ownPosts = {},
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

-- Tier-2-eligible data with Desk 1 and Trainee 1 already owned so only the
-- slot-2 gates are under test. Purchases never touch lifetime, so seeding
-- 1650 keeps the profile tier-2-eligible through the whole ladder.
-- `balance` = confirmed Cuan REMAINING after the fixture purchases.
local function tier2OneWorkerProfile(balance: number?): any
	local p = pcTier1Profile()
	p.lifetimeEarned = 1650
	-- Snapshot tier is server-derived; mirror the derivation for projections.
	p.tier = 2
	p.balance = (if balance ~= nil then balance else 1320) + 180 + 500
	local r = EconomyService.buyDesk(p, 1)
	expectTrue(r.ok, "fixture desk 1")
	r = EconomyService.hireWorker(r.profile, 1, "trainee")
	expectTrue(r.ok, "fixture trainee 1")
	return r.profile
end

local function fullStudioProfile(balance: number?): any
	-- `balance` = confirmed Cuan remaining after ALL slot-2 purchases. The
	-- tier-2 fixture already budgets desk 1/trainee 1 (+180/+500), so only the
	-- slot-2 prices are added here.
	local start = (if balance ~= nil then balance else 320) + 250 + 750
	local r = EconomyService.buyDesk(tier2OneWorkerProfile(start), 2)
	expectTrue(r.ok, "fixture desk 2")
	r = EconomyService.hireWorker(r.profile, 2, "trainee")
	expectTrue(r.ok, "fixture trainee 2")
	-- Derived tier mirrors the server's Rules.eligibleTier projection.
	r.profile.tier = Rules.eligibleTier(r.profile.lifetimeEarned, r.profile.completedMissions, Catalog.Shipped.maxShippedTier)
	return r.profile
end

-- ===== 1-2. Tier 2 thresholds =====
test("Tier 2 requires at least 1600 lifetime Cuan", function()
	expectEqual(Rules.eligibleTier(1599, 3, 2), 1, "1599 lifetime is still tier 1")
	expectEqual(Rules.eligibleTier(1600, 3, 2), 2, "1600 lifetime unlocks tier 2")
end)

test("Tier 2 still requires 3 completed claims", function()
	-- claimsRequired = 3 applies at every tier, so 2 claims reach tier 0 only.
	expectEqual(Rules.eligibleTier(5000, 2, 2), 0, "2 claims cannot reach any tier")
	expectEqual(Rules.eligibleTier(1600, 3, 2), 2, "3 claims with 1600 lifetime reach tier 2")
end)

-- ===== 3. Shipped configuration =====
test("BS-13 ships tier/desk/worker caps at 2/2/2 and preserves V0/M1 baselines", function()
	local shipped = Catalog.Shipped
	expectEqual(shipped.maxShippedTier, 2, "maxShippedTier shipped")
	expectEqual(shipped.maxShippedDeskSlot, 2, "maxShippedDeskSlot shipped")
	expectEqual(shipped.maxShippedWorkerSlot, 2, "maxShippedWorkerSlot shipped")
	expectEqual(Catalog.V0Shipped.maxShippedTier, 0, "V0 baseline untouched")
	expectEqual(Catalog.M1Shipped.maxShippedTier, 1, "M1 baseline untouched")
	expectEqual(Catalog.M1Shipped.maxShippedDeskSlot, 1, "M1 desk baseline untouched")
	expectEqual(Catalog.M1Shipped.maxShippedWorkerSlot, 1, "M1 worker baseline untouched")
	-- Approved prices and rates are unchanged.
	expectEqual(Catalog.DeskPrices[2], 250, "desk 2 price")
	expectEqual(Catalog.HirePrices[2], 750, "trainee 2 price")
	expectEqual(Catalog.WorkerRatePerWorker, 1.5, "per-worker rate")
end)

-- ===== 4-9. Desk 2 purchase gates =====
test("Desk 2 without Desk 1 is refused NOT_READY", function()
	local p = pcTier1Profile()
	p.lifetimeEarned = 1650
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.ok, false, "desk 2 without desk 1 refused")
	expectEqual(r.code, "NOT_READY", "code is NOT_READY")
	expectEqual(p.balance, 1000, "rejection spends nothing")
end)

test("Desk 2 without Trainee 1 is refused NOT_READY", function()
	local p = tier2OneWorkerProfile()
	p.workers = {}
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.ok, false, "desk 2 without trainee 1 refused")
	expectEqual(r.code, "NOT_READY", "code is NOT_READY (docs/04 line 42 gate)")
	expectEqual(p.balance, 1320, "rejection spends nothing")
end)

test("Desk 2 before Tier 2 is refused NOT_READY", function()
	local p = pcTier1Profile()
	local r1 = EconomyService.buyDesk(p, 1)
	expectTrue(r1.ok, "desk 1 owned")
	local r2 = EconomyService.hireWorker(r1.profile, 1, "trainee")
	expectTrue(r2.ok, "trainee 1 hired")
	local r3 = EconomyService.buyDesk(r2.profile, 2)
	expectEqual(r3.code, "NOT_READY", "tier 1 cannot buy desk 2")
end)

test("Desk 2 with 249 Cuan is refused INSUFFICIENT_FUNDS", function()
	local p = tier2OneWorkerProfile(249)
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.ok, false, "249 Cuan cannot buy desk 2")
	expectEqual(r.code, "INSUFFICIENT_FUNDS", "code is INSUFFICIENT_FUNDS")
end)

test("Desk 2 purchase debits exactly 250 Cuan", function()
	local p = tier2OneWorkerProfile(1000)
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.ok, true, "desk 2 purchased")
	expectEqual(r.profile.balance, 750, "balance 1000 -> 750")
	expectEqual(r.profile.lifetimeEarned, 1650, "lifetime untouched by spending")
	expectEqual(r.profile.ownedDesks[1], 1, "slot 1 preserved")
	expectEqual(r.profile.ownedDesks[2], 2, "slot 2 added")
end)

test("Duplicate Desk 2 purchase is refused with ALREADY_DONE", function()
	local p = fullStudioProfile(2000)
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.ok, false, "second desk 2 purchase refused")
	expectEqual(r.code, "ALREADY_DONE", "code is ALREADY_DONE")
end)

-- ===== 10-16. Trainee 2 hire gates =====
test("Trainee 2 without Desk 2 is refused NOT_READY", function()
	local p = tier2OneWorkerProfile(2000)
	local r = EconomyService.hireWorker(p, 2, "trainee")
	expectEqual(r.ok, false, "hire without desk 2 refused")
	expectEqual(r.code, "NOT_READY", "code is NOT_READY")
	expectEqual(#p.workers, 1, "rejection hires nothing")
end)

test("Trainee 2 with 749 Cuan is refused INSUFFICIENT_FUNDS", function()
	local p = tier2OneWorkerProfile()
	local r = EconomyService.buyDesk(p, 2)
	expectTrue(r.ok, "desk 2 purchased first")
	local short = r.profile
	short.balance = 749
	local r2 = EconomyService.hireWorker(short, 2, "trainee")
	expectEqual(r2.ok, false, "749 Cuan cannot hire trainee 2")
	expectEqual(r2.code, "INSUFFICIENT_FUNDS", "code is INSUFFICIENT_FUNDS")
end)

test("Trainee 2 hire debits exactly 750 and incomePerSecond becomes 3.0", function()
	local p = tier2OneWorkerProfile(1000)
	local deskR = EconomyService.buyDesk(p, 2)
	expectEqual(deskR.profile.balance, 750, "250 reserved for desk 2")
	local r = EconomyService.hireWorker(deskR.profile, 2, "trainee")
	expectEqual(r.ok, true, "trainee 2 hired")
	expectEqual(r.profile.balance, 0, "750 debited")
	expectEqual(#r.profile.workers, 2, "two workers on duty")
	expectEqual(r.profile.workers[2].slotIndex, 2, "worker 2 at slot 2")
	expectEqual(r.profile.workers[2].roleId, "trainee", "role is trainee")
	expectEqual(r.profile.workers[1].slotIndex, 1, "worker 1 preserved")
	expectEqual(EconomyService.incomePerSecond(r.profile), 3.0, "two-worker rate")
end)

test("Duplicate Trainee 2 hire is refused with ALREADY_DONE", function()
	local p = fullStudioProfile(2000)
	local r = EconomyService.hireWorker(p, 2, "trainee")
	expectEqual(r.ok, false, "second slot-2 hire refused")
	expectEqual(r.code, "ALREADY_DONE", "code is ALREADY_DONE")
	expectEqual(#p.workers, 2, "no third worker created")
end)

test("A third worker is refused even against a synthetic vacant slot", function()
	-- Two worker records already exist but slot 2 is vacant in this synthetic
	-- fixture; the hard cap must still refuse a third hire.
	local p = fullStudioProfile()
	p.workers = {
		{ hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 },
		{ hireId = "ghost", roleId = "trainee", slotIndex = 1 },
	}
	local r = EconomyService.hireWorker(p, 2, "trainee")
	expectEqual(r.ok, false, "third worker refused")
	expectEqual(r.code, "NOT_READY", "code is NOT_READY (MAX_WORKERS=2)")
	expectEqual(#p.workers, 2, "rejection creates no worker")
end)

test("Invalid role is refused with INVALID_INPUT", function()
	local p = fullStudioProfile(2000)
	local r = EconomyService.hireWorker(p, 2, "manager")
	expectEqual(r.ok, false, "non-trainee role refused")
	expectEqual(r.code, "INVALID_INPUT", "code is INVALID_INPUT")
end)

test("Out-of-range slots are refused with INVALID_INPUT", function()
	local p = fullStudioProfile(2000)
	expectEqual(EconomyService.hireWorker(p, 3, "trainee").code, "INVALID_INPUT", "hire slot 3")
	expectEqual(EconomyService.hireWorker(p, 0, "trainee").code, "INVALID_INPUT", "hire slot 0")
	expectEqual(EconomyService.buyDesk(p, 3).code, "INVALID_INPUT", "buy slot 3")
	expectEqual(EconomyService.buyDesk(p, 1.5).code, "INVALID_INPUT", "fractional slot")
end)

-- ===== 17-21. Worker income =====
test("One worker accrues exactly 1.5 Cuan/s", function()
	local p = tier2OneWorkerProfile()
	expectEqual(EconomyService.incomePerSecond(p), 1.5, "one-worker rate")
	local r = EconomyService.tick(p, 10)
	expectEqual(r.earned, 15, "10s * 1.5 = 15")
	expectEqual(r.profile.balance, 1335, "credited to balance (1320 + 15)")
end)

test("Two workers accrue exactly 3.0 Cuan/s", function()
	local p = fullStudioProfile()
	expectEqual(EconomyService.incomePerSecond(p), 3.0, "two-worker rate")
	local r = EconomyService.tick(p, 10)
	expectEqual(r.earned, 30, "10s * 3.0 = 30")
end)

test("A healthy 30-second two-worker interval banks exactly 90 Cuan", function()
	local p = fullStudioProfile()
	p.balance = 0
	p.fractionalIncome = 0
	local r = EconomyService.tick(p, 30)
	expectEqual(r.earned, 90, "30s * 3.0 = 90")
	expectEqual(r.profile.balance, 90, "banked to confirmed balance")
	expectEqual(r.profile.fractionalIncome, 0, "no residual after exact window")
end)

test("Mixed one/two-worker intervals keep historical rates (15 + 60 = 75)", function()
	local p = tier2OneWorkerProfile()
	local deskR = EconomyService.buyDesk(p, 2)
	expectTrue(deskR.ok, "desk 2 purchased for the mixed-rate sequence")
	local board = deskR.profile
	board.balance = 0
	board.fractionalIncome = 0
	local first = EconomyService.tick(board, 10)
	expectEqual(first.earned, 15, "10s at one-worker 1.5/s = 15")
	-- Refund the hire price for the slot-2 purchase (fixture funds are the
	-- post-fixture remaining, spent on nothing else in this sequence).
	first.profile.balance = 750
	-- Hire trainee 2; the earlier interval must never re-rate.
	local hire = EconomyService.hireWorker(first.profile, 2, "trainee")
	expectEqual(hire.ok, true, "trainee 2 hired")
	hire.profile.balance = 0
	hire.profile.fractionalIncome = 0
	local second = EconomyService.tick(hire.profile, 20)
	expectEqual(second.earned, 60, "20s at two-worker 3.0/s = 60")
	-- Segment equivalence via tickAtRate (SessionService's mechanism).
	local segA = EconomyService.tickAtRate(freshProfile(), 10, 1.5)
	local segB = EconomyService.tickAtRate(segA.profile, 20, 3.0)
	expectEqual(segA.earned + segB.earned, 75, "segmented accrual totals 75")
end)

test("Fractional carry stays exact at the two-worker rate", function()
	local p = fullStudioProfile()
	p.balance = 0
	p.fractionalIncome = 0
	local r1 = EconomyService.tick(p, 0.5)
	expectEqual(r1.earned, 1, "0.5s * 3.0 = 1.5 -> credits 1")
	expectEqual(r1.profile.fractionalIncome, 0.5, "residual 0.5 carried")
	local r2 = EconomyService.tick(r1.profile, 0.5)
	expectEqual(r2.earned, 2, "0.5 + 1.5 = 2.0 -> credits 2")
	expectEqual(r2.profile.fractionalIncome, 0, "residual cleared")
end)

-- ===== Session-level behaviors (22-26) =====
-- Fake adapters mirror tests/Specs/SessionService.spec.luau so the BS-13 suite
-- is self-contained: value-based JSON, deterministic GUIDs, injectable write
-- failures and ambiguous responses.

local function makeClock(start: number): (() -> number, (number) -> ())
	local t = start
	return function()
		return t
	end, function(dt: number)
		t += dt
	end
end

local FakeStore: any = {}
FakeStore.__index = FakeStore
function FakeStore.new()
	local self = setmetatable({}, FakeStore)
	self.data = {} :: { [string]: any }
	self.updateCalls = 0
	self.getCalls = 0
	self.freshGetCalls = 0
	self.failUpdate = false
	self.ambiguousOnce = false
	self._attempts = 0
	self._committed = {} :: { [string]: number }
	return self
end

function FakeStore:GetAsync(key: string, options: any?)
	local s: any = self
	s.getCalls += 1
	if options ~= nil and options.UseCache == false then
		s.freshGetCalls += 1
	end
	return s.data[key]
end

function FakeStore:UpdateAsync(key: string, transform: (any) -> any)
	local s: any = self
	s.updateCalls += 1
	s._attempts += 1
	if s.failUpdate then
		error("FakeStore: injected write failure", 0)
	end
	if s.ambiguousOnce then
		s.ambiguousOnce = false
		local old = s.data[key]
		local result = transform(old)
		if result ~= nil then
			s.data[key] = result
			s._committed[key] = (s._committed[key] or 0) + 1
		end
		error("FakeStore: ambiguous success (response lost)", 0)
	end
	local old = s.data[key]
	local result = transform(old)
	if result == nil then
		return nil
	end
	s.data[key] = result
	s._committed[key] = (s._committed[key] or 0) + 1
	return result
end

function FakeStore:RemoveAsync(key: string)
	local s: any = self
	s.data[key] = nil
end

local FakeHttp = {}
local guidCounter = 0
function FakeHttp:GenerateGUID(_skipParentheses: boolean?): string
	guidCounter += 1
	return `guid-{guidCounter}`
end

local function jsonEncode(v: any): string
	local t = typeof(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return if v then "true" else "false"
	elseif t == "number" then
		if v ~= v then
			return "null"
		elseif v == math.huge then
			return "1e999"
		elseif v == -math.huge then
			return "-1e999"
		end
		return string.format("%.17g", v)
	elseif t == "string" then
		return string.format("%q", v)
	elseif t == "table" then
		local keys: { string } = {}
		for k in pairs(v) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, k in ipairs(keys) do
			table.insert(parts, string.format("%q:%s", k, jsonEncode(v[k])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("jsonEncode: unsupported type", 0)
end

function FakeHttp:JSONEncode(v: any): string
	return jsonEncode(v)
end

local function seedEnvelope(store: any, profile: any, revision: number)
	local data: any = store.data
	data["Player_1234"] = {
		schemaVersion = 1,
		revision = revision,
		lastSaveOpId = "init",
		updatedAt = 1000,
		profile = profile,
		lease = { token = "", jobId = "seed", expiresAt = 0 },
	}
end

local function newSession(store: any, clock: () -> number): any
	return SessionService.new({
		userId = 1234,
		store = store,
		httpService = FakeHttp,
		noCacheOptions = function()
			return { UseCache = false }
		end,
		jobId = "job-bs13",
		now = clock,
		wait = function(_s: number) end,
	})
end

local function startSession(store: any, clock: () -> number): any
	local session = newSession(store, clock)
	local start = session:Start()
	expectTrue(
		start.ok == true,
		`session started: code={tostring(start and start.code)} detail={tostring(start and start.detail)}`
	)
	return session
end

test("No offline income: pending stays 0 without connected Advance", function()
	local store = FakeStore.new()
	local clock, setTime = makeClock(5000)
	local p = fullStudioProfile(320)
	p.lifetimeEarned = 2270
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	expectEqual(session:GetPendingWorkerCuan(), 0, "fresh load has no pending accrual")
	-- Two workers idle while the wall clock races forward 60 transfer minutes.
	setTime(3600)
	expectEqual(session:GetPendingWorkerCuan(), 0, "wall-clock drift accrues nothing")
	expectEqual(session:GetConfirmedProfile().balance, 320, "offline time credits nothing")
	expectEqual(session:GetConfirmedProfile().lifetimeEarned, 2270, "lifetime unchanged offline")
end)

test("A failed bank write leaves confirmed balance untouched", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, fullStudioProfile(0), 1)
	local session = startSession(store, clock)
	session:Advance(25)
	expectEqual(session:GetPendingWorkerCuan(), 75, "25s at 3.0 accrues 75 pending (not spendable)")
	expectEqual(session:GetConfirmedProfile().balance, 0, "confirmed wallet does not include pending")
	store.failUpdate = true
	local result = session:Advance(30)
	expectTrue(result ~= nil, "advance call returns")
	expectEqual(session:GetConfirmedProfile().balance, 0, "failed bank never credits spendable Cuan")
	-- The window survives the failed write and credits exactly once on recovery.
	store.failUpdate = false
	session:Advance(0.01)
	expectEqual(session:GetConfirmedProfile().balance, 165, "55s at 3.0 credited exactly once")
	expectEqual(session:GetPendingWorkerCuan(), 0, "nothing left pending")
end)

test("Successive banks credit each 30s window exactly once", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, fullStudioProfile(0), 1)
	local session = startSession(store, clock)
	local first = session:Advance(30)
	expectTrue(first.ok, "first window banks")
	expectEqual(session:GetConfirmedProfile().balance, 90, "first 30s banks 90")
	expectEqual(session:GetPendingWorkerCuan(), 0, "pending drains after the bank")
	local second = session:Advance(30)
	expectTrue(second.ok, "second window banks")
	expectEqual(session:GetConfirmedProfile().balance, 180, "second window adds exactly 90, not 180")
	expectEqual(session:GetPendingWorkerCuan(), 0, "no residual duplication")
end)

test("An ambiguous committed bank never duplicates the credit", function()
	-- The 10s piggyback write commits but its response is lost. Exactly one
	-- 30-Cuan credit may exist, and the next interval adds only its own value.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, fullStudioProfile(0), 1)
	local session = startSession(store, clock)
	session:Advance(10)
	expectEqual(session:GetPendingWorkerCuan(), 30, "10s at 3.0 = 30 pending")
	store.ambiguousOnce = true
	local renew = session:RenewLease()
	expectTrue(renew ~= nil, "renewal call returns")
	local durableBalance = (store.data["Player_1234"].profile :: any).balance
	expectTrue(durableBalance <= 30, "an ambiguous write never exceeds one credit")
	session:Advance(10)
	expectTrue(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan() <= 60,
		"two intervals never exceed 60"
	)
end)

test("Rejoin preserves both hires, ownership, tier and confirmed balance", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = fullStudioProfile(320)
	p.lifetimeEarned = 2270
	seedEnvelope(store, p, 1)
	-- First session banks one healthy window.
	local session = startSession(store, clock)
	session:Advance(30)
	expectEqual(session:GetConfirmedProfile().balance, 410, "320 + 90 banked")
	-- Graceful stop releases the lease; final banking stays inside the profile.
	local stop = session:Stop()
	expectTrue(stop ~= nil, "stop acknowledged")
	-- Rejoin on a later clock: everything confirmed must survive exactly.
	local session2 = startSession(store, makeClock(5000 + 400))
	local snap = session2:Snapshot()
	local profile = snap.snapshot
	expectEqual(#profile.workers, 2, "both hires preserved")
	expectEqual(profile.workers[1].slotIndex, 1, "worker 1 slot intact")
	expectEqual(profile.workers[2].slotIndex, 2, "worker 2 slot intact")
	expectEqual(profile.ownedDesks[1], 1, "desk 1 persisted")
	expectEqual(profile.ownedDesks[2], 2, "desk 2 persisted")
	expectEqual(profile.balance, 410, "confirmed balance persisted without duplication")
	expectEqual(profile.lifetimeEarned, 2360, "lifetime intact (2270 + 90)")
	expectEqual(profile.tier, 2, "tier 2 restored")
	expectEqual(profile.incomePerSecond, 3.0, "two-worker rate on rejoin")
	expectEqual(profile.pendingWorkerCuan, 0, "no offline income between sessions")
end)

-- ===== 27-34. World presentation =====
local function spawnFullStudio(userId: number, name: string): any
	local player = { UserId = userId, Name = name } :: any
	local p = fullStudioProfile(320)
	p.deviceId = "pc_rumah"
	expectTrue(WorldService.Spawn(player, p), "world spawned")
	return player
end

test("Desk 2 mounts at WorkerDeskSlot2", function()
	local player = spawnFullStudio(3013, "BS13Desk2")
	local anchor = WorldService.GetAnchor(player, "WorkerDeskSlot2")
	expectTrue(anchor ~= nil, "WorkerDeskSlot2 anchor exists")
	expectTrue(anchor:FindFirstChild("WorkerDesk2") ~= nil, "WorkerDesk2 mounted at slot 2")
	WorldService.Remove(player)
end)

test("Trainee 2 marker mounts at WorkerSeat2", function()
	local player = spawnFullStudio(3014, "BS13Trainee2")
	local seat = WorldService.GetAnchor(player, "WorkerSeat2")
	expectTrue(seat ~= nil, "WorkerSeat2 anchor exists")
	local marker = seat:FindFirstChild("Trainee2")
	expectTrue(marker ~= nil, "Trainee2 marker at slot 2")
	expectTrue(marker:IsA("Folder"), "server mounts a cosmetic marker, not a simulated rig")
	expectEqual(marker:GetAttribute("WorkerCosmetic"), true, "marker carries WorkerCosmetic attribute")
	WorldService.Remove(player)
end)

test("SyncWorkers is idempotent for the full studio", function()
	local player = spawnFullStudio(3015, "BS13Idempotent")
	local p = fullStudioProfile(320)
	local seat1 = WorldService.GetAnchor(player, "WorkerSeat1")
	local seat2 = WorldService.GetAnchor(player, "WorkerSeat2")
	local marker1 = seat1:FindFirstChild("Trainee1")
	local marker2 = seat2:FindFirstChild("Trainee2")
	local desk1 = WorldService.GetAnchor(player, "WorkerDeskSlot1"):FindFirstChild("WorkerDesk1")
	local desk2 = WorldService.GetAnchor(player, "WorkerDeskSlot2"):FindFirstChild("WorkerDesk2")
	expectTrue(WorldService.SyncWorkers(player, p.ownedDesks, p.workers), "resync ok")
	expectEqual(seat1:FindFirstChild("Trainee1"), marker1, "trainee 1 marker reused")
	expectEqual(seat2:FindFirstChild("Trainee2"), marker2, "trainee 2 marker reused")
	expectEqual(WorldService.GetAnchor(player, "WorkerDeskSlot1"):FindFirstChild("WorkerDesk1"), desk1, "desk 1 reused")
	expectEqual(WorldService.GetAnchor(player, "WorkerDeskSlot2"):FindFirstChild("WorkerDesk2"), desk2, "desk 2 reused")
	WorldService.Remove(player)
end)

test("Repeated Spawn never duplicates markers or desks", function()
	local player = spawnFullStudio(3016, "BS13SpawnDup")
	local p = fullStudioProfile(320)
	expectTrue(WorldService.Spawn(player, p), "respawn ok")
	local seat1 = WorldService.GetAnchor(player, "WorkerSeat1")
	local seat2 = WorldService.GetAnchor(player, "WorkerSeat2")
	local count1, count2 = 0, 0
	for _, child in ipairs(seat1:GetChildren()) do
		if child.Name == "Trainee1" then count1 += 1 end
	end
	for _, child in ipairs(seat2:GetChildren()) do
		if child.Name == "Trainee2" then count2 += 1 end
	end
	expectEqual(count1, 1, "single trainee 1 marker")
	expectEqual(count2, 1, "single trainee 2 marker")
	local desks = 0
	for _, child in ipairs(WorldService.GetAnchor(player, "WorkerDeskSlot2"):GetChildren()) do
		if child.Name == "WorkerDesk2" then desks += 1 end
	end
	expectEqual(desks, 1, "single desk 2 model")
	WorldService.Remove(player)
end)

test("Removed presentation is recreated from confirmed state", function()
	local player = spawnFullStudio(3017, "BS13Recreate")
	local p = fullStudioProfile(320)
	local desk2 = WorldService.GetAnchor(player, "WorkerDeskSlot2"):FindFirstChild("WorkerDesk2")
	local marker2 = WorldService.GetAnchor(player, "WorkerSeat2"):FindFirstChild("Trainee2")
	desk2:Destroy()
	marker2:Destroy()
	expectTrue(WorldService.SyncWorkers(player, p.ownedDesks, p.workers), "resync ok")
	expectTrue(WorldService.GetAnchor(player, "WorkerDeskSlot2"):FindFirstChild("WorkerDesk2") ~= nil, "desk 2 recreated")
	expectTrue(WorldService.GetAnchor(player, "WorkerSeat2"):FindFirstChild("Trainee2") ~= nil, "trainee 2 recreated")
	WorldService.Remove(player)
end)

test("Client cosmetic rigs mount independently per slot and clean up", function()
	local Controller = require(spScripts:WaitForChild("WorkerAnimationController")) :: any
	local prefabs = ReplicatedStorage:WaitForChild("WorkerPrefabs") :: any
	for _, name in ipairs({ "Trainee1", "Trainee2" }) do
		local prefab = prefabs:WaitForChild(name) :: Model
		local humanoid = prefab:FindFirstChildOfClass("Humanoid")
		expectTrue(humanoid ~= nil, `{name} humanoid present`)
		expectEqual(humanoid.RigType, Enum.HumanoidRigType.R15, `{name} is R15`)
	end
	local root = Instance.new("Folder")
	local seat1 = Instance.new("Part")
	seat1.CFrame = CFrame.new(0, 0, 0)
	seat1.Parent = root
	local seat2 = Instance.new("Part")
	seat2.CFrame = CFrame.new(10, 0, 4)
	seat2.Parent = root
	for index, seat in ipairs({ seat1, seat2 }) do
		local marker = Instance.new("Folder")
		marker.Name = `Trainee{index}`
		marker:SetAttribute("WorkerCosmetic", true)
		marker.Parent = seat
	end
	local controller = Controller.new(root, prefabs, nil)
	expectTrue(controller._records[seat1:FindFirstChild("Trainee1")] ~= nil, "slot 1 rig mounted")
	expectTrue(controller._records[seat2:FindFirstChild("Trainee2")] ~= nil, "slot 2 rig mounted")
	local model1 = controller._records[seat1:FindFirstChild("Trainee1")].model
	local marker2 = seat2:FindFirstChild("Trainee2")
	local model2 = controller._records[marker2].model
	expectTrue(model1 ~= model2, "independent rig instances")
	expectTrue((model2:GetPivot().Position - seat2.CFrame.Position).Magnitude < 0.01, "rig 2 aligned to seat 2")
	-- Removal of one marker cleans exactly its own record and keeps the other.
	marker2:Destroy()
	controller:Step(0)
	expectEqual(controller._records[marker2], nil, "record 2 freed")
	expectTrue(model2.Parent == nil, "rig 2 instance destroyed")
	expectTrue(controller._records[seat1:FindFirstChild("Trainee1")] ~= nil, "rig 1 untouched")
	controller:Destroy()
	expectEqual(next(controller._records), nil, "destroy frees all records")
	root:Destroy()
end)

test("Both cosmetic rigs stay separate, distinct and pivot-aligned", function()
	local Controller = require(spScripts:WaitForChild("WorkerAnimationController")) :: any
	local prefabs = ReplicatedStorage:WaitForChild("WorkerPrefabs") :: any
	local root = Instance.new("Folder")
	local seats = {}
	local markers = {}
	for index, position in ipairs({ Vector3.new(0, 0, 0), Vector3.new(-7.5, 0, 6) }) do
		local seat = Instance.new("Part")
		seat.CFrame = CFrame.new(position)
		seat.Parent = root
		local marker = Instance.new("Folder")
		marker.Name = `Trainee{index}`
		marker:SetAttribute("WorkerCosmetic", true)
		marker.Parent = seat
		table.insert(seats, seat)
		table.insert(markers, marker)
	end
	local controller = Controller.new(root, prefabs, nil)
	local rig1 = controller._records[markers[1]].model
	local rig2 = controller._records[markers[2]].model
	expectTrue((rig1:GetPivot().Position - seats[1].CFrame.Position).Magnitude < 0.01, "rig 1 on seat 1")
	expectTrue((rig2:GetPivot().Position - seats[2].CFrame.Position).Magnitude < 0.01, "rig 2 on seat 2")
	-- Independent rig instances with per-slot phase offsets; separate joints.
	local joint1 = controller._records[markers[1]].joints.RightWrist
	local joint2 = controller._records[markers[2]].joints.RightWrist
	expectTrue(joint1 ~= nil and joint2 ~= nil, "both rigs articulated")
	expectTrue(joint1.motor ~= joint2.motor, "joints belong to separate rigs")
	expectTrue(joint1.motor.Parent ~= joint2.motor.Parent, "no shared rig parts")
	controller:Destroy()
	root:Destroy()
end)

test("Full two-worker studio stays <= 350 server BaseParts", function()
	local player = spawnFullStudio(3018, "BS13Budget")
	local partCount = WorldService.CountInRoom(player, "BasePart")
	WorldService.Remove(player)
	expectTrue(partCount <= 350, `total parts {partCount} must be <= 350`)
	expectTrue(partCount > 250, `total parts {partCount} must include the second workstation`)
end)

-- ===== 35-44. UI and progression =====
test("Desk 2 shows locked before Tier 2 with prerequisites met", function()
	local state = { snapshot = pcTier1Profile() }
	state.snapshot.ownedDesks = { 1 }
	state.snapshot.workers = { { hireId = "t1", roleId = "trainee", slotIndex = 1 } }
	state.snapshot.balance = 1000
	local proj = Workers.projectState(state)
	expectEqual(proj.deskPhase[2], "need_tier", "slot 2 waits for tier 2")
	expectEqual(proj.deskPhase[1], "owned", "desk 1 stays owned")
end)

test("Desk 2 shows affordable when Tier 2 unlocks", function()
	local state = { snapshot = tier2OneWorkerProfile(1000) }
	local proj = Workers.projectState(state)
	expectEqual(proj.deskPhase[2], "affordable", "tier 2 + trainee 1 + funds = affordable")
	expectEqual(proj.traineePhase[1], "hired", "trainee 1 shown on duty")
end)

test("Trainee 2 shows need_desk before Desk 2", function()
	local state = { snapshot = tier2OneWorkerProfile(2000) }
	local proj = Workers.projectState(state)
	expectEqual(proj.traineePhase[2], "need_desk", "trainee 2 waits for desk 2")
	expectEqual(proj.deskPhase[2], "affordable", "desk 2 is the first slot-2 step")
end)

test("Confirmed wallet deduction surfaces after purchase", function()
	local p = tier2OneWorkerProfile(1000)
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.ok, true, "purchase confirmed")
	local state = { snapshot = r.profile }
	local proj = Workers.projectState(state)
	expectEqual(proj.balance, 750, "projection shows server-confirmed balance")
	expectEqual(proj.deskPhase[2], "owned", "desk 2 flips to owned only after confirmation")
end)

test("Pending accrual stays nonspendable in desk projections", function()
	local state = { snapshot = tier2OneWorkerProfile(100) }
	state.snapshot.pendingWorkerCuan = 1000
	state.snapshot.incomePerSecond = 3.0
	local proj = Workers.projectState(state)
	expectEqual(proj.deskRemaining[2], 150, "250 price vs 100 confirmed -> 150 missing")
	expectEqual(proj.pendingWorkerCuan, 1000, "pending surfaced for display only")
	local parent = Instance.new("Folder")
	local view = Workers.new({ parent = parent, onAction = function() end })
	view:Update(state)
	expectTrue(string.find(view._overviewStats.Text, "not spendable", 1, true) ~= nil, "pending marked nonspendable")
	view:Destroy()
	parent:Destroy()
end)

test("Overview shows 2 / 2 staff and +3.0 Cuan/s", function()
	local parent = Instance.new("Folder")
	local view = Workers.new({ parent = parent, onAction = function() end })
	local state = { snapshot = fullStudioProfile(320) }
	state.snapshot.pendingWorkerCuan = 15
	state.snapshot.incomePerSecond = 3.0
	view:Update(state)
	local text = view._overviewStats.Text
	expectTrue(string.find(text, "2 / 2", 1, true) ~= nil, "staff count 2 / 2")
	expectTrue(string.find(text, "+3.0 Cuan/s", 1, true) ~= nil, "two-worker rate displayed")
	view:Destroy()
	parent:Destroy()
end)

test("Chapter is incomplete before Trainee 2", function()
	local p = tier2OneWorkerProfile(320)
	local deskR = EconomyService.buyDesk(p, 2)
	expectTrue(deskR.ok, "desk 2 owned")
	-- Snapshot tier is server-derived; mirror it for the projection input.
	deskR.profile.tier = 2
	local steps, done, complete = Workers.chapterProgress(deskR.profile)
	expectEqual(complete, false, "chapter cannot complete without trainee 2")
	expectEqual(done, 6, "six of seven steps complete")
	expectTrue(steps.desk2 == true, "desk 2 step checked")
	expectTrue(steps.trainee2 == nil or steps.trainee2 == false, "trainee 2 step unchecked")
end)

test("Chapter completes after confirmed Trainee 2", function()
	local p = fullStudioProfile(320)
	local steps, done, complete = Workers.chapterProgress(p)
	expectEqual(complete, true, "home studio chapter complete")
	expectEqual(done, 7, "all seven steps checked")
	expectTrue(steps.pcOwned and steps.tier1 and steps.desk1 and steps.trainee1 and steps.tier2 and steps.desk2 and steps.trainee2, "every step checked")
end)

test("Post-completion state keeps earning and closes repeat purchases", function()
	local p = fullStudioProfile(320)
	p.balance = 100
	local before = p.balance
	local r = EconomyService.buyDesk(p, 2)
	expectEqual(r.code, "ALREADY_DONE", "repeat purchase refused after completion")
	local hire = EconomyService.hireWorker(p, 2, "trainee")
	expectEqual(hire.code, "ALREADY_DONE", "repeat hire refused after completion")
	local r2 = EconomyService.buyDesk(p, 3)
	expectEqual(r2.ok, false, "no third workstation appears after completion")
	expectEqual(p.balance, before, "rejections spend nothing")
	local ticked = EconomyService.tick(p, 10)
	expectEqual(ticked.earned, 30, "workers keep earning after completion")
	-- UI presents the completion state instead of a game-over.
	local parent = Instance.new("Folder")
	local view = Workers.new({ parent = parent, onAction = function() end })
	view:Update({ snapshot = p })
	expectTrue(string.find(view._chapterTitle.Text, "COMPLETE", 1, true) ~= nil, "chapter card shows completion")
	expectTrue(string.find(view._notice.Text, "organic posting", 1, true) ~= nil, "completion notice points to future expansion")
	view:Destroy()
	parent:Destroy()
end)

test("Touch targets >= 44px and labels wrap for mobile", function()
	local parent = Instance.new("Folder")
	local view = Workers.new({ parent = parent, onAction = function() end })
	for slot = 1, 2 do
		expectTrue(view._deskButtons[slot].Size.Y.Offset >= 44, `desk {slot} button touch height`)
		expectTrue(view._traineeButtons[slot].Size.Y.Offset >= 44, `trainee {slot} button touch height`)
	end
	expectTrue(view._overviewStats.TextWrapped == true, "overview wraps on narrow viewports")
	for _, key in ipairs(Workers.CHAPTER_ORDER) do
		expectTrue(view._chapterSteps[key].TextWrapped == true, `chapter step {key} wraps`)
	end
	view:Destroy()
	parent:Destroy()
end)

-- Execute all tests in suite
local passed = 0
for _, t in ipairs(tests) do
	local ok, err = pcall(t.fn)
	if not ok then
		print(`[FAIL] {t.name}: {tostring(err)}`)
		error(`{t.name}: {tostring(err)}`, 0)
	end
	passed += 1
end

return `{passed}/{#tests} passed`
