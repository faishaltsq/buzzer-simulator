--!strict
-- Production entry only. The isolated test project does not execute Bootstrap.
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local SessionService = require(script.Parent:WaitForChild("SessionService"))
local WorldService = require(script.Parent:WaitForChild("WorldService"))
local BootstrapRuntime = require(script.Parent:WaitForChild("BootstrapRuntime"))
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))
local ScoringCatalog = require(script.Parent:WaitForChild("ScoringCatalog"))

local catalogOK, catalogProblems = Catalog.validate()
assert(catalogOK, table.concat(catalogProblems, "; "))
local scoringOK, scoringProblems = ScoringCatalog.validateShippedContent(
	Catalog, Catalog.V0Shipped.organicContextIds, Catalog.V0Shipped.missionIds
)
assert(scoringOK, table.concat(scoringProblems, "; "))

local function monotonic(): number return os.clock() end
local function serverTime(): number return workspace:GetServerTimeNow() end
local function guid(): string return HttpService:GenerateGUID(false) end
local jobId = if game.JobId ~= "" then game.JobId else `studio-{guid()}`
local runtime = BootstrapRuntime.new({
	players = Players,
	prompts = ProximityPromptService,
	replicatedStorage = ReplicatedStorage,
	heartbeat = RunService.Heartbeat,
	bindToClose = function(callback) game:BindToClose(callback) end,
	world = WorldService,
	now = serverTime,
	monotonic = monotonic,
	guid = guid,
	sessionFactory = function(player)
		return SessionService.new({
			userId = player.UserId,
			store = nil,
			jobId = jobId,
			now = serverTime,
			connectedNow = monotonic,
		})
	end,
})
runtime:Start()

if RunService:IsStudio() then
	_G.BuzzerRuntime = runtime
	shared.BuzzerRuntime = runtime
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "StudioPromptBridge"
	bridge.OnInvoke = function(prompt, player)
		return runtime._router:HandlePrompt(prompt, player)
	end
	bridge.Parent = ServerScriptService
end
