--!strict
local Presentation = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Presentation"))
local Theme = require(script.Parent:WaitForChild("Theme") :: any)

local Feed = {}
Feed.__index = Feed

export type FeedOptions = {
	parent: Instance,
	playerName: string,
	onNavigate: (string) -> (),
}

local POST_FIELDS = { "postId", "contextId", "templateId", "publishedAt", "finalImpact", "organicCuan", "mode" }

local function stack(parent: Instance, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
end

local function section(parent: Instance, name: string, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.Parent = parent
	stack(frame, Theme.Spacing.MD)
	return frame
end

local function text(parent: Instance, name: string, value: string, order: number, size: number?, color: Color3?, bold: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.LayoutOrder = order
	label.Text = value
	label.RichText = false
	label.TextWrapped = true
	label.TextSize = size or Theme.TextSizes.Body
	label.Font = if bold then Theme.Fonts.Bold else Theme.Fonts.Regular
	label.TextColor3 = color or Theme.Colors.Cream
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

local function initials(name: string?): string
	if not name or name == "" then return "?" end
	local result = ""
	for word in name:gmatch("%S+") do
		local endByte = utf8.offset(word, 2)
		result ..= word:sub(1, if endByte ~= nil then endByte - 1 else #word)
		if utf8.len(result) == 2 then
			break
		end
	end
	return if result ~= "" then result:upper() else "?"
end

local function card(parent: Instance, data: Presentation.FeedCard, order: number, playerName: string)
	local own = data.kind == "own"
	local frame = section(parent, data.cardId, order)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Theme.Colors.CharcoalLight
	Theme.applyCorner(frame, Theme.Radii.Medium)
	Theme.applyPadding(frame, Theme.Spacing.MD)

	local header = Instance.new("Frame")
	header.Name = "Attribution"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 40)
	header.AutomaticSize = Enum.AutomaticSize.Y
	header.LayoutOrder = 1
	header.Parent = frame

	local name = if own then (playerName or "You") else (data.npcName or "Authored NPC")
	local avatar = Instance.new("TextLabel")
	avatar.Name = "Initials"
	avatar.Size = UDim2.fromOffset(40, 40)
	avatar.BackgroundColor3 = Theme.Colors.CharcoalDark
	avatar.Text = initials(name)
	avatar.RichText = false
	avatar.TextSize = Theme.TextSizes.Body
	avatar.TextColor3 = Theme.Colors.Cream
	avatar.Font = Theme.Fonts.Bold
	avatar.Parent = header
	Theme.applyCorner(avatar, Theme.Radii.Small)

	local attribution = section(header, "Identity", 1)
	attribution.Position = UDim2.fromOffset(52, 0)
	attribution.Size = UDim2.new(1, -52, 0, 0)
	text(attribution, "Name", name, 1, Theme.TextSizes.Body, nil, true)
	text(attribution, "Handle", if own then "You / confirmed post" else `{data.npcHandle or ""} / authored NPC`, 2, Theme.TextSizes.Small, Theme.Colors.CreamMuted)

	local template = (Presentation.Templates :: any)[data.templateId]
	if own then
		text(frame, "Template", if template ~= nil then template.title else "Saved template unavailable", 2, Theme.TextSizes.Small, Theme.Colors.CreamMuted, true)
	end
	text(frame, "Body", if own then (if template ~= nil then template.body else "This confirmed post uses an unavailable authored template.") else data.body, 3)

	local context = (Presentation.Contexts :: any)[data.contextId]
	if context ~= nil then
		text(frame, "Context", `Trend: {context.trend}\nAudience: {context.audience}`, 4, Theme.TextSizes.Small, Theme.Colors.CreamMuted)
	end
	if not own and data.clueText ~= nil then
		text(frame, "PublicClue", `Public clue: {data.clueText}`, 5, Theme.TextSizes.Body, Theme.Colors.Amber)
	end
	if own then
		local mode = if data.mode == "mission" then "Mission post" else "Organic post"
		text(frame, "ConfirmedResult", `{mode}: {Theme.formatNumber(data.finalImpact or 0)} impact / +{Theme.formatNumber(data.organicCuan or 0)} Cuan confirmed`, 5, Theme.TextSizes.Body, Theme.Colors.Amber, true)
	end
	text(frame, "Engagement", `Simulated engagement: {Theme.formatNumber(data.likes)} likes / {Theme.formatNumber(data.replies)} replies`, 6, Theme.TextSizes.Small, Theme.Colors.CreamMuted)
	if not own then
		local replies = Presentation.repliesFor(data.contextId)
		if #replies > 0 then
			text(frame, "AuthoredReplies", `Authored replies: {table.concat(replies, " / ")}`, 7, Theme.TextSizes.Small, Theme.Colors.CreamMuted)
		end
	end
end

local function button(self: any, parent: Instance, name: string, title: string, activate: () -> ()): TextButton
	local control = Instance.new("TextButton")
	control.Name = name
	control.Size = UDim2.new(1, 0, 0, 48)
	control.BackgroundColor3 = Theme.Colors.CharcoalDark
	control.TextColor3 = Theme.Colors.Cream
	control.Text = title
	control.RichText = false
	control.TextWrapped = true
	control.TextSize = Theme.TextSizes.Body
	control.Font = Theme.Fonts.Medium
	control.AutoButtonColor = true
	control.Selectable = true
	control.Parent = parent
	Theme.applyCorner(control, Theme.Radii.Small)
	Theme.applyPadding(control, Theme.Spacing.XS, Theme.Spacing.SM)
	local stroke = Theme.applyStroke(control, Theme.Colors.CreamMuted, 1)
	table.insert(self._connections, control.SelectionGained:Connect(function()
		stroke.Color = Theme.Colors.Amber
		stroke.Thickness = 3
	end))
	table.insert(self._connections, control.SelectionLost:Connect(function()
		stroke.Color = Theme.Colors.CreamMuted
		stroke.Thickness = 1
	end))
	table.insert(self._connections, control.Activated:Connect(activate))
	return control
end

function Feed.new(options: FeedOptions): any
	local self = setmetatable({}, Feed)
	self._connections = {}
	self._playerName = options.playerName
	self._postCache = {}
	self._initialized = false
	self._destroyed = false

	local root = Instance.new("Frame")
	root.Name = "BuzzlineFeed"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = options.parent
	self.Root = root

	-- Keep both sections reachable without scrolling past ten own summaries.
	local tabs = Instance.new("Frame")
	tabs.Name = "SectionNavigation"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, -8, 0, 48)
	tabs.Position = UDim2.fromOffset(4, 4)
	tabs.Parent = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "FeedScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 60)
	scroll.Size = UDim2.new(1, 0, 1, -60)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.Colors.CreamMuted
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Active = true
	scroll.Selectable = true
	scroll.Parent = root
	Theme.applyPadding(scroll, 4, 14, Theme.Spacing.XL, 4)
	stack(scroll, Theme.Spacing.XL)
	self._scroll = scroll
	local scrollFocus = Theme.applyStroke(scroll, Theme.Colors.Amber, 2, 1)
	table.insert(self._connections, scroll.SelectionGained:Connect(function()
		scrollFocus.Transparency = 0
	end))
	table.insert(self._connections, scroll.SelectionLost:Connect(function()
		scrollFocus.Transparency = 1
	end))

	local intro = section(scroll, "Introduction", 1)
	text(intro, "Title", "Buzzline", 1, Theme.TextSizes.Header, nil, true)
	text(intro, "Disclosure", "A fictional, authored community. NPC names, posts, replies, and engagement are game content, not real user activity.", 2, Theme.TextSizes.Body, Theme.Colors.CreamMuted)
	text(intro, "Guide", "Read the public trend and audience clues, then choose an authored template in Create.", 3)
	button(self, intro, "CreatePost", "Create a post", function()
		options.onNavigate("Create")
	end).LayoutOrder = 4

	local community = section(scroll, "AuthoredCommunity", 2)
	text(community, "Heading", "Community clues / 6 authored posts", 1, Theme.TextSizes.Subtitle, nil, true)
	for index, data in ipairs(Presentation.authoredCards()) do
		card(community, data, index + 1, self._playerName)
	end

	local own = section(scroll, "YourPosts", 3)
	self._ownHeading = text(own, "Heading", "Your confirmed posts / 0", 1, Theme.TextSizes.Subtitle, nil, true)
	text(own, "Explanation", "Up to 10 saved results. Cuan below is the confirmed post payout, not your current wallet or a mission bonus.", 2, Theme.TextSizes.Small, Theme.Colors.CreamMuted)
	self._empty = text(own, "EmptyState", "Loading confirmed post history...", 3, Theme.TextSizes.Body, Theme.Colors.CreamMuted)
	self._ownCards = section(own, "ConfirmedCards", 4)

	local function jump(target: GuiObject)
		local y = target.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		local maxY = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
		scroll.CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY))
	end
	local communityButton = button(self, tabs, "CommunityClues", "Community clues", function()
		jump(community)
	end)
	communityButton.Size = UDim2.new(0.5, -4, 1, 0)
	local ownButton = button(self, tabs, "YourPosts", "Your posts", function()
		jump(own)
	end)
	ownButton.Position = UDim2.new(0.5, 4, 0, 0)
	ownButton.Size = UDim2.new(0.5, -4, 1, 0)
	return self
end

function Feed:Update(stateData: any)
	if self._destroyed then
		return
	end
	local snapshot = stateData.snapshot
	local posts = if snapshot ~= nil then snapshot.ownPosts else nil
	local count = if posts ~= nil then math.min(#posts, Presentation.MAX_OWN_CARDS) else 0
	local emptyText = if snapshot == nil
		then (if stateData.activeError ~= nil then "Confirmed post history is unavailable. Use Refresh progress to reconnect." else "Loading confirmed post history...")
		elseif snapshot.pendingPost ~= nil then "Your post is resolving. Its result appears here after server confirmation."
		else "No confirmed posts yet. Choose Create a post to publish your first authored template."
	if self._empty.Text ~= emptyText then
		self._empty.Text = emptyText
	end
	self._empty.Visible = count == 0

	-- Compare only rendered summary fields; snapshot revisions and countdown ticks
	-- do not rebuild the feed, reset its scroll, or replace focused navigation.
	local changed = not self._initialized or count ~= #self._postCache
	if not changed and posts ~= nil then
		for index = 1, count do
			for _, field in ipairs(POST_FIELDS) do
				if posts[index][field] ~= self._postCache[index][field] then
					changed = true
					break
				end
			end
			if changed then
				break
			end
		end
	end
	if not changed then
		return
	end
	self._initialized = true
	table.clear(self._postCache)
	for _, child in ipairs(self._ownCards:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, data in ipairs(Presentation.ownCards(snapshot)) do
		card(self._ownCards, data, index, self._playerName)
		local cached: { [string]: any } = {}
		for _, field in ipairs(POST_FIELDS) do
			cached[field] = posts[index][field]
		end
		table.insert(self._postCache, cached)
	end
	self._ownHeading.Text = `Your confirmed posts / {count}`
end

function Feed:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.Root:Destroy()
end

return Feed
