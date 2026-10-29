--!strict
-- Buzzer Simulator — EconomyService (BS-04, pure domain layer).
-- Device purchases, desk purchases, worker hires, and aggregate worker accrual.
--
-- BOUNDARY (docs/03, BS-04 in docs/08): this module owns pure economy-state
-- transformations ONLY. It never persists, never touches the network, never
-- mutates its input profile, and never awards anything before a durable write
-- confirms it. Every operation returns an explicit code plus a PROPOSED
-- profile; SessionService performs the conditional write and only then
-- publishes the state.
--
-- Determinism: no randomness and no wall-clock reads anywhere. Connected time
-- is injected by the caller in bounded chunks, so a rejoin or a replayed tick
-- produces exactly the same result.
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))
local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Rules"))

local EconomyService = {}

-- Frozen economy guard (docs/04: "stop growth before 1e12"). A credit that
-- would bring either currency total to or past this bound is refused outright
-- rather than clamped, so no payout formula is altered and no partial mutation
-- can land. MissionService and ProfileStore repeat the same check.
local MAX_ECONOMIC_TOTAL = 1e12

-- docs/04: worker rate is 1.5 Cuan/s per owned worker, 0..2 workers.
local WORKER_RATE_PER_WORKER = 1.5
local MAX_WORKERS = 2

-- docs/03: connected monotonic time is processed in bounded chunks so a long
-- save or frame hitch cannot silently discard connected time. The remainder
-- is retained by the caller for the next lane turn.
local MAX_TIME_CHUNK = 60

-- Authored M1 automation values (docs/04). These are FUTURE content: V0 ships
-- no desk or worker purchase, so they are validated only through explicit
-- injected fixtures, never through a V0 button.
local DESK_PRICES: { [number]: number } = { [1] = 180, [2] = 250 }
local HIRE_PRICES: { [number]: number } = { [1] = 500, [2] = 750 }

-- The single productive device that authorizes a worker station (docs/02).
local PC_DEVICE_ID = "pc_rumah"

export type ResultCode =
	"OK"
	| "INVALID_INPUT"
	| "NOT_READY"
	| "ALREADY_DONE"
	| "INSUFFICIENT_FUNDS"
	| "LIMIT_REACHED"
	| "UNKNOWN_DEVICE"
	| "UNKNOWN_DESK"
	| "UNKNOWN_WORKER"

export type OperationResult = {
	ok: boolean,
	code: ResultCode,
	detail: string?,
	profile: any?, -- proposed updated profile when ok
	spent: number?, -- Cuan debited by this operation (purchases/hires)
	earned: number?, -- Cuan credited by this operation (worker accrual)
}

local function ok(profile: any): OperationResult
	return { ok = true, code = "OK", profile = profile }
end
local function fail(code: ResultCode, detail: string?): OperationResult
	return { ok = false, code = code, detail = detail }
end

-- ===== helpers =====
-- Deep copy so the caller's profile is never mutated, in place or by aliasing.
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
EconomyService._deepCopy = deepCopy

local function isNonEmptyString(v: any): boolean
	return typeof(v) == "string" and #v > 0
end

local function isNonNegativeInteger(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0 and v % 1 == 0
end

local function isFiniteNumber(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A valid v1 profile is the caller's responsibility (ProfileStore validates
-- before any durable write). These guards keep the pure layer from paying on
-- a malformed table, and never coerce or repair.
local function isUsableProfile(profile: any): boolean
	if typeof(profile) ~= "table" then
		return false
	end
	if not isNonNegativeInteger(profile.balance) then
		return false
	end
	if not isNonNegativeInteger(profile.lifetimeEarned) then
		return false
	end
	if not isNonNegativeInteger(profile.completedMissions) then
		return false
	end
	if not isNonEmptyString(profile.deviceId) then
		return false
	end
	if typeof(profile.ownedDesks) ~= "table" or typeof(profile.workers) ~= "table" then
		return false
	end
	if not isFiniteNumber(profile.fractionalIncome) or profile.fractionalIncome < 0 or profile.fractionalIncome >= 1 then
		return false
	end
	return true
end

local function findDevice(deviceId: any): any?
	if not isNonEmptyString(deviceId) then
		return nil
	end
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).id == deviceId then
			return device
		end
	end
	return nil
end

-- V0 ships cheap + fast phone only (Catalog.V0Shipped.deviceIds). PC Rumah is
-- authored catalog data but is NOT purchasable until BS-11 releases M1 content.
local function isShippedDevice(deviceId: any): boolean
	if not isNonEmptyString(deviceId) then
		return false
	end
	for _, id in ipairs(Catalog.V0Shipped.deviceIds) do
		if id == deviceId then
			return true
		end
	end
	return false
end

-- Exact-next device progression (docs/03: "Exact next cheap -> fast -> PC").
-- The owned device is the single productive device, so the next purchasable
-- device is the one immediately after it in catalog order. Skipping a tier or
-- re-buying the owned device is refused; device yields never stack.
local function nextDeviceAfter(deviceId: any): any?
	if not isNonEmptyString(deviceId) then
		return nil
	end
	local ownedOrder = nil
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).id == deviceId then
			ownedOrder = (device :: any).order
			break
		end
	end
	if ownedOrder == nil then
		return nil
	end
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).order == ownedOrder + 1 then
			return device
		end
	end
	return nil
end

local function ownsDevice(profile: any, deviceId: any): boolean
	return profile.deviceId == deviceId
end

local function ownsDesk(profile: any, slotIndex: number): boolean
	for _, slot in ipairs(profile.ownedDesks) do
		if slot == slotIndex then
			return true
		end
	end
	return false
end

local function workerAtSlot(profile: any, slotIndex: number): any?
	for _, worker in ipairs(profile.workers) do
		if (worker :: any).slotIndex == slotIndex then
			return worker
		end
	end
	return nil
end

-- Highest shipped eligible tier, derived from the monotone inputs. Spending
-- never demotes, so the derivation is stable across a rejoin.
local function eligibleTier(profile: any): number
	return Rules.eligibleTier(
		profile.lifetimeEarned,
		profile.completedMissions,
		Catalog.V0Shipped.maxShippedTier
	)
end

-- ===== device purchases =====
-- V0 ships exactly one purchasable device: phone_fast at 50 Cuan. The starter
-- device is phone_cheap. Prices come from the catalog only; a client-supplied
-- price is never read.
function EconomyService.buyDevice(profile: any, deviceId: string): OperationResult
	if not isNonEmptyString(deviceId) then
		return fail("INVALID_INPUT", "deviceId is required")
	end
	if not isUsableProfile(profile) then
		return fail("INVALID_INPUT", "profile is not a usable v1 profile")
	end
	local device = findDevice(deviceId)
	if device == nil then
		return fail("UNKNOWN_DEVICE", `unknown device {deviceId}`)
	end
	if not isShippedDevice(deviceId) then
		return fail("NOT_READY", `device {deviceId} is not shipped in V0`)
	end
	if ownsDevice(profile, deviceId) then
		return fail("ALREADY_DONE", `device {deviceId} is already equipped`)
	end
	local nextDevice = nextDeviceAfter(profile.deviceId)
	if nextDevice == nil or (nextDevice :: any).id ~= deviceId then
		return fail(
			"NOT_READY",
			`device {deviceId} is not the exact next device after {profile.deviceId}`
		)
	end
	local price = (device :: any).price
	if profile.balance < price then
		return fail(
			"INSUFFICIENT_FUNDS",
			`device {deviceId} costs {price}; balance is {profile.balance}`
		)
	end
	local nextBalance = profile.balance - price
	if nextBalance < 0 then
		return fail("INSUFFICIENT_FUNDS", "purchase would make the balance negative")
	end
	local next = deepCopy(profile)
	next.balance = nextBalance
	-- The equipped device is the single productive device. Buying replaces it;
	-- yields never stack.
	next.deviceId = deviceId
	local result = ok(next)
	result.spent = price
	return result
end

-- ===== desk purchases =====
-- M1 content (docs/04): desk 1 at 180, desk 2 at 250. Gated on PC Rumah
-- ownership, player tier, sequential slot progression and funds. V0 ships no
-- desk purchase, so this path is exercised only through explicit fixtures.
function EconomyService.buyDesk(profile: any, slotIndex: number): OperationResult
	if typeof(slotIndex) ~= "number" or slotIndex % 1 ~= 0 then
		return fail("INVALID_INPUT", "slotIndex must be an integer")
	end
	if not isUsableProfile(profile) then
		return fail("INVALID_INPUT", "profile is not a usable v1 profile")
	end
	if slotIndex < 1 or slotIndex > MAX_WORKERS then
		return fail("INVALID_INPUT", `slotIndex must be 1 or {MAX_WORKERS}`)
	end
	if ownsDesk(profile, slotIndex) then
		return fail("ALREADY_DONE", `desk slot {slotIndex} is already owned`)
	end
	-- Sequential progression: slot 1 first, then slot 2.
	if slotIndex > 1 and not ownsDesk(profile, slotIndex - 1) then
		return fail("NOT_READY", `desk slot {slotIndex - 1} must be owned first`)
	end
	-- A worker station requires the PC (docs/02 automation table).
	if not ownsDevice(profile, PC_DEVICE_ID) then
		return fail("NOT_READY", `a desk requires the {PC_DEVICE_ID} production device`)
	end
	local tier = eligibleTier(profile)
	if tier < slotIndex then
		return fail("NOT_READY", `desk slot {slotIndex} requires tier {slotIndex}; eligible tier is {tier}`)
	end
	local price = DESK_PRICES[slotIndex]
	if price == nil then
		return fail("UNKNOWN_DESK", `no authored price for desk slot {slotIndex}`)
	end
	if profile.balance < price then
		return fail("INSUFFICIENT_FUNDS", `desk slot {slotIndex} costs {price}; balance is {profile.balance}`)
	end
	local nextBalance = profile.balance - price
	if nextBalance < 0 then
		return fail("INSUFFICIENT_FUNDS", "purchase would make the balance negative")
	end
	local next = deepCopy(profile)
	next.balance = nextBalance
	local desks: { number } = {}
	for _, slot in ipairs(profile.ownedDesks) do
		table.insert(desks, slot)
	end
	table.insert(desks, slotIndex)
	table.sort(desks)
	next.ownedDesks = desks
	local result = ok(next)
	result.spent = price
	return result
end

-- ===== hire workers =====
-- M1 content (docs/04): trainee 1 at 500, trainee 2 at 750. Gated on PC Rumah
-- ownership, tier, a purchased desk in the same slot, a vacant slot, sequential
-- progression, the two-worker cap and funds. Workers never independently
-- complete campaign missions: they only accrue Cuan while connected.
function EconomyService.hireWorker(profile: any, slotIndex: number, roleId: string): OperationResult
	if typeof(slotIndex) ~= "number" or slotIndex % 1 ~= 0 then
		return fail("INVALID_INPUT", "slotIndex must be an integer")
	end
	if roleId ~= "trainee" then
		return fail("INVALID_INPUT", `roleId must be "trainee", got {tostring(roleId)}`)
	end
	if not isUsableProfile(profile) then
		return fail("INVALID_INPUT", "profile is not a usable v1 profile")
	end
	if slotIndex < 1 or slotIndex > MAX_WORKERS then
		return fail("INVALID_INPUT", `slotIndex must be 1 or {MAX_WORKERS}`)
	end
	if workerAtSlot(profile, slotIndex) ~= nil then
		return fail("ALREADY_DONE", `worker slot {slotIndex} is already occupied`)
	end
	if #profile.workers >= MAX_WORKERS then
		return fail("NOT_READY", `at most {MAX_WORKERS} workers may be hired`)
	end
	-- Sequential progression: slot 1 first, then slot 2.
	if slotIndex > 1 and workerAtSlot(profile, slotIndex - 1) == nil then
		return fail("NOT_READY", `worker slot {slotIndex - 1} must be filled first`)
	end
	-- The corresponding desk must be purchased (docs/02 automation table).
	if not ownsDesk(profile, slotIndex) then
		return fail("NOT_READY", `desk slot {slotIndex} must be owned before hiring`)
	end
	if not ownsDevice(profile, PC_DEVICE_ID) then
		return fail("NOT_READY", `hiring requires the {PC_DEVICE_ID} production device`)
	end
	local tier = eligibleTier(profile)
	if tier < slotIndex then
		return fail("NOT_READY", `worker slot {slotIndex} requires tier {slotIndex}; eligible tier is {tier}`)
	end
	local price = HIRE_PRICES[slotIndex]
	if price == nil then
		return fail("UNKNOWN_WORKER", `no authored price for worker slot {slotIndex}`)
	end
	if profile.balance < price then
		return fail("INSUFFICIENT_FUNDS", `worker slot {slotIndex} costs {price}; balance is {profile.balance}`)
	end
	local nextBalance = profile.balance - price
	if nextBalance < 0 then
		return fail("INSUFFICIENT_FUNDS", "hire would make the balance negative")
	end
	local next = deepCopy(profile)
	next.balance = nextBalance
	local workers: { any } = {}
	for _, worker in ipairs(profile.workers) do
		table.insert(workers, deepCopy(worker))
	end
	-- hireId is server-owned and derived from the durable slot, never from the
	-- client. A rejoin restores the same identifier for the same slot.
	table.insert(workers, {
		hireId = `trainee-slot-{slotIndex}`,
		roleId = "trainee",
		slotIndex = slotIndex,
	})
	table.sort(workers, function(a, b)
		return (a :: any).slotIndex < (b :: any).slotIndex
	end)
	next.workers = workers
	local result = ok(next)
	result.spent = price
	return result
end

-- ===== worker accrual =====
-- Aggregate per-player accrual for connected time only. There is no per-worker
-- coroutine and no offline catch-up: the caller supplies monotonic connected
-- elapsed time in bounded chunks and retains the remainder.
--
-- Credit: floor(fractionalIncome + rate * connectedSeconds) with residual
-- carry, so fractional output is never lost or double-counted. The credit is
-- a PROPOSAL only; it becomes confirmed balance after a durable save.
function EconomyService.tick(profile: any, connectedSeconds: number): OperationResult
	if not isFiniteNumber(connectedSeconds) or connectedSeconds < 0 then
		return fail("INVALID_INPUT", "connectedSeconds must be a finite nonnegative number")
	end
	if not isUsableProfile(profile) then
		return fail("INVALID_INPUT", "profile is not a usable v1 profile")
	end
	local workerCount = #profile.workers
	if workerCount == 0 or connectedSeconds == 0 then
		-- No accrual, but still a valid proposal so the caller can treat the
		-- tick uniformly. No write is required for a zero credit.
		return ok(deepCopy(profile))
	end
	if workerCount > MAX_WORKERS then
		return fail("INVALID_INPUT", `at most {MAX_WORKERS} workers may accrue`)
	end
	local rate = WORKER_RATE_PER_WORKER * workerCount
	local fractional = profile.fractionalIncome + rate * connectedSeconds
	local credit = math.floor(fractional)
	local residual = fractional - credit
	if credit > 0 then
		local nextBalance = profile.balance + credit
		local nextLifetime = profile.lifetimeEarned + credit
		if nextBalance >= MAX_ECONOMIC_TOTAL or nextLifetime >= MAX_ECONOMIC_TOTAL then
			return fail(
				"LIMIT_REACHED",
				`worker accrual would reach the {MAX_ECONOMIC_TOTAL} economy limit`
			)
		end
		local next = deepCopy(profile)
		next.balance = nextBalance
		next.lifetimeEarned = nextLifetime
		next.fractionalIncome = residual
		local result = ok(next)
		result.earned = credit
		return result
	end
	-- Sub-integer accrual: carry the residual without touching the wallet.
	local next = deepCopy(profile)
	next.fractionalIncome = residual
	return ok(next)
end

-- ===== introspection (used by SessionService and specs) =====
-- Worker income rate in Cuan/s for the currently owned workers.
function EconomyService.incomePerSecond(profile: any): number
	if typeof(profile) ~= "table" or typeof(profile.workers) ~= "table" then
		return 0
	end
	local workerCount = #profile.workers
	if workerCount == 0 then
		return 0
	end
	return WORKER_RATE_PER_WORKER * math.min(workerCount, MAX_WORKERS)
end

-- Split a connected interval into bounded chunks (docs/03: dt <= 60s) without
-- dropping any remainder. Returns the chunk list and the leftover seconds,
-- which the caller retains for the next lane turn.
function EconomyService.chunkConnectedTime(connectedSeconds: number): ({ number }, number)
	local chunks: { number } = {}
	local remaining = connectedSeconds
	while remaining > 0 do
		local chunk = math.min(remaining, MAX_TIME_CHUNK)
		table.insert(chunks, chunk)
		remaining -= chunk
	end
	return chunks, remaining
end

EconomyService.WORKER_RATE_PER_WORKER = WORKER_RATE_PER_WORKER
EconomyService.MAX_WORKERS = MAX_WORKERS
EconomyService.MAX_TIME_CHUNK = MAX_TIME_CHUNK
EconomyService.MAX_ECONOMIC_TOTAL = MAX_ECONOMIC_TOTAL
EconomyService.DESK_PRICES = DESK_PRICES
EconomyService.HIRE_PRICES = HIRE_PRICES
EconomyService.PC_DEVICE_ID = PC_DEVICE_ID

return EconomyService
