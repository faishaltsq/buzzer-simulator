--!strict
-- Buzzer Simulator — ProfileStore (BS-02).
-- Load/save/release for the v1 profile envelope with a time-limited lease.
-- Contract source: docs/03 "Profile and persistence contract", BS-02 in docs/08.
--
-- Design rules honored here:
--   * No SetAsync anywhere. Load uses GetAsync; every write is conditional
--     UpdateAsync whose callback compares lease token + expected revision.
--   * Failed load yields NO starter profile (never seed a blank save).
--   * Lease: atomically acquired on load if absent/expired/same token, else
--     LOCKED. A competing token can never overwrite the live token.
--   * Ambiguous write result is retried with the SAME operation ID and the
--     same validated snapshot; the callback short-circuits when the stored
--     lastSaveOpId already equals that ID (idempotent, no revision bump).
--   * Unsupported/corrupt data is preserved, never erased or migrated.
--   * Writes are serialized per player by the caller's single lane; this
--     module itself never yields inside a transform callback.
--
-- The DataStore is injected (defaults to a real GlobalDataStore), so specs
-- drive the same code path through a fake adapter with latency, throttle and
-- ambiguous-success injection.
local ProfileStore = {}
ProfileStore.__index = ProfileStore

-- Public catalog only (device IDs for the ownership invariant). Private
-- affinity tags stay in ScoringCatalog (BS-03) and are never touched here.
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))

local STORE_NAME = "PlayerData"
local SCHEMA_VERSION = 1
local LEASE_DURATION = 240 -- seconds
local LEASE_RENEW = 90 -- seconds
local MAX_SAVE_ATTEMPTS = 3 -- bounded retry on ambiguous/failed writes

export type LoadResult = {
	ok: boolean,
	code: "OK" | "LOCKED" | "SAVE_UNAVAILABLE" | "CORRUPT" | "UNSUPPORTED_SCHEMA" | "BUSY",
	envelope: any?, -- validated v1 envelope when ok
	detail: string?,
}
export type SaveResult = {
	ok: boolean,
	code: "OK" | "LOCKED" | "BUSY" | "SAVE_UNAVAILABLE" | "CORRUPT" | "INVALID_PROFILE",
	revision: number?, -- new confirmed revision when ok
	detail: string?,
}
export type ReleaseResult = {
	ok: boolean,
	code: "OK" | "LOCKED" | "SAVE_UNAVAILABLE" | "BUSY",
	detail: string?,
}

export type StoreAdapter = {
	-- options is a DataStoreGetOptions; pass UseCache=false for
	-- backend-fresh reconciliation reads (see readBackendFresh).
	GetAsync: (self: any, key: string, options: any?) -> any,
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
	RemoveAsync: (self: any, key: string) -> any,
}

-- Resolved lazily (not at require time) so specs can inject a fake adapter
-- and the module stays requireable outside Roblox.
local function defaultStore(): StoreAdapter
	local dataStoreService = game:GetService("DataStoreService")
	return dataStoreService:GetDataStore(STORE_NAME) :: any
end
local function defaultHttpService(): any
	return game:GetService("HttpService")
end
-- Backend-fresh read options. Official guidance: "For immediate verification
-- reads after a write, use GetAsync() with DataStoreGetOptions.UseCache =
-- false. By default, GetAsync() uses a local four-second cache, so a normal
-- verification read can return stale data."
-- https://create.roblox.com/docs/cloud-services/data-stores/versioning-listing-and-caching
local function noCacheOptions(): any
	local options = Instance.new("DataStoreGetOptions")
	options.UseCache = false
	return options
end
-- Read the authoritative backend value, bypassing the engine's local cache.
-- Used ONLY for ambiguous-write reconciliation: deciding whether a write whose
-- response was lost actually landed must never trust a 4-second-old cached
-- copy. Ordinary reads (Load) stay cached to protect the request budget.
-- `noCacheOptions` is injectable so specs can run outside Studio.
local function readBackendFresh(store: StoreAdapter, key: string, noCacheOptions: () -> any): (boolean, any)
	local ok, result = pcall(function()
		return store:GetAsync(key, noCacheOptions())
	end)
	return ok, result
end

-- Catalog lookup for the device-ownership invariant. The public catalog is
-- shared data, so validation can consult it without touching private affinities.
local function isKnownDevice(deviceId: any): boolean
	if typeof(deviceId) ~= "string" then
		return false
	end
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).id == deviceId then
			return true
		end
	end
	return false
end

-- ===== v1 validation (docs/03 profile contract) =====
-- Returns (ok, problems). Rejects anything that is not an exact-shape v1
-- envelope: missing fields, wrong types, out-of-range values, broken
-- cross-field invariants. Never coerces or repairs.
local function isFiniteNumber(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
local function isNonNegativeInteger(v: any): boolean
	return isFiniteNumber(v) and (v :: number) % 1 == 0 and (v :: number) >= 0
end
local function isNonEmptyString(v: any): boolean
	return typeof(v) == "string" and #(v :: string) > 0 and #(v :: string) <= 128
end
-- Narrowing helpers for the validation passes: after a typeof guard, Luau's
-- `unknown` still needs an explicit cast before numeric comparison.
local function asNumber(v: any): number
	return v :: number
end

local function validateWorkerEntry(w: any, problems: { string }, where: string)
	if typeof(w) ~= "table" then
		table.insert(problems, `{where}: worker entry must be a table`)
		return
	end
	if not isNonEmptyString(w.hireId) then
		table.insert(problems, `{where}: worker hireId must be a nonempty string`)
	end
	if w.roleId ~= "trainee" then
		table.insert(problems, `{where}: worker roleId must be "trainee"`)
	end
	if not isNonNegativeInteger(w.slotIndex) or w.slotIndex < 1 or w.slotIndex > 2 then
		table.insert(problems, `{where}: worker slotIndex must be 1 or 2`)
	end
end

local function validateActiveMission(m: any, problems: { string })
	if m == nil then
		return
	end
	if typeof(m) ~= "table" then
		table.insert(problems, "activeMission must be a table or nil")
		return
	end
	if not isNonEmptyString(m.missionId) then
		table.insert(problems, "activeMission.missionId must be a nonempty string")
	end
	if not isNonEmptyString(m.runId) then
		table.insert(problems, "activeMission.runId must be a nonempty string")
	end
	if not isNonEmptyString(m.contextId) then
		table.insert(problems, "activeMission.contextId must be a nonempty string")
	end
	local statusOk = m.status == "accepted"
		or m.status == "resolvingPost"
		or m.status == "readyToClaim"
		or m.status == "claimed"
	if not statusOk then
		table.insert(problems, `activeMission.status invalid: {tostring(m.status)}`)
	end
	if not isNonNegativeInteger(m.accumulatedImpact) then
		table.insert(problems, "activeMission.accumulatedImpact must be a nonnegative integer")
	end
	if not isNonNegativeInteger(m.postCount) or m.postCount > 2 then
		table.insert(problems, "activeMission.postCount must be 0..2")
	end
end

local function validatePendingPost(p: any, problems: { string })
	if p == nil then
		return
	end
	if typeof(p) ~= "table" then
		table.insert(problems, "pendingPost must be a table or nil")
		return
	end
	if not isNonEmptyString(p.postId) then
		table.insert(problems, "pendingPost.postId must be a nonempty string")
	end
	if p.mode ~= "organic" and p.mode ~= "mission" then
		table.insert(problems, `pendingPost.mode invalid: {tostring(p.mode)}`)
	end
	if p.mode == "mission" and not isNonEmptyString(p.missionRunId) then
		table.insert(problems, "pendingPost.missionRunId required when mode == mission")
	end
	if not isNonEmptyString(p.contextId) then
		table.insert(problems, "pendingPost.contextId must be a nonempty string")
	end
	if not isNonEmptyString(p.templateId) then
		table.insert(problems, "pendingPost.templateId must be a nonempty string")
	end
	if not isFiniteNumber(p.publishedAt) or p.publishedAt < 0 then
		table.insert(problems, "pendingPost.publishedAt must be a finite nonnegative number")
	end
	if not isFiniteNumber(p.settleAt) or p.settleAt < 0 then
		table.insert(problems, "pendingPost.settleAt must be a finite nonnegative number")
	end
	if not isNonNegativeInteger(p.finalImpact) then
		table.insert(problems, "pendingPost.finalImpact must be a nonnegative integer")
	end
	if not isNonNegativeInteger(p.organicCuan) then
		table.insert(problems, "pendingPost.organicCuan must be a nonnegative integer")
	end
end

local function validateOwnPost(o: any, problems: { string })
	if typeof(o) ~= "table" then
		table.insert(problems, "ownPosts entry must be a table")
		return
	end
	if not isNonEmptyString(o.postId) then
		table.insert(problems, "ownPosts.postId must be a nonempty string")
	end
	if o.mode ~= "organic" and o.mode ~= "mission" then
		table.insert(problems, `ownPosts.mode invalid: {tostring(o.mode)}`)
	end
	if not isNonEmptyString(o.contextId) then
		table.insert(problems, "ownPosts.contextId must be a nonempty string")
	end
	if not isNonEmptyString(o.templateId) then
		table.insert(problems, "ownPosts.templateId must be a nonempty string")
	end
	if not isNonNegativeInteger(o.finalImpact) then
		table.insert(problems, "ownPosts.finalImpact must be a nonnegative integer")
	end
	if not isNonNegativeInteger(o.organicCuan) then
		table.insert(problems, "ownPosts.organicCuan must be a nonnegative integer")
	end
	if not isFiniteNumber(o.publishedAt) or o.publishedAt < 0 then
		table.insert(problems, "ownPosts.publishedAt must be a finite nonnegative number")
	end
end

local function validateMutationOutcome(o: any, problems: { string})
	if typeof(o) ~= "table" then
		table.insert(problems, "recentMutationOutcomes entry must be a table")
		return
	end
	if not isNonEmptyString(o.requestId) then
		table.insert(problems, "outcome.requestId must be a nonempty string")
	end
	if not isNonEmptyString(o.action) then
		table.insert(problems, "outcome.action must be a nonempty string")
	end
	if not isNonEmptyString(o.intent) then
		table.insert(problems, "outcome.intent must be a nonempty string")
	end
	if o.ok ~= true then
		table.insert(problems, "outcome.ok must be true (ring stores successes only)")
	end
	if o.code ~= "OK" then
		table.insert(problems, `outcome.code must be "OK"`)
	end
	if not isNonNegativeInteger(o.revision) then
		table.insert(problems, "outcome.revision must be a nonnegative integer")
	end
	if o.resultIds ~= nil then
		if typeof(o.resultIds) ~= "table" then
			table.insert(problems, "outcome.resultIds must be a table or nil")
		else
			for _, id in ipairs(o.resultIds) do
				if not isNonEmptyString(id) then
					table.insert(problems, "outcome.resultIds entries must be nonempty strings")
				end
			end
		end
	end
end

local function validateProfile(profile: any, problems: { string})
	if typeof(profile) ~= "table" then
		table.insert(problems, "profile must be a table")
		return
	end
	if not isNonNegativeInteger(profile.balance) then
		table.insert(problems, "profile.balance must be a nonnegative integer")
	end
	if not isNonNegativeInteger(profile.lifetimeEarned) then
		table.insert(problems, "profile.lifetimeEarned must be a nonnegative integer")
	end
	if not isNonNegativeInteger(profile.completedMissions) then
		table.insert(problems, "profile.completedMissions must be a nonnegative integer")
	end
	if not isNonEmptyString(profile.deviceId) then
		table.insert(problems, "profile.deviceId must be a nonempty string")
	elseif not isKnownDevice(profile.deviceId) then
		-- Ownership invariant: the equipped device must exist in the catalog.
		-- A saved ID that no longer resolves is corrupt, not a free upgrade.
		table.insert(problems, `profile.deviceId {profile.deviceId} is not a catalog device`)
	end
	if profile.propertyId ~= "bedroom" then
		table.insert(problems, `profile.propertyId must be "bedroom"`)
	end
	if typeof(profile.ownedDesks) ~= "table" then
		table.insert(problems, "profile.ownedDesks must be an array")
	else
		if #profile.ownedDesks > 2 then
			table.insert(problems, "profile.ownedDesks exceeds 2 slots")
		end
		local seen: { [number]: boolean } = {}
		local last = 0
		for _, slot in ipairs(profile.ownedDesks) do
			if not isNonNegativeInteger(slot) or asNumber(slot) < 1 or asNumber(slot) > 2 then
				table.insert(problems, "profile.ownedDesks entries must be 1 or 2")
			elseif seen[asNumber(slot)] then
				table.insert(problems, `profile.ownedDesks duplicate slot {slot}`)
			elseif asNumber(slot) <= last then
				table.insert(problems, "profile.ownedDesks must be ascending")
			end
			seen[asNumber(slot)] = true
			last = asNumber(slot)
		end
	end
	if typeof(profile.workers) ~= "table" then
		table.insert(problems, "profile.workers must be an array")
	else
		if #profile.workers > 2 then
			table.insert(problems, "profile.workers exceeds 2 slots")
		end
		local seenSlots: { [number]: boolean } = {}
		for _, w in ipairs(profile.workers) do
			validateWorkerEntry(w, problems, "profile.workers")
			if typeof(w) == "table" and isNonNegativeInteger((w :: any).slotIndex) then
				if seenSlots[asNumber((w :: any).slotIndex)] then
					table.insert(problems, `profile.workers duplicate slot {(w :: any).slotIndex}`)
				end
				seenSlots[asNumber((w :: any).slotIndex)] = true
			end
		end
	end
	if not isFiniteNumber(profile.fractionalIncome) or asNumber(profile.fractionalIncome) < 0 or asNumber(profile.fractionalIncome) >= 1 then
		table.insert(problems, "profile.fractionalIncome must be in [0,1)")
	end
	if typeof(profile.claimedRunIdsWindow) ~= "table" then
		table.insert(problems, "profile.claimedRunIdsWindow must be an array")
	elseif #profile.claimedRunIdsWindow > 32 then
		table.insert(problems, "profile.claimedRunIdsWindow exceeds 32 entries")
	else
		for _, id in ipairs(profile.claimedRunIdsWindow) do
			if not isNonEmptyString(id) then
				table.insert(problems, "profile.claimedRunIdsWindow entries must be nonempty strings")
			end
		end
	end
	if typeof(profile.recentMutationOutcomes) ~= "table" then
		table.insert(problems, "profile.recentMutationOutcomes must be an array")
	elseif #profile.recentMutationOutcomes > 32 then
		table.insert(problems, "profile.recentMutationOutcomes exceeds 32 entries")
	else
		for _, o in ipairs(profile.recentMutationOutcomes) do
			validateMutationOutcome(o, problems)
		end
	end
	if typeof(profile.missionVariantCounters) ~= "table" then
		table.insert(problems, "profile.missionVariantCounters must be a map")
	else
		for missionId, count in pairs(profile.missionVariantCounters) do
			if not isNonEmptyString(missionId) then
				table.insert(problems, "profile.missionVariantCounters keys must be nonempty strings")
			end
			if not isNonNegativeInteger(count) then
				table.insert(problems, `missionVariantCounters[{missionId}] must be a nonnegative integer`)
			end
		end
	end
	if not isNonNegativeInteger(profile.nextOrganicSequence) then
		table.insert(problems, "profile.nextOrganicSequence must be a nonnegative integer")
	end
	validateActiveMission(profile.activeMission, problems)
	validatePendingPost(profile.pendingPost, problems)
	if typeof(profile.ownPosts) ~= "table" then
		table.insert(problems, "profile.ownPosts must be an array")
	elseif #profile.ownPosts > 10 then
		table.insert(problems, "profile.ownPosts exceeds 10 entries")
	else
		for _, o in ipairs(profile.ownPosts) do
			validateOwnPost(o, problems)
		end
	end
	if not isNonNegativeInteger(profile.nextPostSequence) then
		table.insert(problems, "profile.nextPostSequence must be a nonnegative integer")
	end

	-- ===== cross-field invariants (docs/03) =====
	-- These relate separate fields. They are checked only when both sides are
	-- individually well-formed, so a single malformed field reports one clear
	-- problem instead of a cascade of derived ones.

	-- Worker desk prerequisite: every hired worker must occupy an owned desk.
	-- Ownership is what makes the worker payable; a worker in an unowned slot
	-- is corrupt state, not a legitimate "bought the worker first" ordering
	-- (the server enforces desk-then-hire).
	if typeof(profile.ownedDesks) == "table" and typeof(profile.workers) == "table" then
		local owned: { [number]: boolean } = {}
		for _, slot in ipairs(profile.ownedDesks) do
			if isNonNegativeInteger(slot) then
				owned[asNumber(slot)] = true
			end
		end
		for _, w in ipairs(profile.workers) do
			if typeof(w) == "table" and isNonNegativeInteger((w :: any).slotIndex) then
				local slot = asNumber((w :: any).slotIndex)
				if not owned[slot] then
					table.insert(problems, `worker in slot {slot} requires an owned desk`)
				end
			end
		end
	end

	-- Pending-post / active-mission consistency. docs/02 lifecycle:
	--   available -> accepted -> resolvingPost -> accepted (impact short)
	--                                        -> readyToClaim -> claimed
	-- A mission-tagged pending post must belong to the active run, a
	-- resolvingPost status must have that post in flight, and a mission post
	-- may not exceed the two-post cap. Organic posts are independent and may
	-- coexist with any mission state.
	local activeMission = profile.activeMission
	local pendingPost = profile.pendingPost
	local hasMission = activeMission ~= nil and typeof(activeMission) == "table"
	local hasPost = pendingPost ~= nil and typeof(pendingPost) == "table"
	if hasMission and hasPost then
		if pendingPost.mode == "mission" then
			if not isNonEmptyString(pendingPost.missionRunId) then
				table.insert(problems, "mission pending post requires missionRunId")
			elseif (activeMission :: any).runId ~= pendingPost.missionRunId then
				table.insert(problems, "mission pending post runId must match the active mission")
			elseif asNumber((activeMission :: any).postCount) >= 2 then
				table.insert(problems, "mission pending post exceeds the two-post cap")
			end
		end
	end
	-- resolvingPost means this mission's post is in flight and not yet settled.
	-- docs/02 lifecycle: the status is only entered while a post is pending, so
	-- a resolvingPost mission with no matching pending post is corrupt state
	-- (a crash mid-settlement must not leave the mission claimable-looking).
	if hasMission and (activeMission :: any).status == "resolvingPost" then
		if not hasPost or pendingPost.mode ~= "mission" or (activeMission :: any).runId ~= pendingPost.missionRunId then
			table.insert(problems, "resolvingPost status requires a matching mission pending post")
		end
	end
	-- A mission pending post with no active mission is orphaned state.
	if (activeMission == nil) and pendingPost ~= nil and typeof(pendingPost) == "table" and pendingPost.mode == "mission" then
		table.insert(problems, "mission pending post requires an active mission")
	end
	-- A post cannot settle before it was published.
	if pendingPost ~= nil and typeof(pendingPost) == "table" then
		if isFiniteNumber(pendingPost.publishedAt) and isFiniteNumber(pendingPost.settleAt) then
			if asNumber(pendingPost.settleAt) < asNumber(pendingPost.publishedAt) then
				table.insert(problems, "pending post settleAt must not precede publishedAt")
			end
		end
	end
	-- readyToClaim means the requirement is met: accumulated impact must have
	-- reached the mission's requirement. Checking against the catalog keeps the
	-- claim gate server-authoritative after a rejoin.
	if activeMission ~= nil and typeof(activeMission) == "table" and activeMission.status == "readyToClaim" then
		if isNonEmptyString((activeMission :: any).missionId) and isNonNegativeInteger((activeMission :: any).accumulatedImpact) then
			local missionId = (activeMission :: any).missionId
			local accumulated = asNumber((activeMission :: any).accumulatedImpact)
			for _, mission in ipairs(Catalog.Missions) do
				if (mission :: any).missionId == missionId then
					if accumulated < asNumber((mission :: any).requiredImpact) then
						table.insert(problems, `readyToClaim requires accumulatedImpact >= {(mission :: any).requiredImpact}`)
					end
					break
				end
			end
		end
	end
end

-- Full envelope validation. Returns (ok, problems). Rejects wrong schema
-- versions explicitly (caller preserves the raw value, never migrates).
local function validateEnvelope(envelope: any): (boolean, { string })
	local problems: { string } = {}
	if typeof(envelope) ~= "table" then
		return false, { "envelope must be a table" }
	end
	if envelope.schemaVersion ~= SCHEMA_VERSION then
		return false, { `unsupported schemaVersion {tostring(envelope.schemaVersion)} (expected {SCHEMA_VERSION})` }
	end
	if not isNonNegativeInteger(envelope.revision) or envelope.revision < 1 then
		table.insert(problems, "envelope.revision must be an integer >= 1")
	end
	if not isNonEmptyString(envelope.lastSaveOpId) then
		table.insert(problems, "envelope.lastSaveOpId must be a nonempty string")
	end
	if not isFiniteNumber(envelope.updatedAt) or envelope.updatedAt < 0 then
		table.insert(problems, "envelope.updatedAt must be a finite nonnegative number")
	end
	if envelope.profile == nil then
		-- Transitional envelope with no profile yet: valid only in the two
		-- states that legitimately have none -- (a) a freshly leased key
		-- before SessionService writes the starter profile, and (b) a released
		-- key whose profile was never written. Anything else is corrupt.
		local isFreshInit = envelope.lastSaveOpId == "init" and envelope.revision == 1
		local isReleasedEmpty = typeof(envelope.lease) == "table"
			and envelope.lease.token == ""
			and envelope.lease.expiresAt == 0
		if not isFreshInit and not isReleasedEmpty then
			table.insert(problems, "envelope without profile must be a fresh-init or released-empty envelope")
		end
	else
		validateProfile(envelope.profile, problems)
	end
	if typeof(envelope.lease) ~= "table" then
		table.insert(problems, "envelope.lease must be a table")
	else
		local lease = (envelope :: any).lease
		-- A released envelope carries an empty token with expiresAt 0: that is
		-- the transitional hand-over state written by Release, and it must stay
		-- loadable. Any other empty token is corrupt.
		local released = lease.token == "" and lease.expiresAt == 0
		if not isNonEmptyString(lease.token) and not released then
			table.insert(problems, "envelope.lease.token must be a nonempty string (or empty only when released)")
		end
		if not isNonEmptyString(lease.jobId) then
			table.insert(problems, "envelope.lease.jobId must be a nonempty string")
		end
		if not isFiniteNumber(lease.expiresAt) or asNumber(lease.expiresAt) < 0 then
			table.insert(problems, "envelope.lease.expiresAt must be a finite nonnegative number")
		end
	end
	return #problems == 0, problems
end
ProfileStore._validateEnvelope = validateEnvelope

-- ===== deep copy (immutable snapshots in/out) =====
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
ProfileStore._deepCopy = deepCopy

-- ===== construction =====
-- opts.store: injected adapter (specs). opts.jobId: server identity for lease.
-- opts.now: () -> number epoch seconds (specs inject a fake clock).
function ProfileStore.new(userId: number, opts: ProfileStoreOptions?): ProfileStoreInstance
	local self = setmetatable({}, ProfileStore)
	self._userId = userId
	self._key = `Player_{userId}`
	self._store = (opts and opts.store) or defaultStore()
	self._httpService = (opts and opts.httpService) or defaultHttpService()
	self._noCacheOptions = (opts and opts.noCacheOptions) or noCacheOptions
	self._jobId = (opts and opts.jobId) or "server-unknown"
	self._now = (opts and opts.now) or function()
		return workspace:GetServerTimeNow()
	end
	self._leaseToken = nil :: string?
	self._envelope = nil :: any? -- last confirmed in-memory envelope
	self._lastConfirmedRevision = 0
	return self
end

export type ProfileStoreInstance = {
	_userId: number,
	_key: string,
	_store: StoreAdapter,
	_httpService: any,
	_noCacheOptions: () -> any,
	_jobId: string,
	_now: () -> number,
	_leaseToken: string?,
	_envelope: any?,
	_lastConfirmedRevision: number,
}
export type ProfileStoreOptions = {
	store: StoreAdapter?, -- injected DataStore adapter (specs)
	httpService: any?, -- injected HttpService for lease tokens (specs)
	noCacheOptions: (() -> any)?, -- injected DataStoreGetOptions factory (specs)
	jobId: string?, -- server identity recorded in the lease
	now: (() -> number)?, -- epoch-second clock (specs inject a fake)
}

local function generateToken(httpService: any): string
	return httpService:GenerateGUID(false)
end

-- ===== Load =====
-- GetAsync, validate, then acquire the lease atomically inside UpdateAsync:
-- absent/expired/same-token lease is taken over; a live foreign token is
-- LOCKED. A failed or throttled read returns SAVE_UNAVAILABLE with no
-- starter profile seeded. Corrupt/unsupported data is preserved untouched.
function ProfileStore:Load(): LoadResult
	local ok, raw = pcall(function()
		return self._store:GetAsync(self._key)
	end)
	if not ok then
		return { ok = false, code = "SAVE_UNAVAILABLE", detail = tostring(raw) }
	end
	if raw == nil then
		-- No data yet: acquire a fresh lease on an empty key. The caller
		-- (SessionService) owns starter-profile creation; the store only
		-- guarantees the lease and the revision counter start.
		return self:_acquireFreshLease()
	end
	if typeof(raw) ~= "table" then
		return { ok = false, code = "CORRUPT", detail = "stored value is not a table" }
	end
	local valid, problems = validateEnvelope(raw)
	if not valid then
		if typeof(raw) == "table" and raw.schemaVersion ~= nil and raw.schemaVersion ~= SCHEMA_VERSION then
			-- Preserve unknown schema data untouched; never migrate here.
			return { ok = false, code = "UNSUPPORTED_SCHEMA", detail = table.concat(problems, "; ") }
		end
		return { ok = false, code = "CORRUPT", detail = table.concat(problems, "; ") }
	end
	-- Atomic lease acquisition: compare-and-set on token+expiry.
	local now = self._now()
	local token = generateToken(self._httpService)
	local acquireOk, result: any = pcall(function()
		return self._store:UpdateAsync(self._key, function(old: any)
			if old == nil then
				-- vanished between read and write: treat as fresh
				return nil
			end
			if typeof(old) ~= "table" or old.schemaVersion ~= SCHEMA_VERSION then
				return nil -- abort write; preserve foreign/corrupt data
			end
			local lease = (old :: any).lease
			if typeof(lease) == "table" and typeof(lease.token) == "string" then
				if lease.token ~= token and isFiniteNumber(lease.expiresAt) and asNumber(lease.expiresAt) > now then
					return nil -- live foreign lease: abort, caller sees LOCKED
				end
			end
			local next: any = deepCopy(old)
			next.lease = {
				token = token,
				jobId = self._jobId,
				expiresAt = now + LEASE_DURATION,
			}
			next.updatedAt = now
			return next
		end)
	end)
	if not acquireOk then
		return { ok = false, code = "SAVE_UNAVAILABLE", detail = tostring(result) }
	end
	if result == nil then
		-- Either the key vanished or a live foreign lease blocked us.
		if raw ~= nil and typeof(raw) == "table" and typeof((raw :: any).lease) == "table" then
			local lease = (raw :: any).lease
			if typeof(lease.token) == "string" and lease.token ~= token and isFiniteNumber(lease.expiresAt) and asNumber(lease.expiresAt) > now then
				return { ok = false, code = "LOCKED", detail = "lease held by another server" }
			end
		end
		return { ok = false, code = "SAVE_UNAVAILABLE", detail = "lease acquisition aborted (key changed)" }
	end
	self._leaseToken = token
	self._envelope = deepCopy(result)
	self._lastConfirmedRevision = result.revision
	return { ok = true, code = "OK", envelope = deepCopy(result) }
end

function ProfileStore:_acquireFreshLease(): LoadResult
	local now = self._now()
	local token = generateToken(self._httpService)
	local acquireOk, result: any = pcall(function()
		return self._store:UpdateAsync(self._key, function(old: any)
			if old ~= nil then
				return nil -- someone else created data; abort, re-Load
			end
			local fresh: any = {
				schemaVersion = SCHEMA_VERSION,
				revision = 1,
				lastSaveOpId = "init",
				updatedAt = now,
				profile = nil, -- SessionService writes the starter profile first
				lease = {
					token = token,
					jobId = self._jobId,
					expiresAt = now + LEASE_DURATION,
				},
			}
			return fresh
		end)
	end)
	if not acquireOk then
		return { ok = false, code = "SAVE_UNAVAILABLE", detail = tostring(result) }
	end
	if result == nil then
		return { ok = false, code = "BUSY", detail = "key created concurrently; retry Load" }
	end
	self._leaseToken = token
	self._envelope = deepCopy(result)
	self._lastConfirmedRevision = result.revision
	return { ok = true, code = "OK", envelope = deepCopy(result) }
end

-- ===== Save =====
-- Conditional UpdateAsync: the callback verifies our lease token and the
-- expected revision, bumps the revision once, writes the operation ID and
-- renews the lease. If the stored lastSaveOpId already equals operationId
-- the write short-circuits unchanged (idempotent ambiguous-retry path).
-- profile: the full validated v1 profile to persist.
-- operationId: stable ID for this logical save (retries reuse it).
function ProfileStore:Save(profile: any, operationId: string): SaveResult
	if self._leaseToken == nil then
		return { ok = false, code = "LOCKED", detail = "no lease held; Load first" }
	end
	if not isNonEmptyString(operationId) then
		return { ok = false, code = "INVALID_PROFILE", detail = "operationId must be a nonempty string" }
	end
	local profileProblems: { string } = {}
	validateProfile(profile, profileProblems)
	if #profileProblems > 0 then
		return { ok = false, code = "INVALID_PROFILE", detail = table.concat(profileProblems, "; ") }
	end
	local token = self._leaseToken
	local expectedRevision = self._lastConfirmedRevision
	local now = self._now()
	local attempt = 0
	local lastDetail: string? = nil
	while attempt < MAX_SAVE_ATTEMPTS do
		attempt += 1
		local writeOk, result: any = pcall(function()
			return self._store:UpdateAsync(self._key, function(old: any)
				if old == nil or typeof(old) ~= "table" or old.schemaVersion ~= SCHEMA_VERSION then
					return nil -- never overwrite foreign/missing data
				end
				if typeof(old.lease) ~= "table" or old.lease.token ~= token then
					return nil -- lease lost: abort, never overwrite
				end
				if old.lastSaveOpId == operationId then
					return nil -- already applied: idempotent no-op
				end
				if old.revision ~= expectedRevision then
					return nil -- stale snapshot: abort, caller re-syncs
				end
				local next = deepCopy(old)
				next.profile = deepCopy(profile)
				next.revision = old.revision + 1
				next.lastSaveOpId = operationId
				next.updatedAt = now
				next.lease = {
					token = token,
					jobId = self._jobId,
					expiresAt = now + LEASE_DURATION,
				}
				return next
			end)
		end)
		if not writeOk then
			lastDetail = tostring(result)
			-- Ambiguous failure (throttle/timeout): retry same operationId.
			continue
		end
		if result == nil then
			-- Aborted. Distinguish lease loss from idempotent already-applied
			-- by reading the authoritative backend value with the engine's
			-- local cache bypassed (docs: UseCache=false for verification
			-- reads after a write).
			local readOk, current: any = readBackendFresh(self._store, self._key, self._noCacheOptions)
			if not readOk then
				lastDetail = tostring(current)
				continue
			end
			if typeof(current) == "table" and current.lastSaveOpId == operationId then
				-- Already durably applied by an earlier ambiguous attempt.
				self._envelope = deepCopy(current)
				self._lastConfirmedRevision = current.revision
				self._leaseToken = current.lease and current.lease.token or self._leaseToken
				return { ok = true, code = "OK", revision = current.revision }
			end
			if typeof(current) == "table" and typeof(current.lease) == "table" and current.lease.token ~= token then
				self._leaseToken = nil
				return { ok = false, code = "LOCKED", detail = "lease taken by another server" }
			end
			lastDetail = "conditional write aborted (stale revision or key changed)"
			continue
		end
		self._envelope = deepCopy(result)
		self._lastConfirmedRevision = result.revision
		return { ok = true, code = "OK", revision = result.revision }
	end
	return { ok = false, code = "SAVE_UNAVAILABLE", detail = lastDetail or "save attempts exhausted" }
end

-- ===== Release =====
-- Clean leave: conditional final write that clears our lease token so a
-- rejoin on another server can acquire immediately. Uses the same
-- idempotent operation-ID discipline as Save.
function ProfileStore:Release(operationId: string): ReleaseResult
	if self._leaseToken == nil then
		return { ok = false, code = "LOCKED", detail = "no lease held" }
	end
	if not isNonEmptyString(operationId) then
		return { ok = false, code = "BUSY", detail = "operationId must be a nonempty string" }
	end
	local token = self._leaseToken
	local expectedRevision = self._lastConfirmedRevision
	local now = self._now()
	local attempt = 0
	local lastDetail: string? = nil
	while attempt < MAX_SAVE_ATTEMPTS do
		attempt += 1
		local writeOk, result: any = pcall(function()
			return self._store:UpdateAsync(self._key, function(old: any)
				if old == nil or typeof(old) ~= "table" or old.schemaVersion ~= SCHEMA_VERSION then
					return nil
				end
				if typeof(old.lease) ~= "table" or old.lease.token ~= token then
					return nil
				end
				if old.lastSaveOpId == operationId then
					return nil
				end
				if old.revision ~= expectedRevision then
					return nil
				end
				local next = deepCopy(old)
				next.lease = {
					token = "",
					jobId = self._jobId,
					expiresAt = 0, -- released: immediately acquirable
				}
				next.lastSaveOpId = operationId
				next.updatedAt = now
				return next
			end)
		end)
		if not writeOk then
			lastDetail = tostring(result)
			continue
		end
		if result == nil then
			-- Backend-fresh reconciliation read: the cached copy can be up to
			-- four seconds stale and would misreport an ambiguous release.
			local readOk, current: any = readBackendFresh(self._store, self._key, self._noCacheOptions)
			if not readOk then
				lastDetail = tostring(current)
				continue
			end
			if typeof(current) == "table" and current.lastSaveOpId == operationId then
				self._leaseToken = nil
				return { ok = true, code = "OK" }
			end
			if typeof(current) == "table" and typeof(current.lease) == "table" and current.lease.token ~= token and current.lease.token ~= "" then
				self._leaseToken = nil
				return { ok = false, code = "LOCKED", detail = "lease taken by another server" }
			end
			lastDetail = "release aborted (stale revision or key changed)"
			continue
		end
		self._leaseToken = nil
		return { ok = true, code = "OK" }
	end
	return { ok = false, code = "SAVE_UNAVAILABLE", detail = lastDetail or "release attempts exhausted" }
end

-- ===== introspection for specs/session =====
function ProfileStore:GetLeaseToken(): string?
	return self._leaseToken
end
function ProfileStore:GetLastConfirmedRevision(): number
	return self._lastConfirmedRevision
end
function ProfileStore:GetConfirmedEnvelope(): any?
	return if self._envelope == nil then nil else deepCopy(self._envelope)
end

ProfileStore.LEASE_DURATION = LEASE_DURATION
ProfileStore.LEASE_RENEW = LEASE_RENEW
ProfileStore.SCHEMA_VERSION = SCHEMA_VERSION

return ProfileStore
