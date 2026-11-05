-- Server DataModel, Play mode, isolated review place only.
-- Walks the character from City_Spawn to the fountain apron edge with Humanoid:MoveTo
-- (default WalkSpeed, physics-driven) and reports measured time and stalls.
local Players = game:GetService("Players")
local plr = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
local char = plr.Character or plr.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
local anchors = workspace.City.City_Anchors
local spawnPos = anchors.City_Spawn.Position
root.CFrame = CFrame.new(spawnPos + Vector3.new(0, 3, 0), spawnPos + Vector3.new(0, 3, 10))
task.wait(1.0)
local function walk(target, limit)
	local t0 = os.clock()
	hum:MoveTo(target)
	local done = false
	local c = hum.MoveToFinished:Connect(function() done = true end)
	while not done and os.clock() - t0 < limit do task.wait() end
	c:Disconnect()
	return os.clock() - t0, done
end
local legs, total = {}, 0
-- Door stoop -> lane -> through kiosk west flank -> fountain apron (r 16 ring, north edge).
for _, wp in { Vector3.new(-6, 0, 30), Vector3.new(-6, 0, 62), Vector3.new(-6, 0, 74), Vector3.new(0, 0, 96) } do
	local dt, ok = walk(wp, 15)
	local flat = (Vector3.new(root.Position.X, 0, root.Position.Z) - wp).Magnitude
	table.insert(legs, string.format("(%d,%d) %.2fs reached=%s miss=%.1f", wp.X, wp.Z, dt, tostring(ok), flat))
	total += dt
end
local fromDoor = (Vector3.new(-6, 0, 16) - Vector3.new(-6, 0, spawnPos.Z)).Magnitude / hum.WalkSpeed
return string.format("WalkSpeed=%d total_spawn_to_apron=%.2fs (+door->spawn %.2fs) final=(%.1f,%.1f,%.1f) | %s",
	hum.WalkSpeed, total, fromDoor, root.Position.X, root.Position.Y, root.Position.Z, table.concat(legs, " | "))
