--!strict
-- ReviewPanelRelay.server.luau  —  STUDIO-ONLY.
-- Receives review commands from ReviewPanel (client) via RemoteEvent.
-- Handles progression presets, profile resets, teleportation, and backdrop switching.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	error("[ReviewPanelRelay] REFUSE: not Studio.", 0)
end

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")
local Workspace          = game:GetService("Workspace")
local ServerStorage      = game:GetService("ServerStorage")
local HttpService        = game:GetService("HttpService")

-- ===== Remote setup in ReplicatedStorage =====
local remotesFolder = ReplicatedStorage:FindFirstChild("ReviewRemotes")
if remotesFolder == nil then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "ReviewRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local commandRemote = remotesFolder:FindFirstChild("ReviewCommand") :: RemoteEvent
if commandRemote == nil then
	commandRemote = Instance.new("RemoteEvent")
	commandRemote.Name = "ReviewCommand"
	commandRemote.Parent = remotesFolder
end

local notifyRemote = remotesFolder:FindFirstChild("ReviewNotify") :: RemoteEvent
if notifyRemote == nil then
	notifyRemote = Instance.new("RemoteEvent")
	notifyRemote.Name = "ReviewNotify"
	notifyRemote.Parent = remotesFolder
end

-- ===== Backend & Runtime helpers =====
local function getBackend(): { [string]: any }?
	return (shared :: any).BuzzerReviewBackend
end

local function getRuntime(): any
	return (shared :: any).BuzzerReviewRuntime
end

local function playerKey(userId: number): string
	return `Player_{userId}`
end

-- ===== Presets (Strict Schema v1 Compliant) =====
local function buildPreset(deviceId: string, balance: number, completedMissions: number, ownedDesks: { number }, workers: { any })
	return {
		balance = balance,
		lifetimeEarned = balance,
		completedMissions = completedMissions,
		deviceId = deviceId,
		propertyId = "bedroom",
		ownedDesks = ownedDesks,
		workers = workers,
		fractionalIncome = 0,
		claimedRunIdsWindow = {},
		recentMutationOutcomes = {},
		missionVariantCounters = {},
		nextOrganicSequence = 1,
		activeMission = nil,
		pendingPost = nil,
		ownPosts = {},
		nextPostSequence = 1,
	}
end

local PRESETS: { [string]: any } = {
	fresh = buildPreset("phone_cheap", 0, 0, {}, {}),
	mid = buildPreset("phone_fast", 500, 2, {}, {}),
	tier2 = buildPreset("pc_rumah", 2500, 5, { 1, 2 }, {
		{ hireId = "hire_trainee_1", roleId = "trainee", slotIndex = 1 },
		{ hireId = "hire_trainee_2", roleId = "trainee", slotIndex = 2 },
	}),
}

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy
end

-- ===== Direct Preset Application =====
local function applyPresetDirect(player: Player, presetProfile: any?)
	local runtime = getRuntime()
	if runtime == nil then
		warn("[ReviewPanelRelay] Runtime not ready.")
		return
	end

	local record = runtime._records[player]
	if record == nil or record.session == nil then
		warn("[ReviewPanelRelay] Player session record not found.")
		return
	end

	local profileToApply = if presetProfile ~= nil then deepCopy(presetProfile) else deepCopy(PRESETS.fresh)
	local session = record.session

	-- 1. Update session's in-memory profile
	session._profile = deepCopy(profileToApply)
	if session._store and session._store._envelope then
		session._store._envelope.profile = deepCopy(profileToApply)
	end

	-- 2. Update backend for clean re-reads
	local backend = getBackend()
	if backend then
		local key = playerKey(player.UserId)
		backend[key] = {
			schemaVersion = 1,
			revision = session:GetRevision() or 1,
			lastSaveOpId = `preset_{HttpService:GenerateGUID(false)}`,
			updatedAt = os.time(),
			profile = deepCopy(profileToApply),
			lease = {
				token = "",
				jobId = "review-server",
				expiresAt = 0,
			},
		}
	end

	-- 3. Synchronize world presentation (devices, worker desks, trainees)
	runtime:_syncWorld(record)

	-- 4. Push updated state to player's client UI
	runtime._router:PushState(player)

	notifyRemote:FireClient(player, `Preset applied: {profileToApply.deviceId} (balance: {profileToApply.balance})`)
	warn(`[ReviewPanelRelay] Preset applied for {player.Name}: {profileToApply.deviceId}, balance={profileToApply.balance}`)
end

-- ===== Backdrop switching =====
local function setBackdrop(variant: "baseline" | "centered")
	local city = Workspace:FindFirstChild("City")
	local prefabs = ServerStorage:FindFirstChild("CityPrefabs")
	if city == nil or prefabs == nil then
		warn("[ReviewPanelRelay] City or CityPrefabs not found.")
		return
	end

	-- Remove current backdrop in City
	for _, child in city:GetChildren() do
		if child.Name:find("Backdrop") then
			child:Destroy()
		end
	end

	local prefabName = if variant == "centered" then "CityBackdrop_CenteredReview" else "CityBackdrop"
	local origin = if variant == "centered" then Vector3.new(0, 0, -152) else Vector3.new(88, 0, -152)
	local template: any = prefabs:FindFirstChild(prefabName)
	if template then
		local clone = template:Clone()
		clone.Name = "CityBackdrop"
		clone:PivotTo(CFrame.new(origin))
		clone.Parent = city
		warn(`[ReviewPanelRelay] Backdrop switched to: {variant} ({prefabName} at {origin})`)
	else
		warn(`[ReviewPanelRelay] Prefab {prefabName} not found in CityPrefabs.`)
	end
end

-- ===== Teleportation =====
local function teleportPlayer(player: Player, targetCF: CFrame)
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char:PivotTo(targetCF)
	end
end

-- ===== Command Handler =====
commandRemote.OnServerEvent:Connect(function(player: Player, cmd: string)
	if typeof(cmd) ~= "string" then return end

	if cmd == "preset:fresh" then
		applyPresetDirect(player, PRESETS.fresh)
	elseif cmd == "preset:mid" then
		applyPresetDirect(player, PRESETS.mid)
	elseif cmd == "preset:tier2" then
		applyPresetDirect(player, PRESETS.tier2)
	elseif cmd == "preset:reset" then
		applyPresetDirect(player, nil)
	elseif cmd == "teleport:city" then
		teleportPlayer(player, CFrame.new(-6, 4.5, 20))
	elseif cmd == "teleport:home" then
		teleportPlayer(player, CFrame.new(-6, 3.65, 8))
	elseif cmd == "backdrop:baseline" then
		setBackdrop("baseline")
		notifyRemote:FireClient(player, "Backdrop: Baseline (X 16..160)")
	elseif cmd == "backdrop:centered" then
		setBackdrop("centered")
		notifyRemote:FireClient(player, "Backdrop: Centered (X -120..120)")
	else
		warn("[ReviewPanelRelay] Unknown command: " .. tostring(cmd))
	end
end)

warn("[ReviewPanelRelay] Initialized and listening for review commands.")
