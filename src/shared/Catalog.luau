--!strict
-- Buzzer Simulator — Catalog (BS-01, V0 public catalog; numeric source: docs/04,
-- content IDs: docs/02). Public read-only data ONLY: no trend/audience affinity
-- tags, no answer keys — those live server-side in ScoringCatalog (BS-03).
-- V0 ships one mission context and one organic context; v1 shape supports M1
-- expansion without migration. IDs and ordering are stable for saved runs.

local Catalog = {}

export type DeviceDef = {
	id: string,
	order: number, -- exact-next purchase order: cheaper phones first, then PC
	price: number, -- nonnegative integer Cuan
	deviceYield: number, -- positive finite multiplier, never stacks
	revealSeconds: number, -- 18 / 16 / 13
	modelId: string, -- world prefab model key (mapped from BS-05 onward)
	isPhone: boolean,
}

export type MissionDef = {
	missionId: string,
	requiredImpact: number, -- 100/130/160/220
	reward: number, -- fixed bonus on claim, once per run
	minTier: number,
	unlockClaims: number, -- prior claims required (0 for intro)
	templates: { string }, -- exactly 3 authored template IDs
	contexts: { string }, -- context IDs (V0: first only; M1: 3)
}

export type OrganicContextDef = {
	contextId: string,
	trendId: string,
	audienceId: string,
	clueKey: string,
	templates: { string }, -- exactly 3 authored template IDs
}

export type TierDef = {
	tier: number,
	name: string,
	lifetimeRequired: number,
	claimsRequired: number,
}

-- V0: cheap phone is the productive starter (yield 1.00, 18s reveal); fast
-- phone 50 Cuan (1.60, 16s). PC Rumah is M1 catalog data (planned 220 / 2.50 /
-- 13); V0 shipped cap prevents purchase until BS-11 owns M1 content release.
local Devices: { DeviceDef } = {
	{
		id = "phone_cheap",
		order = 1,
		price = 0,
		deviceYield = 1.00,
		revealSeconds = 18,
		modelId = "PhoneCheap",
		isPhone = true,
	},
	{
		id = "phone_fast",
		order = 2,
		price = 50,
		deviceYield = 1.60,
		revealSeconds = 16,
		modelId = "PhoneFast",
		isPhone = true,
	},
	{
		id = "pc_rumah",
		order = 3,
		price = 220,
		deviceYield = 2.50,
		revealSeconds = 13,
		modelId = "PCRumah",
		isPhone = false,
	},
}

Catalog.Devices = Devices

local Tiers: { TierDef } = {
	{ tier = 0, name = "Buzzer Gabut", lifetimeRequired = 0, claimsRequired = 0 },
	{ tier = 1, name = "Buzzer Rumahan", lifetimeRequired = 300, claimsRequired = 3 },
	{ tier = 2, name = "Studio Rumahan", lifetimeRequired = 1600, claimsRequired = 3 },
}
Catalog.Tiers = Tiers

-- V0 mission inventory: `food_stall_launch` only. Contexts list order is the
-- rotation order (counter % n); first run always uses contexts[1] = "meal_time".
local Missions: { MissionDef } = {
	{
		missionId = "food_stall_launch",
		requiredImpact = 100,
		reward = 80,
		minTier = 0,
		unlockClaims = 0,
		templates = { "meal_meme", "queue_thread", "late_night_quip" },
		contexts = { "meal_time" },
	},
}

-- M1 planned missions live in docs/02; they are added to this table by BS-11
-- with their own three contexts and reviewed affinities in ScoringCatalog.
Catalog.Missions = Missions

-- V0 organic context: `organic_snack` only. Sequence selects by
-- nextOrganicSequence % #OrganicContexts (V0: constant "organic_snack").
local OrganicContexts: { OrganicContextDef } = {
	{
		contextId = "organic_snack",
		trendId = "snack_trend",
		audienceId = "students",
		clueKey = "organic_snack_clue",
		templates = { "snack_meme", "snack_thread", "snack_honest" },
	},
}
Catalog.OrganicContexts = OrganicContexts

-- in this file stay gated behind BS-11 content release):
Catalog.V0Shipped = {
	missionIds = { "food_stall_launch" },
	organicContextIds = { "organic_snack" },
	deviceIds = { "phone_cheap", "phone_fast" },
	maxShippedTier = 0,
}

-- Validate structural invariants (BS-01 acceptance): IDs unique, order exact,
-- counts exact, tier gates consistent. Pure; no affinities touched.
function Catalog.validate(): (boolean, { string })
	local problems: { string } = {}
	local seenDevice: { [string]: boolean } = {}
	local lastOrder = 0
	for i, device in ipairs(Catalog.Devices) do
		if seenDevice[device.id] then
			table.insert(problems, `duplicate device id {device.id}`)
		end
		seenDevice[device.id] = true
		if device.order ~= i then
			table.insert(problems, `device {device.id} order {device.order} != index {i}`)
		end
		if device.order <= lastOrder then
			table.insert(problems, `device order not ascending at {device.id}`)
		end
		lastOrder = device.order
		if not (device.price >= 0 and device.price % 1 == 0) then
			table.insert(problems, `device {device.id} price must be nonnegative integer`)
		end
		if not (device.deviceYield > 0 and device.deviceYield == device.deviceYield and device.deviceYield ~= math.huge) then
			table.insert(problems, `device {device.id} yield must be positive finite`)
		end
		if not (device.revealSeconds > 0 and device.revealSeconds % 1 == 0) then
			table.insert(problems, `device {device.id} revealSeconds must be positive integer`)
		end
	end
	if #Catalog.Devices < 2 then
		table.insert(problems, "expected at least cheap and fast phone in Devices")
	end

	local seenMission: { [string]: boolean } = {}
	for _, mission in ipairs(Catalog.Missions) do
		if seenMission[mission.missionId] then
			table.insert(problems, `duplicate mission id {mission.missionId}`)
		end
		seenMission[mission.missionId] = true
		if #mission.templates ~= 3 then
			table.insert(problems, `mission {mission.missionId} must have exactly 3 templates`)
		end
		local tSeen: { [string]: boolean } = {}
		for _, t in ipairs(mission.templates) do
			if tSeen[t] then
				table.insert(problems, `mission {mission.missionId} duplicate template {t}`)
			end
			tSeen[t] = true
		end
		if #mission.contexts < 1 then
			table.insert(problems, `mission {mission.missionId} needs >=1 context`)
		end
		local cSeen: { [string]: boolean } = {}
		for _, c in ipairs(mission.contexts) do
			if cSeen[c] then
				table.insert(problems, `mission {mission.missionId} duplicate context {c}`)
			end
			cSeen[c] = true
		end
		if mission.requiredImpact % 1 ~= 0 or mission.requiredImpact <= 0 then
			table.insert(problems, `mission {mission.missionId} requiredImpact must be positive integer`)
		end
		if mission.reward % 1 ~= 0 or mission.reward <= 0 then
			table.insert(problems, `mission {mission.missionId} reward must be positive integer`)
		end
	end

	local seenContext: { [string]: boolean } = {}
	for _, ctx in ipairs(Catalog.OrganicContexts) do
		if seenContext[ctx.contextId] then
			table.insert(problems, `duplicate organic context id {ctx.contextId}`)
		end
		seenContext[ctx.contextId] = true
		if #ctx.templates ~= 3 then
			table.insert(problems, `organic context {ctx.contextId} must have exactly 3 templates`)
		end
		local tSeen: { [string]: boolean } = {}
		for _, t in ipairs(ctx.templates) do
			if tSeen[t] then
				table.insert(problems, `organic context {ctx.contextId} duplicate template {t}`)
			end
			tSeen[t] = true
		end
	end

	local seenTier: { [number]: boolean } = {}
	for _, tier in ipairs(Catalog.Tiers) do
		if seenTier[tier.tier] then
			table.insert(problems, `duplicate tier {tier.tier}`)
		end
		seenTier[tier.tier] = true
	end
	if Catalog.Tiers[1] == nil or Catalog.Tiers[1].lifetimeRequired ~= 0 then
		table.insert(problems, "tier 0 must start at lifetimeRequired 0")
	end

	if #Catalog.V0Shipped.missionIds == 0 or #Catalog.V0Shipped.organicContextIds == 0 then
		table.insert(problems, "V0 must ship one mission context and one organic context")
	end

	return #problems == 0, problems
end

return Catalog