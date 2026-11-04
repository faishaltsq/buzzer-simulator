import sys
import os
import time
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio


PROBE_CODE = r"""
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local sss = game:GetService("ServerScriptService")

local SessionService = require(sss:WaitForChild("SessionService"))
local NetRouter = require(sss:WaitForChild("NetRouter"))
local WorldService = require(sss:WaitForChild("WorldService"))

local player = Players:GetPlayers()[1]

local results = {}
local function record(name, pass, detail)
	table.insert(results, { name = name, pass = pass == true, detail = tostring(detail) })
end

-- Mirrors tests/Specs/NetRouter.spec.luau fixture: replies/snapshots are the
-- transports NetRouter actually calls, with the documented 2-argument shape.
local function fixture(userId, overrides)
	local clock = { epoch = 1000, mono = 0 }
	local guid = 0
	local actor = { UserId = userId, Name = "SecProbe_" .. userId }
	local character = Instance.new("Model")
	character.Name = "Character"
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Parent = character
	actor.Character = character

	-- Exact v1 profile shape required by EconomyService.isUsableProfile.
	local profile = {
		balance = 100, lifetimeEarned = 100, completedMissions = 0,
		deviceId = "phone_cheap", propertyId = "bedroom",
		ownedDesks = {}, workers = {}, fractionalIncome = 0,
		claimedRunIdsWindow = {}, recentMutationOutcomes = {},
		missionVariantCounters = {}, nextOrganicSequence = 0,
		ownPosts = {}, nextPostSequence = 1,
	}
	for key, value in next, (overrides or {}) do profile[key] = value end

	local store = { data = {}, writes = 0 }
	function store:GetAsync(key) return self.data[key] end
	function store:UpdateAsync(key, transform)
		self.writes += 1
		local proposed = transform(self.data[key])
		if proposed ~= nil then self.data[key] = proposed end
		return proposed
	end
	store.data["Player_" .. userId] = {
		schemaVersion = 1, revision = 1, lastSaveOpId = "seed", updatedAt = 1000,
		profile = profile, lease = { token = "", jobId = "sec-probe", expiresAt = 0 },
	}

	local session = SessionService.new({
		userId = userId, store = store, jobId = "sec-probe",
		now = function() return clock.epoch end, wait = function() end,
		httpService = { GenerateGUID = function(_braces) guid += 1; return string.format("sec-guid-%04d", guid) end,
			JSONEncode = function(value) return HttpService:JSONEncode(value) end },
		noCacheOptions = function() return { UseCache = false } end,
	})
	local started = session:Start()
	if not started.ok and started.code == "NOT_READY" then session:InitializeStarter() end

	local prompt = Instance.new("ProximityPrompt")
	local world = {
		GetPrompt = function(a) return if a == actor then prompt else nil end,
		ValidateDashboardPrompt = function(a, p) return a == actor and p == prompt, nil end,
	}
	local replies, snapshots = {}, {}
	local router = NetRouter.new({
		world = world,
		now = function() return clock.epoch end,
		monotonic = function() return clock.mono end,
		guid = function() guid += 1; return string.format("dashboard-%04d", guid) end,
		sendReply = function(_actor, message) table.insert(replies, message) end,
		sendSnapshot = function(_actor, message) table.insert(snapshots, message) end,
	})
	router:Register(actor, session)
	local opened = router:HandlePrompt(prompt, actor)
	local dashId = nil
	for index = #snapshots, 1, -1 do
		if snapshots[index].kind == "OpenComputer" then dashId = snapshots[index].dashboardSessionId break end
	end

	local state = { clock = clock, player = actor, session = session, router = router, dashId = dashId,
		opened = opened, replies = replies }
	function state:command(action, payload, id)
		router:HandleCommand(actor, {
			requestId = id, action = action, payload = payload or {},
			dashboardSessionId = if action == "GetSnapshot" then nil else self.dashId,
		})
		return replies[#replies]
	end
	return state
end

-- SEC-01 unknown action ------------------------------------------------------
local f1 = fixture(91001)
local r1 = f1:command("GiveInfiniteCuan", {}, "probe-sec-01")
record("SEC-01 Unknown action forgery rejected", f1.opened and r1 ~= nil and r1.ok == false and r1.code == "UNKNOWN_ACTION",
	`dashboard={tostring(f1.opened)} code={tostring(r1 and r1.code)}`)

-- SEC-02 extra payload field (client price injection) ------------------------
local f2 = fixture(91002)
local r2 = f2:command("PublishOrganic", { templateId = "snack_meme", price = -999999 }, "probe-sec-02")
record("SEC-02 Client price injection rejected", r2 ~= nil and r2.ok == false and r2.code == "INVALID_INPUT",
	`code={tostring(r2 and r2.code)}`)

-- SEC-03 invalid slot numerics ----------------------------------------------
local f3 = fixture(91003)
local r3a = f3:command("BuyDesk", { slotIndex = -1 }, "probe-sec-03a")
local r3b = f3:command("BuyDesk", { slotIndex = 1.5 }, "probe-sec-03b")
local r3c = f3:command("BuyDesk", { slotIndex = 0 / 0 }, "probe-sec-03c")
record("SEC-03 Invalid slot numerics rejected",
	r3a and r3a.code == "INVALID_INPUT" and r3b and r3b.code == "INVALID_INPUT" and r3c and r3c.code == "INVALID_INPUT",
	`codes={tostring(r3a and r3a.code)},{tostring(r3b and r3b.code)},{tostring(r3c and r3c.code)}`)

-- SEC-04 real distance enforcement on a genuine spawned room ----------------
local ok4, pass4, detail4 = pcall(function()
	local room = WorldService.GetRoom(player)
	if room == nil then
		local spawned, err = WorldService.Spawn(player, { deviceId = "phone_cheap", ownedDesks = {}, workers = {} })
		if not spawned then return false, `spawn failed: {tostring(err)}` end
		room = WorldService.GetRoom(player)
	end
	local prompt = WorldService.GetPrompt(player)
	if prompt == nil then return false, "no server-owned dashboard prompt" end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root == nil then return false, "no HumanoidRootPart" end
	local anchor = prompt.Parent
	root.CFrame = CFrame.new(anchor.Position + Vector3.new(0, 3, 40))
	task.wait(0.15)
	local valid, err = WorldService.ValidateDashboardPrompt(player, prompt)
	local farOk = valid == false and typeof(err) == "string" and string.find(err, "studs", 1, true) ~= nil
	root.CFrame = CFrame.new(anchor.Position + Vector3.new(0, 3, 2))
	task.wait(0.15)
	local nearValid = WorldService.ValidateDashboardPrompt(player, prompt)
	return farOk and nearValid == true, `far={tostring(valid)} err={tostring(err)} near={tostring(nearValid)}`
end)
record("SEC-04 Prompt beyond 12 studs rejected", ok4 and pass4 == true,
	if ok4 then tostring(detail4) else `error: {tostring(pass4)}`)

-- SEC-05 cloned prompt instance ---------------------------------------------
local ok5, pass5, detail5 = pcall(function()
	local prompt = WorldService.GetPrompt(player)
	if prompt == nil then return false, "no server-owned dashboard prompt" end
	local clone = prompt:Clone()
	clone.Parent = workspace
	local valid, err = WorldService.ValidateDashboardPrompt(player, clone)
	clone:Destroy()
	return valid == false and typeof(err) == "string", `valid={tostring(valid)} err={tostring(err)}`
end)
record("SEC-05 Cloned prompt rejected", ok5 and pass5 == true,
	if ok5 then tostring(detail5) else `error: {tostring(pass5)}`)

-- SEC-06 rate limiting -------------------------------------------------------
local f6 = fixture(91006)
local admitted, throttled = 0, 0
for index = 1, 20 do
	local reply = f6:command("PublishOrganic", { templateId = "snack_meme" }, string.format("flood-req-%04d", index))
	if reply ~= nil and reply.code == "BUSY" then throttled += 1 else admitted += 1 end
end
record("SEC-06 Command flood throttled", admitted <= 8 and throttled >= 12, `admitted={admitted} throttled={throttled}`)

-- SEC-07 replay with altered intent -----------------------------------------
local f7 = fixture(91007)
local _first = f7:command("PublishOrganic", { templateId = "snack_meme" }, "idem-req-0001")
local r7 = f7:command("PublishOrganic", { templateId = "specs_breakdown" }, "idem-req-0001")
record("SEC-07 Conflicting replay refused", r7 ~= nil and r7.ok == false and r7.code == "INVALID_INPUT",
	`code={tostring(r7 and r7.code)}`)

-- SEC-08 insufficient funds --------------------------------------------------
local f8 = fixture(91008, { balance = 10 })
local r8 = f8:command("BuyDevice", { deviceId = "phone_fast" }, "probe-sec-08")
record("SEC-08 Insufficient funds purchase refused", r8 ~= nil and r8.ok == false and r8.code == "INSUFFICIENT_FUNDS",
	`code={tostring(r8 and r8.code)}`)

-- SEC-09 premature desk 2 gate ----------------------------------------------
local f9 = fixture(91009, { balance = 5000, tier = 0 })
local r9 = f9:command("BuyDesk", { slotIndex = 2 }, "probe-sec-09")
record("SEC-09 Premature desk 2 blocked", r9 ~= nil and r9.ok == false and r9.code == "NOT_READY",
	`code={tostring(r9 and r9.code)}`)

-- SEC-10 idle-expired dashboard ---------------------------------------------
local f10 = fixture(91010)
f10.clock.epoch += 700
f10.clock.mono += 700
f10.router:Step()
local r10 = f10:command("PublishOrganic", { templateId = "snack_meme" }, "probe-sec-10")
record("SEC-10 Expired dashboard refuses mutation", r10 ~= nil and r10.ok == false and r10.code == "SESSION_EXPIRED",
	`code={tostring(r10 and r10.code)}`)

local passed = 0
for _, entry in ipairs(results) do if entry.pass then passed += 1 end end
return HttpService:JSONEncode({ totalProbes = #results, passedProbes = passed, results = results })
"""


def run_probes():
    c = studio.get_client()
    sid = studio.get_studio_id()
    print(f"Starting Play Solo for Security Regression Probes (Studio ID: {sid})...")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(3)

    raw = studio.luau(PROBE_CODE, "Server")
    print("Raw Probe Output:", raw)

    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except Exception as exc:
        print(f"Error parsing probe output: {exc}")
        c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
        return {"error": str(exc), "raw": raw}

    print(f"\n=== Security Probes: {data.get('passedProbes')}/{data.get('totalProbes')} Passed ===")
    for entry in data.get("results", []):
        print(f"  [{'PASS' if entry.get('pass') else 'FAIL'}] {entry.get('name')}: {entry.get('detail')}")

    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})

    os.makedirs(os.path.join("docs", "evidence", "bs14"), exist_ok=True)
    report = os.path.join("docs", "evidence", "bs14", "security-regression.txt")
    ok = data.get("passedProbes") == data.get("totalProbes")
    with open(report, "w", encoding="utf-8") as handle:
        handle.write("=== BS-14 Security & Client-Server Boundary Regression Audit ===\n")
        handle.write(f"Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}\n")
        handle.write(f"Total Probes: {data.get('totalProbes')}, Passed: {data.get('passedProbes')}, "
                     f"Failed: {data.get('totalProbes', 0) - data.get('passedProbes', 0)}\n")
        handle.write(f"Verdict: {'PASS' if ok else 'FAIL'}\n\n")
        for entry in data.get("results", []):
            handle.write(f"[{'PASS' if entry.get('pass') else 'FAIL'}] {entry.get('name')}\n")
            handle.write(f"  Details: {entry.get('detail')}\n\n")
    print(f"Saved {report}")
    return data


if __name__ == "__main__":
    run_probes()
