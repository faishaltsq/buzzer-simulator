--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Presentation = require(Shared:WaitForChild("Presentation"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local FeedService = require(game:GetService("ServerStorage"):WaitForChild("FeedService"))

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end
local function equal(actual: any, expected: any, label: string)
	if typeof(actual) ~= "table" or typeof(expected) ~= "table" then
		assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
		return
	end
	for key, value in pairs(expected) do
		equal(actual[key], value, `{label}.{tostring(key)}`)
	end
	for key in pairs(actual) do
		assert(expected[key] ~= nil, `{label}: unexpected field {tostring(key)}`)
	end
end
local function summary(id: string, time: number, impact: number?): any
	return {
		postId = id, mode = "organic", contextId = "organic_snack", templateId = "snack_thread",
		publishedAt = time, finalImpact = impact or 120, organicCuan = 15,
	}
end

-- Literal compatibility fixtures protect the extraction, including existing authored wording.
test("Shared authored cards preserve all six existing public projections", function()
	local expected = {
		{ "npc-snack-1", "Bagas Wibowo", "@bagasfoodie", "organic_snack", "snack_meme", "Snack siang hari ini benar-benar menyelamatkan deadline.", 1000, 16, 4 },
		{ "npc-snack-2", "Nadia Puspita", "@nadia.p", "organic_snack", "snack_thread", "Thread singkat: tiga jajaran yang wajib dicoba bulan ini.", 1100, 11, 2 },
		{ "npc-snack-3", "Laras Ayu", "@laras.ayu", "organic_snack", "snack_honest", "Jujur saja, aku beli karena kemasannya lucu.", 1200, 13, 3 },
		{ "npc-meal-1", "Rina Padukan", "@rina.codes", "meal_time", "meal_meme", "Waktu makan siang tiba dan semuanya berhenti sejenak.", 1300, 15, 3 },
		{ "npc-meal-2", "Dimas Anggara", "@dimas.gadget", "meal_time", "queue_thread", "Catatan dari meja depan: antrian terpanjang ada jam 12.15.", 1400, 10, 2 },
		{ "npc-meal-3", "Fajar Ramadhan", "@fajar.late", "meal_time", "late_night_quip", "Makan malam larut dengan satu porsi dan banyak cerita.", 1500, 12, 3 },
	}
	local cards = Presentation.authoredCards()
	equal(#cards, 6, "authored count")
	local names = {}
	for index, fixture in ipairs(expected) do
		local context = fixture[4]
		equal(cards[index], {
			cardId = fixture[1], kind = "authored", npcName = fixture[2], npcHandle = fixture[3],
			contextId = context, templateId = fixture[5], body = fixture[6], publishedAt = fixture[7],
			likes = fixture[8], replies = fixture[9],
			clueKey = if context == "organic_snack" then "organic_snack_clue" else "meal_time_clue",
			clueText = (Presentation.Contexts :: any)[context].clue,
		}, `authored {index}`)
		assert(not names[cards[index].npcName], "each card has a distinct fictional NPC")
		names[cards[index].npcName] = true
	end
	equal(Presentation.AUTHORED_NPC_CARDS, 6, "authored bound")
	equal(Presentation.NPC_IDENTITY_LABELS, 8, "identity bound")
	equal(#Presentation.npcIdentities(), 8, "identity inventory")
end)

test("Every shipped context, template, mission and device has only public display copy", function()
	local expectedContexts = { organic_snack = true, meal_time = true }
	local expectedTemplates = {}
	for _, context in ipairs(Catalog.OrganicContexts) do
		for _, id in ipairs(context.templates) do
			expectedTemplates[id] = true
		end
	end
	for _, mission in ipairs(Catalog.Missions) do
		for _, id in ipairs(mission.templates) do
			expectedTemplates[id] = true
		end
		local copy = (Presentation.Missions :: any)[mission.missionId]
		assert(copy ~= nil and #copy.title > 0 and #copy.brief > 0, "mission brief exists")
	end
	for id, copy in pairs(Presentation.Contexts) do
		assert(expectedContexts[id], "no unshipped contexts")
		for key, value in pairs(copy) do
			assert(key == "title" or key == "trend" or key == "audience" or key == "clue", "context contains display fields only")
			assert(typeof(value) == "string" and #value > 0, "readable context value")
		end
		for templateId in pairs(expectedTemplates) do
			assert(copy.clue:find(templateId, 1, true) == nil, "clue does not identify a winning template")
		end
	end
	for id in pairs(expectedContexts) do
		assert((Presentation.Contexts :: any)[id] ~= nil, "every shipped context resolves")
	end
	for id in pairs(expectedTemplates) do
		local copy = (Presentation.Templates :: any)[id]
		assert(copy ~= nil and #copy.title > 0 and #copy.body > 0, "template resolves to authored copy")
		for key in pairs(copy) do
			assert(key == "title" or key == "body", "template contains no affinity or score fields")
		end
	end
	for id in pairs(Presentation.Templates) do
		assert(expectedTemplates[id], "no unshipped templates")
	end
	for _, device in ipairs(Catalog.Devices) do
		local name = (Presentation.Devices :: any)[device.id]
		assert(typeof(name) == "string" and #name > 0, "existing device has a display name")
	end
end)

test("Public clues keep their existing readable wording", function()
	equal(Presentation.Contexts.organic_snack.clue, "Jajanan sore lagi rame di kalangan anak kos. Siapa yang paling bisa bikin mereka berhenti scrolling?", "organic clue")
	equal(Presentation.Contexts.meal_time.clue, "Jam makan siang tiba dan warung mie di ujung jalan selalu penuh. Siapa yang paling bisa bikin antriannya kelihatan ramai?", "mission clue")
end)

test("Own profile and snapshot projections keep confirmed results without inventing text or pending history", function()
	local saved = summary("confirmed", 2000)
	saved.body = "Untrusted stored text"
	saved.likes = 999999
	saved.affinity = "private"
	saved.mode = "mission"
	saved.contextId = "meal_time"
	saved.templateId = "queue_thread"
	local profile = { ownPosts = { saved }, pendingPost = summary("pending", 3000) }
	local snapshot = { revision = 8, ownPosts = { table.clone(saved) }, balance = 999, pendingPost = profile.pendingPost }
	local own = Presentation.ownCards(profile)
	equal(own, Presentation.ownCards(snapshot), "profile/snapshot equivalence")
	equal(own, { {
		cardId = "own-confirmed", kind = "own", contextId = "meal_time", templateId = "queue_thread", body = "",
		clueKey = "meal_time_clue", clueText = Presentation.Contexts.meal_time.clue,
		publishedAt = 2000, likes = 17, replies = 4, finalImpact = 120, organicCuan = 15, mode = "mission",
	} }, "confirmed public result only")
	assert((Presentation.Templates :: any)[own[1].templateId].body ~= saved.body, "UI copy resolves by authored template ID")
	equal(saved.likes, 999999, "source not mutated")
end)

test("Missing post history is empty and own-card bounds preserve saved order", function()
	equal(Presentation.ownCards(nil), {}, "nil history")
	equal(Presentation.ownCards({}), {}, "missing history")
	local ownPosts = {}
	for index = 1, 14 do
		table.insert(ownPosts, summary(`p{index}`, 3000 - index))
	end
	local cards = Presentation.ownCards({ ownPosts = ownPosts })
	equal(#cards, 10, "bounded history")
	equal(Presentation.MAX_OWN_CARDS, 10, "declared history bound")
	equal(cards[1].cardId, "own-p1", "first saved result")
	equal(cards[10].cardId, "own-p10", "tenth saved result")
	equal(#Presentation.build({ ownPosts = ownPosts }), 16, "authored clues survive a full history")
end)

test("Combined feed ordering stays deterministic including same-time own and authored cards", function()
	local input = { ownPosts = { summary("b", 1000), summary("a", 1000), summary("newest", 2000) } }
	local cards = Presentation.build(input)
	local ids = {}
	for _, data in ipairs(cards) do
		table.insert(ids, data.cardId)
	end
	equal(ids, { "own-newest", "npc-meal-3", "npc-meal-2", "npc-meal-1", "npc-snack-3", "npc-snack-2", "own-a", "own-b", "npc-snack-1" }, "stable sorted IDs")
	equal(Presentation.build(input), cards, "repeatable build")
	equal(input.ownPosts[1].postId, "b", "saved order is not sorted in place")
end)

test("Static display data is deeply frozen and returned projection arrays are isolated", function()
	local function frozen(value: any)
		assert(table.isfrozen(value), "static table is frozen")
		for _, child in pairs(value) do
			if typeof(child) == "table" then
				frozen(child)
			end
		end
	end
	frozen(Presentation.Contexts)
	frozen(Presentation.Templates)
	frozen(Presentation.Missions)
	frozen(Presentation.Devices)
	local cards = Presentation.authoredCards()
	cards[1].body = "Changed local projection"
	table.remove(cards)
	local rebuilt = Presentation.authoredCards()
	equal(#rebuilt, 6, "authored array not shared")
	equal(rebuilt[1].body, "Snack siang hari ini benar-benar menyelamatkan deadline.", "authored source not changed")
	local identities = Presentation.npcIdentities()
	table.remove(identities)
	equal(#Presentation.npcIdentities(), 8, "identity array not shared")
	assert(table.isfrozen(Presentation.npcIdentities()[1]), "identity records are immutable")
end)

test("Authored reply pools preserve exact public copy and cannot be changed by a caller", function()
	equal(Presentation.repliesFor("organic_snack"), { "ini enak banget siang ini", "jajan anak kos keren", "kok bisa sekeren itu" }, "organic replies")
	equal(Presentation.repliesFor("meal_time"), { "laper gara gara ini", "menu siang favoritku", "antriannya legendendar" }, "mission replies")
	equal(Presentation.repliesFor("unknown"), {}, "unknown reply pool")
	local replies = Presentation.repliesFor("meal_time")
	replies[1] = "Changed local reply"
	equal(Presentation.repliesFor("meal_time")[1], "laper gara gara ini", "reply source not changed")
end)

test("FeedService remains compatible with the shared public API for all projection exports", function()
	local input = { ownPosts = { summary("server-compatible", 1600) } }
	equal(FeedService.authoredCards(), Presentation.authoredCards(), "authored compatibility")
	equal(FeedService.ownCards(input), Presentation.ownCards(input), "own compatibility")
	equal(FeedService.build(input), Presentation.build(input), "combined compatibility")
	equal(FeedService.repliesFor("meal_time"), Presentation.repliesFor("meal_time"), "replies compatibility")
	equal(FeedService.npcIdentities(), Presentation.npcIdentities(), "identity compatibility")
	equal(FeedService.AUTHORED_NPC_CARDS, Presentation.AUTHORED_NPC_CARDS, "authored constant")
	equal(FeedService.NPC_IDENTITY_LABELS, Presentation.NPC_IDENTITY_LABELS, "identity constant")
	equal(FeedService.MAX_OWN_CARDS, Presentation.MAX_OWN_CARDS, "own constant")
end)

local passed = 0
local failures: { string } = {}
for _, testCase in ipairs(tests) do
	local ok, err = pcall(testCase.fn)
	if ok then
		passed += 1
		print(`[PASS] {testCase.name}`)
	else
		table.insert(failures, `{testCase.name}: {tostring(err)}`)
		print(`[FAIL] {testCase.name}: {tostring(err)}`)
	end
end
print(`Presentation spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print("BS08_PRESENTATION_TESTS_FAILED")
	error(table.concat(failures, "\n"), 0)
end
print("BS08_PRESENTATION_TESTS_PASSED")
return `Presentation: {passed}/{#tests} passed`
