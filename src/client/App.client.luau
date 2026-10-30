--!strict
-- Buzzer Simulator — App.client.luau (BS-07)
-- Main client entry script running under StarterPlayer.StarterPlayerScripts.
-- Owns network connections, camera transitions, HUD, and BuzzerOS desktop shell.
-- Contract sources: docs/03, docs/05, docs/14.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local ClientState = require(script.Parent:WaitForChild("ClientState") :: any)
local uiFolder = script.Parent:WaitForChild("ui")
local Theme = require(uiFolder:WaitForChild("Theme") :: any)
local Hud = require(uiFolder:WaitForChild("Hud") :: any)
local Desktop = require(uiFolder:WaitForChild("Desktop") :: any)

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera

-- Resolve PlayerModule controls
local controls: any = nil
pcall(function()
	local PlayerModule = require(playerScripts:WaitForChild("PlayerModule", 5) :: any) :: any
	controls = PlayerModule:GetControls()
end)

-- Reduced motion helper
local function isReducedMotion(): boolean
	local ok, enabled = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and (enabled == true)
end

-- Initialize state container
local state = ClientState.new(nil)

-- Camera restoration record
local preCameraState = {
	captured = false,
	cameraType = Enum.CameraType.Custom,
	cameraSubject = nil :: Instance?,
	cframe = CFrame.identity,
	fieldOfView = 70,
	activeTween = nil :: Tween?,
}
local openingGeneration = 0
-- Forward declarations
local hud: any = nil
local desktop: any = nil
local remotesFolder: Folder? = nil
local commandRemote: RemoteEvent? = nil

-- Network helper: send command to server
local function sendCommand(envelope: any)
	if commandRemote ~= nil then
		commandRemote:FireServer(envelope)
	end
end

-- Resolve room and camera anchors
local function findRoomAnchors(): (BasePart?, BasePart?)
	local roomFolder = Workspace:FindFirstChild(`BuzzerRoom_{player.UserId}`)
	if roomFolder == nil then
		-- Search for any room folder belonging to player
		for _, child in ipairs(Workspace:GetChildren()) do
			if child.Name == `BuzzerRoom_{player.UserId}` then
				roomFolder = child
				break
			end
		end
	end

	if roomFolder ~= nil then
		local room = roomFolder:FindFirstChild("Room") or roomFolder
		local cameraFocus = room:FindFirstChild("CameraFocus", true) :: BasePart?
		local terminalSlot = room:FindFirstChild("TerminalSlot", true) :: BasePart?
		return cameraFocus, terminalSlot
	end

	return nil, nil
end

-- Disable player controls safely
local function disableControls()
	if controls ~= nil and typeof(controls.Disable) == "function" then
		pcall(function()
			controls:Disable()
		end)
	end
end

-- Enable player controls safely
local function enableControls()
	if controls ~= nil and typeof(controls.Enable) == "function" then
		pcall(function()
			controls:Enable()
		end)
	end
end

-- Critical camera & control restoration (idempotent, single execution per open cycle)
local function restoreCameraAndControls()
	openingGeneration += 1 -- Invalidate any pending camera tween completion callbacks

	-- Cancel in-flight camera tween if active
	if preCameraState.activeTween ~= nil then
		local tweenToCancel = preCameraState.activeTween
		preCameraState.activeTween = nil
		tweenToCancel:Cancel()
	end

	if not preCameraState.captured then
		-- Ensure camera is never left stuck at Scriptable
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = preCameraState.cameraType or Enum.CameraType.Custom
			camera.FieldOfView = preCameraState.fieldOfView or 70
		end
		enableControls()
		return
	end

	-- Restore camera properties
	camera.CameraType = preCameraState.cameraType or Enum.CameraType.Custom

	-- Safely restore subject (prevent destroyed instances on respawn)
	local char = player.Character
	local hum = if char ~= nil then char:FindFirstChildOfClass("Humanoid") else nil
	if preCameraState.cameraSubject ~= nil and preCameraState.cameraSubject.Parent ~= nil then
		camera.CameraSubject = preCameraState.cameraSubject
	elseif hum ~= nil then
		camera.CameraSubject = hum
	end

	camera.FieldOfView = preCameraState.fieldOfView or 70

	-- Restore controls
	enableControls()

	preCameraState.captured = false
	state:OnCameraRestored()

	-- Unbind close action
	pcall(function()
		ContextActionService:UnbindAction("BuzzerOS_Close")
	end)
end

-- Transition camera to computer view
local function transitionCameraToComputer(onComplete: () -> ())
	openingGeneration += 1
	local thisGeneration = openingGeneration

	-- 1. Capture original camera state
	if not preCameraState.captured then
		preCameraState.captured = true
		preCameraState.cameraType = camera.CameraType
		preCameraState.cameraSubject = camera.CameraSubject
		preCameraState.cframe = camera.CFrame
		preCameraState.fieldOfView = camera.FieldOfView
	end

	-- 2. Disable movement controls
	disableControls()

	-- 3. Resolve room anchors
	local cameraFocus, terminalSlot = findRoomAnchors()
	if cameraFocus == nil or terminalSlot == nil then
		-- Fail safely: anchors unavailable, do not point camera into empty sky.
		-- Abort transition, restore camera and controls, and close locally.
		restoreCameraAndControls()
		state:CloseLocally()
		desktop:SetVisible(false, isReducedMotion())
		hud:SetDashboardOpen(false, isReducedMotion())
		return
	end

	local screenCenter = terminalSlot.Position + Vector3.new(0, 1.4, 0)
	local targetCFrame = CFrame.lookAt(cameraFocus.Position, screenCenter)

	-- 4. Set Scriptable and tween
	camera.CameraType = Enum.CameraType.Scriptable

	if isReducedMotion() then
		camera.CFrame = targetCFrame
		if thisGeneration == openingGeneration and state:GetStatus() == "Opening" then
			onComplete()
		end
	else
		if preCameraState.activeTween ~= nil then
			local oldTween = preCameraState.activeTween
			preCameraState.activeTween = nil
			oldTween:Cancel()
		end

		local tweenInfo = TweenInfo.new(0.32, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		local tween = TweenService:Create(camera, tweenInfo, { CFrame = targetCFrame })
		preCameraState.activeTween = tween

		local conn: RBXScriptConnection? = nil
		conn = tween.Completed:Connect(function(playbackState)
			if conn ~= nil then
				conn:Disconnect()
				conn = nil
			end
			if preCameraState.activeTween == tween then
				preCameraState.activeTween = nil
			end

			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			if thisGeneration ~= openingGeneration then
				return
			end
			if state:GetStatus() ~= "Opening" then
				return
			end

			onComplete()
		end)
		tween:Play()
	end

	-- Bind Escape key to close
	ContextActionService:BindAction("BuzzerOS_Close", function(_actionName, inputState, _inputObj)
		if inputState == Enum.UserInputState.Begin then
			local closeCmd = state:CloseLocally()
			if closeCmd ~= nil then
				sendCommand(closeCmd)
			end
			restoreCameraAndControls()
			desktop:SetVisible(false, isReducedMotion())
			hud:SetDashboardOpen(false, isReducedMotion())
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Escape)
end

-- Handle user clicking Close on the desktop shell
local function handleUserClose()
	local closeCmd = state:CloseLocally()
	if closeCmd ~= nil then
		sendCommand(closeCmd)
	end
	restoreCameraAndControls()
	desktop:SetVisible(false, isReducedMotion())
	hud:SetDashboardOpen(false, isReducedMotion())
end

-- Instantiate HUD and Desktop UI
hud = Hud.new({
	parent = playerGui,
})

desktop = Desktop.new({
	parent = playerGui,
	playerName = player.DisplayName or player.Name,
	onClose = handleUserClose,
	onTabSelected = function(tabId)
		state:SetTab(tabId :: any)
	end,
})
-- Expose references for verification and testing
_G.BuzzerState = state
_G.BuzzerDesktop = desktop
_G.BuzzerHud = hud


-- Subscribe to state mutations
state:Subscribe(function(stateData)
	hud:Update(stateData, player)
	desktop:Update(stateData)

	-- Handle status transitions
	if stateData.status == "Opening" then
		hud:SetDashboardOpen(true, isReducedMotion())
		transitionCameraToComputer(function()
			state:OnCameraOpened()
			desktop:SetVisible(true, isReducedMotion())
		end)
	elseif stateData.status == "Open" then
		desktop:SetVisible(true, isReducedMotion())
		hud:SetDashboardOpen(true, isReducedMotion())
	elseif stateData.status == "Closing" or stateData.status == "Expired" or stateData.status == "Closed" then
		desktop:SetVisible(false, isReducedMotion())
		hud:SetDashboardOpen(false, isReducedMotion())
		if preCameraState.captured then
			restoreCameraAndControls()
		end
	end
end)

-- Connect character lifecycle (Death, Removal, Respawn)
local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid ~= nil then
		humanoid.Died:Connect(function()
			state:OnCharacterLost()
			restoreCameraAndControls()
			desktop:SetVisible(false, isReducedMotion())
			hud:SetDashboardOpen(false, isReducedMotion())
		end)
	end
end

if player.Character ~= nil then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
	-- On respawn, ensure controls are cleanly restored if they were locked
	if preCameraState.captured then
		restoreCameraAndControls()
		desktop:SetVisible(false, isReducedMotion())
		hud:SetDashboardOpen(false, isReducedMotion())
	end
end)

-- Network Event Wiring
local function setupNetworking()
	remotesFolder = ReplicatedStorage:WaitForChild("BuzzerRemotes", 10) :: Folder?
	if remotesFolder == nil then
		warn("[App.client] BuzzerRemotes folder not found in ReplicatedStorage")
		return
	end

	local cmd = remotesFolder:WaitForChild("Command", 5) :: RemoteEvent?
	local reply = remotesFolder:WaitForChild("Reply", 5) :: RemoteEvent?
	local snapshot = remotesFolder:WaitForChild("Snapshot", 5) :: RemoteEvent?

	commandRemote = cmd

	if snapshot ~= nil then
		snapshot.OnClientEvent:Connect(function(event: any)
			if event == nil or typeof(event.kind) ~= "string" then
				return
			end

			if event.kind == "State" then
				state:ApplyStateSnapshot(event.state)
			elseif event.kind == "OpenComputer" then
				state:ApplyOpenComputer(event, os.time())
			elseif event.kind == "OpenComputerDenied" then
				state:ApplyOpenComputerDenied(event.code)
			elseif event.kind == "ComputerSessionExpired" then
				state:ApplySessionExpired(event.dashboardSessionId, event.reason)
			end
		end)
	end

	if reply ~= nil then
		reply.OnClientEvent:Connect(function(rep: any)
			state:ApplyReply(rep, os.time())
		end)
	end

	-- Send initial query for authoritative snapshot on join
	local queryId = ClientState.GenerateRequestId("init")
	state:TrackRequest(queryId, "GetSnapshot", false, os.time(), nil)
	sendCommand({
		action = "GetSnapshot",
		requestId = queryId,
		payload = {},
	})
end

task.spawn(setupNetworking)

-- Heartbeat Loop: Local Watchdog and Mutation Timeout Checker
RunService.Heartbeat:Connect(function()
	local now = os.time()

	-- Check local watchdog expiration
	local expired = state:CheckLocalWatchdog(now)
	if expired then
		restoreCameraAndControls()
		desktop:SetVisible(false, isReducedMotion())
		hud:SetDashboardOpen(false, isReducedMotion())
	end

	-- Check 6-second mutation timeouts
	local reconQueries = state:CheckTimeouts(now, 6)
	for _, query in ipairs(reconQueries) do
		sendCommand(query)
	end
end)

-- Player Attribute Change Listeners for HUD status banners
player:GetAttributeChangedSignal("BuzzerReady"):Connect(function()
	hud:Update(state:Get(), player)
end)
player:GetAttributeChangedSignal("BuzzerLoadError"):Connect(function()
	hud:Update(state:Get(), player)
end)
player:GetAttributeChangedSignal("BuzzerWorldError"):Connect(function()
	hud:Update(state:Get(), player)
end)
