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
		warn("[ReviewPanelRelay] Instance not found: shared.BuzzerReviewRuntime")
		return
	end

	local record = runtime._records[player]
	if record == nil or record.session == nil then
		warn(`[ReviewPanelRelay] Instance not found: Session record for {player.Name}`)
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
local function setBackdrop(variant: string)
	local city = Workspace:FindFirstChild("CityRuko") or Workspace:FindFirstChild("City")
	if city == nil then
		warn("[ReviewPanelRelay] Instance not found: Workspace.CityRuko (or Workspace.City)")
		return
	end

	local prefabs = ServerStorage:FindFirstChild("CityRukoPrefabs") or ServerStorage:FindFirstChild("CityPrefabs")
	if prefabs == nil then
		warn("[ReviewPanelRelay] Instance not found: ServerStorage.CityRukoPrefabs (or ServerStorage.CityPrefabs)")
		return
	end

	-- Remove current backdrop in City
	for _, child in city:GetChildren() do
		if child.Name:find("Backdrop") then
			child:Destroy()
		end
	end

	local template: Instance? = prefabs:FindFirstChild("CityBackdrop_Ruko")
	local origin = CFrame.new(0, 0, -180)
	local label = "CityBackdrop_Ruko"

	-- Fallback for legacy CityPrefabs
	if template == nil then
		local prefabName = if variant == "centered" then "CityBackdrop_CenteredReview" else "CityBackdrop"
		origin = if variant == "centered" then CFrame.new(0, 0, -152) else CFrame.new(88, 0, -152)
		template = prefabs:FindFirstChild(prefabName)
		label = prefabName
	end

	if template then
		local clone = template:Clone()
		clone.Name = template.Name
		if clone:IsA("Model") then
			clone:PivotTo(origin)
		elseif clone:IsA("BasePart") then
			clone.CFrame = origin
		end
		clone.Parent = city
		warn(`[ReviewPanelRelay] Backdrop updated to: {label} at {origin}`)
	else
		warn(`[ReviewPanelRelay] Instance not found: CityBackdrop_Ruko in {prefabs:GetFullName()}`)
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
		local city = Workspace:FindFirstChild("CityRuko") or Workspace:FindFirstChild("City")
		if city == nil then
			warn("[ReviewPanelRelay] Instance not found: Workspace.CityRuko (or Workspace.City)")
			return
		end
		local spawnPart = city:FindFirstChild("City_Spawn", true) :: BasePart?
		if spawnPart and spawnPart:IsA("BasePart") then
			teleportPlayer(player, spawnPart.CFrame + Vector3.new(0, 3, 0))
		else
			warn(`[ReviewPanelRelay] Instance not found: City_Spawn in {city:GetFullName()}`)
		end
	elseif cmd == "teleport:home" then
		local room = Workspace:FindFirstChild(`BuzzerRoom_{player.UserId}`)
		if room == nil then
			warn(`[ReviewPanelRelay] Instance not found: Workspace.BuzzerRoom_{player.UserId}`)
			return
		end
		local spawnPart = room:FindFirstChild("Spawn", true) :: BasePart?
		if spawnPart and spawnPart:IsA("BasePart") then
			teleportPlayer(player, spawnPart.CFrame + Vector3.new(0, 3, 0))
		else
			warn(`[ReviewPanelRelay] Instance not found: Spawn in Workspace.BuzzerRoom_{player.UserId}`)
		end
	elseif cmd == "backdrop:baseline" or cmd == "backdrop:centered" or cmd == "backdrop:ruko" then
		setBackdrop(cmd)
		notifyRemote:FireClient(player, "Backdrop: CityBackdrop_Ruko active")
	else
		warn("[ReviewPanelRelay] Unknown command: " .. tostring(cmd))
	end
end)

warn("[ReviewPanelRelay] Initialized and listening for review commands.")
