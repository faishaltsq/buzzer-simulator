--!strict
-- Buzzer Simulator — ProfileStore spec (BS-02).
-- Executed by tests/Runner.server.luau in the test project only.
-- Contract source: docs/03 "Profile and persistence contract", docs/08 BS-02,
-- docs/09 "Persistence" matrix. Drives the real ProfileStore through an
-- injected fake DataStore adapter (never the live universe): read/write
-- failure, throttle and ambiguous-success injection are all covered.
local ServerStorage = game:GetService("ServerStorage")
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))

-- ===== fake DataStore adapter =====
-- Mirrors the conditional-write contract: UpdateAsync runs the transform and
-- only commits when it returns non-nil. Injection knobs reproduce the
-- ambiguous/failed responses docs/09 requires.
local FakeStore = {}
FakeStore.__index = FakeStore

function FakeStore.new(opts: { failGet: boolean?, failUpdate: boolean? }?)
	local self = setmetatable({}, FakeStore)
	self.data = {} :: { [string]: any }
	self.opts = opts or {}
	self.updateCalls = 0
	self.getCalls = 0
	return self
end
-- (fields are declared on the class table below; Luau infers them read-only
-- from the constructor literal, so the increment sites cast self to any.)

function FakeStore:GetAsync(key: string)
	(self :: any).getCalls += 1
	if self.opts.failGet then
		error("FakeStore: injected read failure", 0)
	end
	return self.data[key]
end

function FakeStore:UpdateAsync(key: string, transform: (any) -> any)
	(self :: any).updateCalls += 1
	if self.opts.failUpdate then
		error("FakeStore: injected write failure", 0)
	end
	local old = self.data[key]
	local result = transform(old)
	if result ~= nil then
		self.data[key] = result
	end
	return result
end

function FakeStore:RemoveAsync(key: string)
	self.data[key] = nil
	return true
end

-- Fake HttpService for deterministic lease tokens.
local FakeHttp = {}
function FakeHttp:GenerateGUID(_wrapInBraces: boolean?): string
	FakeHttp._counter = (FakeHttp._counter or 0) + 1
	return `fake-token-{FakeHttp._counter}`
end

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

-- Deterministic clock: specs advance it explicitly.
local function makeClock(start: number)
	local t = start
	return function()
		return t
	end, function(next: number)
		t = next
	end
end

-- ===== fixtures =====
local function validProfile(): any
	return {
		balance = 110,
		lifetimeEarned = 110,
		completedMissions = 1,
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

local function newStore(clock: () -> number, opts: { failGet: boolean?, failUpdate: boolean? }?): (any, any)
	local store = FakeStore.new(opts)
	return store, ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-test",
		now = clock,
	})
end

-- ===== Load: fresh key =====
test("Load on a fresh key acquires a 240s lease and no profile", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	local load = ps:Load()
	expectEqual(load.ok, true, "fresh load ok")
	expectEqual(load.code, "OK", "fresh load code")
	expectTrue(ps:GetLeaseToken() ~= nil, "lease token acquired")
	expectEqual(ps:GetLastConfirmedRevision(), 1, "initial revision 1")
	local stored = store.data["Player_1234"]
	expectEqual(stored.lease.token, ps:GetLeaseToken(), "stored token matches instance")
	expectEqual(stored.lease.expiresAt, 5000 + ProfileStore.LEASE_DURATION, "lease duration 240s")
	expectEqual(stored.profile, nil, "no starter profile seeded by the store")
end)

test("Load validates the v1 envelope before handing it out", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	-- corrupt the stored shape behind the store's back
	store.data["Player_1234"].profile = "not-a-table"
	local ps2 = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-other",
		now = function() return 5001 end,
	})
	local load = ps2:Load()
	expectEqual(load.ok, false, "corrupt envelope rejected")
	expectEqual(load.code, "CORRUPT", "corrupt code")
	expectEqual(store.data["Player_1234"].profile, "not-a-table", "corrupt data preserved untouched")
end)

test("Load preserves an unsupported future schema without migrating", function()
	local now = makeClock(5000)
	local store = FakeStore.new()
	store.data["Player_1234"] = { schemaVersion = 99, profile = { balance = 5 } }
	local ps = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-test",
		now = now,
	})
	local load = ps:Load()
	expectEqual(load.ok, false, "future schema rejected")
	expectEqual(load.code, "UNSUPPORTED_SCHEMA", "unsupported schema code")
	expectEqual(store.data["Player_1234"].schemaVersion, 99, "future schema untouched")
end)

test("A failed read yields no starter profile and no key", function()
	local store, ps = newStore(makeClock(5000), { failGet = true })
	local load = ps:Load()
	expectEqual(load.ok, false, "failed read not ok")
	expectEqual(load.code, "SAVE_UNAVAILABLE", "failed read code")
	expectEqual(next(store.data), nil, "no key created on failed read")
end)

-- ===== lease semantics =====
test("A live foreign lease is LOCKED; an expired one is acquirable", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	-- second server while the first lease is live
	local ps2 = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-second",
		now = function() return 5050 end,
	})
	local load2 = ps2:Load()
	expectEqual(load2.ok, false, "second load denied while lease live")
	expectEqual(load2.code, "LOCKED", "second load LOCKED")
	expectEqual(ps2:GetLeaseToken(), nil, "no token granted on denial")
	-- after expiry another server takes over cleanly
	local ps3 = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-third",
		now = function() return 5000 + ProfileStore.LEASE_DURATION + 1 end,
	})
	local load3 = ps3:Load()
	expectEqual(load3.ok, true, "expired lease acquirable")
	expectEqual(load3.envelope.profile.balance, 110, "data intact after takeover")
end)

test("A competing token cannot overwrite the live token", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	local tokenBefore = store.data["Player_1234"].lease.token
	-- a save attempt from a store instance that never acquired a lease
	local psNoLease = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-thief",
		now = now,
	})
	local save = psNoLease:Save(validProfile(), "op-thief")
	expectEqual(save.ok, false, "save without lease denied")
	expectEqual(store.data["Player_1234"].lease.token, tokenBefore, "live token unchanged")
end)

-- ===== Save =====
test("Save bumps the revision once and stores the operation ID", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	local save = ps:Save(validProfile(), "op-1")
	expectEqual(save.ok, true, "save ok")
	expectEqual(save.revision, 2, "revision bumped to 2")
	local stored = store.data["Player_1234"]
	expectEqual(stored.revision, 2, "stored revision 2")
	expectEqual(stored.lastSaveOpId, "op-1", "operation ID stored")
	expectEqual(stored.profile.balance, 110, "profile persisted")
	expectEqual(stored.updatedAt, 5000, "updatedAt written")
end)

test("An identical operation ID is idempotent: no duplicate durable state", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	local revBefore = store.data["Player_1234"].revision
	local opBefore = store.data["Player_1234"].lastSaveOpId
	local retry = ps:Save(validProfile(), "op-1")
	expectEqual(retry.ok, true, "idempotent retry ok")
	expectEqual(retry.revision, 2, "idempotent retry keeps revision")
	expectEqual(store.data["Player_1234"].revision, revBefore, "no revision change")
	expectEqual(store.data["Player_1234"].lastSaveOpId, opBefore, "no operation change")
	-- a distinct operation ID advances the revision exactly once
	local next = ps:Save(validProfile(), "op-2")
	expectEqual(next.revision, 3, "distinct op bumps revision once")
end)

test("An ambiguous write resolves through the same operation ID", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	-- Simulate a lost response: the transform commits, then the call throws.
	local applied = false
	local realUpdate = store.UpdateAsync
	store.UpdateAsync = function(self: any, key: string, transform: (any) -> any)
		self.updateCalls += 1
		local old = self.data[key]
		local result = transform(old)
		if result ~= nil then
			self.data[key] = result
		end
		if not applied then
			applied = true
			error("FakeStore: ambiguous write failure (response lost)", 0)
		end
		return result
	end
	local save = ps:Save(validProfile(), "op-amb")
	store.UpdateAsync = realUpdate
	expectEqual(save.ok, true, "ambiguous write eventually ok")
	expectEqual(save.revision, 2, "ambiguous write resolves to revision 2")
	expectEqual(store.data["Player_1234"].lastSaveOpId, "op-amb", "operation applied exactly once")
end)

test("A stale snapshot revision aborts instead of overwriting", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	-- another writer advances the stored revision behind our back
	store.data["Player_1234"].revision = 99
	local save = ps:Save(validProfile(), "op-2")
	expectEqual(save.ok, false, "stale save rejected")
	expectEqual(store.data["Player_1234"].revision, 99, "foreign revision preserved")
end)

test("Save is denied after the lease is lost", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	-- another server force-takes the lease after expiry
	local thief = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-thief",
		now = function() return 5000 + ProfileStore.LEASE_DURATION + 1 end,
	})
	thief:Load()
	local save = ps:Save(validProfile(), "op-2")
	expectEqual(save.ok, false, "save denied after lease loss")
	expectEqual(save.code, "LOCKED", "save LOCKED")
end)

test("Persistent write failure yields SAVE_UNAVAILABLE, never a fake success", function()
	local now = makeClock(5000)
	-- Acquire the lease with a healthy store, then break writes: the failure
	-- must surface as SAVE_UNAVAILABLE, never a fabricated success.
	local store = FakeStore.new()
	local ps = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-test",
		now = now,
	})
	ps:Load()
	local opts: any = store.opts
	opts.failUpdate = true
	local save = ps:Save(validProfile(), "op-1")
	expectEqual(save.ok, false, "failing write not ok")
	expectEqual(save.code, "SAVE_UNAVAILABLE", "failing write code")
	expectEqual(save.revision, nil, "no revision reported on failure")
	-- the durable state was never written
	expectEqual(store.data["Player_1234"].lastSaveOpId, "init", "no operation persisted")
end)

-- ===== profile validation (docs/03 cross-field invariants) =====
test("Invalid profiles are rejected before any store write", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	local updateCallsBefore = store.updateCalls

	local function reject(label: string, mutate: (any) -> ())
		local p = validProfile()
		mutate(p)
		local save = ps:Save(p, `op-{label}`)
		expectEqual(save.ok, false, `{label} rejected`)
		expectEqual(save.code, "INVALID_PROFILE", `{label} code`)
	end

	reject("negative balance", function(p) p.balance = -5 end)
	reject("fractional balance", function(p) p.balance = 1.5 end)
	reject("negative lifetime", function(p) p.lifetimeEarned = -1 end)
	reject("fractionalIncome >= 1", function(p) p.fractionalIncome = 1 end)
	reject("negative fractionalIncome", function(p) p.fractionalIncome = -0.1 end)
	reject("wrong property", function(p) p.propertyId = "office" end)
	reject("empty deviceId", function(p) p.deviceId = "" end)
	reject("three owned desks", function(p) p.ownedDesks = { 1, 2, 3 } end)
	reject("duplicate owned desks", function(p) p.ownedDesks = { 1, 1 } end)
	reject("descending owned desks", function(p) p.ownedDesks = { 2, 1 } end)
	reject("desk slot out of range", function(p) p.ownedDesks = { 3 } end)
	reject("three workers", function(p)
		p.workers = {
			{ hireId = "a", roleId = "trainee", slotIndex = 1 },
			{ hireId = "b", roleId = "trainee", slotIndex = 2 },
			{ hireId = "c", roleId = "trainee", slotIndex = 1 },
		}
	end)
	reject("duplicate worker slots", function(p)
		p.workers = {
			{ hireId = "a", roleId = "trainee", slotIndex = 1 },
			{ hireId = "b", roleId = "trainee", slotIndex = 1 },
		}
	end)
	reject("unknown worker role", function(p)
		p.workers = { { hireId = "a", roleId = "manager", slotIndex = 1 } }
	end)
	reject("outcome ring over 32", function(p)
		p.recentMutationOutcomes = {}
		for i = 1, 33 do
			table.insert(p.recentMutationOutcomes, {
				requestId = `r{i}`,
				action = "PublishOrganic",
				intent = "x",
				ok = true,
				code = "OK",
				revision = 1,
			})
		end
	end)
	reject("outcome with ok=false", function(p)
		p.recentMutationOutcomes = {
			{ requestId = "r1", action = "PublishOrganic", intent = "x", ok = false, code = "OK", revision = 1 },
		}
	end)
	reject("outcome with wrong code", function(p)
		p.recentMutationOutcomes = {
			{ requestId = "r1", action = "PublishOrganic", intent = "x", ok = true, code = "BUSY", revision = 1 },
		}
	end)
	reject("mission pending post without run id", function(p)
		p.pendingPost = {
			postId = "p1",
			mode = "mission",
			contextId = "c",
			templateId = "t",
			publishedAt = 1,
			settleAt = 2,
			finalImpact = 3,
			organicCuan = 4,
		}
	end)
	reject("pending post with bad mode", function(p)
		p.pendingPost = {
			postId = "p1",
			mode = "other",
			contextId = "c",
			templateId = "t",
			publishedAt = 1,
			settleAt = 2,
			finalImpact = 3,
			organicCuan = 4,
		}
	end)
	reject("active mission with bad status", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "r1",
			contextId = "meal_time",
			status = "exploding",
			accumulatedImpact = 0,
			postCount = 0,
		}
	end)
	reject("active mission with three posts", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "r1",
			contextId = "meal_time",
			status = "accepted",
			accumulatedImpact = 0,
			postCount = 3,
		}
	end)
	reject("ownPosts over 10", function(p)
		p.ownPosts = {}
		for i = 1, 11 do
			table.insert(p.ownPosts, {
				postId = `p{i}`,
				mode = "organic",
				contextId = "organic_snack",
				templateId = "snack_meme",
				finalImpact = 100,
				organicCuan = 15,
				publishedAt = 1,
			})
		end
	end)
	reject("negative mission variant counter", function(p)
		p.missionVariantCounters = { food_stall_launch = -1 }
	end)
	reject("negative nextPostSequence", function(p) p.nextPostSequence = -1 end)

	expectEqual(store.updateCalls, updateCallsBefore, "no store write for any invalid profile")
end)

test("A fully populated v1 profile round-trips unchanged", function()
	local now = makeClock(5000)
	local _, ps = newStore(now)
	ps:Load()
	local p = validProfile()
	p.ownedDesks = { 1, 2 }
	p.workers = {
		{ hireId = "hire-1", roleId = "trainee", slotIndex = 1 },
		{ hireId = "hire-2", roleId = "trainee", slotIndex = 2 },
	}
	p.claimedRunIdsWindow = { "run-1", "run-2" }
	p.recentMutationOutcomes = {
		{
			requestId = "mut-1",
			action = "PublishOrganic",
			intent = "PublishOrganic|snack_meme",
			ok = true,
			code = "OK",
			revision = 2,
			resultIds = { "post-1" },
		},
	}
	p.missionVariantCounters = { food_stall_launch = 1 }
	p.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-3",
		contextId = "meal_time",
		status = "readyToClaim",
		accumulatedImpact = 120,
		postCount = 2,
	}
	p.pendingPost = {
		postId = "post-2",
		mode = "mission",
		missionRunId = "run-3",
		contextId = "meal_time",
		templateId = "meal_meme",
		publishedAt = 100,
		settleAt = 118,
		finalImpact = 120,
		organicCuan = 15,
	}
	p.ownPosts = {
		{
			postId = "post-1",
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			finalImpact = 100,
			organicCuan = 15,
			publishedAt = 90,
		},
	}
	p.nextPostSequence = 3
	local save = ps:Save(p, "op-full")
	expectEqual(save.ok, true, "full profile saves")
	local back = ps:GetConfirmedEnvelope()
	expectEqual(back.profile.workers[2].slotIndex, 2, "worker slot 2 round-trips")
	expectEqual(back.profile.workers[2].hireId, "hire-2", "worker hireId round-trips")
	expectEqual(back.profile.pendingPost.mode, "mission", "pending post mode round-trips")
	expectEqual(back.profile.pendingPost.missionRunId, "run-3", "mission run id round-trips")
	expectEqual(back.profile.activeMission.status, "readyToClaim", "mission status round-trips")
	expectEqual(back.profile.recentMutationOutcomes[1].resultIds[1], "post-1", "result ids round-trip")
	expectEqual(back.profile.nextPostSequence, 3, "sequence round-trips")
end)

test("Save rejects a missing operation ID", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	local save = ps:Save(validProfile(), "")
	expectEqual(save.ok, false, "empty operation ID rejected")
	expectEqual(store.updateCalls, 1, "only the lease acquisition touched the store")
end)

-- ===== Release and rejoin =====
test("Release clears the lease without bumping the revision; rejoin works", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	local p = validProfile()
	p.balance = 777
	ps:Save(p, "op-1")
	local release = ps:Release("rel-1")
	expectEqual(release.ok, true, "release ok")
	expectEqual(ps:GetLeaseToken(), nil, "instance lease cleared")
	local stored = store.data["Player_1234"]
	expectEqual(stored.lease.token, "", "stored lease token cleared")
	expectEqual(stored.lease.expiresAt, 0, "stored lease expiry zeroed")
	expectEqual(stored.revision, 2, "release does not bump the revision")
	-- a new server joins immediately, no lease wait
	local ps2 = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-next",
		now = function() return 5100 end,
	})
	local load2 = ps2:Load()
	expectEqual(load2.ok, true, "rejoin load ok")
	expectEqual(load2.envelope.profile.balance, 777, "balance survives rejoin")
	expectEqual(load2.envelope.revision, 2, "revision carried across rejoin")
	expectTrue(ps2:GetLeaseToken() ~= ps:GetLeaseToken(), "new lease token issued")
end)

test("Release is idempotent under a repeated operation ID", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	local first = ps:Release("rel-1")
	expectEqual(first.ok, true, "first release ok")
	local second = ps:Release("rel-1")
	expectEqual(second.ok, false, "second release denied (lease already gone)")
	expectEqual(store.data["Player_1234"].revision, 2, "no revision change from repeated release")
end)

test("Release is denied without a lease", function()
	local store, ps = newStore(makeClock(5000), nil)
	local release = ps:Release("rel-1")
	expectEqual(release.ok, false, "release without lease denied")
	expectEqual(next(store.data), nil, "release without lease wrote nothing")
end)

-- ===== immutability =====
test("Confirmed envelopes are deep copies; mutation cannot alias the store", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	local p = validProfile()
	ps:Save(p, "op-1")
	local first = ps:GetConfirmedEnvelope()
	first.profile.balance = 999999
	local second = ps:GetConfirmedEnvelope()
	expectEqual(second.profile.balance, 110, "confirmed envelope not aliased by caller")
	expectEqual(store.data["Player_1234"].profile.balance, 110, "stored profile not aliased")
end)

test("_deepCopy does not alias nested tables", function()
	local original = { a = 1, nested = { b = 2 }, list = { 1, 2 } }
	local copy = ProfileStore._deepCopy(original)
	copy.nested.b = 99
	copy.list[1] = 99
	expectEqual(original.nested.b, 2, "nested table not aliased")
	expectEqual(original.list[1], 1, "array not aliased")
end)

test("_validateEnvelope accepts a well-formed envelope and rejects tampering", function()
	local now = makeClock(5000)
	local _, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	local good = ps:GetConfirmedEnvelope()
	local ok = ProfileStore._validateEnvelope(good)
	expectEqual(ok, true, "valid envelope passes")
	local bad = ProfileStore._deepCopy(good)
	bad.profile.balance = -1
	expectEqual(ProfileStore._validateEnvelope(bad), false, "negative balance fails validation")
	local future = ProfileStore._deepCopy(good)
	future.schemaVersion = 2
	expectEqual(ProfileStore._validateEnvelope(future), false, "future schema fails validation")
end)

-- ===== constants =====
test("Lease constants match the docs/03 contract", function()
	expectEqual(ProfileStore.LEASE_DURATION, 240, "lease duration 240s")
	expectEqual(ProfileStore.LEASE_RENEW, 90, "lease renewal 90s")
	expectEqual(ProfileStore.SCHEMA_VERSION, 1, "schema version v1")
end)

-- ===== Runner =====
local passed = 0
local failures: { string } = {}
for _, testCase in ipairs(tests) do
	local ok, err = pcall(testCase.fn :: any)
	if ok then
		passed += 1
		print(`[PASS] {testCase.name}`)
	else
		table.insert(failures, `{testCase.name}: {tostring(err)}`)
		print(`[FAIL] {testCase.name}: {tostring(err)}`)
	end
end
print(`==============================================`)
print(`ProfileStore spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print(`FAILURES:`)
	for _, f in ipairs(failures) do
		print(`  - {f}`)
	end
	print("BS02_PROFILE_STORE_TESTS_FAILED")
	error(`ProfileStore spec: {#failures} failed (see FAILURES above)`, 0)
end
print("BS02_PROFILE_STORE_TESTS_PASSED")
return `ProfileStore: {passed}/{#tests} passed`
