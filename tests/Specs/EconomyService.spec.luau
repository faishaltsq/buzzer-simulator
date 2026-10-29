--!strict
-- Buzzer Simulator — EconomyService spec (BS-04).
-- Executed by tests/Runner.server.luau in the test project only.
-- Deterministic pure-transformation tests: no randomness, no network, no
-- wall-clock reads. Contract sources: docs/02, docs/04, docs/08 (BS-04).
local ServerStorage = game:GetService("ServerStorage")
local EconomyService = require(ServerStorage:WaitForChild("EconomyService"))
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))

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
local function expectCode(result: any, code: string, label: string)
	if result.ok then
		error(`{label}: expected {code}, got OK`, 0)
	end
	expectEqual(result.code, code, label)
end
local function expectOk(result: any, label: string): any
	if not result.ok then
		error(`{label}: expected OK, got {result.code} ({tostring(result.detail)})`, 0)
	end
	return result.profile
end

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

-- ===== fixture isolation =====
-- M1 content is authored in docs/04 but is NOT shipped in V0. Tests that need
-- PC/desk/worker values swap the shared catalog tables through a protected
-- fixture that restores the EXACT original references even when the body
-- throws, so one failure cannot contaminate the rest of the place.
local function withCatalogFixture(
	deviceIds: { string },
	maxShippedTier: number,
	fn: () -> ()
)
	local realDevices = Catalog.V0Shipped.deviceIds
	local realCap = Catalog.V0Shipped.maxShippedTier
	Catalog.V0Shipped.deviceIds = deviceIds
	Catalog.V0Shipped.maxShippedTier = maxShippedTier
	local ok, err = pcall(fn)
	Catalog.V0Shipped.deviceIds = realDevices
	Catalog.V0Shipped.maxShippedTier = realCap
	if not ok then
		error(err, 0)
	end
end

-- ===== device purchases =====
test("The starter device is the cheap phone", function()
	local p = freshProfile()
	expectEqual(p.deviceId, "phone_cheap", "fresh profile starts on the cheap phone")
	expectEqual(Catalog.Devices[1].id, "phone_cheap", "cheap phone is catalog order 1")
	expectEqual(Catalog.Devices[1].price, 0, "cheap phone costs nothing")
end)

test("Fast phone purchase at exactly 50 succeeds", function()
	local p = freshProfile()
	p.balance = 50
	local next = expectOk(EconomyService.buyDevice(p, "phone_fast"), "buy fast phone at exactly 50")
	expectEqual(next.balance, 0, "balance debited by exactly the catalog price")
	expectEqual(next.deviceId, "phone_fast", "equipped device replaced")
	-- The input profile is never mutated in place.
	expectEqual(p.balance, 50, "input balance untouched")
	expectEqual(p.deviceId, "phone_cheap", "input device untouched")
end)

test("Insufficient funds at 49 is refused", function()
	local p = freshProfile()
	p.balance = 49
	expectCode(EconomyService.buyDevice(p, "phone_fast"), "INSUFFICIENT_FUNDS", "49 is one short")
	expectEqual(p.balance, 49, "input balance untouched on refusal")
end)

test("Duplicate device purchase is refused", function()
	local p = freshProfile()
	p.balance = 200
	p.deviceId = "phone_fast"
	expectCode(EconomyService.buyDevice(p, "phone_fast"), "ALREADY_DONE", "re-buying the equipped device")
end)

test("Device progression bypass is refused", function()
	-- The cheap phone cannot jump straight to the PC: exact-next only.
	local p = freshProfile()
	p.balance = 1000
	expectCode(EconomyService.buyDevice(p, "pc_rumah"), "NOT_READY", "cheap -> PC skips the fast phone")
end)

test("Unshipped PC purchase is refused in V0", function()
	-- pc_rumah exists in the catalog but is not in V0Shipped.deviceIds.
	local p = freshProfile()
	p.balance = 1000
	p.deviceId = "phone_fast"
	expectCode(EconomyService.buyDevice(p, "pc_rumah"), "NOT_READY", "PC is not shipped in V0")
end)

test("An unknown device is refused", function()
	local p = freshProfile()
	p.balance = 1000
	expectCode(EconomyService.buyDevice(p, "phone_ultra"), "UNKNOWN_DEVICE", "unknown device id")
	expectCode(EconomyService.buyDevice(p, ""), "INVALID_INPUT", "empty device id")
end)

test("Buying the fast phone raises the strong organic payout 15 -> 24", function()
	-- docs/04: fast phone yield 1.60, so floor(12 * 1.25 * 1.6) = 24.
	local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Rules"))
	local p = freshProfile()
	p.balance = 50
	local next = expectOk(EconomyService.buyDevice(p, "phone_fast"), "buy fast phone")
	local fastYield = 0
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).id == "phone_fast" then
			fastYield = (device :: any).deviceYield
		end
	end
	expectEqual(fastYield, 1.6, "fast phone yield is 1.60")
	expectEqual(Rules.organicCuan("strong", fastYield), 24, "strong organic payout becomes 24")
	expectEqual(Rules.organicCuan("weak", fastYield), 14, "weak organic payout becomes 14")
	expectEqual(next.balance, 0, "50 spent from exactly 50")
end)

test("The guided journey totals 110 and the phone leaves 60", function()
	-- docs/09 journey 2: organic 15 + campaign organic 15 + claim bonus 80 = 110;
	-- buying the fast phone for 50 leaves 60.
	local p = freshProfile()
	p.balance = 110
	local next = expectOk(EconomyService.buyDevice(p, "phone_fast"), "buy fast phone after the guided journey")
	expectEqual(next.balance, 60, "110 - 50 = 60")
end)

-- ===== M1 PC fixture =====
test("M1 PC fixture: yield 2.5 changes the strong payout 15 -> 37", function()
	local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Rules"))
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 0, function()
		local p = freshProfile()
		p.balance = 1000
		p.deviceId = "phone_fast"
		local next = expectOk(EconomyService.buyDevice(p, "pc_rumah"), "buy PC under the M1 fixture")
		expectEqual(next.deviceId, "pc_rumah", "PC equipped")
		expectEqual(next.balance, 780, "1000 - 220 = 780")
		local pcYield = 0
		for _, device in ipairs(Catalog.Devices) do
			if (device :: any).id == "pc_rumah" then
				pcYield = (device :: any).deviceYield
			end
		end
		expectEqual(pcYield, 2.5, "PC yield is 2.50")
		expectEqual(Rules.organicCuan("strong", pcYield), 37, "strong organic payout becomes 37")
		expectEqual(Rules.organicCuan("weak", pcYield), 22, "weak organic payout becomes 22")
	end)
end)

test("M1 PC fixture: device yields never stack", function()
	-- Buying the PC replaces the phone; only one yield applies.
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 0, function()
		local p = freshProfile()
		p.balance = 1000
		p.deviceId = "phone_fast"
		local next = expectOk(EconomyService.buyDevice(p, "pc_rumah"), "buy PC")
		expectEqual(next.deviceId, "pc_rumah", "the PC is the single productive device")
		expectEqual(EconomyService.incomePerSecond(next), 0, "no worker income without hires")
	end)
end)

-- ===== desk purchases (M1 fixtures) =====
-- A profile that satisfies every desk gate: PC owned, tier 1, funds.
local function pcTier1Profile(): any
	local p = freshProfile()
	p.balance = 5000
	p.deviceId = "pc_rumah"
	p.lifetimeEarned = 300
	p.completedMissions = 3
	return p
end

test("Desk 1 requires PC ownership", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = pcTier1Profile()
		p.deviceId = "phone_fast"
		expectCode(EconomyService.buyDesk(p, 1), "NOT_READY", "no PC means no desk")
	end)
end)

test("Desk 1 requires tier 1", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = pcTier1Profile()
		p.lifetimeEarned = 299
		expectCode(EconomyService.buyDesk(p, 1), "NOT_READY", "tier 0 cannot buy desk 1")
	end)
end)

test("Desk 1 at exactly 180 succeeds and 179 is refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local exact = pcTier1Profile()
		exact.balance = 180
		local next = expectOk(EconomyService.buyDesk(exact, 1), "buy desk 1 at exactly 180")
		expectEqual(next.balance, 0, "180 debited")
		expectEqual(#next.ownedDesks, 1, "one desk owned")
		expectEqual(next.ownedDesks[1], 1, "slot 1 owned")

		local short = pcTier1Profile()
		short.balance = 179
		expectCode(EconomyService.buyDesk(short, 1), "INSUFFICIENT_FUNDS", "179 is one short")
	end)
end)

test("Desk slots must progress sequentially", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 2, function()
		local p = pcTier1Profile()
		p.lifetimeEarned = 1600
		expectCode(EconomyService.buyDesk(p, 2), "NOT_READY", "desk 2 before desk 1")
		local first = expectOk(EconomyService.buyDesk(p, 1), "buy desk 1 first")
		expectEqual(#first.ownedDesks, 1, "one desk after the first purchase")
	end)
end)

test("Desk 2 at exactly 250 succeeds", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 2, function()
		local p = pcTier1Profile()
		p.lifetimeEarned = 1600
		p.balance = 430
		local first = expectOk(EconomyService.buyDesk(p, 1), "buy desk 1")
		expectEqual(first.balance, 250, "180 spent, 250 left")
		local second = expectOk(EconomyService.buyDesk(first, 2), "buy desk 2 at exactly 250")
		expectEqual(second.balance, 0, "250 debited")
		expectEqual(#second.ownedDesks, 2, "two desks owned")
		expectEqual(second.ownedDesks[2], 2, "slot 2 owned")
	end)
end)

test("A duplicate desk purchase is refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = pcTier1Profile()
		local first = expectOk(EconomyService.buyDesk(p, 1), "buy desk 1")
		expectCode(EconomyService.buyDesk(first, 1), "ALREADY_DONE", "desk 1 already owned")
	end)
end)

test("Desk slot indices outside 1..2 are refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 2, function()
		local p = pcTier1Profile()
		expectCode(EconomyService.buyDesk(p, 0), "INVALID_INPUT", "slot 0")
		expectCode(EconomyService.buyDesk(p, 3), "INVALID_INPUT", "slot 3")
	end)
end)

-- ===== worker hires (M1 fixtures) =====
local function desk1Tier1Profile(): any
	local p = pcTier1Profile()
	p.balance = 5000
	table.insert(p.ownedDesks, 1)
	return p
end

test("Hiring requires the corresponding desk", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = pcTier1Profile()
		expectCode(EconomyService.hireWorker(p, 1, "trainee"), "NOT_READY", "no desk means no hire")
	end)
end)

test("Hiring requires PC ownership", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = desk1Tier1Profile()
		p.deviceId = "phone_fast"
		expectCode(EconomyService.hireWorker(p, 1, "trainee"), "NOT_READY", "no PC means no hire")
	end)
end)

test("Trainee 1 at exactly 500 succeeds and 499 is refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local exact = desk1Tier1Profile()
		exact.balance = 500
		local next = expectOk(EconomyService.hireWorker(exact, 1, "trainee"), "hire trainee 1 at exactly 500")
		expectEqual(next.balance, 0, "500 debited")
		expectEqual(#next.workers, 1, "one worker")
		expectEqual(next.workers[1].slotIndex, 1, "worker in slot 1")
		expectEqual(next.workers[1].roleId, "trainee", "role is trainee")
		expectEqual(next.workers[1].hireId, "trainee-slot-1", "server-owned hire id")

		local short = desk1Tier1Profile()
		short.balance = 499
		expectCode(EconomyService.hireWorker(short, 1, "trainee"), "INSUFFICIENT_FUNDS", "499 is one short")
	end)
end)

test("A duplicate worker in the same slot is refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = desk1Tier1Profile()
		local first = expectOk(EconomyService.hireWorker(p, 1, "trainee"), "hire trainee 1")
		expectCode(EconomyService.hireWorker(first, 1, "trainee"), "ALREADY_DONE", "slot 1 already occupied")
	end)
end)

test("Worker slots must progress sequentially and cap at two", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 2, function()
		local p = desk1Tier1Profile()
		p.lifetimeEarned = 1600
		table.insert(p.ownedDesks, 2)
		-- Slot 2 before slot 1 is refused.
		expectCode(EconomyService.hireWorker(p, 2, "trainee"), "NOT_READY", "slot 2 before slot 1")
		local first = expectOk(EconomyService.hireWorker(p, 1, "trainee"), "hire slot 1")
		local second = expectOk(EconomyService.hireWorker(first, 2, "trainee"), "hire slot 2")
		expectEqual(#second.workers, 2, "two workers")
		expectEqual(second.workers[1].slotIndex, 1, "slot 1 first")
		expectEqual(second.workers[2].slotIndex, 2, "slot 2 second")
	end)
end)

test("A non-trainee role is refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = desk1Tier1Profile()
		expectCode(EconomyService.hireWorker(p, 1, "manager"), "INVALID_INPUT", "only the trainee role exists")
	end)
end)

test("Worker slot indices outside 1..2 are refused", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 2, function()
		local p = desk1Tier1Profile()
		expectCode(EconomyService.hireWorker(p, 0, "trainee"), "INVALID_INPUT", "slot 0")
		expectCode(EconomyService.hireWorker(p, 3, "trainee"), "INVALID_INPUT", "slot 3")
	end)
end)

-- ===== worker income =====
test("Zero workers accrue nothing", function()
	local p = freshProfile()
	local next = expectOk(EconomyService.tick(p, 30), "tick with no workers")
	expectEqual(next.balance, 0, "no credit without workers")
	expectEqual(next.fractionalIncome, 0, "no residual without workers")
	expectEqual(EconomyService.incomePerSecond(p), 0, "rate is zero")
end)

test("One worker for 30 seconds banks exactly 45", function()
	-- docs/04: 1.5 Cuan/s, floor(0 + 1.5 * 30) = 45.
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	local next = expectOk(EconomyService.tick(p, 30), "one worker, 30 seconds")
	expectEqual(next.balance, 45, "45 banked")
	expectEqual(next.lifetimeEarned, 45, "lifetime includes banked worker income")
	expectEqual(next.fractionalIncome, 0, "no residual at a whole second boundary")
	expectEqual(EconomyService.incomePerSecond(p), 1.5, "rate is 1.5 Cuan/s")
end)

test("Two workers for 30 seconds bank exactly 90", function()
	-- docs/04: 3.0 Cuan/s, floor(0 + 3 * 30) = 90.
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	table.insert(p.workers, { hireId = "trainee-slot-2", roleId = "trainee", slotIndex = 2 })
	local next = expectOk(EconomyService.tick(p, 30), "two workers, 30 seconds")
	expectEqual(next.balance, 90, "90 banked")
	expectEqual(EconomyService.incomePerSecond(p), 3, "rate is 3 Cuan/s")
end)

test("Fractional carry is preserved across ticks", function()
	-- 1.5 Cuan/s: one second accrues 1.5, so floor credits 1 and 0.5 carries.
	-- The next second makes 2.0, crediting another 1 with no residual.
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	local one = expectOk(EconomyService.tick(p, 1), "one second")
	expectEqual(one.balance, 1, "1 Cuan credited from 1.5")
	expectTrue(math.abs(one.fractionalIncome - 0.5) < 1e-9, "0.5 carried")
	local two = expectOk(EconomyService.tick(one, 1), "second second")
	-- 0.5 carried + 1.5 accrued = 2.0, so floor credits 2 more.
	expectEqual(two.balance, 3, "2 more Cuan credited from the carried residual")
	expectTrue(math.abs(two.fractionalIncome - 0) < 1e-9, "residual consumed")
end)

test("A 75-second connected interval processes 60 + 15 without loss", function()
	-- docs/03: bounded dt<=60 chunks, remainder retained, nothing dropped.
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	local chunks, remaining = EconomyService.chunkConnectedTime(75)
	expectEqual(#chunks, 2, "75 seconds splits into two chunks")
	expectEqual(chunks[1], 60, "first chunk is the 60-second bound")
	expectEqual(chunks[2], 15, "second chunk is the remainder")
	expectEqual(remaining, 0, "no remainder is dropped")
	local total = 0
	local current = p
	for _, chunk in ipairs(chunks) do
		current = expectOk(EconomyService.tick(current, chunk), `chunk {chunk}`)
	end
	expectEqual(current.balance, 112, "floor(1.5 * 75) = 112")
	expectTrue(math.abs(current.fractionalIncome - 0.5) < 1e-9, "0.5 residual carried")
end)

test("Chunking an exact multiple of 60 leaves no remainder", function()
	local chunks, remaining = EconomyService.chunkConnectedTime(120)
	expectEqual(#chunks, 2, "120 seconds is two full chunks")
	expectEqual(remaining, 0, "no remainder")
end)

test("Chunking zero and sub-chunk intervals", function()
	local zeroChunks, zeroRemaining = EconomyService.chunkConnectedTime(0)
	expectEqual(#zeroChunks, 0, "zero seconds produces no chunks")
	expectEqual(zeroRemaining, 0, "zero remainder")
	local smallChunks, smallRemaining = EconomyService.chunkConnectedTime(15)
	expectEqual(#smallChunks, 1, "15 seconds is one chunk")
	expectEqual(smallChunks[1], 15, "the chunk is the whole interval")
	expectEqual(smallRemaining, 0, "no remainder")
end)

test("Negative, NaN and infinite connected time are refused", function()
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	expectCode(EconomyService.tick(p, -1), "INVALID_INPUT", "negative seconds")
	expectCode(EconomyService.tick(p, 0 / 0), "INVALID_INPUT", "NaN seconds")
	expectCode(EconomyService.tick(p, math.huge), "INVALID_INPUT", "+inf seconds")
	expectCode(EconomyService.tick(p, -math.huge), "INVALID_INPUT", "-inf seconds")
end)

test("Worker accrual past the economy limit is refused, not clamped", function()
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	p.balance = EconomyService.MAX_ECONOMIC_TOTAL - 10
	p.lifetimeEarned = EconomyService.MAX_ECONOMIC_TOTAL - 10
	expectCode(EconomyService.tick(p, 30), "LIMIT_REACHED", "accrual would reach 1e12")
	expectEqual(p.balance, EconomyService.MAX_ECONOMIC_TOTAL - 10, "input balance untouched")
end)

test("Worker accrual just below the limit succeeds", function()
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	p.balance = EconomyService.MAX_ECONOMIC_TOTAL - 1000
	p.lifetimeEarned = EconomyService.MAX_ECONOMIC_TOTAL - 1000
	local next = expectOk(EconomyService.tick(p, 30), "accrual below the limit")
	expectEqual(next.balance, EconomyService.MAX_ECONOMIC_TOTAL - 955, "45 credited below the bound")
end)

test("No offline earnings: accrual is driven only by injected connected time", function()
	-- The module reads no clock. A profile with workers and zero injected
	-- connected time earns nothing, so a rejoin cannot fabricate income.
	local p = freshProfile()
	table.insert(p.workers, { hireId = "trainee-slot-1", roleId = "trainee", slotIndex = 1 })
	local next = expectOk(EconomyService.tick(p, 0), "zero connected seconds")
	expectEqual(next.balance, 0, "no credit for zero connected time")
	expectEqual(EconomyService.incomePerSecond(next), 1.5, "rate is reported but not credited")
end)

test("Spending reduces the wallet but never lifetime earned", function()
	withCatalogFixture({ "phone_cheap", "phone_fast", "pc_rumah" }, 1, function()
		local p = pcTier1Profile()
		p.balance = 500
		p.lifetimeEarned = 400
		local next = expectOk(EconomyService.buyDesk(p, 1), "buy desk 1")
		expectEqual(next.balance, 320, "wallet reduced by the price")
		expectEqual(next.lifetimeEarned, 400, "lifetime unchanged by spending")
	end)
end)

test("A malformed profile is refused rather than repaired", function()
	expectCode(EconomyService.buyDevice(nil, "phone_fast"), "INVALID_INPUT", "nil profile")
	expectCode(EconomyService.buyDevice({}, "phone_fast"), "INVALID_INPUT", "empty profile")
	local bad = freshProfile()
	bad.balance = -5
	expectCode(EconomyService.buyDevice(bad, "phone_fast"), "INVALID_INPUT", "negative balance")
	local frac = freshProfile()
	frac.balance = 10.5
	expectCode(EconomyService.buyDevice(frac, "phone_fast"), "INVALID_INPUT", "fractional balance")
	local nan = freshProfile()
	nan.balance = 0 / 0
	expectCode(EconomyService.buyDevice(nan, "phone_fast"), "INVALID_INPUT", "NaN balance")
end)

test("The fixture restores the exact original shipped values", function()
	local realDevices = Catalog.V0Shipped.deviceIds
	local realCap = Catalog.V0Shipped.maxShippedTier
	pcall(function()
		withCatalogFixture({ "phone_cheap" }, 5, function()
			error("intentional fixture failure", 0)
		end)
	end)
	expectEqual(Catalog.V0Shipped.deviceIds == realDevices, true, "device list reference restored")
	expectEqual(Catalog.V0Shipped.maxShippedTier, realCap, "tier cap value restored")
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
print(`EconomyService spec: {passed}/{passed + failed} passed, {failed} failed`)
if failed > 0 then
	error("EconomyService spec failed", 0)
end
return `EconomyService: {passed}/{passed + failed} passed`
