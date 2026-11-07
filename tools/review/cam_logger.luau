-- Client DataModel, Play mode, isolated review place only.
-- Installs a RenderStepped logger (idempotent) and returns/reset its stats via _G.M2A1Cam.
-- Frame time = RenderStepped delta (client render loop), not server Heartbeat.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera
local city = workspace:FindFirstChild("City")

local function fresh()
	return { frames = 0, dts = {}, minDist = math.huge, maxDist = 0, inside = 0, insideNames = {},
		yawMin = math.huge, yawMax = -math.huge, pitchMin = math.huge, pitchMax = -math.huge,
		yaws = {}, label = "", solid = 0, solidNames = {}, point = 0, pointNames = {}, pointMax = 0,
		pointAt = {}, solidAt = {} }
end

if not _G.M2A1Cam then
	_G.M2A1Cam = { s = fresh() }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { city }
	params.RespectCanCollide = false
	local solidParams = OverlapParams.new()
	solidParams.FilterType = Enum.RaycastFilterType.Include
	solidParams.FilterDescendantsInstances = { city }
	solidParams.RespectCanCollide = true
	RunService.RenderStepped:Connect(function(dt)
		local s = _G.M2A1Cam.s
		local ch = plr.Character
		local head = ch and ch:FindFirstChild("Head")
		if not head then return end
		s.frames += 1
		table.insert(s.dts, dt)
		local d = (cam.CFrame.Position - head.Position).Magnitude
		s.minDist, s.maxDist = math.min(s.minDist, d), math.max(s.maxDist, d)
		local look = cam.CFrame.LookVector
		local yaw = math.deg(math.atan2(-look.X, -look.Z))
		local pitch = math.deg(math.asin(look.Y))
		s.yawMin, s.yawMax = math.min(s.yawMin, yaw), math.max(s.yawMax, yaw)
		s.pitchMin, s.pitchMax = math.min(s.pitchMin, pitch), math.max(s.pitchMax, pitch)
		s.yaws[math.floor((yaw + 180) / 30)] = true
		-- Bounds queries nominate candidates; compute containment in each part's local axes.
		local pt = workspace:GetPartBoundsInBox(CFrame.new(cam.CFrame.Position), Vector3.new(0.001, 0.001, 0.001), solidParams)
		if #pt > 0 then
			s.point += 1
			for _, p in pt do
				s.pointNames[p.Name] = (s.pointNames[p.Name] or 0) + 1
				local rel, half = p.CFrame:PointToObjectSpace(cam.CFrame.Position), p.Size / 2
				local depth = math.min(half.X - math.abs(rel.X), half.Y - math.abs(rel.Y), half.Z - math.abs(rel.Z))
				s.pointMax = math.max(s.pointMax, depth)
				if #s.pointAt < 8 then
					table.insert(s.pointAt, string.format("%s boundsDepth=%.4f studs cam=(%.1f,%.1f,%.1f)",
						p.Name, depth, cam.CFrame.X, cam.CFrame.Y, cam.CFrame.Z))
				end
			end
		end
		-- Near-plane-sized (0.3) box: camera touching a collidable surface.
		local solid = workspace:GetPartBoundsInBox(cam.CFrame, Vector3.new(0.3, 0.3, 0.3), solidParams)
		if #solid > 0 then
			s.solid += 1
			for _, h in solid do s.solidNames[h.Name] = (s.solidNames[h.Name] or 0) + 1 end
			if #s.solidAt < 6 then
				table.insert(s.solidAt, string.format("%s@(%.1f,%.1f,%.1f)", solid[1].Name, cam.CFrame.X, cam.CFrame.Y, cam.CFrame.Z))
			end
		end
		local hits = workspace:GetPartBoundsInBox(cam.CFrame, Vector3.new(0.3, 0.3, 0.3), params)
		if #hits > 0 then
			s.inside += 1
			for _, h in hits do s.insideNames[h.Name] = (s.insideNames[h.Name] or 0) + 1 end
		end
	end)
end

local mode = _G.M2A1_CAM_MODE or "report"
local s = _G.M2A1Cam.s
local function pct(sorted, p) return sorted[math.max(1, math.ceil(#sorted * p))] or 0 end
local out
if #s.dts > 0 then
	local sorted = table.clone(s.dts)
	table.sort(sorted)
	local sum = 0
	for _, v in s.dts do sum += v end
	local bins = 0
	for _ in s.yaws do bins += 1 end
	local ins = {}
	for k, v in s.insideNames do table.insert(ins, k .. "x" .. v) end
	local sol = {}
	for k, v in s.solidNames do table.insert(sol, k .. "x" .. v) end
	local pn = {}
	for k, v in s.pointNames do table.insert(pn, k .. "x" .. v) end
	out = string.format("CAMERA_INSIDE_SOLID_frames=%d %s maxPenetration=%.4f studs | NEAR_PLANE_TOUCH_frames=%d %s | frames=%d avg_fps=%.1f p50=%.1fms p95=%.1fms p99=%.1fms worst=%.1fms >33ms=%d | camDist %.1f..%.1f | yaw %.0f..%.0f (%d/12 bins) pitch %.0f..%.0f\nINSIDE_SOLID_AT: %s\nNEAR_PLANE_AT: %s",
		s.point, table.concat(pn, ","), s.pointMax, s.solid, table.concat(sol, ","), s.frames, s.frames / sum, pct(sorted, .5) * 1000, pct(sorted, .95) * 1000, pct(sorted, .99) * 1000,
		sorted[#sorted] * 1000, (function() local n = 0 for _, v in s.dts do if v > 0.033 then n += 1 end end return n end)(),
		s.minDist, s.maxDist, s.yawMin, s.yawMax, bins, s.pitchMin, s.pitchMax,
		#s.pointAt > 0 and table.concat(s.pointAt, " ; ") or "none",
		#s.solidAt > 0 and table.concat(s.solidAt, " ; ") or "none")
else
	out = "no frames yet"
end
if mode == "reset" then
	_G.M2A1Cam.s = fresh()
end
return out
