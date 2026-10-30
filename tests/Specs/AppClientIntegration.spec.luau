--!strict
-- Buzzer Simulator — AppClientIntegration spec (BS-07).
-- Integration tests for the full client runtime pipeline in App.client.luau:
-- ClientState subscription, Desktop/HUD coordination, camera transitions,
-- tween completion callback safety (including state:GetStatus() check),
-- reduced motion mode, session expiry, character loss, and generation isolation.
-- Contract sources: docs/03, docs/05, docs/14.

local StarterPlayer = game:GetService("StarterPlayer")
local spScripts = StarterPlayer:WaitForChild("StarterPlayerScripts", 10) :: Folder
local ClientState = require(spScripts:WaitForChild("ClientState", 10) :: any) :: any
local uiFolder = spScripts:WaitForChild("ui", 10) :: Folder
local Hud = require(uiFolder:WaitForChild("Hud", 10) :: any) :: any
local Desktop = require(uiFolder:WaitForChild("Desktop", 10) :: any) :: any
local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
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
		pendingWorkerCuan = 0,
		incomePerSecond = 0,
		tier = 0,
		deviceId = "starter_phone",
		equippedDeviceId = "starter_phone",
		saveStatus = "healthy",
		workers = {},
		missions = {},
		recentMutationOutcomes = {},
		ownPosts = {},
	}
end

-- Helper to construct an App client pipeline simulation
local function createAppPipeline(
	reducedMotion: boolean?,
	findAnchorsFn: (() -> (any, any))?,
	onSendCommand: ((any) -> ())?
)
	local isReduced = reducedMotion or false
	local testGuiContainer = Instance.new("Folder")

	local state = ClientState.new(sampleSnapshot(1, 100))
	local hud = Hud.new({ parent = testGuiContainer })
	local desktop = Desktop.new({
		parent = testGuiContainer,
		playerName = "TestPlayer",
		onClose = function() end,
		onTabSelected = function() end,
	})

	local fakeCamera = {
		CameraType = Enum.CameraType.Custom,
		CFrame = CFrame.new(0, 5, 10),
		FieldOfView = 70,
	}

	local preCameraState = {
		captured = false,
		cameraType = Enum.CameraType.Custom,
		cframe = CFrame.identity,
		fieldOfView = 70,
	}

	local openingGeneration = 0
	local isTransitioningCamera = false
	local activeTweenCompletedCallback: ((any) -> ())? = nil

	local function restoreCameraAndControls()
		openingGeneration += 1
		isTransitioningCamera = false
		activeTweenCompletedCallback = nil
		if not preCameraState.captured then
			if fakeCamera.CameraType == Enum.CameraType.Scriptable then
				fakeCamera.CameraType = preCameraState.cameraType or Enum.CameraType.Custom
			end
			return
		end
		fakeCamera.CameraType = preCameraState.cameraType or Enum.CameraType.Custom
		fakeCamera.CFrame = preCameraState.cframe or CFrame.identity
		fakeCamera.FieldOfView = preCameraState.fieldOfView or 70
		preCameraState.captured = false
		state:OnCameraRestored()
	end

	local function transitionCameraToComputer(onComplete: () -> ())
		if isTransitioningCamera then
			return
		end
		isTransitioningCamera = true
		openingGeneration += 1
		local thisGeneration = openingGeneration

		if not preCameraState.captured then
			preCameraState.captured = true
			preCameraState.cameraType = fakeCamera.CameraType
			preCameraState.cframe = fakeCamera.CFrame
			preCameraState.fieldOfView = fakeCamera.FieldOfView
		end

		-- Resolve anchors
		local cameraFocus, terminalSlot = true, true
		if findAnchorsFn ~= nil then
			cameraFocus, terminalSlot = findAnchorsFn()
		end

		if cameraFocus == nil or terminalSlot == nil then
			local closeCmd = state:AbortOpening("Terminal camera anchor missing")
			if onSendCommand ~= nil and closeCmd ~= nil then
				onSendCommand(closeCmd)
			end
			restoreCameraAndControls()
			desktop:SetVisible(false, isReduced)
			hud:SetDashboardOpen(false, isReduced)
			isTransitioningCamera = false
			return
		end

		fakeCamera.CameraType = Enum.CameraType.Scriptable
		local targetCFrame = CFrame.new(7.4, 4.5, -3)

		if isReduced then
			fakeCamera.CFrame = targetCFrame
			isTransitioningCamera = false
			-- Verify state:GetStatus() method call in reduced motion path:
			if thisGeneration == openingGeneration and state:GetStatus() == "Opening" then
				onComplete()
			end
		else
			-- Simulate tween
			fakeCamera.CFrame = targetCFrame
			activeTweenCompletedCallback = function(playbackState: any)
				isTransitioningCamera = false
				if playbackState ~= Enum.PlaybackState.Completed then
					return
				end
				if thisGeneration ~= openingGeneration then
					return
				end
				-- Verify state:GetStatus() method call in tween completed path:
				if state:GetStatus() ~= "Opening" then
					return
				end
				onComplete()
			end
		end
	end

	-- Subscribe matching App.client.luau
	state:Subscribe(function(stateData)
		hud:Update(stateData, nil)
		desktop:Update(stateData)

		if stateData.status == "Opening" then
			hud:SetDashboardOpen(true, isReduced)
			transitionCameraToComputer(function()
				state:OnCameraOpened()
				desktop:SetVisible(true, isReduced)
			end)
		elseif stateData.status == "Open" then
			desktop:SetVisible(true, isReduced)
			hud:SetDashboardOpen(true, isReduced)
		elseif stateData.status == "Closing" or stateData.status == "Expired" or stateData.status == "Closed" then
			desktop:SetVisible(false, isReduced)
			hud:SetDashboardOpen(false, isReduced)
			if preCameraState.captured then
				restoreCameraAndControls()
			end
		end
	end)

	return {
		state = state,
		hud = hud,
		desktop = desktop,
		fakeCamera = fakeCamera,
		preCameraState = preCameraState,
		restoreCameraAndControls = restoreCameraAndControls,
		fireTweenCompleted = function(playbackState)
			if activeTweenCompletedCallback ~= nil then
				local cb = activeTweenCompletedCallback
				activeTweenCompletedCallback = nil
				cb(playbackState or Enum.PlaybackState.Completed)
			end
		end,
		hasActiveTween = function()
			return activeTweenCompletedCallback ~= nil
		end,
	}
end

-- 1. Valid server OpenComputer transitions Opening -> Open and Desktop becomes visible
test("Valid server OpenComputer transitions Opening to Open via tween completion with no error", function()
	local app = createAppPipeline(false)
	expectEqual(app.state:GetStatus(), "Closed", "initial status Closed")
	expectFalse(app.desktop:IsVisible(), "desktop initially hidden")

	-- Server sends OpenComputer snapshot
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_integration_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)

	expectEqual(app.state:GetStatus(), "Opening", "state entered Opening")
	expectFalse(app.desktop:IsVisible(), "desktop not visible during camera tween")
	expectEqual(app.fakeCamera.CameraType, Enum.CameraType.Scriptable, "camera set to Scriptable")
	expectTrue(app.hasActiveTween(), "tween callback active")

	-- Camera tween finishes -> calls state:GetStatus() -> OnCameraOpened -> desktop visible
	app.fireTweenCompleted(Enum.PlaybackState.Completed)

	expectEqual(app.state:GetStatus(), "Open", "state entered Open")
	expectTrue(app.desktop:IsVisible(), "desktop is now visible")
	expectTrue(app.state:Get().cameraCaptured, "camera is marked captured")
end)

-- 2. Reduced motion opening transitions immediately without tween
test("Reduced motion opening transitions Opening to Open immediately", function()
	local app = createAppPipeline(true)
	expectEqual(app.state:GetStatus(), "Closed", "initial status Closed")

	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_rm_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)

	expectEqual(app.state:GetStatus(), "Open", "reduced motion opens immediately")
	expectTrue(app.desktop:IsVisible(), "desktop visible immediately")
	expectFalse(app.hasActiveTween(), "no tween created")
end)

-- 3. Cancellation during opening prevents late callback from reopening and restores camera
test("Cancellation while Opening cancels tween, restores camera, and rejects late callback", function()
	local app = createAppPipeline(false)
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_cancel_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	expectEqual(app.state:GetStatus(), "Opening", "in Opening")

	-- User presses Escape / Close during tween:
	app.state:CloseLocally()
	app.restoreCameraAndControls()

	expectEqual(app.state:GetStatus(), "Closed", "status restored to Closed")
	expectEqual(app.fakeCamera.CameraType, Enum.CameraType.Custom, "camera restored to Custom")
	expectFalse(app.desktop:IsVisible(), "desktop is not visible")

	-- Late tween completed callback fires:
	app.fireTweenCompleted(Enum.PlaybackState.Completed)
	expectEqual(app.state:GetStatus(), "Closed", "status remains Closed")
	expectFalse(app.desktop:IsVisible(), "desktop never reopens")
end)

-- 4. User Close from Open restores camera and hides Desktop
test("User close from Open hides desktop and restores camera", function()
	local app = createAppPipeline(true)
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_close_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	expectEqual(app.state:GetStatus(), "Open", "is Open")
	expectTrue(app.desktop:IsVisible(), "desktop visible")

	-- Close
	app.state:CloseLocally()
	expectEqual(app.state:GetStatus(), "Closed", "status Closed")
	expectFalse(app.desktop:IsVisible(), "desktop hidden")
	expectEqual(app.fakeCamera.CameraType, Enum.CameraType.Custom, "camera restored to Custom")
end)

-- 5. Session expiry closes Desktop and restores camera
test("Session expiry transitions Open to Expired, hides desktop, and restores camera", function()
	local app = createAppPipeline(true)
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_expire_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	expectEqual(app.state:GetStatus(), "Open", "is Open")

	app.state:ApplySessionExpired("sess_expire_01", "SESSION_EXPIRED")
	-- Subscriber synchronously runs restoreCameraAndControls() on Expired, which calls state:OnCameraRestored(), transitioning Expired -> Closed.
	expectEqual(app.state:GetStatus(), "Closed", "status Closed after camera restoration")
	expectFalse(app.desktop:IsVisible(), "desktop hidden")
	expectEqual(app.fakeCamera.CameraType, Enum.CameraType.Custom, "camera restored")
end)

-- 6. Character death closes Desktop and restores camera immediately
test("Character death closes Desktop and restores camera", function()
	local app = createAppPipeline(true)
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_death_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	expectEqual(app.state:GetStatus(), "Open", "is Open")

	app.state:OnCharacterLost()
	app.restoreCameraAndControls()

	expectEqual(app.state:GetStatus(), "Closed", "status Closed")
	expectFalse(app.desktop:IsVisible(), "desktop hidden")
	expectEqual(app.fakeCamera.CameraType, Enum.CameraType.Custom, "camera restored")
end)

-- 7. Repeated State snapshots while Closed never trigger Opening or Desktop visibility
test("Repeated State snapshots never trigger Opening or Desktop visibility", function()
	local app = createAppPipeline(false)
	expectEqual(app.state:GetStatus(), "Closed", "initial Closed")

	for rev = 2, 5 do
		app.state:ApplyStateSnapshot(sampleSnapshot(rev, 100 + rev * 10))
		expectEqual(app.state:GetStatus(), "Closed", "remains Closed")
		expectFalse(app.desktop:IsVisible(), "desktop remains hidden")
		expectFalse(app.hasActiveTween(), "no tween created")
	end
end)

-- 8. Repeated OpenComputer while already Open does not spawn duplicate transitions
test("Repeated OpenComputer on active session updates session without duplicate opening transitions", function()
	local app = createAppPipeline(false)
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_dup_01",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)
	app.fireTweenCompleted(Enum.PlaybackState.Completed)
	expectEqual(app.state:GetStatus(), "Open", "is Open")

	-- Server sends replacement OpenComputer with higher expiry:
	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_dup_02",
		expiresAt = 2200,
		serverTime = 1050,
		state = sampleSnapshot(2, 110),
	}, 1050)

	expectEqual(app.state:GetStatus(), "Open", "remains Open")
	expectTrue(app.desktop:IsVisible(), "desktop remains visible")
	expectEqual(app.state:Get().dashboardSessionId, "sess_dup_02", "session ID updated")
	expectFalse(app.hasActiveTween(), "did not create a second tween")
end)
-- 9. Missing anchor during opening aborts opening, closes server session, and never loops
test("Missing anchor during opening aborts opening, closes server session, and never loops", function()
	local sentCommands = {}
	local app = createAppPipeline(false, function()
		return nil, nil -- Simulates missing CameraFocus or TerminalSlot
	end, function(cmd)
		table.insert(sentCommands, cmd)
	end)

	app.state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_missing_anchor",
		expiresAt = 1600,
		serverTime = 1000,
		state = sampleSnapshot(1, 100),
	}, 1000)

	expectEqual(app.state:GetStatus(), "Closed", "status immediately Closed on missing anchor")
	expectEqual(app.fakeCamera.CameraType, Enum.CameraType.Custom, "camera restored to Custom, never Scriptable")
	expectFalse(app.desktop:IsVisible(), "desktop never opens")
	expectEqual(app.state:Get().activeError, "Terminal camera anchor missing", "activeError set")
	expectEqual(#sentCommands, 1, "exactly one CloseComputer command sent to server")
	expectEqual(sentCommands[1].action, "CloseComputer", "action is CloseComputer")
	expectEqual(sentCommands[1].dashboardSessionId, "sess_missing_anchor", "correct session closed on server")
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
print(`AppClientIntegration spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print("FAILURES:")
	for _, f in ipairs(failures) do
		print(`  - {f}`)
	end
	error(`AppClientIntegration spec: {#failures} failed`, 0)
end
return `AppClientIntegration: {passed}/{#tests} passed`
