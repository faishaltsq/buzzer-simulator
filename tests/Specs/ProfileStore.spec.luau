--!strict
-- Buzzer Simulator — ProfileStore spec (BS-02).
-- Executed by tests/Runner.server.luau in the test project only.
-- Contract source: docs/03 "Profile and persistence contract", docs/08 BS-02,
-- docs/09 "Persistence" matrix. Drives the real ProfileStore through an
-- injected fake DataStore adapter (never the live universe): read/write
-- failure, throttle and ambiguous-success injection are all covered.
local ServerStorage = game:GetService("ServerStorage")
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))

-- Deep copy for the fake adapter's cache boundary (mirrors the engine's
-- serialization: the cache holds an independent copy of the value).
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

-- ===== fake DataStore adapter =====
-- Mirrors the conditional-write contract: UpdateAsync runs the transform and
-- only commits when it returns non-nil. Injection knobs reproduce the
-- ambiguous/failed responses docs/09 requires.
--
-- It also reproduces the engine's real caching behaviour, because that is
-- exactly what ambiguous-write reconciliation must survive: GetAsync serves a
-- local copy for four seconds unless DataStoreGetOptions.UseCache is false.
-- `data` is the authoritative backend; `cache` is the local copy.
local FakeStore: any = {}
FakeStore.__index = FakeStore

function FakeStore.new(opts: { failGet: boolean?, failUpdate: boolean?, staleCache: boolean? }?)
	local self = setmetatable({}, FakeStore)
	self.data = {} :: { [string]: any }
	self.cache = {} :: { [string]: { value: any, storedAt: number } }
	self.opts = opts or {}
	self.updateCalls = 0
	self.getCalls = 0
	self.freshGetCalls = 0 -- backend-fresh reads only (UseCache=false)
	self.clock = function()
		return 5000
	end
	return self
end

function FakeStore:GetAsync(key: string, options: any?)
	(self :: any).getCalls += 1
	if self.opts.failGet then
		error("FakeStore: injected read failure", 0)
	end
	local useCache = true
	if options ~= nil then
		-- DataStoreGetOptions.UseCache = false bypasses the local cache.
		useCache = options.UseCache ~= false
	end
	if useCache then
		local entry: any = self.cache[key]
		if entry ~= nil and (self.clock() - entry.storedAt) < 4 then
			return entry.value
		end
	end
	(self :: any).freshGetCalls += 1
	local value = self.data[key]
	-- A backend read refreshes the local cache. The engine caches a serialized
	-- COPY, not a live reference, so a later mutation of the backend table must
	-- not be visible through the cache (that is what makes a cached read stale).
	self.cache[key] = { value = deepCopy(value), storedAt = self.clock() }
	return value
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
		-- A committed write refreshes the local cache copy too (again a copy,
		-- matching the engine's serialization boundary).
		self.cache[key] = { value = deepCopy(result), storedAt = self.clock() }
	end
	return result
end

function FakeStore:RemoveAsync(key: string)
	self.data[key] = nil
	self.cache[key] = nil
	return true
end

-- Test-only: seed a stale local cache entry, as if another server had written
-- the backend after our last read.
function FakeStore:seedStaleCache(key: string, value: any)
	self.cache[key] = { value = value, storedAt = self.clock() }
end

-- Test-only: drop the local cache entry for a key, as if the four-second
-- window had elapsed. Used when a test mutates the backend directly and wants
-- the next read to observe it (the engine would serve the cached copy until
-- the window expires).
function FakeStore:invalidateCache(key: string)
	self.cache[key] = nil
end

-- Fake HttpService for deterministic lease tokens.
local FakeHttp = {}
function FakeHttp:GenerateGUID(_wrapInBraces: boolean?): string
	FakeHttp._counter = (FakeHttp._counter or 0) + 1
	return `fake-token-{FakeHttp._counter}`
end

-- DataStoreGetOptions stand-in. Records the last UseCache flag so tests can
-- prove the reconciliation path asked for a backend-fresh read rather than a
-- possibly-stale cached one.
local FakeGetOptions = {}
FakeGetOptions.__index = FakeGetOptions
function FakeGetOptions.new(): any
	return setmetatable({ UseCache = true, seen = {} }, FakeGetOptions)
end
function FakeGetOptions:makeNoCache()
	self.UseCache = false
	table.insert(self.seen, false)
	return self
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

-- Records every retry sleep so tests can assert the bounded backoff schedule
-- without real waiting.
local waitLog: { number } = {}
local function newStore(clock: () -> number, opts: { failGet: boolean?, failUpdate: boolean?, staleCache: boolean? }?): (any, any)
	-- Defensive: a caller that forwards makeClock()'s second return (the
	-- setter) would send a function as opts and break the fake adapter.
	if typeof(opts) == "function" then
		opts = nil
	end
	table.clear(waitLog)
	local store = FakeStore.new(opts)
	-- The fake adapter's cache must age on the same clock the store reads, so
	-- a test can advance time and observe real four-second cache expiry.
	store.clock = clock
	local getOptions = FakeGetOptions.new()
	return store, ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-test",
		now = clock,
		noCacheOptions = function()
			return getOptions:makeNoCache()
		end,
		wait = function(seconds: number)
			table.insert(waitLog, seconds)
		end,
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
	-- corrupt the stored shape behind the store's back, and drop the cache
	-- entry so the next read actually observes the corruption (a still-fresh
	-- cache entry would legitimately serve the old valid copy for up to 4s).
	store.data["Player_1234"].profile = "not-a-table"
	store:invalidateCache("Player_1234")
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
	local store, ps = newStore(now)
	ps:Load()
	local opts: any = store.opts
	opts.failUpdate = true
	table.clear(waitLog)
	local save = ps:Save(validProfile(), "op-1")
	expectEqual(save.ok, false, "failing write not ok")
	expectEqual(save.code, "SAVE_UNAVAILABLE", "failing write code")
	expectEqual(save.revision, nil, "no revision reported on failure")
	-- the durable state was never written
	expectEqual(store.data["Player_1234"].lastSaveOpId, "init", "no operation persisted")
	-- and the retries were bounded with backoff, not a tight loop
	expectEqual(#waitLog, 2, "two bounded backoff sleeps")
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
	-- M1 state: PC Rumah equipped (workers require PC, docs/03) with both
	-- desks owned and both trainee seats filled.
	p.deviceId = "pc_rumah"
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
	-- resolvingPost: one weak post settled (75) and a second is in flight.
	-- docs/02 lifecycle: accepted -> resolvingPost -> readyToClaim, so a
	-- resolvingPost mission always has its matching pending post.
	p.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-3",
		contextId = "meal_time",
		status = "resolvingPost",
		accumulatedImpact = 75,
		postCount = 1,
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
	expectEqual(back.profile.activeMission.status, "resolvingPost", "mission status round-trips")
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

-- ===== ambiguous-write reconciliation uses a backend-fresh read =====
-- docs: "For immediate verification reads after a write, use GetAsync() with
-- DataStoreGetOptions.UseCache = false. By default, GetAsync() uses a local
-- four-second cache, so a normal verification read can return stale data."
test("Ambiguous-write reconciliation bypasses the local cache", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	-- Seed a stale local cache entry: another server wrote the backend after
	-- our last read, so the cached copy is now four-seconds-stale truth.
	store:seedStaleCache("Player_1234", { schemaVersion = 1, revision = 99, lastSaveOpId = "op-other" })
	-- An ambiguous write: the transform commits, then the response is lost.
	local applied = false
	local realUpdate = store.UpdateAsync
	store.UpdateAsync = function(self: any, key: string, transform: (any) -> any)
		(self :: any).updateCalls += 1
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
	local freshBefore = store.freshGetCalls
	local save = ps:Save(validProfile(), "op-amb")
	store.UpdateAsync = realUpdate
	expectEqual(save.ok, true, "ambiguous write resolves ok")
	-- The backend advanced to revision 3 when the ambiguous attempt landed.
	-- The stale cache claimed 99; reconciliation must report the real backend
	-- revision, proving it did not trust the cache.
	expectEqual(save.revision, 3, "resolves to the real backend revision, not the stale cache's 99")
	expectTrue(save.revision ~= 99, "never reports the stale cached revision")
	-- The reconciliation read must have gone to the backend.
	expectTrue(store.freshGetCalls > freshBefore, "reconciliation performed a backend-fresh read")
	expectEqual(store.data["Player_1234"].revision, 3, "backend holds exactly one committed revision")
end)

test("A stale cached read never drives reconciliation decisions", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	-- A cached copy that claims the operation already applied, while the
	-- backend says otherwise. Trusting the cache would report a phantom write.
	store:seedStaleCache("Player_1234", { schemaVersion = 1, revision = 2, lastSaveOpId = "op-phantom" })
	local realGet = store.GetAsync
	store.GetAsync = function(self: any, key: string, options: any?)
		-- Fail any cached (UseCache unset/true) read so the only usable path is
		-- the backend-fresh one; this proves the code asks for it.
		if options == nil or options.UseCache ~= false then
			error("FakeStore: cached read attempted during reconciliation", 0)
		end
		return realGet(self, key, options)
	end
	local save = ps:Save(validProfile(), "op-2")
	store.GetAsync = realGet
	expectEqual(save.ok, true, "save resolves without consulting the cache")
	expectEqual(save.revision, 3, "revision advances from the real backend state")
end)

test("Release reconciliation also bypasses the local cache", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	store:seedStaleCache("Player_1234", { schemaVersion = 1, revision = 2, lastSaveOpId = "rel-phantom" })
	local realUpdate = store.UpdateAsync
	local ambiguous = false
	store.UpdateAsync = function(self: any, key: string, transform: (any) -> any)
		(self :: any).updateCalls += 1
		local old = self.data[key]
		local result = transform(old)
		if result ~= nil then
			self.data[key] = result
			self.cache[key] = { value = deepCopy(result), storedAt = self.clock() }
		end
		if not ambiguous then
			ambiguous = true
			error("FakeStore: ambiguous release failure (response lost)", 0)
		end
		return result
	end
	local freshBefore = store.freshGetCalls
	local release = ps:Release("rel-1")
	store.UpdateAsync = realUpdate
	expectEqual(release.ok, true, "ambiguous release resolves ok")
	expectTrue(store.freshGetCalls > freshBefore, "release reconciliation performed a backend-fresh read")
	expectEqual(store.data["Player_1234"].lease.token, "", "backend lease actually cleared")
end)

test("The local cache expires after four seconds", function()
	local clock, advance = makeClock(5000)
	local store, ps = newStore(clock)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	-- Populate the cache, then let it age out: a subsequent cached read must
	-- fall through to the backend rather than serve the stale copy.
	local first = store:GetAsync("Player_1234")
	expectEqual(first.revision, 2, "cached read returns the stored value")
	store.data["Player_1234"].revision = 50 -- backend moves on
	advance(5001) -- still inside the four-second window
	expectEqual(store:GetAsync("Player_1234").revision, 2, "cached copy served inside the window")
	advance(5005) -- window elapsed
	expectEqual(store:GetAsync("Player_1234").revision, 50, "expired cache falls through to the backend")
end)

-- ===== idle lease expiry and renewal =====
test("An idle lease expires after 240s and is acquirable without data loss", function()
	local clock, advance = makeClock(5000)
	local store, ps = newStore(clock)
	ps:Load()
	local p = validProfile()
	p.balance = 4242
	ps:Save(p, "op-1")
	-- The session goes idle: no commands, no saves, no release. 239s later the
	-- lease is still ours and a competing server is refused.
	advance(5000 + ProfileStore.LEASE_DURATION - 1)
	local rival = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-rival",
		now = clock,
	})
	expectEqual(rival:Load().code, "LOCKED", "rival refused one second before expiry")
	-- At 240s the lease lapses and the rival takes over with data intact.
	advance(5000 + ProfileStore.LEASE_DURATION)
	local takeover = rival:Load()
	expectEqual(takeover.ok, true, "lease acquirable at expiry")
	expectEqual(takeover.envelope.profile.balance, 4242, "no data lost across idle expiry")
	-- The lapsed holder can no longer write.
	local lateSave = ps:Save(validProfile(), "op-late")
	expectEqual(lateSave.ok, false, "expired holder cannot write")
	expectEqual(lateSave.code, "LOCKED", "expired holder write is LOCKED")
end)

test("A renewal extends the lease without an unnecessary profile mutation", function()
	local clock, advance = makeClock(5000)
	local store, ps = newStore(clock)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	local revisionBefore = store.data["Player_1234"].revision
	local profileBefore = ProfileStore._deepCopy(store.data["Player_1234"].profile)
	-- Advance to the 90s renewal mark. Renewal is modelled as a conditional
	-- write carrying an unchanged profile: it must move only the lease fields,
	-- never the revision or any economic state.
	advance(5000 + ProfileStore.LEASE_RENEW)
	local renewal = ps:Save(ProfileStore._deepCopy(profileBefore), "op-renew")
	expectEqual(renewal.ok, true, "renewal write ok")
	local stored = store.data["Player_1234"]
	expectEqual(stored.revision, revisionBefore + 1, "renewal advances the revision once")
	expectEqual(stored.lease.expiresAt, 5000 + ProfileStore.LEASE_RENEW + ProfileStore.LEASE_DURATION, "lease extended another 240s from the write")
	-- No economic mutation rode along.
	expectEqual(stored.profile.balance, profileBefore.balance, "balance unchanged by renewal")
	expectEqual(stored.profile.lifetimeEarned, profileBefore.lifetimeEarned, "lifetime unchanged by renewal")
	expectEqual(stored.profile.nextPostSequence, profileBefore.nextPostSequence, "sequences unchanged by renewal")
	-- The renewed lease keeps a rival out for the full new window.
	local rival = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-rival",
		now = function() return 5000 + ProfileStore.LEASE_RENEW + 10 end,
	})
	expectEqual(rival:Load().code, "LOCKED", "rival refused during the renewed window")
end)

test("Renewal preserves the pending post and mission state exactly", function()
	local clock, advance = makeClock(5000)
	local store, ps = newStore(clock)
	ps:Load()
	local p = validProfile()
	-- A mission-tagged pending post in flight: docs/02 says resolvingPost means
	-- THIS mission's post is unsettled, so the pending post must be the
	-- mission's own, not an organic one.
	p.pendingPost = {
		postId = "post-1",
		mode = "mission",
		missionRunId = "run-1",
		contextId = "meal_time",
		templateId = "meal_meme",
		publishedAt = 100,
		settleAt = 118,
		finalImpact = 120,
		organicCuan = 15,
	}
	p.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-1",
		contextId = "meal_time",
		status = "resolvingPost",
		accumulatedImpact = 75,
		postCount = 1,
	}
	ps:Save(p, "op-1")
	local pendingBefore = ProfileStore._deepCopy(store.data["Player_1234"].profile.pendingPost)
	local missionBefore = ProfileStore._deepCopy(store.data["Player_1234"].profile.activeMission)
	advance(5000 + ProfileStore.LEASE_RENEW)
	local renewal = ps:Save(ProfileStore._deepCopy(store.data["Player_1234"].profile), "op-renew")
	expectEqual(renewal.ok, true, "renewal ok")
	local stored = store.data["Player_1234"].profile
	expectEqual(stored.pendingPost.postId, pendingBefore.postId, "pending post survives renewal")
	expectEqual(stored.pendingPost.organicCuan, pendingBefore.organicCuan, "frozen payout survives renewal")
	expectEqual(stored.activeMission.status, missionBefore.status, "mission status survives renewal")
	expectEqual(stored.activeMission.accumulatedImpact, missionBefore.accumulatedImpact, "mission impact survives renewal")
end)

test("Idle renewal cannot hand ownership to a competing server", function()
	local now = makeClock(5000)
	local store, ps = newStore(now)
	ps:Load()
	ps:Save(validProfile(), "op-1")
	local tokenBefore = store.data["Player_1234"].lease.token
	-- A renewal write whose lease token does not match must abort rather than
	-- let a second server stamp its own token in.
	local rival = ProfileStore.new(1234, {
		store = store,
		httpService = FakeHttp,
		jobId = "job-rival",
		now = function() return 5000 + ProfileStore.LEASE_RENEW end,
	})
	-- The rival never acquired a lease, so its Save must be refused outright.
	local rivalSave = rival:Save(validProfile(), "op-rival")
	expectEqual(rivalSave.ok, false, "unleased rival cannot renew")
	expectEqual(store.data["Player_1234"].lease.token, tokenBefore, "original token intact")
end)

-- ===== cross-field invariants =====
-- docs/03 invariants: device ownership, worker desk prerequisites, and
-- pending-post/active-mission consistency. Legitimate recoverable states must
-- NOT be rejected (an accepted mission with no post yet, a settled post
-- awaiting claim, a cheap starter phone).
test("Legitimate recoverable states are accepted, not rejected", function()
	local now = makeClock(5000)
	local _, ps = newStore(now)
	ps:Load()

	local function accept(label: string, mutate: (any) -> ())
		local p = validProfile()
		mutate(p)
		local save = ps:Save(p, `op-ok-{label}`)
		expectEqual(save.ok, true, `{label} must be accepted`)
	end

	-- cheap starter phone (price 0, owned from the start)
	accept("cheap starter phone", function(p) p.deviceId = "phone_cheap" end)
	-- purchased fast phone
	accept("fast phone", function(p) p.deviceId = "phone_fast" end)
	-- mission accepted, no post published yet
	accept("accepted mission with no post", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "accepted",
			accumulatedImpact = 0,
			postCount = 0,
		}
	end)
	-- mission with one weak post, still resolving (with its pending post)
	accept("resolving mission after one weak post", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "resolvingPost",
			accumulatedImpact = 75,
			postCount = 1,
		}
		p.pendingPost = {
			postId = "post-1",
			mode = "mission",
			missionRunId = "run-1",
			contextId = "meal_time",
			templateId = "meal_meme",
			publishedAt = 100,
			settleAt = 118,
			finalImpact = 120,
			organicCuan = 15,
		}
	end)
	-- mission ready to claim, no pending post left
	accept("mission ready to claim with no pending post", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "readyToClaim",
			accumulatedImpact = 120,
			postCount = 2,
		}
	end)
	-- pending organic post while a mission is active (explicitly allowed)
	accept("organic pending post alongside active mission", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "accepted",
			accumulatedImpact = 0,
			postCount = 0,
		}
		p.pendingPost = {
			postId = "post-9",
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			publishedAt = 10,
			settleAt = 28,
			finalImpact = 100,
			organicCuan = 15,
		}
	end)
	-- a desk owned with no worker hired yet (worker bought later)
	accept("owned desk without a worker", function(p)
		p.ownedDesks = { 1 }
	end)
	-- a worker hired into an owned desk
	accept("worker in an owned desk with the PC equipped", function(p)
		p.deviceId = "pc_rumah"
		p.ownedDesks = { 1, 2 }
		p.workers = { { hireId = "hire-1", roleId = "trainee", slotIndex = 1 } }
	end)
	-- A worker is only legitimate with the PC equipped; on a phone the same
	-- desk/worker combination must be rejected (see the reject list).
end)

test("Invalid cross-field states are rejected", function()
	local now = makeClock(5000)
	local _, ps = newStore(now)
	ps:Load()

	local function reject(label: string, mutate: (any) -> ())
		local p = validProfile()
		mutate(p)
		local save = ps:Save(p, `op-bad-{label}`)
		expectEqual(save.ok, false, `{label} must be rejected`)
		expectEqual(save.code, "INVALID_PROFILE", `{label} code`)
	end

	-- device ownership: unknown catalog device id
	reject("unknown device id", function(p) p.deviceId = "phone_gold_plated" end)
	-- worker PC prerequisite (docs/03: "workers ... require PC";
	-- docs/02: "worker cannot be hired without a PC, tier, paid desk, free
	-- seat, and funds"). The desk may be owned, but without the PC the hire
	-- could never have been admitted.
	reject("worker without the PC equipped (cheap phone)", function(p)
		p.deviceId = "phone_cheap"
		p.ownedDesks = { 1 }
		p.workers = { { hireId = "hire-1", roleId = "trainee", slotIndex = 1 } }
	end)
	reject("worker without the PC equipped (fast phone)", function(p)
		p.deviceId = "phone_fast"
		p.ownedDesks = { 1, 2 }
		p.workers = { { hireId = "hire-1", roleId = "trainee", slotIndex = 1 } }
	end)
	-- worker desk prerequisite: a worker must sit in an owned desk
	reject("worker without an owned desk", function(p)
		p.deviceId = "pc_rumah"
		p.workers = { { hireId = "hire-1", roleId = "trainee", slotIndex = 1 } }
	end)
	reject("worker in an unowned desk slot", function(p)
		p.deviceId = "pc_rumah"
		p.ownedDesks = { 1 }
		p.workers = { { hireId = "hire-1", roleId = "trainee", slotIndex = 2 } }
	end)
	-- pending-post / active-mission consistency
	reject("mission pending post whose run does not match the active mission", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "resolvingPost",
			accumulatedImpact = 75,
			postCount = 1,
		}
		p.pendingPost = {
			postId = "post-1",
			mode = "mission",
			missionRunId = "run-OTHER",
			contextId = "meal_time",
			templateId = "meal_meme",
			publishedAt = 10,
			settleAt = 28,
			finalImpact = 120,
			organicCuan = 15,
		}
	end)
	reject("mission pending post with no active mission", function(p)
		p.pendingPost = {
			postId = "post-1",
			mode = "mission",
			missionRunId = "run-1",
			contextId = "meal_time",
			templateId = "meal_meme",
			publishedAt = 10,
			settleAt = 28,
			finalImpact = 120,
			organicCuan = 15,
		}
	end)
	reject("resolvingPost status with no pending post", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "resolvingPost",
			accumulatedImpact = 75,
			postCount = 1,
		}
	end)
	-- The cap is on PUBLISHED posts per run and PublishPost admits while
	-- postCount < 2, so postCount == 2 with a post in flight is the legal
	-- SECOND (final) post -- see the dedicated in-flight tests. Only a count
	-- beyond the cap is corrupt.
	reject("pending mission post beyond the two-post cap", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "resolvingPost",
			accumulatedImpact = 200,
			postCount = 3,
		}
		p.pendingPost = {
			postId = "post-3",
			mode = "mission",
			missionRunId = "run-1",
			contextId = "meal_time",
			templateId = "meal_meme",
			publishedAt = 10,
			settleAt = 28,
			finalImpact = 120,
			organicCuan = 15,
		}
	end)
	reject("pending post settling before it was published", function(p)
		p.pendingPost = {
			postId = "post-1",
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			publishedAt = 100,
			settleAt = 99,
			finalImpact = 100,
			organicCuan = 15,
		}
	end)
	reject("readyToClaim status that never met the requirement", function(p)
		p.activeMission = {
			missionId = "food_stall_launch",
			runId = "run-1",
			contextId = "meal_time",
			status = "readyToClaim",
			accumulatedImpact = 75,
			postCount = 1,
		}
	end)
end)

-- ===== postCount semantics for in-flight campaign posts =====
-- Codex frozen contract (docs/03 action table): PublishPost admits while
-- postCount < 2, and "no more than two campaign posts/run". So postCount
-- counts posts ALREADY PUBLISHED, including the one currently in flight:
--   0 = accepted, nothing published
--   1 = first campaign post in flight
--   2 = second (final) campaign post in flight
-- A third post can never be admitted. Settlement moves the status, not the
-- count, so the same count is legal across both weak posts of a run.
local function missionInFlight(postCount: number, accumulated: number): any
	local p = validProfile()
	p.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-1",
		contextId = "meal_time",
		status = "resolvingPost",
		accumulatedImpact = accumulated,
		postCount = postCount,
	}
	p.pendingPost = {
		postId = `post-{postCount + 1}`,
		mode = "mission",
		missionRunId = "run-1",
		contextId = "meal_time",
		templateId = "meal_meme",
		publishedAt = 100,
		settleAt = 118,
		finalImpact = 120,
		organicCuan = 15,
	}
	return p
end

test("First in-flight campaign post (postCount=1) is a legal state", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local save = ps:Save(missionInFlight(1, 75), "op-first")
	expectEqual(save.ok, true, "first in-flight post accepted")
	local back = ps:GetConfirmedEnvelope()
	expectEqual(back.profile.activeMission.postCount, 1, "postCount 1 round-trips")
	expectEqual(back.profile.activeMission.status, "resolvingPost", "resolvingPost round-trips")
	expectEqual(back.profile.pendingPost.missionRunId, "run-1", "in-flight post bound to the run")
end)

test("Second in-flight campaign post (postCount=2) is a legal state", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- The weak-first-post path: the first weak post settled to 75 (short of
	-- 100), so a second post is published. PublishPost admitted it because
	-- postCount was 1 (< 2); after publishing, the count is 2 with the second
	-- post in flight. This state must persist, not be rejected.
	local save = ps:Save(missionInFlight(2, 75), "op-second")
	expectEqual(save.ok, true, "second in-flight post accepted")
	local back = ps:GetConfirmedEnvelope()
	expectEqual(back.profile.activeMission.postCount, 2, "postCount 2 round-trips")
	expectEqual(back.profile.pendingPost.postId, "post-3", "second post id round-trips")
end)

test("A third campaign post (postCount>2) is rejected", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local save = ps:Save(missionInFlight(3, 195), "op-third")
	expectEqual(save.ok, false, "third post rejected")
	expectEqual(save.code, "INVALID_PROFILE", "third post code")
end)

-- DECISION (postCount = 0 with a mission post in flight): REJECTED.
-- Justification: docs/03's PublishPost row admits the command while
-- `postCount < 2` and performs ONE durable save that both freezes the outcome
-- and creates the pending post; docs/02 adds that the server "persists the
-- pending post before replying". The count and the pending post are therefore
-- written in the same atomic write, so a mission post in flight always implies
-- postCount >= 1. A persisted 0 alongside an in-flight mission post can only
-- arise from a write that split the two fields, which the contract does not
-- permit -- it is corrupt state, not a recoverable one. Rejecting it is
-- consistent with the frozen lifecycle and does not affect the legitimate
-- two-weak-post journey, which runs 0 -> 1 -> 2.
test("postCount of 0 with a mission post in flight contradicts the atomic publish", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local save = ps:Save(missionInFlight(0, 0), "op-zero")
	expectEqual(save.ok, false, "postCount 0 with in-flight post rejected")
	expectEqual(save.code, "INVALID_PROFILE", "postCount 0 code")
end)

test("Malformed postCount never raises; it fails validation structurally", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local function reject(label: string, value: any)
		local p = missionInFlight(1, 75)
		p.activeMission.postCount = value
		local save = ps:Save(p, `op-bad-{label}`)
		expectEqual(save.ok, false, `postCount {label} rejected`)
		expectEqual(save.code, "INVALID_PROFILE", `postCount {label} code`)
	end
	reject("string", "two")
	reject("boolean", true)
	reject("table", {})
	reject("fractional", 1.5)
	reject("negative", -1)
	reject("huge", math.huge)
	reject("nan", 0 / 0)
end)

test("A readyToClaim mission holds no pending post and its count is final", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- docs/02 lifecycle: resolvingPost -> readyToClaim happens on settlement,
	-- which clears the pending post. The count stays at its final value.
	local p = validProfile()
	p.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-1",
		contextId = "meal_time",
		status = "readyToClaim",
		accumulatedImpact = 150,
		postCount = 2,
	}
	local save = ps:Save(p, "op-ready")
	expectEqual(save.ok, true, "readyToClaim with no pending post accepted")
	local back = ps:GetConfirmedEnvelope()
	expectEqual(back.profile.activeMission.postCount, 2, "final count preserved")
	expectEqual(back.profile.pendingPost, nil, "pending post cleared on readyToClaim")
end)

-- ===== operationId reuse with a different payload =====
test("The same operationId with a different payload is INVALID_PROFILE", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	expectEqual(ps:Save(first, "op-1").ok, true, "first save ok")
	-- Same ID, different content: this is a protocol violation, not a replay.
	local different = validProfile()
	different.balance = 999
	local second = ps:Save(different, "op-1")
	expectEqual(second.ok, false, "same ID with different payload rejected")
	expectEqual(second.code, "INVALID_PROFILE", "same ID different payload code")
	local detail: string = second.detail or ""
	expectTrue(detail:find("different profile payload") ~= nil, "detail names the conflict")
	-- The backend must still hold the ORIGINAL payload, unmodified.
	expectEqual(store.data["Player_1234"].profile.balance, 100, "original payload untouched")
	expectEqual(store.data["Player_1234"].lastSaveOpId, "op-1", "original operation id untouched")
end)

test("The same operationId with an identical payload still replays", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	expectEqual(ps:Save(validProfile(), "op-1").ok, true, "first save ok")
	local revBefore = store.data["Player_1234"].revision
	-- Same ID, same content (a fresh table with equal values): a legitimate
	-- retry after a lost response must still be idempotent.
	local retry = ps:Save(validProfile(), "op-1")
	expectEqual(retry.ok, true, "identical payload retry ok")
	expectEqual(retry.revision, revBefore, "identical payload retry does not bump revision")
	expectEqual(store.data["Player_1234"].revision, revBefore, "no durable change on identical retry")
end)

test("A different operationId with a different payload is a normal save", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	expectEqual(ps:Save(validProfile(), "op-1").ok, true, "first save ok")
	local changed = validProfile()
	changed.balance = 4242
	local second = ps:Save(changed, "op-2")
	expectEqual(second.ok, true, "distinct ID with distinct payload ok")
	expectEqual(store.data["Player_1234"].profile.balance, 4242, "new payload persisted")
end)

-- ===== transient write retry: bounded backoff and lease safety =====
test("Transient write failures retry with a bounded exponential backoff", function()
	-- Break writes only AFTER the lease is acquired: a store that fails from the
	-- first call cannot even Load, and Save would then report LOCKED.
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local opts: any = store.opts
	opts.failUpdate = true
	local save = ps:Save(validProfile(), "op-1")
	expectEqual(save.ok, false, "persistent failure surfaces SAVE_UNAVAILABLE")
	expectEqual(save.code, "SAVE_UNAVAILABLE", "persistent failure code")
	-- Bounded: exactly MAX_SAVE_ATTEMPTS-1 sleeps, growing 1s then 2s, then stop.
	expectEqual(#waitLog, 2, "two backoff sleeps for three attempts")
	expectEqual(waitLog[1], 1, "first backoff 1s")
	expectEqual(waitLog[2], 2, "second backoff 2s")
	-- The loop must not run away: exactly MAX_SAVE_ATTEMPTS save writes, plus
	-- the single lease-acquiring UpdateAsync that Load performs.
	expectEqual(store.updateCalls, 1 + 3, `store calls bounded, got {store.updateCalls}`)
end)

test("A single transient failure recovers after one backoff", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local attempts = 0
	local realUpdate = store.UpdateAsync
	store.UpdateAsync = function(self: any, key: string, transform: (any) -> any)
		attempts += 1
		if attempts == 1 then
			error("FakeStore: transient write failure", 0)
		end
		return realUpdate(self, key, transform)
	end
	local save = ps:Save(validProfile(), "op-1")
	store.UpdateAsync = realUpdate
	expectEqual(save.ok, true, "recovers after one transient failure")
	expectEqual(save.revision, 2, "recovers to revision 2")
	expectEqual(attempts, 2, "exactly one retry")
	expectEqual(#waitLog, 1, "one backoff sleep before the retry")
	expectEqual(waitLog[1], 1, "first backoff is 1s")
end)

test("Retrying a transient failure never violates lease safety", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local tokenBefore = store.data["Player_1234"].lease.token
	-- Fail twice so the retry path runs, then succeed.
	local failures = 0
	local realUpdate = store.UpdateAsync
	store.UpdateAsync = function(self: any, key: string, transform: (any) -> any)
		failures += 1
		if failures <= 2 then
			error("FakeStore: transient write failure", 0)
		end
		return realUpdate(self, key, transform)
	end
	local save = ps:Save(validProfile(), "op-1")
	store.UpdateAsync = realUpdate
	expectEqual(save.ok, true, "succeeds on the third attempt")
	-- The lease token must be preserved across every retry: a retry may never
	-- re-acquire or release ownership.
	expectEqual(store.data["Player_1234"].lease.token, tokenBefore, "lease token stable across retries")
	expectEqual(ps:GetLeaseToken(), tokenBefore, "instance still holds the same lease")
	expectEqual(save.revision, 2, "revision advanced exactly once")
	expectEqual(#waitLog, 2, "backoff slept before each retry")
end)

test("A retry cannot resurrect a lease lost mid-retry", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local realUpdate = store.UpdateAsync
	local stolen = false
	store.UpdateAsync = function(self: any, key: string, transform: (any) -> any)
		if not stolen then
			stolen = true
			error("FakeStore: transient write failure", 0)
		end
		-- On the retry, another server has taken the lease: the transform must
		-- abort rather than write with a stale token.
		self.data[key].lease.token = "stolen-token"
		return realUpdate(self, key, transform)
	end
	local save = ps:Save(validProfile(), "op-1")
	store.UpdateAsync = realUpdate
	expectEqual(save.ok, false, "write refused after lease loss")
	expectEqual(store.data["Player_1234"].lease.token, "stolen-token", "thief's token untouched")
	expectEqual(store.data["Player_1234"].lastSaveOpId, "init", "no profile write landed")
end)

-- ===== operationId fingerprinting across a reconnect =====
-- docs/03: the ring persists {requestId, action, intent, ...} "in the same
-- conditional write as the mutation" precisely so lookup works AFTER a
-- reconnect. The same-ID/different-payload guard must therefore survive a
-- ProfileStore recreation, not silently forget what an earlier session wrote.
local function instanceOn(backend: any, jobId: string, now: () -> number): any
	return ProfileStore.new(1234, {
		store = backend,
		httpService = FakeHttp,
		jobId = jobId,
		now = now,
		noCacheOptions = function()
			local getOptions = FakeGetOptions.new()
			return getOptions:makeNoCache()
		end,
		wait = function(seconds: number)
			table.insert(waitLog, seconds)
		end,
	})
end

test("Equal-value tables in separate allocations fingerprint identically", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	expectEqual(ps:Save(first, "op-det").ok, true, "first save ok")
	local revAfter = store.data["Player_1234"].revision
	-- A retry after a lost response carries an equal-valued but separately
	-- allocated table. It must be recognised as the same payload, not rejected.
	local retry = validProfile()
	retry.balance = 100
	local result = ps:Save(retry, "op-det")
	expectEqual(result.ok, true, "equal-value retry is idempotent")
	expectEqual(result.revision, revAfter, "equal-value retry does not bump revision")
end)

-- ===== identifier contract: requestId vs transaction identity =====
-- docs/03 separates two questions that must never be conflated:
--   * CLIENT-REQUEST identity -- `intent`, "the canonical bounded
--     action+payload", persisted in the 32-entry ring so it survives a
--     reconnect. "An identical request ID with different action/payload is
--     INVALID_INPUT, not a replay."
--   * TRANSACTION identity -- the whole-profile fingerprint, per-session,
--     answering "is this the exact durable state this operationId wrote?".
-- Comparing one against the other is a category error.
local INTENT_BUY_FAST = "BuyDevice|{\"deviceId\":\"phone_fast\"}"
local INTENT_BUY_PC = "BuyDevice|{\"deviceId\":\"pc_rumah\"}"

test("A reused requestId with a different intent is rejected after a reconnect", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	first.recentMutationOutcomes = {
		{
			requestId = "mut-0001",
			action = "BuyDevice",
			intent = INTENT_BUY_FAST,
			ok = true,
			code = "OK",
			revision = 2,
		},
	}
	expectEqual(ps:Save(first, "mut-0001", INTENT_BUY_FAST).ok, true, "session1 save ok")
	expectEqual(store.data["Player_1234"].profile.balance, 100, "session1 balance persisted")
	local revBefore = store.data["Player_1234"].revision
	ps:Release("rel-1")

	-- Reconnect: a brand-new instance whose in-memory transaction map is empty,
	-- rehydrating client-request identity from the durable ring.
	local reconnected = instanceOn(store, "job-reconnected", function()
		return 5241
	end)
	local load = reconnected:Load()
	expectEqual(load.ok, true, "reconnect load ok")
	expectEqual(load.envelope.profile.balance, 100, "reconnect sees the saved balance")

	-- Same requestId, DIFFERENT intent: a reused ID for different content.
	-- docs/03 requires INVALID_INPUT, and the durable state must not move.
	local different = validProfile()
	different.balance = 999
	local attempt = reconnected:Save(different, "mut-0001", INTENT_BUY_PC)
	expectEqual(attempt.ok, false, "reconnect reuse with different intent rejected")
	expectEqual(attempt.code, "INVALID_PROFILE", "reconnect reuse code")
	expectEqual(store.data["Player_1234"].profile.balance, 100, "durable balance untouched")
	expectEqual(store.data["Player_1234"].revision, revBefore, "durable revision untouched")
end)

test("An identical retry with the same intent is idempotent after a reconnect", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	first.recentMutationOutcomes = {
		{
			requestId = "mut-0001",
			action = "BuyDevice",
			intent = INTENT_BUY_FAST,
			ok = true,
			code = "OK",
			revision = 2,
		},
	}
	ps:Save(first, "mut-0001", INTENT_BUY_FAST)
	ps:Release("rel-1")

	local reconnected = instanceOn(store, "job-reconnected", function()
		return 5241
	end)
	reconnected:Load()
	-- The client retransmits the identical command after a lost reply. This is
	-- a legitimate replay and must be accepted, not rejected as a mismatch.
	local retry = validProfile()
	retry.balance = 100
	retry.recentMutationOutcomes = first.recentMutationOutcomes
	local result = reconnected:Save(retry, "mut-0001", INTENT_BUY_FAST)
	expectEqual(result.ok, true, "identical retry after reconnect accepted")
	expectEqual(result.code, "OK", "identical retry code")
	expectEqual(store.data["Player_1234"].profile.balance, 100, "durable balance unchanged")
end)

test("Equivalent tables with different key insertion order fingerprint identically", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local a = validProfile()
	a.balance = 100
	expectEqual(ps:Save(a, "op-order").ok, true, "first save ok")
	local revAfter = store.data["Player_1234"].revision
	-- Same values, different construction order. JSONEncode normalises key
	-- order, so this must be recognised as the same payload.
	local b = validProfile()
	b.nextPostSequence = 1
	b.ownPosts = {}
	b.pendingPost = nil
	b.activeMission = nil
	b.nextOrganicSequence = 0
	b.missionVariantCounters = {}
	b.recentMutationOutcomes = {}
	b.claimedRunIdsWindow = {}
	b.fractionalIncome = 0
	b.workers = {}
	b.ownedDesks = {}
	b.propertyId = "bedroom"
	b.deviceId = "phone_cheap"
	b.completedMissions = 1
	b.lifetimeEarned = 110
	b.balance = 100
	local result = ps:Save(b, "op-order")
	expectEqual(result.ok, true, "reordered-key retry is idempotent")
	expectEqual(result.revision, revAfter, "reordered-key retry does not bump revision")
end)

test("A save without an intent keeps per-session transaction identity only", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	expectEqual(ps:Save(first, "op-1").ok, true, "first save ok")
	-- Same session, same ID, different payload: still caught by the in-memory
	-- transaction check even though no intent was supplied.
	local different = validProfile()
	different.balance = 999
	local attempt = ps:Save(different, "op-1")
	expectEqual(attempt.ok, false, "same-session different payload rejected")
	expectEqual(attempt.code, "INVALID_PROFILE", "same-session code")
	expectEqual(store.data["Player_1234"].profile.balance, 100, "durable balance untouched")
end)

test("A fresh operationId still saves normally after a reconnect", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	first.recentMutationOutcomes = {
		{ requestId = "op-1", action = "BuyDevice", intent = "canonical-intent-op-1", ok = true, code = "OK", revision = 2 },
	}
	ps:Save(first, "op-1")
	ps:Release("rel-1")

	local reconnected = instanceOn(store, "job-reconnected", function()
		return 5241
	end)
	reconnected:Load()
	local changed = validProfile()
	changed.balance = 777
	local result = reconnected:Save(changed, "op-2")
	expectEqual(result.ok, true, "fresh operationId after reconnect ok")
	expectEqual(store.data["Player_1234"].profile.balance, 777, "new payload persisted")
end)

test("The in-memory guard still applies within a single session", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local first = validProfile()
	first.balance = 100
	expectEqual(ps:Save(first, "op-1").ok, true, "first save ok")
	local different = validProfile()
	different.balance = 999
	local attempt = ps:Save(different, "op-1")
	expectEqual(attempt.ok, false, "same-session reuse rejected")
	expectEqual(attempt.code, "INVALID_PROFILE", "same-session reuse code")
	expectEqual(store.data["Player_1234"].profile.balance, 100, "same-session balance untouched")
end)

-- ===== mission lifecycle journey (docs/02) =====
-- The full two-weak-post journey must remain persistable at every step, and
-- each transition must match the frozen lifecycle:
--   accepted -> resolvingPost -> accepted (impact short)
--                            -> readyToClaim -> claimed
local function missionRun(status: string, postCount: number, accumulated: number, pending: any?): any
	local p = validProfile()
	p.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-1",
		contextId = "meal_time",
		status = status,
		accumulatedImpact = accumulated,
		postCount = postCount,
	}
	p.pendingPost = pending
	return p
end

local function missionPost(postId: string, impact: number, cuan: number): any
	return {
		postId = postId,
		mode = "mission",
		missionRunId = "run-1",
		contextId = "meal_time",
		templateId = "meal_meme",
		publishedAt = 100,
		settleAt = 118,
		finalImpact = impact,
		organicCuan = cuan,
	}
end

test("Mission journey: accept, weak publish, short settle, weak publish, claim-ready", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()

	-- 1. AcceptMission: postCount 0, nothing pending.
	expectEqual(ps:Save(missionRun("accepted", 0, 0, nil), "op-accept").ok, true, "accept persists")

	-- 2. PublishPost #1 (weak, 75 < 100): the atomic write sets BOTH the
	--    pending post and postCount 1.
	expectEqual(
		ps:Save(missionRun("resolvingPost", 1, 75, missionPost("post-1", 75, 9)), "op-pub1").ok,
		true,
		"first weak post pending persists"
	)

	-- 3. Settlement of #1: impact short, so status returns to accepted and the
	--    pending post clears. The count stays 1 -- settlement moves the status,
	--    not the count.
	expectEqual(ps:Save(missionRun("accepted", 1, 75, nil), "op-settle1").ok, true, "first weak post settled persists")

	-- 4. PublishPost #2 (weak): admitted because postCount 1 < 2. The atomic
	--    write sets the pending post and postCount 2.
	expectEqual(
		ps:Save(missionRun("resolvingPost", 2, 75, missionPost("post-2", 75, 9)), "op-pub2").ok,
		true,
		"second weak post pending persists"
	)

	-- 5. Settlement of #2: 75 + 75 = 150 >= 100, so readyToClaim with no
	--    pending post left.
	local ready = ps:Save(missionRun("readyToClaim", 2, 150, nil), "op-settle2")
	expectEqual(ready.ok, true, "second weak post settled persists")
	local back = ps:GetConfirmedEnvelope()
	expectEqual(back.profile.activeMission.status, "readyToClaim", "status readyToClaim after two weak posts")
	expectEqual(back.profile.activeMission.accumulatedImpact, 150, "accumulated impact 150")
	expectEqual(back.profile.activeMission.postCount, 2, "final postCount 2")
	expectEqual(back.profile.pendingPost, nil, "no pending post once ready to claim")
end)

test("Mission journey: a strong first post reaches readyToClaim in one publish", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- docs/02: "a strong first always meets requirement". 120 >= 100.
	local result = ps:Save(missionRun("resolvingPost", 1, 120, missionPost("post-1", 120, 15)), "op-strong")
	expectEqual(result.ok, true, "strong first post pending persists")
	local settled = ps:Save(missionRun("readyToClaim", 1, 120, nil), "op-settle")
	expectEqual(settled.ok, true, "strong post settled to readyToClaim persists")
end)

test("Mission journey: a pending organic post may coexist with an accepted mission", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- docs/02: "Publishing an organic post while a mission is accepted/ready to
	-- claim is allowed, but never while any post is resolving."
	local p = missionRun("accepted", 0, 0, nil)
	p.pendingPost = {
		postId = "post-organic",
		mode = "organic",
		contextId = "organic_snack",
		templateId = "snack_meme",
		publishedAt = 100,
		settleAt = 118,
		finalImpact = 100,
		organicCuan = 15,
	}
	local result = ps:Save(p, "op-organic")
	expectEqual(result.ok, true, "organic pending post alongside accepted mission persists")
	local back = ps:GetConfirmedEnvelope()
	expectEqual(back.profile.pendingPost.mode, "organic", "organic post mode preserved")
	expectEqual(back.profile.activeMission.status, "accepted", "mission still accepted")
end)

test("Mission journey: an organic pending post may NOT coexist with resolvingPost", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- resolvingPost means THIS mission's post is in flight, so the single
	-- global pending slot cannot be an organic post at the same time.
	local p = missionRun("resolvingPost", 1, 75, nil)
	p.pendingPost = {
		postId = "post-organic",
		mode = "organic",
		contextId = "organic_snack",
		templateId = "snack_meme",
		publishedAt = 100,
		settleAt = 118,
		finalImpact = 100,
		organicCuan = 15,
	}
	local result = ps:Save(p, "op-mixed")
	expectEqual(result.ok, false, "organic post during resolvingPost rejected")
	expectEqual(result.code, "INVALID_PROFILE", "organic during resolvingPost code")
end)

-- ===== eviction and server-owned identifiers =====
-- docs/09: "Evicted entries are UNKNOWN, not evidence that retry is safe" and
-- "UNKNOWN in any session means no automatic retransmit/new-ID mutation".
-- ProfileStore's part of that contract: a requestId that has fallen out of the
-- 32-entry ring must NOT be treated as either applied or unapplied -- the
-- in-memory transaction map is the only thing that can answer for it, and that
-- is per-session.
test("An evicted requestId is not treated as applied after a reconnect", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- Fill the ring to its 32-entry bound, then push the target ID out.
	local ring: { any } = {}
	for i = 1, 32 do
		table.insert(ring, {
			requestId = `mut-old-{i}`,
			action = "PublishOrganic",
			intent = "PublishOrganic|{\"templateId\":\"snack_meme\"}",
			ok = true,
			code = "OK",
			revision = 2,
		})
	end
	local first = validProfile()
	first.balance = 100
	first.recentMutationOutcomes = ring
	ps:Save(first, "op-fill")
	ps:Release("rel-1")

	local reconnected = instanceOn(store, "job-reconnected", function()
		return 5241
	end)
	reconnected:Load()
	-- A requestId that is NOT in the ring carries no durable identity, so the
	-- reconnect guard must not fire for it -- it is UNKNOWN, not applied. The
	-- save proceeds on its own merits (validated profile, valid lease).
	local fresh = validProfile()
	fresh.balance = 200
	local result = reconnected:Save(fresh, "mut-never-seen", "PublishOrganic|{\"templateId\":\"snack_meme\"}")
	expectEqual(result.ok, true, "unknown requestId is not blocked as a replay")
	expectEqual(store.data["Player_1234"].profile.balance, 200, "unknown requestId save applies normally")
end)

test("A full 32-entry ring is accepted and a 33rd entry is rejected", function()
	local _, ps = newStore(makeClock(5000), nil)
	ps:Load()
	local ring: { any } = {}
	for i = 1, 32 do
		table.insert(ring, {
			requestId = `mut-{i}`,
			action = "PublishOrganic",
			intent = `intent-{i}`,
			ok = true,
			code = "OK",
			revision = 2,
		})
	end
	local full = validProfile()
	full.recentMutationOutcomes = ring
	expectEqual(ps:Save(full, "op-full").ok, true, "32-entry ring accepted")
	local over = validProfile()
	over.recentMutationOutcomes = table.clone(ring)
	table.insert(over.recentMutationOutcomes, {
		requestId = "mut-33",
		action = "PublishOrganic",
		intent = "intent-33",
		ok = true,
		code = "OK",
		revision = 2,
	})
	local result = ps:Save(over, "op-over")
	expectEqual(result.ok, false, "33-entry ring rejected")
	expectEqual(result.code, "INVALID_PROFILE", "33-entry ring code")
end)

test("Server-owned settlement IDs are distinct from client request IDs", function()
	local store, ps = newStore(makeClock(5000), nil)
	ps:Load()
	-- docs/03: "Server-owned settlement/bank operation IDs stay in the existing
	-- last-save/settlement reconciliation path, not in the client-request ring."
	-- A server-owned ID used as a Save operationId must not collide with a
	-- client requestId recorded in the ring.
	local first = validProfile()
	first.balance = 100
	first.recentMutationOutcomes = {
		{ requestId = "settle-post-1", action = "PublishOrganic", intent = "server-owned", ok = true, code = "OK", revision = 2 },
	}
	expectEqual(ps:Save(first, "settle-post-1").ok, true, "server-owned settlement save ok")
	local revAfter = store.data["Player_1234"].revision
	-- Retrying the same server-owned ID with the same payload is idempotent.
	local retry = validProfile()
	retry.balance = 100
	retry.recentMutationOutcomes = first.recentMutationOutcomes
	local result = ps:Save(retry, "settle-post-1")
	expectEqual(result.ok, true, "server-owned ID retry idempotent")
	expectEqual(result.revision, revAfter, "server-owned ID retry does not bump revision")
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
