--!strict
-- Public authored copy and deterministic projections; no scoring inputs or answer keys.
local Catalog = require(script.Parent:WaitForChild("Catalog"))

local Presentation = {}

export type FeedCard = {
	cardId: string,
	kind: "authored" | "own",
	npcName: string?,
	npcHandle: string?,
	contextId: string,
	templateId: string,
	body: string,
	clueKey: string?,
	clueText: string?,
	publishedAt: number,
	likes: number,
	replies: number,
	finalImpact: number?,
	organicCuan: number?,
	mode: string?,
}

local AUTHORED_NPC_CARDS = 6
local NPC_IDENTITY_LABELS = 8
local MAX_OWN_CARDS = 10

local NPC_IDENTITIES = {
	{ name = "Rina Padukan", handle = "@rina.codes" },
	{ name = "Bagas Wibowo", handle = "@bagasfoodie" },
	{ name = "Sari Melati", handle = "@sari.melati" },
	{ name = "Dimas Anggara", handle = "@dimas.gadget" },
	{ name = "Nadia Puspita", handle = "@nadia.p" },
	{ name = "Fajar Ramadhan", handle = "@fajar.late" },
	{ name = "Laras Ayu", handle = "@laras.ayu" },
	{ name = "Yoga Pratama", handle = "@yoga.builds" },
}

local MISSION_CLUE_KEYS: { [string]: string } = {
	meal_time = "meal_time_clue",
}
local CLUE_TEXTS: { [string]: string } = {
	organic_snack_clue = "Jajanan sore lagi rame di kalangan anak kos. Siapa yang paling bisa bikin mereka berhenti scrolling?",
	meal_time_clue = "Jam makan siang tiba dan warung mie di ujung jalan selalu penuh. Siapa yang paling bisa bikin antriannya kelihatan ramai?",
}

Presentation.Contexts = {
	organic_snack = {
		title = "Jajanan sore",
		trend = "Jajanan sore",
		audience = "Anak kos",
		clue = CLUE_TEXTS.organic_snack_clue,
	},
	meal_time = {
		title = "Jam makan siang",
		trend = "Makan siang di warung mie",
		audience = "Mahasiswa yang mencari makan siang",
		clue = CLUE_TEXTS.meal_time_clue,
	},
}

-- Composer copy is separate from the unchanged NPC feed copy.
Presentation.Templates = {
	snack_meme = {
		title = "Meme jajanan",
		body = "Deadline belum selesai, perut sudah minta rapat. Jajanan sore dulu, lanjut tugas kemudian.",
	},
	snack_thread = {
		title = "Thread jajanan",
		body = "Catatan jajanan sore: cek porsinya, bandingkan harganya, lalu ajak teman berbagi pilihan.",
	},
	snack_honest = {
		title = "Cerita jajan jujur",
		body = "Aku mampir karena bungkusnya lucu. Sekarang waktunya duduk sebentar dan menikmati jajanan ini.",
	},
	meal_meme = {
		title = "Meme jam makan",
		body = "Jam kuliah boleh padat, jadwal makan jangan lewat. Ketemu di Warung Mie Orbit pas perut mulai protes.",
	},
	queue_thread = {
		title = "Catatan antrean",
		body = "Catatan makan siang kantor: kumpulkan pesanan sebelum berangkat, lalu bergantian antre di Warung Mie Orbit.",
	},
	late_night_quip = {
		title = "Celetukan larut malam",
		body = "Shift selesai, cerita belum habis. Semangkuk mie di Warung Mie Orbit menemani obrolan malam ini.",
	},
}

Presentation.Missions = {
	food_stall_launch = {
		title = "Warung Mie Orbit",
		brief = "Buat postingan untuk warung mie fiksi ini. Baca tren, audiens, dan petunjuk run sebelum memilih template. Bonus misi diklaim terpisah dari Cuan postingan.",
	},
}
Presentation.Devices = {
	phone_cheap = "HP Hemat",
	phone_fast = "HP Cepat",
	pc_rumah = "PC Rumah",
}

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
local AUTHORED_CARDS = {
	{
		cardId = "npc-snack-1", npcIndex = 2, contextId = "organic_snack", templateId = "snack_meme",
		body = "Snack siang hari ini benar-benar menyelamatkan deadline.", publishedAt = 1000,
	},
	{
		cardId = "npc-snack-2", npcIndex = 5, contextId = "organic_snack", templateId = "snack_thread",
		body = "Thread singkat: tiga jajaran yang wajib dicoba bulan ini.", publishedAt = 1100,
	},
	{
		cardId = "npc-snack-3", npcIndex = 7, contextId = "organic_snack", templateId = "snack_honest",
		body = "Jujur saja, aku beli karena kemasannya lucu.", publishedAt = 1200,
	},
	{
		cardId = "npc-meal-1", npcIndex = 1, contextId = "meal_time", templateId = "meal_meme",
		body = "Waktu makan siang tiba dan semuanya berhenti sejenak.", publishedAt = 1300,
	},
	{
		cardId = "npc-meal-2", npcIndex = 4, contextId = "meal_time", templateId = "queue_thread",
		body = "Catatan dari meja depan: antrian terpanjang ada jam 12.15.", publishedAt = 1400,
	},
	{
		cardId = "npc-meal-3", npcIndex = 6, contextId = "meal_time", templateId = "late_night_quip",
		body = "Makan malam larut dengan satu porsi dan banyak cerita.", publishedAt = 1500,
	},
}

local function freezeDeep(value: any)
	for _, child in pairs(value) do
		if typeof(child) == "table" and not table.isfrozen(child) then
			freezeDeep(child)
		end
	end
	table.freeze(value)
end
for _, value in ipairs({
	NPC_IDENTITIES, MISSION_CLUE_KEYS, CLUE_TEXTS, REPLY_POOLS, AUTHORED_CARDS,
	Presentation.Contexts, Presentation.Templates, Presentation.Missions, Presentation.Devices,
}) do
	freezeDeep(value)
end

local function deriveEngagement(finalImpact: number, publishedAt: number): (number, number)
	local likes = math.floor(finalImpact / 10) + (publishedAt % 7)
	return likes, math.floor(likes / 4)
end

local function clueKeyFor(contextId: string): string?
	for _, context in ipairs(Catalog.OrganicContexts) do
		if context.contextId == contextId then
			return context.clueKey
		end
	end
	return MISSION_CLUE_KEYS[contextId]
end

local function clueTextFor(clueKey: string?): string?
	return if clueKey ~= nil then CLUE_TEXTS[clueKey] else nil
end

function Presentation.authoredCards(): { FeedCard }
	local cards: { FeedCard } = {}
	for _, authored in ipairs(AUTHORED_CARDS) do
		if #cards >= AUTHORED_NPC_CARDS then
			break
		end
		local identity = NPC_IDENTITIES[authored.npcIndex]
		local likes, replies = deriveEngagement(100, authored.publishedAt)
		local clueKey = clueKeyFor(authored.contextId)
		table.insert(cards, {
			cardId = authored.cardId, kind = "authored",
			npcName = identity.name, npcHandle = identity.handle,
			contextId = authored.contextId, templateId = authored.templateId,
			body = authored.body, clueKey = clueKey, clueText = clueTextFor(clueKey),
			publishedAt = authored.publishedAt, likes = likes, replies = replies,
		})
	end
	table.sort(cards, function(a, b)
		return a.publishedAt < b.publishedAt
	end)
	return cards
end

function Presentation.ownCards(profileOrSnapshot: any): { FeedCard }
	local cards: { FeedCard } = {}
	if profileOrSnapshot == nil or profileOrSnapshot.ownPosts == nil then
		return cards
	end
	for _, summary in ipairs(profileOrSnapshot.ownPosts) do
		if #cards >= MAX_OWN_CARDS then
			break
		end
		local s: any = summary
		local likes, replies = deriveEngagement(s.finalImpact, s.publishedAt)
		local clueKey = clueKeyFor(s.contextId)
		table.insert(cards, {
			cardId = `own-{s.postId}`, kind = "own",
			contextId = s.contextId, templateId = s.templateId,
			body = "", -- Preserve the server projection: UI resolves authored template copy by ID.
			clueKey = clueKey, clueText = clueTextFor(clueKey),
			publishedAt = s.publishedAt, likes = likes, replies = replies,
			finalImpact = s.finalImpact, organicCuan = s.organicCuan,
			mode = if typeof(s.mode) == "string" then s.mode else nil,
		})
	end
	return cards
end

function Presentation.build(profileOrSnapshot: any): { FeedCard }
	local combined = Presentation.authoredCards()
	for _, card in ipairs(Presentation.ownCards(profileOrSnapshot)) do
		table.insert(combined, card)
	end
	table.sort(combined, function(a, b)
		if a.publishedAt == b.publishedAt then
			if a.kind == b.kind then
				return a.cardId < b.cardId
			end
			return a.kind == "own"
		end
		return a.publishedAt > b.publishedAt
	end)
	return combined
end

function Presentation.repliesFor(contextId: string): { string }
	local pool = REPLY_POOLS[contextId]
	return if pool ~= nil then table.clone(pool) else {}
end

function Presentation.npcIdentities(): { { name: string, handle: string } }
	return table.clone(NPC_IDENTITIES)
end

Presentation.AUTHORED_NPC_CARDS = AUTHORED_NPC_CARDS
Presentation.NPC_IDENTITY_LABELS = NPC_IDENTITY_LABELS
Presentation.MAX_OWN_CARDS = MAX_OWN_CARDS

return table.freeze(Presentation)
