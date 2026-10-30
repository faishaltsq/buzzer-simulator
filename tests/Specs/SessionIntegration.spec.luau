--!strict
-- Real SessionService/ProfileStore/domain paths; only transport and clocks are fake.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SessionService = require(ServerStorage:WaitForChild("SessionService"))
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end
local function equal(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`, 0)
	end
end
local function check(value: any, label: string)
	if not value then
		error(label, 0)
	end
end
local copy = ProfileStore._deepCopy
local function encode(value: any): string
	if typeof(value) ~= "table" then
		return typeof(value) .. ":" .. tostring(value)
	end
	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: any, b: any): boolean
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, encode(key) .. "=" .. encode(value[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
local guid = 0
local http: any = {}
function http:GenerateGUID(): string
	guid += 1
	return `integration-guid-{guid}`
end
function http:JSONEncode(value: any): string
	return encode(value)
end

local FakeStore: any = {}
FakeStore.__index = FakeStore
function FakeStore.new(): any
	return setmetatable({ data = {}, gets = 0, updates = 0, commits = 0,
		failReads = false, failWrites = false, loseResponses = false, beforeUpdate = nil,
		operations = {},
	}, FakeStore)
end
function FakeStore:GetAsync(key: string, _options: any?): any
	self.gets += 1
	if self.failReads then
		error("injected read failure", 0)
	end
	return copy(self.data[key])
end
function FakeStore:UpdateAsync(key: string, transform: (any) -> any): any
	self.updates += 1
	if self.beforeUpdate ~= nil then
		local callback = self.beforeUpdate
		self.beforeUpdate = nil
		callback()
	end
	if self.failWrites then
		error("injected write failure", 0)
	end
	local nextValue = transform(copy(self.data[key]))
	if nextValue ~= nil then
		self.data[key] = copy(nextValue)
		self.commits += 1
		table.insert(self.operations, nextValue.lastSaveOpId)
	end
	if self.loseResponses then
		error("injected committed response loss", 0)
	end
	return copy(nextValue)
end

local function fresh(): any
	return {
		balance = 0, lifetimeEarned = 0, completedMissions = 0,
		deviceId = "phone_cheap", propertyId = "bedroom", ownedDesks = {}, workers = {},
		fractionalIncome = 0, claimedRunIdsWindow = {}, recentMutationOutcomes = {},
		missionVariantCounters = {}, nextOrganicSequence = 0, activeMission = nil,
		pendingPost = nil, ownPosts = {}, nextPostSequence = 1,
	}
end
local function worker(): any
	local p = fresh()
	p.balance = 10000
	p.lifetimeEarned = 10000
	p.completedMissions = 10
	p.deviceId = "pc_rumah"
	p.ownedDesks = { 1, 2 }
	p.workers = { { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 } }
	return p
end
local function fixture(profile: any?, connectedClock: boolean?): (any, any, any)
	local store = FakeStore.new()
	local clock = { wall = 1000, connected = 0, waits = 0 }
	if profile ~= nil then
		store.data.Player_1234 = {
			schemaVersion = 1, revision = 1, lastSaveOpId = "seed", updatedAt = 900,
			profile = copy(profile), lease = { token = "", jobId = "seed", expiresAt = 0 },
		}
	end
	local session = SessionService.new({
		userId = 1234, store = store, httpService = http, jobId = "integration",
		now = function() return clock.wall end,
		connectedNow = if connectedClock then function() return clock.connected end else nil,
		noCacheOptions = function() return { UseCache = false } end,
		wait = function(_seconds: number) clock.waits += 1 end,
	})
	return session, store, clock
end
local function loaded(profile: any?, connectedClock: boolean?): (any, any, any)
	local session, store, clock = fixture(profile or fresh(), connectedClock)
	check(session:Start().ok, "existing profile loads")
	return session, store, clock
end
local function publish(session: any, id: string?): any
	return session:Mutate({ requestId = id or "publish-0001", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
end
local function withTierTwo(fn: () -> ())
	local previous = Catalog.V0Shipped.maxShippedTier
	Catalog.V0Shipped.maxShippedTier = 2
	local ok, err = pcall(fn)
	Catalog.V0Shipped.maxShippedTier = previous
	if not ok then error(err, 0) end
end
local function resume(thread: thread)
	local ok, err = coroutine.resume(thread)
	check(ok, tostring(err))
end

test("Initialization requires an explicitly acquired empty lease", function()
	local session, store = fixture()
	equal(session:InitializeStarter().ok, false, "not started")
	equal(store.updates, 0, "no write")
	equal(session:GetConfirmedProfile(), nil, "no invented profile")
	equal(session:ReadSnapshot().code, "NOT_READY", "read while loading is explicit")
	equal(session:Snapshot().code, "NOT_READY", "network snapshot while loading")
end)

test("Reads and initialization remain unavailable during a yielding Start", function()
	local session, store = fixture()
	store.beforeUpdate = function() coroutine.yield("held acquisition") end
	local result: any = nil
	local thread = coroutine.create(function() result = session:Start() end)
	resume(thread)
	equal(session:ReadSnapshot().code, "NOT_READY", "no profile while loading")
	equal(session:Snapshot().code, "NOT_READY", "no network settlement while loading")
	equal(session:InitializeStarter().ok, false, "no premature seed")
	equal(session:Start().code, "BUSY", "concurrent acquire refused")
	equal(store.updates, 1, "only original acquisition")
	resume(thread)
	equal(result.code, "NOT_READY", "acquisition confirms empty")
	check(session:InitializeStarter().ok, "now safe to initialize")
end)

test("Fresh join conditionally writes the exact frozen v1 starter", function()
	local session, store = fixture()
	equal(session:Start().code, "NOT_READY", "empty lease")
	local token = store.data.Player_1234.lease.token
	equal(store.data.Player_1234.profile, nil, "Start does not invent data")
	check(session:InitializeStarter().ok, "starter confirmed")
	equal(encode(session:GetConfirmedProfile()), encode(fresh()), "all starter fields")
	check(ProfileStore._validateEnvelope(store.data.Player_1234), "valid v1 envelope")
	equal(store.data.Player_1234.lease.token, token, "same lease token")
	equal(store.updates, 2, "one acquisition and one Save")
	check(session:IsStarted(), "started without reacquisition")
	check(session:IsWritable(), "writable after confirmation")
end)

test("Repeated initialization never overwrites confirmed progress", function()
	local session, store = fixture()
	session:Start()
	check(session:InitializeStarter().ok, "first init")
	check(publish(session).ok, "real domain progress")
	local revision, writes = session:GetRevision(), store.updates
	check(session:InitializeStarter().ok, "repeat is idempotent")
	equal(session:GetRevision(), revision, "revision unchanged")
	equal(store.updates, writes, "no repeated Save")
	equal(session:GetConfirmedProfile().nextPostSequence, 2, "post progress survives")
end)

test("A second Start cannot reacquire the empty session's lease", function()
	local session, store = fixture()
	session:Start()
	local token, writes = store.data.Player_1234.lease.token, store.updates
	equal(session:Start().code, "BUSY", "repeat Start refused")
	equal(store.updates, writes, "no acquire retry")
	equal(store.data.Player_1234.lease.token, token, "token retained")
	check(session:InitializeStarter().ok, "original lease still initializes")
end)

test("Failed initial reads cannot seed or acquire a profile", function()
	local session, store = fixture()
	store.failReads = true
	equal(session:Start().code, "SAVE_UNAVAILABLE", "read failure")
	equal(session:InitializeStarter().ok, false, "cannot initialize")
	equal(store.updates, 0, "zero writes")
	equal(store.data.Player_1234, nil, "key remains absent")
end)

test("Failed lease acquisition cannot authorize starter initialization", function()
	local session, store = fixture()
	store.failWrites = true
	equal(session:Start().code, "SAVE_UNAVAILABLE", "acquisition failed")
	local writes = store.updates
	equal(session:InitializeStarter().ok, false, "no acquired lease")
	equal(store.updates, writes, "no seed retry")
end)

test("Corrupt saved data is preserved byte-for-byte", function()
	local session, store = fixture()
	store.data.Player_1234 = { schemaVersion = 1, broken = "do-not-repair" }
	local before = encode(store.data.Player_1234)
	equal(session:Start().code, "CORRUPT", "corrupt rejected")
	equal(session:InitializeStarter().ok, false, "no seed")
	equal(store.updates, 0, "no write")
	equal(encode(store.data.Player_1234), before, "raw data untouched")
end)

test("Unsupported schema is preserved without migration or starter data", function()
	local session, store = fixture()
	store.data.Player_1234 = { schemaVersion = 99, future = { balance = 123 } }
	local before = encode(store.data.Player_1234)
	equal(session:Start().code, "UNSUPPORTED_SCHEMA", "future schema refused")
	equal(session:InitializeStarter().ok, false, "no seed")
	equal(store.updates, 0, "no write")
	equal(encode(store.data.Player_1234), before, "future data untouched")
end)

test("A competing lease cannot initialize an existing profile", function()
	local owner, store = loaded()
	local contender = SessionService.new({ userId = 1234, store = store, httpService = http,
		now = function() return 1000 end, wait = function() end })
	equal(contender:Start().code, "LOCKED", "foreign lease refused")
	local before = encode(store.data.Player_1234)
	equal(contender:InitializeStarter().ok, false, "no unauthorized starter")
	equal(encode(store.data.Player_1234), before, "owner unchanged")
	check(owner:IsWritable(), "owner remains writable")
end)

test("A competing lease cannot initialize an empty transitional envelope", function()
	local owner, store = fixture()
	owner:Start()
	local contender = SessionService.new({ userId = 1234, store = store, httpService = http,
		now = function() return 1000 end, wait = function() end })
	equal(contender:Start().code, "LOCKED", "empty key still leased")
	equal(contender:InitializeStarter().ok, false, "no seed")
	equal(store.data.Player_1234.profile, nil, "empty owner not overwritten")
	check(owner:InitializeStarter().ok, "only owner can initialize")
end)

test("Failed initialization retries its exact proposal and stable identity", function()
	local session, store = fixture()
	session:Start()
	store.failWrites = true
	equal(session:InitializeStarter().ok, false, "write failed")
	local pending = session._pendingWrite
	equal(session:GetConfirmedProfile(), nil, "unconfirmed starter invisible")
	equal(session:IsStarted(), false, "not prematurely started")
	store.failWrites = false
	check(session:InitializeStarter().ok, "retry confirms")
	equal(store.data.Player_1234.lastSaveOpId, pending.opId, "same operation")
	equal(encode(store.data.Player_1234.profile), encode(pending.profile), "same proposal")
	equal(store.data.Player_1234.revision, 2, "one profile revision")
end)

test("Lost initialization responses remain unconfirmed until exact reconciliation", function()
	local session, store = fixture()
	session:Start()
	store.loseResponses = true
	equal(session:InitializeStarter().ok, false, "unknown response")
	equal(session:GetConfirmedProfile(), nil, "not manufactured success")
	local identity = store.data.Player_1234.lastSaveOpId
	store.loseResponses = false
	check(session:Reconcile().ok, "exact initialization recovered")
	check(session:IsStarted(), "reconciliation activates session")
	equal(store.data.Player_1234.lastSaveOpId, identity, "same durable operation")
	equal(store.data.Player_1234.revision, 2, "no second revision")
end)

test("Leaving after failed initialization reconciles before releasing", function()
	local session, store = fixture()
	session:Start()
	store.failWrites = true
	session:InitializeStarter()
	equal(session:Stop().ok, false, "cannot release unresolved initialization")
	check(store.data.Player_1234.lease.token ~= "", "lease retained")
	store.failWrites = false
	check(session:Stop().ok, "safe retry finishes and releases")
	equal(store.data.Player_1234.lease.token, "", "lease released")
	equal(encode(store.data.Player_1234.profile), encode(fresh()), "only starter persisted")
end)

test("Leaving an unused empty lease permits a later clean initialization", function()
	local session, store = fixture()
	session:Start()
	check(session:Stop().ok, "empty lease released")
	local rejoin = SessionService.new({ userId = 1234, store = store, httpService = http,
		now = function() return 1001 end, wait = function() end })
	equal(rejoin:Start().code, "NOT_READY", "released empty envelope recognized")
	check(rejoin:InitializeStarter().ok, "later join seeds safely")
end)

test("Rejoin preserves durable progress without starter replacement", function()
	local session, store = fixture()
	session:Start()
	session:InitializeStarter()
	check(publish(session).ok, "publish confirmed")
	check(session:Stop().ok, "leave released")
	local rejoin = SessionService.new({ userId = 1234, store = store, httpService = http,
		now = function() return 1001 end, wait = function() end })
	check(rejoin:Start().ok, "rejoin loaded")
	equal(rejoin:GetConfirmedProfile().nextPostSequence, 2, "sequence retained")
	equal(rejoin:ReadSnapshot("publish-0001").lookup.status, "APPLIED", "durable replay survived")
	local writes = store.updates
	check(rejoin:InitializeStarter().ok, "already initialized")
	equal(store.updates, writes, "no replacement Save")
end)

test("Local lease expiry denies writes without consulting the backend", function()
	local session, store, clock = loaded()
	equal(session:GetLeaseExpiresAt(), 1240, "acquired expiry")
	clock.wall = 1240
	local writable, code = session:IsWritable()
	equal(writable, false, "expiry boundary is exclusive")
	equal(code, "LOCKED", "expired lease")
	local writes = store.updates
	equal(publish(session).code, "LOCKED", "mutation refused")
	equal(store.updates, writes, "no expired write")
end)

test("A local token mismatch is not a writable lease", function()
	local session = loaded()
	session._store._leaseToken = "not-the-confirmed-token"
	equal(session:IsWritable(), false, "token mismatch denied")
	equal(session:GetLeaseExpiresAt(), 1240, "expiry alone does not authorize")
end)

test("ReadSnapshot cannot settle a due post or write", function()
	local session, store, clock = loaded()
	check(publish(session).ok, "pending post created")
	clock.wall = session:GetConfirmedProfile().pendingPost.settleAt
	local writes, revision = store.updates, session:GetRevision()
	local result = session:ReadSnapshot("publish-0001")
	check(result.snapshot.pendingPost ~= nil, "due post still pending")
	equal(result.snapshot.balance, 0, "no unconfirmed settlement payout")
	equal(result.lookup.status, "APPLIED", "publish remains applied")
	equal(session:GetRevision(), revision, "no revision change")
	equal(store.updates, writes, "read-only projection")
end)

test("Snapshot cannot settle a due post after local lease expiry", function()
	local session, store, clock = loaded()
	check(publish(session).ok, "pending post confirmed")
	clock.wall = session:GetLeaseExpiresAt()
	local writes = store.updates
	local result = session:Snapshot()
	check(result.ok, "last confirmed state remains readable")
	check(result.snapshot.pendingPost ~= nil, "due post not settled with expired lease")
	equal(result.snapshot.balance, 0, "no payout")
	equal(result.snapshot.saveStatus, "BUSY", "read-only status surfaced")
	equal(store.updates, writes, "no expired settlement attempt")
end)

test("Snapshot cannot launch another settlement while a save is unhealthy", function()
	local session, store, clock = loaded()
	check(publish(session).ok, "pending post confirmed")
	clock.wall = session:GetConfirmedProfile().pendingPost.settleAt
	store.failWrites = true
	session:Snapshot()
	local pending = session._pendingWrite
	check(pending ~= nil, "failed settlement retained")
	store.failWrites = false
	local writes = store.updates
	local state = session:Snapshot()
	equal(state.snapshot.saveStatus, "SAVE_UNAVAILABLE", "confirmed read-only status")
	equal(store.updates, writes, "ordinary query never retries a failed save")
	check(session:Reconcile().ok, "explicit same-proposal reconciliation")
	equal(store.data.Player_1234.lastSaveOpId, pending.opId, "original settlement identity")
	equal(session:GetConfirmedProfile().balance, 15, "exactly one settlement")
end)

test("A yielding mutation stays PENDING and reads never wait for its lane", function()
	local session, store, clock = loaded()
	store.beforeUpdate = function() coroutine.yield("held") end
	local result: any = nil
	local thread = coroutine.create(function() result = publish(session) end)
	resume(thread)
	equal(coroutine.status(thread), "suspended", "write really yielded")
	local calls, waits = store.updates, clock.waits
	local state = session:ReadSnapshot("publish-0001")
	equal(state.lookup.status, "PENDING", "reservation visible")
	equal(state.snapshot.pendingPost, nil, "proposal not exposed")
	equal(session:Reconcile().code, "BUSY", "reconcile does not wait")
	equal(publish(session).lookup, "PENDING", "duplicate stays pending")
	equal(store.updates, calls, "no concurrent Save")
	equal(clock.waits, waits, "read and retry do not wait")
	resume(thread)
	check(result.ok, "admitted mutation finishes")
	equal(session:ReadSnapshot("publish-0001").lookup.status, "APPLIED", "now durable")
end)

test("Conflicting held request identities are rejected before a second Save", function()
	local session, store = loaded()
	store.beforeUpdate = function() coroutine.yield("held") end
	local thread = coroutine.create(function() publish(session) end)
	resume(thread)
	local writes = store.updates
	local conflict = session:Mutate({ requestId = "publish-0001", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	equal(conflict.code, "INVALID_INPUT", "reserved canonical intent compared")
	equal(store.updates, writes, "no second Save")
	resume(thread)
end)

test("A cached domain rejection cannot replay under a conflicting intent", function()
	local session, store = loaded()
	local first = session:Mutate({ requestId = "reject-0001", action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	equal(first.lookup, "REJECTED", "definite rejection cached")
	local writes = store.updates
	local conflict = session:Mutate({ requestId = "reject-0001", action = "PublishOrganic", payload = { templateId = "snack_meme" } })
	equal(conflict.code, "INVALID_INPUT", "different intent rejected")
	equal(store.updates, writes, "no economic write")
end)

test("Live results and their identities have a finite eviction bound", function()
	local session, store = loaded()
	local writes = store.updates
	for index = 1, 300 do
		session:Mutate({ requestId = `reject-{index}`, action = "BuyDevice", payload = { deviceId = "phone_fast" } })
	end
	local results, intents = 0, 0
	for _ in pairs(session._liveResults) do results += 1 end
	for _ in pairs(session._liveIntents) do intents += 1 end
	equal(results, SessionService.MAX_LIVE_RESULTS, "bounded results")
	equal(intents, results, "no orphan identity growth")
	equal(#session._liveOrder, results, "bounded eviction queue")
	equal(session:ReadSnapshot("reject-1").lookup.status, "UNKNOWN", "evicted rejection is unknown")
	equal(session:ReadSnapshot("reject-300").lookup.status, "REJECTED", "recent rejection retained")
	equal(store.updates, writes, "rejections did not write")
end)

test("Durable success outranks a stale live rejection during lookup", function()
	local session = loaded()
	check(publish(session).ok, "real durable success")
	session._liveResults["publish-0001"] = { ok = false, code = "BUSY", revision = 1 }
	local lookup = session:ReadSnapshot("publish-0001").lookup
	equal(lookup.status, "APPLIED", "durable ring wins")
	equal(lookup.originalResult.ok, true, "successful original outcome")
end)

test("Unresolved writes prevent scheduler settlement and unrelated operations", function()
	local session, store, clock = loaded()
	store.loseResponses = true
	equal(publish(session).ok, false, "response unresolved")
	local pending = session._pendingWrite
	clock.wall = store.data.Player_1234.profile.pendingPost.settleAt
	local revision = store.data.Player_1234.revision
	session:Advance(0)
	session:Snapshot()
	equal(session._pendingWrite.opId, pending.opId, "same proposal retained")
	equal(store.data.Player_1234.revision, revision, "no settlement or newer write races")
	equal(session:ReadSnapshot("publish-0001").lookup.status, "PENDING", "retained server proposal pending")
	store.loseResponses = false
	check(session:Reconcile().ok, "original proposal reconciles")
	equal(session:ReadSnapshot("publish-0001").lookup.status, "APPLIED", "applied without client reexecute")
	equal(store.data.Player_1234.revision, revision, "reconciliation adds no revision")
end)

test("Unknown lookup and empty reconciliation never execute domain operations", function()
	local session, store = loaded()
	local writes = store.updates
	equal(session:ReadSnapshot("unknown-0001").lookup.status, "UNKNOWN", "unknown remains unknown")
	check(session:Reconcile().ok, "nothing to reconcile")
	equal(store.updates, writes, "no guessed mutation")
end)

test("Production clock admission freezes on save failure and resumes without catch-up", function()
	local session, store, clock = loaded(worker(), true)
	clock.connected = 10
	session:CaptureConnectedTime()
	equal(session:GetPendingWorkerCuan(), 15, "healthy connected interval admitted")
	store.failWrites = true
	equal(publish(session).ok, false, "write failure")
	clock.connected = 30
	session:CaptureConnectedTime()
	equal(session:GetPendingWorkerCuan(), 15, "unhealthy time refused")
	equal(session:Advance(5).code, "INVALID_INPUT", "clock sessions cannot inject fresh dt")
	store.failWrites = false
	check(session:Reconcile().ok, "exact proposal recovered")
	equal(session:GetConfirmedProfile().balance, 10015, "previous interval retained exactly once")
	clock.connected = 40
	session:CaptureConnectedTime()
	equal(session:GetPendingWorkerCuan(), 15, "only resumed ten seconds accrue")
end)

test("Production clock stops accrual at local lease loss", function()
	local session, _store, clock = loaded(worker(), true)
	clock.connected = 10
	session:CaptureConnectedTime()
	clock.wall = 1240
	clock.connected = 50
	session:CaptureConnectedTime()
	equal(session:IsWritable(), false, "expired")
	equal(session:GetPendingWorkerCuan(), 15, "already admitted interval retained; no lost-lease income")
end)

test("Held first hire cannot retroactively pay zero-worker save latency", function()
	withTierTwo(function()
		local p = worker()
		p.workers = {}
		local session, store, clock = loaded(p, true)
		clock.connected = 10
		session:CaptureConnectedTime()
		store.beforeUpdate = function() coroutine.yield("held") end
		local result: any = nil
		local thread = coroutine.create(function()
			result = session:Mutate({ requestId = "hire-first", action = "HireWorker", payload = { slotIndex = 1, roleId = "trainee" } })
		end)
		resume(thread)
		clock.connected = 20
		session:CaptureConnectedTime()
		clock.connected = 30
		resume(thread)
		check(result.ok, "hire confirmed")
		equal(session:GetPendingWorkerCuan(), 0, "pre-confirmation time had zero workers")
		clock.connected = 40
		session:CaptureConnectedTime()
		equal(session:GetPendingWorkerCuan(), 15, "only post-confirmation interval earns")
	end)
end)

test("Held second hire tags sampled and unsampled latency at the old rate", function()
	withTierTwo(function()
		local session, store, clock = loaded(worker(), true)
		clock.connected = 10
		session:CaptureConnectedTime()
		store.beforeUpdate = function() coroutine.yield("held") end
		local result: any = nil
		local thread = coroutine.create(function()
			result = session:Mutate({ requestId = "hire-second", action = "HireWorker", payload = { slotIndex = 2, roleId = "trainee" } })
		end)
		resume(thread)
		clock.connected = 20
		session:CaptureConnectedTime()
		clock.connected = 30
		resume(thread)
		check(result.ok, "second hire confirmed")
		equal(session:GetPendingWorkerCuan(), 30, "twenty seconds of latency at 1.5/s")
		clock.connected = 40
		session:CaptureConnectedTime()
		equal(session:GetPendingWorkerCuan(), 60, "new ten seconds at 3/s")
	end)
end)

test("Zero-worker clock samples never accumulate interval records", function()
	local session, _store, clock = loaded(fresh(), true)
	for index = 1, 1000 do
		clock.connected = index / 8
		session:CaptureConnectedTime()
	end
	equal(#session._pendingAccrual, 0, "zero-rate intervals omitted")
	equal(session:GetPendingWorkerCuan(), 0, "no zero-worker income")
end)

test("Rate-tagged pending intervals remain bounded without losing connected income", function()
	local session, _store, clock = loaded(worker(), true)
	for index = 1, 1000 do
		clock.connected = index / 8
		session:CaptureConnectedTime()
	end
	check(#session._pendingAccrual <= SessionService.MAX_PENDING_INTERVALS, "finite pending memory")
	equal(session:GetPendingWorkerCuan(), 187, "all 125 seconds retained at 1.5/s")
	check(session:Advance(0).ok, "bounded chunks eventually bank")
	equal(session:GetConfirmedProfile().balance, 10187, "confirmed bank keeps all elapsed time")
end)

test("A retained proposal cannot overwrite an unexpectedly replaced confirmed base", function()
	local p = worker()
	p.balance = 0
	local session, store = loaded(p)
	store.failWrites = true
	session:Advance(30)
	local replacement = session:GetConfirmedProfile()
	table.insert(replacement.workers, { hireId = "trainee-slot-2", roleId = "trainee", slotIndex = 2 })
	session._profile = replacement
	store.failWrites = false
	local writes = store.updates
	equal(session:Advance(10).ok, false, "stale base refused")
	equal(store.updates, writes, "no stale Save attempt")
	equal(session:GetPendingWorkerCuan(), 75, "both historical rates retained")
	local oldSeconds = 0
	for _, entry in ipairs(session._pendingAccrual) do
		if entry.rate == 1.5 then oldSeconds += entry.seconds end
	end
	equal(oldSeconds, 30, "old-rate interval not consumed by stale proposal")
end)

test("Stopping during a held write freezes admission but permits admitted completion", function()
	local session, store, clock = loaded(worker(), true)
	clock.connected = 10
	session:CaptureConnectedTime()
	store.beforeUpdate = function() coroutine.yield("held") end
	local result: any = nil
	local thread = coroutine.create(function() result = publish(session) end)
	resume(thread)
	equal(session:Stop().code, "BUSY", "held write cannot be released")
	equal(session:IsWritable(), false, "leave stops new admission")
	clock.connected = 100
	resume(thread)
	check(result.ok, "admitted write still completes")
	equal(session:GetPendingWorkerCuan(), 0, "disconnected latency does not accrue")
	check(session:Stop().ok, "retry finishes leave")
	equal(store.data.Player_1234.lease.token, "", "released only after completion")
end)

test("Fractional worker banks retain the exact proposal across failed renewal", function()
	local session, store = loaded(worker())
	session:Advance(0.25)
	store.failWrites = true
	equal(session:RenewLease().ok, false, "renewal failed")
	local proposal = session._pendingWrite
	equal(proposal.profile.fractionalIncome, 0.375, "fraction retained in proposal")
	store.failWrites = false
	check(session:RenewLease().ok, "same renewal reconciles")
	equal(store.data.Player_1234.lastSaveOpId, proposal.opId, "stable operation")
	equal(session:GetConfirmedProfile().fractionalIncome, 0.375, "fraction confirmed once")
	equal(session:GetPendingWorkerCuan(), 0, "no restored duplicate")
end)

test("A released lease is cleared for the next generation without a prior save", function()
	local first, store = loaded(worker())
	check(first:Stop().ok, "first generation leaves cleanly")
	equal(store.data.Player_1234.lease.token, "", "first release cleared the backend lease")
	local second = SessionService.new({
		userId = 1234, store = store, httpService = http, jobId = "integration",
		now = function() return 1000 end,
		noCacheOptions = function() return { UseCache = false } end,
		wait = function() end,
	})
	check(second:Start().ok, "second generation acquires the released key")
	check(second:Stop().ok, "second generation leaves with no economic save")
	equal(store.data.Player_1234.lease.token, "", "reused final ID cannot fake the second release")
	local third = SessionService.new({
		userId = 1234, store = store, httpService = http, jobId = "integration",
		now = function() return 1000 end,
		noCacheOptions = function() return { UseCache = false } end,
		wait = function() end,
	})
	check(third:Start().ok, "third generation joins immediately instead of LOCKED")
	check(third:Stop().ok, "third generation leaves cleanly")
end)

test("Server transaction fingerprints remain bounded while recent payload conflicts are rejected", function()
	local session, store = loaded()
	local persistence = session._store
	local profile = session:GetConfirmedProfile()
	for index = 1, 100 do
		check(persistence:Save(profile, `bounded-server-{index}`).ok, "server-owned save confirmed")
	end
	local count = 0
	for _ in pairs(persistence._opPayloads) do count += 1 end
	check(count <= 64, "transaction fingerprint memory is bounded")
	local writes = store.updates
	local conflicting = copy(profile)
	conflicting.balance += 1
	conflicting.lifetimeEarned += 1
	equal(persistence:Save(conflicting, "bounded-server-100").ok, false, "recent identity cannot change payload")
	equal(store.updates, writes, "conflicting payload never reaches transport")
end)

local passed, failed = 0, 0
for _, item in ipairs(tests) do
	local ok, err = pcall(item.fn)
	if ok then
		passed += 1
		print(`[PASS] {item.name}`)
	else
		failed += 1
		print(`[FAIL] {item.name}: {tostring(err)}`)
	end
end
print(`SessionIntegration spec: {passed}/{passed + failed} passed, {failed} failed`)
if failed > 0 then error("SessionIntegration spec failed", 0) end
return `SessionIntegration: {passed}/{passed + failed} passed`
