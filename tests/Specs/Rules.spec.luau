--!strict
-- Buzzer Simulator — Rules spec (BS-01). Executed by tests/Runner.server.luau
-- in the test project only. Numeric source: docs/04, formulas docs/02, contract 03.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage.Shared.Catalog)
local GameTypes = require(ReplicatedStorage.Shared.GameTypes)
local Rules = require(ReplicatedStorage.Shared.Rules)

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`, 0)
	end
end

local function expectError(fn: () -> (), _label: string)
	local ok, err = pcall(fn :: any)
	if ok then
		error("expected error, got success", 0)
	end
	if type(err) ~= "string" or #err == 0 then
		error("expected string error message", 0)
	end
end

local tests: { { name: string, fn: () -> () } } = {}

local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

-- ===== Catalog invariants (BS-01 acceptance) =====

test("Catalog validates structurally", function()
	local ok, problems = Catalog.validate()
	if not ok then
		error("Catalog.validate failed: " .. table.concat(problems, "; "), 0)
	end
end)

test("Catalog V0 content: mission, context, templates", function()
	local mission = Catalog.Missions[1]
	expectEqual(mission.missionId, "food_stall_launch", "food mission id")
	expectEqual(mission.requiredImpact, 100, "impact")
	expectEqual(mission.reward, 80, "bonus")
	expectEqual(mission.contexts[1], "meal_time", "first context")
	local hasMealMeme = false
	for _, t in ipairs(mission.templates) do
		if t == "meal_meme" then hasMealMeme = true end
	end
	expectEqual(hasMealMeme, true, "meal_meme present")
	expectEqual(#mission.templates, 3, "mission template count")

	local ctx = Catalog.OrganicContexts[1]
	expectEqual(ctx.contextId, "organic_snack", "organic context id")
	local hasSnackMeme = false
	for _, t in ipairs(ctx.templates) do
		if t == "snack_meme" then hasSnackMeme = true end
	end
	expectEqual(hasSnackMeme, true, "snack_meme present")
	expectEqual(#ctx.templates, 3, "organic template count")
end)

test("Catalog devices: order, yield, reveal, price", function()
	local cheap, fast, pc = Catalog.Devices[1], Catalog.Devices[2], Catalog.Devices[3]
	expectEqual(cheap.id, "phone_cheap", "cheap id")
	expectEqual(cheap.deviceYield, 1, "cheap yield")
	expectEqual(cheap.revealSeconds, 18, "cheap reveal")
	expectEqual(cheap.price, 0, "cheap price")
	expectEqual(fast.id, "phone_fast", "fast id")
	expectEqual(fast.deviceYield, 1.6, "fast yield")
	expectEqual(fast.revealSeconds, 16, "fast reveal")
	expectEqual(fast.price, 50, "fast price")
	expectEqual(pc.id, "pc_rumah", "pc id")
	expectEqual(pc.deviceYield, 2.5, "pc yield")
	expectEqual(pc.revealSeconds, 13, "pc reveal")
	expectEqual(pc.price, 220, "pc price")
	-- exact-next purchase order: cheap -> fast -> pc
	expectEqual(cheap.order, 1, "cheap order")
	expectEqual(fast.order, 2, "fast order")
	expectEqual(pc.order, 3, "pc order")
end)

test("Catalog tiers: planned thresholds 300/3 and 1600/3; V0 cap tier 0", function()
	expectEqual(#Catalog.Tiers, 3, "tier count")
	local t1, t2 = Catalog.Tiers[2], Catalog.Tiers[3]
	expectEqual(t1.lifetimeRequired, 300, "tier1 lifetime")
	expectEqual(t1.claimsRequired, 3, "tier1 claims")
	expectEqual(t2.lifetimeRequired, 1600, "tier2 lifetime")
	expectEqual(t2.claimsRequired, 3, "tier2 claims")
	expectEqual(Catalog.V0Shipped.maxShippedTier, 0, "V0 shipped cap")
end)

test("Catalog carries no affinity tags / answer keys", function()
	-- Public catalog must not contain trend/audience affinity tagging data.
	for _, device in ipairs(Catalog.Devices) do
		for key in pairs(device) do
			if key:lower():find("affinity") or key:lower():find("strongtemplate") then
				error("public device carries forbidden affinity key: " .. tostring(key), 0)
			end
		end
	end
	for _, mission in ipairs(Catalog.Missions) do
		for key in pairs(mission) do
			if key:lower():find("affinity") or key:lower():find("strongtemplate") then
				error("public mission carries forbidden affinity key: " .. tostring(key), 0)
			end
		end
	end
	for _, ctx in ipairs(Catalog.OrganicContexts) do
		for key in pairs(ctx) do
			if key:lower():find("affinity") or key:lower():find("strongtemplate") then
				error("public context carries forbidden affinity key: " .. tostring(key), 0)
			end
		end
	end
end)

-- ===== Rules.postImpact (docs/04 exact values) =====

test("postImpact strong/weak at B=100 yield=1: 120 / 75", function()
	expectEqual(Rules.postImpact(100, "strong", 1), 120, "strong impact")
	expectEqual(Rules.postImpact(100, "weak", 1), 75, "weak impact")
end)

test("postImpact weak at PC yield 2.5 is 94 and remains < 100", function()
	local weakPc = Rules.postImpact(100, "weak", 2.5)
	expectEqual(weakPc, 94, "weak impact at yield 2.5")
	if weakPc >= 100 then
		error("weak PC impact must stay below B=100", 0)
	end
end)

test("two weak starter posts always reach required impact 100", function()
	local first = Rules.postImpact(100, "weak", 1)
	local second = Rules.postImpact(100, "weak", 1)
	if first + second < 100 then
		error(`two weak starter posts {first}+{second} < 100`, 0)
	end
end)

test("postImpact strong food post reaches requiredImpact 100", function()
	if Rules.postImpact(100, "strong", 1) < 100 then
		error("strong starter post must clear B=100", 0)
	end
end)

test("postImpact floors and stays integral for fractional yields", function()
	expectEqual(Rules.postImpact(100, "strong", 1.6), 192, "strong fast phone: floor(100*1.2*1.6)")
	expectEqual(Rules.postImpact(130, "strong", 2.5), 390, "strong PC on gadget: floor(130*1.2*2.5)")
	expectEqual(Rules.postImpact(100, "weak", 1.6), 114, "weak fast: floor(100*.75*1.6)")
end)

test("postImpact rejects nonfinite/negative/garbage input", function()
	expectError(function() Rules.postImpact(100, "strong", 0) end, "zero yield")
	expectError(function() Rules.postImpact(100, "strong", -1) end, "negative yield")
	expectError(function() Rules.postImpact(100, "strong", math.huge) end, "infinite yield")
	expectError(function() Rules.postImpact(100, "strong", 0 / 0) end, "NaN yield")
	expectError(function() Rules.postImpact(0, "strong", 1) end, "B=0")
	expectError(function() Rules.postImpact(-5, "strong", 1) end, "negative B")
	expectError(function() Rules.postImpact(100.5, "strong", 1) end, "fractional B")
	expectError(function() Rules.postImpact(100, "best" :: any, 1) end, "invalid fit")
	expectError(function() Rules.postImpact(math.huge, "strong", 1) end, "infinite B")
end)

-- ===== Rules.organicCuan (docs/04 exact values) =====

test("organicCuan cheap 15/9, fast 24/14, PC 37/22", function()
	expectEqual(Rules.organicCuan("strong", 1), 15, "cheap strong")
	expectEqual(Rules.organicCuan("weak", 1), 9, "cheap weak")
	expectEqual(Rules.organicCuan("strong", 1.6), 24, "fast strong: floor(12*1.25*1.6)")
	expectEqual(Rules.organicCuan("weak", 1.6), 14, "fast weak: floor(12*.75*1.6)")
	expectEqual(Rules.organicCuan("strong", 2.5), 37, "PC strong: floor(12*1.25*2.5)")
	expectEqual(Rules.organicCuan("weak", 2.5), 22, "PC weak: floor(12*.75*2.5)")
end)

test("organicCuan rejects invalid input", function()
	expectError(function() Rules.organicCuan("strong", 0) end, "zero yield")
	expectError(function() Rules.organicCuan("strong", -2) end, "negative yield")
	expectError(function() Rules.organicCuan("strong", 0 / 0) end, "NaN yield")
	expectError(function() Rules.organicCuan("meh" :: any, 1) end, "invalid fit")
	expectError(function() Rules.organicCuan("strong", math.huge) end, "infinite yield")
end)

-- ===== Rules.eligibleTier =====

test("eligibleTier: tier0 start, both thresholds, max shipped clamp", function()
	expectEqual(Rules.eligibleTier(0, 0, 0), 0, "fresh profile")
	expectEqual(Rules.eligibleTier(299, 99, 2), 0, "below tier1 need")
	expectEqual(Rules.eligibleTier(300, 3, 2), 1, "exact tier1")
	expectEqual(Rules.eligibleTier(1600, 2, 2), 0, "lifetime alone cannot skip claims")
	expectEqual(Rules.eligibleTier(1600, 6, 2), 2, "exact tier2")
	expectEqual(Rules.eligibleTier(5000, 50, 0), 0, "clamped to V0 shipped cap")
	expectEqual(Rules.eligibleTier(1600, 3, 1), 1, "clamp to maxShippedTier=1")
end)

test("eligibleTier rejects invalid input", function()
	expectError(function() Rules.eligibleTier(-1, 0, 2) end, "negative lifetime")
	expectError(function() Rules.eligibleTier(0, -1, 2) end, "negative claims")
	expectError(function() Rules.eligibleTier(0, 0, -2) end, "negative cap")
	expectError(function() Rules.eligibleTier(0 / 0, 0, 2) end, "NaN lifetime")
	expectError(function() Rules.eligibleTier(0.5, 0, 2) end, "fractional lifetime")
end)

-- ===== GameTypes contract surface (03) — shape review, no transport =====

test("GameTypes union shapes exist as documented type surface", function()
	-- Type-only module: presence of exported fields reviewed via require;
	-- runtime check is that the module loads and returns nil w/o remotes.
	expectEqual(GameTypes, nil, "GameTypes returns no runtime value (types only)")
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
print(`Rules spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print(`FAILURES:`)
	for _, f in ipairs(failures) do
		print(`  - {f}`)
	end
	print("BS01_RULES_TESTS_FAILED")
	error(`Rules spec: {#failures} failed (see FAILURES above)`, 0)
end
print("BS01_RULES_TESTS_PASSED")
return `Rules: {passed}/{#tests} passed`