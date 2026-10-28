--!strict
-- Buzzer Simulator — ScoringCatalog (BS-03, server-only).
-- Private authored template relevance. NEVER replicated to clients: the public
-- Catalog deliberately carries no affinity tags, and this module is the only
-- place the answer key lives (docs/03: "Private `ScoringCatalog` in
-- ServerScriptService stores the authored trend/audience template affinities").
--
-- Score = 2 * trendMatch + audienceMatch, each match 0 or 1 (docs/03). Exactly
-- one template per context must hold the highest score; a tie or a missing
-- winner is invalid authored content and is rejected at load, never resolved
-- by a random tiebreak. There is no per-post RNG.
--
-- The interface is context-keyed and takes its content by injection, so M1 can
-- add contexts and missions without changing the scoring surface.
-- FitKind is declared locally rather than imported from GameTypes: this module
-- is pure and dependency-free, and the values are identical to the frozen
-- GameTypes.FitKind union ("strong" | "weak").
export type FitKind = "strong" | "weak"

local ScoringCatalog = {}

export type Affinity = {
	trendId: string,
	audienceId: string,
}

-- Authored private affinities. A template's relevance to a context comes from
-- how its trend and audience tags line up with the context's own tags. V0
-- ships exactly one organic context and one mission context; M1 content is
-- added here when BS-11 owns its release.
local ORGANIC_AFFINITIES: { [string]: Affinity } = {
	-- organic_snack: trend snack_trend, audience students.
	-- snack_meme matches BOTH -> 2*1 + 1 = 3 (unique strong).
	snack_meme = { trendId = "snack_trend", audienceId = "students" },
	-- snack_thread matches trend only -> 2.
	snack_thread = { trendId = "snack_trend", audienceId = "office_workers" },
	-- snack_honest matches audience only -> 1.
	snack_honest = { trendId = "late_night_trend", audienceId = "students" },
}

local MISSION_AFFINITIES: { [string]: Affinity } = {
	-- meal_time: trend snack_trend, audience students (same tags as the V0
	-- organic context, so the authored winners differ by template set).
	-- meal_meme matches BOTH -> 3 (unique strong).
	meal_meme = { trendId = "snack_trend", audienceId = "students" },
	-- queue_thread matches trend only -> 2.
	queue_thread = { trendId = "snack_trend", audienceId = "office_workers" },
	-- late_night_quip matches audience only -> 1.
	late_night_quip = { trendId = "late_night_trend", audienceId = "students" },
}

-- M1-style fixtures used only by tests, to prove context rotation picks a
-- different winner per context without shipping M1 content.
ScoringCatalog.TestFixtures = {
	organic = {
		organic_snack = ORGANIC_AFFINITIES,
		-- A second organic context whose tags make a DIFFERENT template win.
		organic_gadget = {
			demo_curious = { trendId = "gadget_trend", audienceId = "students" },
			demo_joke = { trendId = "gadget_trend", audienceId = "office_workers" },
			demo_thread = { trendId = "snack_trend", audienceId = "students" },
		},
	},
	mission = {
		meal_time = MISSION_AFFINITIES,
		neon_market = {
			weekend_plans = { trendId = "market_trend", audienceId = "students" },
			event_thread = { trendId = "market_trend", audienceId = "office_workers" },
			neon_quip = { trendId = "snack_trend", audienceId = "students" },
		},
	},
}

-- Score one template against a context's tags. Pure; no randomness.
function ScoringCatalog.scoreTemplate(
	affinity: Affinity,
	contextTrendId: string,
	contextAudienceId: string
): number
	local trendMatch = if affinity.trendId == contextTrendId then 1 else 0
	local audienceMatch = if affinity.audienceId == contextAudienceId then 1 else 0
	return 2 * trendMatch + audienceMatch
end

-- Resolve the unique strong template for a context.
-- `affinities` maps templateId -> Affinity for exactly the templates the public
-- Catalog lists for this context. Returns (templateId, nil) on success or
-- (nil, reason) when the authored content is invalid: a missing affinity, a
-- tie, or no winner at all. Never guesses and never randomises.
function ScoringCatalog.resolveStrongTemplate(
	templateIds: { string },
	affinities: { [string]: Affinity },
	contextTrendId: string,
	contextAudienceId: string
): (string?, string?)
	if #templateIds == 0 then
		return nil, "context has no templates"
	end
	local bestId: string? = nil
	local bestScore = -1
	local tied = false
	for _, templateId in ipairs(templateIds) do
		local affinity = affinities[templateId]
		if affinity == nil then
			return nil, `template {templateId} has no authored affinity`
		end
		local score = ScoringCatalog.scoreTemplate(affinity, contextTrendId, contextAudienceId)
		if score > bestScore then
			bestScore = score
			bestId = templateId
			tied = false
		elseif score == bestScore then
			tied = true
		end
	end
	if bestId == nil then
		return nil, "no winning template"
	end
	if tied then
		return nil, `tie for the strong template in context (score {bestScore})`
	end
	return bestId, nil
end

-- Determine the fit of a chosen template for a context. The unique strong
-- template is "strong"; every other authored template is "weak". Returns
-- (fit, nil) or (nil, reason) for unknown templates or invalid content.
function ScoringCatalog.fitForTemplate(
	templateId: string,
	templateIds: { string },
	affinities: { [string]: Affinity },
	contextTrendId: string,
	contextAudienceId: string
): (FitKind?, string?)
	local known = false
	for _, id in ipairs(templateIds) do
		if id == templateId then
			known = true
			break
		end
	end
	if not known then
		return nil, `template {templateId} does not belong to this context`
	end
	local strongId, resolveErr = ScoringCatalog.resolveStrongTemplate(
		templateIds,
		affinities,
		contextTrendId,
		contextAudienceId
	)
	if strongId == nil then
		return nil, resolveErr or "context has no unique strong template"
	end
	return if templateId == strongId then "strong" else "weak", nil
end

-- ===== content validation (reject at load, per BS-03 constraints) =====
-- Verifies every shipped context in the public Catalog has a unique winner
-- against the private affinities. `contexts` is the list of OrganicContextDef
-- or MissionDef-shaped tables to check; `affinitySets` maps contextId ->
-- affinity table. Returns (ok, problems).
-- `entries` may be either shape:
--   * an OrganicContextDef -- has contextId, trendId, audienceId, templates;
--   * a MissionDef -- has missionId and a `contexts` array, whose tags come
--     from the matching organic context (V0's meal_time shares the snack
--     context's tags).
-- Both shapes are validated so a tie or missing winner is rejected at load.
function ScoringCatalog.validateContent(
	entries: { any },
	affinitySets: { [string]: { [string]: Affinity } },
	tagLookup: ((string) -> (string, string))? 
): (boolean, { string })
	local problems: { string } = {}
	local lookup: (string) -> (string, string) = tagLookup or function(_contextId: string)
		return "snack_trend", "students"
	end
	for _, entry in ipairs(entries) do
		local e: any = entry
		if e.contextId ~= nil then
			-- Organic context shape.
			local affinities = affinitySets[e.contextId]
			if affinities == nil then
				table.insert(problems, `context {e.contextId} has no authored affinity set`)
			elseif e.trendId == nil or e.audienceId == nil then
				table.insert(problems, `context {e.contextId} is missing trendId or audienceId`)
			else
				local _, err = ScoringCatalog.resolveStrongTemplate(
					e.templates,
					affinities,
					e.trendId,
					e.audienceId
				)
				if err ~= nil then
					table.insert(problems, `context {e.contextId}: {err}`)
				end
			end
		elseif e.missionId ~= nil then
			-- Mission shape: validate every context it lists.
			for _, contextId in ipairs((e.contexts or {}) :: { string }) do
				local affinities = affinitySets[contextId :: string]
				if affinities == nil then
					table.insert(problems, `mission {e.missionId} context {contextId} has no authored affinity set`)
				else
					local trendId, audienceId = lookup(contextId)
					local _, err = ScoringCatalog.resolveStrongTemplate(
						e.templates,
						affinities,
						trendId,
						audienceId
					)
					if err ~= nil then
						table.insert(problems, `mission {e.missionId} context {contextId}: {err}`)
					end
				end
			end
		else
			table.insert(problems, "content entry has neither contextId nor missionId")
		end
	end
	return #problems == 0, problems
end

-- V0 shipped content, resolved against the private affinities. Used by
-- MissionService and by tests.
function ScoringCatalog.organicAffinities(): { [string]: { [string]: Affinity } }
	return {
		organic_snack = ORGANIC_AFFINITIES,
	}
end

function ScoringCatalog.missionAffinities(): { [string]: { [string]: Affinity } }
	return {
		meal_time = MISSION_AFFINITIES,
	}
end

return ScoringCatalog
