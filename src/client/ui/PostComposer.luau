--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Presentation = require(Shared:WaitForChild("Presentation"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Composer = {}
Composer.__index = Composer

-- Content-sized rows keep long authored copy readable at every viewport width.
function Composer.stack(parent: Instance, name: string, scrollable: boolean?): any
	local root = Instance.new(if scrollable then "ScrollingFrame" else "Frame") :: any
	root.Name = name
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, if scrollable then 1 else 0, 0)
	if scrollable then
		root.CanvasSize = UDim2.new()
		root.AutomaticCanvasSize = Enum.AutomaticSize.Y
		root.ScrollBarThickness = 4
		root.ScrollBarImageColor3 = Theme.Colors.Sage
		root.ScrollingDirection = Enum.ScrollingDirection.Y
	else
		root.AutomaticSize = Enum.AutomaticSize.Y
	end
	root.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = root
	Theme.applyPadding(root, 16, 16, 24, 16)
	return root
end

function Composer.label(parent: Instance, name: string, text: string, size: number?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = if size and size >= 18 then Theme.Fonts.Bold else Theme.Fonts.Regular
	label.TextSize = size or 15
	label.TextColor3 = color or Theme.Colors.Cream
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = text
	label.Parent = parent
	return label
end

function Composer.button(parent: Instance, name: string, text: string, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(1, 0, 0, 48)
	button.Font = Theme.Fonts.Bold
	button.TextSize = 15
	button.TextWrapped = true
	button.TextColor3 = Theme.Colors.CharcoalDark
	button.BackgroundColor3 = Theme.Colors.Lime
	button.Text = text
	button.AutoButtonColor = true
	button.Selectable = true
	button.Parent = parent
	Theme.applyCorner(button, Theme.Radii.Small)
	button.Activated:Connect(callback)
	button.SelectionGained:Connect(function()
		Theme.applyStroke(button, Theme.Colors.Cream, 2)
		local ancestor = button.Parent
		while ancestor do
			if ancestor:IsA("ScrollingFrame") then
				local top = button.AbsolutePosition.Y - ancestor.AbsolutePosition.Y + ancestor.CanvasPosition.Y
				if top < ancestor.CanvasPosition.Y then
					ancestor.CanvasPosition = Vector2.new(0, math.max(0, top - 8))
				elseif top + button.AbsoluteSize.Y > ancestor.CanvasPosition.Y + ancestor.AbsoluteWindowSize.Y then
					ancestor.CanvasPosition = Vector2.new(0, math.max(0, top + button.AbsoluteSize.Y - ancestor.AbsoluteWindowSize.Y + 8))
				end
				break
			end
			ancestor = ancestor.Parent
		end
	end)
	button.SelectionLost:Connect(function()
		if button:GetAttribute("Selected") == true then
			Theme.applyStroke(button, Theme.Colors.Amber, 2)
		else
			Theme.applyStroke(button, Theme.Colors.BorderLight, 1)
		end
	end)
	return button
end

function Composer.setEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then Theme.Colors.Lime else Theme.Colors.CharcoalLight
	button.TextColor3 = if enabled then Theme.Colors.CharcoalDark else Theme.Colors.CreamMuted
end

function Composer.new(options: any): any
	local self = setmetatable({}, Composer)
	self._mode = options.mode or "organic"
	self._onAction = options.onAction
	self._getBlockReason = options.getBlockReason
	self._selection = nil
	self._contextKey = nil
	self._state = nil
	self.Root = Composer.stack(options.parent, if self._mode == "organic" then "Page_Create" else "MissionComposer", self._mode == "organic")
	self._heading = Composer.label(self.Root, "Heading", if self._mode == "organic" then "Create a Buzzline post" else "Campaign post", 22)
	self._heading.LayoutOrder = -4
	self._context = Composer.label(self.Root, "Context", "Loading your next context...", 18, Theme.Colors.Amber)
	self._clue = Composer.label(self.Root, "Clue", "Waiting for confirmed progress.")
	self._device = Composer.label(self.Root, "ProductionDevice", "", 14, Theme.Colors.CreamMuted)
	self._choices = Composer.stack(self.Root, "TemplateChoices")
	self._buttons = {}
	for index = 1, 3 do
		local card = Composer.button(self._choices, `Template{index}`, "", function()
			if self._templateIds then
				self._selection = self._templateIds[index]
				self:_renderSelection()
			end
		end)
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.TextXAlignment = Enum.TextXAlignment.Left
		card.TextYAlignment = Enum.TextYAlignment.Top
		Theme.applyPadding(card, 14, 14, 14, 14)
		local minimum = Instance.new("UISizeConstraint")
		minimum.MinSize = Vector2.new(0, 76)
		minimum.Parent = card
		self._buttons[index] = card
	end
	self._preview = Composer.label(self.Root, "SelectedPreview", "Select a post before publishing.", 15, Theme.Colors.Sage)
	self._publish = Composer.button(self.Root, "Publish", "Publish organic post", function() self:Publish() end)
	self._notice = Composer.label(self.Root, "MutationStatus", "", 14, Theme.Colors.CreamMuted)
	self._pending = Composer.stack(self.Root, "PendingPost")
	self._pending.LayoutOrder = -3
	self._pendingTitle = Composer.label(self._pending, "PendingTitle", "", 18, Theme.Colors.Amber)
	self._pendingBody = Composer.label(self._pending, "PendingBody", "", 15)
	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.Size = UDim2.new(1, 0, 0, 4)
	track.BackgroundColor3 = Theme.Colors.CharcoalLight
	track.BorderSizePixel = 0
	track.Parent = self._pending
	self._progress = Instance.new("Frame")
	self._progress.Name = "ServerTimeProgress"
	self._progress.Size = UDim2.new(0, 0, 1, 0)
	self._progress.BackgroundColor3 = Theme.Colors.Sage
	self._progress.BorderSizePixel = 0
	self._progress.Parent = track
	self._result = Composer.label(self.Root, "ConfirmedResult", "", 15, Theme.Colors.Amber)
	self._result.LayoutOrder = -2
	self._refresh = Composer.button(self.Root, "RefreshProgress", "Refresh confirmed progress", function() self._onAction("GetSnapshot", {}) end)
	self._refresh.BackgroundColor3 = Theme.Colors.CharcoalLight
	self._refresh.TextColor3 = Theme.Colors.Cream
	return self
end

function Composer:_renderSelection()
	for index, button in ipairs(self._buttons) do
		local id = self._templateIds and self._templateIds[index]
		local copy = id and Presentation.Templates[id]
		local selected = id ~= nil and self._selection == id
		button:SetAttribute("Selected", selected)
		button.Text = if copy then `{if selected then "Selected · " else ""}{copy.title}\n{copy.body}` else "Context unavailable"
		button.BackgroundColor3 = if selected then Theme.Colors.CharcoalDark else Theme.Colors.CharcoalLight
		button.TextColor3 = Theme.Colors.Cream
		Theme.applyStroke(button, if selected then Theme.Colors.Amber else Theme.Colors.BorderLight, if selected then 2 else 1)
	end
	local copy = self._selection and Presentation.Templates[self._selection]
	self._preview.Text = if copy then `Your selected post:\n{copy.body}` else "Select a post before publishing."
	local reason = self._getBlockReason and self._getBlockReason() or nil
	if reason == nil and self._state and self._state.snapshot and self._state.snapshot.pendingPost then
		reason = "One post is already resolving. Both publishing modes share this slot."
	end
	local canPost = self._eligible and self._selection ~= nil and reason == nil
	Composer.setEnabled(self._publish, canPost == true)
	self._notice.Text = reason or (self._state and (self._state.activeError or self._state.mutationNotice)) or "Results and Cuan appear only after server confirmation."
end

function Composer:Publish()
	if not self._publish.Active or not self._selection or not self._eligible then return end
	local snap = self._state and self._state.snapshot
	if not snap then return end
	if self._mode == "mission" then
		local mission = snap.activeMission
		if not mission or not mission.runId then return end
		self._onAction("PublishPost", { runId = mission.runId, templateId = self._selection })
	else
		self._onAction("PublishOrganic", { templateId = self._selection })
	end
end

function Composer:Update(data: any)
	self._state = data
	local snap = data.snapshot
	self._pending.Visible = snap ~= nil and snap.pendingPost ~= nil
	local mission = snap and snap.activeMission
	local contextId = if self._mode == "mission" then mission and mission.contextId else snap and snap.nextOrganicContextId
	local templates = nil
	self._eligible = false
	if self._mode == "mission" then
		if mission then
			for _, def in ipairs(Catalog.Missions) do
				if def.missionId == mission.missionId then templates = def.templates end
			end
			self._eligible = mission.status == "accepted" and mission.postCount < 2
		end
	else
		for _, context in ipairs(Catalog.OrganicContexts) do
			if context.contextId == contextId then templates = context.templates end
		end
		self._eligible = templates ~= nil
	end
	local contextKey = `{contextId or ""}:{if self._mode == "mission" and mission then mission.runId else "organic"}`
	if contextKey ~= self._contextKey then
		self._contextKey = contextKey
		self._selection = nil
	end
	self._templateIds = templates
	local context = contextId and Presentation.Contexts[contextId]
	self._context.Text = if context then `{context.title}\nTrend: {context.trend} · Audience: {context.audience}` else "Waiting for an available context"
	self._clue.Text = if context then context.clue else "Open the campaign briefing to begin."
	local device = snap and snap.deviceId
	for _, def in ipairs(Catalog.Devices) do
		if def.id == device then
			self._device.Text = `{Presentation.Devices[device] or device} · Estimated reveal: {def.revealSeconds}s\nThe CRT opens BuzzerOS; your equipped device produces the post.`
		end
	end
	self._publish.Text = if self._mode == "mission" then "Publish campaign post" else "Publish organic post"
	self._choices.Visible = templates ~= nil and (self._mode ~= "mission" or self._eligible)
	self._preview.Visible = self._choices.Visible
	self._publish.Visible = self._choices.Visible
	local latest = nil
	if snap and snap.ownPosts then
		for _, post in ipairs(snap.ownPosts) do
			if latest == nil or post.publishedAt > latest.publishedAt then latest = post end
		end
	end
	self._result.Visible = snap ~= nil
	if latest then
		local likes = math.floor(math.floor(latest.finalImpact / 10) + (latest.publishedAt % 7))
		local replies = math.floor(likes / 4)
		local contribution = if latest.mode == "mission" then `\nCampaign contribution: {latest.finalImpact} impact. Bonus is claimed separately in Missions.` else "\nOrganic post only; campaign progress is unchanged."
		self._result.Text = `Latest confirmed post · {latest.finalImpact} impact\n+{latest.organicCuan} organic Cuan credited.\nEngagement display: {likes} likes · {replies} replies{contribution}`
	else
		self._result.Text = "No confirmed posts yet. Read the clue and choose your first post."
	end
	self:_renderSelection()
end

function Composer:Tick(serverNow: number)
	if self._lastTick and (serverNow >= self._lastTick and serverNow - self._lastTick < 0.2) then return end
	self._lastTick = serverNow
	local post = self._state and self._state.snapshot and self._state.snapshot.pendingPost
	self._pending.Visible = post ~= nil
	if not post then return end
	local remaining = math.max(0, post.settleAt - serverNow)
	self._pendingTitle.Text = if remaining > 0 then `Post resolving · {math.ceil(remaining)}s remaining` else "Awaiting server confirmation"
	local copy = Presentation.Templates[post.templateId]
	self._pendingBody.Text = `{if post.mode == "mission" then "Campaign-tagged" else "Organic"} · {if copy then copy.body else post.templateId}\n{if remaining > 0 then "Engagement is being resolved. You can browse Buzzline or close BuzzerOS." else "The reveal window has ended. Saving or network confirmation is still pending; no Cuan has been shown as credited."}`
	local duration = math.max(1, post.settleAt - post.publishedAt)
	self._progress.Size = UDim2.new(math.clamp((serverNow - post.publishedAt) / duration, 0, 1), 0, 1, 0)
end

function Composer:Destroy()
	self.Root:Destroy()
end

return Composer
