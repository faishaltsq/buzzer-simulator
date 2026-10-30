--!strict
-- Buzzer Simulator — Desktop (BS-07)
-- Complete responsive BuzzerOS dashboard shell and home screen.
-- Contract sources: docs/03, docs/05.

local Theme = require(script.Parent:WaitForChild("Theme") :: any)
local Desktop = {}
Desktop.__index = Desktop

export type DesktopOptions = {
	parent: Instance,
	playerName: string,
	onClose: () -> (),
	onTabSelected: (string) -> (),
}

local TABS = {
	{ id = "Home", label = "Home", desc = "Overview" },
	{ id = "Feed", label = "Buzzline", desc = "Trends" },
	{ id = "Create", label = "Create", desc = "Post" },
	{ id = "Missions", label = "Missions", desc = "Bounties" },
	{ id = "Upgrades", label = "Upgrades", desc = "Hardware" },
	{ id = "Workers", label = "Workers", desc = "Staff" },
}

function Desktop.new(options: DesktopOptions): any
	local self = setmetatable({}, Desktop)
	self._parent = options.parent
	self._playerName = options.playerName
	self._onClose = options.onClose
	self._onTabSelected = options.onTabSelected
	self._currentTab = "Home"
	self._isMobile = false
	self._moreMenuOpen = false
	self._connections = {}
	self._tabButtons = {} :: { [string]: GuiButton }
	self._tabIndicator = nil :: Frame?
	self._contentContainers = {} :: { [string]: GuiObject }
	self._metricBoxes = {}

	-- ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuzzerOSDesktop"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Enabled = false
	screenGui.Parent = self._parent
	self._gui = screenGui

	-- Dim backdrop behind the window
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Parent = screenGui
	self._backdrop = backdrop

	-- Main Window Container
	local window = Instance.new("Frame")
	window.Name = "BuzzerOSWindow"
	window.BackgroundColor3 = Theme.Colors.Charcoal
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.new(0.5, 0, 0.5, 0)
	window.Size = UDim2.new(0.9, 0, 0.88, 0)
	window.ClipsDescendants = true
	window.Parent = screenGui
	self._window = window

	Theme.applyCorner(window, Theme.Radii.Large)
	Theme.applyStroke(window, Theme.Colors.Border, 1)

	-- Size Constraint for responsive scaling
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(280, 240)
	sizeConstraint.MaxSize = Vector2.new(1100, 720)
	sizeConstraint.Parent = window
	self._sizeConstraint = sizeConstraint

	-- Window Header Bar
	local header = Instance.new("Frame")
	header.Name = "WindowHeader"
	header.BackgroundColor3 = Theme.Colors.CharcoalDark
	header.Size = UDim2.new(1, 0, 0, 48)
	header.Parent = window
	Theme.applyPadding(header, 0, 12, 0, 16)

	-- Header Brand
	local brand = Instance.new("TextLabel")
	brand.Name = "Brand"
	brand.BackgroundTransparency = 1
	brand.Size = UDim2.new(0, 200, 1, 0)
	brand.Font = Theme.Fonts.Black
	brand.Text = "BuzzerOS 1.0"
	brand.TextColor3 = Theme.Colors.Amber
	brand.TextSize = Theme.TextSizes.Body
	brand.TextXAlignment = Enum.TextXAlignment.Left
	brand.Parent = header

	-- Header Clock / Status
	local headerClock = Instance.new("TextLabel")
	headerClock.Name = "Clock"
	headerClock.BackgroundTransparency = 1
	headerClock.Size = UDim2.new(0, 180, 1, 0)
	headerClock.Position = UDim2.new(0.5, -90, 0, 0)
	headerClock.Font = Theme.Fonts.Medium
	headerClock.Text = "Cozy Bedroom Studio"
	headerClock.TextColor3 = Theme.Colors.CreamMuted
	headerClock.TextSize = Theme.TextSizes.Small
	headerClock.TextXAlignment = Enum.TextXAlignment.Center
	headerClock.Parent = header
	self._headerClock = headerClock

	-- Close Button (Touch target >= 44x44)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.BackgroundColor3 = Theme.Colors.CharcoalLight
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.new(0, 72, 0, 44)
	closeBtn.Font = Theme.Fonts.Bold
	closeBtn.Text = "Close"
	closeBtn.TextColor3 = Theme.Colors.Cream
	closeBtn.TextSize = Theme.TextSizes.Small
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = header
	Theme.applyCorner(closeBtn, Theme.Radii.Small)
	Theme.applyStroke(closeBtn, Theme.Colors.Border, 1)

	closeBtn.MouseEnter:Connect(function()
		closeBtn.BackgroundColor3 = Theme.Colors.Coral
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = Theme.Colors.CharcoalLight
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if self._onClose ~= nil then
			self._onClose()
		end
	end)
	self._closeBtn = closeBtn

	-- Desktop Body Container (Holds Navigation Rail and Content)
	local body = Instance.new("Frame")
	body.Name = "WindowBody"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -48)
	body.Position = UDim2.new(0, 0, 0, 48)
	body.Parent = window
	self._body = body

	-- Desktop Navigation Rail (Left side)
	local navRail = Instance.new("Frame")
	navRail.Name = "NavRail"
	navRail.BackgroundColor3 = Theme.Colors.CharcoalDark
	navRail.Size = UDim2.new(0, 180, 1, 0)
	navRail.Parent = body
	self._navRail = navRail

	local navPadding = Theme.applyPadding(navRail, 16, 8, 16, 8)

	local navLayout = Instance.new("UIListLayout")
	navLayout.FillDirection = Enum.FillDirection.Vertical
	navLayout.Padding = UDim.new(0, 6)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Parent = navRail

	-- Main Content Region
	local contentArea = Instance.new("Frame")
	contentArea.Name = "ContentArea"
	contentArea.BackgroundTransparency = 1
	contentArea.Size = UDim2.new(1, -180, 1, 0)
	contentArea.Position = UDim2.new(0, 180, 0, 0)
	contentArea.ClipsDescendants = true
	contentArea.Parent = body
	self._contentArea = contentArea

	-- Mobile Bottom Bar
	local mobileNav = Instance.new("Frame")
	mobileNav.Name = "MobileNav"
	mobileNav.BackgroundColor3 = Theme.Colors.CharcoalDark
	mobileNav.Size = UDim2.new(1, 0, 0, 56)
	mobileNav.Position = UDim2.new(0, 0, 1, -56)
	mobileNav.Visible = false
	mobileNav.Parent = window
	self._mobileNav = mobileNav

	local mobileNavLayout = Instance.new("UIListLayout")
	mobileNavLayout.FillDirection = Enum.FillDirection.Horizontal
	mobileNavLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	mobileNavLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	mobileNavLayout.Padding = UDim.new(0, 4)
	mobileNavLayout.Parent = mobileNav

	-- Mobile "More" Drawer Menu
	local moreDrawer = Instance.new("Frame")
	moreDrawer.Name = "MoreDrawer"
	moreDrawer.BackgroundColor3 = Theme.Colors.CharcoalDark
	moreDrawer.Size = UDim2.new(1, 0, 0, 160)
	moreDrawer.Position = UDim2.new(0, 0, 1, 0) -- Hidden below
	moreDrawer.Visible = false
	moreDrawer.ZIndex = 5
	moreDrawer.Parent = window
	self._moreDrawer = moreDrawer
	Theme.applyCorner(moreDrawer, Theme.Radii.Large)
	Theme.applyStroke(moreDrawer, Theme.Colors.BorderLight, 1)

	local moreDrawerLayout = Instance.new("UIListLayout")
	moreDrawerLayout.FillDirection = Enum.FillDirection.Vertical
	moreDrawerLayout.Padding = UDim.new(0, 6)
	moreDrawerLayout.Parent = moreDrawer
	Theme.applyPadding(moreDrawer, 12, 16, 12, 16)

	-- Build tab buttons for both desktop nav and mobile nav
	self:_buildNavigation()

	-- Build content pages
	self:_buildPages()

	-- Setup responsive layout monitoring
	local function updateLayout()
		local vp = window.AbsoluteSize
		local isNarrow = vp.X < 640

		if isNarrow ~= self._isMobile then
			self._isMobile = isNarrow
			self:_applyResponsiveMode(isNarrow)
		end
	end

	table.insert(self._connections, window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout))
	updateLayout()

	return self
end

function Desktop:_buildNavigation()
	-- 1. Desktop Nav Rail Buttons
	for i, tab in ipairs(TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = `Nav_{tab.id}`
		btn.BackgroundColor3 = if tab.id == self._currentTab then Theme.Colors.CharcoalLight else Theme.Colors.CharcoalDark
		btn.Size = UDim2.new(1, 0, 0, 40)
		btn.LayoutOrder = i
		btn.Font = Theme.Fonts.Medium
		btn.Text = `  {tab.label}`
		btn.TextColor3 = if tab.id == self._currentTab then Theme.Colors.Cream else Theme.Colors.CreamMuted
		btn.TextSize = Theme.TextSizes.Body
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
		btn.Parent = self._navRail
		Theme.applyCorner(btn, Theme.Radii.Medium)

		btn.MouseEnter:Connect(function()
			if self._currentTab ~= tab.id then
				btn.BackgroundColor3 = Theme.Colors.Charcoal
			end
		end)
		btn.MouseLeave:Connect(function()
			if self._currentTab ~= tab.id then
				btn.BackgroundColor3 = Theme.Colors.CharcoalDark
			end
		end)
		btn.MouseButton1Click:Connect(function()
			self:SelectTab(tab.id)
		end)

		self._tabButtons[tab.id] = btn
	end

	-- 2. Mobile Bottom Bar Buttons (Top 3 + More)
	local mobileItems = {
		{ id = "Home", label = "Home" },
		{ id = "Feed", label = "Feed" },
		{ id = "Create", label = "Create" },
		{ id = "More", label = "More" },
	}

	for i, item in ipairs(mobileItems) do
		local mBtn = Instance.new("TextButton")
		mBtn.Name = `MobileNav_{item.id}`
		mBtn.BackgroundColor3 = Theme.Colors.CharcoalDark
		mBtn.Size = UDim2.new(0.24, 0, 1, -8)
		mBtn.Font = Theme.Fonts.Bold
		mBtn.Text = item.label
		mBtn.TextColor3 = Theme.Colors.CreamMuted
		mBtn.TextSize = Theme.TextSizes.Small
		mBtn.AutoButtonColor = false
		mBtn.Parent = self._mobileNav
		Theme.applyCorner(mBtn, Theme.Radii.Small)

		mBtn.MouseButton1Click:Connect(function()
			if item.id == "More" then
				self:ToggleMoreMenu()
			else
				self:SelectTab(item.id)
				self:CloseMoreMenu()
			end
		end)
	end

	-- 3. Drawer buttons for remaining items
	local drawerItems = {
		{ id = "Missions", label = "Missions" },
		{ id = "Upgrades", label = "Upgrades" },
		{ id = "Workers", label = "Workers" },
	}
	for _, dItem in ipairs(drawerItems) do
		local dBtn = Instance.new("TextButton")
		dBtn.Name = `DrawerNav_{dItem.id}`
		dBtn.BackgroundColor3 = Theme.Colors.CharcoalLight
		dBtn.Size = UDim2.new(1, 0, 0, 38)
		dBtn.Font = Theme.Fonts.Medium
		dBtn.Text = `  {dItem.label}`
		dBtn.TextColor3 = Theme.Colors.Cream
		dBtn.TextSize = Theme.TextSizes.Body
		dBtn.TextXAlignment = Enum.TextXAlignment.Left
		dBtn.AutoButtonColor = false
		dBtn.Parent = self._moreDrawer
		Theme.applyCorner(dBtn, Theme.Radii.Small)

		dBtn.MouseButton1Click:Connect(function()
			self:SelectTab(dItem.id)
			self:CloseMoreMenu()
		end)
	end
end

function Desktop:_applyResponsiveMode(isNarrow: boolean)
	if isNarrow then
		-- Mobile view
		self._navRail.Visible = false
		self._contentArea.Size = UDim2.new(1, 0, 1, -104)
		self._contentArea.Position = UDim2.new(0, 0, 0, 48)
		self._mobileNav.Visible = true
	else
		-- Desktop view
		self._navRail.Visible = true
		self._contentArea.Size = UDim2.new(1, -180, 1, -48)
		self._contentArea.Position = UDim2.new(0, 180, 0, 0)
		self._mobileNav.Visible = false
		self:CloseMoreMenu()
	end

	-- Update Home finance row responsive layout
	if self._financeLayout ~= nil and self._financeRow ~= nil and self._metricBoxes ~= nil then
		if isNarrow then
			self._financeLayout.FillDirection = Enum.FillDirection.Vertical
			self._financeRow.Size = UDim2.new(1, 0, 0, 172)
			for _, mBox in ipairs(self._metricBoxes) do
				mBox.box.Size = UDim2.new(1, 0, 0, 50)
				mBox.tag.Size = UDim2.new(0.55, 0, 1, 0)
				mBox.tag.Position = UDim2.new(0, 0, 0, 0)
				mBox.tag.TextSize = Theme.TextSizes.Small
				mBox.tag.TextYAlignment = Enum.TextYAlignment.Center
				mBox.val.Size = UDim2.new(0.45, 0, 1, 0)
				mBox.val.Position = UDim2.new(0.55, 0, 0, 0)
				mBox.val.TextSize = Theme.TextSizes.Body
				mBox.val.TextXAlignment = Enum.TextXAlignment.Right
				mBox.val.TextYAlignment = Enum.TextYAlignment.Center
			end
		else
			self._financeLayout.FillDirection = Enum.FillDirection.Horizontal
			self._financeRow.Size = UDim2.new(1, 0, 0, 84)
			for _, mBox in ipairs(self._metricBoxes) do
				mBox.box.Size = UDim2.new(0.32, -8, 1, 0)
				mBox.tag.Size = UDim2.new(1, 0, 0, 16)
				mBox.tag.Position = UDim2.new(0, 0, 0, 0)
				mBox.tag.TextSize = Theme.TextSizes.Tiny
				mBox.tag.TextYAlignment = Enum.TextYAlignment.Top
				mBox.val.Size = UDim2.new(1, 0, 1, -18)
				mBox.val.Position = UDim2.new(0, 0, 0, 18)
				mBox.val.TextSize = Theme.TextSizes.Title
				mBox.val.TextXAlignment = Enum.TextXAlignment.Left
				mBox.val.TextYAlignment = Enum.TextYAlignment.Center
			end
		end
	end
end

function Desktop:ToggleMoreMenu()
	if self._moreMenuOpen then
		self:CloseMoreMenu()
	else
		self._moreMenuOpen = true
		self._moreDrawer.Visible = true
		Theme.tween(self._moreDrawer, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 1, -216),
		})
	end
end

function Desktop:CloseMoreMenu()
	if not self._moreMenuOpen then
		return
	end
	self._moreMenuOpen = false
	Theme.tween(self._moreDrawer, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0, 0, 1, 0),
	})
	task.delay(0.2, function()
		if not self._moreMenuOpen then
			self._moreDrawer.Visible = false
		end
	end)
end

function Desktop:SelectTab(tabId: string)
	self._currentTab = tabId
	if self._onTabSelected ~= nil then
		self._onTabSelected(tabId)
	end
	-- Update nav button styles
	for id, btn in pairs(self._tabButtons) do
		if id == tabId then
			btn.BackgroundColor3 = Theme.Colors.CharcoalLight
			btn.TextColor3 = Theme.Colors.Cream
		else
			btn.BackgroundColor3 = Theme.Colors.CharcoalDark
			btn.TextColor3 = Theme.Colors.CreamMuted
		end
	end

	-- Switch active content page
	for id, page in pairs(self._contentContainers) do
		page.Visible = (id == tabId)
	end
end

-- ==================== PAGE BUILDERS ====================

function Desktop:_buildPages()
	-- 1. Home Page (Rich confirmed profile overview)
	self._contentContainers["Home"] = self:_createHomePage()

	-- 2. Feed Page (Informational placeholder)
	self._contentContainers["Feed"] = self:_createPlaceholderPage(
		"Buzzline Feed",
		"Browse authored NPC cards and community posts. Research viral audience affinities and trends.",
		"Planned for Milestone BS-08"
	)

	-- 3. Create Page (Informational placeholder)
	self._contentContainers["Create"] = self:_createPlaceholderPage(
		"Post Composer",
		"Craft high-engagement posts. Organic yield and reveal times are computed from your equipped phone.",
		"Planned for Milestone BS-08"
	)

	-- 4. Missions Page (Informational placeholder)
	self._contentContainers["Missions"] = self:_createPlaceholderPage(
		"Campaign Missions",
		"Accept commercial contracts from local brands and claim guaranteed Cuan bonuses upon goal delivery.",
		"Planned for Milestone BS-08"
	)

	-- 5. Upgrades Page (Informational placeholder)
	self._contentContainers["Upgrades"] = self:_createPlaceholderPage(
		"Hardware & Studio Upgrades",
		"Upgrade from Cheap Phone to Fast Phone, install PC Rumah, and expand your home studio desks.",
		"Planned for Milestone BS-09"
	)

	-- 6. Workers Page (Informational placeholder)
	self._contentContainers["Workers"] = self:_createPlaceholderPage(
		"Home Studio Staffing",
		"Recruit trainee assistants to generate automated, continuous online Cuan.",
		"Planned for Milestone M1"
	)

	-- Show Home by default
	self:SelectTab("Home")
end

function Desktop:_createHomePage(): GuiObject
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Page_Home"
	scroll.BackgroundTransparency = 1
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 680)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.Colors.Border
	scroll.Parent = self._contentArea

	Theme.applyPadding(scroll, 16, 20, 24, 20)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	-- 1. Welcome Card
	local welcome = Instance.new("Frame")
	welcome.Name = "WelcomeCard"
	welcome.BackgroundColor3 = Theme.Colors.CharcoalDark
	welcome.Size = UDim2.new(1, 0, 0, 64)
	welcome.LayoutOrder = 1
	welcome.Parent = scroll
	Theme.applyCorner(welcome, Theme.Radii.Medium)
	Theme.applyStroke(welcome, Theme.Colors.Border, 1)
	Theme.applyPadding(welcome, 10, 16, 10, 16)

	local wTitle = Instance.new("TextLabel")
	wTitle.Name = "Title"
	wTitle.BackgroundTransparency = 1
	wTitle.Size = UDim2.new(1, 0, 0, 22)
	wTitle.Font = Theme.Fonts.Black
	wTitle.Text = `Welcome to BuzzerOS, @{self._playerName}`
	wTitle.TextColor3 = Theme.Colors.Cream
	wTitle.TextSize = Theme.TextSizes.Subtitle
	wTitle.TextXAlignment = Enum.TextXAlignment.Left
	wTitle.Parent = welcome

	local wSub = Instance.new("TextLabel")
	wSub.Name = "Subtitle"
	wSub.BackgroundTransparency = 1
	wSub.Size = UDim2.new(1, 0, 0, 18)
	wSub.Position = UDim2.new(0, 0, 0, 24)
	wSub.Font = Theme.Fonts.Regular
	wSub.Text = "Authoritative Bedroom Creator Workstation • Shipped V0 Prototype"
	wSub.TextColor3 = Theme.Colors.Sage
	wSub.TextSize = Theme.TextSizes.Small
	wSub.TextXAlignment = Enum.TextXAlignment.Left
	wSub.Parent = welcome

	-- 2. Financial Overview Row
	local financeRow = Instance.new("Frame")
	financeRow.Name = "FinanceRow"
	financeRow.BackgroundTransparency = 1
	financeRow.Size = UDim2.new(1, 0, 0, 84)
	financeRow.LayoutOrder = 2
	financeRow.Parent = scroll
	self._financeRow = financeRow

	local fLayout = Instance.new("UIListLayout")
	fLayout.FillDirection = Enum.FillDirection.Horizontal
	fLayout.Padding = UDim.new(0, 10)
	fLayout.Parent = financeRow
	self._financeLayout = fLayout
	-- Box 1: Spendable Cuan
	local b1 = self:_createMetricBox(financeRow, "CONFIRMED SPENDABLE", "0 Cuan", Theme.Colors.Amber, 0.32)
	self._homeCuanVal = b1

	-- Box 2: Pending Worker Carry
	local b2 = self:_createMetricBox(financeRow, "UNBANKED WORKER CARRY", "0 Cuan", Theme.Colors.CreamMuted, 0.32)
	self._homePendingVal = b2

	-- Box 3: Online Accrual Rate
	local b3 = self:_createMetricBox(financeRow, "ONLINE REVENUE RATE", "+0.0 Cuan/s", Theme.Colors.Lime, 0.32)
	self._homeRateVal = b3

	-- 3. Hardware & Production Card
	local deviceCard = Instance.new("Frame")
	deviceCard.Name = "DeviceCard"
	deviceCard.BackgroundColor3 = Theme.Colors.CharcoalDark
	deviceCard.Size = UDim2.new(1, 0, 0, 100)
	deviceCard.LayoutOrder = 3
	deviceCard.Parent = scroll
	Theme.applyCorner(deviceCard, Theme.Radii.Medium)
	Theme.applyStroke(deviceCard, Theme.Colors.Border, 1)
	Theme.applyPadding(deviceCard, 12, 16, 12, 16)

	local dTag = Instance.new("TextLabel")
	dTag.Name = "Tag"
	dTag.BackgroundTransparency = 1
	dTag.Size = UDim2.new(1, 0, 0, 14)
	dTag.Font = Theme.Fonts.Bold
	dTag.Text = "EQUIPPED PRODUCTION HARDWARE"
	dTag.TextColor3 = Theme.Colors.Amber
	dTag.TextSize = Theme.TextSizes.Tiny
	dTag.TextXAlignment = Enum.TextXAlignment.Left
	dTag.Parent = deviceCard

	local dName = Instance.new("TextLabel")
	dName.Name = "DeviceName"
	dName.BackgroundTransparency = 1
	dName.Size = UDim2.new(1, 0, 0, 22)
	dName.Position = UDim2.new(0, 0, 0, 18)
	dName.Font = Theme.Fonts.Black
	dName.Text = "Cheap Phone (Starter)"
	dName.TextColor3 = Theme.Colors.Cream
	dName.TextSize = Theme.TextSizes.Subtitle
	dName.TextXAlignment = Enum.TextXAlignment.Left
	dName.Parent = deviceCard
	self._homeDeviceName = dName

	local dNote = Instance.new("TextLabel")
	dNote.Name = "DeviceNote"
	dNote.BackgroundTransparency = 1
	dNote.Size = UDim2.new(1, 0, 0, 36)
	dNote.Position = UDim2.new(0, 0, 0, 42)
	dNote.Font = Theme.Fonts.Regular
	dNote.Text = "This phone at PhoneSlot drives your post yield (1.0x). The CRT is a dashboard terminal only."
	dNote.TextColor3 = Theme.Colors.CreamMuted
	dNote.TextSize = Theme.TextSizes.Small
	dNote.TextXAlignment = Enum.TextXAlignment.Left
	dNote.TextWrapped = true
	dNote.Parent = deviceCard
	self._homeDeviceNote = dNote

	-- 4. Active Activity Summary (Mission & Pending Post)
	local activityCard = Instance.new("Frame")
	activityCard.Name = "ActivityCard"
	activityCard.BackgroundColor3 = Theme.Colors.CharcoalDark
	activityCard.Size = UDim2.new(1, 0, 0, 110)
	activityCard.LayoutOrder = 4
	activityCard.Parent = scroll
	Theme.applyCorner(activityCard, Theme.Radii.Medium)
	Theme.applyStroke(activityCard, Theme.Colors.Border, 1)
	Theme.applyPadding(activityCard, 12, 16, 12, 16)

	local actTag = Instance.new("TextLabel")
	actTag.Name = "Tag"
	actTag.BackgroundTransparency = 1
	actTag.Size = UDim2.new(1, 0, 0, 14)
	actTag.Font = Theme.Fonts.Bold
	actTag.Text = "ACTIVE OPERATIONS"
	actTag.TextColor3 = Theme.Colors.Amber
	actTag.TextSize = Theme.TextSizes.Tiny
	actTag.TextXAlignment = Enum.TextXAlignment.Left
	actTag.Parent = activityCard

	local postSummary = Instance.new("TextLabel")
	postSummary.Name = "PostSummary"
	postSummary.BackgroundTransparency = 1
	postSummary.Size = UDim2.new(1, 0, 0, 20)
	postSummary.Position = UDim2.new(0, 0, 0, 20)
	postSummary.Font = Theme.Fonts.Medium
	postSummary.Text = "Pending Post: None"
	postSummary.TextColor3 = Theme.Colors.Cream
	postSummary.TextSize = Theme.TextSizes.Small
	postSummary.TextXAlignment = Enum.TextXAlignment.Left
	postSummary.Parent = activityCard
	self._homePostSummary = postSummary

	local missionSummary = Instance.new("TextLabel")
	missionSummary.Name = "MissionSummary"
	missionSummary.BackgroundTransparency = 1
	missionSummary.Size = UDim2.new(1, 0, 0, 20)
	missionSummary.Position = UDim2.new(0, 0, 0, 44)
	missionSummary.Font = Theme.Fonts.Medium
	missionSummary.Text = "Active Mission: None (Ready for new campaign)"
	missionSummary.TextColor3 = Theme.Colors.Cream
	missionSummary.TextSize = Theme.TextSizes.Small
	missionSummary.TextXAlignment = Enum.TextXAlignment.Left
	missionSummary.Parent = activityCard
	self._homeMissionSummary = missionSummary

	local progressTip = Instance.new("TextLabel")
	progressTip.Name = "ProgressTip"
	progressTip.BackgroundTransparency = 1
	progressTip.Size = UDim2.new(1, 0, 0, 18)
	progressTip.Position = UDim2.new(0, 0, 0, 72)
	progressTip.Font = Theme.Fonts.Regular
	progressTip.Text = "Next step: Post creation and campaign missions unlock in BS-08."
	progressTip.TextColor3 = Theme.Colors.Sage
	progressTip.TextSize = Theme.TextSizes.Tiny
	progressTip.TextXAlignment = Enum.TextXAlignment.Left
	progressTip.Parent = activityCard
	self._homeProgressTip = progressTip

	-- 5. Next Upgrade Preview Card
	local upgradeCard = Instance.new("Frame")
	upgradeCard.Name = "NextUpgradeCard"
	upgradeCard.BackgroundColor3 = Theme.Colors.CharcoalDark
	upgradeCard.Size = UDim2.new(1, 0, 0, 74)
	upgradeCard.LayoutOrder = 5
	upgradeCard.Parent = scroll
	Theme.applyCorner(upgradeCard, Theme.Radii.Medium)
	Theme.applyStroke(upgradeCard, Theme.Colors.Border, 1)
	Theme.applyPadding(upgradeCard, 10, 16, 10, 16)

	local uTag = Instance.new("TextLabel")
	uTag.Name = "Tag"
	uTag.BackgroundTransparency = 1
	uTag.Size = UDim2.new(1, 0, 0, 14)
	uTag.Font = Theme.Fonts.Bold
	uTag.Text = "NEXT HARDWARE GOAL"
	uTag.TextColor3 = Theme.Colors.Amber
	uTag.TextSize = Theme.TextSizes.Tiny
	uTag.TextXAlignment = Enum.TextXAlignment.Left
	uTag.Parent = upgradeCard

	local uDesc = Instance.new("TextLabel")
	uDesc.Name = "Desc"
	uDesc.BackgroundTransparency = 1
	uDesc.Size = UDim2.new(1, 0, 0, 36)
	uDesc.Position = UDim2.new(0, 0, 0, 18)
	uDesc.Font = Theme.Fonts.Medium
	uDesc.Text = "PhoneFast (50 Cuan) — Boosts strong organic payout from 15 to 24 Cuan per post."
	uDesc.TextColor3 = Theme.Colors.Cream
	uDesc.TextSize = Theme.TextSizes.Small
	uDesc.TextXAlignment = Enum.TextXAlignment.Left
	uDesc.TextWrapped = true
	uDesc.Parent = upgradeCard
	self._homeUpgradeDesc = uDesc

	return scroll
end

function Desktop:_createMetricBox(parent: Instance, tag: string, value: string, valColor: Color3, widthFraction: number): TextLabel
	local box = Instance.new("Frame")
	box.Name = `Box_{tag}`
	box.BackgroundColor3 = Theme.Colors.CharcoalDark
	box.Size = UDim2.new(widthFraction, -8, 1, 0)
	box.Parent = parent
	Theme.applyCorner(box, Theme.Radii.Medium)
	Theme.applyStroke(box, Theme.Colors.Border, 1)
	Theme.applyPadding(box, 10, 12, 10, 12)

	local tLabel = Instance.new("TextLabel")
	tLabel.Name = "Tag"
	tLabel.BackgroundTransparency = 1
	tLabel.Size = UDim2.new(1, 0, 0, 16)
	tLabel.Font = Theme.Fonts.Bold
	tLabel.Text = tag
	tLabel.TextColor3 = Theme.Colors.CreamMuted
	tLabel.TextSize = Theme.TextSizes.Tiny
	tLabel.TextXAlignment = Enum.TextXAlignment.Left
	tLabel.TextWrapped = true
	tLabel.Parent = box

	local tagSizeConstraint = Instance.new("UITextSizeConstraint")
	tagSizeConstraint.MinTextSize = 9
	tagSizeConstraint.MaxTextSize = 13
	tagSizeConstraint.Parent = tLabel

	local vLabel = Instance.new("TextLabel")
	vLabel.Name = "Val"
	vLabel.BackgroundTransparency = 1
	vLabel.Size = UDim2.new(1, 0, 1, -18)
	vLabel.Position = UDim2.new(0, 0, 0, 18)
	vLabel.Font = Theme.Fonts.Black
	vLabel.Text = value
	vLabel.TextColor3 = valColor
	vLabel.TextSize = Theme.TextSizes.Title
	vLabel.TextXAlignment = Enum.TextXAlignment.Left
	vLabel.Parent = box

	local textSizeConstraint = Instance.new("UITextSizeConstraint")
	textSizeConstraint.MinTextSize = 12
	textSizeConstraint.MaxTextSize = 22
	textSizeConstraint.Parent = vLabel

	if self._metricBoxes ~= nil then
		table.insert(self._metricBoxes, {
			box = box,
			tag = tLabel,
			val = vLabel,
		})
	end

	return vLabel
end

function Desktop:_createPlaceholderPage(title: string, description: string, badgeText: string): GuiObject
	local page = Instance.new("Frame")
	page.Name = `Page_{title}`
	page.BackgroundTransparency = 1
	page.Size = UDim2.new(1, 0, 1, 0)
	page.Visible = false
	page.Parent = self._contentArea

	Theme.applyPadding(page, 32, 32, 32, 32)

	local card = Instance.new("Frame")
	card.Name = "InfoCard"
	card.BackgroundColor3 = Theme.Colors.CharcoalDark
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.45, 0)
	card.Size = UDim2.new(0.9, 0, 0, 240)
	card.Parent = page
	Theme.applyCorner(card, Theme.Radii.Large)
	Theme.applyStroke(card, Theme.Colors.Border, 1)
	Theme.applyPadding(card, 24, 24, 24, 24)

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.BackgroundColor3 = Theme.Colors.CharcoalLight
	badge.Size = UDim2.new(0, 180, 0, 24)
	badge.Font = Theme.Fonts.Bold
	badge.Text = string.upper(badgeText)
	badge.TextColor3 = Theme.Colors.Amber
	badge.TextSize = Theme.TextSizes.Tiny
	badge.Parent = card
	Theme.applyCorner(badge, Theme.Radii.Pill)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 0, 0, 36)
	titleLabel.Size = UDim2.new(1, 0, 0, 28)
	titleLabel.Font = Theme.Fonts.Black
	titleLabel.Text = title
	titleLabel.TextColor3 = Theme.Colors.Cream
	titleLabel.TextSize = Theme.TextSizes.Header
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 0, 0, 72)
	descLabel.Size = UDim2.new(1, 0, 0, 48)
	descLabel.Font = Theme.Fonts.Regular
	descLabel.Text = description
	descLabel.TextColor3 = Theme.Colors.CreamMuted
	descLabel.TextSize = Theme.TextSizes.Body
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.Parent = card

	local notice = Instance.new("TextLabel")
	notice.Name = "Notice"
	notice.BackgroundTransparency = 1
	notice.Position = UDim2.new(0, 0, 0, 136)
	notice.Size = UDim2.new(1, 0, 0, 40)
	notice.Font = Theme.Fonts.Medium
	notice.Text = "This screen's interactive workflows will be active in future milestones. No speculative currency or actions take place here."
	notice.TextColor3 = Theme.Colors.Sage
	notice.TextSize = Theme.TextSizes.Small
	notice.TextXAlignment = Enum.TextXAlignment.Left
	notice.TextWrapped = true
	notice.Parent = card

	return page
end

-- ==================== UPDATE & LIFECYCLE ====================

function Desktop:Update(stateData: any)
	local snap = stateData.snapshot
	if snap == nil then
		return
	end

	-- Update Financials
	local balance = snap.balance or 0
	local pending = snap.pendingWorkerCuan or 0
	local rate = snap.incomePerSecond or 0
	local deviceId = snap.deviceId or "phone_cheap"

	self._homeCuanVal.Text = `{Theme.formatNumber(balance)} Cuan`
	self._homePendingVal.Text = `{Theme.formatNumber(pending)} Cuan`
	self._homeRateVal.Text = `+{string.format("%.1f", rate)}/s`

	-- Update Hardware Display
	if deviceId == "phone_fast" then
		self._homeDeviceName.Text = "Fast Phone (Equipped)"
		self._homeDeviceNote.Text = "Enhanced mobile production hardware. 1.6x yield multiplier active on organic posts."
		self._homeUpgradeDesc.Text = "PC Rumah (Workstation) — Available in BS-09 expansion."
	else
		self._homeDeviceName.Text = "Cheap Phone (Equipped)"
		self._homeDeviceNote.Text = "Starter mobile phone. Yield multiplier is 1.0x. Fast Phone upgrade available."
		self._homeUpgradeDesc.Text = "PhoneFast (50 Cuan) — Boosts strong organic payout from 15 to 24 Cuan per post."
	end

	-- Update Post Summary
	if snap.pendingPost ~= nil then
		local p = snap.pendingPost
		self._homePostSummary.Text = `Pending Post: Mode '{p.mode}' in review. Impact: {p.finalImpact}`
	else
		self._homePostSummary.Text = "Pending Post: None (Ready to compose)"
	end

	-- Update Mission Summary
	if snap.activeMission ~= nil then
		local m = snap.activeMission
		self._homeMissionSummary.Text = `Active Mission: '{m.missionId}' ({m.status}) — Impact: {m.accumulatedImpact}`
	else
		self._homeMissionSummary.Text = "Active Mission: None (Ready for new campaign)"
	end
end

function Desktop:SetVisible(visible: boolean, reducedMotion: boolean?)
	self._gui.Enabled = visible
	if visible then
		self._window.Size = UDim2.new(0.85, 0, 0.83, 0)
		self._backdrop.BackgroundTransparency = 1
		if reducedMotion then
			self._window.Size = UDim2.new(0.9, 0, 0.88, 0)
			self._backdrop.BackgroundTransparency = 0.45
		else
			Theme.tween(self._window, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0.9, 0, 0.88, 0),
			})
			Theme.tween(self._backdrop, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.45,
			})
		end
	end
end

function Desktop:Destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	self._gui:Destroy()
end

return Desktop
