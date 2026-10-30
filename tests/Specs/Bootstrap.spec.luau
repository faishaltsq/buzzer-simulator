--!strict
-- Real sessions, persistence and world kits; only clocks/transport/platform signals are injected.
local ServerStorage = game:GetService("ServerStorage")
local Runtime = require(ServerStorage:WaitForChild("BootstrapRuntime"))
local SessionService = require(ServerStorage:WaitForChild("SessionService"))
local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))
local WorldService = require(ServerStorage:WaitForChild("WorldService"))
local tests = {}
local function test(name, fn) table.insert(tests, {name = name, fn = fn}) end
local function equal(actual, expected, label)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end
local function signal()
	local entries = {}
	local s = {}
	function s:Connect(callback)
		local entry = {callback = callback, active = true}
		table.insert(entries, entry)
		return {Disconnect = function() entry.active = false end}
	end
	function s:Fire(...)
		for _, entry in ipairs(table.clone(entries)) do
			if entry.active then entry.callback(...) end
		end
	end
	function s:Count()
		local count = 0
		for _, entry in ipairs(entries) do if entry.active then count += 1 end end
		return count
	end
	return s
end
local function encode(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for key in pairs(value) do table.insert(keys, key) end
	table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, key in ipairs(keys) do table.insert(parts, tostring(key)..":"..encode(value[key])) end
	return "{"..table.concat(parts, ",").."}"
end
local function starter()
	return {
		balance=0, lifetimeEarned=0, completedMissions=0, deviceId="phone_cheap",
		propertyId="bedroom", ownedDesks={}, workers={}, fractionalIncome=0,
		claimedRunIdsWindow={}, recentMutationOutcomes={}, missionVariantCounters={},
		nextOrganicSequence=0, ownPosts={}, nextPostSequence=1,
	}
end
local function worker()
	local profile = starter()
	profile.deviceId="pc_rumah"; profile.lifetimeEarned=300; profile.completedMissions=3
	profile.ownedDesks={1}; profile.workers={{hireId="worker-1",roleId="trainee",slotIndex=1}}
	return profile
end
local nextUser = 61000
local function character()
	local c = Instance.new("Model"); c.Name="BootstrapFixtureCharacter"; c.Parent=workspace
	local h = Instance.new("Humanoid"); h.Parent=c
	local p = Instance.new("Part"); p.Name="HumanoidRootPart"; p.Anchored=true; p.CanCollide=false; p.Parent=c
	return c
end
local function fixture(profile)
	nextUser += 1
	local f = {mono=0, replies={}, snapshots={}, reports={}, sessions={}, jobs={}, holds={}}
	local data = {}
	local adapter = {updates=0, gets=0, failRead=false, failWrite=false}
	function adapter:GetAsync(key)
		self.gets += 1
		if self.onGet then self.onGet(key) end
		if self.failRead then error("injected read failure") end
		return ProfileStore._deepCopy(data[key])
	end
	function adapter:UpdateAsync(key, transform)
		self.updates += 1
		if self.onUpdate then self.onUpdate(key) end
		if self.failWrite then error("injected write failure") end
		local proposal=transform(ProfileStore._deepCopy(data[key]))
		if proposal then data[key]=ProfileStore._deepCopy(proposal) end
		return ProfileStore._deepCopy(proposal)
	end
	local player = {UserId=nextUser, Name=`BootstrapFixture{nextUser}`, Character=character(),
		CharacterAdded=signal(), CharacterRemoving=signal(), attributes={}}
	function player:SetAttribute(k,v) self.attributes[k]=v end
	function player:GetAttribute(k) return self.attributes[k] end
	f.player=player; f.store=adapter; f.data=data
	local players={PlayerAdded=signal(), PlayerRemoving=signal(), current={player}}
	function players:GetPlayers() return self.current end
	f.players=players; f.prompts={PromptTriggered=signal()}; f.heartbeat=signal()
	f.root=Instance.new("Folder")
	if profile then
		data[`Player_{player.UserId}`]={schemaVersion=1,revision=1,lastSaveOpId="seed",updatedAt=1000,
			profile=profile,lease={token="",jobId="seed",expiresAt=0}}
	end
	local guidCounter=0
	local http={}
	function http:GenerateGUID()
		guidCounter += 1
		return `bootstrap-guid-{nextUser}-{guidCounter}`
	end
	function http:JSONEncode(v) return encode(v) end
	local function run(fn)
		local co=coroutine.create(fn)
		table.insert(f.jobs,co)
		local ok,err=coroutine.resume(co)
		assert(ok,err)
	end
	f.runtime=Runtime.new({
		players=players,prompts=f.prompts,heartbeat=f.heartbeat,replicatedStorage=f.root,
		bindToClose=function(callback) f.close=callback end,
		world=WorldService, now=function() return 1000+f.mono end, monotonic=function() return f.mono end,
		guid=function() return http:GenerateGUID() end,spawn=run,
		wait=function(dt) if dt>0 then f.mono+=dt end end, shutdownSeconds=1,
		report=function(message) table.insert(f.reports,message) end,
		sendReply=function(p,message) table.insert(f.replies,{player=p,message=message}) end,
		sendSnapshot=function(p,message) table.insert(f.snapshots,{player=p,message=message}) end,
		sessionFactory=function(p)
			local session=SessionService.new({userId=p.UserId,store=adapter,httpService=http,
				jobId="bootstrap-tests",now=function() return 1000+f.mono end,
				connectedNow=function() return f.mono end,wait=function() end,
				noCacheOptions=function() return {UseCache=false} end})
			f.sessions[p]=session
			return session
		end,
	})
	function f:step(dt)
		self.mono+=dt
		self.runtime:Step()
	end
	function f:open()
		local anchor=WorldService.GetAnchor(player,"DashboardPromptAnchor")
		player.Character.HumanoidRootPart.Position=anchor.Position+Vector3.new(0,0,3)
		self.prompts.PromptTriggered:Fire(WorldService.GetPrompt(player),player)
		local message=self.snapshots[#self.snapshots].message
		equal(message.kind,"OpenComputer","validated prompt opens")
		return message.dashboardSessionId
	end
	function f:command(id,action,payload,dashboard)
		self.runtime:HandleCommand(player,{requestId=id,action=action,payload=payload,dashboardSessionId=dashboard})
		return self.replies[#self.replies].message
	end
	function f:finish()
		self.runtime:Stop()
		WorldService.Remove(player)
		if player.Character then player.Character:Destroy() end
		self.root:Destroy()
	end
	return f
end

-- Always restore real prefabs/fixtures even if an assertion raises.
local function withFixture(profile, body)
	local f=fixture(profile)
	local ok,err=xpcall(function() body(f) end,debug.traceback)
	f:finish()
	assert(ok,err)
end

test("Fresh join durably initializes once and creates the correct V0 room",function()
	withFixture(nil,function(f)
		f.runtime:Start()
		local saved=f.data[`Player_{f.player.UserId}`]
		equal(saved.revision,2,"lease plus starter revision")
		equal(saved.profile.balance,0,"zero starter balance")
		equal(saved.profile.deviceId,"phone_cheap","starter phone")
		equal(f.player:GetAttribute("BuzzerReady"),true,"ready after confirmation")
		equal(WorldService.CountInRoom(f.player,"ProximityPrompt"),1,"stable prompt")
		assert(WorldService.GetRoom(f.player):FindFirstChild("OldCRT",true))
		assert(not WorldService.GetRoom(f.player):FindFirstChild("PCRumah",true))
		local writes=f.store.updates
		f.runtime:Start(); f.players.PlayerAdded:Fire(f.player)
		equal(f.store.updates,writes,"duplicate lifecycle does not reload or reinitialize")
	end)
end)

test("Failed reads never initialize or spawn a room",function()
	withFixture(nil,function(f)
		f.store.failRead=true; f.runtime:Start()
		equal(f.store.updates,0,"no lease/init write after failed read")
		equal(f.data[`Player_{f.player.UserId}`],nil,"empty key remains empty")
		equal(WorldService.GetRoom(f.player),nil,"no unconfirmed world")
		equal(f.player:GetAttribute("BuzzerLoadError"),"SAVE_UNAVAILABLE","load error surfaced")
		local reply=f:command("before01","GetSnapshot",{})
		equal(reply.ok,false,"no session access")
	end)
end)

test("A competing lease prevents initialization and world ownership",function()
	withFixture(starter(),function(f)
		local saved=f.data[`Player_{f.player.UserId}`]
		saved.lease={token="foreign-token",jobId="other-server",expiresAt=1200}
		f.runtime:Start()
		equal(f.player:GetAttribute("BuzzerReady"),false,"not ready with foreign lease")
		equal(saved.lease.token,"foreign-token","foreign token unchanged")
		equal(WorldService.GetRoom(f.player),nil,"no world on failed acquisition")
	end)
end)

test("Leaving during a held first read does not initialize after departure",function()
	withFixture(nil,function(f)
		local held
		f.store.onGet=function() f.store.onGet=nil; held=coroutine.running(); coroutine.yield() end
		f.runtime:Start()
		f.players.PlayerRemoving:Fire(f.player)
		local ok,err=coroutine.resume(held); assert(ok,err)
		local saved=f.data[`Player_{f.player.UserId}`]
		equal(saved.profile,nil,"no starter invented for departed player")
		equal(saved.lease.token,"","acquired empty lease released")
		equal(WorldService.GetRoom(f.player),nil,"no late room")
		equal(f.player:GetAttribute("BuzzerReady"),false,"no late readiness")
	end)
end)

test("Confirmed phone purchase recovers presentation without charging twice",function()
	local profile=starter(); profile.balance=100; profile.lifetimeEarned=100
	withFixture(profile,function(f)
		f.runtime:Start()
		local dashboard=f:open()
		local prompt=WorldService.GetPrompt(f.player)
		local prefabs=ServerStorage.WorldPrefabs
		local fast=prefabs.PhoneFast; fast.Parent=nil
		local ok,err=xpcall(function()
			local result=f:command("buyphone1","BuyDevice",{deviceId="phone_fast"},dashboard)
			equal(result.ok,true,"confirmed purchase remains successful")
			equal(f.sessions[f.player]:GetConfirmedProfile().balance,50,"charged once")
			assert(f.player:GetAttribute("BuzzerWorldError"),"presentation error surfaced")
			fast.Parent=prefabs
			local writes=f.store.updates
			f:step(2)
			equal(f.player:GetAttribute("BuzzerWorldError"),nil,"presentation recovered")
			assert(WorldService.GetAnchor(f.player,"PhoneSlot"):FindFirstChild("PhoneFast"))
			equal(WorldService.GetPrompt(f.player),prompt,"prompt unchanged")
			f:command("buyphone1","BuyDevice",{deviceId="phone_fast"},dashboard)
			equal(f.store.updates,writes,"visual recovery/replay add no economic write")
			equal(f.sessions[f.player]:GetConfirmedProfile().balance,50,"no second charge")
		end,debug.traceback)
		fast.Parent=prefabs
		assert(ok,err)
	end)
end)

test("Long scheduler stalls retain bounded-chunk connected income exactly once",function()
	withFixture(worker(),function(f)
		f.runtime:Start()
		f:step(75)
		local session=f.sessions[f.player]
		equal(session:GetConfirmedProfile().balance,112,"75 seconds banked")
		equal(session:GetConfirmedProfile().fractionalIncome,.5,"half Cuan carried")
		f:step(0)
		equal(session:GetConfirmedProfile().balance,112,"same sample cannot pay twice")
		f:step(75)
		equal(session:GetConfirmedProfile().balance,225,"second75 seconds counted once")
		equal(session:GetConfirmedProfile().fractionalIncome,0,"fractional carry exact")
	end)
end)

test("Worker banks piggyback lease renewal instead of competing durable loops",function()
	withFixture(worker(),function(f)
		f.runtime:Start()
		local writes=f.store.updates
		f:step(30); f:step(60)
		equal(f.store.updates-writes,2,"two banks and no redundant renewal")
		equal(f.sessions[f.player]:GetConfirmedProfile().balance,135,"90 connected seconds")
	end)
end)

test("Idle State pushes never write and lease renewal waits90 seconds",function()
	withFixture(starter(),function(f)
		f.runtime:Start()
		local writes=f.store.updates
		for _=1,10 do f:step(1) end
		equal(f.store.updates,writes,"ordinary pushes perform no save")
		assert(#f.snapshots<=6,"State pushes throttled to2 seconds")
		f:step(79)
		equal(f.store.updates,writes,"no early renewal")
		f:step(1)
		equal(f.store.updates,writes+1,"one renewal at90")
	end)
end)

test("Post settlement runs behind scheduler and exposes confirmed credit only",function()
	withFixture(starter(),function(f)
		f.runtime:Start()
		local dashboard=f:open()
		local publish=f:command("publish01","PublishOrganic",{templateId="snack_meme"},dashboard)
		equal(publish.ok,true,"publish admitted")
		equal(f.sessions[f.player]:GetConfirmedProfile().balance,0,"not paid at publish")
		f:step(17)
		equal(f.sessions[f.player]:GetConfirmedProfile().balance,0,"not paid early")
		f:step(1)
		equal(f.sessions[f.player]:GetConfirmedProfile().balance,15,"one due organic payment")
		local writes=f.store.updates
		f:step(2)
		equal(f.store.updates,writes,"settlement not duplicated")
		local state=f.snapshots[#f.snapshots].message.state
		equal(state.balance,15,"confirmed State credit")
		equal(state.lease,nil,"no lease in State")
		equal(state.recentMutationOutcomes,nil,"no durable internals in State")
	end)
end)

test("Character loss expires once and player leave disposes listeners and lease",function()
	withFixture(starter(),function(f)
		f.runtime:Start(); local dashboard=f:open()
		local oldCharacter=f.player.Character
		f.player.CharacterRemoving:Fire(oldCharacter); f.player.Character=nil
		f:step(1); f:step(1)
		local expiries=0
		for _,sent in ipairs(f.snapshots) do
			if sent.message.kind=="ComputerSessionExpired" then
				expiries+=1; equal(sent.message.dashboardSessionId,dashboard,"original generation")
				equal(sent.message.reason,"CHARACTER_LOST","loss reason")
			end
		end
		equal(expiries,1,"one character expiry")
		oldCharacter:Destroy()
		f.player.Character=character(); f.player.CharacterAdded:Fire(f.player.Character)
		f.players.PlayerRemoving:Fire(f.player)
		equal(f.player.CharacterAdded:Count(),0,"added listener disconnected")
		equal(f.player.CharacterRemoving:Count(),0,"removing listener disconnected")
		equal(WorldService.GetRoom(f.player),nil,"world removed")
		equal(f.data[`Player_{f.player.UserId}`].lease.token,"","lease released")
	end)
end)

test("Shutdown banks connected remainder and disconnects aggregate listeners",function()
	withFixture(worker(),function(f)
		f.runtime:Start(); f:step(10)
		f.close()
		equal(f.data[`Player_{f.player.UserId}`].profile.balance,15,"final remainder banked")
		equal(f.data[`Player_{f.player.UserId}`].lease.token,"","final release")
		equal(f.heartbeat:Count(),0,"aggregate scheduler disconnected")
		equal(f.players.PlayerAdded:Count(),0,"join listener disconnected")
		equal(f.prompts.PromptTriggered:Count(),0,"prompt listener disconnected")
		local writes=f.store.updates
		equal(f.runtime:Stop(),true,"repeated shutdown idempotent")
		equal(f.store.updates,writes,"no repeat final writes")
	end)
end)

test("Failed final banking is reported without fictional shutdown success",function()
	withFixture(worker(),function(f)
		f.runtime:Start(); f:step(10); f.store.failWrite=true
		equal(f.runtime:Stop(),false,"best-effort failure remains visible")
		equal(f.data[`Player_{f.player.UserId}`].profile.balance,0,"unconfirmed bank not exposed")
		assert(f.data[`Player_{f.player.UserId}`].lease.token~="","lease retained for reconciliation")
		assert(#f.reports>0,"finalization failure surfaced")
	end)
end)

test("Expired lease prevents scheduler from inventing long-stall worker income",function()
	withFixture(worker(),function(f)
		f.runtime:Start()
		local writes=f.store.updates
		f:step(245)
		equal(f.sessions[f.player]:GetConfirmedProfile().balance,0,"no income beyond lease authority")
		equal(f.store.updates,writes,"expired session creates no new write")
	end)
end)

local passed=0
for _, case in ipairs(tests) do
	local ok,err=pcall(case.fn)
	if ok then passed+=1; print(`[PASS] {case.name}`) else warn(`[FAIL] {case.name}: {err}`) end
end
print(`Bootstrap spec: {passed}/{#tests} passed, {#tests-passed} failed`)
assert(passed==#tests,`Bootstrap: {#tests-passed} test(s) failed`)
return `Bootstrap: {passed}/{#tests} passed`
