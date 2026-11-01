--!strict
-- Buzzer Simulator — BS-10 spec: V0 recovery, reliability, persistence and
-- failure hardening.
--
-- Exercises the REAL ProfileStore, SessionService, EconomyService,
-- MissionService and ClientState against an injected DataStore adapter and a
-- fake clock. Nothing in the business logic is faked: only the store transport
-- and the clock.
--
-- Invariant under test: confirmed economic transactions are never duplicated
-- and never silently lost.
--   Phase A: load integrity / corrupt data / competing leases
--   Phase B: post reveal survival, frozen payout, settlement retry stability
--   Phase C: Fast Phone purchase across rejoin and retry idempotency
--   Phase D: ambiguous write reconciliation (server ring + client 6s timeout)
--   Phase E: competing servers, clean release handoff, shutdown safety
--   Phase F: client session, camera and control recovery
--   Phase G: end-to-end journey across three rejoin boundaries
-- Contract sources: docs/03, docs/04, docs/08 (BS-10), docs/09.

local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SessionService = require(ServerStorage:WaitForChild("SessionService"))
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))

local spScripts = StarterPlayer:WaitForChild("StarterPlayerScripts", 10) :: any
local ClientState = require(spScripts:WaitForChild("ClientState", 10)) :: any

-- ===== harness =====
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
local function expectNotNil(value: any, label: string)
	if value == nil then
		error(label, 0)
	end
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy
end

-- ===== fake clock =====
local function makeClock(start: number): (() -> number, (number) -> ())
	local t = start
	return function()
		return t
	end, function(dt: number)
		t += dt
	end
end

-- ===== fake DataStore adapter =====
local FakeStore: any = {}
FakeStore.__index = FakeStore

function FakeStore.new()
	local self = setmetatable({}, FakeStore)
	self.data = {} :: { [string]: any }
	self.updateCalls = 0
	self.getCalls = 0
	self.failGet = false
	self.failUpdate = false
	self.failUpdateTimes = 0
	self.ambiguousOnce = false
	return self
end

function FakeStore:GetAsync(key: string, _options: any?)
	local s: any = self
	s.getCalls += 1
	if s.failGet then
		error("FakeStore: injected read failure", 0)
	end
	local value = s.data[key]
	return if value ~= nil then deepCopy(value) else nil
end

function FakeStore:UpdateAsync(key: string, transform: (any) -> any)
	local s: any = self
	s.updateCalls += 1
	if s.failUpdate then
		error("FakeStore: injected write failure", 0)
	end
	if s.failUpdateTimes > 0 then
		s.failUpdateTimes -= 1
		error("FakeStore: injected transient write failure", 0)
	end
	if s.ambiguousOnce then
		s.ambiguousOnce = false
		local committed = transform(if s.data[key] ~= nil then deepCopy(s.data[key]) else nil)
		if committed ~= nil then
			s.data[key] = deepCopy(committed)
		end
		error("FakeStore: ambiguous success (response lost)", 0)
	end
	local old = if s.data[key] ~= nil then deepCopy(s.data[key]) else nil
	local result = transform(old)
	if result == nil then
		return nil
	end
	s.data[key] = deepCopy(result)
	return deepCopy(result)
end

function FakeStore:RemoveAsync(key: string)
	local s: any = self
	s.data[key] = nil
end

-- ===== fake HttpService =====
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

-- ===== fixtures =====
local KEY = "Player_1234"

local function freshProfile(): any
	return {
		balance = 0,
		lifetimeEarned = 0,
		completedMissions = 0,
		deviceId = "phone_cheap",
		propertyId = "bedroom",
		ownedDesks = {},
		workers = {},
		fractionalIncome = 0,
		claimedRunIdsWindow = {},
		recentMutationOutcomes = {},
		missionVariantCounters = {},
		nextOrganicSequence = 0,
		activeMission = nil,
		pendingPost = nil,
		ownPosts = {},
		nextPostSequence = 1,
	}
end

local function guidedProfile(): any
	local p = freshProfile()
	p.balance = 110
	p.lifetimeEarned = 110
	p.completedMissions = 1
	return p
end

local function seedEnvelope(store: any, profile: any, revision: number)
	local data: any = store.data
	data[KEY] = {
		schemaVersion = 1,
		revision = revision,
		lastSaveOpId = "init",
		updatedAt = 1000,
		profile = profile,
		lease = { token = "", jobId = "seed", expiresAt = 0 },
	}
end

local function newSession(store: any, clock: () -> number, jobId: string?): any
	return SessionService.new({
		userId = 1234,
		store = store,
		httpService = FakeHttp,
		noCacheOptions = function()
			return { UseCache = false }
		end,
		jobId = jobId or "job-test",
		now = clock,
		wait = function(_s: number) end,
	})
end

local function startSession(store: any, clock: () -> number, jobId: string?): any
	local session = newSession(store, clock, jobId)
	local started = session:Start()
	expectEqual(started.ok, true, `session started ({tostring(started.code)})`)
	return session
end

local function durableBalance(store: any): number
	local envelope: any = store.data[KEY]
	return envelope.profile.balance
end

local function durableProfile(store: any): any
	local envelope: any = store.data[KEY]
	return envelope.profile
end

local function lastOpId(store: any): string
	local envelope: any = store.data[KEY]
	return envelope.lastSaveOpId
end

local function sampleClientSnapshot(rev: number?, balance: number?, deviceId: string?): any
	return {
		revision = rev or 1,
		serverTime = 1000,
		balance = balance or 100,
		pendingWorkerCuan = 0,
		incomePerSecond = 0,
		lifetimeEarned = balance or 100,
		completedMissions = 1,
		tier = 0,
		maxShippedTier = 0,
		deviceId = deviceId or "phone_cheap",
		ownedDesks = {},
		workers = {},
		activeMission = nil,
		pendingPost = nil,
		nextOrganicContextId = "organic_snack",
		ownPosts = {},
		feedVersion = 1,
		saveStatus = "healthy",
	}
end

local function openEvent(sessionId: string, snapshot: any?): any
	local snap = snapshot or sampleClientSnapshot(1, 100)
	return {
		kind = "OpenComputer",
		dashboardSessionId = sessionId,
		expiresAt = 1600,
		serverTime = 1000,
		state = snap,
	}
end

-- =============================================================================
-- Phase A — load integrity: a failed read never becomes a blank profile
-- =============================================================================

test("A1: A failed backend read never initializes a blank profile", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 7)
	store.failGet = true

	local session = newSession(store, clock)
	local started = session:Start()

	expectEqual(started.ok, false, "start refused")
	expectEqual(started.code, "SAVE_UNAVAILABLE", "reports the read failure")
	expectEqual(session:GetConfirmedProfile(), nil, "no profile is published")
	expectEqual(session:GetSaveStatus(), "SAVE_UNAVAILABLE", "save status reflects the outage")
	expectEqual(session:Mutate({ requestId = "r1", action = "PublishOrganic", payload = { templateId = "snack_meme" } }).ok, false, "no economy action on an unloaded session")
	expectEqual(store.data[KEY].revision, 7, "revision untouched")
	expectEqual(durableBalance(store), 0, "durable profile untouched")
	expectEqual(lastOpId(store), "init", "no write was attempted")
end)

test("A2: A corrupt payload is rejected and preserved untouched", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 3)
	store.data[KEY].profile.balance = "not-a-number"

	local session = newSession(store, clock)
	local started = session:Start()
	expectEqual(started.ok, false, "start refused")
	expectEqual(started.code, "CORRUPT", "corruption reported, not repaired")
	expectEqual(store.data[KEY].revision, 3, "revision untouched")
	expectEqual(store.data[KEY].profile.balance, "not-a-number", "corrupt bytes preserved for support")
end)

test("A3: An unsupported schema is never migrated or overwritten", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 2)
	store.data[KEY].schemaVersion = 99
	local before = deepCopy(store.data[KEY])

	local session = newSession(store, clock)
	local started = session:Start()
	expectEqual(started.ok, false, "start refused")
	expectEqual(started.code, "UNSUPPORTED_SCHEMA", "future schema reported")
	expectEqual(store.data[KEY].schemaVersion, 99, "schema version untouched")
	expectEqual(store.updateCalls, 0, "no write attempted")
	expectEqual(jsonEncode(store.data[KEY]), jsonEncode(before), "stored bytes identical")
end)

test("A4: A live foreign lease blocks a second server without overwriting data", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)

	local first = startSession(store, clock, "job-a")
	local before: any = deepCopy(store.data[KEY])

	local second = newSession(store, clock, "job-b")
	local blocked = second:Start()
	expectEqual(blocked.ok, false, "second server refused")
	expectEqual(blocked.code, "LOCKED", "lease collision reported")
	expectEqual(second:GetConfirmedProfile(), nil, "no profile published to the loser")
	expectEqual(store.data[KEY].lease.token, before.lease.token, "winner keeps the lease")
	expectEqual(store.data[KEY].revision, before.revision, "no write from the loser")
	expectEqual(first:GetConfirmedProfile().balance, 0, "winner still healthy")
end)

test("A5: An expired lease is taken over and the confirmed profile survives", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	local p = freshProfile()
	p.balance = 42
	p.lifetimeEarned = 42
	seedEnvelope(store, p, 1)

	local crashed = startSession(store, clock, "job-a")
	expectEqual(crashed:GetConfirmedProfile().balance, 42, "first server confirmed")
	advance(241)

	local takeover = newSession(store, clock, "job-b")
	local started = takeover:Start()
	expectEqual(started.ok, true, "expired lease acquired")
	expectEqual(takeover:GetConfirmedProfile().balance, 42, "confirmed balance survived the crash")
	expectEqual(store.data[KEY].lease.jobId, "job-b", "lease owner is the new server")
end)

test("A6: A key that vanishes between read and write never seeds a blank profile", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 4)

	local originalGet = store.GetAsync
	store.GetAsync = function(self: any, key: string, options: any?)
		local value = originalGet(self, key, options)
		self.data[key] = nil
		return value
	end

	local session = newSession(store, clock)
	local started = session:Start()
	expectEqual(started.ok, false, "start refused rather than inventing state")
	expectEqual(started.code, "SAVE_UNAVAILABLE", "vanished key reported explicitly")
	expectEqual(session:GetConfirmedProfile(), nil, "nothing published")
end)

-- =============================================================================
-- Phase B — post reveal survival, frozen payout, stable settlement identity
-- =============================================================================

test("B1: An organic post survives a rejoin and settles exactly once", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)

	local first = startSession(store, clock, "job-a")
	local published = first:Mutate({
		requestId = "org-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(published.ok, true, "post published")
	local pending: any = first:GetConfirmedProfile().pendingPost
	expectNotNil(pending, "pending post is durable")
	expectEqual(pending.postId, "post-1", "server-owned post id")
	local frozenCuan = pending.organicCuan
	local frozenImpact = pending.finalImpact
	expectEqual(first:Stop().ok, true, "clean leave releases the lease")

	local rejoined = startSession(store, clock, "job-b")
	local resumed: any = rejoined:GetConfirmedProfile().pendingPost
	expectNotNil(resumed, "pending post survived the rejoin")
	expectEqual(resumed.postId, "post-1", "same post identity")
	expectEqual(resumed.organicCuan, frozenCuan, "frozen payout unchanged")
	expectEqual(resumed.finalImpact, frozenImpact, "frozen impact unchanged")

	advance(18)
	local before = durableBalance(store)
	rejoined:Snapshot()
	expectEqual(durableBalance(store), before + frozenCuan, "the frozen payout is credited once")
	expectEqual(rejoined:GetConfirmedProfile().pendingPost, nil, "pending slot cleared")
	expectEqual(#rejoined:GetConfirmedProfile().ownPosts, 1, "one own-post summary")

	local second = rejoined:Mutate({ requestId = "org-2", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	expectEqual(second.ok, true, "a fresh post still publishes")
	expectEqual(rejoined:GetConfirmedProfile().balance, frozenCuan, "no double credit from the first post")
end)

test("B2: Settlement retry uses one stable identity and credits exactly once", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)

	session:Mutate({ requestId = "org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(18)
	store.failUpdateTimes = 1
	local writesBefore = store.updateCalls
	session:Snapshot()

	expectTrue(store.updateCalls > writesBefore, "the settlement was retried")
	expectEqual(lastOpId(store), "settle-post-1", "stable settle-<postId> identity")
	expectEqual(durableBalance(store), 15, "credited exactly once")
	expectEqual(session:GetSaveStatus(), "healthy", "recovered to healthy")
end)

test("B3: A post that is not yet due is never settled early across a rejoin", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)

	local first = startSession(store, clock)
	first:Mutate({ requestId = "org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	first:Stop()

	local rejoined = startSession(store, clock, "job-b")
	advance(5)
	rejoined:Snapshot()
	expectEqual(durableBalance(store), 0, "early reveal pays nothing")
	expectNotNil(rejoined:GetConfirmedProfile().pendingPost, "post still resolving")
	advance(13)
	rejoined:Snapshot()
	expectEqual(durableBalance(store), 15, "pays once the reveal window closes")
	expectEqual(rejoined:GetConfirmedProfile().pendingPost, nil, "consumed")
end)

test("B4: A campaign post survives a rejoin and its claim still pays once", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)

	local first = startSession(store, clock)
	first:Mutate({ requestId = "acc-1", action = "AcceptMission", payload = { missionId = "food_stall_launch" } })
	local runId = first:GetConfirmedProfile().activeMission.runId
	first:Mutate({ requestId = "pub-1", action = "PublishPost", payload = { runId = runId, templateId = "meal_meme" } })
	expectEqual(first:GetConfirmedProfile().activeMission.status, "resolvingPost", "postCount advanced with the publish")
	first:Stop()

	local rejoined = startSession(store, clock, "job-b")
	expectEqual(rejoined:GetConfirmedProfile().activeMission.status, "resolvingPost", "campaign progress survived")
	advance(18)
	rejoined:Snapshot()
	expectEqual(rejoined:GetConfirmedProfile().activeMission.status, "readyToClaim", "strong post clears the requirement")
	local claim = rejoined:Mutate({ requestId = "clm-1", action = "ClaimMission", payload = { runId = runId } })
	expectEqual(claim.ok, true, "claim accepted after rejoin")
	expectEqual(rejoined:GetConfirmedProfile().balance, 95, "15 organic + 80 bonus")
	local replay = rejoined:Mutate({ requestId = "clm-2", action = "ClaimMission", payload = { runId = runId } })
	expectEqual(replay.ok, false, "a second claim is refused")
	expectEqual(durableBalance(store), 95, "durable balance paid once")
end)

test("B5: A settlement whose response was lost never pays twice", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(18)
	store.ambiguousOnce = true
	session:Snapshot()
	session:Snapshot()
	expectEqual(durableBalance(store), 15, "exactly one payout")
	expectEqual(session:GetConfirmedProfile().balance, 15, "confirmed view agrees with the backend")
end)

-- =============================================================================
-- Phase C — Fast Phone purchase across rejoin and retry
-- =============================================================================

test("C1: A Fast Phone purchase survives a rejoin with one deduction", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 9)

	local first = startSession(store, clock)
	local buy = first:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(buy.ok, true, "purchase confirmed")
	expectEqual(first:GetConfirmedProfile().balance, 60, "110 - 50")
	expectEqual(first:GetConfirmedProfile().deviceId, "phone_fast", "device swapped")
	first:Stop()

	local rejoined = startSession(store, clock, "job-b")
	expectEqual(rejoined:GetConfirmedProfile().deviceId, "phone_fast", "owned device survived")
	expectEqual(rejoined:GetConfirmedProfile().balance, 60, "deduction survived exactly once")
	expectEqual(rejoined:GetConfirmedProfile().lifetimeEarned, 110, "spending never reduces lifetime")
end)

test("C2: An identical retried purchase replays without a second deduction", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 9)
	local session = startSession(store, clock)

	local first = session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(first.ok, true, "first purchase ok")
	local writes = store.updateCalls
	local replay = session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(replay.ok, true, "identical retry replays as OK")
	expectEqual(store.updateCalls, writes, "the replay performs no write")
	expectEqual(durableBalance(store), 60, "charged once")
end)

test("C3: A purchase whose response was lost resolves without double charging", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 9)
	local session = startSession(store, clock)

	store.ambiguousOnce = true
	store.failUpdateTimes = 2
	local attempt = session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(attempt.ok, false, "the lost response is not reported as confirmed")
	expectEqual(attempt.code, "SAVE_UNAVAILABLE", "save failure reported")
	local retry = session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(retry.ok, true, "identical retry resolves")
	expectEqual(durableBalance(store), 60, "charged exactly once")
	expectEqual(session:GetConfirmedProfile().balance, 60, "confirmed view agrees")
	expectEqual(durableProfile(store).deviceId, "phone_fast", "device durable")
end)

test("C4: A different request for the owned device is refused with no deduction", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 9)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })

	local again = session:Mutate({ requestId = "buy-2", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(again.ok, false, "re-buy refused")
	expectEqual(again.code, "ALREADY_DONE", "reported as already owned")
	expectEqual(durableBalance(store), 60, "no second deduction")
end)

test("C5: An unaffordable purchase is refused and never reaches the store", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = guidedProfile()
	p.balance = 10
	p.lifetimeEarned = 10
	seedEnvelope(store, p, 2)
	local session = startSession(store, clock)

	local writes = store.updateCalls
	local buy = session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(buy.ok, false, "purchase refused")
	expectEqual(buy.code, "INSUFFICIENT_FUNDS", "reported as unaffordable")
	expectEqual(store.updateCalls, writes, "a domain rejection performs no write")
	expectEqual(durableProfile(store).deviceId, "phone_cheap", "device unchanged")
	expectEqual(durableBalance(store), 10, "balance unchanged")
end)

test("C6: A spoofed device id cannot skip a tier or buy unshipped hardware", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = guidedProfile()
	p.balance = 5000
	p.lifetimeEarned = 5000
	seedEnvelope(store, p, 3)
	local session = startSession(store, clock)

	local skipped = session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "pc_rumah" } })
	expectEqual(skipped.ok, false, "tier skip refused")
	expectEqual(skipped.code, "NOT_READY", "unshipped hardware gated")
	expectEqual(durableBalance(store), 5000, "no charge")

	local unknown = session:Mutate({ requestId = "buy-2", action = "BuyDevice", payload = { deviceId = "phone_platinum" } })
	expectEqual(unknown.ok, false, "unknown device refused")
	expectEqual(durableBalance(store), 5000, "no charge")
end)

-- =============================================================================
-- Phase D — ambiguous writes and client reconciliation
-- =============================================================================

test("D1: A lookup for an applied request is APPLIED and performs no write", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	local writes = store.updateCalls

	local lookup = session:Snapshot("buy-1")
	expectEqual(lookup.lookup.status, "APPLIED", "durable outcome reported as applied")
	expectEqual(lookup.lookup.originalRequestId, "buy-1", "correlated with the original id")
	expectEqual(lookup.lookup.originalResult.code, "OK", "carries the original result")
	expectEqual(store.updateCalls, writes, "a lookup is read-only")
end)

test("D2: A never-seen request id is UNKNOWN and never proof of rejection", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)
	local session = startSession(store, clock)

	local lookup = session:Snapshot("never-sent")
	expectEqual(lookup.lookup.status, "UNKNOWN", "unknown is explicit")
	expectEqual(lookup.lookup.originalResult, nil, "unknown carries no verdict")
end)

test("D3: A rejected mutation is cached as REJECTED and replayed as such", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)

	local bad = session:Mutate({ requestId = "bad-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(bad.ok, false, "rejected")
	local lookup = session:Snapshot("bad-1")
	expectEqual(lookup.lookup.status, "REJECTED", "rejection is durable knowledge for the session")
	expectEqual(lookup.lookup.originalResult.code, "INSUFFICIENT_FUNDS", "carries the rejection code")
end)

test("D4: A reused request id with different content is refused, never replayed", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })

	local forged = session:Mutate({ requestId = "buy-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	expectEqual(forged.ok, false, "reused id refused")
	expectEqual(forged.code, "INVALID_INPUT", "reported as invalid input, not a replay")
	expectEqual(durableBalance(store), 60, "no extra economic effect")
end)

test("D5: The durable outcome ring cannot grow without bound", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p32 = guidedProfile()
	for i = 1, 32 do
		table.insert(p32.recentMutationOutcomes, {
			requestId = `r{i}`,
			action = "BuyDevice",
			intent = 'buydevice:{"deviceId":"phone_fast"}',
			ok = true,
			code = "OK",
			revision = i,
			resultIds = {},
		})
	end
	seedEnvelope(store, p32, 40)
	local probe32 = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		noCacheOptions = function() return { UseCache = false } end,
		jobId = "job-p32",
		now = clock,
		wait = function(_s: number) end,
	})
	local load32 = probe32:Load()
	expectEqual(load32.ok, true, "a full 32-entry ring is valid")

	local store2 = FakeStore.new()
	local p33 = guidedProfile()
	for i = 1, 33 do
		table.insert(p33.recentMutationOutcomes, {
			requestId = `w{i}`,
			action = "BuyDevice",
			intent = 'buydevice:{"deviceId":"phone_fast"}',
			ok = true,
			code = "OK",
			revision = i,
			resultIds = {},
		})
	end
	seedEnvelope(store2, p33, 40)
	local probe33 = ProfileStore.new(1234, {
		store = store2,
		httpService = FakeHttp,
		noCacheOptions = function() return { UseCache = false } end,
		jobId = "job-p33",
		now = clock,
		wait = function(_s: number) end,
	})
	local load33 = probe33:Load()
	expectEqual(load33.ok, false, "a 33-entry ring is rejected")
	expectEqual(load33.code, "CORRUPT", "profile integrity enforced")
end)

test("D6: A 6-second client timeout reserves the intent and emits a progress query", function()
	local state = ClientState.new(sampleClientSnapshot(1, 100))
	state:ApplyOpenComputer(openEvent("sess-1"), 1000)
	state:OnCameraOpened()

	expectEqual(state:MutationBlockReason(), nil, "lane free before the action")
	local cmd = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1000)
	expectNotNil(cmd, "mutation admitted")
	local mutId = cmd.requestId

	local queries = state:CheckTimeouts(1007, 6)
	expectEqual(#queries, 1, "one progress query emitted")
	expectEqual(queries[1].payload.lookupRequestId, mutId, "query looks up the timed out mutation")
	expectTrue(state:Get().uncertainMutations[mutId] ~= nil, "uncertainty reserved")
	expectEqual(next(state:Get().inFlightRequests), queries[1].requestId, "only the progress query is now in flight")
end)

test("D7: An APPLIED lookup reply resolves the client uncertain mutation", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)
	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()

	local cmd = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1000)
	local mutId = cmd.requestId
	local queries = state:CheckTimeouts(1007, 6)
	local queryId = queries[1].requestId

	local lookupReply = {
		requestId = queryId,
		ok = true,
		code = "OK",
		revision = 2,
		data = {
			snapshot = sampleClientSnapshot(2, 50, "phone_fast"),
			lookup = {
				originalRequestId = mutId,
				status = "APPLIED",
				originalResult = { ok = true, code = "OK", revision = 2, data = {} },
			},
		},
	}
	state:ApplyReply(lookupReply, 1008)

	expectEqual(state:Get().uncertainMutations[mutId], nil, "uncertain mutation resolved")
	expectEqual(state:GetConfirmedBalance(), 50, "confirmed balance updated")
	expectEqual(state:MutationBlockReason(), nil, "economic buttons unblocked")
end)

test("D8: An UNKNOWN lookup reply preserves uncertainty and never resends", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)
	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()

	local cmd = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1000)
	local mutId = cmd.requestId
	local queries = state:CheckTimeouts(1007, 6)
	local queryId = queries[1].requestId

	local unknownReply = {
		requestId = queryId,
		ok = true,
		code = "OK",
		revision = 1,
		data = {
			snapshot = sampleClientSnapshot(1, 100),
			lookup = {
				originalRequestId = mutId,
				status = "UNKNOWN",
				originalResult = nil,
			},
		},
	}
	state:ApplyReply(unknownReply, 1008)

	expectTrue(state:Get().uncertainMutations[mutId] ~= nil, "uncertainty preserved on UNKNOWN")
	expectEqual(next(state:Get().inFlightRequests), nil, "no new request issued")
end)

test("D9: An uncertain mutation blocks further economic actions in ClientState", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)
	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()

	state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1000)
	state:CheckTimeouts(1007, 6)

	local reason = state:MutationBlockReason()
	expectNotNil(reason, "actions are blocked")
	expectTrue(string.find(reason :: string, "BUSY") ~= nil, "block reason names BUSY")
	local secondCmd = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1008)
	expectEqual(secondCmd, nil, "second mutation refused while earlier is unconfirmed")
end)

-- =============================================================================
-- Phase E — competing servers, clean release handoff, shutdown safety
-- =============================================================================

test("E1: Two sessions on same key: second Start returns LOCKED while first holds lease", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)

	local s1 = startSession(store, clock, "srv-1")
	expectTrue(s1:IsStarted(), "s1 started")

	local s2 = newSession(store, clock, "srv-2")
	local start2 = s2:Start()
	expectEqual(start2.ok, false, "s2 refused")
	expectEqual(start2.code, "LOCKED", "lease collision reported")
	expectFalse(s2:IsStarted(), "s2 not started")
end)

test("E2: Clean release handoff transfers lease authority immediately", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)

	local s1 = startSession(store, clock, "srv-1")
	local stop1 = s1:Stop()
	expectEqual(stop1.ok, true, "s1 clean leave")

	local s2 = startSession(store, clock, "srv-2")
	expectTrue(s2:IsStarted(), "s2 acquires immediately after release")
	expectEqual(s2:GetConfirmedProfile().balance, 110, "state matches")
end)

test("E3: Stale save from a server that lost its lease is rejected LOCKED and never overwrites", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)

	local s1 = startSession(store, clock, "srv-1")
	advance(241)

	local s2 = startSession(store, clock, "srv-2")
	local buy2 = s2:Mutate({ requestId = "b2", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(buy2.ok, true, "s2 buy succeeds")
	expectEqual(durableBalance(store), 60, "s2 reduced balance")

	local staleWrite = s1:Mutate({ requestId = "b1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(staleWrite.ok, false, "stale server write refused")
	expectEqual(staleWrite.code, "LOCKED", "reported as LOCKED")
	expectEqual(durableBalance(store), 60, "s2 balance preserved")
	expectEqual(store.data[KEY].lease.jobId, "srv-2", "s2 lease retained")
end)

test("E4: Stop called twice is idempotent and avoids redundant saves or releases", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)
	local session = startSession(store, clock)

	local stop1 = session:Stop()
	expectEqual(stop1.ok, true, "first stop ok")
	local writesAfterFirst = store.updateCalls

	local stop2 = session:Stop()
	expectEqual(stop2.ok, true, "second stop ok")
	expectEqual(stop2.detail, "already stopped", "idempotent notice")
	expectEqual(store.updateCalls, writesAfterFirst, "no extra write on second stop")
end)

test("E5: Stop with an unresolved write failure retains the lease and reports explicitly", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, guidedProfile(), 1)
	local session = startSession(store, clock)

	store.failUpdate = true
	local stop = session:Stop()
	expectEqual(stop.ok, false, "stop failure reported")
	expectEqual(stop.code, "SAVE_UNAVAILABLE", "save error reported")
	expectNotNil(store.data[KEY].lease.token, "lease retained for rejoin reconciliation")
end)

-- =============================================================================
-- Phase F — client session, camera and control recovery
-- =============================================================================

test("F1: Denied open while Opening restores camera/controls and resets to Closed", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)

	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	expectEqual(state:GetStatus(), "Opening", "state is Opening")

	state:ApplyOpenComputerDenied("NOT_READY")
	expectEqual(state:GetStatus(), "Closed", "status cleanly reset to Closed")
	expectEqual(state:Get().activeDenial, "NOT_READY", "denial code recorded")
	expectEqual(state:Get().dashboardSessionId, nil, "session cleared")
	expectFalse(state:Get().cameraCaptured, "camera not captured")
end)

test("F2: Session expiration during Open transitions to Expired and closes dashboard", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)

	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()
	expectEqual(state:GetStatus(), "Open", "dashboard is open")

	local expired = state:ApplySessionExpired("sess-1", "SESSION_EXPIRED")
	expectTrue(expired, "expiration handled")
	expectEqual(state:GetStatus(), "Expired", "state is Expired")
	expectEqual(state:Get().dashboardSessionId, nil, "sessionId dropped")
end)

test("F3: Local watchdog expiration transitions to Expired and clears session", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)

	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()
	expectEqual(state:GetStatus(), "Open", "open")

	local fired = state:CheckLocalWatchdog(1601)
	expectTrue(fired, "watchdog triggered")
	expectEqual(state:GetStatus(), "Expired", "watchdog expired the dashboard")
	expectEqual(state:Get().dashboardSessionId, nil, "sessionId cleared")
end)

test("F4: SAVE_UNAVAILABLE status blocks mutation requests in ClientState", function()
	local snap = sampleClientSnapshot(1, 100)
	snap.saveStatus = "SAVE_UNAVAILABLE"
	local state = ClientState.new(snap)
	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()

	expectTrue(state:IsSaveBlocked(), "is save blocked")
	local reason = state:MutationBlockReason()
	expectNotNil(reason, "blocked")
	expectTrue(string.find(reason :: string, "SAVE_UNAVAILABLE") ~= nil, "block reason names SAVE_UNAVAILABLE")

	local cmd = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1000)
	expectEqual(cmd, nil, "mutation rejected locally")
end)

test("F5: Stale expiry for an older session generation is safely ignored", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)

	state:ApplyOpenComputer(openEvent("sess-2", snap), 1000)
	state:OnCameraOpened()
	expectEqual(state:Get().dashboardSessionId, "sess-2", "current session is sess-2")

	local handled = state:ApplySessionExpired("sess-old", "SESSION_EXPIRED")
	expectFalse(handled, "stale expiry rejected")
	expectEqual(state:GetStatus(), "Open", "status preserved")
	expectEqual(state:Get().dashboardSessionId, "sess-2", "current session preserved")
end)

test("F6: Character loss resets dashboard state to Closed and invalidates session", function()
	local snap = sampleClientSnapshot(1, 100)
	local state = ClientState.new(snap)

	state:ApplyOpenComputer(openEvent("sess-1", snap), 1000)
	state:OnCameraOpened()
	expectEqual(state:GetStatus(), "Open", "dashboard open")

	local wasActive = state:OnCharacterLost()
	expectTrue(wasActive, "active session was terminated")
	expectEqual(state:GetStatus(), "Closed", "state is Closed")
	expectEqual(state:Get().dashboardSessionId, nil, "dashboard session dropped")
end)

-- =============================================================================
-- Phase G — end-to-end recovery journey across three rejoin boundaries
-- =============================================================================

test("G1: Multi-step player journey across three server rejoins conserves Cuan exactly", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)

	-- === Server 1: Organic Post ===
	local s1 = startSession(store, clock, "srv-1")
	local p1 = s1:Mutate({ requestId = "j-org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	expectEqual(p1.ok, true, "s1 organic published")
	advance(18)
	s1:Snapshot()
	expectEqual(s1:GetConfirmedProfile().balance, 15, "s1 organic settled: 15")
	s1:Stop()

	-- === Server 2: Campaign & Claim (Rejoin 1) ===
	local s2 = startSession(store, clock, "srv-2")
	expectEqual(s2:GetConfirmedProfile().balance, 15, "rejoin 1 sees 15 Cuan")
	s2:Mutate({ requestId = "j-acc-1", action = "AcceptMission", payload = { missionId = "food_stall_launch" } })
	local runId = s2:GetConfirmedProfile().activeMission.runId
	s2:Mutate({ requestId = "j-pub-1", action = "PublishPost", payload = { runId = runId, templateId = "meal_meme" } })
	advance(18)
	s2:Snapshot()
	expectEqual(s2:GetConfirmedProfile().activeMission.status, "readyToClaim", "campaign ready")
	local claim = s2:Mutate({ requestId = "j-clm-1", action = "ClaimMission", payload = { runId = runId } })
	expectEqual(claim.ok, true, "s2 claim accepted")
	expectEqual(s2:GetConfirmedProfile().balance, 110, "15 + 15 + 80 = 110")
	s2:Stop()

	-- === Server 3: Fast Phone Purchase (Rejoin 2) ===
	local s3 = startSession(store, clock, "srv-3")
	expectEqual(s3:GetConfirmedProfile().balance, 110, "rejoin 2 sees 110 Cuan")
	local buy = s3:Mutate({ requestId = "j-buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(buy.ok, true, "s3 fast phone purchased")
	expectEqual(s3:GetConfirmedProfile().balance, 60, "110 - 50 = 60")
	expectEqual(s3:GetConfirmedProfile().deviceId, "phone_fast", "fast phone equipped")
	s3:Stop()

	-- === Server 4: Fast Phone Yield Verification (Rejoin 3) ===
	local s4 = startSession(store, clock, "srv-4")
	expectEqual(s4:GetConfirmedProfile().deviceId, "phone_fast", "rejoin 3 owns fast phone")
	expectEqual(s4:GetConfirmedProfile().balance, 60, "balance is 60")
	s4:Mutate({ requestId = "j-org-2", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(16)
	s4:Snapshot()
	expectEqual(s4:GetConfirmedProfile().balance, 84, "60 + 24 = 84")
	expectEqual(durableBalance(store), 84, "durable backend reflects 84 exactly")
	s4:Stop()
end)

-- ===== runner =====
local passed = 0
local failures: { string } = {}
for _, testCase in ipairs(tests) do
	local ok, err = pcall(testCase.fn)
	if ok then
		passed += 1
		print(`[PASS] {testCase.name}`)
	else
		table.insert(failures, `{testCase.name}: {tostring(err)}`)
		print(`[FAIL] {testCase.name}: {tostring(err)}`)
	end
end

print(`==============================================`)
print(`BS-10 spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print("FAILURES:")
	for _, failure in ipairs(failures) do
		print(`  - {failure}`)
	end
	error(`BS-10 spec: {#failures} failed`, 0)
end
return `BS-10: {passed}/{#tests} passed`
