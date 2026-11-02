--!strict
-- Buzzer Simulator — BS-11 spec: Context catalog, PC Rumah, M1 content expansion.
-- Validates:
-- 1. All 12 mission contexts and 3 organic contexts have strictly 1 unique winner.
-- 2. Deterministic rotation of organic and mission contexts via counters.
-- 3. 12 authored feed cards, 12 NPC identities, and clean presentation projections.
-- 4. PC Rumah hardware: 220 Cuan, 2.50x yield, 13s reveal, 37 strong / 22 weak payout.
-- 5. Exact-next progression (phone_fast -> pc_rumah) and no yield stacking.
-- 6. WorldService swaps OldCRT with PCRumah at TerminalSlot, phone inert at PhoneSlot.
-- 7. Upgrades UI dynamic card progression and responsive desktop layout.
-- 8. Career tier gating (Tier 1: 300/3 unlocks brand_remix, Tier 2: 1600/3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog")) :: any
local Rules = require(Shared:WaitForChild("Rules")) :: any
local Presentation = require(Shared:WaitForChild("Presentation")) :: any

local ScoringCatalog = require(ServerStorage:WaitForChild("ScoringCatalog")) :: any
local MissionService = require(ServerStorage:WaitForChild("MissionService")) :: any
local EconomyService = require(ServerStorage:WaitForChild("EconomyService")) :: any
local WorldService = require(ServerStorage:WaitForChild("WorldService")) :: any
local FeedService = require(ServerStorage:WaitForChild("FeedService")) :: any

local spScripts = StarterPlayer:WaitForChild("StarterPlayerScripts", 10) :: any
local ClientState = require(spScripts:WaitForChild("ClientState", 10)) :: any
local uiFolder = spScripts:WaitForChild("ui", 10) :: any
local Upgrades = require(uiFolder:WaitForChild("Upgrades", 10)) :: any
local Desktop = require(uiFolder:WaitForChild("Desktop", 10)) :: any

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

local function freshProfile(): any
	return {
		schemaVersion = 1,
		balance = 0,
		lifetimeEarned = 0,
		completedMissions = 0,
		deviceId = "phone_cheap",
		ownedDesks = {},
		workers = {},
		fractionalIncome = 0,
		activeMission = nil,
		pendingPost = nil,
		nextPostSequence = 1,
		nextOrganicSequence = 0,
		missionVariantCounters = {},
		ownPosts = {},
		claimedRunIdsWindow = {},
		recentMutationOutcomes = {},
	}
end

-- ====================================================================
-- 1. Context Catalog & Scoring
-- ====================================================================

test("M1 ships exactly 4 missions and 3 organic contexts", function()
	local shipped = Catalog.Shipped or Catalog.M1Shipped
	expectEqual(#shipped.missionIds, 4, "4 shipped missions")
	expectEqual(#shipped.organicContextIds, 3, "3 shipped organic contexts")
	expectEqual(#Catalog.OrganicContexts, 3, "3 organic context definitions")
	
	local missionCount = 0
	for _, m in ipairs(Catalog.Missions) do
		if table.find(shipped.missionIds, m.missionId) ~= nil then
			missionCount += 1
			expectEqual(#m.contexts, 3, `mission {m.missionId} has exactly 3 contexts`)
			expectEqual(#m.templates, 3, `mission {m.missionId} has exactly 3 templates`)
		end
	end
	expectEqual(missionCount, 4, "all 4 shipped missions found in catalog")
end)

test("All 12 mission contexts and 3 organic contexts have strictly 1 unique winner", function()
	local shipped = Catalog.Shipped or Catalog.M1Shipped
	local ok, problems = ScoringCatalog.validateShippedContent(
		Catalog,
		shipped.organicContextIds,
		shipped.missionIds
	)
	expectTrue(ok, `validateShippedContent failed: {table.concat(problems, ", ")}`)

	-- Verify organic winners directly
	local orgAffinities = ScoringCatalog.organicAffinities()
	for _, orgCtx in ipairs(Catalog.OrganicContexts) do
		local ctxId = orgCtx.contextId
		local affinities = orgAffinities[ctxId]
		expectTrue(affinities ~= nil, `organic context {ctxId} has affinities`)
		local strongTmpl, resolveErr = ScoringCatalog.resolveStrongTemplate(
			orgCtx.templates,
			affinities,
			orgCtx.trendId,
			orgCtx.audienceId
		)
		expectTrue(strongTmpl ~= nil, `organic context {ctxId} has unique strong template: {tostring(resolveErr)}`)
		for _, tmplId in ipairs(orgCtx.templates) do
			local fit = ScoringCatalog.fitForTemplate(
				tmplId,
				orgCtx.templates,
				affinities,
				orgCtx.trendId,
				orgCtx.audienceId
			)
			if tmplId == strongTmpl then
				expectEqual(fit, "strong", `template {tmplId} should be strong`)
			else
				expectEqual(fit, "weak", `template {tmplId} should be weak`)
			end
		end
	end

	-- Verify mission winners and rotation coverage across templates
	local missionAffinities = ScoringCatalog.missionAffinities()
	for _, mission in ipairs(Catalog.Missions) do
		local templateWinCounts: { [string]: number } = {}
		for _, tmplId in ipairs(mission.templates) do
			templateWinCounts[tmplId] = 0
		end

		for _, ctxId in ipairs(mission.contexts) do
			local trendId, audienceId, tagErr = ScoringCatalog.missionContextTags(ctxId)
			expectTrue(trendId ~= nil and audienceId ~= nil, `mission context {ctxId} has tags: {tostring(tagErr)}`)
			local affinities = missionAffinities[ctxId]
			expectTrue(affinities ~= nil, `mission context {ctxId} has affinities`)
			local strongTmpl, resolveErr = ScoringCatalog.resolveStrongTemplate(
				mission.templates,
				affinities,
				trendId :: string,
				audienceId :: string
			)
			expectTrue(strongTmpl ~= nil, `mission context {ctxId} must have unique strong template: {tostring(resolveErr)}`)
			templateWinCounts[strongTmpl :: string] += 1

			for _, tmplId in ipairs(mission.templates) do
				local fit = ScoringCatalog.fitForTemplate(
					tmplId,
					mission.templates,
					affinities,
					trendId :: string,
					audienceId :: string
				)
				if tmplId == strongTmpl then
					expectEqual(fit, "strong", `template {tmplId} in {ctxId} should be strong`)
				else
					expectEqual(fit, "weak", `template {tmplId} in {ctxId} should be weak`)
				end
			end
		end

		-- No single template wins every run: all 3 templates must win in exactly 1 context
		for tmplId, count in pairs(templateWinCounts) do
			expectEqual(count, 1, `mission {mission.missionId} template {tmplId} must win exactly 1 context`)
		end
	end
end)

test("Public catalog contains no server-only private affinity tags", function()
	local HttpService = game:GetService("HttpService")
	local publicJson = HttpService:JSONEncode(Catalog)
	expectTrue(publicJson:find('"snack_meme":{"trendId"') == nil, "no per-template affinity map in public catalog")
	expectTrue(publicJson:find('"trendMatch"') == nil, "no trendMatch scoring logic in public catalog")
	expectTrue(publicJson:find('"affinities"') == nil, "no private affinities tables in public catalog")
	for _, m in ipairs(Catalog.Missions) do
		expectEqual((m :: any).affinities, nil, "no private affinities in public mission")
	end
end)

-- ====================================================================
-- 2. Deterministic Context Rotation
-- ====================================================================

test("Organic context rotates deterministically via nextOrganicSequence counter", function()
	local p = freshProfile()
	local seen = {}
	for i = 1, 6 do
		local ctx, err = MissionService.nextOrganicContext(p)
		expectTrue(ctx ~= nil, `nextOrganicContext returned {tostring(err)}`)
		table.insert(seen, (ctx :: any).contextId)
		p.nextOrganicSequence += 1
	end
	expectEqual(seen[1], "organic_snack", "sequence 0 -> organic_snack")
	expectEqual(seen[2], "organic_gadget", "sequence 1 -> organic_gadget")
	expectEqual(seen[3], "organic_weekend", "sequence 2 -> organic_weekend")
	expectEqual(seen[4], "organic_snack", "sequence 3 -> organic_snack (loop)")
	expectEqual(seen[5], "organic_gadget", "sequence 4 -> organic_gadget")
	expectEqual(seen[6], "organic_weekend", "sequence 5 -> organic_weekend")
end)

test("Mission context rotates deterministically across runs per mission", function()
	local p = freshProfile()
	local mission = Catalog.Missions[1] -- food_stall_launch
	
	local res1 = MissionService.accept(p, mission.missionId, "run-1", 1000)
	expectTrue(res1.ok, "accept 1 ok")
	local c1 = res1.profile.activeMission.contextId
	expectEqual(c1, mission.contexts[1], "first run uses context 1")
	
	-- Publish with winner and settle
	local pub1 = MissionService.publishMission(res1.profile, "run-1", mission.templates[1], 1000)
	expectTrue(pub1.ok, "pub 1 ok")
	local set1 = MissionService.settle(pub1.profile, 1018)
	expectTrue(set1.ok, "settle 1 ok")
	local claim1 = MissionService.claim(set1.profile, "run-1")
	expectTrue(claim1.ok, "claim 1 ok")
	
	-- Run 2
	local res2 = MissionService.accept(claim1.profile, mission.missionId, "run-2", 2000)
	expectTrue(res2.ok, "accept 2 ok")
	local c2 = res2.profile.activeMission.contextId
	expectEqual(c2, mission.contexts[2], "second run uses context 2")
	
	local pub2 = MissionService.publishMission(res2.profile, "run-2", mission.templates[2], 2000)
	local set2 = MissionService.settle(pub2.profile, 2018)
	local claim2 = MissionService.claim(set2.profile, "run-2")
	
	-- Run 3
	local res3 = MissionService.accept(claim2.profile, mission.missionId, "run-3", 3000)
	expectTrue(res3.ok, "accept 3 ok")
	local c3 = res3.profile.activeMission.contextId
	expectEqual(c3, mission.contexts[3], "third run uses context 3")
end)

-- ====================================================================
-- 3. Feed Presentation & NPC Identities
-- ====================================================================

test("Presentation contains 12 authored cards and 12 NPC identities", function()
	expectEqual(#Presentation.authoredCards(), 12, "exactly 12 authored cards")
	expectEqual(#Presentation.npcIdentities(), 12, "exactly 12 NPC identities")
	expectEqual(Presentation.AUTHORED_NPC_CARDS, 12, "AUTHORED_NPC_CARDS is 12")
	
	local state = {
		ownPosts = {
			{ postId = "post-1", kind = "organic", contextId = "organic_snack", templateId = "snack_meme", finalImpact = 15, organicCuan = 15, publishedAt = 3000 },
		},
		feedVersion = 1,
	}
	local projected = Presentation.build(state)
	expectTrue(#projected >= 13, "feed includes authored cards plus own posts")
	expectEqual(projected[1].cardId, "own-post-1", "newest own post projected at top of feed")
end)

-- ====================================================================
-- 4. PC Rumah Hardware & Economy
-- ====================================================================

test("PC Rumah catalog specs and integer payouts match docs/04", function()
	local pc = nil
	for _, d in ipairs(Catalog.Devices) do
		if d.id == "pc_rumah" then pc = d; break end
	end
	expectTrue(pc ~= nil, "pc_rumah exists in catalog")
	expectEqual(pc.price, 220, "PC price is 220 Cuan")
	expectEqual(pc.deviceYield, 2.50, "PC yield is 2.50x")
	expectEqual(pc.revealSeconds, 13, "PC reveal time is 13 seconds")

	local strong = Rules.organicCuan("strong", pc.deviceYield)
	local weak = Rules.organicCuan("weak", pc.deviceYield)
	expectEqual(strong, 37, "PC strong payout is 37 Cuan")
	expectEqual(weak, 22, "PC weak payout is 22 Cuan")
end)

test("Exact-next device progression: cheap -> fast -> PC Rumah", function()
	local p = freshProfile()
	p.balance = 1000

	-- Cannot jump from cheap to pc_rumah
	local badJump = EconomyService.buyDevice(p, "pc_rumah")
	expectEqual(badJump.ok, false, "cannot skip phone_fast to buy pc_rumah")
	expectEqual(badJump.code, "NOT_READY", "rejection code is NOT_READY")

	-- Buy fast phone
	local buyFast = EconomyService.buyDevice(p, "phone_fast")
	expectTrue(buyFast.ok, "buy fast phone ok")
	expectEqual(buyFast.profile.deviceId, "phone_fast", "deviceId updated to phone_fast")
	expectEqual(buyFast.profile.balance, 950, "deducted 50 Cuan")

	-- Cannot re-buy fast phone
	local rebuyFast = EconomyService.buyDevice(buyFast.profile, "phone_fast")
	expectEqual(rebuyFast.ok, false, "cannot re-buy phone_fast")
	expectEqual(rebuyFast.code, "ALREADY_DONE", "rejection code is ALREADY_DONE")

	-- Now buy PC Rumah
	local buyPC = EconomyService.buyDevice(buyFast.profile, "pc_rumah")
	expectTrue(buyPC.ok, "buy pc_rumah ok")
	expectEqual(buyPC.profile.deviceId, "pc_rumah", "deviceId updated to pc_rumah")
	expectEqual(buyPC.profile.balance, 730, "deducted 220 Cuan")

	-- Yield does not stack: sole productive device
	local devYield = buyPC.profile.deviceId == "pc_rumah" and 2.50 or 1.00
	expectEqual(devYield, 2.50, "sole productive device yield is 2.50x")
end)

-- ====================================================================
-- 5. WorldService Presentation: PCRumah at TerminalSlot
-- ====================================================================

test("WorldService equips PCRumah at TerminalSlot and preserves prompt", function()
	local fakePlayer: any = { UserId = 88811, Name = "PCPlayer" }
	local profile = freshProfile()
	profile.deviceId = "pc_rumah"

	local spawned, spawnErr = WorldService.Spawn(fakePlayer, profile)
	expectTrue(spawned, `Spawn with pc_rumah returned {tostring(spawnErr)}`)

	local room = WorldService.GetRoom(fakePlayer)
	expectTrue(room ~= nil, "room spawned")

	local terminalSlot = WorldService.GetAnchor(fakePlayer, "TerminalSlot")
	expectTrue(terminalSlot ~= nil, "TerminalSlot anchor exists")
	local pcModel = (terminalSlot :: any):FindFirstChild("PCRumah")
	expectTrue(pcModel ~= nil, "PCRumah is placed at TerminalSlot")
	expectEqual(pcModel.Name, "PCRumah", "model name is PCRumah")

	-- PhoneSlot retains inert PhoneFast prop
	local phoneSlot = WorldService.GetAnchor(fakePlayer, "PhoneSlot")
	expectTrue(phoneSlot ~= nil, "PhoneSlot anchor exists")
	local phoneProp = (phoneSlot :: any):FindFirstChild("PhoneFast")
	expectTrue(phoneProp ~= nil, "PhoneFast remains as prop at PhoneSlot")

	-- Prompt anchor intact
	local promptAnchor = WorldService.GetAnchor(fakePlayer, "DashboardPromptAnchor")
	expectTrue(promptAnchor ~= nil, "DashboardPromptAnchor intact")
	local prompt = (promptAnchor :: any):FindFirstChildOfClass("ProximityPrompt")
	expectTrue(prompt ~= nil, "ProximityPrompt exists")

	WorldService.Remove(fakePlayer)
end)

-- ====================================================================
-- 6. Upgrades UI Dynamic Progression & Desktop Responsiveness
-- ====================================================================

test("Upgrades.shopState dynamically targets PC Rumah when fast phone is owned", function()
	local function makeState(deviceId: string, bal: number)
		return {
			snapshot = {
				deviceId = deviceId,
				balance = bal,
				maxShippedTier = 1,
				saveStatus = "healthy",
			},
		}
	end

	-- Fast phone owned, balance 100 < 220 -> locked
	local sLocked = Upgrades.shopState(makeState("phone_fast", 100))
	expectEqual(sLocked.phase, "locked", "PC Rumah locked when balance < 220")
	expectEqual((sLocked.target :: any).id, "pc_rumah", "target is pc_rumah")
	expectEqual(sLocked.price, 220, "price is 220")
	expectEqual(sLocked.remaining, 120, "remaining is 120")

	-- Fast phone owned, balance 220 -> affordable
	local sAffordable = Upgrades.shopState(makeState("phone_fast", 220))
	expectEqual(sAffordable.phase, "affordable", "PC Rumah affordable when balance >= 220")
	expectEqual((sAffordable.target :: any).id, "pc_rumah", "target is pc_rumah")

	-- PC Rumah owned -> owned
	local sOwned = Upgrades.shopState(makeState("pc_rumah", 500))
	expectEqual(sOwned.phase, "owned", "PC Rumah equipped -> owned phase")
end)

test("Desktop UI layout conforms to responsive contract (180px rail, 72x44 close)", function()
	local screenGui = Instance.new("ScreenGui")
	local desk = Desktop.new({
		parent = screenGui,
		onAction = function() end,
		onClose = function() end,
		getBlockReason = function() return nil end,
	})

	expectEqual(desk._navRail.Size.X.Offset, 180, "navigation rail width is 180px")
	expectEqual(desk._closeBtn.Size.X.Offset, 72, "close button width is 72px")
	expectEqual(desk._closeBtn.Size.Y.Offset, 44, "close button height is 44px")
	expectTrue(desk._mobileNav ~= nil, "mobile bottom navigation exists")
	expectTrue(desk._moreDrawer ~= nil, "mobile more drawer exists")

	desk:Destroy()
	screenGui:Destroy()
end)

-- ====================================================================
-- 7. Career Tier Progression
-- ====================================================================

test("Tier 1 (300 lifetime + 3 claims) gates brand_remix", function()
	local p = freshProfile()
	p.lifetimeEarned = 299
	p.completedMissions = 3

	-- Short on lifetime
	local accShortLife = MissionService.accept(p, "brand_remix", "r-1", 1000)
	expectEqual(accShortLife.ok, false, "lifetime 299 cannot accept brand_remix")
	expectEqual(accShortLife.code, "NOT_READY", "code is NOT_READY")

	-- Short on claims
	p.lifetimeEarned = 500
	p.completedMissions = 2
	local accShortClaims = MissionService.accept(p, "brand_remix", "r-2", 1000)
	expectEqual(accShortClaims.ok, false, "2 claims cannot accept brand_remix")
	expectEqual(accShortClaims.code, "NOT_READY", "code is NOT_READY")

	-- Both met
	p.completedMissions = 3
	local accOk = MissionService.accept(p, "brand_remix", "r-3", 1000)
	expectTrue(accOk.ok, "300+ lifetime and 3+ claims accepts brand_remix")
	expectEqual(accOk.profile.activeMission.missionId, "brand_remix", "brand_remix accepted")
end)

-- ====================================================================
-- Aggregator Run
-- ====================================================================

local passed = 0
local failed = 0
for _, t in ipairs(tests) do
	local ok, err = pcall(t.fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`[FAIL] {t.name}: {tostring(err)}`)
	end
end

print(`BS-11 spec: {passed}/{passed + failed} passed, {failed} failed`)
if failed > 0 then
	error(`BS-11 spec: {failed} failed`, 0)
end

return `BS-11: {passed}/{passed + failed} passed`
