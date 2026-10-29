--!strict
-- Buzzer Simulator — SessionService (BS-04, server-owned session lifecycle).
-- Start / Mutate / Snapshot / Stop over ProfileStore, MissionService and
-- EconomyService.
--
-- BOUNDARY (docs/03, BS-04 in docs/08): this module owns the server-side
-- session. It serializes one player's mutations through a single lane,
-- coordinates durable replay, and never exposes unconfirmed Cuan. It does NOT
-- implement remotes, UI, world assets or dashboard prompts (BS-05/06/07).
--
-- The three load-bearing rules:
--
--   1. ONE LANE. Every durable action for a player -- user command, due post
--      settlement, worker banking, lease renewal, final save -- runs through a
--      single serialized per-player lane. No per-worker coroutine, no
--      independent settlement thread, no concurrent writes.
--
--   2. CONFIRMED ONLY. MissionService and EconomyService return PROPOSED
--      profiles. A proposal becomes confirmed state only after
--      ProfileStore:Save returns ok. A failed or ambiguous save leaves the
--      last confirmed snapshot visible and blocks dependent economic actions.
--
--   3. EXACTLY ONCE. A client request is identified by requestId + canonical
--      intent. A durable write is identified by a server-owned operationId.
--      A completed request is replayed from the durable
--      recentMutationOutcomes ring instead of re-running domain logic, so a
--      late duplicate of an old mutation can never overwrite a newer one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Rules = require(Shared:WaitForChild("Rules"))
local _GameTypes = require(Shared:WaitForChild("GameTypes"))

-- Sibling server modules. Resolved through the service tree rather than
-- script.Parent so the module works under both Rojo layouts: production maps
-- them beside SessionService in ServerScriptService, while the test project
-- maps them to ServerStorage so specs can require them without auto-running.
local function sibling(name: string): any
	for _, serviceName in ipairs({ "ServerScriptService", "ServerStorage" }) do
		local service = game:GetService(serviceName)
		local found = service:FindFirstChild(name)
		if found ~= nil then
			return require(found)
		end
	end
	error(`SessionService: {name} module not found`, 0)
end

local ProfileStore = sibling("ProfileStore")
local MissionService = sibling("MissionService")
local EconomyService = sibling("EconomyService")

local SessionService = {}
SessionService.__index = SessionService

-- docs/04: bank worker income at most every 30 connected seconds while
-- healthy. docs/03: renew the lease at most every 90 seconds.
local WORKER_BANK_INTERVAL = 30
local LEASE_RENEW_INTERVAL = 90

-- docs/03: connected monotonic time is processed in bounded chunks so a long
-- save or frame hitch cannot silently discard connected time.
local MAX_TIME_CHUNK = 60

-- Bounds from the frozen v1 profile contract (docs/03).
local MAX_RECENT_OUTCOMES = 32
local MAX_QUEUED_ACTIONS = 32

-- Server-owned operation-ID namespaces. Client request IDs never enter these.
local OP_PREFIX = {
	command = "cmd",
	settlement = "settle",
	bank = "bank",
	renew = "renew",
	final = "final",
}

export type SaveStatusCode = "healthy" | "SAVE_UNAVAILABLE" | "BUSY"
export type LookupStatus = "APPLIED" | "REJECTED" | "PENDING" | "UNKNOWN"

export type MutationRequest = {
	requestId: string,
	action: string,
	payload: { [string]: any },
	intent: string?, -- canonical action+payload; computed when omitted
}

export type MutationResult = {
	ok: boolean,
	code: string,
	revision: number,
	detail: string?,
	lookup: LookupStatus?, -- set when the request was resolved from a replay
	data: { [string]: any }?,
}

export type SnapshotResult = {
	ok: boolean,
	code: string,
	snapshot: any?,
	lookup: {
		originalRequestId: string,
		status: LookupStatus,
		originalResult: { ok: boolean, code: string, revision: number, data: { [string]: any }? }?,
	}?,
}

export type SessionOptions = {
	userId: number,
	store: any, -- injected DataStore adapter (specs)
	httpService: any?, -- injected HttpService (specs)
	noCacheOptions: (() -> any)?, -- injected DataStoreGetOptions factory (specs)
	jobId: string?,
	now: (() -> number)?, -- epoch-second clock (specs inject a fake)
	wait: ((number) -> ())?, -- retry sleep (specs inject a fake)
}

-- ===== canonical intent =====
-- docs/03: "intent is the canonical bounded action+payload". It must be
-- deterministic and order-independent, so two tables that differ only in key
-- insertion order encode identically. Only the validated action and the exact
-- bounded payload are encoded: transport metadata (dashboardSessionId,
-- requestId) is deliberately excluded.
local function canonicalEncode(value: any): string
	local t = typeof(value)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return if value then "true" else "false"
	elseif t == "number" then
		if value ~= value then
			return "nan"
		elseif value == math.huge then
			return "inf"
		elseif value == -math.huge then
			return "-inf"
		end
		return string.format("%.17g", value)
	elseif t == "string" then
		return string.format("%q", value)
	elseif t == "table" then
		local keys: { string } = {}
		for k in pairs(value) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, k in ipairs(keys) do
			table.insert(parts, string.format("%q:%s", k, canonicalEncode((value :: any)[k])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("canonicalEncode: unsupported value type", 0)
end

-- The canonical intent for a mutation: action plus exact payload. Bounded by
-- ProfileStore's 128-char intent field, so an oversize payload is rejected
-- before it can reach the durable ring.
local MAX_INTENT_LENGTH = 128
local function canonicalIntent(action: string, payload: { [string]: any }): string
	local encoded = canonicalEncode({ action = action, payload = payload })
	if #encoded > MAX_INTENT_LENGTH then
		error(`canonicalIntent: encoded intent exceeds {MAX_INTENT_LENGTH} characters`, 0)
	end
	return encoded
end
SessionService._canonicalIntent = canonicalIntent

-- ===== validation =====
local function isNonEmptyString(v: any): boolean
	return typeof(v) == "string" and #v > 0 and #v <= 128
end

local function isFiniteNumber(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Exact-shape payload validation. The client supplies IDs and slot indices
-- only: never money, scores, timestamps, rates or contexts. Extra keys are
-- rejected so a forged field cannot ride along.
local function validatePayload(action: string, payload: any): (boolean, string?)
	if typeof(payload) ~= "table" then
		return false, "payload must be a table"
	end
	local function exactKeys(allowed: { string }): boolean
		local count = 0
		for k in pairs(payload) do
			count += 1
			local ok = false
			for _, a in ipairs(allowed) do
				if k == a then
					ok = true
					break
				end
			end
			if not ok then
				return false
			end
		end
		return count == #allowed
	end
	if action == "AcceptMission" then
		if not exactKeys({ "missionId" }) or not isNonEmptyString(payload.missionId) then
			return false, "AcceptMission requires exactly {missionId: string}"
		end
	elseif action == "PublishOrganic" then
		if not exactKeys({ "templateId" }) or not isNonEmptyString(payload.templateId) then
			return false, "PublishOrganic requires exactly {templateId: string}"
		end
	elseif action == "PublishPost" then
		if not exactKeys({ "runId", "templateId" })
			or not isNonEmptyString(payload.runId)
			or not isNonEmptyString(payload.templateId) then
			return false, "PublishPost requires exactly {runId: string, templateId: string}"
		end
	elseif action == "ClaimMission" then
		if not exactKeys({ "runId" }) or not isNonEmptyString(payload.runId) then
			return false, "ClaimMission requires exactly {runId: string}"
		end
	elseif action == "BuyDevice" then
		if not exactKeys({ "deviceId" }) or not isNonEmptyString(payload.deviceId) then
			return false, "BuyDevice requires exactly {deviceId: string}"
		end
	elseif action == "BuyDesk" then
		if not exactKeys({ "slotIndex" }) or typeof(payload.slotIndex) ~= "number"
			or payload.slotIndex % 1 ~= 0 then
			return false, "BuyDesk requires exactly {slotIndex: integer}"
		end
	elseif action == "HireWorker" then
		if not exactKeys({ "slotIndex", "roleId" })
			or typeof(payload.slotIndex) ~= "number"
			or payload.slotIndex % 1 ~= 0
			or payload.roleId ~= "trainee" then
			return false, "HireWorker requires exactly {slotIndex: integer, roleId: \"trainee\"}"
		end
	else
		return false, `unsupported action {action}`
	end
	return true, nil
end

-- Actions that mutate durable state. Everything else is a read.
local MUTATING_ACTIONS: { [string]: boolean } = {
	AcceptMission = true,
	PublishOrganic = true,
	PublishPost = true,
	ClaimMission = true,
	BuyDevice = true,
	BuyDesk = true,
	HireWorker = true,
}

-- ===== construction =====
function SessionService.new(opts: SessionOptions): SessionServiceInstance
	local self = setmetatable({}, SessionService)
	self._userId = opts.userId
	self._now = opts.now or function()
		return workspace:GetServerTimeNow()
	end
	self._wait = opts.wait or function(_s: number)
		task.wait(_s)
	end
	self._store = ProfileStore.new(opts.userId, {
		store = opts.store,
		httpService = opts.httpService,
		noCacheOptions = opts.noCacheOptions,
		jobId = opts.jobId,
		now = self._now,
		wait = self._wait,
	})
	-- Last confirmed state. Never nil once started successfully.
	self._profile = nil :: any?
	self._revision = 0
	self._saveStatus = "healthy" :: SaveStatusCode
	-- Monotonic connected-session elapsed time. Never derived from wall clock
	-- differences, so a rejoin cannot fabricate offline income.
	self._connectedSeconds = 0
	-- Seconds since the last durable bank, tracked so a renewal or a command
	-- can piggyback the same accrued interval exactly once.
	self._unbankedSeconds = 0
	-- Pending accrual as rate-tagged intervals, so each is credited at the
	-- worker count active while it elapsed.
	self._pendingAccrual = {} :: { { seconds: number, rate: number } }
	self._lastBankAt = 0
	-- Live reservation/replay bookkeeping. The durable ring is the authority
	-- after a reconnect; this table only answers within the live session.
	self._reserved = {} :: { [string]: boolean }
	self._liveResults = {} :: { [string]: MutationResult }
	-- In-flight proposals retained so an ambiguous retry reuses the SAME payload
	-- and the SAME operationId, resolving idempotently instead of being rejected
	-- as a different-payload protocol violation.
	self._inflight = {} :: { [string]: { profile: any, opId: string, intent: string } }
	-- One serialized lane per player. A boolean guard plus a bounded queue:
	-- no unbounded growth, no concurrent writes.
	self._laneBusy = false
	self._queue = {} :: { { requestId: string, action: string, payload: { [string]: any }, intent: string } }
	-- Shutdown bookkeeping so a second Stop cannot double-save or double-release.
	self._stopped = false
	self._stopping = false
	self._started = false
	return self
end

export type SessionServiceInstance = {
	-- Mutable session state. Written only inside the serialized lane or during
	-- construction; never mutated from outside the module.
	_userId: number,
	_now: () -> number,
	_wait: (number) -> (),
	_store: any,
	_profile: any?,
	_revision: number,
	_saveStatus: SaveStatusCode,
	_connectedSeconds: number,
	_unbankedSeconds: number,
	_pendingAccrual: { { seconds: number, rate: number } },
	_lastBankAt: number,
	_reserved: { [string]: boolean },
	_liveResults: { [string]: MutationResult },
	_inflight: { [string]: { profile: any, opId: string, intent: string } },
	_laneBusy: boolean,
	_queue: { { requestId: string, action: string, payload: { [string]: any }, intent: string } },
	_stopped: boolean,
	_stopping: boolean,
	_started: boolean,
}

-- ===== Start =====
-- Load through ProfileStore. A failed load yields NO starter profile and an
-- explicit status. The last confirmed revision and a deep-copied profile are
-- retained; outstanding pending-post state is recovered, never rerolled. No
-- offline worker income is awarded here.
function SessionService:Start(): { ok: boolean, code: string, detail: string?, snapshot: any? }
	if self._started then
		return { ok = false, code = "BUSY", detail = "session already started" }
	end
	local load = self._store:Load()
	if not load.ok then
		-- Never seed a starter profile after a failed load (docs/03).
		self._profile = nil
		self._revision = 0
		self._saveStatus = if load.code == "SAVE_UNAVAILABLE" then "SAVE_UNAVAILABLE" else "BUSY"
		return { ok = false, code = load.code, detail = load.detail }
	end
	local envelope = load.envelope
	if envelope == nil or envelope.profile == nil then
		-- A freshly leased key with no profile yet: the caller (BS-06 Bootstrap)
		-- owns starter-profile creation. BS-04 refuses to invent one.
		local freshEnvelope: any = envelope
		self._profile = nil
		self._revision = if freshEnvelope ~= nil then freshEnvelope.revision else 0
		self._saveStatus = "healthy"
		return { ok = false, code = "NOT_READY", detail = "no profile written yet; starter profile is owned by Bootstrap" }
	end
	local confirmed: any = self._store:GetConfirmedEnvelope()
	self._profile = confirmed.profile
	self._revision = self._store:GetLastConfirmedRevision()
	self._saveStatus = "healthy"
	self._started = true
	self._connectedSeconds = 0
	self._unbankedSeconds = 0
	-- Pending accrual as rate-tagged intervals, so each is credited at the
	-- worker count active while it elapsed.
	self._pendingAccrual = {} :: { { seconds: number, rate: number } }
	self._lastBankAt = 0
	return { ok = true, code = "OK", snapshot = self:_buildSnapshot() }
end

-- ===== snapshot projection =====
-- Sanitized read projection compatible with GameTypes.ProfileSnapshot. Never
-- exposes lease tokens, private affinities or another player's profile, and
-- never performs a durable write on its own.
function SessionService:_buildSnapshot(): any
	local profile = self._profile
	if profile == nil then
		return nil
	end
	local pendingWorker = self:_pendingWorkerCuan()
	return {
		revision = self._revision,
		serverTime = self._now(),
		balance = profile.balance, -- confirmed spendable only
		pendingWorkerCuan = pendingWorker, -- ephemeral, never spendable
		incomePerSecond = EconomyService.incomePerSecond(profile),
		lifetimeEarned = profile.lifetimeEarned,
		completedMissions = profile.completedMissions,
		tier = Rules.eligibleTier(
			profile.lifetimeEarned,
			profile.completedMissions,
			Catalog.V0Shipped.maxShippedTier
		),
		maxShippedTier = Catalog.V0Shipped.maxShippedTier,
		deviceId = profile.deviceId,
		ownedDesks = self._store._deepCopy(profile.ownedDesks),
		workers = self._store._deepCopy(profile.workers),
		activeMission = if profile.activeMission == nil then nil else self._store._deepCopy(profile.activeMission),
		pendingPost = if profile.pendingPost == nil then nil else self._store._deepCopy(profile.pendingPost),
		nextOrganicContextId = self:_nextOrganicContextId(),
		ownPosts = self._store._deepCopy(profile.ownPosts),
		feedVersion = self._revision,
		saveStatus = self._saveStatus,
	}
end

function SessionService:_nextOrganicContextId(): string
	local profile = self._profile
	if profile == nil then
		return ""
	end
	local contexts = Catalog.OrganicContexts
	if #contexts == 0 then
		return ""
	end
	local sequence: number = profile.nextOrganicSequence
	local index = (sequence % #contexts) + 1
	return (contexts[index] :: any).contextId
end

-- Unbanked worker accrual, displayed separately and never spendable. Computed
-- from the live session's monotonic connected time only; there is no
-- wall-clock catch-up after a reconnect.
function SessionService:_pendingWorkerCuan(): number
	local profile = self._profile
	if profile == nil then
		return 0
	end
	-- Project each pending interval at ITS OWN rate, so the displayed
	-- unbanked accrual matches what a bank would actually credit. Using the
	-- current rate would overstate (or understate) an interval that elapsed
	-- under a different worker count.
	local fractional = profile.fractionalIncome
	local projected = 0
	local accrual: { { seconds: number, rate: number } } = self._pendingAccrual
	for i = 1, #accrual do
		local entry = accrual[i]
		fractional += entry.rate * entry.seconds
	end
	projected = math.floor(fractional)
	return projected
end

-- ===== durable replay =====
-- The durable recentMutationOutcomes ring is the authority for a completed
-- request. ProfileStore.lastSaveOpId is a single-slot last-write marker, NOT a
-- historical result cache, so a late duplicate of an OLD mutation must be
-- answered from the ring rather than from lastSaveOpId.
local function findOutcome(profile: any, requestId: string): any?
	if profile == nil then
		return nil
	end
	for _, outcome in ipairs(profile.recentMutationOutcomes) do
		if (outcome :: any).requestId == requestId then
			return outcome
		end
	end
	return nil
end

-- Result identifiers recorded in the durable ring: the minimal identity needed
-- to replay a result without re-running domain logic.
local function resultIdsFor(action: string, profile: any): { string }
	local ids: { string } = {}
	if action == "AcceptMission" and profile.activeMission ~= nil then
		table.insert(ids, `mission:{(profile.activeMission :: any).missionId}`)
		table.insert(ids, `run:{(profile.activeMission :: any).runId}`)
	elseif action == "PublishOrganic" and profile.pendingPost ~= nil then
		table.insert(ids, `post:{(profile.pendingPost :: any).postId}`)
	elseif action == "PublishPost" and profile.pendingPost ~= nil then
		table.insert(ids, `post:{(profile.pendingPost :: any).postId}`)
		table.insert(ids, `run:{(profile.pendingPost :: any).missionRunId}`)
	elseif action == "ClaimMission" then
		table.insert(ids, `claims:{profile.completedMissions}`)
	elseif action == "BuyDevice" then
		table.insert(ids, `device:{profile.deviceId}`)
	elseif action == "BuyDesk" then
		for _, slot in ipairs(profile.ownedDesks) do
			table.insert(ids, `desk:{slot}`)
		end
	elseif action == "HireWorker" then
		for _, worker in ipairs(profile.workers) do
			table.insert(ids, `hire:{(worker :: any).slotIndex}`)
		end
	end
	return ids
end

-- Append the outcome to the bounded ring, newest last, evicting the oldest.
local function appendOutcome(profile: any, outcome: any)
	local ring = profile.recentMutationOutcomes
	table.insert(ring, outcome)
	while #ring > MAX_RECENT_OUTCOMES do
		table.remove(ring, 1)
	end
end

-- ===== the single serialized lane =====
-- Every durable action for this player runs here, one at a time. The lane never
-- runs two writes concurrently for the same player, and it never busy-waits:
-- an unbounded `while busy do wait(0) end` spin would stall a caller for as long
-- as a held write takes, and docs/03 requires a busy read to return the last
-- confirmed state "without waiting".
--
-- `_tryRunLane` returns false when the lane is already held, so a caller can
-- either back off with explicit BUSY backpressure or defer the work. `_runLane`
-- keeps the blocking form for callers that must complete the action in this
-- turn (a command that has already reserved its identity), but it waits with a
-- BOUNDED number of yields and then reports BUSY rather than spinning forever.
local MAX_LANE_WAITS = 64

function SessionService:_tryRunLane(fn: () -> ()): boolean
	if self._laneBusy then
		return false
	end
	self._laneBusy = true
	local ok, err = pcall(fn)
	self._laneBusy = false
	if not ok then
		error(err, 0)
	end
	return true
end

function SessionService:_runLane(fn: () -> ()): boolean
	local waits = 0
	while self._laneBusy do
		if waits >= MAX_LANE_WAITS then
			-- Bounded backpressure: never spin forever behind a held write.
			return false
		end
		self._wait(0)
		waits += 1
	end
	return self:_tryRunLane(fn)
end

-- Advance connected time in bounded chunks without dropping the remainder.
--
-- RATE-AWARE PENDING ACCRUAL: each pending interval is stored with the
-- worker RATE that was active while it accrued, not just its duration. A
-- hire or a worker-count change must not retroactively re-rate time that
-- elapsed under a different count, and a failed write must restore the
-- interval at its ORIGINAL rate rather than the rate current at recovery.
-- `_unbankedSeconds` remains the total unbanked duration for reporting.
function SessionService:_drainChunks(): { { seconds: number, rate: number } }
	local session: any = self
	local pending: { { seconds: number, rate: number } } = session._pendingAccrual
	local drained: { { seconds: number, rate: number } } = {}
	local remaining: { { seconds: number, rate: number } } = {}
	for i = 1, #pending do
		local entry = pending[i]
		local seconds = entry.seconds
		while seconds > 0 do
			local chunk = math.min(seconds, MAX_TIME_CHUNK)
			table.insert(drained, { seconds = chunk, rate = entry.rate })
			seconds -= chunk
		end
	end
	session._pendingAccrual = remaining
	session._unbankedSeconds = 0
	return drained
end

-- Apply accrued worker income to a PROPOSED profile. Returns the proposed
-- profile, the credited amount, and the EXACT list of consumed intervals.
-- Each interval is credited with the worker count that was active while it
-- elapsed, so a hire never re-rates earlier time. The confirmed profile is
-- never touched: the caller commits the proposal only after a durable save
-- succeeds, so a failed or ambiguous write cannot publish unconfirmed Cuan.
function SessionService:_applyWorkerAccrual(base: any): (any, number, { { seconds: number, rate: number } })
	local chunks = self:_drainChunks()
	if #chunks == 0 then
		return base, 0, {}
	end
	local current = base
	local totalCredited = 0
	local consumed: { { seconds: number, rate: number } } = {}
	for i = 1, #chunks do
		local chunk = chunks[i]
		-- Credit this interval using the worker count it accrued under, by
		-- ticking a profile whose worker list reflects that rate.
		local tick = EconomyService.tickAtRate(current, chunk.seconds, chunk.rate)
		if not tick.ok then
			-- Refuse rather than clamp: the caller must not persist a partial or
			-- silently reduced credit.
			error(`SessionService: worker accrual refused ({tick.code}: {tostring(tick.detail)})`, 0)
		end
		current = tick.profile
		totalCredited += tick.earned or 0
		table.insert(consumed, chunk)
	end
	self._lastBankAt = self._connectedSeconds
	return current, totalCredited, consumed
end

-- Fold accrued worker income into a durable write that is happening anyway.
-- Returns the PROPOSED profile (with the worker credit applied) and the
-- credited amount. Never issues a write of its own: piggybacking is the only
-- path that avoids a redundant bank, and the caller performs the save.
function SessionService:_piggybackWorker(): (any, number, { { seconds: number, rate: number } })
	return self:_applyWorkerAccrual(self._profile)
end

-- Commit a proposed profile durably. On success the proposal becomes the
-- confirmed state. On failure the confirmed state is left untouched and the
-- accrued interval is restored so it is credited on a later turn exactly once.
function SessionService:_commit(proposed: any, operationId: string, intent: string?): {
	ok: boolean,
	code: string,
	revision: number?,
	detail: string?,
}
	local save = self._store:Save(proposed, operationId, intent)
	if not save.ok then
		self._saveStatus = if save.code == "SAVE_UNAVAILABLE" then "SAVE_UNAVAILABLE" else "BUSY"
		return { ok = false, code = save.code, detail = save.detail }
	end
	self._profile = self._store:GetConfirmedEnvelope().profile
	self._revision = save.revision or self._revision
	self._saveStatus = "healthy"
	return { ok = true, code = "OK", revision = save.revision }
end

-- A standalone worker bank write, used only when no other durable write is
-- already carrying the accrued interval.
function SessionService:_bankWorker(): { ok: boolean, code: string, credited: number }
	local proposed, credited, consumed = self:_piggybackWorker()
	if credited == 0 then
		return { ok = true, code = "OK", credited = 0 }
	end
	local commit = self:_commit(proposed, `{OP_PREFIX.bank}-{self._userId}-{self._lastBankAt}`)
	if not commit.ok then
		-- The proposal is discarded. The confirmed wallet is unchanged, and the
		-- exact accrued interval is restored so it is credited on a later turn
		-- exactly once rather than being silently dropped.
		self:_restoreUnbanked(credited, consumed)
		return { ok = false, code = commit.code, credited = 0 }
	end
	return { ok = true, code = "OK", credited = credited }
end

-- Restore an accrued interval that could not be confirmed, so the next lane
-- turn credits it exactly once.
--
-- EXACT ATTRIBUTION: the interval is restored as the SECONDS captured when
-- the accrual was computed, not reconstructed from the rounded credit.
-- Deriving seconds as `credited / currentRate` loses the fractional residual
-- and, worse, misattributes the interval when the worker count changed
-- between the failed write and its recovery: the same credit would be
-- divided by a different rate and the restored time would be wrong.
-- `_applyWorkerAccrual` records the exact seconds it consumed, and this
-- function restores precisely those.
function SessionService:_restoreUnbanked(credited: number, consumed: { { seconds: number, rate: number } }?)
	if credited <= 0 then
		return
	end
	local session: any = self
	if consumed ~= nil and #consumed > 0 then
		-- Restore each interval with its ORIGINAL rate, so a worker-count change
		-- between the failed write and its recovery cannot re-rate the interval.
		for i = 1, #consumed do
			local entry = consumed[i]
			table.insert(session._pendingAccrual, entry)
			session._unbankedSeconds += entry.seconds
		end
		return
	end
	-- Fallback for a caller that did not record the interval: recover from the
	-- credit using the CURRENT rate. Approximate, and only reached on a path
	-- that did not change the worker count.
	local profile = self._profile
	if profile == nil then
		return
	end
	local rate = EconomyService.incomePerSecond(profile)
	if rate <= 0 then
		return
	end
	session._unbankedSeconds += credited / rate
end


-- Settle a due post through the durable lane using its stable settlement
-- identity. The postId is server-owned and frozen, so a replayed settlement
-- cannot pay twice.
function SessionService:_settleDue(): { ok: boolean, code: string, settled: boolean }
	local profile = self._profile
	if profile == nil or profile.pendingPost == nil then
		return { ok = true, code = "OK", settled = false }
	end
	local pending: any = profile.pendingPost
	if self._now() < pending.settleAt then
		return { ok = true, code = "OK", settled = false }
	end
	local opId = `{OP_PREFIX.settlement}-{pending.postId}`
	local proposed = MissionService.settle(self._profile, self._now())
	if not proposed.ok then
		if proposed.code == "NO_PENDING_POST" then
			return { ok = true, code = "OK", settled = false }
		end
		return { ok = false, code = proposed.code, settled = false }
	end
	-- Fold accrued worker income into this same durable write.
	local merged, credited, consumed = self:_applyWorkerAccrual(proposed.profile)
	local commit = self:_commit(merged, opId)
	if not commit.ok then
		-- The proposal is discarded and the exact accrued interval is restored, so
		-- the settlement and the worker credit are retried together on a later turn.
		self:_restoreUnbanked(credited, consumed)
		return { ok = false, code = commit.code, settled = false }
	end
	return { ok = true, code = "OK", settled = true }
end

-- ===== Mutate =====
-- One serialized per-player lane. Reservations are taken BEFORE the lane so a
-- duplicate requestId cannot enter twice, and a completed request is replayed
-- from the durable ring instead of re-running domain logic.
function SessionService:Mutate(request: MutationRequest): MutationResult
	if self._stopped or self._stopping then
		return { ok = false, code = "BUSY", revision = self._revision, detail = "session is stopping" }
	end
	if self._profile == nil then
		return { ok = false, code = "LOCKED", revision = self._revision, detail = "no confirmed profile" }
	end
	if not isNonEmptyString(request.requestId) then
		return { ok = false, code = "INVALID_INPUT", revision = self._revision, detail = "requestId is required" }
	end
	if (self._saveStatus :: string) ~= "healthy" then
		-- docs/03: on lease loss or repeated failure, block economic commands.
		-- A retry of a request whose in-flight proposal is retained is the one
		-- exception: it reuses the SAME operationId and payload, so it resolves
		-- an ambiguous write instead of issuing a new economic action.
		if self._inflight[request.requestId] == nil then
			return {
				ok = false,
				code = (self._saveStatus :: string),
				revision = self._revision,
				detail = "economic actions are blocked until the save lane is healthy",
			}
		end
	end
	local action = request.action
	if MUTATING_ACTIONS[action] == nil then
		return { ok = false, code = "UNKNOWN_ACTION", revision = self._revision, detail = `unsupported action {tostring(action)}` }
	end
	local payloadOk, payloadErr = validatePayload(action, request.payload)
	if not payloadOk then
		return { ok = false, code = "INVALID_INPUT", revision = self._revision, detail = payloadErr }
	end

	-- Canonical intent. ALWAYS derived server-side from the validated action and
	-- payload. A caller-supplied `intent` is never trusted: it is the string the
	-- conflict check compares against, so honouring it would let a reused
	-- requestId with a different action/payload forge a match and be reported as
	-- a successful replay. docs/03: "An identical request ID with different
	-- action/payload is INVALID_INPUT, not a replay." BS-06's NetRouter must not
	-- forward any client intent field into this layer.
	local intent: string
	local intentOk, intentErr = pcall(function()
		intent = canonicalIntent(action, request.payload)
	end)
	if not intentOk or intent == nil then
		return { ok = false, code = "INVALID_INPUT", revision = self._revision, detail = tostring(intentErr) }
	end

	-- The durable ring is the authority for what this requestId actually did,
	-- so the intent comparison happens against the ring FIRST: a repeated
	-- requestId with a DIFFERENT intent is invalid and must not execute or save,
	-- even when a live result is already cached in this session.
	local durable = findOutcome(self._profile, request.requestId)
	if durable ~= nil then
		if durable.intent ~= intent then
			return {
				ok = false,
				code = "INVALID_INPUT",
				revision = self._revision,
				detail = "requestId was already used with a different intent",
			}
		end
		-- The ring confirms this request was APPLIED, so the ring is the
		-- authority. A cached live DEFINITE REJECTION is stale: it was recorded
		-- before the durable write landed (for example a settlement that failed
		-- locally while the held write actually committed). Returning it would
		-- report a rejection for a mutation that durably succeeded. Only a live
		-- result that is itself an APPLIED/OK record may be reused.
		local live = self._liveResults[request.requestId]
		if live ~= nil and live.code == "OK" then
			if live.lookup == nil then
				local replayedLive: MutationResult = {
					ok = true,
					code = "OK",
					revision = live.revision,
					lookup = "APPLIED",
					data = live.data,
				}
				self._liveResults[request.requestId] = replayedLive
				return replayedLive
			end
			return live
		end
		local replayed: MutationResult = {
			ok = true,
			code = "OK",
			revision = durable.revision,
			lookup = "APPLIED",
			data = { resultIds = durable.resultIds },
		}
		self._liveResults[request.requestId] = replayed
		return replayed
	end
	-- No durable record: a live definite rejection is still cached, because a
	-- validation error never reaches the store and so never enters the ring.
	local live = self._liveResults[request.requestId]
	if live ~= nil then
		return live
	end
	-- An ambiguous write left an in-flight proposal. A retry of the identical
	-- request reuses that SAME proposal and operationId, so ProfileStore's
	-- idempotent short-circuit resolves it instead of rejecting a rebuilt
	-- payload as a protocol violation. The domain logic is never re-run.
	local inflight = self._inflight[request.requestId]
	if inflight ~= nil then
		if inflight.intent ~= intent then
			return {
				ok = false,
				code = "INVALID_INPUT",
				revision = self._revision,
				detail = "requestId was already used with a different intent",
			}
		end
		local retryResult: MutationResult? = nil
		local retrySession: any = self
		self:_runLane(function()
			local commit = retrySession:_commit(inflight.profile, inflight.opId, inflight.intent)
			if not commit.ok then
				local failedRetry: MutationResult = {
					ok = false,
					code = (commit.code :: string),
					revision = retrySession._revision,
					detail = commit.detail,
					lookup = if (commit.code :: string) == "BUSY" then "PENDING" else "UNKNOWN",
				}
				retryResult = failedRetry
				return
			end
			retrySession._inflight[request.requestId] = nil
			-- The reconciled proposal already carries the durable ring entry, so
			-- the recorded resultIds come straight from it. Assigning to
			-- retryResult is what makes the APPLIED result reach the caller; without
			-- it Mutate falls through and reports the mutation as unprocessed.
			local ring = inflight.profile.recentMutationOutcomes
			local recorded = ring[#ring]
			retryResult = {
				ok = true,
				code = "OK",
				revision = retrySession._revision,
				lookup = "APPLIED",
				data = { resultIds = if recorded ~= nil then recorded.resultIds else nil },
			} :: MutationResult
		end)
		if retryResult ~= nil then
			if retryResult.ok then
				self._liveResults[request.requestId] = retryResult
			end
			return retryResult
		end
	end

	-- Reservation before the lane, so a duplicate cannot enter twice.
	if self._reserved[request.requestId] then
		return {
			ok = false,
			code = "BUSY",
			revision = self._revision,
			detail = "request is already in flight",
			lookup = "PENDING",
		}
	end
	if #self._queue >= MAX_QUEUED_ACTIONS then
		return {
			ok = false,
			code = "BUSY",
			revision = self._revision,
			detail = "mutation queue is full",
		}
	end
	self._reserved[request.requestId] = true
	table.insert(self._queue, {
		requestId = request.requestId,
		action = action,
		payload = request.payload,
		intent = intent,
	})

	local result: MutationResult? = nil
	local session: any = self
	self:_runLane(function()
		-- Drop everything queued ahead of us that is no longer relevant: a
		-- queued request whose ID was resolved while waiting is skipped.
		while #session._queue > 0 do
			local head = session._queue[1]
			if session._liveResults[head.requestId] ~= nil then
				table.remove(session._queue, 1)
				continue
			end
			table.remove(session._queue, 1)
			local outcome = session:_executeMutation(head.requestId, head.action, head.payload, head.intent)
			if head.requestId == request.requestId then
				result = outcome
			end
			-- A failed or blocked lane stops the drain: later requests must see
			-- the current save status rather than queue behind a dead lane.
			if not outcome.ok and (outcome.code == "SAVE_UNAVAILABLE" or outcome.code == "BUSY") then
				break
			end
		end
	end)

	if result == nil then
		-- Our request was resolved by an earlier turn in the same drain.
		local settled_ = self._liveResults[request.requestId]
		if settled_ ~= nil then
			return settled_
		end
		return {
			ok = false,
			code = "BUSY",
			revision = self._revision,
			detail = "mutation was not processed",
			lookup = "UNKNOWN",
		}
	end
	return result
end

-- Execute one reserved mutation inside the lane. Domain logic is delegated to
-- MissionService / EconomyService; this function owns the durable write and
-- the replay bookkeeping only.
function SessionService:_executeMutation(
	requestId: string,
	action: string,
	payload: { [string]: any },
	intent: string
): MutationResult
	-- A due settlement is processed first through its own stable identity, so
	-- the command never races an outstanding post.
	local settle = self:_settleDue()
	if not settle.ok then
		local blocked: MutationResult = {
			ok = false,
			code = settle.code,
			revision = self._revision,
			detail = "pending settlement could not be confirmed",
		}
		self._liveResults[requestId] = blocked
		self._reserved[requestId] = nil
		return blocked
	end

	-- Domain transformation on a proposal. The confirmed profile is never
	-- mutated in place.
	--
	-- ACCRUAL ORDERING (correctness): accrued connected time must be attributed
	-- to the worker count that was active DURING that interval, not the count
	-- this mutation is about to produce. A first hire must not retroactively pay
	-- the pre-hire seconds at the new rate, and a second hire must not re-rate
	-- the first interval. So the worker credit is computed against the CONFIRMED
	-- pre-mutation profile first, and the domain mutation is applied on top of
	-- that credited proposal. The single durable write still carries both
	-- atomically, so piggybacking is preserved and previously accrued income can
	-- fund the purchase exactly as the frozen economy contract requires.
	local accrued, workerCredited, workerConsumed = self:_applyWorkerAccrual(self._profile)
	local proposed: any = nil
	local domainCode = "OK"
	local domainDetail: string? = nil
	if action == "AcceptMission" then
		local r = MissionService.accept(accrued, payload.missionId, self:_nextRunId(), self._now())
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	elseif action == "PublishOrganic" then
		local r = MissionService.publishOrganic(accrued, payload.templateId, self._now())
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	elseif action == "PublishPost" then
		local r = MissionService.publishMission(accrued, payload.runId, payload.templateId, self._now())
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	elseif action == "ClaimMission" then
		local r = MissionService.claim(accrued, payload.runId)
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	elseif action == "BuyDevice" then
		local r = EconomyService.buyDevice(accrued, payload.deviceId)
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	elseif action == "BuyDesk" then
		local r = EconomyService.buyDesk(accrued, payload.slotIndex)
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	elseif action == "HireWorker" then
		local r = EconomyService.hireWorker(accrued, payload.slotIndex, payload.roleId)
		proposed, domainCode, domainDetail = r.profile, r.code, r.detail
	end
	if proposed == nil then
		-- Definite rejection: cached live, no durable write. The accrued interval
		-- is NOT consumed, because nothing was written; it stays unbanked and is
		-- credited on the next durable turn exactly once.
		local rejected: MutationResult = {
			ok = false,
			code = domainCode,
			revision = self._revision,
			detail = domainDetail,
			lookup = "REJECTED",
		}
		self._liveResults[requestId] = rejected
		self._reserved[requestId] = nil
		return rejected
	end
	-- Record the durable outcome in the SAME conditional write as the mutation
	-- (docs/03: "persist the outcome in the same conditional write as the
	-- mutation"). The ring entry is appended to the proposal before the save,
	-- so a reconnect can replay this request without re-running domain logic.
	local ids = resultIdsFor(action, proposed)
	appendOutcome(proposed, {
		requestId = requestId,
		action = action,
		intent = intent,
		ok = true,
		code = "OK",
		revision = self._revision + 1,
		resultIds = ids,
	})
	-- Server-owned operation ID for this durable write. It is NOT the client
	-- requestId: request identity lives in the ring, transaction identity here.
	local opId = `{OP_PREFIX.command}-{self._userId}-{requestId}`
	-- Retain the in-flight proposal so an ambiguous retry reuses the SAME
	-- payload and the SAME operationId. ProfileStore compares the durable
	-- profile against a fingerprint of what this operationId wrote; rebuilding
	-- the proposal would produce a different fingerprint and be rejected as a
	-- protocol violation instead of resolving idempotently.
	self._inflight[requestId] = { profile = proposed, opId = opId, intent = intent }
	local commit = self:_commit(proposed, opId, intent)
	if not commit.ok then
		-- The proposal is discarded. The accrued interval is restored so the
		-- worker credit is applied on a later turn exactly once, and the
		-- mutation itself is never confirmed.
		self:_restoreUnbanked(workerCredited, workerConsumed)
		local failed: MutationResult = {
			ok = false,
			code = commit.code,
			revision = self._revision,
			detail = commit.detail,
			lookup = if commit.code == "BUSY" then "PENDING" else "UNKNOWN",
		}
		-- Never cache an ambiguous outcome as a definite result. The in-flight
		-- entry is kept so a retry can resolve through the same identity.
		self._reserved[requestId] = nil
		return failed
	end
	self._inflight[requestId] = nil

	-- Confirmed. The durable profile is the authority: it already carries the
	-- ring entry written in this same conditional save, so a reconnect can
	-- replay this request without re-running domain logic.
	self._profile = self._store:GetConfirmedEnvelope().profile
	self._revision = commit.revision or self._revision
	self._saveStatus = "healthy"

	local confirmed: MutationResult = {
		ok = true,
		code = "OK",
		revision = self._revision,
		data = { resultIds = ids, workerCredited = workerCredited },
	}
	self._liveResults[requestId] = confirmed
	self._reserved[requestId] = nil
	return confirmed
end

-- Server-owned run identifier for a newly accepted mission.
--
-- UNIQUENESS: the ID is derived from the persisted monotonic
-- `nextPostSequence`, never from `#claimedRunIdsWindow`. The claimed window is a
-- bounded 32-entry eviction structure, so its length is not a counter: once
-- eviction begins, `#window + 1` regenerates IDs that were already claimed,
-- and MissionService.claim would then refuse the new run with ALREADY_DONE,
-- permanently blocking that mission. `nextPostSequence` is already part of the
-- frozen v1 profile, is monotonic, and advances on every publish, so it can
-- never repeat for the lifetime of the profile. No new persisted field is
-- introduced.
function SessionService:_nextRunId(): string
	local profile = self._profile
	if profile == nil then
		return "run-1"
	end
	-- A fresh v1 profile carries nextPostSequence = 1, and the counter advances
	-- once per published post. The run is created at accept time, before any of
	-- its posts exist, so the current value is the correct base: run-1 for a
	-- fresh profile, run-2 after one post, and so on. Because the counter is
	-- monotonic and never reused, no generated ID can collide with an active or
	-- previously claimed run, even after the 32-entry claimed window evicts.
	local sequence: number = profile.nextPostSequence or 1
	return `run-{sequence}`
end

-- ===== Snapshot =====
-- Sanitized read projection. Performs no write of its own for ordinary reads.
-- docs/03: GetSnapshot "may settle an already-due post through durable lane";
-- a due settlement is processed through the existing serialized lane using its
-- stable settlement identity, so a snapshot can settle an already-due post but
-- never creates one. When the lane is busy, the last confirmed snapshot is
-- returned with the lookup status, without waiting.
function SessionService:Snapshot(lookupRequestId: string?): SnapshotResult
	if self._profile == nil then
		return { ok = false, code = "LOCKED" }
	end
	local lookup = nil
	if lookupRequestId ~= nil and isNonEmptyString(lookupRequestId) then
		lookup = self:_lookup(lookupRequestId)
	end
	-- Settle an already-due post through the durable lane. The settlement has
	-- its own stable server-owned identity, so it cannot pay twice and cannot
	-- race a concurrent command.
	--
	-- NON-BLOCKING (docs/03): "when write lane is busy, return last confirmed
	-- snapshot and current lookup status without waiting." A read must never
	-- stall behind a held write, so the settlement is attempted only when the
	-- lane is free; otherwise the last confirmed snapshot is returned as-is and
	-- the due post settles on the next lane turn.
	local pending: any = self._profile.pendingPost
	if pending ~= nil and self._now() >= pending.settleAt then
		local session: any = self
		self:_tryRunLane(function()
			session:_settleDue()
		end)
	end
	return { ok = true, code = "OK", snapshot = self:_buildSnapshot(), lookup = lookup }
end

-- Resolve a request ID to APPLIED / REJECTED / PENDING / UNKNOWN.
-- An evicted or absent outcome is UNKNOWN, never evidence that the write did
-- not happen.
function SessionService:_lookup(requestId: string): {
	originalRequestId: string,
	status: LookupStatus,
	originalResult: { ok: boolean, code: string, revision: number, data: { [string]: any }? }?,
}
	local live = self._liveResults[requestId]
	if live ~= nil then
		if live.code == "OK" then
			return {
				originalRequestId = requestId,
				status = "APPLIED",
				originalResult = { ok = true, code = "OK", revision = live.revision, data = live.data },
			}
		end
		return {
			originalRequestId = requestId,
			status = "REJECTED",
			originalResult = { ok = false, code = (live.code :: string), revision = live.revision, data = live.data },
		}
	end
	if self._reserved[requestId] then
		return { originalRequestId = requestId, status = "PENDING" }
	end
	local durable = findOutcome(self._profile, requestId)
	if durable ~= nil then
		return {
			originalRequestId = requestId,
			status = "APPLIED",
			originalResult = {
				ok = true,
				code = "OK",
				revision = durable.revision,
				data = { resultIds = durable.resultIds },
			},
		}
	end
	return { originalRequestId = requestId, status = "UNKNOWN" }
end

-- ===== Stop =====
-- Stop connected-time accrual, drain or safely resolve outstanding writes,
-- perform the final worker banking through a durable Save where possible, and
-- release the lease only after that confirmed banking. A second Stop cannot
-- double-save or double-release.
function SessionService:Stop(): { ok: boolean, code: string, detail: string?, banked: number? }
	if self._stopped then
		return { ok = true, code = "OK", detail = "already stopped", banked = 0 }
	end
	if self._stopping then
		return { ok = false, code = "BUSY", detail = "stop already in progress" }
	end
	if self._profile == nil then
		self._stopped = true
		return { ok = true, code = "OK", detail = "nothing to stop", banked = 0 }
	end
	self._stopping = true
	local banked = 0
	-- Final worker banking through a durable Save where possible. ProfileStore
	-- Release does NOT accept a final profile payload, so the bank must be a
	-- real Save before the lease is cleared.
	--
	-- The bank runs inside the serialized lane so it cannot race an in-progress
	-- mutation. If the lane is held, Stop must not hang: it reports BUSY and
	-- leaves the session open so the caller can retry once the lane drains. The
	-- lease is retained, so a rejoin can still reconcile.
	local bankResult: { ok: boolean, code: string, credited: number }? = nil
	local entered = self:_runLane(function()
		bankResult = self:_bankWorker()
	end)
	if not entered then
		self._stopping = false
		return {
			ok = false,
			code = "BUSY",
			detail = "the mutation lane is busy; retry Stop once it drains",
			banked = 0,
		}
	end
	local bank = bankResult :: any
	if bank.ok then
		banked = bank.credited
	else
		-- Unresolved failure: report it explicitly. The confirmed wallet is
		-- unchanged and the lease is NOT released, so a rejoin can reconcile.
		self._stopping = false
		self._stopped = true
		return {
			ok = false,
			code = bank.code,
			detail = "final worker bank could not be confirmed; lease retained",
			banked = 0,
		}
	end
	local release = self._store:Release(`{OP_PREFIX.final}-{self._userId}`)
	self._stopping = false
	self._stopped = true
	if not release.ok then
		return {
			ok = false,
			code = release.code,
			detail = "final bank confirmed but the lease could not be released",
			banked = banked,
		}
	end
	return { ok = true, code = "OK", banked = banked }
end

-- ===== scheduler surface (BS-06 Bootstrap integration) =====
-- One shared aggregate scheduler interface. Deterministic under a fake clock:
-- the caller supplies monotonic connected elapsed time, never a wall-clock
-- difference, so no offline income can be fabricated.
function SessionService:Advance(connectedSeconds: number): { ok: boolean, code: string, banked: number }
	if self._stopped or self._stopping then
		return { ok = false, code = "BUSY", banked = 0 }
	end
	if self._profile == nil then
		return { ok = false, code = "LOCKED", banked = 0 }
	end
	if not isFiniteNumber(connectedSeconds) or connectedSeconds < 0 then
		return { ok = false, code = "INVALID_INPUT", banked = 0 }
	end
	local session: any = self
	session._connectedSeconds += connectedSeconds
	-- Tag the interval with the worker rate active NOW, so a later hire cannot
	-- re-rate time that elapsed under the current count.
	local activeRate = EconomyService.incomePerSecond(self._profile)
	table.insert(session._pendingAccrual, { seconds = connectedSeconds, rate = activeRate })
	session._unbankedSeconds += connectedSeconds
	-- A due settlement is handled by the lane through its stable identity.
	local banked = 0
	self:_runLane(function()
		local settle = self:_settleDue()
		if not settle.ok then
			return
		end
		-- Bank at most every 30 connected seconds while healthy.
		if self._unbankedSeconds >= WORKER_BANK_INTERVAL then
			local bank = self:_bankWorker()
			if bank.ok then
				banked = bank.credited
			end
		end
	end)
	return { ok = true, code = "OK", banked = banked }
end

-- Renew the lease when it is close to expiry, piggybacking any accrued worker
-- income onto the same durable write so an idle session costs at most one
-- write per renewal window.
function SessionService:RenewLease(): { ok: boolean, code: string }
	if self._stopped or self._stopping or self._profile == nil then
		return { ok = false, code = "BUSY" }
	end
	local okCode = "OK"
	self:_runLane(function()
		local proposed, _credited = self:_piggybackWorker()
		local opId = `{OP_PREFIX.renew}-{self._userId}-{self._connectedSeconds}`
		local commit = self:_commit(proposed, opId)
		if not commit.ok then
			okCode = commit.code
			return
		end
	end)
	return { ok = okCode == "OK", code = okCode }
end

-- ===== introspection for specs / Bootstrap =====
function SessionService:GetConfirmedProfile(): any?
	return if self._profile == nil then nil else self._store._deepCopy(self._profile)
end
function SessionService:GetRevision(): number
	return self._revision
end
function SessionService:GetSaveStatus(): SaveStatusCode
	return self._saveStatus
end
function SessionService:GetPendingWorkerCuan(): number
	return self:_pendingWorkerCuan()
end
function SessionService:IsStarted(): boolean
	return self._started
end

SessionService.WORKER_BANK_INTERVAL = WORKER_BANK_INTERVAL
SessionService.LEASE_RENEW_INTERVAL = LEASE_RENEW_INTERVAL
SessionService.MAX_TIME_CHUNK = MAX_TIME_CHUNK
SessionService.MAX_QUEUED_ACTIONS = MAX_QUEUED_ACTIONS
SessionService.MAX_INTENT_LENGTH = MAX_INTENT_LENGTH
SessionService.MAX_LANE_WAITS = MAX_LANE_WAITS

return SessionService
