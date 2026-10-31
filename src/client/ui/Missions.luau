--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Presentation = require(Shared:WaitForChild("Presentation"))
local Composer = require(script.Parent:WaitForChild("PostComposer"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Missions = {}
Missions.__index = Missions

function Missions.new(options: any): any
	local self = setmetatable({}, Missions)
	self._onAction = options.onAction
	self._getBlockReason = options.getBlockReason
	self.Root = Composer.stack(options.parent, "Page_Missions", true)
	Composer.label(self.Root, "Heading", "Campaign desk", 22)
	self._brief = Composer.label(self.Root, "Briefing", "Loading available campaigns...", 18, Theme.Colors.Amber)
	self._details = Composer.label(self.Root, "CampaignDetails", "", 15)
	self._progress = Composer.label(self.Root, "MissionProgress", "", 18)
	self._action = Composer.button(self.Root, "CampaignAction", "Accept campaign", function() self:Act() end)
	self._notice = Composer.label(self.Root, "MissionStatus", "", 14, Theme.Colors.CreamMuted)
	self._composer = Composer.new({parent = self.Root, mode = "mission", onAction = options.onAction, getBlockReason = options.getBlockReason})
	return self
end

function Missions:Act()
	if not self._action.Active or not self._definition then return end
	local snap = self._state and self._state.snapshot
	if not snap then return end
	local active = snap.activeMission
	if active then
		if active.status == "readyToClaim" and active.runId then
			self._onAction("ClaimMission", { runId = active.runId })
		end
	else
		self._onAction("AcceptMission", { missionId = self._definition.missionId })
	end
end

function Missions:Update(data: any)
	self._state = data
	local snap = data.snapshot
	local active = snap and snap.activeMission
	local def = nil
	for _, mission in ipairs(Catalog.Missions) do
		if (active and mission.missionId == active.missionId) or (not active and table.find(Catalog.V0Shipped.missionIds, mission.missionId)) then
			def = mission
			break
		end
	end
	self._definition = def
	self._composer:Update(data)
	self._composer.Root.Visible = active ~= nil
	if not snap or not def then
		Composer.setEnabled(self._action, false)
		return
	end
	local copy = Presentation.Missions[def.missionId]
	self._brief.Text = if copy then copy.title else def.missionId
	local contextId = if active then active.contextId else def.contexts[1]
	local context = Presentation.Contexts[contextId]
	self._details.Text = `{if copy then copy.brief else "Read the campaign clue before choosing a post."}\n\nRequired impact: {def.requiredImpact} · Separate bonus: {def.reward} Cuan\n{if context then `Trend: {context.trend}\nAudience: {context.audience}\n{context.clue}` else "Context not available."}`
	local reason = self._getBlockReason and self._getBlockReason() or nil
	local tier = snap.tier or 0
	local completedMissions = snap.completedMissions or 0
	local unlocked = tier >= def.minTier and completedMissions >= def.unlockClaims
	local enabled = false
	if active then
		if active.status == "readyToClaim" then
			self._progress.Text = `Ready to claim · {active.accumulatedImpact}/{def.requiredImpact} impact\nOrganic post earnings are already credited.`
			self._action.Text = `Claim {def.reward} Cuan campaign bonus`
			enabled = true
		elseif active.status == "resolvingPost" then
			self._progress.Text = `Campaign post resolving · {active.accumulatedImpact}/{def.requiredImpact} confirmed impact`
			self._action.Text = "Waiting for post settlement"
		else
			self._progress.Text = `Accepted · {active.accumulatedImpact}/{def.requiredImpact} impact · {active.postCount}/2 posts\n{if active.postCount > 0 then "The campaign needs more impact. Choose a second post below." else "Choose a campaign-tagged post below."}`
			self._action.Text = "Choose a campaign post below"
		end
	else
		self._progress.Text = if completedMissions > 0 then `Bonus claimed · {completedMissions} confirmed campaign claims\nStart a new run when you are ready.` else "Available · Accept this campaign to tag your next post."
		self._action.Text = if unlocked then "Accept campaign" else "Campaign locked"
		enabled = unlocked
	end
	Composer.setEnabled(self._action, enabled and reason == nil)
	self._notice.Text = reason or data.activeError or "Organic-only posts do not advance this campaign. No more than two campaign posts per run."
end

function Missions:Tick(serverNow: number)
	self._composer:Tick(serverNow)
end

function Missions:Destroy()
	self.Root:Destroy()
end
return Missions
