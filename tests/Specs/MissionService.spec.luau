--!strict
-- Buzzer Simulator — MissionService spec (BS-03).
-- Executed by tests/Runner.server.luau in the test project only.
-- Deterministic pure-domain tests: no randomness, no DataStore, no clock other
-- than the injected `now` argument. Contract sources: docs/02, docs/03, docs/08
-- (BS-03), docs/09.
local ServerStorage = game:GetService("ServerStorage")
local MissionService = require(ServerStorage:WaitForChild("MissionService"))
local ScoringCatalog = require(ServerStorage:WaitForChild("ScoringCatalog"))
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

-- A fresh, valid v1 profile. Matches ProfileStore's validation so a proposed
-- profile can be round-tripped through it in recovery tests.
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

-- Simulate a durable save/reload: serialize through a deep copy so any aliasing
-- between the proposed profile and the input would be exposed. This is NOT real
-- DataStore evidence -- it only proves the transformation is reconstructable.
local function reload(profile: any): any
	local encoded = game:GetService("HttpService"):JSONEncode(profile)
	return game:GetService("HttpService"):JSONDecode(encoded)
end

local function assertOk(result: any, label: string): any
	if not result.ok then
		error(`{label}: expected OK, got {result.code} ({tostring(result.detail)})`, 0)
	end
	return result.profile
end
local function assertCode(result: any, code: string, label: string)
	if result.ok then
		error(`{label}: expected {code}, got OK`, 0)
	end
	expectEqual(result.code, code, label)
end
-- ===== shared-catalog fixture isolation =====
-- `Catalog.Missions` and `Catalog.V0Shipped.missionIds` are module-level tables
-- shared by every test in this spec and by the other specs in the same place.
-- A test that replaces one must restore the EXACT original reference even when
-- an assertion or the callback itself errors, otherwise one real defect
-- contaminates every later test and the reported failure names the wrong cause.
-- Restoration happens before the error is re-raised, and the originals are
-- captured as references (never reconstructed from a hardcoded V0 value).
local function withCatalogFixture(
	missions: { any },
	shippedMissionIds: { string },
	fn: () -> ()
)
	local realMissions = Catalog.Missions
	local realShipped = Catalog.V0Shipped.missionIds
	Catalog.Missions = missions
	Catalog.V0Shipped.missionIds = shippedMissionIds
	local ok, err = pcall(fn)
	Catalog.Missions = realMissions
	Catalog.V0Shipped.missionIds = realShipped
	if not ok then
		error(err, 0)
	end
end

-- ===== ScoringCatalog =====
test("V0 organic context has snack_meme as its unique strong template", function()
	local ctx = Catalog.OrganicContexts[1]
	expectEqual(ctx.contextId, "organic_snack", "first organic context id")
	local affinities = ScoringCatalog.organicAffinities()["organic_snack"]
	expectTrue(affinities ~= nil, "organic_snack has authored affinities")
	local strong, err = ScoringCatalog.resolveStrongTemplate(
		ctx.templates,
		affinities,
		ctx.trendId,
		ctx.audienceId
	)
	expectEqual(err, nil, "no resolution error")
	expectEqual(strong, "snack_meme", "snack_meme is the strong template")
end)

test("V0 mission context has meal_meme as its unique strong template", function()
	local mission = Catalog.Missions[1]
	expectEqual(mission.missionId, "food_stall_launch", "first mission id")
	expectEqual(mission.contexts[1], "meal_time", "first mission context")
	local affinities = ScoringCatalog.missionAffinities()["meal_time"]
	expectTrue(affinities ~= nil, "meal_time has authored affinities")
	local strong, err = ScoringCatalog.resolveStrongTemplate(
		mission.templates,
		affinities,
		"snack_trend",
		"students"
	)
	expectEqual(err, nil, "no resolution error")
	expectEqual(strong, "meal_meme", "meal_meme is the strong template")
end)

test("Scoring formula is exactly 2*trendMatch + audienceMatch", function()
	local affinities = ScoringCatalog.organicAffinities()["organic_snack"]
	-- snack_meme: both match -> 3.
	expectEqual(
		ScoringCatalog.scoreTemplate(affinities["snack_meme"], "snack_trend", "students"),
		3,
		"both match = 3"
	)
	-- snack_thread: trend only -> 2.
	expectEqual(
		ScoringCatalog.scoreTemplate(affinities["snack_thread"], "snack_trend", "students"),
		2,
		"trend only = 2"
	)
	-- snack_honest: audience only -> 1.
	expectEqual(
		ScoringCatalog.scoreTemplate(affinities["snack_honest"], "snack_trend", "students"),
		1,
		"audience only = 1"
	)
end)

test("fitForTemplate classifies strong and weak correctly", function()
	local ctx = Catalog.OrganicContexts[1]
	local affinities = ScoringCatalog.organicAffinities()["organic_snack"]
	local strong, err1 = ScoringCatalog.fitForTemplate(
		"snack_meme",
		ctx.templates,
		affinities,
		ctx.trendId,
		ctx.audienceId
	)
	expectEqual(err1, nil, "strong fit no error")
	expectEqual(strong, "strong", "snack_meme is strong")
	local weak, err2 = ScoringCatalog.fitForTemplate(
		"snack_thread",
		ctx.templates,
		affinities,
		ctx.trendId,
		ctx.audienceId
	)
	expectEqual(err2, nil, "weak fit no error")
	expectEqual(weak, "weak", "snack_thread is weak")
end)

test("A tie is rejected, never resolved randomly", function()
	local affinities = {
		a = { trendId = "t", audienceId = "u" },
		b = { trendId = "t", audienceId = "u" },
		c = { trendId = "x", audienceId = "y" },
	}
	local winner, err = ScoringCatalog.resolveStrongTemplate({ "a", "b", "c" }, affinities, "t", "u")
	expectEqual(winner, nil, "tie has no winner")
	local detail: string = err or ""
	expectTrue(detail:find("tie") ~= nil, "error names the tie")
end)

test("A missing affinity is rejected", function()
	local affinities = { a = { trendId = "t", audienceId = "u" } }
	local winner, err = ScoringCatalog.resolveStrongTemplate({ "a", "b" }, affinities, "t", "u")
	expectEqual(winner, nil, "missing affinity has no winner")
	local detail: string = err or ""
	expectTrue(detail:find("no authored affinity") ~= nil, "error names the missing affinity")
end)

test("A context with no templates is rejected", function()
	local winner, err = ScoringCatalog.resolveStrongTemplate({}, {}, "t", "u")
	expectEqual(winner, nil, "empty context has no winner")
	local detail: string = err or ""
	expectTrue(detail:find("no templates") ~= nil, "error names the empty context")
end)

test("An unknown template is rejected by fitForTemplate", function()
	local ctx = Catalog.OrganicContexts[1]
	local affinities = ScoringCatalog.organicAffinities()["organic_snack"]
	local fit, err = ScoringCatalog.fitForTemplate(
		"not_a_template",
		ctx.templates,
		affinities,
		ctx.trendId,
		ctx.audienceId
	)
	expectEqual(fit, nil, "unknown template has no fit")
	local detail: string = err or ""
	expectTrue(detail:find("does not belong") ~= nil, "error names the unknown template")
end)

test("V0 shipped content validates with unique winners", function()
	local okOrganic, problemsOrganic = ScoringCatalog.validateContent(
		Catalog.OrganicContexts,
		ScoringCatalog.organicAffinities()
	)
	expectTrue(okOrganic, `organic content invalid: {table.concat(problemsOrganic, "; ")}`)
	local okMission, problemsMission = ScoringCatalog.validateContent(
		Catalog.Missions,
		ScoringCatalog.missionAffinities(),
		-- Mission contexts must be resolved through the authoritative
		-- server-owned mapping, never a defaulted tag pair.
		ScoringCatalog.missionContextTags
	)
	expectTrue(okMission, `mission content invalid: {table.concat(problemsMission, "; ")}`)
end)

test("M1-style fixtures rotate winners per context without shipping M1", function()
	local fixtures = ScoringCatalog.TestFixtures
	-- Two organic contexts, each with a DIFFERENT unique winner.
	local organicContexts = {
		{ contextId = "organic_snack", trendId = "snack_trend", audienceId = "students", templates = { "snack_meme", "snack_thread", "snack_honest" } },
		{ contextId = "organic_gadget", trendId = "gadget_trend", audienceId = "students", templates = { "demo_curious", "demo_joke", "demo_thread" } },
	}
	local ok, problems = ScoringCatalog.validateContent(organicContexts, fixtures.organic)
	expectTrue(ok, `M1 organic fixtures invalid: {table.concat(problems, "; ")}`)
	local snackWinner = ScoringCatalog.resolveStrongTemplate(
		organicContexts[1].templates,
		fixtures.organic["organic_snack"],
		"snack_trend",
		"students"
	)
	local gadgetWinner = ScoringCatalog.resolveStrongTemplate(
		organicContexts[2].templates,
		fixtures.organic["organic_gadget"],
		"gadget_trend",
		"students"
	)
	expectEqual(snackWinner, "snack_meme", "snack context winner")
	expectEqual(gadgetWinner, "demo_curious", "gadget context winner")
	expectTrue(snackWinner ~= gadgetWinner, "different contexts pick different winners")
	-- M1 content must NOT be reachable through the shipped V0 catalog.
	expectEqual(#Catalog.V0Shipped.organicContextIds, 1, "V0 still ships one organic context")
end)

test("Private affinities are not present in the public Catalog", function()
	-- The public catalog lists template IDs and context tags, but must NOT carry
	-- the private template->affinity mapping that decides the winner.
	local publicEncoded = game:GetService("HttpService"):JSONEncode(Catalog.OrganicContexts)
	expectTrue(publicEncoded:find("snack_meme") ~= nil, "public catalog lists template IDs")
	expectTrue(publicEncoded:find("snack_trend") ~= nil, "public catalog exposes the context trend tag")
	-- The private affinity table is the only place the per-template mapping
	-- lives, and it must never be reachable from the public catalog.
	local privateEncoded = game:GetService("HttpService"):JSONEncode(ScoringCatalog.organicAffinities())
	expectTrue(privateEncoded:find("snack_meme") ~= nil, "private affinities key templates")
	expectTrue(privateEncoded:find("audienceId") ~= nil, "private affinities carry audience tags")
	-- The privacy boundary is the PER-TEMPLATE affinity mapping. The public
	-- catalog legitimately exposes each context's own trendId/audienceId
	-- (docs/03); what must never appear is a template keyed to its own
	-- affinity, which is what would reveal the winner.
	expectTrue(
		publicEncoded:find('"snack_meme":{"trendId"') == nil,
		"public catalog carries no per-template affinity mapping"
	)
end)

-- ===== AcceptMission =====
test("First V0 mission uses meal_time and freezes the run", function()
	local p = freshProfile()
	local next = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	expectEqual(next.activeMission.missionId, "food_stall_launch", "mission id")
	expectEqual(next.activeMission.runId, "run-1", "run id frozen")
	expectEqual(next.activeMission.contextId, "meal_time", "first context is meal_time")
	expectEqual(next.activeMission.status, "accepted", "status accepted")
	expectEqual(next.activeMission.postCount, 0, "postCount 0")
	expectEqual(next.activeMission.accumulatedImpact, 0, "impact 0")
end)

test("Accept increments the variant counter only in the proposed state", function()
	local p = freshProfile()
	local next = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	expectEqual(next.missionVariantCounters["food_stall_launch"], 1, "counter advanced")
	-- The input profile must be untouched.
	expectEqual(p.missionVariantCounters["food_stall_launch"], nil, "input counter unchanged")
	expectEqual(p.activeMission, nil, "input has no active mission")
end)

test("A second active mission is rejected", function()
	local p = freshProfile()
	local next = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "first accept")
	assertCode(
		MissionService.accept(next, "food_stall_launch", "run-2", 1000),
		"MISSION_ACTIVE",
		"duplicate active mission"
	)
end)

test("An unknown mission ID is rejected", function()
	assertCode(
		MissionService.accept(freshProfile(), "not_a_mission", "run-1", 1000),
		"UNKNOWN_MISSION",
		"unknown mission"
	)
end)

test("Accept requires a nonempty runId", function()
	assertCode(
		MissionService.accept(freshProfile(), "food_stall_launch", "", 1000),
		"INVALID_INPUT",
		"empty runId"
	)
end)
-- ===== tier gate (mission.minTier) =====
-- docs/02 career table: a mission's minTier is a progression gate. The v1
-- profile persists no tier field, so accept() derives eligibility from
-- lifetimeEarned + completedMissions clamped to the shipped tier cap.
test("A tier-0 player is rejected from a tier-1 mission", function()
	withCatalogFixture(
		{
			{
				missionId = "tier1_mission",
				requiredImpact = 100,
				reward = 80,
				minTier = 1,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
		},
		{ "tier1_mission" },
		function()
			local p = freshProfile()
			-- A profile that satisfies every OTHER gate: claims, mission
			-- content, context, no active mission. Only the tier is short.
			p.lifetimeEarned = 500
			p.completedMissions = 5
			assertCode(
				MissionService.accept(p, "tier1_mission", "run-1", 1000),
				"NOT_READY",
				"tier 0 cannot accept a tier-1 mission"
			)
		end
	)
end)
test("A tier-1 mission requires BOTH lifetime and claim thresholds", function()
	-- The shipped tier cap must also permit tier 1 for this test, otherwise the
	-- clamp holds eligibility at 0 regardless of the profile's totals.
	local realCap = Catalog.V0Shipped.maxShippedTier
	Catalog.V0Shipped.maxShippedTier = 1
	withCatalogFixture(
		{
			{
				missionId = "tier1_mission",
				requiredImpact = 100,
				reward = 80,
				minTier = 1,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
		},
		{ "tier1_mission" },
		function()
			-- Lifetime met, claims short (tier 1 needs 3 claims).
			local shortClaims = freshProfile()
			shortClaims.lifetimeEarned = 300
			shortClaims.completedMissions = 2
			assertCode(
				MissionService.accept(shortClaims, "tier1_mission", "run-1", 1000),
				"NOT_READY",
				"claims threshold not met"
			)
			-- Claims met, lifetime short.
			local shortLifetime = freshProfile()
			shortLifetime.lifetimeEarned = 299
			shortLifetime.completedMissions = 3
			assertCode(
				MissionService.accept(shortLifetime, "tier1_mission", "run-1", 1000),
				"NOT_READY",
				"lifetime threshold not met"
			)
			-- Both thresholds met: accepted.
			local eligible = freshProfile()
			eligible.lifetimeEarned = 300
			eligible.completedMissions = 3
			local next = assertOk(
				MissionService.accept(eligible, "tier1_mission", "run-1", 1000),
				"both thresholds met"
			)
			expectEqual(next.activeMission.missionId, "tier1_mission", "tier-1 mission accepted")
		end
	)
	Catalog.V0Shipped.maxShippedTier = realCap
end)
test("The shipped tier cap blocks a tier above the shipped cap", function()
	-- V0 ships maxShippedTier = 0, so even a profile that would clear tier 1's
	-- authored thresholds stays at tier 0 while the cap is 0.
	withCatalogFixture(
		{
			{
				missionId = "tier1_mission",
				requiredImpact = 100,
				reward = 80,
				minTier = 1,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
		},
		{ "tier1_mission" },
		function()
			local p = freshProfile()
			p.lifetimeEarned = 9999
			p.completedMissions = 99
			assertCode(
				MissionService.accept(p, "tier1_mission", "run-1", 1000),
				"NOT_READY",
				"shipped tier cap holds"
			)
		end
	)
end)
test("The V0 food mission remains available at tier 0", function()
	-- The shipped intro mission has minTier = 0, so a fresh profile accepts it.
	local p = freshProfile()
	local next = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "tier-0 accept")
	expectEqual(next.activeMission.missionId, "food_stall_launch", "V0 mission accepted at tier 0")
end)
test("The tier gate does not advance the variant counter", function()
	-- A rejected accept must not mutate the proposed state at all.
	withCatalogFixture(
		{
			{
				missionId = "tier1_mission",
				requiredImpact = 100,
				reward = 80,
				minTier = 1,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
		},
		{ "tier1_mission" },
		function()
			local p = freshProfile()
			local before = game:GetService("HttpService"):JSONEncode(p)
			assertCode(
				MissionService.accept(p, "tier1_mission", "run-1", 1000),
				"NOT_READY",
				"tier gate rejects"
			)
			expectEqual(
				game:GetService("HttpService"):JSONEncode(p),
				before,
				"input unchanged by the tier gate"
			)
			expectEqual(p.missionVariantCounters["tier1_mission"], nil, "counter not advanced")
		end
	)
end)

test("Accept is rejected while a mission is already active", function()
	local p = freshProfile()
	local next = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(next, "run-1", "meal_meme", 1000), "publish")
	-- docs/03 AcceptMission requires "no active run", so an active mission is
	-- the contract-specified rejection even while its post is resolving.
	assertCode(
		MissionService.accept(published, "food_stall_launch", "run-2", 1000),
		"MISSION_ACTIVE",
		"accept during an active mission"
	)
end)

test("Accept is allowed while an organic post is resolving", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "organic publish")
	-- docs/02: "Accepting a mission while browsing or making organic posts is
	-- allowed." Accepting does not touch the pending-post slot.
	local accepted = assertOk(
		MissionService.accept(published, "food_stall_launch", "run-1", 1000),
		"accept during a pending organic post"
	)
	expectEqual(accepted.activeMission.contextId, "meal_time", "mission accepted")
	expectEqual(accepted.activeMission.postCount, 0, "fresh postCount")
	-- The one-global-pending-post invariant still holds: the organic post is
	-- untouched and is still the single pending post.
	expectEqual(accepted.pendingPost.mode, "organic", "organic post still pending")
	expectEqual(accepted.pendingPost.templateId, "snack_meme", "organic post unchanged")
	expectEqual(accepted.pendingPost.settleAt, 1018, "organic settleAt unchanged")
end)

test("Accepting a mission does not disturb the pending organic settlement", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "organic publish")
	local accepted = assertOk(MissionService.accept(published, "food_stall_launch", "run-1", 1000), "accept")
	-- The organic post settles normally, with its frozen payout.
	local settled = assertOk(MissionService.settle(accepted, 1018), "settle organic")
	expectEqual(settled.balance, 15, "organic Cuan credited once")
	expectEqual(settled.lifetimeEarned, 15, "lifetime credited once")
	expectEqual(settled.pendingPost, nil, "pending post cleared")
	-- The newly accepted campaign is untouched by the organic settlement.
	expectEqual(settled.activeMission.status, "accepted", "mission still accepted")
	expectEqual(settled.activeMission.postCount, 0, "mission postCount still 0")
	expectEqual(settled.activeMission.accumulatedImpact, 0, "organic post did not advance the mission")
end)

test("An organic settlement does not advance a newly accepted campaign", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "organic publish")
	local accepted = assertOk(MissionService.accept(published, "food_stall_launch", "run-1", 1000), "accept")
	local settled = assertOk(MissionService.settle(accepted, 1018), "settle")
	-- The mission is still publishable and unaffected.
	local campaign = assertOk(MissionService.publishMission(settled, "run-1", "meal_meme", 2000), "campaign publish")
	expectEqual(campaign.activeMission.postCount, 1, "campaign postCount 1")
	expectEqual(campaign.pendingPost.mode, "mission", "campaign post pending")
	expectEqual(campaign.pendingPost.finalImpact, 120, "campaign impact scored fresh")
end)

test("Accept is still rejected while a mission post is resolving", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	-- A mission-tagged post belongs to a run; accepting a new mission would
	-- orphan it, so this stays blocked.
	assertCode(
		MissionService.accept(published, "food_stall_launch", "run-2", 1000),
		"MISSION_ACTIVE",
		"accept during a mission post"
	)
end)

test("Rejoin preserves the frozen context and does not reroll", function()
	local p = freshProfile()
	local next = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	-- Simulate a save/reload at every later transition; the context must never
	-- change and the counter must not advance again.
	local restored = reload(next)
	expectEqual(restored.activeMission.contextId, "meal_time", "context preserved across reload")
	local published = assertOk(MissionService.publishMission(restored, "run-1", "meal_meme", 1000), "publish")
	local restored2 = reload(published)
	expectEqual(restored2.activeMission.contextId, "meal_time", "context preserved after publish")
	expectEqual(restored2.missionVariantCounters["food_stall_launch"], 1, "counter not advanced by publish")
end)

test("Counter rotation works with a multi-context fixture", function()
	-- Inject a mission with three contexts and prove the counter rotates the
	-- frozen context across successive runs, without shipping M1 content.
	local p = freshProfile()
	p.missionVariantCounters = { multi_ctx_mission = 0 }
	local seen: { string } = {}
	withCatalogFixture(
		{
			{
				missionId = "multi_ctx_mission",
				requiredImpact = 100,
				reward = 80,
				minTier = 0,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time", "ctx_b", "ctx_c" },
			},
		},
		{ "multi_ctx_mission" },
		function()
			for i = 1, 3 do
				local next = assertOk(
					MissionService.accept(p, "multi_ctx_mission", `run-{i}`, 1000),
					`accept run {i}`
				)
				table.insert(seen, next.activeMission.contextId)
				-- Claim it so the next accept is allowed.
				next.activeMission.status = "readyToClaim"
				local claimed = assertOk(MissionService.claim(next, `run-{i}`), `claim run {i}`)
				p = claimed
			end
		end
	)
	expectEqual(seen[1], "meal_time", "first run uses the first context")
	expectEqual(seen[2], "ctx_b", "second run rotates")
	expectEqual(seen[3], "ctx_c", "third run rotates again")
end)

-- ===== PublishOrganic =====
test("A strong organic post publishes with frozen values and no reward", function()
	local p = freshProfile()
	local next = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish organic")
	local pending = next.pendingPost
	expectTrue(pending ~= nil, "pending post created")
	expectEqual(pending.mode, "organic", "mode organic")
	expectEqual(pending.contextId, "organic_snack", "context organic_snack")
	expectEqual(pending.templateId, "snack_meme", "template snack_meme")
	expectEqual(pending.missionRunId, nil, "no mission run id")
	expectEqual(pending.postId, "post-1", "postId from nextPostSequence")
	expectEqual(pending.publishedAt, 1000, "publishedAt frozen")
	expectEqual(pending.settleAt, 1018, "settleAt = publishedAt + 18s reveal")
	expectEqual(pending.finalImpact, 120, "strong impact 120")
	expectEqual(pending.organicCuan, 15, "strong organic 15")
	-- No currency at publish time.
	expectEqual(next.balance, 0, "no balance at publish")
	expectEqual(next.lifetimeEarned, 0, "no lifetime at publish")
	-- Sequence advanced only in the proposed state.
	expectEqual(next.nextOrganicSequence, 1, "organic sequence advanced")
	expectEqual(next.nextPostSequence, 2, "post sequence advanced")
	expectEqual(p.nextOrganicSequence, 0, "input organic sequence unchanged")
end)

test("A weak organic post publishes with weak frozen values", function()
	local p = freshProfile()
	local next = assertOk(MissionService.publishOrganic(p, "snack_thread", 1000), "publish weak organic")
	expectEqual(next.pendingPost.finalImpact, 75, "weak impact 75")
	expectEqual(next.pendingPost.organicCuan, 9, "weak organic 9")
	expectEqual(next.balance, 0, "no reward at publish")
end)

test("An invalid organic template is rejected", function()
	assertCode(
		MissionService.publishOrganic(freshProfile(), "not_a_template", 1000),
		"UNKNOWN_TEMPLATE",
		"unknown organic template"
	)
end)

test("A second organic post is refused while one is resolving", function()
	local p = freshProfile()
	local next = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "first publish")
	assertCode(
		MissionService.publishOrganic(next, "snack_meme", 1000),
		"PENDING_POST",
		"second publish during pending"
	)
end)

test("An organic post is allowed alongside an accepted mission", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local next = assertOk(MissionService.publishOrganic(accepted, "snack_meme", 1000), "organic publish")
	expectEqual(next.pendingPost.mode, "organic", "pending post is organic")
	expectEqual(next.activeMission.status, "accepted", "mission untouched")
	expectEqual(next.activeMission.postCount, 0, "mission postCount unchanged")
end)

test("An organic post never advances mission impact", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishOrganic(accepted, "snack_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	expectEqual(settled.activeMission.accumulatedImpact, 0, "mission impact unchanged by organic post")
	expectEqual(settled.activeMission.postCount, 0, "mission postCount unchanged")
	expectEqual(settled.balance, 15, "organic Cuan credited")
end)

-- ===== PublishPost (campaign) =====
test("A strong campaign post publishes and reaches readyToClaim on settle", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	expectEqual(published.pendingPost.mode, "mission", "mode mission")
	expectEqual(published.pendingPost.missionRunId, "run-1", "mission run id set")
	expectEqual(published.pendingPost.finalImpact, 120, "strong impact 120")
	expectEqual(published.pendingPost.organicCuan, 15, "strong organic 15")
	expectEqual(published.activeMission.postCount, 1, "postCount advanced at publish")
	expectEqual(published.activeMission.status, "resolvingPost", "status resolvingPost")
	expectEqual(published.balance, 0, "no reward at publish")

	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	expectEqual(settled.balance, 15, "organic credited at settle")
	expectEqual(settled.activeMission.accumulatedImpact, 120, "impact credited")
	expectEqual(settled.activeMission.status, "readyToClaim", "readyToClaim after strong post")
	expectEqual(settled.pendingPost, nil, "pending post cleared")
end)

test("The two-weak-post journey works end to end", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")

	-- First weak post: 75 < 100, so the mission returns to accepted.
	local pub1 = assertOk(MissionService.publishMission(accepted, "run-1", "queue_thread", 1000), "publish weak 1")
	expectEqual(pub1.pendingPost.finalImpact, 75, "first weak impact 75")
	expectEqual(pub1.pendingPost.organicCuan, 9, "first weak organic 9")
	expectEqual(pub1.activeMission.postCount, 1, "postCount 1 after first publish")

	local settle1 = assertOk(MissionService.settle(pub1, 1018), "settle weak 1")
	expectEqual(settle1.balance, 9, "first weak organic credited")
	expectEqual(settle1.activeMission.accumulatedImpact, 75, "impact 75")
	expectEqual(settle1.activeMission.status, "accepted", "back to accepted (short)")
	expectEqual(settle1.activeMission.postCount, 1, "postCount stays 1 after settle")

	-- Second weak post: admitted because postCount 1 < 2.
	local pub2 = assertOk(MissionService.publishMission(settle1, "run-1", "late_night_quip", 2000), "publish weak 2")
	expectEqual(pub2.activeMission.postCount, 2, "postCount 2 after second publish")
	expectEqual(pub2.pendingPost.finalImpact, 75, "second weak impact 75")

	local settle2 = assertOk(MissionService.settle(pub2, 2018), "settle weak 2")
	expectEqual(settle2.balance, 18, "both weak organic payouts credited (9+9)")
	expectEqual(settle2.activeMission.accumulatedImpact, 150, "combined impact 150")
	expectEqual(settle2.activeMission.status, "readyToClaim", "readyToClaim after two weak posts")

	-- Claim awards the fixed 80 once.
	local claimed = assertOk(MissionService.claim(settle2, "run-1"), "claim")
	expectEqual(claimed.balance, 98, "18 organic + 80 bonus")
	expectEqual(claimed.completedMissions, 1, "completedMissions 1")
	expectEqual(claimed.lifetimeEarned, 98, "lifetime 98")
end)

test("A third campaign post is rejected", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local pub1 = assertOk(MissionService.publishMission(accepted, "run-1", "queue_thread", 1000), "publish 1")
	local settle1 = assertOk(MissionService.settle(pub1, 1018), "settle 1")
	local pub2 = assertOk(MissionService.publishMission(settle1, "run-1", "late_night_quip", 2000), "publish 2")
	local settle2 = assertOk(MissionService.settle(pub2, 2018), "settle 2")
	assertCode(
		MissionService.publishMission(settle2, "run-1", "meal_meme", 3000),
		"LIMIT_REACHED",
		"third campaign post"
	)
end)

test("An incorrect run ID is rejected for campaign publish", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	assertCode(
		MissionService.publishMission(accepted, "run-WRONG", "meal_meme", 1000),
		"RUN_MISMATCH",
		"wrong run id"
	)
end)

test("An invalid campaign template is rejected", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	assertCode(
		MissionService.publishMission(accepted, "run-1", "not_a_template", 1000),
		"UNKNOWN_TEMPLATE",
		"unknown campaign template"
	)
end)

test("Campaign publish is refused with no active mission", function()
	assertCode(
		MissionService.publishMission(freshProfile(), "run-1", "meal_meme", 1000),
		"NO_ACTIVE_MISSION",
		"no active mission"
	)
end)

test("Cross-mode pending-post conflict is refused", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	-- An organic post is in flight; a campaign post must be refused.
	local organic = assertOk(MissionService.publishOrganic(accepted, "snack_meme", 1000), "organic publish")
	assertCode(
		MissionService.publishMission(organic, "run-1", "meal_meme", 1000),
		"PENDING_POST",
		"campaign publish during organic pending"
	)
	-- And the reverse: a campaign post in flight blocks an organic one.
	local campaign = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "campaign publish")
	assertCode(
		MissionService.publishOrganic(campaign, "snack_meme", 1000),
		"PENDING_POST",
		"organic publish during campaign pending"
	)
end)

test("A frozen campaign result survives a serialized profile reconstruction", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local restored = reload(published)
	expectEqual(restored.pendingPost.finalImpact, 120, "frozen impact survives reload")
	expectEqual(restored.pendingPost.organicCuan, 15, "frozen payout survives reload")
	expectEqual(restored.pendingPost.settleAt, 1018, "frozen settleAt survives reload")
	-- Settling the restored profile must use the frozen values, not rescore.
	local settled = assertOk(MissionService.settle(restored, 1018), "settle restored")
	expectEqual(settled.balance, 15, "frozen payout credited from restored state")
end)

-- ===== Settle =====
test("Settlement before settleAt is rejected", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	assertCode(MissionService.settle(published, 1017), "NOT_DUE", "settle one second early")
end)

test("Settlement exactly at settleAt succeeds", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle at settleAt")
	expectEqual(settled.balance, 15, "credited at settleAt")
end)

test("Settlement after settleAt succeeds", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 5000), "settle late")
	expectEqual(settled.balance, 15, "credited after settleAt")
end)

test("Duplicate settlement does not pay again", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "first settle")
	expectEqual(settled.balance, 15, "first settle credits once")
	-- The pending post is consumed, so a second attempt has nothing to settle.
	assertCode(MissionService.settle(settled, 2000), "NO_PENDING_POST", "second settle")
	expectEqual(settled.balance, 15, "balance unchanged by second attempt")
end)

test("Settlement with no pending post is rejected", function()
	assertCode(MissionService.settle(freshProfile(), 1000), "NO_PENDING_POST", "settle with nothing pending")
end)

test("Own post history is capped at ten", function()
	local p = freshProfile()
	for i = 1, 12 do
		local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), `publish {i}`)
		p = assertOk(MissionService.settle(published, 1018), `settle {i}`)
	end
	expectEqual(#p.ownPosts, 10, "own posts capped at 10")
	-- Newest first.
	expectEqual(p.ownPosts[1].postId, "post-12", "newest post is first")
	expectEqual(p.ownPosts[10].postId, "post-3", "oldest retained is post 3")
end)

test("The input profile is never mutated on success or failure", function()
	local p = freshProfile()
	local before = game:GetService("HttpService"):JSONEncode(p)
	-- Success path.
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	expectEqual(game:GetService("HttpService"):JSONEncode(p), before, "input unchanged after publish")
	assertOk(MissionService.settle(published, 1018), "settle")
	expectEqual(game:GetService("HttpService"):JSONEncode(p), before, "input unchanged after settle")
	-- Failure path.
	MissionService.settle(p, 5000)
	MissionService.publishOrganic(p, "not_a_template", 1000)
	MissionService.claim(p, "run-1")
	expectEqual(game:GetService("HttpService"):JSONEncode(p), before, "input unchanged after failures")
end)

test("Mission impact is credited exactly once", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	expectEqual(settled.activeMission.accumulatedImpact, 120, "impact credited once")
	-- Re-settling is impossible (no pending post), so impact cannot double.
	assertCode(MissionService.settle(settled, 2000), "NO_PENDING_POST", "re-settle refused")
end)
test("Settlement does not alias own-post summaries with the input profile", function()
	-- The proposed profile must OWN every nested table. A JSON snapshot cannot
	-- detect aliasing, so this mutates a retained summary in the proposal and
	-- checks the profile that was actually passed to settle(), then the other
	-- way round.
	local p = freshProfile()
	for i = 1, 3 do
		table.insert(p.ownPosts, {
			postId = `post-{i}`,
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			finalImpact = 120,
			organicCuan = 15,
			publishedAt = 1000 * i,
		})
	end
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 5000), "publish")
	local settled = assertOk(MissionService.settle(published, 5018), "settle")
	expectEqual(#settled.ownPosts, 4, "new summary prepended, three retained")
	-- Mutating the proposal's retained summaries must not reach the profile
	-- that was passed to settle().
	for i = 2, 4 do
		settled.ownPosts[i].finalImpact = 999999
	end
	for i = 1, 3 do
		expectEqual(
			published.ownPosts[i].finalImpact,
			120,
			`settle input summary {i} untouched by proposal mutation`
		)
	end
	-- Mutating the settle input's summaries must not reach the proposal.
	for i = 1, 3 do
		published.ownPosts[i].finalImpact = 888888
	end
	for i = 2, 4 do
		expectEqual(
			settled.ownPosts[i].finalImpact,
			999999,
			`proposal summary {i} untouched by settle input mutation`
		)
	end
end)
test("Settlement refuses a credit that reaches the economy limit", function()
	-- docs/04: "stop growth before 1e12". The payout formula is unchanged; the
	-- transition is refused instead of clamped, with no partial mutation.
	-- 1e12 - 5 + 15 = 1e12 + 10, which reaches the limit.
	local p = freshProfile()
	p.balance = 1e12 - 5
	p.lifetimeEarned = 1e12 - 5
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	local result = MissionService.settle(published, 1018)
	assertCode(result, "LIMIT_REACHED", "settlement past the limit")
	expectEqual(result.profile, nil, "no proposed profile on refusal")
	-- The input is untouched.
	expectEqual(published.balance, 1e12 - 5, "input balance unchanged")
	expectEqual(published.pendingPost ~= nil, true, "pending post still pending")
end)
test("A credit just below the economy limit still succeeds", function()
	-- The boundary is exclusive: a total strictly below 1e12 is legal.
	-- 1e12 - 1000 + 15 = 1e12 - 985.
	local p = freshProfile()
	p.balance = 1e12 - 1000
	p.lifetimeEarned = 1e12 - 1000
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle below limit")
	expectEqual(settled.balance, 1e12 - 985, "credit applied below the limit")
	expectEqual(settled.lifetimeEarned, 1e12 - 985, "lifetime applied below the limit")
end)
test("Claim refuses a bonus that reaches the economy limit", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	-- 1e12 - 5 + 80 = 1e12 + 75, which reaches the limit.
	settled.balance = 1e12 - 5
	settled.lifetimeEarned = 1e12 - 5
	local result = MissionService.claim(settled, "run-1")
	assertCode(result, "LIMIT_REACHED", "claim past the limit")
	expectEqual(result.profile, nil, "no proposed profile on refusal")
	expectEqual(settled.completedMissions, 0, "claim count unchanged")
	expectEqual(#settled.claimedRunIdsWindow, 0, "claimed window unchanged")
	expectEqual(settled.activeMission ~= nil, true, "mission still active")
end)
-- ===== server timestamp validation =====
test("Publish rejects NaN, infinities and negative timestamps", function()
	local p = freshProfile()
	local nan = 0 / 0
	assertCode(MissionService.publishOrganic(p, "snack_meme", nan), "INVALID_INPUT", "NaN now")
	assertCode(MissionService.publishOrganic(p, "snack_meme", math.huge), "INVALID_INPUT", "+inf now")
	assertCode(MissionService.publishOrganic(p, "snack_meme", -math.huge), "INVALID_INPUT", "-inf now")
	assertCode(MissionService.publishOrganic(p, "snack_meme", -1), "INVALID_INPUT", "negative now")
	assertCode(
		MissionService.publishMission(p, "run-1", "meal_meme", nan),
		"INVALID_INPUT",
		"NaN now on campaign publish"
	)
	assertCode(
		MissionService.publishMission(p, "run-1", "meal_meme", math.huge),
		"INVALID_INPUT",
		"+inf now on campaign publish"
	)
	assertCode(MissionService.publishMission(p, "run-1", "meal_meme", -5), "INVALID_INPUT", "negative now on campaign publish")
end)
test("Settle rejects NaN, infinities and negative timestamps", function()
	local p = freshProfile()
	local published = assertOk(MissionService.publishOrganic(p, "snack_meme", 1000), "publish")
	local nan = 0 / 0
	assertCode(MissionService.settle(published, nan), "INVALID_INPUT", "NaN now")
	assertCode(MissionService.settle(published, math.huge), "INVALID_INPUT", "+inf now")
	assertCode(MissionService.settle(published, -math.huge), "INVALID_INPUT", "-inf now")
	assertCode(MissionService.settle(published, -1), "INVALID_INPUT", "negative now")
end)
test("Accept rejects NaN, infinities and negative timestamps", function()
	local nan = 0 / 0
	assertCode(
		MissionService.accept(freshProfile(), "food_stall_launch", "run-1", nan),
		"INVALID_INPUT",
		"NaN now"
	)
	assertCode(
		MissionService.accept(freshProfile(), "food_stall_launch", "run-1", math.huge),
		"INVALID_INPUT",
		"+inf now"
	)
	assertCode(
		MissionService.accept(freshProfile(), "food_stall_launch", "run-1", -math.huge),
		"INVALID_INPUT",
		"-inf now"
	)
	assertCode(
		MissionService.accept(freshProfile(), "food_stall_launch", "run-1", -1),
		"INVALID_INPUT",
		"negative now"
	)
end)

-- ===== ClaimMission =====
test("A successful claim awards the fixed 80 Cuan exactly once", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	local claimed = assertOk(MissionService.claim(settled, "run-1"), "claim")
	expectEqual(claimed.balance, 95, "15 organic + 80 bonus")
	expectEqual(claimed.lifetimeEarned, 95, "lifetime 95")
	expectEqual(claimed.completedMissions, 1, "completedMissions 1")
	expectEqual(#claimed.claimedRunIdsWindow, 1, "one claimed run recorded")
	expectEqual(claimed.claimedRunIdsWindow[1], "run-1", "claimed run id recorded")
	expectEqual(claimed.activeMission, nil, "mission consumed")
end)

test("A claim before readyToClaim is rejected", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	assertCode(MissionService.claim(accepted, "run-1"), "NOT_READY", "claim while accepted")
end)

test("A duplicate claim is rejected", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	local claimed = assertOk(MissionService.claim(settled, "run-1"), "claim")
	-- The mission is consumed, so a second claim has no active mission.
	assertCode(MissionService.claim(claimed, "run-1"), "NO_ACTIVE_MISSION", "second claim")
end)

test("A claim with an incorrect run ID is rejected", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	assertCode(MissionService.claim(settled, "run-WRONG"), "RUN_MISMATCH", "wrong run id claim")
end)

test("A claimed run stays claimable-proof within the 32-entry bound", function()
	local p = freshProfile()
	-- Pre-fill the window to the bound with older runs.
	for i = 1, 32 do
		table.insert(p.claimedRunIdsWindow, `old-run-{i}`)
	end
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-new", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-new", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	local claimed = assertOk(MissionService.claim(settled, "run-new"), "claim")
	expectEqual(#claimed.claimedRunIdsWindow, 32, "window stays at 32")
	expectEqual(claimed.claimedRunIdsWindow[32], "run-new", "newest claim is last")
	expectEqual(claimed.claimedRunIdsWindow[1], "old-run-2", "oldest evicted")
end)

test("A new eligible mission can be accepted after a claim", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept 1")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	local claimed = assertOk(MissionService.claim(settled, "run-1"), "claim")
	-- The intro mission has unlockClaims 0, so it is immediately available again.
	local reaccepted = assertOk(MissionService.accept(claimed, "food_stall_launch", "run-2", 2000), "accept 2")
	expectEqual(reaccepted.activeMission.runId, "run-2", "new run accepted")
	expectEqual(reaccepted.activeMission.postCount, 0, "fresh postCount")
	-- The counter rotated, but V0 has one context so it is still meal_time.
	expectEqual(reaccepted.activeMission.contextId, "meal_time", "context still meal_time")
end)

test("Settlement does not auto-claim the mission", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	expectEqual(settled.activeMission.status, "readyToClaim", "status readyToClaim, not claimed")
	expectEqual(settled.completedMissions, 0, "no claim counted")
	expectEqual(settled.balance, 15, "only organic credited, no bonus")
end)

-- ===== Recovery at every transition =====
test("Recovery: state reconstructs without reroll or double-pay at each step", function()
	local p = freshProfile()
	local checkpoints: { { label: string, profile: any } } = {}

	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	table.insert(checkpoints, { label = "accepted", profile = accepted })

	local published = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "publish")
	table.insert(checkpoints, { label = "campaign pending", profile = published })

	local settled = assertOk(MissionService.settle(published, 1018), "settle")
	table.insert(checkpoints, { label = "ready to claim", profile = settled })

	local claimed = assertOk(MissionService.claim(settled, "run-1"), "claim")
	table.insert(checkpoints, { label = "claimed", profile = claimed })

	for _, checkpoint in ipairs(checkpoints) do
		local restored = reload(checkpoint.profile)
		-- Replaying the SAME operation on a restored state must not double-pay.
		if restored.pendingPost ~= nil then
			local before = restored.balance
			local resettled = assertOk(MissionService.settle(restored, 9999), `re-settle {checkpoint.label}`)
			expectEqual(resettled.balance, before + restored.pendingPost.organicCuan, `single payout at {checkpoint.label}`)
			-- A second settle on the result pays nothing further.
			assertCode(MissionService.settle(resettled, 9999), "NO_PENDING_POST", `no double settle at {checkpoint.label}`)
		end
		if restored.activeMission ~= nil and restored.activeMission.status == "readyToClaim" then
			local beforeBalance = restored.balance
			local beforeClaims = restored.completedMissions
			local reclaimed = assertOk(MissionService.claim(restored, restored.activeMission.runId), `re-claim {checkpoint.label}`)
			expectEqual(reclaimed.balance, beforeBalance + 80, `single bonus at {checkpoint.label}`)
			expectEqual(reclaimed.completedMissions, beforeClaims + 1, `single claim count at {checkpoint.label}`)
		end
	end
end)

test("Recovery: a restored accepted mission keeps its frozen context", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local restored = reload(accepted)
	expectEqual(restored.activeMission.contextId, "meal_time", "context frozen across reload")
	-- Publishing on the restored state uses the frozen context.
	local published = assertOk(MissionService.publishMission(restored, "run-1", "meal_meme", 1000), "publish restored")
	expectEqual(published.pendingPost.contextId, "meal_time", "published against the frozen context")
end)

-- ===== mission impact uses the mission's requiredImpact as B =====
-- docs/03: `Rules.postImpact(requiredImpact, fit, deviceYield)`. Organic-only
-- posts use B=100 for presentation. These fixtures are NOT shipped: they prove
-- the scoring path honours each mission's own requirement.
local function withMissionFixture(requiredImpact: number, fn: (any) -> ())
	withCatalogFixture(
		{
			{
				missionId = "fixture_mission",
				requiredImpact = requiredImpact,
				reward = 80,
				minTier = 0,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
		},
		{ "fixture_mission" },
		fn
	)
end

test("V0 mission posts score 120 strong / 75 weak (B=100)", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	local strong = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "strong publish")
	expectEqual(strong.pendingPost.finalImpact, 120, "V0 strong impact 120")
	expectEqual(strong.pendingPost.organicCuan, 15, "V0 strong organic 15")
	-- A separate run for the weak assertion, so the strong settle (which reaches
	-- readyToClaim) does not block it.
	local accepted2 = assertOk(MissionService.accept(freshProfile(), "food_stall_launch", "run-2", 1000), "accept 2")
	local weak = assertOk(MissionService.publishMission(accepted2, "run-2", "queue_thread", 2000), "weak publish")
	expectEqual(weak.pendingPost.finalImpact, 75, "V0 weak impact 75")
	expectEqual(weak.pendingPost.organicCuan, 9, "V0 weak organic 9")
end)

test("A B=130 mission scores 156 strong / 97 weak", function()
	withMissionFixture(130, function()
		local p = freshProfile()
		local accepted = assertOk(MissionService.accept(p, "fixture_mission", "run-1", 1000), "accept")
		local strong = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "strong")
		expectEqual(strong.pendingPost.finalImpact, 156, "B=130 strong: floor(130*1.2)")
		local settle = assertOk(MissionService.settle(strong, 1018), "settle")
		expectEqual(settle.activeMission.status, "readyToClaim", "156 >= 130 is claimable")
		-- A separate run for the weak assertion (the strong settle already
		-- reached readyToClaim).
		local accepted2 = assertOk(MissionService.accept(freshProfile(), "fixture_mission", "run-2", 1000), "accept 2")
		local weak = assertOk(MissionService.publishMission(accepted2, "run-2", "queue_thread", 2000), "weak")
		expectEqual(weak.pendingPost.finalImpact, 97, "B=130 weak: floor(130*0.75)")
	end)
end)

test("A B=160 mission scores 192 strong / 120 weak", function()
	withMissionFixture(160, function()
		local p = freshProfile()
		local accepted = assertOk(MissionService.accept(p, "fixture_mission", "run-1", 1000), "accept")
		local strong = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "strong")
		expectEqual(strong.pendingPost.finalImpact, 192, "B=160 strong: floor(160*1.2)")
		local settle = assertOk(MissionService.settle(strong, 1018), "settle")
		expectEqual(settle.activeMission.status, "readyToClaim", "192 >= 160 is claimable")
		-- A separate run for the weak assertion (the strong settle already
		-- reached readyToClaim).
		local accepted2 = assertOk(MissionService.accept(freshProfile(), "fixture_mission", "run-2", 1000), "accept 2")
		local weak = assertOk(MissionService.publishMission(accepted2, "run-2", "queue_thread", 2000), "weak")
		expectEqual(weak.pendingPost.finalImpact, 120, "B=160 weak: floor(160*0.75)")
	end)
end)

test("A B=220 mission scores 264 strong / 165 weak", function()
	withMissionFixture(220, function()
		local p = freshProfile()
		local accepted = assertOk(MissionService.accept(p, "fixture_mission", "run-1", 1000), "accept")
		local strong = assertOk(MissionService.publishMission(accepted, "run-1", "meal_meme", 1000), "strong")
		expectEqual(strong.pendingPost.finalImpact, 264, "B=220 strong: floor(220*1.2)")
		local settle = assertOk(MissionService.settle(strong, 1018), "settle")
		expectEqual(settle.activeMission.status, "readyToClaim", "264 >= 220 is claimable")
		-- A separate run for the weak assertion (the strong settle already
		-- reached readyToClaim).
		local accepted2 = assertOk(MissionService.accept(freshProfile(), "fixture_mission", "run-2", 1000), "accept 2")
		local weak = assertOk(MissionService.publishMission(accepted2, "run-2", "queue_thread", 2000), "weak")
		expectEqual(weak.pendingPost.finalImpact, 165, "B=220 weak: floor(220*0.75)")
	end)
end)

test("Organic posts still use B=100 regardless of the active mission", function()
	withMissionFixture(220, function()
		local p = freshProfile()
		local accepted = assertOk(MissionService.accept(p, "fixture_mission", "run-1", 1000), "accept")
		-- An organic post is scored against B=100, not the mission's 220.
		local organic = assertOk(MissionService.publishOrganic(accepted, "snack_meme", 1000), "organic publish")
		expectEqual(organic.pendingPost.finalImpact, 120, "organic strong impact stays 120")
		expectEqual(organic.pendingPost.organicCuan, 15, "organic strong payout stays 15")
	end)
end)

-- ===== mission context tag resolution =====
test("A known mission context resolves its authored tags", function()
	local trendId, audienceId, err = MissionService._missionContextTags("meal_time")
	expectEqual(err, nil, "no error for a known context")
	expectEqual(trendId, "snack_trend", "meal_time trend")
	expectEqual(audienceId, "students", "meal_time audience")
end)

test("An unknown mission context fails instead of falling back to V0 tags", function()
	local trendId, _, err = MissionService._missionContextTags("neon_market")
	expectEqual(trendId, nil, "no tags for an unknown context")
	local detail: string = err or ""
	expectTrue(detail:find("no authored tags") ~= nil, "error names the missing tags")
end)

test("Publishing against an unknown mission context is refused", function()
	local p = freshProfile()
	local accepted = assertOk(MissionService.accept(p, "food_stall_launch", "run-1", 1000), "accept")
	-- Corrupt the frozen context to one with no authored tags.
	accepted.activeMission.contextId = "neon_market"
	local result = MissionService.publishMission(accepted, "run-1", "meal_meme", 1000)
	expectEqual(result.ok, false, "unknown context refused")
	expectEqual(result.code, "UNKNOWN_CONTEXT", "unknown context code")
end)

-- ===== shipped-content validation gate =====
test("Shipped V0 content passes the validation gate", function()
	local ok, problems = ScoringCatalog.validateShippedContent(
		Catalog,
		Catalog.V0Shipped.organicContextIds,
		Catalog.V0Shipped.missionIds
	)
	expectTrue(ok, `shipped content invalid: {table.concat(problems, "; ")}`)
end)

test("The validation gate rejects a shipped context with no affinities", function()
	local ok, problems = ScoringCatalog.validateShippedContent(
		Catalog,
		{ "organic_snack", "organic_unknown" },
		Catalog.V0Shipped.missionIds
	)
	expectEqual(ok, false, "unshipped-affinity context rejected")
	expectTrue(#problems > 0, "problems reported")
end)

test("The validation gate rejects a shipped mission context with no tags", function()
	withCatalogFixture(
		{
			{
				missionId = "bad_mission",
				requiredImpact = 100,
				reward = 80,
				minTier = 0,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time", "untagged_context" },
			},
		},
		{ "bad_mission" },
		function()
			local ok, problems = ScoringCatalog.validateShippedContent(
				Catalog,
				Catalog.V0Shipped.organicContextIds,
				Catalog.V0Shipped.missionIds
			)
			expectEqual(ok, false, "untagged mission context rejected")
			expectTrue(#problems > 0, "problems reported")
		end
	)
end)

test("The validation gate ignores unshipped M1 content", function()
	-- An unshipped mission referencing an unknown context must not fail the
	-- gate, because M1 content is not gated on V0 affinities yet. The valid
	-- shipped V0 mission stays present, so this also proves the new
	-- shipped-mission-existence check does not fire on real content.
	withCatalogFixture(
		{
			-- The real V0 mission: shipped and valid.
			{
				missionId = "food_stall_launch",
				requiredImpact = 100,
				reward = 80,
				minTier = 0,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
			-- Unshipped M1 content with an unknown context: must be ignored.
			{
				missionId = "m1_mission",
				requiredImpact = 160,
				reward = 120,
				minTier = 1,
				unlockClaims = 1,
				templates = { "weekend_plans", "event_thread", "neon_quip" },
				contexts = { "neon_market" },
			},
		},
		{ "food_stall_launch" },
		function()
			local ok, problems = ScoringCatalog.validateShippedContent(
				Catalog,
				Catalog.V0Shipped.organicContextIds,
				Catalog.V0Shipped.missionIds
			)
			expectTrue(ok, `unshipped M1 content must not fail the gate: {table.concat(problems, "; ")}`)
		end
	)
end)
test("The validation gate rejects a shipped mission missing from the catalog", function()
	-- A shipped mission ID with no matching definition must fail: the mission
	-- loop only walks the missions that exist, so a missing ID is otherwise
	-- never examined at all.
	withCatalogFixture(
		{
			{
				missionId = "food_stall_launch",
				requiredImpact = 100,
				reward = 80,
				minTier = 0,
				unlockClaims = 0,
				templates = { "meal_meme", "queue_thread", "late_night_quip" },
				contexts = { "meal_time" },
			},
		},
		{ "food_stall_launch", "typo_mission" },
		function()
			local ok, problems = ScoringCatalog.validateShippedContent(
				Catalog,
				Catalog.V0Shipped.organicContextIds,
				Catalog.V0Shipped.missionIds
			)
			expectEqual(ok, false, "missing shipped mission rejected")
			expectTrue(#problems > 0, "problems reported")
			expectTrue(
				table.concat(problems, "; "):find("typo_mission") ~= nil,
				"problem names the missing mission"
			)
		end
	)
end)
test("assertShippedContentValid raises on a missing shipped mission", function()
	local ok, err = pcall(function()
		ScoringCatalog.assertShippedContentValid(
			Catalog,
			Catalog.V0Shipped.organicContextIds,
			{ "missing_mission" }
		)
	end)
	expectEqual(ok, false, "missing shipped mission raises")
	expectTrue(
		type(err) == "string" and err:find("missing_mission") ~= nil,
		"error names the missing mission"
	)
end)
test("validateContent rejects an unknown mission context instead of defaulting tags", function()
	-- The generic validator must NOT silently score an unknown mission context
	-- against the V0 identifiers. An unresolvable context is invalid content.
	local ok, problems = ScoringCatalog.validateContent(
		{
			{
				missionId = "m1_mission",
				requiredImpact = 160,
				reward = 120,
				minTier = 1,
				unlockClaims = 1,
				templates = { "weekend_plans", "event_thread", "neon_quip" },
				contexts = { "neon_market" },
			},
		},
		ScoringCatalog.TestFixtures.mission,
		ScoringCatalog.missionContextTags
	)
	expectEqual(ok, false, "unknown mission context rejected")
	expectTrue(#problems > 0, "problems reported")
	expectTrue(
		table.concat(problems, "; "):find("neon_market") ~= nil,
		"problem names the unknown context"
	)
end)
test("validateContent rejects mission entries when no tag lookup is supplied", function()
	-- Without an explicit lookup there is no authoritative source for mission
	-- context tags, so the validator must refuse rather than guess.
	local ok, problems = ScoringCatalog.validateContent(
		Catalog.Missions,
		ScoringCatalog.missionAffinities()
	)
	expectEqual(ok, false, "missing tag lookup rejected")
	expectTrue(#problems > 0, "problems reported")
end)
test("A failing catalog fixture restores the exact original references", function()
	-- Shared catalog state must survive a fixture whose body errors, otherwise
	-- one real defect contaminates every later test in the place.
	local realMissions = Catalog.Missions
	local realShipped = Catalog.V0Shipped.missionIds
	local fixtureFailed = false
	pcall(function()
		withCatalogFixture(
			{
				{
					missionId = "boom_mission",
					requiredImpact = 100,
					reward = 80,
					minTier = 0,
					unlockClaims = 0,
					templates = { "meal_meme", "queue_thread", "late_night_quip" },
					contexts = { "meal_time" },
				},
			},
			{ "boom_mission" },
			function()
				-- Force a failure inside the fixture body.
				error("intentional fixture failure", 0)
			end
		)
	end)
	fixtureFailed = true
	expectEqual(fixtureFailed, true, "fixture body ran")
	-- Reference identity, not just equal contents.
	expectEqual(Catalog.Missions == realMissions, true, "Catalog.Missions reference restored")
	expectEqual(
		Catalog.V0Shipped.missionIds == realShipped,
		true,
		"V0Shipped.missionIds reference restored"
	)
	expectEqual(Catalog.Missions[1].missionId, "food_stall_launch", "real mission content restored")
	expectEqual(#Catalog.V0Shipped.missionIds, 1, "real shipped list restored")
	expectEqual(Catalog.V0Shipped.missionIds[1], "food_stall_launch", "real shipped id restored")
end)

test("assertShippedContentValid raises on invalid content", function()
	local ok, err = pcall(function()
		ScoringCatalog.assertShippedContentValid(Catalog, { "organic_unknown" }, {})
	end)
	expectEqual(ok, false, "invalid content raises")
	expectTrue(type(err) == "string" and err:find("invalid") ~= nil, "error names the invalidity")
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
print(`MissionService spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print(`FAILURES:`)
	for _, f in ipairs(failures) do
		print(`  - {f}`)
	end
	print("BS03_MISSION_TESTS_FAILED")
	error(`MissionService spec: {#failures} failed (see FAILURES above)`, 0)
end
print("BS03_MISSION_TESTS_PASSED")
return `MissionService: {passed}/{#tests} passed`
