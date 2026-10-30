--!strict
-- Buzzer Simulator — ClientState spec (BS-07).
-- Verifies the client state machine, network event reduction, generation replacement,
-- request correlation, timeout handling, and snapshot reconciliation.
-- Contract sources: docs/03, docs/05, docs/14.

local StarterPlayer = game:GetService("StarterPlayer")
local ServerStorage = game:GetService("ServerStorage")

local ClientState do
	local spScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if spScripts and spScripts:FindFirstChild("ClientState") then
		ClientState = require(spScripts.ClientState) :: any
	elseif ServerStorage:FindFirstChild("ClientState") then
		ClientState = require(ServerStorage.ClientState) :: any
	else
		local sps = StarterPlayer:WaitForChild("StarterPlayerScripts")
		ClientState = require(sps:WaitForChild("ClientState")) :: any
	end
end

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`, 0)
	end
end

local function expectTrue(val: boolean, label: string)
	if not val then
		error(`{label}: expected true, got false`, 0)
	end
end

local function expectFalse(val: boolean, label: string)
	if val then
		error(`{label}: expected false, got true`, 0)
	end
end

local function sampleSnapshot(rev: number?, balance: number?): any
	return {
		revision = rev or 1,
		serverTime = 1000,
		balance = balance or 100,
		pendingWorkerCuan = 45,
		incomePerSecond = 1.5,
		lifetimeEarned = 200,
		completedMissions = 1,
		tier = 0,
		maxShippedTier = 0,
		deviceId = "phone_cheap",
		ownedDesks = {},
		workers = {},
		activeMission = nil,
		pendingPost = nil,
		nextOrganicContextId = "organic_snack",
		ownPosts = {},
		feedVersion = 1,
		saveStatus = "healthy",
	}
end

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

-- 1. State snapshot updates without opening UI
test("State snapshot updates without opening UI", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	expectEqual(state:Get().status, "Closed", "initial status")

	local updated = sampleSnapshot(2, 75)
	local applied = state:ApplyStateSnapshot(updated)
	expectTrue(applied, "snapshot applied")
	expectEqual(state:Get().status, "Closed", "status remains Closed")
	expectEqual(state:GetConfirmedBalance(), 75, "confirmed balance updated")
	expectEqual(state:Get().latestRevision, 2, "latest revision updated")
end)

-- 2. Valid OpenComputer
test("Valid OpenComputer transitions status to Opening", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	local openEvent = {
		kind = "OpenComputer",
		dashboardSessionId = "sess_001",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 60),
	}
	local applied = state:ApplyOpenComputer(openEvent, 1000)
	expectTrue(applied, "OpenComputer applied")
	expectEqual(state:Get().status, "Opening", "status is Opening")
	expectEqual(state:Get().dashboardSessionId, "sess_001", "session ID set")
	expectEqual(state:Get().expiresAt, 1600, "expiresAt set")
	expectEqual(state:GetConfirmedBalance(), 60, "balance updated")
end)

-- 3. OpenComputerDenied does not transition camera
test("OpenComputerDenied does not transition camera or open UI", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputerDenied("NOT_READY")
	expectEqual(state:Get().status, "Closed", "status remains Closed")
	expectEqual(state:Get().activeDenial, "NOT_READY", "denial recorded")
	expectFalse(state:Get().cameraCaptured, "camera not captured")
end)

-- 4. Generation replacement
test("Generation replacement preserves open status without recapturing camera", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_001",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 50),
	}, 1000)
	state:OnCameraOpened()
	expectEqual(state:Get().status, "Open", "opened")
	expectTrue(state:Get().cameraCaptured, "camera captured")

	-- Replace with sess_002
	local replaced = state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_002",
		expiresAt = 2200,
		serverTime = 1600,
		state = sampleSnapshot(3, 80),
	}, 1600)
	expectTrue(replaced, "replaced")
	expectEqual(state:Get().status, "Open", "still open")
	expectEqual(state:Get().dashboardSessionId, "sess_002", "new session ID")
	expectTrue(state:Get().cameraCaptured, "camera stays captured without reset")
end)

-- 5. Stale expiry ignored
test("Stale expiry ignored for an older session", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_002",
		expiresAt = 2200,
		serverTime = 1600,
		state = sampleSnapshot(2, 50),
	}, 1600)
	state:OnCameraOpened()

	-- Expire sess_001 (stale)
	local expired = state:ApplySessionExpired("sess_001", "IDLE")
	expectFalse(expired, "stale expiry rejected")
	expectEqual(state:Get().status, "Open", "remains Open")
	expectEqual(state:Get().dashboardSessionId, "sess_002", "session ID preserved")
end)

-- 6. Matching expiry closes dashboard
test("Matching expiry closes dashboard and marks session Expired", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_002",
		expiresAt = 2200,
		serverTime = 1600,
		state = sampleSnapshot(2, 50),
	}, 1600)
	state:OnCameraOpened()

	local expired = state:ApplySessionExpired("sess_002", "IDLE")
	expectTrue(expired, "expiry accepted")
	expectEqual(state:Get().status, "Expired", "status Expired")
	expectEqual(state:Get().dashboardSessionId, nil, "session ID cleared")
	expectTrue(state:Get().closedGenerations["sess_002"], "closed generation recorded")
end)

-- 7. Local watchdog expiration
test("Local watchdog expiration closes dashboard if deadline passes without server event", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_watchdog",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 50),
	}, 1000)
	state:OnCameraOpened()

	-- Local time 1200: not expired yet
	local expiredEarly = state:CheckLocalWatchdog(1200)
	expectFalse(expiredEarly, "not expired at 1200")
	expectEqual(state:Get().status, "Open", "still Open")

	-- Local time 1601: expired!
	local expiredLate = state:CheckLocalWatchdog(1601)
	expectTrue(expiredLate, "watchdog expired at 1601")
	expectEqual(state:Get().status, "Expired", "status Expired")
	expectTrue(state:Get().closedGenerations["sess_watchdog"], "closed generation recorded")
end)

-- 8. Close during opening tween
test("Close during opening tween transitions status to Closing and clears session", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_fastclose",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 50),
	}, 1000)
	expectEqual(state:Get().status, "Opening", "is opening")

	local cmd = state:CloseLocally()
	expectTrue(cmd ~= nil, "command emitted")
	expectEqual(cmd.action, "CloseComputer", "action is CloseComputer")
	expectEqual(cmd.dashboardSessionId, "sess_fastclose", "session ID matches")
	expectEqual(state:Get().status, "Closing", "status is Closing")
	expectEqual(state:Get().dashboardSessionId, nil, "session cleared")
end)

-- 9. Duplicate close
test("Duplicate close is idempotent and does not emit command twice", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_dup",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 50),
	}, 1000)
	state:OnCameraOpened()

	local cmd1 = state:CloseLocally()
	expectTrue(cmd1 ~= nil, "first close succeeds")

	local cmd2 = state:CloseLocally()
	expectEqual(cmd2, nil, "second close returns nil")
	expectEqual(state:Get().status, "Closing", "status stays Closing")
end)

-- 10. Death during camera transition
test("Death during camera transition immediately closes session", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_death",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 50),
	}, 1000)
	expectEqual(state:Get().status, "Opening", "opening")

	local wasActive = state:OnCharacterLost()
	expectTrue(wasActive, "was active")
	expectEqual(state:Get().status, "Closed", "closed")
	expectEqual(state:Get().dashboardSessionId, nil, "session cleared")
end)

-- 11. Respawn and CameraSubject recovery
test("Respawn and CameraSubject recovery handles camera restore cycle", function()
	local state = ClientState.new(sampleSnapshot(1, 50))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_respawn",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(2, 50),
	}, 1000)
	state:OnCameraOpened()
	expectTrue(state:Get().cameraCaptured, "camera captured")

	state:OnCharacterLost()
	expectEqual(state:Get().status, "Closed", "closed on death")

	state:OnCameraRestored()
	expectFalse(state:Get().cameraCaptured, "camera uncaptured")
end)

-- 12. HUD still updates while UI closed
test("HUD still updates while UI closed", function()
	local state = ClientState.new(sampleSnapshot(1, 10))
	expectEqual(state:Get().status, "Closed", "closed")

	state:ApplyStateSnapshot(sampleSnapshot(2, 25))
	expectEqual(state:Get().status, "Closed", "remains closed")
	expectEqual(state:GetConfirmedBalance(), 25, "balance updated while closed")
end)

-- 13. Old revision cannot replace newer confirmed balance
test("Old revision cannot replace newer confirmed balance", function()
	local state = ClientState.new(sampleSnapshot(5, 500))
	local applied = state:ApplyStateSnapshot(sampleSnapshot(4, 100))
	expectFalse(applied, "older revision dropped")
	expectEqual(state:GetConfirmedBalance(), 500, "balance not regressed")
end)

-- 14. New revision updates confirmed balance
test("New revision updates confirmed balance", function()
	local state = ClientState.new(sampleSnapshot(5, 500))
	local applied = state:ApplyStateSnapshot(sampleSnapshot(6, 650))
	expectTrue(applied, "newer revision accepted")
	expectEqual(state:GetConfirmedBalance(), 650, "balance updated")
end)

-- 15. PendingWorkerCuan never enters spendable balance
test("PendingWorkerCuan never enters spendable balance", function()
	local snap = sampleSnapshot(1, 100)
	snap.pendingWorkerCuan = 90
	local state = ClientState.new(snap)

	expectEqual(state:GetConfirmedBalance(), 100, "spendable is exactly confirmed balance")
	expectEqual(state:GetPendingWorkerCuan(), 90, "pending is separate")
end)

-- 16. GetSnapshot correlation
test("GetSnapshot correlation removes in-flight query and updates state", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:TrackRequest("qry_01", "GetSnapshot", false, 1000, nil)
	expectTrue(state:Get().inFlightRequests["qry_01"] ~= nil, "tracked")

	local reply = {
		requestId = "qry_01",
		ok = true,
		code = "OK",
		revision = 2,
		serverTime = 1001,
		data = {
			snapshot = sampleSnapshot(2, 120),
		},
	}
	state:ApplyReply(reply, 1001)
	expectEqual(state:Get().inFlightRequests["qry_01"], nil, "in-flight cleared")
	expectEqual(state:GetConfirmedBalance(), 120, "balance reconciled")
end)

-- 17. APPLIED lookup handling
test("APPLIED lookup handling resolves uncertain mutation", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:TrackRequest("mut_01", "BuyDevice", true, 1000, nil)

	-- Simulate timeout:
	local queries = state:CheckTimeouts(1007, 6)
	expectEqual(#queries, 1, "generated reconciliation query")
	expectEqual(queries[1].payload.lookupRequestId, "mut_01", "lookup matches mut_01")
	expectEqual(state:Get().status, "ConnectionUncertain", "status uncertain")

	-- Reconcile via reply with APPLIED
	local reply = {
		requestId = queries[1].requestId,
		ok = true,
		code = "OK",
		revision = 2,
		serverTime = 1008,
		data = {
			snapshot = sampleSnapshot(2, 50),
			lookup = {
				originalRequestId = "mut_01",
				status = "APPLIED",
				originalResult = { ok = true, code = "OK", revision = 2 },
			},
		},
	}
	state:ApplyReply(reply, 1008)
	expectEqual(state:Get().uncertainMutations["mut_01"], nil, "uncertain resolved")
	expectEqual(state:Get().status, "Closed", "status restored")
	expectEqual(state:GetConfirmedBalance(), 50, "balance updated")
end)

-- 18. REJECTED lookup handling
test("REJECTED lookup handling clears uncertain mutation without retransmitting", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:TrackRequest("mut_02", "BuyDevice", true, 1000, nil)
	local queries = state:CheckTimeouts(1007, 6)
	expectEqual(#queries, 1, "reconciliation query generated")

	local reply = {
		requestId = queries[1].requestId,
		ok = true,
		code = "OK",
		revision = 1,
		serverTime = 1008,
		data = {
			lookup = {
				originalRequestId = "mut_02",
				status = "REJECTED",
				originalResult = { ok = false, code = "INSUFFICIENT_FUNDS", revision = 1 },
			},
		},
	}
	state:ApplyReply(reply, 1008)
	expectEqual(state:Get().uncertainMutations["mut_02"], nil, "uncertain cleared")
	expectEqual(state:Get().status, "Closed", "status restored")
end)

-- 19. PENDING preservation
test("PENDING preservation keeps uncertain mutation in flight", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:TrackRequest("mut_03", "PublishOrganic", true, 1000, nil)
	local queries = state:CheckTimeouts(1007, 6)

	local reply = {
		requestId = queries[1].requestId,
		ok = true,
		code = "OK",
		revision = 1,
		serverTime = 1008,
		data = {
			lookup = {
				originalRequestId = "mut_03",
				status = "PENDING",
			},
		},
	}
	state:ApplyReply(reply, 1008)
	expectTrue(state:Get().uncertainMutations["mut_03"] ~= nil, "still preserved as uncertain")
	expectEqual(state:Get().status, "ConnectionUncertain", "status remains uncertain")
end)

-- 20. UNKNOWN does not retry
test("UNKNOWN lookup does not trigger automatic retry or retransmission", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:TrackRequest("mut_04", "PublishOrganic", true, 1000, nil)
	local queries = state:CheckTimeouts(1007, 6)

	local reply = {
		requestId = queries[1].requestId,
		ok = true,
		code = "OK",
		revision = 1,
		serverTime = 1008,
		data = {
			lookup = {
				originalRequestId = "mut_04",
				status = "UNKNOWN",
			},
		},
	}
	state:ApplyReply(reply, 1008)
	-- Clears uncertain without retransmitting
	expectEqual(state:Get().uncertainMutations["mut_04"], nil, "uncertain cleared on UNKNOWN")
	expectEqual(state:Get().status, "Closed", "returned to normal")
	expectEqual(next(state:Get().inFlightRequests), nil, "no new request issued")
end)

-- 21. Late Reply does not reopen
test("Late Reply does not reopen closed dashboard", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:TrackRequest("qry_late", "GetSnapshot", false, 1000, nil)
	expectEqual(state:Get().status, "Closed", "closed")

	local reply = {
		requestId = "qry_late",
		ok = true,
		code = "OK",
		revision = 2,
		serverTime = 1010,
		dashboardSession = {
			dashboardSessionId = "sess_old",
			expiresAt = 1600,
		},
		data = {
			snapshot = sampleSnapshot(2, 100),
		},
	}
	state:ApplyReply(reply, 1010)
	expectEqual(state:Get().status, "Closed", "remains closed after reply")
end)

-- 22. Matching dashboard metadata refreshes watchdog
test("Matching dashboard metadata in Reply refreshes watchdog deadline", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_active",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	state:OnCameraOpened()

	local initialWatchdog = state:Get().localWatchdogTime

	state:TrackRequest("req_action", "AcceptMission", true, 1050, nil)
	local reply = {
		requestId = "req_action",
		ok = true,
		code = "OK",
		revision = 2,
		serverTime = 1050,
		dashboardSession = {
			dashboardSessionId = "sess_active",
			expiresAt = 2200, -- extended!
		},
	}
	state:ApplyReply(reply, 1050)
	expectEqual(state:Get().expiresAt, 2200, "expiresAt updated")
	expectTrue(state:Get().localWatchdogTime > initialWatchdog, "watchdog refreshed")
end)

-- 23. Stale dashboard metadata cannot refresh a new session
test("Stale dashboard metadata cannot refresh a new session watchdog", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_brandnew",
		expiresAt = 2200,
		serverTime = 1600,
		state = sampleSnapshot(2, 100),
	}, 1600)
	state:OnCameraOpened()

	local watchdog = state:Get().localWatchdogTime

	-- Reply carries stale metadata from sess_old
	local reply = {
		requestId = "old_req",
		ok = true,
		code = "OK",
		revision = 1,
		serverTime = 1605,
		dashboardSession = {
			dashboardSessionId = "sess_old",
			expiresAt = 1700,
		},
	}
	state:ApplyReply(reply, 1605)
	expectEqual(state:Get().dashboardSessionId, "sess_brandnew", "session ID preserved")
	expectEqual(state:Get().expiresAt, 2200, "expiresAt not corrupted")
	expectEqual(state:Get().localWatchdogTime, watchdog, "watchdog not corrupted")
end)

-- 24. Blocked save state disables future economic actions
test("Blocked save state is reported accurately by IsSaveBlocked", function()
	local healthySnap = sampleSnapshot(1, 100)
	healthySnap.saveStatus = "healthy"
	local state1 = ClientState.new(healthySnap)
	expectFalse(state1:IsSaveBlocked(), "healthy save not blocked")

	local blockedSnap = sampleSnapshot(2, 100)
	blockedSnap.saveStatus = "SAVE_UNAVAILABLE"
	local state2 = ClientState.new(blockedSnap)
	expectTrue(state2:IsSaveBlocked(), "SAVE_UNAVAILABLE is blocked")
end)

-- 25. UI cleanup does not leave duplicate listeners
test("UI cleanup does not leave duplicate listeners", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	local callCount = 0
	local unsub = state:Subscribe(function()
		callCount += 1
	end)
	-- Subscribe immediately calls listener once
	expectEqual(callCount, 1, "initial call")

	state:ApplyStateSnapshot(sampleSnapshot(2, 110))
	expectEqual(callCount, 2, "second call")

	unsub()
	state:ApplyStateSnapshot(sampleSnapshot(3, 120))
	expectEqual(callCount, 2, "no further calls after unsubscribe")
end)

-- 26. Cancel tween during opening prevents late callback from reopening or capturing camera
test("Cancelled opening transition prevents late OnCameraOpened from reopening or capturing camera", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_cancel_test",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	expectEqual(state:Get().status, "Opening", "state is Opening")
	expectFalse(state:Get().cameraCaptured, "camera not captured yet")

	-- User cancels/closes while opening tween is in-flight:
	local closeCmd = state:CloseLocally()
	expectTrue(closeCmd ~= nil, "close command returned")
	expectEqual(state:Get().status, "Closing", "state is Closing")

	-- Late camera tween Completed callback fires now:
	local opened = state:OnCameraOpened()
	expectFalse(opened, "OnCameraOpened rejected because status is not Opening")
	expectEqual(state:Get().status, "Closing", "status remained Closing")
	expectFalse(state:Get().cameraCaptured, "camera was not marked captured")

	-- Camera restoration finishes:
	state:OnCameraRestored()
	expectEqual(state:Get().status, "Closed", "state is Closed")
	expectFalse(state:Get().cameraCaptured, "camera not captured")
end)

-- 27. Delayed SESSION_EXPIRED reply for an older session cannot close a newly opened session
test("Delayed SESSION_EXPIRED reply for older session does not close active newer session", function()
	local state = ClientState.new(sampleSnapshot(1, 100))

	-- 1. Open session A
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_A",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	state:OnCameraOpened()
	expectEqual(state:Get().status, "Open", "Session A is Open")
	expectEqual(state:Get().dashboardSessionId, "sess_A", "Session ID is sess_A")

	-- Track request sent under session A
	state:TrackRequest("req_A_mut", "BuyDevice", true, 1005, nil, "sess_A")

	-- 2. Close session A
	local closeCmd = state:CloseLocally()
	expectTrue(closeCmd ~= nil, "CloseComputer generated")
	state:OnCameraRestored()
	expectEqual(state:Get().status, "Closed", "Session A closed")

	-- 3. Open session B
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_B",
		expiresAt = 2200,
		serverTime = 1020,
		state = sampleSnapshot(2, 100),
	}, 1020)
	state:OnCameraOpened()
	expectEqual(state:Get().status, "Open", "Session B is Open")
	expectEqual(state:Get().dashboardSessionId, "sess_B", "Session ID is sess_B")

	-- 4. Delayed SESSION_EXPIRED arrives for req_A_mut (which belonged to sess_A)
	local expiredReply = {
		requestId = "req_A_mut",
		code = "SESSION_EXPIRED",
		ok = false,
	}
	local applied = state:ApplyReply(expiredReply, 1025)
	expectFalse(applied, "stale reply rejected from closing active session")
	expectEqual(state:Get().status, "Open", "Session B remains Open")
	expectEqual(state:Get().dashboardSessionId, "sess_B", "Session B ID preserved")
	expectTrue(state:Get().cameraCaptured, "Camera remains captured for Session B")
end)

-- 28. Uncorrelated old SESSION_EXPIRED reply cannot close current session
test("Uncorrelated old SESSION_EXPIRED reply cannot close current session", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_active_01",
		expiresAt = 2000,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	state:OnCameraOpened()

	local reply = {
		requestId = "unknown_ancient_req",
		code = "SESSION_EXPIRED",
		ok = false,
	}
	local applied = state:ApplyReply(reply, 1010)
	expectFalse(applied, "uncorrelated reply ignored")
	expectEqual(state:Get().status, "Open", "Active session remains Open")
	expectEqual(state:Get().dashboardSessionId, "sess_active_01", "Active session ID preserved")
end)

-- 29. GetStatus returns current status string matching Get().status
test("GetStatus returns current status string matching Get().status", function()
	local state = ClientState.new(sampleSnapshot(1, 100))
	expectEqual(state:GetStatus(), "Closed", "initial status is Closed")
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_status_test",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	expectEqual(state:GetStatus(), "Opening", "status is Opening")
	state:OnCameraOpened()
	expectEqual(state:GetStatus(), "Open", "status is Open")
	state:CloseLocally()
	expectEqual(state:GetStatus(), "Closing", "status is Closing")
	state:OnCameraRestored()
	expectEqual(state:GetStatus(), "Closed", "status is Closed")
end)

-- Runner loop
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
print(`ClientState spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print("FAILURES:")
	for _, f in ipairs(failures) do
		print(`  - {f}`)
	end
	error(`ClientState spec: {#failures} failed`, 0)
end
return `ClientState: {passed}/{#tests} passed`
