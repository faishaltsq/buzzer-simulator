-- Edit DataModel, isolated review place. Reads the assembled Workspace.City.
local EXPECT = {
	City_HomeDoor = Vector3.new(-6, 3.65, 16), City_Spawn = Vector3.new(-6, 0.6, 20),
	City_DoorPromptInterior = Vector3.new(-6, 3.65, 8), City_Zone_Street = Vector3.new(0, 0, 40),
	City_Zone_TownCenter = Vector3.new(0, 0, 112), City_Zone_FutureGate = Vector3.new(0, 0, 168),
	City_Prompt_Boards = Vector3.new(0, 3, 68), City_Prompt_FutureGate = Vector3.new(0, 3, 168),
	City_TransitStop = Vector3.new(24, 0, 96), City_Signpost_01 = Vector3.new(-21, 0, 18),
	City_Signpost_02 = Vector3.new(0, 0, 58),
}
local city = workspace.City
local out, seen, per = {}, {}, {}
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") then
		local zone = d:FindFirstAncestorOfClass("Model") or d.Parent
		per[zone.Name] = (per[zone.Name] or 0) + 1
		if EXPECT[d.Name] then
			seen[d.Name] = (seen[d.Name] or 0) + 1
			if (d.Position - EXPECT[d.Name]).Magnitude > 1e-3 then
				table.insert(out, "POS " .. d.Name .. " " .. tostring(d.Position))
			end
		end
		if not d.Anchored then table.insert(out, "UNANCHORED " .. d:GetFullName()) end
	end
end
for n in EXPECT do
	if seen[n] ~= 1 then table.insert(out, "COUNT " .. n .. "=" .. tostring(seen[n])) end
end
-- Spawn throat: any collidable within a 4-stud-radius character column at City_Spawn?
local params = OverlapParams.new()
params.FilterDescendantsInstances = { city }
params.FilterType = Enum.RaycastFilterType.Include
params.RespectCanCollide = true
local hits = workspace:GetPartBoundsInBox(CFrame.new(-6, 3.5, 20), Vector3.new(8, 5, 8), params)
local names = {}
for _, h in hits do table.insert(names, h.Name) end
-- Ground under spawn and along the lane.
local rp = RaycastParams.new()
rp.FilterDescendantsInstances = { city }
rp.FilterType = Enum.RaycastFilterType.Include
local gaps = {}
for z = 17, 158, 3 do
	for _, x in { -10, -6, 0, 6 } do
		local r = workspace:Raycast(Vector3.new(x, 5, z), Vector3.new(0, -10, 0), rp)
		if not r or math.abs(r.Position.Y) > 0.06 then
			if not (r and r.Instance.Name:match("^Kiosk") ) and not (r and r.Position.Y > 0.06 and (Vector3.new(x,0,z) - Vector3.new(0,0,112)).Magnitude < 8.6) then
				table.insert(gaps, string.format("(%d,%d)%s", x, z, r and string.format("%s@%.2f", r.Instance.Name, r.Position.Y) or "void"))
			end
		end
	end
end
local zones = {}
for k, v in per do table.insert(zones, k .. "=" .. v) end
table.sort(zones)
return table.concat({
	"issues=" .. #out .. " " .. table.concat(out, "; "),
	"spawn_box_collidables=" .. #hits .. " " .. table.concat(names, ","),
	"ground_probe_anomalies=" .. #gaps .. " " .. table.concat(gaps, " "),
	"per_zone " .. table.concat(zones, " "),
	"Lighting ClockTime=" .. game.Lighting.ClockTime .. " Brightness=" .. game.Lighting.Brightness
		.. " StreamingEnabled=" .. tostring(workspace.StreamingEnabled),
}, "\n")
