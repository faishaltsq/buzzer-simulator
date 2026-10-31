--!strict
local StarterPlayer = game:GetService("StarterPlayer")
local ClientState = require(StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("ClientState") :: any) :: any

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end
local function equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 0)
	end
end
local function truth(value: any, label: string?)
	if not value then error(label or "expected truthy value", 0) end
end
local function count(value: any): number
	local result = 0
	for _ in pairs(value) do result += 1 end
	return result
end
local function snapshot(revision: number?): any
	return {
		revision = revision or 1, serverTime = 1000, balance = 100,
		pendingWorkerCuan = 0, incomePerSecond = 0, lifetimeEarned = 0,
		completedMissions = 0, tier = 0, maxShippedTier = 0,
		deviceId = "phone_cheap", ownedDesks = {}, workers = {},
		activeMission = nil, pendingPost = nil, nextOrganicContextId = "organic_snack",
		ownPosts = {}, feedVersion = 1, saveStatus = "healthy",
	}
end
local function mission(status: string?, posts: number?): any
	return {
		missionId = "food_stall_launch", runId = "run-original", contextId = "meal_time",
		status = status or "accepted", accumulatedImpact = 0, postCount = posts or 0,
	}
end
local function open(state: any, id: string?, revision: number?)
	state:ApplyOpenComputer({
		kind = "OpenComputer", dashboardSessionId = id or "session-original",
		expiresAt = 1600, serverTime = 1000, state = snapshot(revision),
	}, 1000)
	state:OnCameraOpened()
end
local function fixture(snap: any?): any
	local state = ClientState.new()
	open(state)
	if snap ~= nil then state:ApplyStateSnapshot(snap) end
	return state
end
local function reply(id: string, revision: number?, ok: boolean?, code: string?): any
	return {
		requestId = id, ok = if ok == nil then true else ok,
		code = code or "OK", revision = revision or 1, serverTime = 1001,
	}
end
local function lookupReply(query: any, original: string, status: string, snap: any?, result: any?): any
	local value = reply(query.requestId, if snap then snap.revision else 1)
	value.data = {
		snapshot = snap,
		lookup = { originalRequestId = original, status = status, originalResult = result },
	}
	return value
end

-- These exercise the returned wire commands rather than a separate UI approximation.
test("Organic admission returns one exact session-bound command and reserves before notification", function()
	local state = fixture()
	local notifiedRequest = nil
	local duplicate = nil
	state:Subscribe(function(data)
		if next(data.inFlightRequests) ~= nil and notifiedRequest == nil then
			notifiedRequest = next(data.inFlightRequests)
			duplicate = state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1000)
		end
	end)
	local input = { templateId = "snack_thread" }
	local command = state:BeginMutation("PublishOrganic", input, 1000)
	truth(command, "command admitted")
	equal(command.action, "PublishOrganic")
	equal(command.dashboardSessionId, "session-original")
	equal(count(command), 4, "exact envelope")
	equal(count(command.payload), 1, "exact payload")
	equal(command.payload.templateId, "snack_thread")
	truth(#command.requestId >= 8 and #command.requestId <= 64, "bounded request ID")
	equal(string.find(command.requestId, "[^%z\1-\127]"), nil, "ASCII request ID")
	equal(notifiedRequest, command.requestId, "subscriber sees reservation immediately")
	equal(duplicate, nil, "reentrant cross-mode tap blocked")
	equal(count(state:Get().inFlightRequests), 1)
	input.templateId = "snack_honest"
	equal(command.payload.templateId, "snack_thread", "payload detached from caller")
	equal(state:GetConfirmedBalance(), 100, "no optimistic money")
end)

for _, case in ipairs({
	{ action = "AcceptMission", payload = { missionId = "food_stall_launch" }, active = nil, fields = 1 },
	{ action = "PublishPost", payload = { runId = "run-original", templateId = "meal_meme" }, active = mission(), fields = 2 },
	{ action = "ClaimMission", payload = { runId = "run-original" }, active = mission("readyToClaim", 1), fields = 1 },
}) do
	test(`{case.action} emits only its frozen ID fields`, function()
		local snap = snapshot()
		snap.activeMission = case.active
		local command = fixture(snap):BeginMutation(case.action, case.payload, 1000)
		truth(command)
		equal(count(command.payload), case.fields)
		for key, value in pairs(case.payload) do equal(command.payload[key], value, key) end
		equal(command.dashboardSessionId, "session-original")
	end)
end

for _, action in ipairs({ "BuyDevice", "BuyDesk", "HireWorker", "CloseComputer", "GetSnapshot", "MadeUp" }) do
	test(`BeginMutation does not admit {action}`, function()
		local state = fixture()
		equal(state:BeginMutation(action, {}, 1000), nil)
		equal(next(state:Get().inFlightRequests), nil)
		truth(string.find(state:Get().activeError, "UNKNOWN_ACTION", 1, true))
	end)
end

for _, case in ipairs({
	{ action = "PublishOrganic", payload = { templateId = "snack_meme", balance = 999 } },
	{ action = "PublishOrganic", payload = { templateId = "meal_meme" } },
	{ action = "PublishOrganic", payload = { templateId = "missing" } },
	{ action = "PublishOrganic", payload = {} },
	{ action = "AcceptMission", payload = { missionId = "unshipped_mission" } },
	{ action = "PublishPost", payload = { runId = "run-original", templateId = "snack_meme" } },
	{ action = "PublishPost", payload = { runId = "old-run", templateId = "meal_meme" } },
	{ action = "ClaimMission", payload = { runId = "old-run" } },
	{ action = "ClaimMission", payload = { runId = "run-original", reward = 80 } },
}) do
	test(`Rejects invalid {case.action} payload {tostring(case.payload.templateId or case.payload.missionId or case.payload.runId)}`, function()
		local snap = snapshot()
		snap.activeMission = mission("readyToClaim", 1)
		local state = fixture(snap)
		equal(state:BeginMutation(case.action, case.payload, 1000), nil)
		equal(next(state:Get().inFlightRequests), nil)
		truth(state:Get().activeError)
	end)
end

for _, status in ipairs({ "Closed", "Opening", "Closing", "Expired", "ConnectionUncertain" }) do
	test(`Mutation cannot start while dashboard is {status}`, function()
		local state = fixture()
		state:Get().status = status
		equal(state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000), nil)
		truth(state:MutationBlockReason())
		local query = state:RefreshProgress(1000)
		equal(query.action, "GetSnapshot", "reads remain available")
		equal(query.dashboardSessionId, nil)
	end)
end

for _, saveStatus in ipairs({ "SAVE_UNAVAILABLE", "BUSY" }) do
	test(`Save status {saveStatus} blocks all mutation modes but permits refresh`, function()
		local snap = snapshot()
		snap.saveStatus = saveStatus
		local state = fixture(snap)
		truth(state:IsSaveBlocked())
		truth(state:MutationBlockReason())
		equal(state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1000), nil)
		equal(state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000), nil)
		local query = state:RefreshProgress(1000)
		equal(count(query.payload), 0)
		equal(query.dashboardSessionId, nil)
		truth(state:Get().inFlightRequests[query.requestId])
	end)
end

test("Open without a confirmed writable snapshot cannot mutate", function()
	local state = ClientState.new()
	state:ApplyOpenComputer({ dashboardSessionId = "session-empty", expiresAt = 1600, serverTime = 1000 }, 1000)
	state:OnCameraOpened()
	truth(state:MutationBlockReason())
	equal(state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000), nil)
end)

for _, pendingMode in ipairs({ "organic", "mission" }) do
	for _, action in ipairs({ "PublishOrganic", "PublishPost" }) do
		test(`Pending {pendingMode} post blocks {action} across modes`, function()
			local snap = snapshot()
			snap.pendingPost = { mode = pendingMode, settleAt = 1018 }
			snap.activeMission = mission()
			local state = fixture(snap)
			local payload = if action == "PublishOrganic" then { templateId = "snack_meme" }
				else { runId = "run-original", templateId = "meal_meme" }
			equal(state:BeginMutation(action, payload, 1000), nil)
			equal(next(state:Get().inFlightRequests), nil)
		end)
	end
end

test("Pending organic post does not block accepting a mission", function()
	local snap = snapshot()
	snap.pendingPost = { mode = "organic", settleAt = 1018 }
	truth(fixture(snap):BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1000))
end)

test("Active mission or pending campaign post blocks another acceptance", function()
	local snap = snapshot()
	snap.activeMission = mission()
	equal(fixture(snap):BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1000), nil)
	snap.activeMission = nil
	snap.pendingPost = { mode = "mission", settleAt = 1018 }
	equal(fixture(snap):BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1000), nil)
end)

test("Campaign publish cap is two and ready mission only accepts claim", function()
	local snap = snapshot()
	snap.activeMission = mission("accepted", 2)
	local state = fixture(snap)
	equal(state:BeginMutation("PublishPost", { runId = "run-original", templateId = "meal_meme" }, 1000), nil)
	truth(string.find(state:Get().activeError, "LIMIT_REACHED", 1, true))
	snap.activeMission = mission("accepted", 1)
	equal(fixture(snap):BeginMutation("ClaimMission", { runId = "run-original" }, 1000), nil)
	snap.activeMission = mission("readyToClaim", 1)
	equal(fixture(snap):BeginMutation("PublishPost", { runId = "run-original", templateId = "meal_meme" }, 1000), nil)
	snap.activeMission = mission("accepted", 1)
	truth(fixture(snap):BeginMutation("PublishPost", { runId = "run-original", templateId = "meal_meme" }, 1000))
end)

test("All tracked economic actions share the posting lock", function()
	local state = fixture()
	state:TrackRequest("upgrade-inflight", "BuyDevice", true, 1000)
	equal(state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000), nil)
	local query = state:RefreshProgress(1000)
	equal(query.payload.lookupRequestId, "upgrade-inflight")
	equal(query.dashboardSessionId, nil)
end)

test("Six second timeout looks up original ID with a tracked fresh query without changing camera lifecycle", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	equal(#state:CheckTimeouts(1005.999), 0)
	local queries = state:CheckTimeouts(1006)
	equal(#queries, 1)
	local query = queries[1]
	equal(query.action, "GetSnapshot")
	equal(query.payload.lookupRequestId, command.requestId)
	truth(query.requestId ~= command.requestId)
	equal(query.dashboardSessionId, nil)
	equal(count(query), 3)
	equal(state:Get().inFlightRequests[query.requestId].lookupRequestId, command.requestId)
	equal(state:Get().inFlightRequests[query.requestId].dashboardSessionId, nil)
	equal(state:Get().uncertainMutations[command.requestId].dashboardSessionId, "session-original")
	equal(state:GetStatus(), "Open")
	equal(state:Get().cameraCaptured, true)
	equal(#state:CheckTimeouts(1012), 0, "no mutation retransmission or polling loop")
	truth(state:MutationBlockReason())
end)

for _, status in ipairs({ "PENDING", "UNKNOWN" }) do
	test(`{status} lookup preserves reservation until an explicit later resolution`, function()
		local state = fixture()
		local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
		local query = state:CheckTimeouts(1006)[1]
		state:ApplyReply(lookupReply(query, command.requestId, status, snapshot(2)), 1007)
		truth(state:Get().uncertainMutations[command.requestId])
		truth(state:MutationBlockReason())
		equal(state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1007), nil)
		equal(#state:CheckTimeouts(1015), 0)
		local refresh = state:RefreshProgress(1015)
		equal(refresh.payload.lookupRequestId, command.requestId)
		truth(refresh.requestId ~= query.requestId and refresh.requestId ~= command.requestId)
		equal(refresh.dashboardSessionId, nil)
		state:ApplyReply(lookupReply(refresh, command.requestId, "REJECTED", snapshot(2), {
			ok = false, code = "NOT_READY", revision = 2,
		}), 1016)
		equal(state:Get().uncertainMutations[command.requestId], nil)
		equal(state:MutationBlockReason(), nil)
		truth(string.find(state:Get().activeError, "NOT_READY", 1, true))
	end)
end

test("An arbitrary or mismatched lookup cannot release a mutation reservation", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local query = state:CheckTimeouts(1006)[1]
	local result = { ok = false, code = "NOT_READY", revision = 1 }
	equal(state:ApplyReply(lookupReply({ requestId = "untracked-query" }, command.requestId, "REJECTED", nil, result), 1007), false)
	truth(state:Get().uncertainMutations[command.requestId])
	state:ApplyReply(lookupReply(query, "different-original", "REJECTED", snapshot(2), result), 1007)
	truth(state:Get().uncertainMutations[command.requestId])
	equal(state:Get().resolvedLookups["different-original"], nil)
	local ordinary = state:RefreshProgress(1008)
	state:ApplyReply(lookupReply(ordinary, command.requestId, "APPLIED", nil, nil), 1009)
	truth(state:Get().uncertainMutations[command.requestId], "APPLIED requires originalResult")
end)

test("A plain snapshot query cannot reconcile an unrelated payload lookup", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local plain = { requestId = "plain-query" }
	state:TrackRequest(plain.requestId, "GetSnapshot", false, 1005, nil)
	state:CheckTimeouts(1006)
	state:ApplyReply(lookupReply(plain, command.requestId, "REJECTED", snapshot(2), {
		ok = false, code = "NOT_READY", revision = 2,
	}), 1007)
	truth(state:Get().uncertainMutations[command.requestId])
end)

test("Late original rejection resolves UNKNOWN without reopening a closed dashboard", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local query = state:CheckTimeouts(1006)[1]
	state:ApplyReply(lookupReply(query, command.requestId, "UNKNOWN"), 1007)
	state:CloseLocally()
	state:OnCameraRestored()
	state:ApplyReply(reply(command.requestId, 1, false, "NOT_READY"), 1008)
	equal(state:Get().uncertainMutations[command.requestId], nil)
	equal(state:GetStatus(), "Closed")
	equal(state:Get().cameraCaptured, false)
	truth(string.find(state:Get().activeError, "NOT_READY", 1, true))
	open(state, "session-new")
	equal(state:MutationBlockReason(), nil)
end)

test("Timeout after local close cannot reopen and a new dashboard retains the reservation", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	state:CloseLocally()
	state:OnCameraRestored()
	state:CheckTimeouts(1006)
	equal(state:GetStatus(), "Closed")
	equal(state:Get().cameraCaptured, false)
	equal(state:ApplyOpenComputer({ dashboardSessionId = "session-original" }, 1007), false, "closed generation rejected")
	open(state, "session-new", 2)
	truth(state:MutationBlockReason())
	equal(state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1008), nil)
	state:ApplyReply(reply(command.requestId, 2, false, "NOT_READY"), 1009)
	equal(state:GetStatus(), "Open")
	equal(state:Get().dashboardSessionId, "session-new")
	equal(state:MutationBlockReason(), nil)
end)

test("Expired and character-lost dashboards stay closed through timeout and delayed original success", function()
	for _, close in ipairs({
		function(state: any) state:ApplySessionExpired("session-original", "IDLE") end,
		function(state: any) state:OnCharacterLost() end,
	}) do
		local state = fixture()
		local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
		close(state)
		local status = state:GetStatus()
		state:CheckTimeouts(1006)
		equal(state:GetStatus(), status)
		state:ApplyReply(reply(command.requestId, 2), 1007)
		equal(state:GetStatus(), status)
		equal(state:Get().dashboardSessionId, nil)
		equal(state:GetConfirmedBalance(), 100)
	end
end)

test("Stale original SESSION_EXPIRED resolves old reservation without expiring the newer generation", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	state:CheckTimeouts(1006)
	state:CloseLocally()
	state:OnCameraRestored()
	open(state, "session-new", 2)
	local expired = reply(command.requestId, 2, false, "SESSION_EXPIRED")
	expired.dashboardSession = { dashboardSessionId = "session-new", expiresAt = 1600 }
	state:ApplyReply(expired, 1007)
	equal(state:GetStatus(), "Open")
	equal(state:Get().dashboardSessionId, "session-new")
	equal(state:Get().uncertainMutations[command.requestId], nil)
	equal(state:Get().cameraCaptured, true)
end)

test("Replacing a generation invalidates its old OpenComputer event without recapturing camera", function()
	local state = fixture()
	open(state, "session-new", 2)
	equal(state:ApplyOpenComputer({ dashboardSessionId = "session-original", state = snapshot(3) }, 1001), false)
	equal(state:Get().dashboardSessionId, "session-new")
	equal(state:GetStatus(), "Open")
	equal(state:Get().cameraCaptured, true)
end)

test("Ordinary OK waits for its actual revision snapshot without fabricating confirmed state", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	state:ApplyReply(reply(command.requestId, 3), 1001)
	equal(state:Get().latestRevision, 1, "Reply revision is not a snapshot")
	equal(state:Get().snapshot.revision, 1)
	equal(state:GetConfirmedBalance(), 100)
	truth(state:MutationBlockReason(), "success confirmation barrier")
	equal(state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1001), nil)
	local middle = snapshot(2)
	middle.balance = 110
	equal(state:ApplyStateSnapshot(middle), true, "intermediate snapshot can still update HUD")
	equal(state:GetConfirmedBalance(), 110)
	truth(state:MutationBlockReason())
	local confirmed = snapshot(3)
	confirmed.balance = 115
	state:ApplyStateSnapshot(confirmed)
	equal(state:MutationBlockReason(), nil)
	equal(state:GetConfirmedBalance(), 115)
	local nextCommand = state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1002)
	truth(nextCommand)
	truth(nextCommand.requestId ~= command.requestId, "fresh identity on next intent")
end)

test("Snapshot arriving before success Reply satisfies the confirmation barrier", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	state:ApplyStateSnapshot(snapshot(3))
	truth(state:MutationBlockReason(), "in-flight request still reserved")
	state:ApplyReply(reply(command.requestId, 2), 1001)
	equal(state:MutationBlockReason(), nil)
	equal(state:Get().latestRevision, 3)
end)

test("APPLIED lookup waits for original success revision and later query snapshot confirms it", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local query = state:CheckTimeouts(1006)[1]
	state:ApplyReply(lookupReply(query, command.requestId, "APPLIED", snapshot(2), {
		ok = true, code = "OK", revision = 3,
	}), 1007)
	equal(state:Get().uncertainMutations[command.requestId], nil)
	truth(state:MutationBlockReason())
	local refresh = state:RefreshProgress(1008)
	equal(refresh.payload.lookupRequestId, nil, "only confirmed snapshot remains outstanding")
	local confirmed = reply(refresh.requestId, 3)
	confirmed.data = { snapshot = snapshot(3) }
	state:ApplyReply(confirmed, 1009)
	equal(state:MutationBlockReason(), nil)
end)

test("Late original success after timeout retains barrier until authoritative State arrives", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local query = state:CheckTimeouts(1006)[1]
	state:ApplyReply(reply(command.requestId, 2), 1007)
	equal(state:Get().uncertainMutations[command.requestId], nil)
	truth(state:MutationBlockReason())
	state:ApplyStateSnapshot(snapshot(2))
	equal(state:MutationBlockReason(), nil)
	state:ApplyReply(lookupReply(query, command.requestId, "UNKNOWN", snapshot(2)), 1008)
	equal(state:MutationBlockReason(), nil, "old query cannot resurrect resolved reservation")
end)

test("Duplicate Reply cannot clear a newer mutation and older snapshots cannot regress confirmation", function()
	local state = fixture()
	local first = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	state:ApplyReply(reply(first.requestId, 2), 1001)
	state:ApplyStateSnapshot(snapshot(2))
	local second = state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1002)
	truth(second)
	equal(state:ApplyReply(reply(first.requestId, 2), 1003), false)
	truth(state:Get().inFlightRequests[second.requestId])
	state:ApplyReply(reply(second.requestId, 3), 1004)
	equal(state:ApplyStateSnapshot(snapshot(1)), false)
	truth(state:MutationBlockReason())
	state:ApplyStateSnapshot(snapshot(3))
	state:ApplyStateSnapshot(snapshot(3))
	equal(state:MutationBlockReason(), nil)
	equal(state:Get().latestRevision, 3)
end)

test("Untracked Reply or action-shaped snapshot data cannot fabricate authoritative state", function()
	local state = fixture()
	local untracked = reply("untracked-reply", 99)
	untracked.data = { snapshot = snapshot(99) }
	equal(state:ApplyReply(untracked, 1001), false)
	equal(state:Get().latestRevision, 1)
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local actionReply = reply(command.requestId, 2)
	actionReply.data = { snapshot = snapshot(99) }
	state:ApplyReply(actionReply, 1001)
	equal(state:Get().snapshot.revision, 1)
	truth(state:MutationBlockReason())
end)

for _, code in ipairs({ "SAVE_UNAVAILABLE", "BUSY" }) do
	test(`Ordinary {code} Reply cannot release a possibly persisted action`, function()
		local state = fixture()
		local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
		state:ApplyReply(reply(command.requestId, 1, false, code), 1001)
		truth(state:Get().uncertainMutations[command.requestId], "retain ambiguous original identity")
		equal(state:Get().snapshot.saveStatus, "healthy", "last snapshot can still be healthy")
		truth(state:MutationBlockReason())
		equal(state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1001), nil)
		equal(state:GetStatus(), "Open")
		truth(string.find(state:Get().activeError, "BUSY", 1, true), "duplicate feedback remains readable")
		local query = state:RefreshProgress(1002)
		equal(query.payload.lookupRequestId, command.requestId)
		state:ApplyReply(lookupReply(query, command.requestId, "REJECTED", snapshot(2), {
			ok = false, code = code, revision = 2,
		}), 1003)
		equal(state:Get().uncertainMutations[command.requestId], nil, "explicit REJECTED is definitive")
		equal(state:MutationBlockReason(), nil)
	end)
end

test("BeginMutation expires a passed local watchdog before returning any envelope", function()
	local state = fixture()
	equal(state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1600), nil)
	equal(state:GetStatus(), "Expired")
	equal(state:Get().dashboardSessionId, nil)
	equal(next(state:Get().inFlightRequests), nil)
	equal(state:Get().closedGenerations["session-original"], true)
end)

test("Uncertain dashboard remains navigable and closable and its watchdog still runs", function()
	local state = fixture()
	local command = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	state:CheckTimeouts(1006)
	state:SetTab("Missions")
	equal(state:Get().currentTab, "Missions")
	equal(state:GetStatus(), "Open")
	equal(state:CheckLocalWatchdog(1599), false)
	equal(state:CheckLocalWatchdog(1600), true)
	equal(state:GetStatus(), "Expired")
	truth(state:Get().uncertainMutations[command.requestId])
	local another = fixture()
	another:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	another:CheckTimeouts(1006)
	local close = another:CloseLocally()
	truth(close)
	equal(close.action, "CloseComputer")
	another:OnCameraRestored()
	equal(another:GetStatus(), "Closed")
end)

test("Replacement generation admits new actions only after the old original identity resolves", function()
	local state = fixture()
	local first = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	open(state, "session-replacement", 2)
	equal(state:Get().inFlightRequests[first.requestId].dashboardSessionId, "session-original")
	equal(state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1001), nil)
	state:ApplyReply(reply(first.requestId, 2, false, "NOT_READY"), 1002)
	local second = state:BeginMutation("AcceptMission", { missionId = "food_stall_launch" }, 1003)
	truth(second)
	equal(second.dashboardSessionId, "session-replacement")
	truth(second.requestId ~= first.requestId)
end)

test("Read query may resolve the original while its Reply is still in flight", function()
	local state = fixture()
	local original = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local query = state:RefreshProgress(1001)
	equal(query.payload.lookupRequestId, original.requestId)
	state:ApplyReply(lookupReply(query, original.requestId, "APPLIED", snapshot(2), {
		ok = true, code = "OK", revision = 2,
	}), 1002)
	equal(state:Get().inFlightRequests[original.requestId], nil)
	equal(state:MutationBlockReason(), nil)
	equal(state:ApplyReply(reply(original.requestId, 2), 1003), false, "duplicate original already reconciled")
end)

test("Legacy ConnectionUncertain resolution restores only its existing generation", function()
	local state = fixture()
	local original = state:BeginMutation("PublishOrganic", { templateId = "snack_meme" }, 1000)
	local query = state:CheckTimeouts(1006)[1]
	state:Get().status = "ConnectionUncertain"
	state:ApplyReply(lookupReply(query, original.requestId, "REJECTED", snapshot(2), {
		ok = false, code = "NOT_READY", revision = 2,
	}), 1007)
	equal(state:GetStatus(), "Open")
	equal(state:Get().dashboardSessionId, "session-original")
	equal(state:Get().cameraCaptured, true)
end)

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
print(`PostingState spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then error(table.concat(failures, "\n"), 0) end
return `PostingState: {passed}/{#tests} passed`
