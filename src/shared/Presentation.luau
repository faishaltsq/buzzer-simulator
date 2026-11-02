--!strict
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

local AUTHORED_NPC_CARDS = 12
local NPC_IDENTITY_LABELS = 12
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
	{ name = "Maya Indah", handle = "@maya.market" },
	{ name = "Reza Kurnia", handle = "@reza.remix" },
	{ name = "Tari Lestari", handle = "@tari.culinary" },
	{ name = "Kevin Sanjaya", handle = "@kevin.gadgeteer" },
}

local MISSION_CLUE_KEYS: { [string]: string } = {
	meal_time = "meal_time_clue",
	office_lunch = "office_lunch_clue",
	late_snack = "late_snack_clue",
	demo_curious = "demo_curious_clue",
	collectors = "collectors_clue",
	desk_setup = "desk_setup_clue",
	weekend_plans = "weekend_plans_clue",
	bargain_hunters = "bargain_hunters_clue",
	food_walk = "food_walk_clue",
	before_after = "before_after_clue",
	nostalgia_wave = "nostalgia_wave_clue",
	honest_review = "honest_review_clue",
}

local CLUE_TEXTS: { [string]: string } = {
	organic_snack_clue = "Jajanan sore lagi rame di kalangan anak kos. Siapa yang paling bisa bikin mereka berhenti scrolling?",
	organic_gadget_clue = "Perangkat meja kerja baru lagi viral di forum teknologi. Ulasan mana yang paling menarik perhatian mereka?",
	organic_weekend_clue = "Warga kota mencari tempat santai untuk akhir pekan. Rekomendasi mana yang paling pas buat mereka?",
	meal_time_clue = "Jam makan siang tiba dan warung mie di ujung jalan selalu penuh. Siapa yang paling bisa bikin antriannya kelihatan ramai?",
	office_lunch_clue = "Pekerja kantor butuh makan siang cepat dan enak. Pesan apa yang paling bisa meyakinkan mereka mampir?",
	late_snack_clue = "Warung buka sampai tengah malam buat yang lembur. Format apa yang paling pas menemani malam mereka?",
	demo_curious_clue = "Mainan meja PipPod baru diperkenalkan ke publik. Gaya penyampaian apa yang bikin orang langsung paham fungsinya?",
	collectors_clue = "Para kolektor mencari keunikan detail PipPod edisi terbatas. Sudut pandang apa yang paling mereka hargai?",
	desk_setup_clue = "PipPod dipajang di setup meja kerja minimalis. Konten seperti apa yang menyatu sempurna dengan meja mereka?",
	weekend_plans_clue = "Pasar Neon mengumumkan jadwal buka akhir pekan ini. Informasi apa yang paling ditunggu pengunjung?",
	bargain_hunters_clue = "Banyak booth menawarkan harga spesial di Pasar Neon. Apa yang paling memikat pemburu diskon?",
	food_walk_clue = "Aroma makanan menggoda di sepanjang lorong Pasar Neon. Cerita apa yang bikin perut langsung lapar?",
	before_after_clue = "KokoPop berganti formula dan tampilan baru. Konten apa yang paling adil membandingkan rasa lama dan baru?",
	nostalgia_wave_clue = "Rasa klasik KokoPop membangkitkan kenangan masa sekolah. Cerita apa yang paling menyentuh ingatan mereka?",
	honest_review_clue = "Banyak klaim beredar tentang kemasan baru KokoPop. Ulasan seperti apa yang bisa dipercaya pembeli?",
}

Presentation.Contexts = {
	organic_snack = {
		title = "Jajanan sore",
		trend = "Jajanan sore",
		audience = "Anak kos",
		clue = CLUE_TEXTS.organic_snack_clue,
	},
	organic_gadget = {
		title = "Gadget meja kerja",
		trend = "Gadget meja kerja",
		audience = "Pecinta teknologi",
		clue = CLUE_TEXTS.organic_gadget_clue,
	},
	organic_weekend = {
		title = "Rencana akhir pekan",
		trend = "Wisata kota akhir pekan",
		audience = "Penjelajah kota",
		clue = CLUE_TEXTS.organic_weekend_clue,
	},
	meal_time = {
		title = "Jam makan siang",
		trend = "Makan siang di warung mie",
		audience = "Mahasiswa yang mencari makan siang",
		clue = CLUE_TEXTS.meal_time_clue,
	},
	office_lunch = {
		title = "Makan siang kantor",
		trend = "Makan siang di warung mie",
		audience = "Pekerja kantoran yang terburu-buru",
		clue = CLUE_TEXTS.office_lunch_clue,
	},
	late_snack = {
		title = "Makan larut malam",
		trend = "Jajanan larut malam",
		audience = "Pekerja shift dan penikmat malam",
		clue = CLUE_TEXTS.late_snack_clue,
	},
	demo_curious = {
		title = "Demo produk unik",
		trend = "Demo mainan meja interaktif",
		audience = "Pelajar yang penasaran",
		clue = CLUE_TEXTS.demo_curious_clue,
	},
	collectors = {
		title = "Edisi kolektor",
		trend = "Demo mainan meja interaktif",
		audience = "Kolektor miniatur dan gadget",
		clue = CLUE_TEXTS.collectors_clue,
	},
	desk_setup = {
		title = "Estetika meja kerja",
		trend = "Penataan meja kerja minimalis",
		audience = "Penggemar dekorasi meja",
		clue = CLUE_TEXTS.desk_setup_clue,
	},
	weekend_plans = {
		title = "Agenda Pasar Neon",
		trend = "Festival lampu dan pasar malam",
		audience = "Perencana akhir pekan",
		clue = CLUE_TEXTS.weekend_plans_clue,
	},
	bargain_hunters = {
		title = "Promo pasar malam",
		trend = "Festival lampu dan pasar malam",
		audience = "Pemburu promo dan diskon",
		clue = CLUE_TEXTS.bargain_hunters_clue,
	},
	food_walk = {
		title = "Wisata kuliner malam",
		trend = "Jelajah jajanan pasar malam",
		audience = "Pencinta kuliner malam",
		clue = CLUE_TEXTS.food_walk_clue,
	},
	before_after = {
		title = "Perubahan kemasan",
		trend = "Remix merek legendaris",
		audience = "Konsumen yang suka membandingkan",
		clue = CLUE_TEXTS.before_after_clue,
	},
	nostalgia_wave = {
		title = "Kenangan masa lalu",
		trend = "Remix merek legendaris",
		audience = "Penggemar rasa klasik nostalgia",
		clue = CLUE_TEXTS.nostalgia_wave_clue,
	},
	honest_review = {
		title = "Ulasan jujur produk",
		trend = "Ulasan jujur tanpa sponsor",
		audience = "Konsumen kritis dan skeptis",
		clue = CLUE_TEXTS.honest_review_clue,
	},
}

-- Composer copy is separate from the unchanged NPC feed copy.
Presentation.Templates = {
	-- organic_snack
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
	-- organic_gadget
	demo_bit = {
		title = "Cuplikan demo gadget",
		body = "Tiga detik melihat cara kerjanya, langsung paham kenapa gadget meja ini bikin nagih.",
	},
	specs_breakdown = {
		title = "Rincian spesifikasi",
		body = "Bedah spesifikasi ringkas: daya tahan baterai, bahan bodi, dan fungsi tombol utamanya.",
	},
	daily_driver = {
		title = "Pengalaman harian",
		body = "Setelah seminggu di atas meja kerja, perangkat ini jadi bagian penting dari rutinitas harian.",
	},
	-- organic_weekend
	weekend_vlog_text = {
		title = "Vlog teks akhir pekan",
		body = "Sabtu pagi jalan santai tanpa tujuan, berakhir di sudut kota yang tenang dan teduh.",
	},
	chill_spot_recs = {
		title = "Rekomendasi tempat santai",
		body = "Tiga tempat santai pilihan minggu ini: kopi enak, angin semilir, dan bebas bising kendaraan.",
	},
	local_roundup = {
		title = "Rangkuman lokal",
		body = "Rangkuman agenda seru kota akhir pekan ini untuk kamu yang ingin keluar rumah sejenak.",
	},
	-- food_stall_launch
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
	-- fictional_gadget
	demo_joke = {
		title = "Celetukan demo PipPod",
		body = "Beli PipPod niatnya buat hiasan meja, ujung-ujungnya malah dimainkan sepanjang rapat kerja.",
	},
	collector_thread = {
		title = "Thread koleksi PipPod",
		body = "Detail edisi pertama PipPod: material matte, nomor seri khusus, dan alasan layak disimpan.",
	},
	setup_thread = {
		title = "Tips penataan meja PipPod",
		body = "Menata PipPod di sudut monitor kerja agar kabel rapi dan meja tetap terlihat bersih minimalis.",
	},
	-- neon_market
	event_thread = {
		title = "Panduan Pasar Neon",
		body = "Panduan lengkap keliling Pasar Neon: waktu terbaik datang, lokasi parkir, dan rute anti-macet.",
	},
	price_list = {
		title = "Daftar harga promo",
		body = "Daftar menu dan jajanan di bawah dua puluh rupiah yang wajib kamu buru di Pasar Neon.",
	},
	food_map = {
		title = "Peta kuliner malam",
		body = "Peta rute kuliner lorong Pasar Neon: dari camilan gurih di pintu masuk sampai es segar di ujung barat.",
	},
	-- brand_remix
	comparison_thread = {
		title = "Banding rasa KokoPop",
		body = "Perbandingan langsung formula lama vs kemasan baru KokoPop: lebih gurih dan renyah tahan lama.",
	},
	nostalgia_story = {
		title = "Cerita nostalgia KokoPop",
		body = "Rasa cemilan yang dulu selalu ada di kantin sekolah kini hadir lagi dengan kenangan manisnya.",
	},
	review_thread = {
		title = "Ulasan jujur KokoPop",
		body = "Ulasan tanpa sponsor: uji rasa, tekstur kemasan, dan apakah sepadan dengan harganya.",
	},
}

Presentation.Missions = {
	food_stall_launch = {
		title = "Warung Mie Orbit",
		brief = "Buat postingan untuk warung mie fiksi ini. Baca tren, audiens, dan petunjuk run sebelum memilih template. Bonus misi diklaim terpisah dari Cuan postingan.",
	},
	fictional_gadget = {
		title = "PipPod Desk Toy",
		brief = "Rancang postingan promosi untuk mainan meja fiksi PipPod. Perhatikan tren demo dan minat audiens sebelum memilih template kampanye.",
	},
	neon_market = {
		title = "Pasar Neon",
		brief = "Bantu keramaian festival pasar malam Pasar Neon. Sesuaikan sudut pandang acara, promo, atau kuliner dengan audiens target.",
	},
	brand_remix = {
		title = "KokoPop Remix",
		brief = "Luncurkan kembali brand legendaris KokoPop dengan sentuhan modern. Pilih antara perbandingan kemasan, nostalgia, atau ulasan jujur.",
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
	organic_gadget = {
		"gadget meja idaman",
		"keren banget setupnya",
		"pengen punya satu",
	},
	organic_weekend = {
		"akhir pekan seru",
		"rekomendasi mantap",
		"besok langsung ke sana",
	},
	meal_time = {
		"laper gara gara ini",
		"menu siang favoritku",
		"antriannya legendendar",
	},
	office_lunch = {
		"cocok buat makan siang kantor",
		"porsi pas buat istirahat",
		"langsung pesan sekarang",
	},
	late_snack = {
		"pas banget buat yang lembur",
		"menu malam andalan",
		"bikin melek lagi",
	},
	demo_curious = {
		"lucu banget mainannya",
		"cara kerjanya unik",
		"menarik buat dicoba",
	},
	collectors = {
		"wajib masuk koleksi",
		"detailnya rapi banget",
		"edisi terbatas keren",
	},
	desk_setup = {
		"setup meja jadi estetik",
		"rapi dan minimalis",
		"inspirasi meja kerja",
	},
	weekend_plans = {
		"jadwal akhir pekan terselamatkan",
		"siap berangkat malam ini",
		"tempatnya kelihatan seru",
	},
	bargain_hunters = {
		"promonya menarik banget",
		"hemat tapi kenyang",
		"ramah di kantong",
	},
	food_walk = {
		"wajib cobain semua",
		"aromanya sampai sini",
		"kuliner malam terenak",
	},
	before_after = {
		"perubahannya kelihatan jelas",
		"kemasan baru lebih keren",
		"rasanya tetap enak",
	},
	nostalgia_wave = {
		"teringat masa sekolah",
		"rasa klasik yang ngangenin",
		"bikin nostalgia",
	},
	honest_review = {
		"ulasan yang informatif",
		"terpercaya penjelasannya",
		"membantu sebelum beli",
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
	{
		cardId = "npc-gadget-1", npcIndex = 8, contextId = "organic_gadget", templateId = "demo_bit",
		body = "Setup meja kerja minimalis tapi produktivitas maksimal.", publishedAt = 1600,
	},
	{
		cardId = "npc-weekend-1", npcIndex = 3, contextId = "organic_weekend", templateId = "local_roundup",
		body = "Rekomendasi tempat santai akhir pekan ini yang jarang orang tahu.", publishedAt = 1700,
	},
	{
		cardId = "npc-pip-1", npcIndex = 12, contextId = "demo_curious", templateId = "demo_joke",
		body = "Mainan meja kecil ini ternyata bikin fokus seharian.", publishedAt = 1800,
	},
	{
		cardId = "npc-market-1", npcIndex = 9, contextId = "weekend_plans", templateId = "event_thread",
		body = "Pasar Neon buka malam ini, ada banyak jajanan dan lampu estetik.", publishedAt = 1900,
	},
	{
		cardId = "npc-remix-1", npcIndex = 10, contextId = "before_after", templateId = "comparison_thread",
		body = "Kemasan baru atau lama? Menurutku versi terbaru jauh lebih segar.", publishedAt = 2000,
	},
	{
		cardId = "npc-walk-1", npcIndex = 11, contextId = "food_walk", templateId = "food_map",
		body = "Peta kuliner malam: mulai dari ujung barat sampai gerbang timur.", publishedAt = 2100,
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
		local likes, replies = deriveEngagement(s.finalImpact or 0, s.publishedAt or 0)
		local clueKey = clueKeyFor(s.contextId)
		table.insert(cards, {
			cardId = `own-{s.postId}`, kind = "own",
			contextId = s.contextId, templateId = s.templateId,
			body = "", -- Preserve the server projection: UI resolves authored template copy by ID.
			clueKey = clueKey, clueText = clueTextFor(clueKey),
			publishedAt = s.publishedAt or 0, likes = likes, replies = replies,
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

Presentation.combinedFeed = Presentation.build

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
