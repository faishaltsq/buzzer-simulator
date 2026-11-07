--!strict
-- ReviewTravelService.server.luau  —  STUDIO-ONLY.
-- Wires ProximityPrompts for seamless room <-> city exploration:
-- 1. Front door inside bedroom: "Keluar ke Kota" -> Teleport to City_Spawn (-6, 4.5, 20)
-- 2. House door in Gang Melati: "Masuk Rumah"    -> Teleport to Bedroom (-6, 3.65, 8)
-- 3. Mission Board in Gang Melati: "Periksa Papan Misi" -> Info interaction
-- Safety: checks character alive and implements a 1.5s travel debounce.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	error("[ReviewTravelService] REFUSE: not Studio.", 0)
end

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CITY_SPAWN_CF  = CFrame.new(-6, 4.5, 20)
local HOME_SPAWN_CF  = CFrame.new(-6, 3.65, 8)
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
	if roomFolder == nil then return end

	local doorPart: BasePart? = nil
	for _, d in roomFolder:GetDescendants() do
		if d.Name == "Door" and d:IsA("BasePart") then
			doorPart = d :: BasePart
			break
		end
	end
	if doorPart == nil then return end

	local exitPrompt = makePrompt(doorPart, "Keluar ke Kota", "Pintu Rumah")
	exitPrompt.Triggered:Connect(function(triggerPlayer: Player)
		if triggerPlayer ~= player then return end
		if not canTravel(player.UserId) then return end
		markTravel(player.UserId)
		teleportCharacter(player, CITY_SPAWN_CF)
	end)
end

-- ===== Wire city doors and kiosk =====
local function wireCity()
	local city: Instance? = nil
	local t0 = os.clock()
	while city == nil and (os.clock() - t0) < 15 do
		city = Workspace:FindFirstChild("City")
		if city == nil then task.wait(0.5) end
	end
	if city == nil then return end

	-- 1. City_HomeDoor return prompt
	local homeDoor: BasePart? = nil
	for _, desc in city:GetDescendants() do
		if desc.Name == "City_HomeDoor" and desc:IsA("BasePart") then
			homeDoor = desc :: BasePart
			break
		end
	end

	if homeDoor then
		local returnPrompt = makePrompt(homeDoor, "Masuk Rumah", "Pintu Kamar")
		returnPrompt.Triggered:Connect(function(player: Player)
			if not canTravel(player.UserId) then return end
			markTravel(player.UserId)
			teleportCharacter(player, HOME_SPAWN_CF)
		end)
	end

	-- 2. Mission kiosk prompt
	local kioskAnchor: BasePart? = nil
	for _, desc in city:GetDescendants() do
		if (desc.Name == "City_Prompt_Boards" or desc.Name == "BoardCork") and desc:IsA("BasePart") then
			kioskAnchor = desc :: BasePart
			break
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
				end
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

task.spawn(wireCity)
warn("[ReviewTravelService] Travel service wired (Door <-> City_Spawn).")
