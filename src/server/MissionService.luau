--!strict
-- Buzzer Simulator — MissionService (BS-03, pure domain layer).
-- One shared post/settlement path for organic and mission-tagged posts.
--
-- BOUNDARY (docs/03, BS-03 backlog): this module owns pure gameplay-state
-- transformations ONLY. It never persists, never touches the network, never
-- mutates its input profile, and never awards anything before a durable write
-- confirms it. Every operation returns an explicit code plus a PROPOSED
-- profile; SessionService (BS-04) performs the conditional write and only then
-- publishes the state. A failed or uncertain save therefore cannot expose
-- unconfirmed balance or mission progress.
--
-- Determinism: no randomness anywhere. Outcomes are frozen at publish and
-- settlement consumes the frozen values, so a rejoin replays exactly.
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))
local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Rules"))
-- Sibling server module. Resolved through the service tree rather than
-- script.Parent so the module works under both Rojo layouts: production maps
-- it beside MissionService in ServerScriptService, while the test project maps
-- it to ServerStorage so specs can require it without auto-running it.
--
-- The lookup is deferred to first use (not at require time) so the module loads
-- under either layout and under test harnesses that install globals later.
local ScoringCatalog: any = nil
local function scoringCatalog(): any
	if ScoringCatalog ~= nil then
		return ScoringCatalog
	end
	local services = { "ServerScriptService", "ServerStorage" }
	for _, serviceName in ipairs(services) do
		local service = game:GetService(serviceName)
		local found = service:FindFirstChild("ScoringCatalog")
		if found ~= nil then
			ScoringCatalog = require(found)
			return ScoringCatalog
		end
	end
	error("MissionService: ScoringCatalog module not found", 0)
end

local MissionService = {}

-- Bounds from the frozen v1 profile contract (docs/03).
local MAX_OWN_POSTS = 10
local MAX_CLAIMED_RUNS = 32
local MAX_CAMPAIGN_POSTS = 2
-- Frozen economy guard (docs/04): "stop growth before 1e12". A credit that
-- would bring either currency total to or past this bound is refused outright
-- rather than clamped, so no payout formula is altered and no partial
-- mutation can land. ProfileStore repeats the check as defense in depth.
local MAX_ECONOMIC_TOTAL = 1e12

-- PostMode and FitKind are declared locally to match the frozen GameTypes
-- unions ("organic" | "mission", "strong" | "weak") without a runtime
-- dependency on the shared module.
export type PostMode = "organic" | "mission"
export type FitKind = "strong" | "weak"

export type ResultCode =
	"OK"
	| "INVALID_INPUT"
	| "NOT_READY"
	| "ALREADY_DONE"
	| "LIMIT_REACHED"
	| "UNKNOWN_MISSION"
	| "UNKNOWN_TEMPLATE"
	| "UNKNOWN_CONTEXT"
	| "NO_ACTIVE_MISSION"
	| "MISSION_ACTIVE"
	| "PENDING_POST"
	| "NOT_DUE"
	| "NO_PENDING_POST"
	| "RUN_MISMATCH"
	| "INVALID_CONTENT"

export type OperationResult = {
	ok: boolean,
	code: ResultCode,
	detail: string?,
	profile: any?, -- proposed updated profile when ok
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
MissionService._deepCopy = deepCopy

local function isNonEmptyString(v: any): boolean
	return typeof(v) == "string" and #v > 0
end

-- Server time is injected by the caller (BS-04 supplies it). Only a finite,
-- nonnegative number is a valid server timestamp: NaN and both infinities are
-- rejected (Rules validates its numeric inputs the same way, src/shared/Rules),
-- and a negative timestamp cannot describe a published or settled post. A
-- non-finite `now` would otherwise produce a pending post with an infinite
-- settleAt that ProfileStore rejects far from its cause.
local function isValidServerTime(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= 0
end

local function findMission(missionId: any): any?
	if not isNonEmptyString(missionId) then
		return nil
	end
	for _, mission in ipairs(Catalog.Missions) do
		if (mission :: any).missionId == missionId then
			return mission
		end
	end
	return nil
end

-- Shipped-content gate. V0 must not expose M1 content early (docs/03:
-- "Respect Catalog.V0Shipped: unshipped M1 content cannot become available").
local function isShippedMission(missionId: string): boolean
	for _, id in ipairs(Catalog.V0Shipped.missionIds) do
		if id == missionId then
			return true
		end
	end
	return false
end

local function isShippedOrganicContext(contextId: string): boolean
	for _, id in ipairs(Catalog.V0Shipped.organicContextIds) do
		if id == contextId then
			return true
		end
	end
	return false
end

-- The equipped device's yield and reveal window. Posting always reads the ONE
-- productive profile.deviceId, never a terminal or client-supplied value
-- (docs/03).
local function deviceFor(profile: any): (number?, number?, string?)
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).id == profile.deviceId then
			return (device :: any).deviceYield, (device :: any).revealSeconds, nil
		end
	end
	return nil, nil, `unknown device {tostring(profile.deviceId)}`
end

-- Organic contexts available to this profile: only shipped ones, in catalog
-- order. V0 has exactly one, so the sequence is constant until BS-11.
local function shippedOrganicContexts(): { any }
	local out: { any } = {}
	for _, ctx in ipairs(Catalog.OrganicContexts) do
		if isShippedOrganicContext((ctx :: any).contextId) then
			table.insert(out, ctx)
		end
	end
	return out
end

-- Contexts available to a mission: only the ones the public Catalog lists for
-- it AND that are shipped. Rotation is `counter % #contexts`.
local function missionContexts(mission: any): { string }
	local out: { string } = {}
	for _, contextId in ipairs(mission.contexts) do
		table.insert(out, contextId)
	end
	return out
end

local function nextOrganicContext(profile: any): (any?, string?)
	local contexts = shippedOrganicContexts()
	if #contexts == 0 then
		return nil, "no shipped organic contexts"
	end
	local index = (profile.nextOrganicSequence % #contexts) + 1
	return contexts[index], nil
end

-- Freeze a pending post. The outcome is computed ONCE here and never recomputed
-- (docs/03: "compute and freeze final outcome on the server at publish").
-- `requiredImpact` is the B the post is scored against. Organic-only posts use
-- B=100 for presentation (docs/03); mission-tagged posts use the mission's own
-- requiredImpact, so a harder mission genuinely needs a stronger post.
local function buildPendingPost(
	profile: any,
	mode: PostMode,
	contextId: string,
	templateId: string,
	fit: FitKind,
	deviceYield: number,
	revealSeconds: number,
	now: number,
	missionRunId: string?,
	requiredImpact: number
): any
	local finalImpact = Rules.postImpact(requiredImpact, fit, deviceYield)
	local organicCuan = Rules.organicCuan(fit, deviceYield)
	local postId = `post-{profile.nextPostSequence}`
	return {
		postId = postId,
		mode = mode,
		missionRunId = missionRunId,
		contextId = contextId,
		templateId = templateId,
		publishedAt = now,
		settleAt = now + revealSeconds,
		finalImpact = finalImpact,
		organicCuan = organicCuan,
	}
end

-- A mission's own contexts are shipped with the mission itself; V0 ships one
-- mission with one context, so this is true for every catalogued mission
-- context. Kept as a named check so BS-11 can gate M1 contexts explicitly.
local function isMissionContextShipped(mission: any, contextId: string): boolean
	for _, id in ipairs((mission :: any).contexts) do
		if id == contextId then
			return true
		end
	end
	return false
end
MissionService._isMissionContextShipped = isMissionContextShipped

-- Mission-context tags come from ScoringCatalog's explicit server-owned
-- mapping. MissionDef in the public Catalog carries no trendId/audienceId, so
-- there is nothing to inherit and no default to fall back to: an unknown
-- context is a hard error, which keeps M1 content from silently scoring
-- against V0 tags.
local function missionContextTags(contextId: any): (string?, string?, string?)
	return scoringCatalog().missionContextTags(contextId)
end
MissionService._missionContextTags = missionContextTags

-- ===== AcceptMission =====
-- Validate against shipped catalog content and progression, require no active
-- mission, freeze the rotated context and the assigned run ID, and increment
-- the variant counter ONLY in the proposed state.
function MissionService.accept(profile: any, missionId: string, runId: string, now: number): OperationResult
	if not isNonEmptyString(missionId) or not isNonEmptyString(runId) then
		return fail("INVALID_INPUT", "missionId and runId are required")
	end
	if not isValidServerTime(now) then
		return fail("INVALID_INPUT", "now must be a finite nonnegative number")
	end
	if profile.activeMission ~= nil then
		return fail("MISSION_ACTIVE", "a mission is already active")
	end
	-- docs/02: "Accepting a mission while browsing or making organic posts is
	-- allowed." Accepting does not touch the single global pending-post slot, so
	-- an in-flight ORGANIC post must not block it. A mission-tagged post in
	-- flight does block it, because that post belongs to a run and accepting a
	-- new mission would orphan it.
	if profile.pendingPost ~= nil and profile.pendingPost.mode == "mission" then
		return fail("PENDING_POST", "a mission post is already resolving")
	end
	local mission = findMission(missionId)
	if mission == nil then
		return fail("UNKNOWN_MISSION", `unknown mission {missionId}`)
	end
	if not isShippedMission(missionId) then
		return fail("NOT_READY", `mission {missionId} is not shipped in V0`)
	end
	-- Progression gates from the catalog definition.
	if profile.completedMissions < mission.unlockClaims then
		return fail("NOT_READY", `mission {missionId} requires {mission.unlockClaims} prior claims`)
	end
	-- Tier gate from the catalog definition. The v1 profile persists no tier
	-- field, so eligibility is derived from the monotone inputs (docs/02 career
	-- table: tier requires BOTH lifetime earnings and completed claims) and
	-- clamped to the currently shipped tier cap. Spending never demotes, so the
	-- derivation is stable across a rejoin. V0's food_stall_launch has
	-- minTier = 0 and stays available at tier 0.
	local eligibleTier = Rules.eligibleTier(
		profile.lifetimeEarned,
		profile.completedMissions,
		Catalog.V0Shipped.maxShippedTier
	)
	if eligibleTier < (mission :: any).minTier then
		return fail(
			"NOT_READY",
			`mission {missionId} requires tier {(mission :: any).minTier}; eligible tier is {eligibleTier}`
		)
	end
	local contexts = missionContexts(mission)
	if #contexts == 0 then
		return fail("INVALID_CONTENT", `mission {missionId} has no contexts`)
	end
	-- Rotation from the SAVED counter, never rerolled on reopen or rejoin.
	local counter = profile.missionVariantCounters[missionId] or 0
	local index = (counter % #contexts) + 1
	local contextId = contexts[index]
	if not isShippedOrganicContext(contextId) and not isMissionContextShipped(mission, contextId) then
		return fail("NOT_READY", `context {contextId} is not shipped in V0`)
	end

	local next = deepCopy(profile)
	next.activeMission = {
		missionId = missionId,
		runId = runId,
		contextId = contextId,
		status = "accepted",
		accumulatedImpact = 0,
		postCount = 0,
	}
	-- The counter advances only in the successful proposed state.
	next.missionVariantCounters = deepCopy(profile.missionVariantCounters)
	next.missionVariantCounters[missionId] = counter + 1
	return ok(next)
end


-- ===== PublishOrganic =====
-- No mission required. Selects the next organic context from the saved
-- sequence, validates the template, freezes the outcome, and advances the
-- sequence only in the proposed state. Awards nothing at publish.
function MissionService.publishOrganic(profile: any, templateId: string, now: number): OperationResult
	if not isNonEmptyString(templateId) then
		return fail("INVALID_INPUT", "templateId is required")
	end
	if not isValidServerTime(now) then
		return fail("INVALID_INPUT", "now must be a finite nonnegative number")
	end
	if profile.pendingPost ~= nil then
		return fail("PENDING_POST", "a post is already resolving")
	end
	local context, ctxErr = nextOrganicContext(profile)
	if context == nil then
		return fail("UNKNOWN_CONTEXT", ctxErr)
	end
	local affinities = scoringCatalog().organicAffinities()[context.contextId]
	if affinities == nil then
		return fail("INVALID_CONTENT", `context {context.contextId} has no authored affinities`)
	end
	local fit, fitErr = scoringCatalog().fitForTemplate(
		templateId,
		context.templates,
		affinities,
		context.trendId,
		context.audienceId
	)
	if fit == nil then
		return fail("UNKNOWN_TEMPLATE", fitErr)
	end
	local deviceYield, revealSeconds, devErr = deviceFor(profile)
	if deviceYield == nil then
		return fail("INVALID_INPUT", devErr)
	end

	local next = deepCopy(profile)
	next.pendingPost = buildPendingPost(
		profile,
		"organic",
		context.contextId,
		templateId,
		fit,
		deviceYield,
		revealSeconds :: number,
		now,
		nil,
		-- Organic-only posts use B=100 for presentation (docs/03).
		100
	)
	next.nextPostSequence = profile.nextPostSequence + 1
	-- The organic sequence advances only on a successful publish.
	next.nextOrganicSequence = profile.nextOrganicSequence + 1
	return ok(next)
end

-- ===== PublishPost (mission-tagged) =====
-- Requires an active eligible mission and a matching run ID. Uses exactly the
-- same scoring, payout and settlement behaviour as organic posting, through the
-- one shared pending-post slot. Capped at two published posts per run.
function MissionService.publishMission(
	profile: any,
	runId: string,
	templateId: string,
	now: number
): OperationResult
	if not isNonEmptyString(runId) or not isNonEmptyString(templateId) then
		return fail("INVALID_INPUT", "runId and templateId are required")
	end
	if not isValidServerTime(now) then
		return fail("INVALID_INPUT", "now must be a finite nonnegative number")
	end
	if profile.pendingPost ~= nil then
		return fail("PENDING_POST", "a post is already resolving")
	end
	local mission = profile.activeMission
	if mission == nil then
		return fail("NO_ACTIVE_MISSION", "no active mission")
	end
	if mission.runId ~= runId then
		return fail("RUN_MISMATCH", "runId does not match the active mission")
	end
	-- The frozen cap: PublishPost admits while postCount < 2 (docs/03). Checked
	-- before the status so a third post reports the specific LIMIT_REACHED
	-- rather than a generic NOT_READY.
	if mission.postCount >= MAX_CAMPAIGN_POSTS then
		return fail("LIMIT_REACHED", "a mission run allows at most two campaign posts")
	end
	if mission.status ~= "accepted" and mission.status ~= "resolvingPost" then
		return fail("NOT_READY", `mission is {mission.status}`)
	end
	local missionDef = findMission(mission.missionId)
	if missionDef == nil then
		return fail("UNKNOWN_MISSION", `unknown mission {mission.missionId}`)
	end
	-- The template must belong to the mission's FROZEN context.
	local contextId = mission.contextId
	-- Resolve the tags first: an unknown context is the more specific and more
	-- actionable failure, and it must never fall back to V0 tags.
	local trendId, audienceId, tagErr = missionContextTags(contextId)
	if trendId == nil then
		return fail("UNKNOWN_CONTEXT", tagErr)
	end
	local affinities = scoringCatalog().missionAffinities()[contextId]
	if affinities == nil then
		return fail("INVALID_CONTENT", `context {contextId} has no authored affinities`)
	end
	local fit, fitErr = scoringCatalog().fitForTemplate(
		templateId,
		missionDef.templates,
		affinities,
		trendId,
		audienceId
	)
	if fit == nil then
		return fail("UNKNOWN_TEMPLATE", fitErr)
	end
	local deviceYield, revealSeconds, devErr = deviceFor(profile)
	if deviceYield == nil then
		return fail("INVALID_INPUT", devErr)
	end

	local next = deepCopy(profile)
	next.pendingPost = buildPendingPost(
		profile,
		"mission",
		contextId,
		templateId,
		fit,
		deviceYield,
		revealSeconds :: number,
		now,
		mission.runId,
		-- Mission-tagged posts score against the mission's own requirement.
		missionDef.requiredImpact
	)
	next.nextPostSequence = profile.nextPostSequence + 1
	-- postCount advances with the PUBLISH transition, not settlement
	-- (docs/03: the count and the pending post are one atomic write).
	next.activeMission = deepCopy(mission)
	next.activeMission.postCount = mission.postCount + 1
	next.activeMission.status = "resolvingPost"
	return ok(next)
end


-- ===== Settle =====
-- Consumes the frozen result. Requires now >= settleAt. Credits organic Cuan
-- once, adds the bounded own-post summary, clears the pending post, and for
-- mission posts adds impact and moves the mission status. A second settlement
-- after the pending post is consumed pays nothing.
function MissionService.settle(profile: any, now: number): OperationResult
	if not isValidServerTime(now) then
		return fail("INVALID_INPUT", "now must be a finite nonnegative number")
	end
	local pending = profile.pendingPost
	if pending == nil then
		return fail("NO_PENDING_POST", "no pending post to settle")
	end
	if now < pending.settleAt then
		return fail("NOT_DUE", `post settles at {pending.settleAt}`)
	end

	local next = deepCopy(profile)
	-- Credit the FROZEN organic payout exactly once.
	local nextBalance = profile.balance + pending.organicCuan
	local nextLifetime = profile.lifetimeEarned + pending.organicCuan
	-- Frozen economy guard (docs/04): refuse rather than clamp, so the payout
	-- formula is untouched and no partial mutation can land.
	if nextBalance >= MAX_ECONOMIC_TOTAL or nextLifetime >= MAX_ECONOMIC_TOTAL then
		return fail(
			"LIMIT_REACHED",
			`settlement would reach the {MAX_ECONOMIC_TOTAL} economy limit`
		)
	end
	next.balance = nextBalance
	next.lifetimeEarned = nextLifetime
	-- Bounded own-post summary (newest first, capped at 10).
	local summary = {
		postId = pending.postId,
		mode = pending.mode,
		contextId = pending.contextId,
		templateId = pending.templateId,
		finalImpact = pending.finalImpact,
		organicCuan = pending.organicCuan,
		publishedAt = pending.publishedAt,
		missionRunId = pending.missionRunId,
	}
	-- Retained summaries are DEEP COPIED from the input. `deepCopy(profile)`
	-- above already produced a private copy of ownPosts, but rebuilding the
	-- array from the input's tables would alias the caller's summaries into the
	-- proposal, so any later in-place edit would write through into the input
	-- profile. The module boundary (never mutates its input profile) requires
	-- the proposal to own every nested table.
	local ownPosts: { any } = { summary }
	for _, existing in ipairs(profile.ownPosts) do
		if #ownPosts < MAX_OWN_POSTS then
			table.insert(ownPosts, deepCopy(existing))
		end
	end
	next.ownPosts = ownPosts
	-- Clear the single global pending slot.
	next.pendingPost = nil

	if pending.mode == "mission" then
		local mission = profile.activeMission
		if mission == nil or mission.runId ~= pending.missionRunId then
			return fail("RUN_MISMATCH", "pending mission post has no matching active mission")
		end
		local missionDef = findMission(mission.missionId)
		if missionDef == nil then
			return fail("UNKNOWN_MISSION", `unknown mission {mission.missionId}`)
		end
		local updated = deepCopy(mission)
		updated.accumulatedImpact = mission.accumulatedImpact + pending.finalImpact
		if updated.accumulatedImpact >= missionDef.requiredImpact then
			updated.status = "readyToClaim"
		else
			-- Impact still short: back to accepted so a second post is allowed.
			updated.status = "accepted"
		end
		next.activeMission = updated
	end
	return ok(next)
end

-- ===== ClaimMission =====
-- Requires the matching active mission to be readyToClaim. Awards the fixed
-- catalog reward exactly once, records the run in the bounded claimed window,
-- and leaves the player free to accept another eligible mission.
function MissionService.claim(profile: any, runId: string): OperationResult
	if not isNonEmptyString(runId) then
		return fail("INVALID_INPUT", "runId is required")
	end
	local mission = profile.activeMission
	if mission == nil then
		return fail("NO_ACTIVE_MISSION", "no active mission")
	end
	if mission.runId ~= runId then
		return fail("RUN_MISMATCH", "runId does not match the active mission")
	end
	if mission.status ~= "readyToClaim" then
		return fail("NOT_READY", `mission is {mission.status}, not readyToClaim`)
	end
	local missionDef = findMission(mission.missionId)
	if missionDef == nil then
		return fail("UNKNOWN_MISSION", `unknown mission {mission.missionId}`)
	end
	-- Guard against a double claim even if the run was already recorded.
	for _, claimed in ipairs(profile.claimedRunIdsWindow) do
		if claimed == runId then
			return fail("ALREADY_DONE", "this run was already claimed")
		end
	end

	local next = deepCopy(profile)
	local nextBalance = profile.balance + missionDef.reward
	local nextLifetime = profile.lifetimeEarned + missionDef.reward
	-- Frozen economy guard (docs/04): refuse rather than clamp, so the fixed
	-- catalog reward is untouched and no partial mutation can land.
	if nextBalance >= MAX_ECONOMIC_TOTAL or nextLifetime >= MAX_ECONOMIC_TOTAL then
		return fail(
			"LIMIT_REACHED",
			`claim would reach the {MAX_ECONOMIC_TOTAL} economy limit`
		)
	end
	next.balance = nextBalance
	next.lifetimeEarned = nextLifetime
	next.completedMissions = profile.completedMissions + 1
	-- Bounded claimed-run window (<=32, newest last).
	local window: { string } = {}
	for _, claimed in ipairs(profile.claimedRunIdsWindow) do
		table.insert(window, claimed)
	end
	table.insert(window, runId)
	while #window > MAX_CLAIMED_RUNS do
		table.remove(window, 1)
	end
	next.claimedRunIdsWindow = window
	-- The mission is consumed; the player may accept another eligible one.
	next.activeMission = nil
	return ok(next)
end

MissionService.MAX_OWN_POSTS = MAX_OWN_POSTS
MissionService.MAX_CLAIMED_RUNS = MAX_CLAIMED_RUNS
MissionService.MAX_CAMPAIGN_POSTS = MAX_CAMPAIGN_POSTS

return MissionService
