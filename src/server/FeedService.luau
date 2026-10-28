--!strict
-- Buzzer Simulator — FeedService (BS-03, pure projection).
-- The fictional social feed ("Buzzline") projection. Deterministic, bounded,
-- and authored: no runtime AI, no free text, no user-generated comments, no
-- network requests, no per-NPC simulation loops.
--
-- V0 scope (docs/02, BS-03 backlog): six authored NPC feed cards, eight bounded
-- fictional NPC identity labels, and up to ten recent player-owned post
-- summaries projected from the saved profile.
--
-- PRIVACY: this module must never leak private scoring affinities or answer
-- keys. It reads only the public Catalog and the profile's own post summaries.
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))

local FeedService = {}

-- Bounds from the approved V0 scope.
local AUTHORED_NPC_CARDS = 6
local NPC_IDENTITY_LABELS = 8
local MAX_OWN_CARDS = 10

export type FeedCard = {
	cardId: string,
	kind: "authored" | "own",
	-- Presentation metadata for the future UI. Authored cards carry the NPC
	-- identity; own cards carry the player's frozen post result.
	npcName: string?,
	npcHandle: string?,
	contextId: string,
	templateId: string,
	body: string, -- authored copy only; never user text
	clueKey: string?, -- authored clue relevant to a supported posting context
	publishedAt: number,
	-- Engagement is DERIVED from frozen impact and timestamps, never random and
	-- never client-supplied.
	likes: number,
	replies: number,
	-- Own-card extras.
	finalImpact: number?,
	organicCuan: number?,
	mode: string?, -- presentation only; not a scoring input
}

-- Authored NPC identities. Exactly eight, fixed, fictional.
local NPC_IDENTITIES: { { name: string, handle: string } } = {
	{ name = "Rina Padukan", handle = "@rina.codes" },
	{ name = "Bagas Wibowo", handle = "@bagasfoodie" },
	{ name = "Sari Melati", handle = "@sari.melati" },
	{ name = "Dimas Anggara", handle = "@dimas.gadget" },
	{ name = "Nadia Puspita", handle = "@nadia.p" },
	{ name = "Fajar Ramadhan", handle = "@fajar.late" },
	{ name = "Laras Ayu", handle = "@laras.ayu" },
	{ name = "Yoga Pratama", handle = "@yoga.builds" },
}

-- Server-owned public clue keys for mission contexts.
--
-- MissionDef in the public Catalog has no clueKey field (only OrganicContextDef
-- does), so mission-context feed cards would otherwise carry no clue and become
-- undiscoverable. These are PUBLIC clue identifiers only -- they name the
-- authored clue, never the template affinity that decides the winner, so no
-- private scoring data is exposed. V0 ships one mission context; M1 clues are
-- added by BS-11 with their content.
local MISSION_CLUE_KEYS: { [string]: string } = {
	meal_time = "meal_time_clue",
}

-- Authored reply/comment pools. Bounded and fictional; never user text.
local REPLY_POOLS: { [string]: { string } } = {
	organic_snack = {
		"ini enak banget siang ini",
		"jajan anak kos keren",
		"kok bisa sekeren itu",
	},
	meal_time = {
		"laper gara gara ini",
		"menu siang favoritku",
		"antriannya legendendar",
	},
}

-- Authored NPC cards for V0. Six cards, each tied to a supported context so the
-- clue stays discoverable. Bodies are fixed authored copy.
local AUTHORED_CARDS: { {
	cardId: string,
	npcIndex: number,
	contextId: string,
	templateId: string,
	body: string,
	publishedAt: number,
} } = {
	{
		cardId = "npc-snack-1",
		npcIndex = 2,
		contextId = "organic_snack",
		templateId = "snack_meme",
		body = "Snack siang hari ini benar-benar menyelamatkan deadline.",
		publishedAt = 1000,
	},
	{
		cardId = "npc-snack-2",
		npcIndex = 5,
		contextId = "organic_snack",
		templateId = "snack_thread",
		body = "Thread singkat: tiga jajaran yang wajib dicoba bulan ini.",
		publishedAt = 1100,
	},
	{
		cardId = "npc-snack-3",
		npcIndex = 7,
		contextId = "organic_snack",
		templateId = "snack_honest",
		body = "Jujur saja, aku beli karena kemasannya lucu.",
		publishedAt = 1200,
	},
	{
		cardId = "npc-meal-1",
		npcIndex = 1,
		contextId = "meal_time",
		templateId = "meal_meme",
		body = "Waktu makan siang tiba dan semuanya berhenti sejenak.",
		publishedAt = 1300,
	},
	{
		cardId = "npc-meal-2",
		npcIndex = 4,
		contextId = "meal_time",
		templateId = "queue_thread",
		body = "Catatan dari meja depan: antrian terpanjang ada jam 12.15.",
		publishedAt = 1400,
	},
	{
		cardId = "npc-meal-3",
		npcIndex = 6,
		contextId = "meal_time",
		templateId = "late_night_quip",
		body = "Makan malam larut dengan satu porsi dan banyak cerita.",
		publishedAt = 1500,
	},
}

-- Deterministic engagement derived from frozen impact and the publish
-- timestamp. No randomness, so the same input always renders the same feed.
local function deriveEngagement(finalImpact: number, publishedAt: number): (number, number)
	local likes = math.floor(finalImpact / 10) + (publishedAt % 7)
	local replies = math.floor(likes / 4)
	return likes, replies
end

-- The authored clue key for a context, from the public Catalog. Keeps important
-- clue cards discoverable without exposing any private affinity data.
local function clueKeyFor(contextId: string): string?
	-- Organic contexts publish their clueKey in the public Catalog.
	for _, ctx in ipairs(Catalog.OrganicContexts) do
		if (ctx :: any).contextId == contextId then
			return (ctx :: any).clueKey
		end
	end
	-- Mission contexts carry a server-owned public clue key instead.
	return MISSION_CLUE_KEYS[contextId]
end

-- Authored NPC cards, projected. Bounded to AUTHORED_NPC_CARDS and ordered by
-- publishedAt so presentation is stable.
function FeedService.authoredCards(): { FeedCard }
	local cards: { FeedCard } = {}
	for _, authored in ipairs(AUTHORED_CARDS) do
		local a: any = authored
		if #cards >= AUTHORED_NPC_CARDS then
			break
		end
		local identity = NPC_IDENTITIES[a.npcIndex]
		local likes, replies = deriveEngagement(100, a.publishedAt)
		local card: FeedCard = {
			cardId = a.cardId,
			kind = "authored",
			npcName = identity.name,
			npcHandle = identity.handle,
			contextId = a.contextId,
			templateId = a.templateId,
			body = a.body,
			clueKey = clueKeyFor(a.contextId),
			publishedAt = a.publishedAt,
			likes = likes,
			replies = replies,
			finalImpact = nil,
			organicCuan = nil,
			mode = nil,
		}
		table.insert(cards, card)
	end
	table.sort(cards, function(a, b)
		return (a.publishedAt :: number) < (b.publishedAt :: number)
	end)
	return cards
end

-- The player's own recent posts, projected from the saved summaries. Bounded to
-- MAX_OWN_CARDS, newest first.
function FeedService.ownCards(profile: any): { FeedCard }
	local cards: { FeedCard } = {}
	if profile == nil or profile.ownPosts == nil then
		return cards
	end
	for _, summary in ipairs(profile.ownPosts) do
		if #cards >= MAX_OWN_CARDS then
			break
		end
		local s: any = summary
		local likes, replies = deriveEngagement(s.finalImpact, s.publishedAt)
		local card: FeedCard = {
			cardId = `own-{s.postId}`,
			kind = "own",
			npcName = nil,
			npcHandle = nil,
			contextId = s.contextId,
			templateId = s.templateId,
			body = "", -- own cards render from frozen results, never stored text
			clueKey = clueKeyFor(s.contextId),
			publishedAt = s.publishedAt,
			likes = likes,
			replies = replies,
			finalImpact = s.finalImpact,
			organicCuan = s.organicCuan,
			mode = if typeof(s.mode) == "string" then s.mode else nil,
		}
		table.insert(cards, card)
	end
	return cards
end

-- The combined bounded feed: authored cards plus the player's own, ordered by
-- publishedAt descending (newest first) with a stable authored/own tiebreak.
function FeedService.build(profile: any): { FeedCard }
	local combined: { FeedCard } = {}
	for _, card in ipairs(FeedService.authoredCards()) do
		table.insert(combined, card)
	end
	for _, card in ipairs(FeedService.ownCards(profile)) do
		table.insert(combined, card)
	end
	table.sort(combined, function(a, b)
		if (a.publishedAt :: number) == (b.publishedAt :: number) then
			-- Deterministic tiebreak: own posts surface above authored ones.
			if a.kind == b.kind then
				return (a.cardId :: string) < (b.cardId :: string)
			end
			return a.kind == "own"
		end
		return (a.publishedAt :: number) > (b.publishedAt :: number)
	end)
	return combined
end

-- Authored reply pool for a context. Bounded; used by the future UI only.
function FeedService.repliesFor(contextId: string): { string }
	local pool = REPLY_POOLS[contextId]
	if pool == nil then
		return {}
	end
	local out: { string } = {}
	for _, reply in ipairs(pool) do
		table.insert(out, reply)
	end
	return out
end

-- The bounded NPC identity labels, for UI attribution.
function FeedService.npcIdentities(): { { name: string, handle: string } }
	local out: { { name: string, handle: string } } = {}
	for i = 1, NPC_IDENTITY_LABELS do
		table.insert(out, NPC_IDENTITIES[i])
	end
	return out
end

FeedService.AUTHORED_NPC_CARDS = AUTHORED_NPC_CARDS
FeedService.NPC_IDENTITY_LABELS = NPC_IDENTITY_LABELS
FeedService.MAX_OWN_CARDS = MAX_OWN_CARDS

return FeedService
