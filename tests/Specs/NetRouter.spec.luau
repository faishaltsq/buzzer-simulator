--!strict
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local NetRouter = require(ServerStorage:WaitForChild("NetRouter"))
local SessionService = require(ServerStorage:WaitForChild("SessionService"))
local WorldService = require(ServerStorage:WaitForChild("WorldService"))

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ()) table.insert(tests, { name = name, fn = fn }) end
local function equal(actual: any, expected: any, label: string?)
	if actual ~= expected then error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 0) end
end
local function truth(value: any, label: string?) if not value then error(label or "expected truthy", 0) end end
local cleanup: { () -> () } = {}
local function track(instance: Instance): any
	table.insert(cleanup, function() instance:Destroy() end)
	return instance
end
local function profile(): any
	return {
		balance = 0, lifetimeEarned = 0, completedMissions = 0, deviceId = "phone_cheap", propertyId = "bedroom",
		ownedDesks = {}, workers = {}, fractionalIncome = 0, claimedRunIdsWindow = {}, recentMutationOutcomes = {},
		missionVariantCounters = {}, nextOrganicSequence = 0, ownPosts = {}, nextPostSequence = 1,
	}
end
local nextUser = 80000
local function fixture(options: any?): any
	options = options or {}
	nextUser += 1
	local clock = { epoch = 1000, mono = 0 }
	local player: any = { UserId = nextUser, Name = `Router{nextUser}` }
	local character = track(Instance.new("Model"))
	character.Name = "Character"
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Parent = character
	player.Character = character
	local store: any = { data = {}, writes = 0, hold = false, fail = false }
	function store:GetAsync(key: string, _options: any?) return self.data[key] end
	function store:UpdateAsync(key: string, transform: (any) -> any)
		self.writes += 1
		if self.hold then self.hold = false; coroutine.yield("held-write") end
		if self.fail then error("injected datastore transport failure", 0) end
		local proposed = transform(self.data[key])
		if proposed ~= nil then self.data[key] = proposed end
		return proposed
	end
	local p = options.profile or profile()
	store.data[`Player_{player.UserId}`] = {
		schemaVersion = 1, revision = 1, lastSaveOpId = "seed", updatedAt = 1000, profile = p,
		lease = { token = "", jobId = "seed", expiresAt = 0 },
	}
	local guid = 0
	local http: any = {}
	function http:GenerateGUID(_braces: boolean?) guid += 1; return `router-guid-{guid}` end
	function http:JSONEncode(value: any) return HttpService:JSONEncode(value) end
	local function newSession(): any
		return SessionService.new({
			userId = player.UserId, store = store, httpService = http, jobId = "router-spec",
			now = function() return clock.epoch end, wait = function(_seconds: number) end,
			noCacheOptions = function() return { UseCache = false } end,
		})
	end
	local session = newSession()
	truth(session:Start().ok, "real session starts")
	local prompt = track(Instance.new("ProximityPrompt"))
	local world: any = {
		GetPrompt = function(actor: any) return if actor == player then prompt else nil end,
		ValidateDashboardPrompt = function(_actor: any, _prompt: any) return true end,
	}
	local replies, snapshots = {}, {}
	local state: any = { clock = clock, player = player, session = session, store = store, prompt = prompt,
		world = world, replies = replies, snapshots = snapshots, root = root, humanoid = humanoid, newSession = newSession,
		hooks = 0, confirmed = 0 }
	local router = NetRouter.new({
		world = world, now = function() return clock.epoch end, monotonic = function() return clock.mono end,
		guid = function() guid += 1; return `dashboard-{guid}` end,
		sendReply = function(actor: any, message: any)
			if state.failReply then error("injected reply transport error", 0) end
			table.insert(replies, { player = actor, message = message })
		end,
		sendSnapshot = function(actor: any, message: any) table.insert(snapshots, { player = actor, message = message }) end,
		beforeMutation = function(_actor: any) state.hooks += 1; if state.hookError then error("accounting hook error", 0) end end,
		onConfirmed = function(_actor: any, _snapshot: any)
			state.confirmed += 1
			if state.visualError then error("injected world presentation error", 0) end
		end,
	})
	state.router = router
	router:Register(player, session)
	function state:advance(seconds: number) clock.epoch += seconds; clock.mono += seconds end
	function state:open(): string
		truth(router:HandlePrompt(prompt, player), "owned prompt opens")
		self.id = snapshots[#snapshots].message.dashboardSessionId
		return self.id
	end
	function state:command(action: string, payload: any?, id: string?): any
		local message = { requestId = id or "mutation-0001", action = action, payload = payload or {},
			dashboardSessionId = if action == "GetSnapshot" then nil else self.id }
		router:HandleCommand(player, message)
		return if #replies > 0 then replies[#replies].message else nil
	end
	function state:last(): any return replies[#replies].message end
	return state
end

for _, conflict in ipairs({ "folder class", "duplicate folder", "remote class", "duplicate remote", "extra child" }) do
	test(`EnsureRemotes rejects {conflict}`, function()
		local storage = track(Instance.new("Folder"))
		local folder = Instance.new(if conflict == "folder class" then "Model" else "Folder")
		folder.Name = "BuzzerRemotes"; folder.Parent = storage
		if conflict == "duplicate folder" then local duplicate = Instance.new("Folder"); duplicate.Name = folder.Name; duplicate.Parent = storage end
		if conflict == "remote class" or conflict == "duplicate remote" or conflict == "extra child" then
			local child = Instance.new(if conflict == "remote class" then "Folder" else "RemoteEvent")
			child.Name = if conflict == "extra child" then "OpenComputer" else "Command"; child.Parent = folder
			if conflict == "duplicate remote" then local duplicate = child:Clone(); duplicate.Parent = folder end
		end
		equal(pcall(NetRouter.EnsureRemotes, storage), false)
	end)
end

test("EnsureRemotes creates exactly three private RemoteEvents idempotently", function()
	local storage = track(Instance.new("Folder"))
	local first = NetRouter.EnsureRemotes(storage)
	local second = NetRouter.EnsureRemotes(storage)
	equal(#storage:GetChildren(), 1)
	equal(#storage.BuzzerRemotes:GetChildren(), 3)
	for _, name in ipairs({ "Command", "Reply", "Snapshot" }) do
		equal(first[name], second[name]); truth(first[name]:IsA("RemoteEvent"))
	end
end)

local malformed = {
	{ "extra userId", function(c: any) c.userId = 1 end },
	{ "extra intent", function(c: any) c.intent = "forged" end },
	{ "money", function(c: any) c.payload.balance = 999999 end },
	{ "price", function(c: any) c.payload.price = 0 end },
	{ "score", function(c: any) c.payload.score = 100 end },
	{ "context", function(c: any) c.payload.contextId = "meal_time" end },
	{ "timestamp", function(c: any) c.payload.publishedAt = 1 end },
	{ "rate", function(c: any) c.payload.incomePerSecond = 999 end },
	{ "unknown template", function(c: any) c.payload.templateId = "forged_template" end },
	{ "nested scalar", function(c: any) c.payload.templateId = { "snack_meme" } end },
	{ "cyclic payload", function(c: any) c.payload.templateId = c.payload end },
	{ "cyclic envelope", function(c: any) c.extra = c end },
	{ "array envelope", function(c: any) c[1] = "forged" end },
	{ "array payload", function(c: any) c.payload[1] = "forged" end },
	{ "metatable", function(c: any) setmetatable(c, { __index = function() error("must not invoke client metamethod") end }) end },
	{ "missing payload", function(c: any) c.payload = nil end },
	{ "non-table payload", function(c: any) c.payload = 5 end },
	{ "missing dashboard", function(c: any) c.dashboardSessionId = nil end },
	{ "nested dashboard", function(c: any) c.dashboardSessionId = {} end },
}
for _, case in ipairs(malformed) do
	test(`Rejects forged shape: {case[1]}`, function()
		local f = fixture(); f:open(); f:advance(10)
		local writes = f.store.writes
		local command: any = { requestId = "forgery-0001", action = "PublishOrganic", payload = { templateId = "snack_meme" }, dashboardSessionId = f.id }
		local forge = case[2] :: any
		forge(command)
		f.router:HandleCommand(f.player, command)
		equal(f:last().code, "INVALID_INPUT"); equal(f.hooks, 0); equal(f.store.writes, writes)
		equal(f:last().dashboardSession.expiresAt, 1600, "invalid traffic does not extend idle")
	end)
end

for _, invalid in ipairs({ "short", string.rep("x", 65), "nonascii-\195\169" }) do
	test(`Drops uncorrelatable request ID length {#invalid}`, function()
		local f = fixture(); f:open()
		f.router:HandleCommand(f.player, { requestId = invalid, action = "GetSnapshot", payload = {} })
		equal(#f.replies, 0); equal(f.hooks, 0)
	end)
end

for _, slot in ipairs({ 0, 3, 1.5, math.huge, -math.huge, math.sqrt(-1), "1" }) do
	test(`Rejects invalid numeric slot {tostring(slot)}`, function()
		local f = fixture(); f:open()
		equal(f:command("HireWorker", { slotIndex = slot, roleId = "trainee" }).code, "INVALID_INPUT")
		equal(f.hooks, 0)
	end)
end

for _, case in ipairs({
	{ "AcceptMission", { missionId = "unknown_mission" } },
	{ "BuyDevice", { deviceId = "server_money" } },
	{ "HireWorker", { slotIndex = 1, roleId = "boss" } },
	{ "PublishPost", { runId = {}, templateId = "meal_meme" } },
	{ "ClaimMission", { runId = string.rep("r", 65) } },
	{ "CloseComputer", { extra = true } },
}) do
	test(`Rejects action-specific invalid {case[1]} payload`, function()
		local f = fixture(); f:open(); equal(f:command(case[1] :: string, case[2]).code, "INVALID_INPUT"); equal(f.hooks, 0)
	end)
end

test("Client cannot command OpenComputer", function()
	local f = fixture(); equal(f:command("OpenComputer").code, "UNKNOWN_ACTION"); equal(#f.snapshots, 0)
end)

test("Snapshot union forbids dashboard IDs and query equaling original lookup ID", function()
	local f = fixture(); f:open()
	f.router:HandleCommand(f.player, { requestId = "query-000001", action = "GetSnapshot", payload = {}, dashboardSessionId = f.id })
	equal(f:last().code, "INVALID_INPUT")
	equal(f:command("GetSnapshot", { lookupRequestId = "query-000002" }, "query-000002").code, "INVALID_INPUT")
end)

test("Snapshot is available with dashboard closed and never writes ordinary reads", function()
	local f = fixture(); local writes = f.store.writes
	local result = f:command("GetSnapshot", {}, "query-000001")
	equal(result.ok, true); equal(result.data.snapshot.balance, 0); equal(result.dashboardSession, nil)
	equal(f.store.writes, writes); equal(f.hooks, 0)
end)

test("Prompt opens sanitized state only and always replaces generation", function()
	local f = fixture(); local writes = f.store.writes
	local first = f:open(); local second = f:open(); truth(first ~= second)
	local event = f.snapshots[#f.snapshots].message
	equal(event.kind, "OpenComputer"); equal(event.state.lease, nil); equal(event.state.recentMutationOutcomes, nil)
	equal(event.state.missionVariantCounters, nil); equal(event.state.fractionalIncome, nil)
	equal(f.store.writes, writes)
end)

test("Old generation cannot mutate or close a reopened dashboard", function()
	local f = fixture(); local old = f:open(); local current = f:open(); local writes = f.store.writes
	for index, action in ipairs({ "PublishOrganic", "CloseComputer" }) do
		f.router:HandleCommand(f.player, { requestId = `old-generation-{index}`, action = action,
			payload = if action == "CloseComputer" then {} else { templateId = "snack_meme" }, dashboardSessionId = old })
		equal(f:last().code, "SESSION_EXPIRED"); equal(f:last().dashboardSession.dashboardSessionId, current)
	end
	equal(f.store.writes, writes); equal(f.hooks, 0)
end)

test("Economic admission extends deadline even when domain refuses funds", function()
	local f = fixture(); f:open(); f:advance(20); local writes = f.store.writes
	local result = f:command("BuyDevice", { deviceId = "phone_fast" })
	equal(result.code, "INSUFFICIENT_FUNDS"); equal(result.dashboardSession.expiresAt, 1620)
	equal(f.hooks, 1); equal(f.store.writes, writes)
	local again = f:command("BuyDevice", { deviceId = "phone_fast" })
	equal(again.code, "INSUFFICIENT_FUNDS"); equal(f.hooks, 1)
	local lookup = f:command("GetSnapshot", { lookupRequestId = "mutation-0001" }, "query-000001")
	equal(lookup.data.lookup.status, "REJECTED"); equal(lookup.data.lookup.originalResult.code, "INSUFFICIENT_FUNDS")
end)

test("Queries and close never extend deadline or enter accounting hook", function()
	local f = fixture(); f:open(); f:advance(20)
	equal(f:command("GetSnapshot", {}, "query-000001").dashboardSession.expiresAt, 1600)
	equal(f:command("CloseComputer", {}, "close-000001").dashboardSession, nil)
	equal(f.hooks, 0)
end)

test("Idle expiry emits once, without scheduler, and cannot reopen on command", function()
	local f = fixture(); f:open(); f:advance(600)
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "SESSION_EXPIRED")
	f.router:Step(); f.router:Step()
	equal(#f.snapshots, 2); equal(f.snapshots[2].message.reason, "IDLE"); equal(f.hooks, 0)
end)

test("Monotonic deadline does not follow epoch clock rollback", function()
	local f = fixture(); f:open(); f.clock.epoch = 900; f.clock.mono = 600; f.router:Step()
	equal(f.snapshots[2].message.kind, "ComputerSessionExpired")
end)

for _, loss in ipairs({ "death", "missing root", "removed character", "replaced character" }) do
	test(`Character validity rejects commands without scheduler: {loss}`, function()
		local f = fixture(); f:open()
		if loss == "death" then f.humanoid.Health = 0
		elseif loss == "missing root" then f.root:Destroy()
		elseif loss == "removed character" then f.player.Character = nil
		else f.player.Character = track(Instance.new("Model")) end
		equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "SESSION_EXPIRED")
		f.router:CharacterLost(f.player); f.router:Step()
		equal(#f.snapshots, 2); equal(f.snapshots[2].message.reason, "CHARACTER_LOST"); equal(f.hooks, 0)
	end)
end

test("Commands use actual registered Player identity, never equal user IDs", function()
	local f = fixture(); f:open()
	local impostor = { UserId = f.player.UserId, Name = f.player.Name, Character = f.player.Character }
	f.router:HandleCommand(impostor, { requestId = "forged-actor-1", action = "BuyDevice", payload = { deviceId = "phone_fast" }, dashboardSessionId = f.id })
	equal(#f.replies, 0); equal(f.hooks, 0)
end)

test("Eight commands per second are bounded and independent per registered actor", function()
	local f = fixture(); f:open()
	for index = 1, 8 do equal(f:command("GetSnapshot", {}, `query-rate-{index}`).code, "OK") end
	equal(f:command("GetSnapshot", {}, "query-rate-9").code, "BUSY")
	f:advance(1); equal(f:command("GetSnapshot", {}, "query-rate-10").code, "OK")
	local other = { UserId = f.player.UserId, Character = f.player.Character }
	f.router:Register(other, f.session)
	f.router:HandleCommand(other, { requestId = "other-rate-1", action = "GetSnapshot", payload = {} })
	equal(f:last().code, "OK"); equal(f.replies[#f.replies].player, other)
end)

test("Malformed traffic consumes limiter without economic admission", function()
	local f = fixture(); f:open()
	for _ = 1, 8 do f.router:HandleCommand(f.player, {}) end
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "BUSY"); equal(f.hooks, 0)
end)

test("Duplicate successful publish recovers before cooldown and does not republish", function()
	local f = fixture(); f:open()
	equal(f:command("PublishOrganic", { templateId = "snack_meme" }).code, "OK")
	local writes = f.store.writes
	equal(f:command("PublishOrganic", { templateId = "snack_meme" }).code, "OK")
	equal(f.store.writes, writes); equal(f.hooks, 1)
	equal(f:command("PublishOrganic", { templateId = "snack_thread" }, "mutation-0002").code, "BUSY")
	f:advance(2)
	equal(f:command("PublishOrganic", { templateId = "snack_thread" }, "mutation-0003").code, "NOT_READY")
	equal(f.store.writes, writes, "pending-post rejection writes nothing")
end)

test("Same request ID with different live intent never reaches domain", function()
	local f = fixture(); f:open()
	f:command("PublishOrganic", { templateId = "snack_meme" })
	local writes = f.store.writes
	equal(f:command("PublishOrganic", { templateId = "snack_thread" }).code, "INVALID_INPUT")
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "INVALID_INPUT")
	equal(f.hooks, 1); equal(f.store.writes, writes)
end)

test("Lookup query ID is distinct and private; absent ID is UNKNOWN without retry", function()
	local f = fixture(); f:open(); local writes = f.store.writes
	local result = f:command("GetSnapshot", { lookupRequestId = "original-unknown" }, "query-000001")
	equal(result.requestId, "query-000001"); equal(result.data.lookup.originalRequestId, "original-unknown")
	equal(result.data.lookup.status, "UNKNOWN"); equal(result.data.lookup.originalResult, nil)
	equal(f.store.writes, writes); equal(f.hooks, 0); equal(f.replies[1].player, f.player)
end)

test("Ordinary push uses non-writing projection even when post is due", function()
	local f = fixture(); f:open(); f:command("PublishOrganic", { templateId = "snack_meme" })
	f:advance(18); local writes = f.store.writes
	truth(f.router:PushState(f.player)); equal(f.store.writes, writes)
	local state = f.snapshots[#f.snapshots].message.state
	equal(state.balance, 0); truth(state.pendingPost ~= nil)
	local result = f:command("GetSnapshot", {}, "query-due-001")
	equal(result.data.snapshot.balance, 15); equal(f.store.writes, writes + 1)
	f:command("GetSnapshot", {}, "query-due-002"); equal(f.store.writes, writes + 1)
end)

test("PushState is at least two seconds apart", function()
	local f = fixture(); truth(f.router:PushState(f.player)); equal(f.router:PushState(f.player), false)
	f:advance(1.99); equal(f.router:PushState(f.player), false)
	f:advance(0.01); truth(f.router:PushState(f.player)); equal(#f.snapshots, 2)
end)

local function holdPublish(f: any): thread
	f.store.hold = true
	local thread = coroutine.create(function() f:command("PublishOrganic", { templateId = "snack_meme" }) end)
	local ok, marker = coroutine.resume(thread)
	truth(ok, tostring(marker)); equal(marker, "held-write"); equal(coroutine.status(thread), "suspended")
	return thread
end

test("Held write queries are nonblocking PENDING and confirmed-only", function()
	local f = fixture(); f:open(); local thread = holdPublish(f)
	local result = f:command("GetSnapshot", { lookupRequestId = "mutation-0001" }, "query-held-001")
	equal(result.data.lookup.status, "PENDING"); equal(result.data.snapshot.pendingPost, nil)
	equal(result.data.snapshot.revision, 1); equal(coroutine.status(thread), "suspended")
	truth(coroutine.resume(thread)); equal(coroutine.status(thread), "dead")
	local resolved = f:command("GetSnapshot", { lookupRequestId = "mutation-0001" }, "query-held-002")
	equal(resolved.data.lookup.status, "APPLIED")
end)

test("Held identical retry and conflicting intent cannot execute another mutation", function()
	local f = fixture(); f:open(); local thread = holdPublish(f); local writes = f.store.writes
	equal(f:command("PublishOrganic", { templateId = "snack_meme" }).code, "BUSY")
	equal(f:command("PublishOrganic", { templateId = "snack_thread" }).code, "INVALID_INPUT")
	equal(f.hooks, 1); equal(f.store.writes, writes); truth(coroutine.resume(thread))
end)

test("Held result finishes after idle expiry without reopening dashboard", function()
	local f = fixture(); f:open(); local thread = holdPublish(f)
	f:advance(600); f.router:Step(); equal(f.snapshots[2].message.kind, "ComputerSessionExpired")
	truth(coroutine.resume(thread)); equal(f:last().code, "OK"); equal(f:last().dashboardSession, nil)
	equal(f.snapshots[#f.snapshots].message.kind, "State")
end)

test("Late result contains current reopened generation, never captured old metadata", function()
	local f = fixture(); f:open(); local thread = holdPublish(f)
	local newer = f:open(); truth(coroutine.resume(thread))
	equal(f:last().dashboardSession.dashboardSessionId, newer)
	equal(f.snapshots[#f.snapshots].message.kind, "State")
end)

test("Unregister suppresses all late held completion delivery and presentation", function()
	local f = fixture(); f:open(); local thread = holdPublish(f)
	f.router:Unregister(f.player); truth(coroutine.resume(thread))
	equal(#f.replies, 0); equal(#f.snapshots, 1); equal(f.confirmed, 0)
	f.router:Step(); equal(f.router:PushState(f.player), false)
end)

test("Replacing registration suppresses completion from previous record", function()
	local f = fixture(); f:open(); local thread = holdPublish(f)
	f.router:Register(f.player, f.session); truth(coroutine.resume(thread))
	equal(#f.replies, 0); equal(#f.snapshots, 1); equal(f.confirmed, 0)
end)

test("Durable replay after session reconnect preserves ring authority", function()
	local f = fixture(); f:open(); f:command("PublishOrganic", { templateId = "snack_meme" })
	truth(f.session:Stop().ok); f.router:Unregister(f.player)
	f.session = f.newSession(); truth(f.session:Start().ok); f.router:Register(f.player, f.session); f:open()
	local writes = f.store.writes
	local replay = f:command("PublishOrganic", { templateId = "snack_meme" })
	equal(replay.code, "OK"); equal(f.store.writes, writes)
	local different = f:command("PublishOrganic", { templateId = "snack_thread" })
	equal(different.code, "INVALID_INPUT"); equal(f.store.writes, writes)
	local lookup = f:command("GetSnapshot", { lookupRequestId = "mutation-0001" }, "query-rejoin-001")
	equal(lookup.data.lookup.status, "APPLIED"); equal(lookup.data.lookup.originalResult.code, "OK")
end)

test("Live rejection identity conflicts are rejected and cache stays bounded", function()
	local f = fixture(); f:open()
	for index = 1, 80 do
		f:advance(1)
		equal(f:command("BuyDevice", { deviceId = "phone_fast" }, `reject-cache-{index}`).code, "INSUFFICIENT_FUNDS")
	end
	local record = f.router._records[f.player]
	equal(#record.order, 64)
	local count = 0; for _ in pairs(record.cache) do count += 1 end; equal(count, 64)
	equal(f:command("GetSnapshot", { lookupRequestId = "reject-cache-80" }, "query-cache-001").data.lookup.status, "REJECTED")
end)

test("Query IDs cannot overwrite a known durable mutation identity", function()
	local f = fixture(); f:open(); f:command("PublishOrganic", { templateId = "snack_meme" })
	equal(f:command("GetSnapshot", {}, "mutation-0001").code, "INVALID_INPUT")
end)

test("Projection failure blocks opening and writes; expired lease also blocks", function()
	local f = fixture(); f:open(); f:advance(240)
	local writes = f.store.writes
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "LOCKED")
	equal(f.router:HandlePrompt(f.prompt, f.player), false)
	equal(f.snapshots[#f.snapshots].message.code, "NOT_READY"); equal(f.store.writes, writes)
end)

test("Transport errors permit explicit replay without a second charge", function()
	local p = profile(); p.balance = 100; p.lifetimeEarned = 100
	local f = fixture({ profile = p }); f:open(); f.failReply = true
	f:command("BuyDevice", { deviceId = "phone_fast" }); equal(f.session:GetConfirmedProfile().balance, 50)
	local writes = f.store.writes; f.failReply = false
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "OK"); equal(f.store.writes, writes)
end)

test("Visual failure never rolls back confirmed device purchase", function()
	local p = profile(); p.balance = 100; p.lifetimeEarned = 100
	local f = fixture({ profile = p }); f:open(); f.visualError = true
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "OK")
	equal(f.session:GetConfirmedProfile().deviceId, "phone_fast"); equal(f.session:GetConfirmedProfile().balance, 50)
end)

test("Unexpected accounting callback error is surfaced and releases router pending flag", function()
	local f = fixture(); f:open(); f.hookError = true
	local ok, err = pcall(function() f:command("BuyDevice", { deviceId = "phone_fast" }) end)
	equal(ok, false); truth(string.find(tostring(err), "accounting hook error", 1, true))
	equal(f.router._records[f.player].cache["mutation-0001"].pending, false)
end)

test("World adapter errors deny recoverably without granting dashboard", function()
	local f = fixture(); f.world.GetPrompt = function() error("injected world adapter error", 0) end
	equal(f.router:HandlePrompt(f.prompt, f.player), false)
	equal(f.snapshots[1].message.code, "INVALID_STATE"); equal(f.router._records[f.player].dashboard, nil)
end)

test("Prompt requires exact ProximityPrompt, rejecting anchor and foreign clone", function()
	local f = fixture()
	local anchor = track(Instance.new("Part")); local clone = track(Instance.new("ProximityPrompt"))
	equal(f.router:HandlePrompt(anchor, f.player), false); equal(f.router:HandlePrompt(clone, f.player), false)
	equal(f.router._records[f.player].dashboard, nil)
end)

test("Real WorldService prompt enforces exact identity, living character and 12 studs", function()
	local f = fixture()
	truth(WorldService.Spawn(f.player, f.session:GetConfirmedProfile()))
	table.insert(cleanup, function() WorldService.Remove(f.player) end)
	local prompt = WorldService.GetPrompt(f.player)
	local anchor = WorldService.GetAnchor(f.player, "DashboardPromptAnchor") :: BasePart
	f.world.GetPrompt = WorldService.GetPrompt
	f.world.ValidateDashboardPrompt = WorldService.ValidateDashboardPrompt
	f.root.Position = anchor.Position + Vector3.new(12, 0, 0)
	truth(f.router:HandlePrompt(prompt, f.player))
	f.root.Position = anchor.Position + Vector3.new(12.1, 0, 0)
	equal(f.router:HandlePrompt(prompt, f.player), false)
	equal(f.snapshots[#f.snapshots].message.code, "OUT_OF_RANGE")
	f.root.Position = anchor.Position; f.humanoid.Health = 0
	equal(f.router:HandlePrompt(prompt, f.player), false)
	equal(f.snapshots[#f.snapshots].message.code, "INVALID_STATE")
end)

test("Destroy is idempotent and removes admission and lifecycle delivery", function()
	local f = fixture(); f:open(); f.router:Destroy(); f.router:Destroy()
	equal(f.router:PushState(f.player), false); equal(f.router:HandlePrompt(f.prompt, f.player), false)
	f:command("BuyDevice", { deviceId = "phone_fast" }); f.router:CharacterLost(f.player); f.router:Step()
	equal(#f.replies, 0); equal(#f.snapshots, 1)
end)

test("Real mission claim settles due post once and duplicate claims never credit again", function()
	local f = fixture(); f:open()
	equal(f:command("AcceptMission", { missionId = "food_stall_launch" }, "accept-00001").code, "OK")
	local run = f.session:GetConfirmedProfile().activeMission.runId
	equal(f:command("ClaimMission", { runId = run }, "claim-early-1").code, "NOT_READY")
	equal(f:command("PublishPost", { runId = run, templateId = "meal_meme" }, "publish-0001").code, "OK")
	f:advance(18)
	equal(f:command("ClaimMission", { runId = run }, "claim-final-1").code, "OK")
	equal(f.session:GetConfirmedProfile().balance, 95)
	local writes = f.store.writes
	equal(f:command("ClaimMission", { runId = run }, "claim-final-1").code, "OK")
	equal(f:command("ClaimMission", { runId = run }, "claim-again-1").code, "NOT_READY")
	equal(f.store.writes, writes); equal(f.session:GetConfirmedProfile().balance, 95)
	equal(f.session:GetConfirmedProfile().completedMissions, 1)
end)

test("Two registered real sessions receive only their own projections", function()
	local first = fixture()
	local p = profile(); p.balance = 333; p.lifetimeEarned = 333
	local second = fixture({ profile = p })
	first.router:Register(second.player, second.session)
	first.router:HandleCommand(second.player, { requestId = "second-query-1", action = "GetSnapshot", payload = {} })
	equal(first:last().data.snapshot.balance, 333)
	equal(first.replies[1].player, second.player)
	equal(first:command("GetSnapshot", {}, "first-query-01").data.snapshot.balance, 0)
	equal(first.replies[2].player, first.player)
	equal(#second.replies, 0); equal(#first.snapshots, 0)
end)

test("Real room prompt from another owner cannot open this player's dashboard", function()
	local owner, intruder = fixture(), fixture()
	truth(WorldService.Spawn(owner.player, owner.session:GetConfirmedProfile()))
	truth(WorldService.Spawn(intruder.player, intruder.session:GetConfirmedProfile()))
	table.insert(cleanup, function() WorldService.Remove(owner.player); WorldService.Remove(intruder.player) end)
	intruder.world.GetPrompt = WorldService.GetPrompt
	intruder.world.ValidateDashboardPrompt = WorldService.ValidateDashboardPrompt
	local anchor = WorldService.GetAnchor(owner.player, "DashboardPromptAnchor") :: BasePart
	intruder.root.Position = anchor.Position
	equal(intruder.router:HandlePrompt(WorldService.GetPrompt(owner.player), intruder.player), false)
	equal(intruder.snapshots[1].message.code, "INVALID_STATE")
	equal(intruder.router._records[intruder.player].dashboard, nil)
end)

test("Unstarted real session cannot open or admit economic work", function()
	local f = fixture(); local unloaded = f.newSession()
	f.router:Register(f.player, unloaded)
	equal(f.router:HandlePrompt(f.prompt, f.player), false)
	equal(f.snapshots[1].message.code, "NOT_READY")
	equal(f.hooks, 0)
end)

test("Failed durable save leaves confirmed-only state and blocks fresh mutations", function()
	local p = profile(); p.balance = 100; p.lifetimeEarned = 100
	local f = fixture({ profile = p }); f:open(); f.store.fail = true
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }).code, "SAVE_UNAVAILABLE")
	equal(f.session:GetConfirmedProfile().balance, 100)
	local writes = f.store.writes
	equal(f:command("BuyDevice", { deviceId = "phone_fast" }, "purchase-new-1").code, "SAVE_UNAVAILABLE")
	equal(f.store.writes, writes); equal(f.hooks, 1)
	equal(f.router:HandlePrompt(f.prompt, f.player), false)
	equal(f.snapshots[#f.snapshots].message.code, "SAVE_UNAVAILABLE")
	local lookup = f:command("GetSnapshot", { lookupRequestId = "mutation-0001" }, "query-failed-01")
	equal(lookup.data.snapshot.balance, 100)
	truth(lookup.data.lookup.status == "PENDING" or lookup.data.lookup.status == "UNKNOWN")
	equal(f.store.writes, writes, "failed purchase lookup never retransmits it")
end)

for _, case in ipairs({
	{ name = "long run ID", runId = string.rep("r", 64) },
	{ name = "escaped ASCII run ID", runId = string.rep("\0", 64) },
}) do
	test(`Canonical budget rejects {case.name} before idle and accounting admission`, function()
		local f = fixture(); f:open(); f:advance(20)
		local writes = f.store.writes
		equal(pcall(f.session._canonicalIntent, "PublishPost", { runId = case.runId, templateId = "meal_meme" }), false,
			"fixture must exceed the authoritative encoded budget")
		local result = f:command("PublishPost", { runId = case.runId, templateId = "meal_meme" }, "canonical-budget-1")
		equal(result.code, "INVALID_INPUT")
		equal(result.dashboardSession.expiresAt, 1600)
		equal(f.hooks, 0); equal(f.store.writes, writes)
		equal(f.router._records[f.player].cache["canonical-budget-1"], nil)
	end)
end

test("A close request ID cannot become an economic intent after reopening", function()
	local f = fixture(); f:open()
	equal(f:command("CloseComputer", {}, "close-identity-1").code, "OK")
	f:open(); f:advance(20)
	local writes = f.store.writes
	local result = f:command("BuyDevice", { deviceId = "phone_fast" }, "close-identity-1")
	equal(result.code, "INVALID_INPUT"); equal(result.dashboardSession.expiresAt, 1600)
	equal(f.hooks, 0); equal(f.store.writes, writes)
end)

test("A durable mutation ID cannot close a fresh dashboard after router cache replacement", function()
	local f = fixture(); f:open()
	equal(f:command("PublishOrganic", { templateId = "snack_meme" }, "durable-close-1").code, "OK")
	f.router:Register(f.player, f.session)
	local current = f:open()
	local writes = f.store.writes
	local result = f:command("CloseComputer", {}, "durable-close-1")
	equal(result.code, "INVALID_INPUT")
	equal(result.dashboardSession.dashboardSessionId, current)
	equal(f.router._records[f.player].dashboard.id, current)
	equal(f.store.writes, writes)
end)

test("Registered session before Start replies NOT_READY to well-shaped economic commands", function()
	local f = fixture(); local unloaded = f.newSession()
	f.router:Register(f.player, unloaded)
	local writes = f.store.writes
	f.router:HandleCommand(f.player, {
		requestId = "unloaded-command-1", action = "BuyDevice",
		payload = { deviceId = "phone_fast" }, dashboardSessionId = "not-yet-open",
	})
	equal(f:last().code, "NOT_READY"); equal(f:last().revision, 0)
	equal(f.hooks, 0); equal(f.store.writes, writes)
end)

local passed, failed = 0, 0
for _, case in ipairs(tests) do
	local ok, err = pcall(case.fn)
	for index = #cleanup, 1, -1 do
		local cleaned, cleanupError = pcall(cleanup[index])
		if not cleaned then ok, err = false, cleanupError end
	end
	table.clear(cleanup)
	if ok then passed += 1; print(`[PASS] {case.name}`)
	else failed += 1; print(`[FAIL] {case.name}: {tostring(err)}`) end
end
print(`NetRouter spec: {passed}/{passed + failed} passed, {failed} failed`)
if failed > 0 then error("NetRouter spec failed", 0) end
return `NetRouter: {passed}/{passed + failed} passed`
