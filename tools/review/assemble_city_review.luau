-- M2-A1 isolated review assembly. Run in the Edit DataModel of the review place
-- built from tools/review/m2a1-city-review.project.json. Never run in production.
-- Each zone is cloned and placed exactly once with PivotTo(zone origin).
-- Set BACKDROP to "CityBackdrop_CenteredReview" to compare the D1 candidate.
local BACKDROP = _G.M2A1_BACKDROP or "CityBackdrop"
local ORIGINS = {
	HouseExterior = Vector3.new(0, 0, 0),
	StreetBlock = Vector3.new(0, 0, 40),
	TownCenter = Vector3.new(0, 0, 112),
	CityBoards = Vector3.new(0, 0, 68),
	CityGate = Vector3.new(0, 0, 168),
	CityBackdrop = Vector3.new(88, 0, -152),
	CityBackdrop_CenteredReview = Vector3.new(0, 0, -152),
}
local prefabs = game:GetService("ServerStorage"):WaitForChild("CityPrefabs")
local old = workspace:FindFirstChild("City")
if old then old:Destroy() end
local city = Instance.new("Folder")
city.Name = "City"
for _, name in { "HouseExterior", "StreetBlock", "TownCenter", "CityBoards", "CityGate", BACKDROP } do
	local m = prefabs[name]:Clone()
	m:PivotTo(CFrame.new(ORIGINS[name]))
	m.Parent = city
end
local anchors = prefabs.CityAnchors:Clone()
anchors.Name = "City_Anchors" -- parent 02 §6 hierarchy name
anchors.Parent = city
city.Parent = workspace

-- Review-only scaffolding (not part of any prefab): spawn at City_Spawn, outer ground.
for _, n in { "ReviewSpawn", "ReviewOuterGround" } do
	local o = workspace:FindFirstChild(n)
	if o then o:Destroy() end
end
local spawn = Instance.new("SpawnLocation")
spawn.Name = "ReviewSpawn"
spawn.Size = Vector3.new(4, 0.2, 4)
spawn.CFrame = CFrame.new(-6, 0.1, 22)
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 0
spawn.Parent = workspace
local ground = Instance.new("Part")
ground.Name = "ReviewOuterGround"
ground.Size = Vector3.new(600, 1, 600)
ground.CFrame = CFrame.new(0, -1.6, 60)
ground.Anchored = true
ground.Color = Color3.fromRGB(112, 134, 88)
ground.Material = Enum.Material.Grass
ground.Parent = workspace

local n, anchored, scripts = 0, 0, 0
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
		if d.Anchored then anchored += 1 end
	elseif d:IsA("LuaSourceContainer") then
		scripts += 1
	end
end
return string.format("assembled backdrop=%s baseparts=%d anchored=%d scripts=%d StreamingEnabled=%s",
	BACKDROP, n, anchored, scripts, tostring(workspace.StreamingEnabled))
