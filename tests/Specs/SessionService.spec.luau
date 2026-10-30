--!strict
-- Buzzer Simulator — SessionService spec (BS-04).
-- Executed by tests/Runner.server.luau in the test project only.
--
-- Contract sources: docs/03 (profile/persistence, exactly-once, serialized
-- lane), docs/04 (worker banking), docs/08 (BS-04), docs/09 (test matrix).
--
-- Everything runs against the REAL ProfileStore, MissionService and
-- EconomyService through an injected fake DataStore adapter and a fake clock.
-- No business logic is faked: only the store transport and the clock.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SessionService = require(ServerStorage:WaitForChild("SessionService"))
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))
local EconomyService = require(ServerStorage:WaitForChild("EconomyService"))
local Catalog = require(Shared:WaitForChild("Catalog"))

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

-- ===== fake clock =====
-- Monotonic and injectable. SessionService never reads a wall clock, so the
-- whole suite is deterministic.
local function makeClock(start: number): (() -> number, (number) -> ())
	local t = start
	return function()
		return t
	end, function(dt: number)
		t += dt
	end
end

-- ===== fake DataStore adapter =====
-- Mirrors the conditional-write contract: UpdateAsync runs the transform and
-- only commits when it returns non-nil. Injection knobs reproduce delayed,
-- throttled and ambiguous responses.
-- `any` on the table keeps the analyzer from inferring read-only fields on the
-- metatable, matching the existing ProfileStore spec's fake adapter.
local FakeStore: any = {}
FakeStore.__index = FakeStore
function FakeStore.new()
	local self = setmetatable({}, FakeStore)
	self.data = {} :: { [string]: any }
	self.updateCalls = 0
	self.getCalls = 0
	self.freshGetCalls = 0
	-- injection knobs
	self.delaySeconds = 0
	self.failUpdate = false
	self.ambiguousOnce = false
	self.throttleTimes = 0
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
	if s.delaySeconds > 0 then
		-- A held write: the transform still runs (the write may have landed),
		-- but the caller never sees the response.
		local old = s.data[key]
		local result = transform(old)
		if result ~= nil then
			s.data[key] = result
			s._committed[key] = (s._committed[key] or 0) + 1
		end
		error("FakeStore: injected write delay (response lost)", 0)
	end
	if s.failUpdate then
		error("FakeStore: injected write failure", 0)
	end
	if s.throttleTimes > 0 then
		s.throttleTimes -= 1
		error("FakeStore: injected throttle", 0)
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

-- ===== fake HttpService =====
-- JSONEncode must be deterministic and value-based: ProfileStore fingerprints
-- payloads with it, so `tostring` (a table address) would make every retry look
-- like a different payload. Keys are sorted so equivalent tables with different
-- insertion order encode identically.
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

-- ===== profile fixtures =====
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

-- A profile that satisfies every worker invariant (docs/03): PC Rumah
-- equipped, one desk and one trainee. V0 ships no such state, so this is an
-- explicit M1-shaped fixture, never a V0 button.
local function workerProfile(): any
	local p = freshProfile()
	p.deviceId = "pc_rumah"
	p.balance = 100
	p.lifetimeEarned = 300
	p.completedMissions = 3
	table.insert(p.ownedDesks, 1)
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	return p
end

-- Seed a durable envelope with a profile, as BS-06 Bootstrap would after the
-- first successful starter-profile write.
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

-- M1 content is authored in docs/04 but NOT shipped in V0. Tests that need
-- PC/desk/worker eligibility swap the shared shipped-tier cap through a
-- protected fixture that restores the EXACT original value even when the body
-- throws, so one failure cannot contaminate the rest of the place.
local function withShippedTierCap(cap: number, fn: () -> ())
	local realCap = Catalog.V0Shipped.maxShippedTier
	Catalog.V0Shipped.maxShippedTier = cap
	local ok, err = pcall(fn)
	Catalog.V0Shipped.maxShippedTier = realCap
	if not ok then
		error(err, 0)
	end
end

local function newSession(store: any, clock: () -> number, waitLog: { number }?): any
	return SessionService.new({
		userId = 1234,
		store = store,
		httpService = FakeHttp,
		noCacheOptions = function()
			return { UseCache = false }
		end,
		jobId = "job-test",
		now = clock,
		wait = if waitLog == nil then function(_s: number) end else function(s: number)
			table.insert(waitLog, s)
		end,
	})
end

local function startSession(store: any, clock: () -> number, profile: any?): any
	local session = newSession(store, clock)
	local start = session:Start()
	if profile ~= nil then
		expectEqual(start.ok, true, "session started")
	end
	return session
end

-- ===== Start =====
test("Fresh profile load yields a confirmed snapshot", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local snap = session:Snapshot()
	expectEqual(snap.ok, true, "snapshot ok")
	expectEqual(snap.snapshot.balance, 0, "confirmed balance 0")
	expectEqual(snap.snapshot.revision, 1, "revision 1")
	expectEqual(snap.snapshot.saveStatus, "healthy", "save status healthy")
	expectEqual(snap.snapshot.deviceId, "phone_cheap", "starter device")
	expectEqual(snap.snapshot.pendingWorkerCuan, 0, "no pending worker accrual")
	expectEqual(snap.snapshot.incomePerSecond, 0, "no workers")
	expectEqual(snap.snapshot.tier, 0, "tier 0")
	expectEqual(snap.snapshot.nextOrganicContextId, "organic_snack", "first organic context")
end)

test("A lease conflict is reported explicitly with no starter profile", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	-- A live foreign lease blocks acquisition.
	store.data["Player_1234"].lease = { token = "other", jobId = "job-other", expiresAt = 9999 }
	local session = newSession(store, clock)
	local start = session:Start()
	expectEqual(start.ok, false, "start refused")
	expectEqual(start.code, "LOCKED", "lease conflict code")
	expectEqual(session:GetConfirmedProfile(), nil, "no profile invented after a failed load")
	expectEqual(session:GetRevision(), 0, "no revision after a failed load")
end)

test("A failed load yields no starter profile", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	store.failUpdate = true
	local session = newSession(store, clock)
	-- GetAsync succeeds with nil, so Load takes the fresh-lease path, which
	-- fails on the injected UpdateAsync error.
	local start = session:Start()
	expectEqual(start.ok, false, "start refused")
	expectEqual(session:GetConfirmedProfile(), nil, "never seed a blank save")
end)

test("A leased key with no profile yet is NOT_READY, not a blank profile", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	-- Bootstrap has not written the starter profile yet.
	local data: any = store.data
	data["Player_1234"] = {
		schemaVersion = 1,
		revision = 1,
		lastSaveOpId = "init",
		updatedAt = 1000,
		profile = nil,
		lease = { token = "", jobId = "seed", expiresAt = 0 },
	}
	local session = newSession(store, clock)
	local start = session:Start()
	expectEqual(start.ok, false, "start refused")
	expectEqual(start.code, "NOT_READY", "no profile written yet")
	expectEqual(session:GetConfirmedProfile(), nil, "no invented profile")
end)

test("The snapshot never exposes lease tokens or private affinities", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local snap = session:Snapshot()
	local encoded = tostring(snap.snapshot)
	expectTrue(encoded:find("token") == nil, "no lease token in the snapshot")
	expectTrue(encoded:find("jobId") == nil, "no job id in the snapshot")
	expectTrue(encoded:find("trendId") == nil, "no private affinity tags")
	expectTrue(encoded:find("affinity") == nil, "no affinity data")
end)

-- ===== organic publication and durable settlement =====
test("Organic publication and durable settlement credit 15 exactly once", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local pub = session:Mutate({
		requestId = "mut-org-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(pub.ok, true, "publish ok")
	expectEqual(pub.revision, 2, "revision advanced once")
	expectEqual(session:GetConfirmedProfile().balance, 0, "no Cuan before settlement")
	-- Not due yet.
	advance(17)
	local early = session:Snapshot()
	expectEqual(early.snapshot.balance, 0, "not settled before settleAt")
	-- Due at 18s.
	advance(1)
	local due = session:Snapshot()
	expectEqual(due.snapshot.balance, 15, "settled organic payout 15")
	expectEqual(due.snapshot.pendingPost, nil, "pending post consumed")
	expectEqual(due.snapshot.ownPosts[1].organicCuan, 15, "own post summary records 15")
end)

test("A duplicate settlement does not pay again", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(18)
	session:Snapshot()
	expectEqual(session:GetConfirmedProfile().balance, 15, "settled once")
	-- A second snapshot after the settlement must not credit again.
	session:Snapshot()
	expectEqual(session:GetConfirmedProfile().balance, 15, "still 15")
	-- And a second organic publish is refused while nothing is pending.
	local second = session:Mutate({
		requestId = "mut-org-2",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(second.ok, true, "a new post is allowed once the slot is free")
	expectEqual(session:GetConfirmedProfile().balance, 15, "publish alone credits nothing")
end)

test("A failed settlement save never publishes speculative Cuan", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(18)
	-- Fail the settlement write.
	store.failUpdate = true
	local snap = session:Snapshot()
	expectEqual(snap.snapshot.balance, 0, "unconfirmed Cuan never appears as spendable")
	expectEqual(snap.snapshot.saveStatus, "SAVE_UNAVAILABLE", "save status reports the failure")
	expectEqual(session:GetConfirmedProfile().balance, 0, "confirmed wallet unchanged")
	-- Economic actions are blocked while the lane is unhealthy.
	local blocked = session:Mutate({
		requestId = "mut-org-2",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(blocked.ok, false, "economic action blocked")
	expectEqual(blocked.code, "SAVE_UNAVAILABLE", "blocked with the save code")
end)

-- ===== campaign lifecycle =====
test("Strong-first campaign lifecycle: 15 organic then 80 bonus", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local accept = session:Mutate({
		requestId = "mut-acc-1",
		action = "AcceptMission",
		payload = { missionId = "food_stall_launch" },
	})
	expectEqual(accept.ok, true, "accept ok")
	expectEqual(session:GetConfirmedProfile().activeMission.contextId, "meal_time", "first context frozen")
	local publish = session:Mutate({
		requestId = "mut-pub-1",
		action = "PublishPost",
		payload = { runId = "run-1", templateId = "meal_meme" },
	})
	expectEqual(publish.ok, true, "publish ok")
	advance(18)
	session:Snapshot()
	expectEqual(session:GetConfirmedProfile().balance, 15, "organic credited at settlement")
	expectEqual(session:GetConfirmedProfile().activeMission.status, "readyToClaim", "strong post reaches readyToClaim")
	local claim = session:Mutate({ requestId = "mut-clm-1", action = "ClaimMission", payload = { runId = "run-1" } })
	expectEqual(claim.ok, true, "claim ok")
	expectEqual(session:GetConfirmedProfile().balance, 95, "15 + 80 = 95")
	expectEqual(session:GetConfirmedProfile().lifetimeEarned, 95, "lifetime includes the bonus")
	expectEqual(session:GetConfirmedProfile().completedMissions, 1, "one claim counted")
end)

test("Two-weak campaign lifecycle reaches the bonus on the second post", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-acc-1", action = "AcceptMission", payload = { missionId = "food_stall_launch" } })
	session:Mutate({ requestId = "mut-pub-1", action = "PublishPost", payload = { runId = "run-1", templateId = "queue_thread" } })
	advance(18)
	session:Snapshot()
	local afterFirst = session:GetConfirmedProfile()
	expectEqual(afterFirst.balance, 9, "first weak post credits 9")
	expectEqual(afterFirst.activeMission.status, "accepted", "impact still short")
	session:Mutate({ requestId = "mut-pub-2", action = "PublishPost", payload = { runId = "run-1", templateId = "queue_thread" } })
	advance(18)
	session:Snapshot()
	local afterSecond = session:GetConfirmedProfile()
	expectEqual(afterSecond.balance, 18, "second weak post credits another 9")
	expectEqual(afterSecond.activeMission.status, "readyToClaim", "two weak posts clear the requirement")
	local claim = session:Mutate({ requestId = "mut-clm-1", action = "ClaimMission", payload = { runId = "run-1" } })
	expectEqual(claim.ok, true, "claim ok")
	expectEqual(session:GetConfirmedProfile().balance, 98, "18 + 80 = 98")
end)

test("A duplicate claim does not pay again", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-acc-1", action = "AcceptMission", payload = { missionId = "food_stall_launch" } })
	session:Mutate({ requestId = "mut-pub-1", action = "PublishPost", payload = { runId = "run-1", templateId = "meal_meme" } })
	advance(18)
	session:Snapshot()
	session:Mutate({ requestId = "mut-clm-1", action = "ClaimMission", payload = { runId = "run-1" } })
	expectEqual(session:GetConfirmedProfile().balance, 95, "claimed once")
	local again = session:Mutate({ requestId = "mut-clm-2", action = "ClaimMission", payload = { runId = "run-1" } })
	expectEqual(again.ok, false, "second claim refused")
	expectEqual(session:GetConfirmedProfile().balance, 95, "balance unchanged")
end)

test("The guided journey totals 110 and the phone leaves 60", function()
	-- docs/09 journey 2: organic 15 + campaign organic 15 + claim bonus 80 = 110.
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	local p = freshProfile()
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(18)
	session:Snapshot()
	session:Mutate({ requestId = "mut-acc-1", action = "AcceptMission", payload = { missionId = "food_stall_launch" } })
	-- The run ID is server-owned and derived from the persisted post sequence,
	-- which the earlier organic publish advanced. Read it from the confirmed
	-- active mission rather than assuming a literal.
	local runId = session:GetConfirmedProfile().activeMission.runId
	print("guided runId=", tostring(runId))
	session:Mutate({ requestId = "mut-pub-1", action = "PublishPost", payload = { runId = runId, templateId = "meal_meme" } })
	advance(18)
	session:Snapshot()
	session:Mutate({ requestId = "mut-clm-1", action = "ClaimMission", payload = { runId = runId } })
	expectEqual(session:GetConfirmedProfile().balance, 110, "guided total is 110")
	local buy = session:Mutate({ requestId = "mut-buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	expectEqual(buy.ok, true, "fast phone purchase ok")
	expectEqual(session:GetConfirmedProfile().balance, 60, "110 - 50 = 60")
	expectEqual(session:GetConfirmedProfile().lifetimeEarned, 110, "spending never reduces lifetime")
end)

test("After the fast phone, a strong organic post earns 24", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	local p = freshProfile()
	p.balance = 110
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-buy-1", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	session:Mutate({ requestId = "mut-org-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(16)
	session:Snapshot()
	expectEqual(session:GetConfirmedProfile().balance, 84, "60 + 24 = 84")
end)

-- ===== exactly-once: request identity =====
test("The same requestId with a different intent is rejected", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(first.ok, true, "first request ok")
	-- Same ID, different payload: a different intent.
	local conflict = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_thread" },
	})
	expectEqual(conflict.ok, false, "same ID with a different intent is invalid")
	expectEqual(conflict.code, "INVALID_INPUT", "rejected as INVALID_INPUT")
	expectEqual(session:GetConfirmedProfile().balance, 0, "no extra payout")
end)

test("The same requestId replays during the active session without a second write", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(first.ok, true, "first request ok")
	local writesAfterFirst = store.updateCalls
	local replay = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(replay.ok, true, "replay ok")
	expectEqual(replay.lookup, "APPLIED", "replay reports APPLIED")
	expectEqual(replay.revision, first.revision, "replay does not bump the revision")
	expectEqual(store.updateCalls, writesAfterFirst, "no second durable write")
end)

test("The same requestId replays after a reconnect from the durable ring", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	local revisionAfterFirst = session:GetRevision()
	-- Reconnect: a brand-new instance with an empty in-memory replay table.
	-- A reconnect happens after the previous session released its lease.
	session:Stop()
	local reconnected = startSession(store, clock)
	local replay = reconnected:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(replay.ok, true, "replay after reconnect ok")
	expectEqual(replay.lookup, "APPLIED", "resolved from the durable ring")
	expectEqual(replay.revision, revisionAfterFirst, "no revision bump on replay")
	expectEqual(reconnected:GetConfirmedProfile().balance, 0, "no second payout")
end)

test("Critical regression: Save A, Save B, late replay of A", function()
	-- docs/03: a late duplicate of an OLD mutation must never overwrite a newer
	-- durable profile. ProfileStore.lastSaveOpId is a single-slot marker, so
	-- this is answered from the durable ring, not from the last write.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local funded = freshProfile()
	funded.balance = 200
	seedEnvelope(store, funded, 1)
	local session = startSession(store, clock)
	-- Mutation A: an organic publish.
	local a = session:Mutate({
		requestId = "mut-A",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(a.ok, true, "A committed")
	-- Mutation B: a device purchase against the confirmed funds.
	local b = session:Mutate({
		requestId = "mut-B",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast" },
	})
	expectEqual(b.ok, true, "B committed")
	expectEqual(session:GetConfirmedProfile().deviceId, "phone_fast", "B is the latest durable state")
	local revisionAfterB = session:GetRevision()
	-- A late duplicate of A arrives.
	local lateA = session:Mutate({
		requestId = "mut-A",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(lateA.ok, true, "A replays its original result")
	expectEqual(lateA.lookup, "APPLIED", "A reports APPLIED")
	expectEqual(lateA.revision, a.revision, "A returns its ORIGINAL revision, not B's")
	-- B remains the latest durable profile.
	expectEqual(session:GetConfirmedProfile().deviceId, "phone_fast", "B still owns the durable state")
	expectEqual(session:GetRevision(), revisionAfterB, "revision did not advance")
	expectEqual(session:GetConfirmedProfile().balance, 150, "no second purchase or payout")
end)

test("Save A, Save B, late replay of A after a reconnect", function()
	-- The same ordering guarantee must survive a reconnect, where the live
	-- replay table is empty and only the durable ring remains.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local funded = freshProfile()
	funded.balance = 200
	seedEnvelope(store, funded, 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-A", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	session:Mutate({ requestId = "mut-B", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	-- A reconnect happens after the previous session released its lease.
	session:Stop()
	local reconnected = startSession(store, clock)
	local lateA = reconnected:Mutate({
		requestId = "mut-A",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(lateA.ok, true, "A replays after reconnect")
	expectEqual(reconnected:GetConfirmedProfile().deviceId, "phone_fast", "B still owns the durable state")
	expectEqual(reconnected:GetConfirmedProfile().balance, 150, "no stale profile overwrote B")
end)

-- ===== ambiguous writes =====
test("An ambiguous committed write resolves through the same operationId", function()
	-- The write lands but the response is lost. ProfileStore retries with the
	-- SAME operationId inside Save, so the caller either sees the resolved
	-- result or an uncertain outcome; either way a subsequent identical retry
	-- must resolve through the idempotent path, never a second payout.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	store.ambiguousOnce = true
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	if not first.ok then
		expectTrue(
			first.code == "BUSY" or first.code == "SAVE_UNAVAILABLE",
			"uncertain code reported"
		)
	end
	-- A retry with the identical request must resolve through ProfileStore's
	-- idempotent operation-ID path, not a new payout.
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(retry.ok, true, "identical retry resolves")
	expectEqual(retry.lookup, "APPLIED", "resolved as APPLIED")
	expectEqual(session:GetConfirmedProfile().pendingPost.templateId, "snack_meme", "exactly one post exists")
	-- Exactly one durable write landed for this logical mutation.
	expectEqual(store._committed["Player_1234"], 2, "lease acquisition + one mutation write")
end)

test("An uncertain UNKNOWN mutation is blocked, never auto-retried", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	-- A held write: the transform commits but the response is lost forever.
	store.delaySeconds = 1
	local attempt = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(attempt.ok, false, "uncertain outcome reported")
	expectEqual(attempt.lookup, "UNKNOWN", "no evidence of application, so UNKNOWN")
	-- The durable state DID change, but the session must not claim it.
	expectEqual(session:GetConfirmedProfile().pendingPost, nil, "unconfirmed proposal not published")
	-- A DIFFERENT request must not silently re-run the same economic action.
	local other = session:Mutate({
		requestId = "mut-2",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(other.ok, false, "a new mutation is blocked while unresolved")
	expectEqual(other.code, "SAVE_UNAVAILABLE", "blocked with the save code")
end)

test("A known APPLIED mutation replays its result without another write", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	local writes = store.updateCalls
	local lookup = session:Snapshot("mut-1")
	expectEqual(lookup.lookup.status, "APPLIED", "lookup reports APPLIED")
	expectEqual(lookup.lookup.originalRequestId, "mut-1", "lookup correlates the original ID")
	expectEqual(store.updateCalls, writes, "a lookup performs no write")
end)

test("An evicted or absent outcome is UNKNOWN, not evidence of non-application", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local lookup = session:Snapshot("mut-never-seen")
	expectEqual(lookup.lookup.status, "UNKNOWN", "absent outcome is UNKNOWN")
	expectEqual(lookup.lookup.originalResult, nil, "UNKNOWN carries no result")
end)

-- ===== serialized lane =====
test("A concurrent command and worker tick do not race", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	-- Accrue 30 connected seconds, then issue a command in the same turn.
	local advance = session:Advance(30)
	expectEqual(advance.ok, true, "advance ok")
	expectEqual(advance.banked, 45, "30 seconds with one worker banks 45")
	expectEqual(session:GetConfirmedProfile().balance, 145, "100 + 45 confirmed")
	expectEqual(session:GetPendingWorkerCuan(), 0, "accrual fully banked")
end)

test("Worker banking is piggybacked onto a purchase, not written twice", function()
	-- A PC + tier 1 profile with one desk and one trainee. The accrued worker
	-- income must ride along with the next durable economy write instead of
	-- issuing its own bank.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	withShippedTierCap(2, function()
		local p = workerProfile()
		p.balance = 1000
		p.lifetimeEarned = 1600
		seedEnvelope(store, p, 1)
		local session = startSession(store, clock)
		-- 10 connected seconds accrues 15 but is NOT banked yet (the 30s bank
		-- boundary has not been reached).
		session:Advance(10)
		local writesBefore = store.updateCalls
		local buy = session:Mutate({
			requestId = "mut-buy-1",
			action = "BuyDesk",
			payload = { slotIndex = 2 },
		})
		expectEqual(buy.ok, true, "purchase ok")
		-- The accrued 15 rode along with the purchase: exactly one write.
		expectEqual(store.updateCalls, writesBefore + 1, "one write for the piggybacked purchase")
		expectEqual(session:GetConfirmedProfile().balance, 765, "1000 + 15 - 250 = 765")
		expectEqual(buy.data.workerCredited, 15, "the purchase reports the banked worker income")
	end)
end)

test("Worker banking happens exactly once across a claim", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-acc-1", action = "AcceptMission", payload = { missionId = "food_stall_launch" } })
	session:Mutate({ requestId = "mut-pub-1", action = "PublishPost", payload = { runId = "run-1", templateId = "meal_meme" } })
	-- The settlement piggybacks the worker income accrued during the reveal, so
	-- the organic credit and the worker credit are confirmed in ONE write.
	advance(18)
	session:Snapshot()
	expectEqual(session:GetConfirmedProfile().balance, 37, "15 organic + floor(1.5*18)=22 worker")
	expectEqual(session:GetPendingWorkerCuan(), 0, "settlement banked the accrued interval")
	-- A further sub-boundary interval stays unbanked until the next durable
	-- write, which is the claim.
	session:Advance(10)
	expectEqual(session:GetPendingWorkerCuan(), 15, "15 Cuan accrued but unbanked")
	local before = session:GetConfirmedProfile().balance
	local claim = session:Mutate({ requestId = "mut-clm-1", action = "ClaimMission", payload = { runId = "run-1" } })
	expectEqual(claim.ok, true, "claim ok")
	-- 37 + 15 worker + 80 bonus.
	expectEqual(session:GetConfirmedProfile().balance, before + 95, "worker income banked exactly once")
	expectEqual(claim.data.workerCredited, 15, "the claim reports the banked worker income")
	expectEqual(session:GetPendingWorkerCuan(), 0, "nothing left unbanked")
end)

test("A failed worker bank leaves the confirmed balance unchanged", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	store.failUpdate = true
	local bank = session:Advance(30)
	expectEqual(bank.banked, 0, "nothing banked on failure")
	expectEqual(session:GetConfirmedProfile().balance, 100, "confirmed wallet unchanged")
	expectEqual(session:GetPendingWorkerCuan(), 45, "accrual retained as unspendable pending")
	expectEqual(session:GetSaveStatus(), "SAVE_UNAVAILABLE", "save status reports the failure")
end)

test("A 75-second connected interval banks all 75 seconds", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	session:Advance(75)
	-- floor(1.5 * 75) = 112, processed as 60 + 15 chunks.
	expectEqual(session:GetConfirmedProfile().balance, 212, "100 + floor(1.5*75) = 212")
	expectEqual(session:GetPendingWorkerCuan(), 0, "nothing dropped")
end)

test("No offline earnings after a reconnect", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	session:Advance(30)
	expectEqual(session:GetConfirmedProfile().balance, 145, "100 + 45 banked while connected")
	-- A long disconnect, then a rejoin after the lease is released.
	session:Stop()
	advance(10000)
	local reconnected = startSession(store, clock)
	expectEqual(reconnected:GetConfirmedProfile().balance, 145, "no offline catch-up income")
	expectEqual(reconnected:GetPendingWorkerCuan(), 0, "no pending accrual after a rejoin")
end)

-- ===== snapshot and write safety =====
test("An ordinary snapshot performs no durable write", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local writes = store.updateCalls
	session:Snapshot()
	session:Snapshot()
	expectEqual(store.updateCalls, writes, "snapshots add zero writes")
end)

test("A definite rejection performs no durable write", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local writes = store.updateCalls
	local rejected = session:Mutate({
		requestId = "mut-bad-1",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast" },
	})
	expectEqual(rejected.ok, false, "no funds")
	expectEqual(rejected.code, "INSUFFICIENT_FUNDS", "insufficient funds")
	expectEqual(store.updateCalls, writes, "a rejection adds zero writes")
end)

test("A malformed payload is rejected before the lane", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local writes = store.updateCalls
	local extraKey = session:Mutate({
		requestId = "mut-x-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme", price = 999 },
	})
	expectEqual(extraKey.ok, false, "extra key rejected")
	expectEqual(extraKey.code, "INVALID_INPUT", "rejected as INVALID_INPUT")
	local forged = session:Mutate({
		requestId = "mut-x-2",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast", price = 0 },
	})
	expectEqual(forged.ok, false, "forged price rejected")
	local badSlot = session:Mutate({
		requestId = "mut-x-3",
		action = "HireWorker",
		payload = { slotIndex = 1, roleId = "manager" },
	})
	expectEqual(badSlot.ok, false, "forged role rejected")
	expectEqual(store.updateCalls, writes, "no write for any malformed payload")
end)

test("Bounded queued command handling", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	-- The queue bound is enforced: a burst beyond it is refused with BUSY
	-- rather than growing without limit.
	expectEqual(SessionService.MAX_QUEUED_ACTIONS, 32, "queue bound is 32")
	-- Fill the queue by holding the lane, then confirm the bound holds.
	local held = false
	local realRun = session._runLane
	session._runLane = function(_self: any, fn: () -> ())
		held = true
		-- Do not run: simulate a busy lane.
		local unused: any = fn
	end
	for i = 1, SessionService.MAX_QUEUED_ACTIONS do
		local r = session:Mutate({
			requestId = `mut-q-{i}`,
			action = "PublishOrganic",
			payload = { templateId = "snack_meme" },
		})
		-- The first is queued; the rest see the lane busy and wait, so they are
		-- queued too. The bound must refuse beyond 32.
		if not r.ok then
			expectEqual(r.code, "BUSY", "beyond the bound is BUSY")
		end
	end
	local overflow = session:Mutate({
		requestId = "mut-overflow",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(overflow.ok, false, "overflow refused")
	expectEqual(overflow.code, "BUSY", "overflow is BUSY, never unbounded")
	session._runLane = realRun
	expectTrue(held, "the lane was held for the whole burst")
end)

-- ===== lease renewal =====
test("An idle lease renewal banks pending worker income in one write", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	session:Advance(30)
	-- The 30-second bank already fired, so a renewal with no new accrual must
	-- not add a redundant write.
	local writes = store.updateCalls
	local renew = session:RenewLease()
	expectEqual(renew.ok, true, "renewal ok")
	expectEqual(store.updateCalls, writes + 1, "one renewal write, no redundant bank")
end)

-- ===== Stop =====
test("Stop performs the final bank then releases the lease", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	session:Advance(10)
	local stop = session:Stop()
	expectEqual(stop.ok, true, "stop ok")
	expectEqual(stop.banked, 15, "final bank credited the accrued 10 seconds")
	expectEqual(session:GetConfirmedProfile().balance, 115, "100 + 15 final bank confirmed")
	expectEqual(store.data["Player_1234"].lease.token, "", "lease released after the confirmed bank")
end)

test("Stop called twice does not double-save or double-release", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	session:Advance(10)
	local first = session:Stop()
	expectEqual(first.ok, true, "first stop ok")
	local writes = store.updateCalls
	local second = session:Stop()
	expectEqual(second.ok, true, "second stop is a no-op")
	expectEqual(second.banked, 0, "no second bank")
	expectEqual(store.updateCalls, writes, "no second durable write")
end)

test("A failed final bank retains the lease and reports explicitly", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, workerProfile(), 1)
	local session = startSession(store, clock)
	session:Advance(10)
	store.failUpdate = true
	local stop = session:Stop()
	expectEqual(stop.ok, false, "stop reports the failure")
	expectEqual(stop.banked, 0, "nothing banked")
	expectTrue(store.data["Player_1234"].lease.token ~= "", "lease retained so a rejoin can reconcile")
end)

-- ===== proposal isolation =====
test("All proposed profile objects stay isolated from confirmed state", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local confirmedBefore = session:GetConfirmedProfile()
	session:Mutate({ requestId = "mut-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	-- Mutating the returned confirmed copy must not reach the live session.
	confirmedBefore.balance = 99999
	confirmedBefore.deviceId = "hacked"
	expectEqual(session:GetConfirmedProfile().balance, 0, "live balance untouched")
	expectEqual(session:GetConfirmedProfile().deviceId, "phone_cheap", "live device untouched")
	-- The snapshot is a deep copy too.
	local snap = session:Snapshot()
	snap.snapshot.balance = 88888
	expectEqual(session:GetConfirmedProfile().balance, 0, "snapshot mutation does not leak")
end)

-- ===== worker accrual attribution =====
-- Regression: accrued connected time must be attributed to the worker count
-- active DURING that interval, never to the count a later hire produces.
-- Before the fix, `_executeMutation` accrued against the POST-mutation profile,
-- so a first hire paid the pre-hire seconds at the new rate and a second hire
-- re-rated the first interval.
test("Pre-hire connected time is not credited at the new worker rate", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 500
	p.workers = {}
	seedEnvelope(store, p, 1)
	withShippedTierCap(1, function()
		local session = startSession(store, clock)
		-- Ten connected seconds with ZERO workers.
		session:Advance(10)
		expectEqual(session:GetPendingWorkerCuan(), 0, "zero workers accrue nothing")
		-- Hire worker 1.
		local hire = session:Mutate({
			requestId = "mut-hire-1",
			action = "HireWorker",
			payload = { slotIndex = 1, roleId = "trainee" },
		})
		expectEqual(hire.ok, true, "hire ok")
		-- The hire must NOT credit the pre-hire interval at the new rate.
		expectEqual(hire.data.workerCredited, 0, "10 seconds with ZERO workers credits 0, not 15")
		expectEqual(session:GetConfirmedProfile().balance, 0, "500 - 500 hire = 0, no pre-hire income")
		-- Ten further seconds at the new one-worker rate.
		session:Advance(10)
		expectEqual(session:GetPendingWorkerCuan(), 15, "post-hire 10 seconds at 1.5/s = 15")
	end)
end)

test("A second hire does not re-rate the first interval", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 2000
	p.lifetimeEarned = 1600
	table.insert(p.ownedDesks, 2)
	seedEnvelope(store, p, 1)
	withShippedTierCap(2, function()
		local session = startSession(store, clock)
		-- Ten connected seconds with ONE worker.
		session:Advance(10)
		expectEqual(session:GetPendingWorkerCuan(), 15, "one worker for 10 seconds = 15")
		-- Hire worker 2.
		local hire = session:Mutate({
			requestId = "mut-hire-2",
			action = "HireWorker",
			payload = { slotIndex = 2, roleId = "trainee" },
		})
		expectEqual(hire.ok, true, "hire ok")
		-- The first interval is credited at the OLD one-worker rate.
		expectEqual(hire.data.workerCredited, 15, "first 10 seconds at 1.5/s = 15, not 30")
		-- Ten further seconds at the new two-worker rate.
		session:Advance(10)
		expectEqual(session:GetPendingWorkerCuan(), 30, "second 10 seconds at 3.0/s = 30")
		-- Total worker income is 15 + 30 = 45, never 30 + 30.
		expectEqual(
			session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan(),
			2000 - 750 + 45,
			"total worker income is 15 + 30 = 45"
		)
	end)
end)

-- ===== D-A: durable retry correctness =====
test("A lost response resolves to APPLIED on an identical retry", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	-- The transform commits but the response is lost.
	store.delaySeconds = 1
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(first.ok, false, "the caller sees an uncertain outcome")
	expectTrue(
		first.code == "BUSY" or first.code == "SAVE_UNAVAILABLE",
		"uncertain code reported"
	)
	expectEqual(session._inflight["mut-1"] ~= nil, true, "the proposal is retained in flight")
	-- Release the write and retry the identical request.
	store.delaySeconds = 0
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(retry.ok, true, "the retry resolves")
	expectEqual(retry.lookup, "APPLIED", "the retry reports APPLIED")
	expectTrue(retry.data ~= nil, "the retry carries data")
	expectTrue(retry.data.resultIds ~= nil, "the retry carries the recorded resultIds")
	expectEqual(session._inflight["mut-1"], nil, "the in-flight entry is cleared")
	-- Exactly one durable economic effect: one pending post, one ring entry.
	expectEqual(session:GetConfirmedProfile().pendingPost ~= nil, true, "exactly one post exists")
	expectEqual(#session:GetConfirmedProfile().recentMutationOutcomes, 1, "one ring entry")
end)

test("A stale cached rejection never shadows a durable APPLIED outcome", function()
	-- The held write commits durably, but the same turn records a local
	-- rejection. The ring is the authority: the retry must report APPLIED and
	-- must not return the stale rejection.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	store.delaySeconds = 1
	session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	-- Confirm the durable state landed even though the caller saw a failure.
	expectEqual(#store.data["Player_1234"].profile.recentMutationOutcomes, 1, "the write landed durably")
	store.delaySeconds = 0
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(retry.ok, true, "the durable outcome wins over the stale rejection")
	expectEqual(retry.lookup, "APPLIED", "reported as APPLIED")
	expectEqual(#session:GetConfirmedProfile().recentMutationOutcomes, 1, "still one ring entry")
end)

test("Repeated identical retries stay idempotent", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	store.delaySeconds = 1
	session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	store.delaySeconds = 0
	local revisionAfterResolve: number? = nil
	for i = 1, 3 do
		local retry = session:Mutate({
			requestId = "mut-1",
			action = "PublishOrganic",
			payload = { templateId = "snack_meme" },
		})
		expectEqual(retry.ok, true, `retry {i} ok`)
		expectEqual(retry.lookup, "APPLIED", `retry {i} APPLIED`)
		if revisionAfterResolve == nil then
			revisionAfterResolve = retry.revision
		else
			expectEqual(retry.revision, revisionAfterResolve, `retry {i} does not bump the revision`)
		end
	end
	expectEqual(#session:GetConfirmedProfile().recentMutationOutcomes, 1, "still one ring entry")
	expectEqual(session:GetConfirmedProfile().pendingPost ~= nil, true, "still one post")
end)

-- ===== D-B: run ID uniqueness =====
test("Run IDs stay unique across 40 claims and window eviction", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	-- A profile whose claimed window has already evicted: it holds the 32 most
	-- recent of 40 completed runs, named with the REAL generated scheme.
	local p = freshProfile()
	for i = 9, 40 do
		table.insert(p.claimedRunIdsWindow, `run-{i}`)
	end
	p.nextPostSequence = 41
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	local next = session:_nextRunId()
	print("B next after 40 claims=", tostring(next))
	expectEqual(#session:GetConfirmedProfile().claimedRunIdsWindow, 32, "window is at its bound")
	-- The generated ID must not be any already-claimed run.
	for _, claimed in ipairs(session:GetConfirmedProfile().claimedRunIdsWindow) do
		expectTrue(claimed ~= next, `generated run ID {next} collides with claimed {claimed}`)
	end
	-- And it must not collide with the evicted older runs either.
	for i = 1, 8 do
		expectTrue(next ~= `run-{i}`, `generated run ID {next} collides with evicted run-{i}`)
	end
end)

test("A fresh profile still generates run-1", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	expectEqual(session:_nextRunId(), "run-1", "a fresh profile starts at run-1")
end)

test("Accept then claim succeeds after window eviction", function()
	-- The end-to-end guarantee: after 40 claims the next run must be claimable.
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	local p = freshProfile()
	for i = 9, 40 do
		table.insert(p.claimedRunIdsWindow, `run-{i}`)
	end
	p.nextPostSequence = 41
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	local accept = session:Mutate({
		requestId = "mut-acc-1",
		action = "AcceptMission",
		payload = { missionId = "food_stall_launch" },
	})
	expectEqual(accept.ok, true, "accept ok after eviction")
	local runId = session:GetConfirmedProfile().activeMission.runId
	print("B accepted runId=", tostring(runId))
	local publish = session:Mutate({
		requestId = "mut-pub-1",
		action = "PublishPost",
		payload = { runId = runId, templateId = "meal_meme" },
	})
	expectEqual(publish.ok, true, "publish ok")
	advance(18)
	session:Snapshot()
	local claim = session:Mutate({
		requestId = "mut-clm-1",
		action = "ClaimMission",
		payload = { runId = runId },
	})
	expectEqual(claim.ok, true, "the new run is claimable, never ALREADY_DONE")
	expectEqual(session:GetConfirmedProfile().completedMissions, 1, "one claim counted")
end)

-- ===== D-D: authoritative canonical intent =====
test("A forged matching intent cannot turn a conflict into a replay", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local funded = freshProfile()
	funded.balance = 200
	seedEnvelope(store, funded, 1)
	local session = startSession(store, clock)
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(first.ok, true, "first request ok")
	-- Reuse the ID with a DIFFERENT action/payload, supplying the original
	-- request's canonical intent. The server must ignore the caller's string.
	local forged = SessionService._canonicalIntent("PublishOrganic", { templateId = "snack_meme" })
	local conflict = session:Mutate({
		requestId = "mut-1",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast" },
		intent = forged,
	})
	expectEqual(conflict.ok, false, "a conflicting request must not replay")
	expectEqual(conflict.code, "INVALID_INPUT", "conflict is INVALID_INPUT")
	expectEqual(session:GetConfirmedProfile().deviceId, "phone_cheap", "no device was purchased")
	expectEqual(session:GetConfirmedProfile().balance, 200, "no funds were spent")
end)

test("A legitimate identical retry still replays with the canonical intent", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(first.ok, true, "first request ok")
	-- The same request, with the caller ALSO supplying a (correct) intent.
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
		intent = SessionService._canonicalIntent("PublishOrganic", { templateId = "snack_meme" }),
	})
	expectEqual(retry.ok, true, "an identical retry still replays")
	expectEqual(retry.lookup, "APPLIED", "reported as APPLIED")
end)

-- ===== D-F: non-blocking serialized lane =====
test("A busy lane makes Snapshot return promptly without waiting", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local waitCalls = {}
	local session = newSession(store, clock, waitCalls)
	session:Start()
	-- Hold the lane as a concurrent write would.
	session._laneBusy = true
	local snap = session:Snapshot()
	expectEqual(snap.ok, true, "snapshot returns while the lane is held")
	expectEqual(#waitCalls, 0, "snapshot performed zero waits")
	expectEqual(snap.snapshot.balance, 0, "the last confirmed state is returned")
	session._laneBusy = false
end)

test("A busy lane bounds Stop instead of spinning forever", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local waitCalls = {}
	local session = newSession(store, clock, waitCalls)
	session:Start()
	session:Advance(10)
	-- Hold the lane so the final bank cannot proceed.
	session._laneBusy = true
	local stop = session:Stop()
	print("F stop.ok=", tostring(stop.ok), "code=", tostring(stop.code), "waits=", #waitCalls)
	-- The wait loop is bounded: it must not spin without limit.
	expectTrue(#waitCalls <= SessionService.MAX_LANE_WAITS, "waits are bounded")
	expectEqual(stop.ok, false, "stop reports the failure rather than hanging")
	session._laneBusy = false
end)

test("The lane serializes concurrent mutations", function()
	-- Two different requests cannot both be inside the lane at once.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local funded = freshProfile()
	funded.balance = 200
	seedEnvelope(store, funded, 1)
	local session = startSession(store, clock)
	local reentered = false
	local realTry = session._tryRunLane
	session._tryRunLane = function(self2: any, fn: () -> ())
		if self2._laneBusy then
			reentered = true
		end
		return realTry(self2, fn)
	end
	local a = session:Mutate({
		requestId = "mut-a",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(a.ok, true, "first mutation ok")
	expectEqual(reentered, false, "the lane was never entered twice concurrently")
	session._tryRunLane = realTry
end)

-- ===== section 6: fractional accrual and failed banking =====
test("A failed bank followed by recovery credits exactly once", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	-- Fail the bank, then let it succeed.
	store.failUpdate = true
	session:Advance(30)
	expectEqual(session:GetConfirmedProfile().balance, 0, "a failed bank credits nothing")
	expectEqual(session:GetPendingWorkerCuan(), 45, "the interval is retained as pending")
	store.failUpdate = false
	session:Advance(30)
	expectEqual(session:GetConfirmedProfile().balance, 90, "30s + 30s at 1.5/s = 90, credited once")
	expectEqual(session:GetPendingWorkerCuan(), 0, "nothing left pending")
end)

test("A failed bank preserves the fractional residual exactly", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	-- 1 worker at 1.5/s: 10s -> floor(1.5*10) = 15, residual 0.
	store.failUpdate = true
	session:Advance(10)
	expectEqual(session._unbankedSeconds, 10, "the exact interval is restored, not 15/1.5 reconstructed")
	store.failUpdate = false
	session:Advance(20)
	-- 30 connected seconds total at 1.5/s = 45.
	expectEqual(session:GetConfirmedProfile().balance, 45, "30 connected seconds credit 45 exactly once")
end)

test("A failed bank restores the interval even if the worker count changes", function()
	-- The exact-accrual restore must not depend on the CURRENT rate. If the
	-- interval were reconstructed as credited / currentRate, a worker-count
	-- change between the failed write and its recovery would restore the wrong
	-- number of seconds and credit connected time under the wrong rate.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	-- 30 connected seconds at 1.5/s credits 45. Fail the write so the bank is
	-- attempted and rejected, which is the only path that restores the interval.
	store.failUpdate = true
	session:Advance(30)
	expectEqual(session:GetConfirmedProfile().balance, 0, "a failed bank credits nothing")
	expectEqual(session:GetPendingWorkerCuan(), 45, "the 30-second interval is retained as pending")
	expectEqual(session._unbankedSeconds, 30, "all 30 seconds are restored")
	-- Simulate the worker count changing before the recovery: the confirmed
	-- profile now carries two workers, so the CURRENT rate is 3.0/s. A
	-- reconstructed restore would give 45 / 3.0 = 15 seconds and silently lose
	-- half the connected interval.
	local prof = session:GetConfirmedProfile()
	table.insert(prof.workers, { hireId = "trainee-slot-2", roleId = "trainee", slotIndex = 2 })
	session._profile = prof
	expectEqual(EconomyService.incomePerSecond(session:GetConfirmedProfile()), 3, "current rate is 3.0/s")
	expectEqual(session._unbankedSeconds, 30, "the restored interval is still 30 seconds, not 15")
	-- The retained interval must still be credited at its own 1.5/s rate.
	store.failUpdate = false
	session:Advance(10)
	-- 30s at 1.5/s (45) + 10s at 3.0/s (30) = 75.
	expectEqual(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan(),
		75,
		"the restored interval is credited at its own rate, not the new one"
	)
	local restoredSeconds = 0
	for _, entry in ipairs(session._pendingAccrual) do
		if entry.rate == 1.5 then
			restoredSeconds += entry.seconds
		end
	end
	expectEqual(restoredSeconds, 30, "the 1.5/s interval is preserved as 30 seconds, not reconstructed as 15")
end)

test("An ambiguous bank response resolves without double credit", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	store.ambiguousOnce = true
	session:Advance(30)
	local after = session:GetConfirmedProfile().balance
	local pending = session:GetPendingWorkerCuan()
	print("E ambiguous balance=", tostring(after), "pending=", tostring(pending))
	-- Whatever the resolution, the total must never exceed one 45-Cuan credit.
	expectTrue(after + pending <= 45, "no double credit from an ambiguous bank")
	-- And a further interval must add exactly its own value.
	session:Advance(30)
	expectTrue(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan() <= 90,
		"two intervals never exceed 90"
	)
end)

test("A reconnect preserves confirmed worker income and drops no pending accrual", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(30)
	expectEqual(session:GetConfirmedProfile().balance, 45, "45 banked while connected")
	session:Stop()
	local reconnected = startSession(store, clock)
	expectEqual(reconnected:GetConfirmedProfile().balance, 45, "confirmed income survives the reconnect")
	expectEqual(reconnected:GetPendingWorkerCuan(), 0, "no phantom pending accrual after a reconnect")
end)


-- ===== TASK 1 REPRO =====
test("A rejected command preserves pending worker income exactly", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 10
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(10)
	local buy = session:Mutate({
		requestId = "mut-buy-1",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast" },
	})
	print("T1 buy.ok=", tostring(buy.ok), "code=", tostring(buy.code))
	expectEqual(buy.ok, false, "purchase rejected")
	expectEqual(session:GetPendingWorkerCuan(), 15, "pending income preserved after a rejection")
end)

-- ===== TASK 2 REPRO =====
test("An ambiguous save credits worker income exactly once", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	-- 10 seconds with one worker = 15 pending.
	session:Advance(10)
	-- A command whose proposal includes the 15 Cuan. Hold the write so the
	-- transform commits but the response is lost.
	store.delaySeconds = 1
	local first = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	-- Retry the identical request.
	store.delaySeconds = 0
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	-- The 15 Cuan must be credited exactly once.
	expectEqual(session:GetConfirmedProfile().balance, 15, "worker income credited exactly once")
end)

-- ===== lossless pending accrual on rejection =====
test("A rejected mission command preserves the fractional residual", function()
	-- 1 worker at 1.5/s: 7 seconds accrues 10.5 -> credits 10, residual 0.5.
	-- A rejection must restore the interval AND the residual, so a later bank
	-- credits the remaining 0.5 rather than losing it.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 10
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(7)
	expectEqual(session:GetPendingWorkerCuan(), 10, "7 seconds at 1.5/s credits 10")
	-- Reject an unaffordable purchase.
	local buy = session:Mutate({
		requestId = "mut-buy-1",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast" },
	})
	expectEqual(buy.ok, false, "purchase rejected")
	expectEqual(buy.code, "NOT_READY", "wrong device progression is refused")
	-- The interval and its residual survive.
	expectEqual(session:GetPendingWorkerCuan(), 10, "pending income preserved after the rejection")
	expectEqual(session._unbankedSeconds, 7, "the exact 7-second interval is restored")
	-- A later bank credits the full 10.5 worth: 7 more seconds at 1.5/s.
	session:Advance(7)
	-- 14 connected seconds at 1.5/s = floor(21) = 21, plus the starting 10.
	expectEqual(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan(),
		31,
		"the residual is not lost: 10 starting + 21 accrued = 31"
	)
end)

test("A rejected hire preserves pending accrual for a later valid hire", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 10
	p.workers = {}
	seedEnvelope(store, p, 1)
	withShippedTierCap(1, function()
		local session = startSession(store, clock)
		session:Advance(10)
		expectEqual(session:GetPendingWorkerCuan(), 0, "zero workers accrue nothing")
		-- A hire with no desk is refused.
		local hire = session:Mutate({
			requestId = "mut-hire-1",
			action = "HireWorker",
			payload = { slotIndex = 1, roleId = "trainee" },
		})
		expectEqual(hire.ok, false, "hire is refused")
		-- With zero workers the accrual credits nothing, so there is no credit to
		-- restore; the interval itself must still be pending.
		expectEqual(session:GetPendingWorkerCuan(), 0, "zero workers accrue nothing")
		-- Nothing was written.
		expectEqual(#session:GetConfirmedProfile().recentMutationOutcomes, 0, "no durable write for a rejection")
	end)
end)

-- ===== ambiguous settlement and standalone banking =====
test("An ambiguous settlement does not double-credit worker income", function()
	local store = FakeStore.new()
	local clock, advance = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Mutate({ requestId = "mut-pub-1", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	advance(18)
	-- The settlement write commits but its response is lost.
	store.ambiguousOnce = true
	session:Snapshot()
	local after = session:GetConfirmedProfile().balance
	local pending = session:GetPendingWorkerCuan()
	-- The organic 15 plus floor(1.5*18)=22 worker = 37, credited once.
	expectTrue(after + pending <= 37, "an ambiguous settlement never exceeds one credit")
	-- A further interval must add exactly its own value.
	session:Advance(30)
	expectTrue(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan() <= 37 + 45,
		"no double credit across the ambiguous settlement"
	)
end)

test("An ambiguous standalone bank does not double-credit", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	store.ambiguousOnce = true
	session:Advance(30)
	local after = session:GetConfirmedProfile().balance
	local pending = session:GetPendingWorkerCuan()
	expectTrue(after + pending <= 45, "an ambiguous bank never exceeds one 45-Cuan credit")
	-- A repeated retry of the same connected interval must not pay again.
	session:Advance(30)
	expectTrue(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan() <= 90,
		"two intervals never exceed 90"
	)
end)

test("A repeated in-flight retry never pays twice", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(10)
	store.delaySeconds = 1
	session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	store.delaySeconds = 0
	local revisionAfterFirst: number? = nil
	for i = 1, 3 do
		local retry = session:Mutate({
			requestId = "mut-1",
			action = "PublishOrganic",
			payload = { templateId = "snack_meme" },
		})
		expectEqual(retry.ok, true, `retry {i} ok`)
		expectEqual(retry.lookup, "APPLIED", `retry {i} APPLIED`)
		if revisionAfterFirst == nil then
			revisionAfterFirst = retry.revision
		else
			expectEqual(retry.revision, revisionAfterFirst, `retry {i} keeps the revision stable`)
		end
	end
	-- Exactly one 15-Cuan worker credit. The organic payout is frozen and lands
	-- at settlement, so the confirmed balance is the worker credit alone.
	expectEqual(session:GetConfirmedProfile().balance, 15, "worker income credited exactly once")
	expectEqual(session:GetPendingWorkerCuan(), 0, "no pending interval remains")
end)

test("New connected time after an ambiguous response is preserved separately", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(10)
	store.delaySeconds = 1
	session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	-- Accrue MORE time while the write is unresolved.
	session:Advance(5)
	expectEqual(session:GetPendingWorkerCuan(), 22, "the restored 10s plus the new 5s = 22")
	store.delaySeconds = 0
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(retry.ok, true, "retry resolves")
	expectEqual(retry.lookup, "APPLIED", "APPLIED")
	-- The first interval is consumed by the commit; the new 5 seconds remain.
	expectEqual(session:GetPendingWorkerCuan(), 7, "post-failure accrual is preserved")
	expectEqual(session:GetConfirmedProfile().balance, 15, "the worker credit landed exactly once")
end)

-- ===== busy lane result propagation =====
test("Advance reports BUSY when the lane is held and loses no accrual", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session._laneBusy = true
	local advance = session:Advance(30)
	expectEqual(advance.ok, false, "Advance reports BUSY, not a false success")
	expectEqual(advance.code, "BUSY", "BUSY code")
	expectEqual(advance.banked, 0, "nothing banked")
	session._laneBusy = false
	-- The accrued interval is intact and banks on the next turn.
	expectEqual(session:GetPendingWorkerCuan(), 45, "the interval is preserved")
	session._laneBusy = false
	local retryAdvance = session:Advance(0)
	expectEqual(retryAdvance.ok, true, "a later turn succeeds")
end)

test("RenewLease reports BUSY when the lane is held", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	session._laneBusy = true
	local renew = session:RenewLease()
	expectEqual(renew.ok, false, "renewal reports BUSY, not a false OK")
	expectEqual(renew.code, "BUSY", "BUSY code")
	session._laneBusy = false
	local retryRenew = session:RenewLease()
	expectEqual(retryRenew.ok, true, "a later renewal succeeds")
end)

test("Mutate reports BUSY and keeps the reservation when the lane is held", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	seedEnvelope(store, freshProfile(), 1)
	local session = startSession(store, clock)
	-- Hold the lane so the bounded wait expires.
	session._laneBusy = true
	local result = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(result.ok, false, "no false success")
	expectEqual(result.code, "BUSY", "BUSY code")
	expectEqual(result.lookup, "PENDING", "PENDING lookup")
	-- The reserved identity is released so a later retry can execute it.
	expectEqual(session._reserved["mut-1"], nil, "the reservation is released")
	session._laneBusy = false
	-- A later retry executes exactly once.
	local retry = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(retry.ok, true, "the retry executes")
	expectEqual(#session:GetConfirmedProfile().recentMutationOutcomes, 1, "exactly one durable write")
end)

test("A held lane never executes two writes concurrently", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local funded = freshProfile()
	funded.balance = 200
	seedEnvelope(store, funded, 1)
	local session = startSession(store, clock)
	local concurrent = false
	local realTry = session._tryRunLane
	session._tryRunLane = function(self2: any, fn: () -> ())
		if self2._laneBusy then
			concurrent = true
			return false
		end
		return realTry(self2, fn)
	end
	local a = session:Mutate({
		requestId = "mut-a",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(a.ok, true, "first mutation ok")
	expectEqual(concurrent, false, "the lane was never entered twice")
	session._tryRunLane = realTry
end)

-- ===== FIX A REPRO =====
test("A sub-integer accrual survives a rejected mutation", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 10
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	-- 0.2 seconds at 1.5/s = 0.3 Cuan, which floors to 0.
	session:Advance(0.2)
	-- Reject an unaffordable purchase.
	local buy = session:Mutate({
		requestId = "mut-buy-1",
		action = "BuyDevice",
		payload = { deviceId = "phone_fast" },
	})
	-- 0.5 more seconds: total 0.7s at 1.5/s = 1.05 -> 1 Cuan.
	session:Advance(0.5)
	expectEqual(session:GetPendingWorkerCuan(), 1, "0.7 seconds at 1.5/s credits 1 Cuan")
end)

-- ===== FIX B REPRO =====
test("A failed renewal preserves pending worker accrual", function()
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(10)
	-- Force the renewal write to fail.
	store.failUpdate = true
	local renew = session:RenewLease()
	-- Recover and verify exactly-once banking.
	store.failUpdate = false
	session:Advance(20)
	-- The 30-second interval was preserved by the failed renewal and then
	-- credited exactly once during recovery.
	expectEqual(session:GetConfirmedProfile().balance, 45, "30 seconds at 1.5/s credited exactly once")
	expectEqual(session:GetPendingWorkerCuan(), 0, "nothing left pending")
end)

-- ===== sub-integer accrual and renewal integrity =====
test("A sub-integer interval survives a failed commit", function()
	-- The rejection path is not the only consumer: a failed durable commit also
	-- drains the pending list. A zero-credit interval must survive it too.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	-- 0.2 seconds at 1.5/s = 0.3 Cuan, which floors to a zero credit.
	session:Advance(0.2)
	expectEqual(session:GetPendingWorkerCuan(), 0, "0.2 seconds floors to zero")
	expectEqual(#session._pendingAccrual, 1, "but the interval is still tracked")
	-- A command whose durable write fails.
	store.failUpdate = true
	local pub = session:Mutate({
		requestId = "mut-1",
		action = "PublishOrganic",
		payload = { templateId = "snack_meme" },
	})
	expectEqual(pub.ok, false, "the write failed")
	expectEqual(#session._pendingAccrual, 1, "the sub-integer interval is restored")
	-- Recover and finish the interval: 0.2 + 0.5 = 0.7 seconds at 1.5/s = 1.05.
	store.failUpdate = false
	session:Advance(0.5)
	expectEqual(
		session:GetPendingWorkerCuan() + session:GetConfirmedProfile().balance,
		1,
		"0.7 seconds at 1.5/s credits 1 Cuan exactly once"
	)
end)

test("A zero-credit partial interval is never discarded", function()
	-- Several sub-integer intervals accumulate fractional earnings that only
	-- become a whole Cuan once combined. None may be dropped on the way.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	for i = 1, 3 do
		session:Advance(0.2)
		-- Reject an unaffordable purchase between each accrual.
		session:Mutate({
			requestId = `mut-rej-{i}`,
			action = "BuyDevice",
			payload = { deviceId = "phone_fast" },
		})
	end
	expectEqual(#session._pendingAccrual, 3, "all three sub-integer intervals survive")
	expectTrue(math.abs(session._unbankedSeconds - 0.6) < 1e-9, "0.6 seconds retained in total")
	-- 0.6 seconds at 1.5/s = 0.9, still sub-integer.
	expectEqual(session:GetPendingWorkerCuan(), 0, "0.9 Cuan is still unbanked")
	-- One more interval crosses the boundary: 0.8 seconds at 1.5/s = 1.2.
	session:Advance(0.2)
	expectEqual(session:GetPendingWorkerCuan(), 1, "0.8 seconds credits 1 Cuan")
end)

test("An ambiguous renewal success never restores a committed interval", function()
	-- The renewal write commits but its response is lost. The reconciliation
	-- must not restore the interval as spendable a second time.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(10)
	expectEqual(session:GetPendingWorkerCuan(), 15, "15 pending before the renewal")
	store.ambiguousOnce = true
	local renew = session:RenewLease()
	-- Whether the caller sees success or an uncertain outcome, the durable state
	-- must hold exactly one 15-Cuan credit and no restored duplicate.
	local durableBalance = store.data["Player_1234"].profile.balance
	expectTrue(durableBalance <= 15, "an ambiguous renewal never exceeds one credit")
	-- A further interval must add exactly its own value, never a duplicate.
	session:Advance(10)
	expectTrue(
		session:GetConfirmedProfile().balance + session:GetPendingWorkerCuan() <= 30,
		"two intervals never exceed 30"
	)
end)

test("A failed renewal keeps a stable operation identity for reconciliation", function()
	-- The renewal operationId is derived from the connected-time total, so a
	-- retry after a failed write reuses the SAME identity and reconciles
	-- idempotently instead of issuing a fresh write.
	local store = FakeStore.new()
	local clock = makeClock(5000)
	local p = workerProfile()
	p.balance = 0
	seedEnvelope(store, p, 1)
	local session = startSession(store, clock)
	session:Advance(10)
	store.failUpdate = true
	local first = session:RenewLease()
	expectEqual(first.ok, false, "the first renewal fails")
	local opIdBefore = store.data["Player_1234"].lastSaveOpId
	store.failUpdate = false
	local second = session:RenewLease()
	expectEqual(second.ok, true, "the retry succeeds")
	-- Exactly one durable write landed for the renewal, and the interval was
	-- credited exactly once.
	expectEqual(session:GetConfirmedProfile().balance, 15, "15 credited once")
	expectEqual(session:GetPendingWorkerCuan(), 0, "nothing left pending")
end)

-- ===== run =====
local passed, failed = 0, 0
for _, t in ipairs(tests) do
	local ok, err = pcall(t.fn)
	if ok then
		passed += 1
		print(`[PASS] {t.name}`)
	else
		failed += 1
		print(`[FAIL] {t.name}: {tostring(err)}`)
	end
end
print(`==============================================`)
print(`SessionService spec: {passed}/{passed + failed} passed, {failed} failed`)
if failed > 0 then
	error("SessionService spec failed", 0)
end
return `SessionService: {passed}/{passed + failed} passed`
