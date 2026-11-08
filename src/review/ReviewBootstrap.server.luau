--!strict
-- ReviewBootstrap.server.luau  —  STUDIO-ONLY entry point for the full review place.
-- Replaces production Bootstrap.server.luau; uses in-memory ProfileStore adapter
-- so no cloud DataStore is ever touched during review.
-- Fail-closed: errors out immediately if not running in Studio.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	error("[ReviewBootstrap] REFUSE: not Studio. This script must never run in production.", 0)
end

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local HttpService        = game:GetService("HttpService")
local Workspace          = game:GetService("Workspace")

-- ===== In-memory StoreAdapter (mirrors ProfileStore.StoreAdapter contract) =====
local backend: { [string]: any } = {}
local function deepCopy(value: any): any
	if typeof(value) ~= "table" then return value end
	local copy: any = {}
	for k, v in pairs(value) do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy
end
local inMemoryStore = {
	GetAsync = function(_self: any, key: string, _options: any?)
		local val = backend[key]
		return if val ~= nil then deepCopy(val) else nil
	end,
	UpdateAsync = function(_self: any, key: string, transform: (any) -> any)
		local old = backend[key]
		local oldCopy = if old ~= nil then deepCopy(old) else nil
		local new = transform(oldCopy)
		if new ~= nil then backend[key] = deepCopy(new) end
		return if new ~= nil then deepCopy(new) else nil
	end,
	RemoveAsync = function(_self: any, key: string)
		backend[key] = nil
		return true
	end,
}

-- ===== Pre-built city in Workspace (edit-mode preview cleanup) =====
-- ReviewBedroom exists in the place for edit-mode inspection.
-- On Play, hide it so WorldService can spawn the real per-player room.
local function hideEditPreview()
	local preview = Workspace:FindFirstChild("ReviewBedroom")
	if preview ~= nil then
		preview.Parent = ServerStorage -- move out of Workspace, keeps geometry available
		warn("[ReviewBootstrap] ReviewBedroom moved to ServerStorage (play-mode hidden).")
	end
	-- Also assemble the city in Workspace if not already present.
	local existing = Workspace:FindFirstChild("CityRuko") or Workspace:FindFirstChild("City")
	if existing == nil then
		local prefabsRuko = ServerStorage:FindFirstChild("CityRukoPrefabs")
		local prefabsLegacy = ServerStorage:FindFirstChild("CityPrefabs")

		if prefabsRuko ~= nil then
			local ORIGINS_RUKO: { [string]: CFrame } = {
				Intersection      = CFrame.new(0, 0, 0),
				RukoBlockWest     = CFrame.new(-55, 0, -60),
				RukoBlockEast     = CFrame.new(55, 0, -60),
				CityFacilities    = CFrame.new(0, 0, 60),
				CityBackdrop_Ruko = CFrame.new(0, 0, -180),
			}
			local city = Instance.new("Folder")
			city.Name = "CityRuko"
			for _, name in { "Intersection", "RukoBlockWest", "RukoBlockEast", "CityFacilities", "CityBackdrop_Ruko" } do
				local prefab: any = prefabsRuko:FindFirstChild(name)
				if prefab then
					local m = prefab:Clone()
					m:PivotTo(ORIGINS_RUKO[name])
					m.Parent = city
				else
					warn(`[ReviewBootstrap] Instance not found: ServerStorage.CityRukoPrefabs.{name}`)
				end
			end
			city.Parent = Workspace
		elseif prefabsLegacy ~= nil then
			local ORIGINS_LEGACY: { [string]: CFrame } = {
				HouseExterior = CFrame.new(0, 0, 0),
				StreetBlock   = CFrame.new(0, 0, 40),
				TownCenter    = CFrame.new(0, 0, 112),
				CityBoards    = CFrame.new(0, 0, 68),
				CityGate      = CFrame.new(0, 0, 168),
				CityBackdrop  = CFrame.new(88, 0, -152),
			}
			local city = Instance.new("Folder")
			city.Name = "City"
			for _, name in { "HouseExterior", "StreetBlock", "TownCenter", "CityBoards", "CityGate", "CityBackdrop" } do
				local prefab: any = prefabsLegacy:FindFirstChild(name)
				if prefab then
					local m = prefab:Clone()
					m:PivotTo(ORIGINS_LEGACY[name])
					m.Parent = city
				else
					warn(`[ReviewBootstrap] Instance not found: ServerStorage.CityPrefabs.{name}`)
				end
			end
			local anchors: any = prefabsLegacy:FindFirstChild("CityAnchors")
			if anchors then
				local a = anchors:Clone()
				a.Name = "City_Anchors"
				a.Parent = city
			end
			city.Parent = Workspace
		else
			warn("[ReviewBootstrap] Instance not found: ServerStorage.CityRukoPrefabs")
			return
		end

		-- Outer review ground (if not already in Workspace)
		if Workspace:FindFirstChild("ReviewOuterGround") == nil then
			local ground = Instance.new("Part")
			ground.Name  = "ReviewOuterGround"
			ground.Size  = Vector3.new(600, 1, 600)
			ground.CFrame = CFrame.new(0, -1.6, -30)
			ground.Anchored = true
			ground.CanCollide = true
			ground.Color    = Color3.fromRGB(92, 90, 86)
			ground.Material = Enum.Material.Slate
			ground.Parent   = Workspace
		end
	end
end
hideEditPreview()

-- ===== Service wiring =====
local WorldService   = require(ServerScriptService:WaitForChild("WorldService"))
local BootstrapRuntime = require(ServerScriptService:WaitForChild("BootstrapRuntime"))

local function monotonic(): number return os.clock() end
local function serverTime(): number return Workspace:GetServerTimeNow() end
local function guid(): string return HttpService:GenerateGUID(false) end
local jobId = `review-{guid()}`

local runtime = BootstrapRuntime.new({
	players           = Players,
	prompts           = ProximityPromptService,
	replicatedStorage = ReplicatedStorage,
	heartbeat         = game:GetService("RunService").Heartbeat,
	bindToClose       = function(callback) game:BindToClose(callback) end,
	world             = WorldService,
	now               = serverTime,
	monotonic         = monotonic,
	guid              = guid,
	-- Inject in-memory store so every SessionService gets an offline adapter.
	sessionFactory = function(player: Player)
		local SessionService = require(ServerScriptService:WaitForChild("SessionService"))
		return SessionService.new({
			userId      = player.UserId,
			store       = inMemoryStore,  -- <-- offline, never touches DataStore
			jobId       = jobId,
			now         = serverTime,
			connectedNow = monotonic,
		})
	end,
})

runtime:Start()

-- Expose runtime for Studio command bar / ReviewPanel
_G.BuzzerReviewRuntime = runtime
shared.BuzzerReviewRuntime  = runtime
shared.BuzzerReviewBackend  = backend  -- direct access for profile preset injection

local bridge = Instance.new("BindableFunction")
bridge.Name = "StudioPromptBridge"
bridge.OnInvoke = function(prompt: any, player: any)
	return runtime._router:HandlePrompt(prompt, player)
end
bridge.Parent = ServerScriptService

warn("[ReviewBootstrap] Review runtime started. In-memory store active. No cloud DataStore touched.")
