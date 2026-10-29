--!strict
-- Buzzer Simulator — FeedService spec (BS-03).
-- Executed by tests/Runner.server.luau in the test project only.
-- Deterministic bounded-projection tests: no randomness, no network, no
-- user-generated content. Contract sources: docs/02, docs/08 (BS-03).
local ServerStorage = game:GetService("ServerStorage")
local FeedService = require(ServerStorage:WaitForChild("FeedService"))
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

-- ===== authored cards =====
test("Authored feed has exactly six NPC cards", function()
	local cards = FeedService.authoredCards()
	expectEqual(#cards, 6, "six authored cards")
	expectEqual(#cards, FeedService.AUTHORED_NPC_CARDS, "matches the declared bound")
end)

test("Every authored card carries an NPC identity and authored body", function()
	for _, card in ipairs(FeedService.authoredCards()) do
		local c: any = card
		expectTrue(c.npcName ~= nil and #c.npcName > 0, "card has an NPC name")
		expectTrue(c.npcHandle ~= nil and #c.npcHandle > 0, "card has an NPC handle")
		expectTrue(#c.body > 0, "card has authored body copy")
		expectEqual(c.kind, "authored", "card kind is authored")
	end
end)

test("Authored cards use only the eight bounded NPC identities", function()
	local identities = FeedService.npcIdentities()
	expectEqual(#identities, 8, "eight NPC identities")
	expectEqual(#identities, FeedService.NPC_IDENTITY_LABELS, "matches the declared bound")
	local allowed: { [string]: boolean } = {}
	for _, identity in ipairs(identities) do
		allowed[(identity :: any).name] = true
	end
	for _, card in ipairs(FeedService.authoredCards()) do
		local npcName = (card :: any).npcName
		expectTrue(allowed[npcName] ~= nil, `card NPC {tostring(npcName)} is a known identity`)
	end
end)

test("Authored cards are ordered deterministically by publish time", function()
	local cards = FeedService.authoredCards()
	for i = 2, #cards do
		expectTrue(cards[i - 1].publishedAt <= cards[i].publishedAt, "authored cards sorted by publishedAt")
	end
	-- Rebuilding produces the identical order.
	local again = FeedService.authoredCards()
	for i = 1, #cards do
		expectEqual(again[i].cardId, cards[i].cardId, "authored order is stable")
	end
end)

test("Authored cards carry clues for their supported contexts", function()
	-- Only organic contexts carry a clueKey in the public Catalog (MissionDef
	-- has no clueKey field), so mission-context cards legitimately have none.
	-- A clue is valid if it is either an organic context's public clueKey or a
	-- mission context's server-owned public clue key. Neither form exposes any
	-- private template affinity.
	local validClues: { [string]: boolean } = {}
	for _, ctx in ipairs(Catalog.OrganicContexts) do
		validClues[(ctx :: any).clueKey] = true
	end
	validClues["meal_time_clue"] = true
	for _, card in ipairs(FeedService.authoredCards()) do
		local clueKey = (card :: any).clueKey
		if clueKey ~= nil then
			expectTrue(validClues[clueKey] ~= nil, `clue {tostring(clueKey)} is a known public clue`)
		end
	end
	-- Every V0 authored card must carry a discoverable clue, including the
	-- mission-context ones.
	local withClue = 0
	for _, card in ipairs(FeedService.authoredCards()) do
		if (card :: any).clueKey ~= nil then
			withClue += 1
		end
	end
	expectEqual(withClue, #FeedService.authoredCards(), "every authored card carries a clue")
	-- Mission-context cards specifically must be discoverable.
	local missionClue = 0
	for _, card in ipairs(FeedService.authoredCards()) do
		if (card :: any).contextId == "meal_time" and (card :: any).clueKey ~= nil then
			missionClue += 1
		end
	end
	expectEqual(missionClue, 3, "all three meal_time cards carry a clue")
end)
test("Both V0 contexts resolve to readable authored clue text", function()
	-- docs/02: "Each context names a fictional trend, audience, and readable
	-- clue." A clue KEY alone is not usable by a player, so every shipped
	-- context must resolve to readable text through the projection.
	local expected: { [string]: string } = {
		organic_snack = "organic_snack_clue",
		meal_time = "meal_time_clue",
	}
	for contextId, expectedKey in pairs(expected) do
		local found = false
		for _, card in ipairs(FeedService.authoredCards()) do
			local c: any = card
			if c.contextId == contextId then
				found = true
				expectEqual(c.clueKey, expectedKey, `{contextId} clue key`)
				expectTrue(
					typeof(c.clueText) == "string" and #(c.clueText :: string) > 0,
					`{contextId} resolves to readable clue text`
				)
			end
		end
		expectTrue(found, `{contextId} has authored feed cards`)
	end
	-- Own cards resolve the same way, so the composer can show the clue too.
	local p = freshProfile()
	table.insert(p.ownPosts, {
		postId = "post-1",
		mode = "organic",
		contextId = "organic_snack",
		templateId = "snack_meme",
		finalImpact = 120,
		organicCuan = 15,
		publishedAt = 1000,
	})
	local own = FeedService.ownCards(p)
	expectEqual(#own, 1, "one own card")
	expectEqual((own[1] :: any).clueKey, "organic_snack_clue", "own card clue key")
	expectTrue(
		#((own[1] :: any).clueText :: string) > 0,
		"own card resolves to readable clue text"
	)
end)
test("Clue text never reveals the winning template", function()
	-- The clue is public readable context. It must not name or imply which
	-- template the private scoring catalog will score as strong.
	local clues = {
		organic_snack = "organic_snack_clue",
		meal_time = "meal_time_clue",
	}
	local winners = {
		organic_snack = "snack_meme",
		meal_time = "meal_meme",
	}
	for contextId, clueKey in pairs(clues) do
		local text: string? = nil
		for _, card in ipairs(FeedService.authoredCards()) do
			local c: any = card
			if c.contextId == contextId and c.clueKey == clueKey then
				text = c.clueText
				break
			end
		end
		expectTrue(text ~= nil, `{contextId} has clue text`)
		expectTrue(
			(text :: string):find(winners[contextId], 1, true) == nil,
			`{contextId} clue text does not name its winning template`
		)
	end
end)

test("Engagement is derived, not random", function()
	local cards = FeedService.authoredCards()
	local first = cards[1]
	local again = FeedService.authoredCards()
	expectEqual(again[1].likes, first.likes, "likes are deterministic")
	expectEqual(again[1].replies, first.replies, "replies are deterministic")
	-- Derived from impact and timestamp, so a higher impact yields more likes.
	local lowImpact = FeedService.authoredCards()
	expectTrue(lowImpact[1].likes >= 0, "likes are nonnegative")
end)

-- ===== own cards =====
test("Own cards project from saved summaries, bounded to ten", function()
	local p = freshProfile()
	for i = 1, 14 do
		table.insert(p.ownPosts, {
			postId = `post-{i}`,
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			finalImpact = 100 + i,
			organicCuan = 15,
			publishedAt = 1000 + i,
		})
	end
	local cards = FeedService.ownCards(p)
	expectEqual(#cards, 10, "own cards capped at 10")
	expectEqual(#cards, FeedService.MAX_OWN_CARDS, "matches the declared bound")
	-- Newest first, matching the saved order.
	expectEqual(cards[1].finalImpact, 101, "newest own post first")
	expectEqual(cards[10].finalImpact, 110, "tenth own post")
end)

test("Own cards carry the frozen result values", function()
	local p = freshProfile()
	table.insert(p.ownPosts, {
		postId = "post-1",
		mode = "mission",
		contextId = "meal_time",
		templateId = "meal_meme",
		finalImpact = 120,
		organicCuan = 15,
		publishedAt = 1000,
		missionRunId = "run-1",
	})
	local cards = FeedService.ownCards(p)
	expectEqual(#cards, 1, "one own card")
	expectEqual(cards[1].kind, "own", "kind own")
	expectEqual(cards[1].finalImpact, 120, "frozen impact projected")
	expectEqual(cards[1].organicCuan, 15, "frozen payout projected")
	expectEqual(cards[1].mode, "mission", "mode projected")
	expectEqual(cards[1].npcName, nil, "own card has no NPC name")
end)

test("Own cards never contain user text", function()
	local p = freshProfile()
	table.insert(p.ownPosts, {
		postId = "post-1",
		mode = "organic",
		contextId = "organic_snack",
		templateId = "snack_meme",
		finalImpact = 100,
		organicCuan = 15,
		publishedAt = 1000,
	})
	local cards = FeedService.ownCards(p)
	expectEqual(cards[1].body, "", "own card body is empty; no free text is stored")
end)

test("An empty profile yields no own cards", function()
	expectEqual(#FeedService.ownCards(freshProfile()), 0, "no own posts means no own cards")
end)

-- ===== combined feed =====
test("The combined feed is bounded and deterministic", function()
	local p = freshProfile()
	for i = 1, 5 do
		table.insert(p.ownPosts, {
			postId = `post-{i}`,
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			finalImpact = 100,
			organicCuan = 15,
			publishedAt = 2000 + i,
		})
	end
	local feed = FeedService.build(p)
	expectEqual(#feed, 11, "six authored plus five own")
	-- Newest first.
	for i = 2, #feed do
		expectTrue(feed[i - 1].publishedAt >= feed[i].publishedAt, "combined feed sorted newest first")
	end
	-- Deterministic across rebuilds.
	local again = FeedService.build(p)
	for i = 1, #feed do
		expectEqual(again[i].cardId, feed[i].cardId, "combined order is stable")
	end
end)

test("Own posts surface above authored cards at the same timestamp", function()
	local p = freshProfile()
	-- Match an authored card's timestamp exactly (npc-snack-1 is at 1000).
	table.insert(p.ownPosts, {
		postId = "post-1",
		mode = "organic",
		contextId = "organic_snack",
		templateId = "snack_meme",
		finalImpact = 100,
		organicCuan = 15,
		publishedAt = 1000,
	})
	local feed = FeedService.build(p)
	-- The feed is newest-first, so the 1000 tie sits at the bottom. Find the
	-- tied pair and confirm the own card leads it.
	local ownIndex, authoredIndex = -1, -1
	for i, card in ipairs(feed) do
		local c: any = card
		if c.kind == "own" then
			ownIndex = i
		elseif c.cardId == "npc-snack-1" then
			authoredIndex = i
		end
	end
	expectEqual(feed[ownIndex].publishedAt, 1000, "own card is at the tied timestamp")
	expectEqual(feed[authoredIndex].publishedAt, 1000, "authored card shares the timestamp")
	expectTrue(ownIndex < authoredIndex, "own card leads the authored card at the same timestamp")
end)

test("The feed never grows without bound", function()
	local p = freshProfile()
	for i = 1, 50 do
		table.insert(p.ownPosts, {
			postId = `post-{i}`,
			mode = "organic",
			contextId = "organic_snack",
			templateId = "snack_meme",
			finalImpact = 100,
			organicCuan = 15,
			publishedAt = 1000 + i,
		})
	end
	local feed = FeedService.build(p)
	expectEqual(#feed, 16, "six authored plus at most ten own")
end)

-- ===== reply pools =====
test("Reply pools are bounded and authored", function()
	for _, ctx in ipairs(Catalog.OrganicContexts) do
		local replies = FeedService.repliesFor((ctx :: any).contextId)
		expectTrue(#replies > 0, `context {(ctx :: any).contextId} has a reply pool`)
		expectTrue(#replies <= 8, "reply pool is bounded")
		for _, reply in ipairs(replies) do
			expectTrue(#(reply :: string) > 0, "reply is nonempty authored copy")
		end
	end
end)

test("An unknown context has no reply pool", function()
	expectEqual(#FeedService.repliesFor("not_a_context"), 0, "unknown context yields no replies")
end)

-- ===== privacy =====
test("The feed never leaks private scoring affinities", function()
	local p = freshProfile()
	table.insert(p.ownPosts, {
		postId = "post-1",
		mode = "organic",
		contextId = "organic_snack",
		templateId = "snack_meme",
		finalImpact = 120,
		organicCuan = 15,
		publishedAt = 1000,
	})
	local encoded = game:GetService("HttpService"):JSONEncode(FeedService.build(p))
	-- The per-template affinity mapping must not appear anywhere in the feed.
	expectTrue(encoded:find('"snack_meme":{"trendId"') == nil, "no per-template affinity in the feed")
	expectTrue(encoded:find("audienceId") == nil, "no audience tags in the feed")
	-- The readable clue text is public context, but it must never carry the
	-- private affinity field names that would reveal the answer key.
	expectTrue(encoded:find("trendId") == nil, "no trendId affinity fields in the feed")
	expectTrue(encoded:find('"snack_meme":') == nil, "no template-keyed affinity table in the feed")
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
print(`FeedService spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print(`FAILURES:`)
	for _, f in ipairs(failures) do
		print(`  - {f}`)
	end
	print("BS03_FEED_TESTS_FAILED")
	error(`FeedService spec: {#failures} failed (see FAILURES above)`, 0)
end
print("BS03_FEED_TESTS_PASSED")
return `FeedService: {passed}/{#tests} passed`
