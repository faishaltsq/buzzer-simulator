-- Client-only measurement in the isolated review place; never writes camera CFrame.
-- Set _G.M2G2_FRAME_ACTION to "start" or "report" before executing this file.
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local action = _G.M2G2_FRAME_ACTION or "report"
if action == "start" then
	if _G.M2G2Frame and _G.M2G2Frame.connection then
		_G.M2G2Frame.connection:Disconnect()
	end
	local s = { started = os.clock(), delta = {}, engine = {} }
	_G.M2G2Frame = s
	s.connection = RunService.RenderStepped:Connect(function(dt)
		table.insert(s.delta, dt)
		table.insert(s.engine, Stats.FrameTime)
	end)
	return "Client RenderStepped and Stats.FrameTime sampling started"
end
local s = assert(_G.M2G2Frame, "Start frame measurement first")
s.connection:Disconnect()
local duration = os.clock() - s.started
assert(#s.delta > 0, "No render frames collected")
local function distribution(values)
	local sorted = table.clone(values)
	table.sort(sorted)
	local sum, over33, over100 = 0, 0, 0
	for _, v in values do
		sum += v
		if v > 1 / 30 then over33 += 1 end
		if v > .1 then over100 += 1 end
	end
	return {
		frames = #values, averageFps = #values / sum,
		p50Ms = sorted[math.ceil(#sorted * .5)] * 1000,
		p95Ms = sorted[math.ceil(#sorted * .95)] * 1000,
		p99Ms = sorted[math.ceil(#sorted * .99)] * 1000,
		worstMs = sorted[#sorted] * 1000,
		over33Ms = over33, over100Ms = over100,
	}
end
return game:GetService("HttpService"):JSONEncode({
	durationSeconds = duration,
	viewport = tostring(workspace.CurrentCamera.ViewportSize),
	quality = tostring(settings().Rendering.QualityLevel),
	streamingEnabled = workspace.StreamingEnabled,
	renderStepped = distribution(s.delta),
	statsFrameTime = distribution(s.engine),
	note = "Studio client timings, not physical-device or GPU profiling; viewport focus affects cadence",
})
