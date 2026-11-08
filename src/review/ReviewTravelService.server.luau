--!strict
-- ReviewTravelService.server.luau  —  STUDIO-ONLY.
-- Wires ProximityPrompts for seamless room <-> city exploration:
-- 1. Front door inside bedroom: "Keluar ke Kota" -> Dynamic teleport to City_Spawn
-- 2. House door in City: "Masuk Rumah"          -> Dynamic teleport to BuzzerRoom_<UserId>.Spawn
-- 3. Mission Kiosk in City: "Periksa Misi"        -> Info interaction
-- Safety: checks character alive, implements a 1.5s travel debounce, cleans on PlayerRemoving.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	error("[ReviewTravelService] REFUSE: not Studio.", 0)
end

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PROMPT_DIST    = 8
local DEBOUNCE_SEC   = 1.5
local debounce: { [number]: number } = {}

local function canTravel(userId: number): boolean
	local last = debounce[userId] or 0
	return (os.clock() - last) >= DEBOUNCE_SEC
end

local function markTravel(userId: number)
	debounce[userId] = os.clock()
end

local function teleportCharacter(player: Player, cf: CFrame)
	local char = player.Character
	if char == nil then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp == nil or hum == nil or hum.Health <= 0 then return end
	hrp.CFrame = cf
end

local function getCity(): Instance?
	local city = Workspace:FindFirstChild("CityRuko") or Workspace:FindFirstChild("City")
	if city == nil then
		warn("[ReviewTravelService] Instance not found: Workspace.CityRuko (or Workspace.City)")
	end
	return city
end

local function teleportToCity(player: Player)
	local city = getCity()
	if city == nil then return end

	local spawnPart = city:FindFirstChild("City_Spawn", true) :: BasePart?
	if spawnPart == nil or not spawnPart:IsA("BasePart") then
		warn(`[ReviewTravelService] Instance not found: City_Spawn in {city:GetFullName()}`)
		return
	end

	teleportCharacter(player, spawnPart.CFrame + Vector3.new(0, 3, 0))
end

local function teleportHome(player: Player)
	local roomPath = `Workspace.BuzzerRoom_{player.UserId}`
	local room = Workspace:FindFirstChild(`BuzzerRoom_{player.UserId}`)
	if room == nil then
		warn(`[ReviewTravelService] Instance not found: {roomPath}`)
		return
	end

	local spawnPart = room:FindFirstChild("Spawn", true) :: BasePart?
	if spawnPart == nil or not spawnPart:IsA("BasePart") then
		warn(`[ReviewTravelService] Instance not found: Spawn in {roomPath}`)
		return
	end

	teleportCharacter(player, spawnPart.CFrame + Vector3.new(0, 3, 0))
end

local function makePrompt(parent: Instance, action: string, object: string): ProximityPrompt
	local existing = parent:FindFirstChildOfClass("ProximityPrompt")
	if existing then existing:Destroy() end
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.MaxActivationDistance = PROMPT_DIST
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- ===== Wire bedroom door exit prompt =====
local function wireRoom(player: Player)
	local roomFolder: Instance? = nil
	local t0 = os.clock()
	while roomFolder == nil and (os.clock() - t0) < 12 do
		roomFolder = Workspace:FindFirstChild(`BuzzerRoom_{player.UserId}`)
		if roomFolder == nil then task.wait(0.25) end
	end
	if roomFolder == nil then
		warn(`[ReviewTravelService] Instance not found: Workspace.BuzzerRoom_{player.UserId}`)
		return
	end

	local doorPart: BasePart? = nil
	for _, d in roomFolder:GetDescendants() do
		if d.Name == "Door" and d:IsA("BasePart") then
			doorPart = d :: BasePart
			break
		end
	end
	if doorPart == nil then
		warn(`[ReviewTravelService] Instance not found: Door in Workspace.BuzzerRoom_{player.UserId}`)
		return
	end

	local exitPrompt = makePrompt(doorPart, "Keluar ke Kota", "Pintu Rumah")
	exitPrompt.Triggered:Connect(function(triggerPlayer: Player)
		if triggerPlayer ~= player then return end
		if not canTravel(player.UserId) then return end
		markTravel(player.UserId)
		teleportToCity(player)
	end)
end

-- ===== Wire city doors and kiosk =====
local function wireCity()
	local city: Instance? = nil
	local t0 = os.clock()
	while city == nil and (os.clock() - t0) < 15 do
		city = Workspace:FindFirstChild("CityRuko") or Workspace:FindFirstChild("City")
		if city == nil then task.wait(0.5) end
	end
	if city == nil then
		warn("[ReviewTravelService] Instance not found: Workspace.CityRuko (or Workspace.City)")
		return
	end

	-- 1. City_HomeDoor return prompt (fallback to Door_A1 in CityRuko)
	local homeDoor: BasePart? = nil
	local targetDoor = city:FindFirstChild("City_HomeDoor", true)
	if targetDoor and targetDoor:IsA("BasePart") then
		homeDoor = targetDoor :: BasePart
	else
		warn(`[ReviewTravelService] Instance not found: City_HomeDoor in {city:GetFullName()}. Using fallback Door_A1 for return prompt.`)
		local fallbackDoor = city:FindFirstChild("Door_A1", true)
		if fallbackDoor and fallbackDoor:IsA("BasePart") then
			homeDoor = fallbackDoor :: BasePart
		else
			warn(`[ReviewTravelService] Instance not found: Door_A1 in {city:GetFullName()}`)
		end
	end

	if homeDoor then
		local returnPrompt = makePrompt(homeDoor, "Masuk Rumah", "Pintu Kamar")
		returnPrompt.Triggered:Connect(function(player: Player)
			if not canTravel(player.UserId) then return end
			markTravel(player.UserId)
			teleportHome(player)
		end)
	end

	-- 2. Mission kiosk prompt
	local kioskAnchor: BasePart? = nil
	local missionMarker = city:FindFirstChild("Prompt_CityMissions", true)
	if missionMarker and missionMarker:IsA("BasePart") then
		kioskAnchor = missionMarker :: BasePart
	else
		local fallbackMarker = city:FindFirstChild("City_Prompt_Boards", true) or city:FindFirstChild("BoardCork", true)
		if fallbackMarker and fallbackMarker:IsA("BasePart") then
			kioskAnchor = fallbackMarker :: BasePart
		else
			warn(`[ReviewTravelService] Instance not found: Prompt_CityMissions in {city:GetFullName()}`)
		end
	end

	if kioskAnchor then
		local kioskPrompt = makePrompt(kioskAnchor, "Periksa Misi", "Papan Misi Gang Melati")
		kioskPrompt.Triggered:Connect(function(player: Player)
			local remotes = ReplicatedStorage:FindFirstChild("ReviewRemotes")
			if remotes then
				local notify = remotes:FindFirstChild("ReviewNotify") :: RemoteEvent?
				if notify then
					notify:FireClient(player, "📋 Papan Misi Gang Melati: Buka dashboard di PC/Phone untuk kelola campaign.")
				else
					warn("[ReviewTravelService] Instance not found: ReplicatedStorage.ReviewRemotes.ReviewNotify")
				end
			else
				warn("[ReviewTravelService] Instance not found: ReplicatedStorage.ReviewRemotes")
			end
		end)
	end
end

-- ===== Connect Player Lifecycle =====
local function onCharacter(player: Player, _char: Model)
	task.spawn(wireRoom, player)
end

for _, p in Players:GetPlayers() do
	if p.Character then task.spawn(wireRoom, p) end
	p.CharacterAdded:Connect(function(char) onCharacter(p, char) end)
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	debounce[player.UserId] = nil
end)

task.spawn(wireCity)
warn("[ReviewTravelService] Travel service wired (Door <-> City_Spawn).")
