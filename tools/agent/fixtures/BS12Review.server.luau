--!strict
-- Isolated Studio evidence fixture. Never mapped by production or test projects.
assert(game:GetService("RunService"):IsStudio(), "Review fixture is Studio-only")
local SS = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ProfileStore = require(SS.ProfileStore)
local SessionService = require(SS.SessionService)
local WorldService = require(SS.WorldService)
local Runtime = require(SS.BootstrapRuntime)
local copy = ProfileStore._deepCopy
local backend = {}
local store = {}
function store:GetAsync(key) return copy(backend[key]) end
function store:UpdateAsync(key, transform)
	local value = transform(copy(backend[key]))
	if value ~= nil then backend[key] = copy(value) end
	return copy(backend[key])
end
local runtime = Runtime.new({
	players = Players, prompts = game:GetService("ProximityPromptService"),
	replicatedStorage = game:GetService("ReplicatedStorage"), heartbeat = game:GetService("RunService").Heartbeat,
	bindToClose = function(callback) game:BindToClose(callback) end,
	world = WorldService, now = function() return workspace:GetServerTimeNow() end,
	monotonic = os.clock, guid = function() return game:GetService("HttpService"):GenerateGUID(false) end,
	sessionFactory = function(player)
		backend["Player_" .. player.UserId] = {
			schemaVersion = 1, revision = 1, lastSaveOpId = "review-seed", updatedAt = 0,
			lease = { token = "", jobId = "review-seed", expiresAt = 0 },
			profile = { balance = 1000, lifetimeEarned = 2000, completedMissions = 3,
				deviceId = "pc_rumah", propertyId = "bedroom", ownedDesks = {}, workers = {}, fractionalIncome = 0,
				claimedRunIdsWindow = {}, recentMutationOutcomes = {}, missionVariantCounters = {},
				nextOrganicSequence = 0, ownPosts = {}, nextPostSequence = 1 },
		}
		return SessionService.new({ userId = player.UserId, store = store, jobId = "bs12-review", now = function() return workspace:GetServerTimeNow() end, connectedNow = os.clock })
	end,
})
runtime:Start()
local bridge = Instance.new("BindableFunction")
bridge.Name = "BS12ReviewBridge"
bridge.OnInvoke = function(action)
	local player = Players:GetPlayers()[1]
	if action == "Open" then
		local prompt = WorldService.GetPrompt(player)
		player.Character:WaitForChild("HumanoidRootPart").CFrame = prompt.Parent.CFrame * CFrame.new(0, 0, 3)
		return runtime._router:HandlePrompt(prompt, player)
	elseif action == "Stored" then
		return copy(backend["Player_" .. player.UserId])
	end
end
bridge.Parent = game:GetService("ServerScriptService")
print("BS12_REVIEW_FIXTURE_READY: seeded PC/Tier1/1000 Cuan; memory backend, G2 OPEN")
