--!strict
local scripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local State = require(scripts:WaitForChild("ClientState"))
local Composer = require(scripts.ui:WaitForChild("PostComposer"))
local Missions = require(scripts.ui:WaitForChild("Missions"))
local Desktop = require(scripts.ui:WaitForChild("Desktop"))
local Feed = require(scripts.ui:WaitForChild("Feed"))
local tests = {}
local function test(name, fn) table.insert(tests, {name=name, fn=fn}) end
local function snapshot(revision)
	return {revision=revision or 1, serverTime=1000, balance=0, saveStatus="healthy", tier=0, completedMissions=0,
		deviceId="phone_cheap", nextOrganicContextId="organic_snack", ownPosts={}, workers={}, pendingWorkerCuan=0, incomePerSecond=0}
end
local function fixture()
	local state = State.new(snapshot())
	state:ApplyOpenComputer({dashboardSessionId="dashboard-test", expiresAt=1600, serverTime=1000, state=snapshot()}, 10)
	state:OnCameraOpened()
	local parent = Instance.new("Folder")
	local sent = {}
	local options = {parent=parent, onAction=function(action,payload)
		local envelope = state:BeginMutation(action,payload,11)
		if envelope then table.insert(sent,envelope) end
	end, getBlockReason=function() return state:MutationBlockReason() end}
	return state,parent,sent,options
end

test("organic context and three eligible authored choices come from snapshot", function()
	local state,parent,_,options=fixture()
	local composer=Composer.new(options)
	composer:Update(state:Get())
	assert(composer._context.Text:find("Trend:",1,true))
	assert(composer._templateIds[1]=="snack_meme" and composer._templateIds[2]=="snack_thread" and composer._templateIds[3]=="snack_honest")
	local changed=snapshot(2); changed.nextOrganicContextId="unshipped_context"
	state:ApplyStateSnapshot(changed); composer:Update(state:Get())
	assert(not composer._publish.Active and not composer._choices.Visible)
	parent:Destroy()
end)

test("selected organic preview publishes once with no arbitrary context or money", function()
	local state,parent,sent,options=fixture(); local composer=Composer.new(options)
	state:Subscribe(function(data) composer:Update(data) end)
	composer._selection="snack_honest"; composer:_renderSelection()
	assert(composer._preview.Text:find("Your selected post",1,true))
	composer:Publish(); composer:Publish()
	assert(#sent==1 and sent[1].action=="PublishOrganic" and sent[1].payload.templateId=="snack_honest")
	local count=0; for _ in pairs(sent[1].payload) do count+=1 end
	assert(count==1 and sent[1].dashboardSessionId=="dashboard-test")
	assert(state:GetConfirmedBalance()==0)
	parent:Destroy()
end)

test("save blocked selection cannot publish",function()
	local state,parent,sent,options=fixture(); local composer=Composer.new(options)
	local snap=snapshot(2);snap.saveStatus="SAVE_UNAVAILABLE";state:ApplyStateSnapshot(snap)
	composer:Update(state:Get());composer._selection="snack_meme";composer:_renderSelection();composer:Publish()
	assert(not composer._publish.Active and #sent==0)
	parent:Destroy()
end)

test("global pending blocks both composers and zero reveal cannot settle",function()
	local state,parent,sent,options=fixture();local organic=Composer.new(options)
	local missionOptions=table.clone(options);missionOptions.mode="mission";local mission=Composer.new(missionOptions)
	local snap=snapshot(2)
	snap.activeMission={missionId="food_stall_launch",runId="run-test",contextId="meal_time",status="accepted",accumulatedImpact=0,postCount=0}
	snap.pendingPost={postId="post-0",mode="organic",contextId="organic_snack",templateId="snack_meme",publishedAt=1000,settleAt=1018,finalImpact=120,organicCuan=15}
	state:ApplyStateSnapshot(snap)
	for _,view in ipairs({organic,mission}) do
		view:Update(state:Get());view._selection=view._templateIds[1];view:_renderSelection();view:Publish();view:Tick(1100)
		assert(not view._publish.Active and view._pendingTitle.Text=="Awaiting server confirmation")
	end
	assert(#sent==0 and state:GetConfirmedBalance()==0 and state:Get().snapshot.activeMission.accumulatedImpact==0)
	assert(state:Get().snapshot.pendingPost.postId=="post-0")
	parent:Destroy()
end)

test("mission composer binds selection to current authoritative run",function()
	local state,parent,sent,options=fixture();options.mode="mission";local view=Composer.new(options)
	local snap=snapshot(2);snap.activeMission={missionId="food_stall_launch",runId="run-current",contextId="meal_time",status="accepted",accumulatedImpact=75,postCount=1}
	state:ApplyStateSnapshot(snap);view:Update(state:Get());view._selection="queue_thread";view:_renderSelection();view:Publish()
	assert(#sent==1 and sent[1].action=="PublishPost" and sent[1].payload.runId=="run-current" and sent[1].payload.templateId=="queue_thread")
	parent:Destroy()
end)

test("new mission generation clears previous selected template",function()
	local state,parent,_,options=fixture();options.mode="mission";local view=Composer.new(options)
	local snap=snapshot(2);snap.activeMission={missionId="food_stall_launch",runId="run-old",contextId="meal_time",status="accepted",accumulatedImpact=0,postCount=0}
	state:ApplyStateSnapshot(snap);view:Update(state:Get());view._selection="meal_meme";view:_renderSelection()
	local replacement=snapshot(3);replacement.activeMission=table.clone(snap.activeMission);replacement.activeMission.runId="run-new"
	state:ApplyStateSnapshot(replacement);view:Update(state:Get())
	assert(view._selection==nil and not view._publish.Active)
	parent:Destroy()
end)

test("ready mission claims separately and hides third publish",function()
	local state,parent,sent,options=fixture();local view=Missions.new(options)
	local snap=snapshot(2);snap.balance=18;snap.activeMission={missionId="food_stall_launch",runId="run-ready",contextId="meal_time",status="readyToClaim",accumulatedImpact=150,postCount=2}
	state:ApplyStateSnapshot(snap);state:Subscribe(function(data)view:Update(data)end)
	assert(view._action.Active and view._action.Text:find("80",1,true))
	assert(not view._composer._publish.Visible)
	view:Act();view:Act()
	assert(#sent==1 and sent[1].action=="ClaimMission" and sent[1].payload.runId=="run-ready")
	assert(state:GetConfirmedBalance()==18)
	parent:Destroy()
end)

test("available campaign accepts catalog mission rather than publishing",function()
	local state,parent,sent,options=fixture();local view=Missions.new(options)
	state:Subscribe(function(data)view:Update(data)end);view:Act();view:Act()
	assert(#sent==1 and sent[1].action=="AcceptMission" and sent[1].payload.missionId=="food_stall_launch")
	assert(state:Get().snapshot.activeMission==nil)
	parent:Destroy()
end)

test("close reopen reconstructs global pending without replaying publication",function()
	local state,parent,sent,options=fixture();local view=Composer.new(options)
	local snap=snapshot(2);snap.pendingPost={postId="post-resume",mode="organic",templateId="snack_meme",contextId="organic_snack",publishedAt=1000,settleAt=1018,finalImpact=120,organicCuan=15}
	state:ApplyStateSnapshot(snap);state:CloseLocally();state:OnCameraRestored()
	state:ApplyOpenComputer({dashboardSessionId="dashboard-reopen",expiresAt=1600,serverTime=1010,state=snap},20);state:OnCameraOpened()
	view:Update(state:Get());view:Tick(1010)
	assert(view._pending.Visible and view._pendingTitle.Text:find("8s",1,true))
	assert(#sent==0 and state:GetConfirmedBalance()==0)
	parent:Destroy()
end)

test("confirmed history renders payout while stale snapshots cannot change balance",function()
	local state,parent,_,options=fixture();local view=Composer.new(options)
	local snap=snapshot(4);snap.balance=15;snap.ownPosts={{postId="post-paid",mode="organic",templateId="snack_meme",contextId="organic_snack",publishedAt=1000.25,finalImpact=120,organicCuan=15}}
	state:ApplyStateSnapshot(snap);state:ApplyStateSnapshot(snapshot(3));view:Update(state:Get())
	assert(state:GetConfirmedBalance()==15 and view._result.Text:find("+15 organic Cuan credited",1,true))
	assert(view._result.Text:find("18 likes · 4 replies",1,true), "fractional server timestamps must not produce fractional engagement counts")
	assert(not view._result.Text:find("strong",1,true))
	parent:Destroy()
end)
test("Missions UI reflects intermediate weak state, resolving state, and claim reset", function()
	local state, parent, sent, options = fixture()
	local view = Missions.new(options)
	
	local snap1 = snapshot(2)
	snap1.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-weak",
		contextId = "meal_time",
		status = "accepted",
		accumulatedImpact = 75,
		postCount = 1,
	}
	state:ApplyStateSnapshot(snap1)
	view:Update(state:Get())
	assert(view._progress.Text:find("needs more impact", 1, true), "must guide to second post")
	assert(view._action.Text == "Choose a campaign post below")
	assert(not view._action.Active)
	
	local snap2 = snapshot(3)
	snap2.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-weak",
		contextId = "meal_time",
		status = "resolvingPost",
		accumulatedImpact = 75,
		postCount = 2,
	}
	state:ApplyStateSnapshot(snap2)
	view:Update(state:Get())
	assert(view._progress.Text:find("resolving", 1, true), "must reflect in-flight resolving state")
	assert(view._action.Text == "Waiting for post settlement")
	assert(not view._action.Active)
	
	local snap3 = snapshot(4)
	snap3.completedMissions = 1
	snap3.balance = 208
	state:ApplyStateSnapshot(snap3)
	view:Update(state:Get())
	assert(view._progress.Text:find("1 confirmed campaign claims", 1, true), "must show claim count")
	assert(view._action.Text == "Accept campaign")
	assert(view._action.Active)
	parent:Destroy()
end)

test("Feed UI renders empty states, confirmed cards, and navigation callback", function()
	local state, parent, _, options = fixture()
	local navigatedTo = nil
	local feed = Feed.new({
		parent = parent,
		onNavigate = function(tabId)
			navigatedTo = tabId
		end,
	})
	
	feed:Update(state:Get())
	assert(feed.Root ~= nil)
	
	local snap = snapshot(2)
	snap.ownPosts = {
		{
			postId = "p-1",
			mode = "organic",
			templateId = "snack_meme",
			contextId = "organic_snack",
			publishedAt = 1000,
			finalImpact = 120,
			organicCuan = 15,
		},
	}
	state:ApplyStateSnapshot(snap)
	feed:Update(state:Get())
	assert(feed.Root:FindFirstChild("own-p-1", true) ~= nil, "must render confirmed card")
	parent:Destroy()
end)

test("Desktop Home reflects dynamic shortcuts and action dispatches", function()
	local state, parent, sent, options = fixture()
	local navigated = nil
	local actionsSent = {}
	local desktop = Desktop.new({
		parent = parent,
		onTabSelected = function(tab) navigated = tab end,
		onAction = function(action, payload) table.insert(actionsSent, { action = action, payload = payload }) end,
		getBlockReason = function() return state:MutationBlockReason() end,
	})
	
	local snap = snapshot(2)
	snap.activeMission = {
		missionId = "food_stall_launch",
		runId = "run-home",
		contextId = "meal_time",
		status = "readyToClaim",
		accumulatedImpact = 150,
		postCount = 2,
	}
	state:ApplyStateSnapshot(snap)
	desktop:Update(state:Get())
	
	desktop._onAction("GetSnapshot", {})
	assert(#actionsSent == 1 and actionsSent[1].action == "GetSnapshot")
	assert(desktop._homeRefresh.Name == "RefreshProgress")
	parent:Destroy()
end)

test("PostComposer confirmation barrier disables publish button and displays barrier copy", function()
	local state, parent, sent, options = fixture()
	local composer = Composer.new(options)
	composer:Update(state:Get())
	composer._selection = "snack_meme"
	composer:_renderSelection()
	assert(composer._publish.Active, "must be active when free")
	
	state:TrackRequest("req-1", "PublishOrganic", true, 1000)
	composer:Update(state:Get())
	assert(not composer._publish.Active, "barrier must disable publish button")
	assert(composer._notice.Text:find("BUSY", 1, true), "barrier notice must display")
	parent:Destroy()
end)

local failed=0
for _,case in ipairs(tests) do
	local ok,err=pcall(case.fn)
	if ok then print(`[PASS] {case.name}`) else failed+=1;warn(`[FAIL] {case.name}: {err}`) end
end
assert(failed==0,`ComposerIntegration: {failed} failed`)
return `{#tests}/{#tests} passed`
