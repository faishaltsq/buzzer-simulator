--!strict
-- Buzzer Simulator — Hud (BS-07)
-- World HUD displaying confirmed Cuan, pending worker income, online rate,
-- player tier, current progression objective, and system status banners.
-- Contract sources: docs/03, docs/05.

local Theme = require(script.Parent:WaitForChild("Theme") :: any)

local Hud = {}
Hud.__index = Hud

export type HudOptions = {
	parent: Instance,
	onOpenTerminalHint: (() -> ())?,
}

local function computeObjective(snapshot: any?): (string, string)
	if snapshot == nil then
		return "Loading profile...", "Connecting to BuzzerOS"
	end

	local balance = snapshot.balance or 0
	local deviceId = snapshot.deviceId or "phone_cheap"
	local completedMissions = snapshot.completedMissions or 0
	local ownPosts = snapshot.ownPosts or {}
	local activeMission = snapshot.activeMission

	if activeMission ~= nil then
		return "Active Mission", "Complete campaign post at the computer"
	elseif completedMissions == 0 and #ownPosts == 0 then
		return "First Goal", "Create your first Buzzline post at the computer"
	elseif deviceId == "phone_cheap" and balance < 50 then
		return "Next Hardware", `Save {50 - balance} more Cuan for PhoneFast (50 Cuan)`
	elseif deviceId == "phone_cheap" and balance >= 50 then
		return "Hardware Ready", "Upgrade to PhoneFast at the computer (50 Cuan)"
	elseif deviceId == "phone_fast" then
		return "Studio Progression", "Produce posts to prepare for Studio Expansion"
	else
		return "Daily Routine", "Produce high-impact posts to grow your Cuan"
	end
end

function Hud.new(options: HudOptions): any
	local self = setmetatable({}, Hud)
	self._parent = options.parent
	self._isDashboardOpen = false
	self._connections = {}

	-- ScreenGui container
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuzzerWorldHud"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 1
	screenGui.Parent = self._parent
	self._gui = screenGui

	-- Root frame with CanvasGroup for smooth dimming when BuzzerOS opens
	local root = Instance.new("CanvasGroup")
	root.Name = "HudRoot"
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 1, 0)
	root.Position = UDim2.new(0, 0, 0, 0)
	root.GroupTransparency = 0
	root.Parent = screenGui
	self._root = root

	-- Safe area padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = root

	-- Top Left: Financial & Tier Card
	local balanceCard = Instance.new("Frame")
	balanceCard.Name = "BalanceCard"
	balanceCard.BackgroundColor3 = Theme.Colors.CharcoalDark
	balanceCard.BackgroundTransparency = 0.1
	balanceCard.Size = UDim2.new(0, 250, 0, 84)
	balanceCard.Position = UDim2.new(0, 0, 0, 0)
	balanceCard.Parent = root
	self._balanceCard = balanceCard
	Theme.applyCorner(balanceCard, Theme.Radii.Medium)
	Theme.applyStroke(balanceCard, Theme.Colors.Border, 1)

	local cardPadding = Theme.applyPadding(balanceCard, 10, 12, 10, 12)

	-- Confirmed Cuan Row
	local cuanRow = Instance.new("Frame")
	cuanRow.Name = "CuanRow"
	cuanRow.BackgroundTransparency = 1
	cuanRow.Size = UDim2.new(1, 0, 0, 24)
	cuanRow.Parent = balanceCard

	local cuanIcon = Instance.new("TextLabel")
	cuanIcon.Name = "CuanIcon"
	cuanIcon.BackgroundTransparency = 1
	cuanIcon.Size = UDim2.new(0, 24, 1, 0)
	cuanIcon.Font = Theme.Fonts.Bold
	cuanIcon.Text = "C$"
	cuanIcon.TextColor3 = Theme.Colors.Amber
	cuanIcon.TextSize = Theme.TextSizes.Title
	cuanIcon.TextXAlignment = Enum.TextXAlignment.Left
	cuanIcon.Parent = cuanRow

	local cuanLabel = Instance.new("TextLabel")
	cuanLabel.Name = "CuanLabel"
	cuanLabel.BackgroundTransparency = 1
	cuanLabel.Size = UDim2.new(1, -26, 1, 0)
	cuanLabel.Position = UDim2.new(0, 26, 0, 0)
	cuanLabel.Font = Theme.Fonts.Black
	cuanLabel.Text = "0 Cuan"
	cuanLabel.TextColor3 = Theme.Colors.Cream
	cuanLabel.TextSize = Theme.TextSizes.Title
	cuanLabel.TextXAlignment = Enum.TextXAlignment.Left
	cuanLabel.Parent = cuanRow
	self._cuanLabel = cuanLabel

	-- Secondary Row: Unbanked & Rate
	local secondaryRow = Instance.new("Frame")
	secondaryRow.Name = "SecondaryRow"
	secondaryRow.BackgroundTransparency = 1
	secondaryRow.Size = UDim2.new(1, 0, 0, 18)
	secondaryRow.Position = UDim2.new(0, 0, 0, 28)
	secondaryRow.Parent = balanceCard

	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "RateLabel"
	rateLabel.BackgroundTransparency = 1
	rateLabel.Size = UDim2.new(0.5, 0, 1, 0)
	rateLabel.Font = Theme.Fonts.Medium
	rateLabel.Text = "+0.0 Cuan/s"
	rateLabel.TextColor3 = Theme.Colors.Lime
	rateLabel.TextSize = Theme.TextSizes.Small
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel.Parent = secondaryRow
	self._rateLabel = rateLabel

	local pendingLabel = Instance.new("TextLabel")
	pendingLabel.Name = "PendingLabel"
	pendingLabel.BackgroundTransparency = 1
	pendingLabel.Size = UDim2.new(0.5, 0, 1, 0)
	pendingLabel.Position = UDim2.new(0.5, 0, 0, 0)
	pendingLabel.Font = Theme.Fonts.Regular
	pendingLabel.Text = "Unbanked: 0"
	pendingLabel.TextColor3 = Theme.Colors.CreamMuted
	pendingLabel.TextSize = Theme.TextSizes.Small
	pendingLabel.TextXAlignment = Enum.TextXAlignment.Right
	pendingLabel.Parent = secondaryRow
	self._pendingLabel = pendingLabel

	-- Tier Badge / Progression
	local tierRow = Instance.new("Frame")
	tierRow.Name = "TierRow"
	tierRow.BackgroundTransparency = 1
	tierRow.Size = UDim2.new(1, 0, 0, 16)
	tierRow.Position = UDim2.new(0, 0, 0, 50)
	tierRow.Parent = balanceCard

	local tierBadge = Instance.new("TextLabel")
	tierBadge.Name = "TierBadge"
	tierBadge.BackgroundTransparency = 1
	tierBadge.Size = UDim2.new(1, 0, 1, 0)
	tierBadge.Font = Theme.Fonts.Bold
	tierBadge.Text = "Tier 0: Bedroom Solo"
	tierBadge.TextColor3 = Theme.Colors.Sage
	tierBadge.TextSize = Theme.TextSizes.Tiny
	tierBadge.TextXAlignment = Enum.TextXAlignment.Left
	tierBadge.Parent = tierRow
	self._tierBadge = tierBadge

	-- Top Center: Objective Pill
	local objectivePill = Instance.new("Frame")
	objectivePill.Name = "ObjectivePill"
	objectivePill.BackgroundColor3 = Theme.Colors.CharcoalDark
	objectivePill.BackgroundTransparency = 0.15
	objectivePill.Size = UDim2.new(0, 300, 0, 46)
	objectivePill.Position = UDim2.new(0.5, 0, 0, 0)
	objectivePill.AnchorPoint = Vector2.new(0.5, 0)
	objectivePill.Parent = root
	self._objectivePill = objectivePill
	Theme.applyCorner(objectivePill, Theme.Radii.Large)
	Theme.applyStroke(objectivePill, Theme.Colors.Border, 1)
	Theme.applyPadding(objectivePill, 6, 12, 6, 12)

	local objTag = Instance.new("TextLabel")
	objTag.Name = "Tag"
	objTag.BackgroundTransparency = 1
	objTag.Size = UDim2.new(1, 0, 0, 14)
	objTag.Font = Theme.Fonts.Bold
	objTag.Text = "CURRENT OBJECTIVE"
	objTag.TextColor3 = Theme.Colors.Amber
	objTag.TextSize = Theme.TextSizes.Tiny
	objTag.TextXAlignment = Enum.TextXAlignment.Center
	objTag.Parent = objectivePill
	self._objTag = objTag

	local objDesc = Instance.new("TextLabel")
	objDesc.Name = "Description"
	objDesc.BackgroundTransparency = 1
	objDesc.Size = UDim2.new(1, 0, 0, 18)
	objDesc.Position = UDim2.new(0, 0, 0, 16)
	objDesc.Font = Theme.Fonts.Medium
	objDesc.Text = "Approach the old CRT to open BuzzerOS"
	objDesc.TextColor3 = Theme.Colors.Cream
	objDesc.TextSize = Theme.TextSizes.Small
	objDesc.TextXAlignment = Enum.TextXAlignment.Center
	objDesc.TextTruncate = Enum.TextTruncate.AtEnd
	objDesc.Parent = objectivePill
	self._objDesc = objDesc

	-- Bottom Center: Interaction Reminder / Context Banner
	local hintBanner = Instance.new("Frame")
	hintBanner.Name = "InteractionHint"
	hintBanner.BackgroundColor3 = Theme.Colors.CharcoalDark
	hintBanner.BackgroundTransparency = 0.2
	hintBanner.Size = UDim2.new(0, 380, 0, 36)
	hintBanner.Position = UDim2.new(0.5, 0, 1, -12)
	hintBanner.AnchorPoint = Vector2.new(0.5, 1)
	hintBanner.Parent = root
	self._hintBanner = hintBanner
	Theme.applyCorner(hintBanner, Theme.Radii.Pill)
	Theme.applyStroke(hintBanner, Theme.Colors.Border, 1)
	Theme.applyPadding(hintBanner, 6, 16, 6, 16)

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "HintLabel"
	hintLabel.BackgroundTransparency = 1
	hintLabel.Size = UDim2.new(1, 0, 1, 0)
	hintLabel.Font = Theme.Fonts.Regular
	hintLabel.Text = "Old CRT runs BuzzerOS • Equipped phone drives post yield"
	hintLabel.TextColor3 = Theme.Colors.CreamMuted
	hintLabel.TextSize = Theme.TextSizes.Tiny
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Parent = hintBanner
	self._hintLabel = hintLabel

	-- Top Right: System Status Banner (Error, Save-blocked, Offline)
	local statusBanner = Instance.new("Frame")
	statusBanner.Name = "StatusBanner"
	statusBanner.BackgroundColor3 = Theme.Colors.Coral
	statusBanner.BackgroundTransparency = 0.1
	statusBanner.Size = UDim2.new(0, 230, 0, 36)
	statusBanner.AnchorPoint = Vector2.new(1, 0)
	statusBanner.Position = UDim2.new(1, 0, 0, 0)
	statusBanner.Visible = false
	statusBanner.Parent = root
	self._statusBanner = statusBanner
	Theme.applyCorner(statusBanner, Theme.Radii.Medium)
	Theme.applyStroke(statusBanner, Theme.Colors.Border, 1)
	Theme.applyPadding(statusBanner, 6, 10, 6, 10)

	local statusText = Instance.new("TextLabel")
	statusText.Name = "StatusText"
	statusText.BackgroundTransparency = 1
	statusText.Size = UDim2.new(1, 0, 1, 0)
	statusText.Font = Theme.Fonts.Bold
	statusText.Text = "SAVE BLOCKED"
	statusText.TextColor3 = Theme.Colors.Cream
	statusText.TextSize = Theme.TextSizes.Tiny
	statusText.TextXAlignment = Enum.TextXAlignment.Center
	statusText.Parent = statusBanner
	self._statusBanner = statusBanner

	table.insert(self._connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateLayout()
	end))
	self:_updateLayout()
	self._statusText = statusText

	return self
end

function Hud:_updateLayout()
	local width = self._root.AbsoluteSize.X
	local isNarrow = width < 640
	local isBannerVisible = self._statusBanner.Visible

	if isNarrow then
		if isBannerVisible then
			self._statusBanner.AnchorPoint = Vector2.new(0, 0)
			self._statusBanner.Position = UDim2.new(0, 0, 0, 0)
			self._statusBanner.Size = UDim2.new(1, 0, 0, 26)
		end

		local topOffset = if isBannerVisible then 30 else 0

		self._balanceCard.AnchorPoint = Vector2.new(0, 0)
		self._balanceCard.Position = UDim2.new(0, 0, 0, topOffset)
		self._balanceCard.Size = UDim2.new(1, 0, 0, 68)

		self._objectivePill.AnchorPoint = Vector2.new(0, 0)
		self._objectivePill.Position = UDim2.new(0, 0, 0, topOffset + 74)
		self._objectivePill.Size = UDim2.new(1, 0, 0, 36)

		self._hintBanner.AnchorPoint = Vector2.new(0.5, 1)
		self._hintBanner.Position = UDim2.new(0.5, 0, 1, -6)
		self._hintBanner.Size = UDim2.new(1, 0, 0, 28)
	else
		self._balanceCard.AnchorPoint = Vector2.new(0, 0)
		self._balanceCard.Position = UDim2.new(0, 0, 0, 0)
		self._balanceCard.Size = UDim2.new(0, 250, 0, 84)

		self._objectivePill.AnchorPoint = Vector2.new(0.5, 0)
		self._objectivePill.Position = UDim2.new(0.5, 0, 0, 0)
		self._objectivePill.Size = UDim2.new(0, 300, 0, 46)

		self._statusBanner.AnchorPoint = Vector2.new(1, 0)
		self._statusBanner.Position = UDim2.new(1, 0, 0, 0)
		self._statusBanner.Size = UDim2.new(0, 230, 0, 36)

		self._hintBanner.AnchorPoint = Vector2.new(0.5, 1)
		self._hintBanner.Position = UDim2.new(0.5, 0, 1, -12)
		self._hintBanner.Size = UDim2.new(0, 380, 0, 36)
	end
end

-- Updates HUD from authoritative client state and player attributes
function Hud:Update(stateData: any, player: Player?)
	local snap = stateData.snapshot
	local balance = if snap ~= nil then snap.balance or 0 else 0
	local pending = if snap ~= nil then snap.pendingWorkerCuan or 0 else 0
	local rate = if snap ~= nil then snap.incomePerSecond or 0 else 0
	local tier = if snap ~= nil then snap.tier or 0 else 0

	-- Format spendable balance
	self._cuanLabel.Text = `{Theme.formatNumber(balance)} Cuan`

	-- Format rate and unbanked
	self._rateLabel.Text = `+{string.format("%.1f", rate)}/s`
	self._pendingLabel.Text = `Unbanked: {Theme.formatNumber(pending)}`

	-- Format tier badge
	self._tierBadge.Text = `Tier {tier}: Bedroom Solo`

	-- Compute objective
	local tag, desc = computeObjective(snap)
	self._objTag.Text = string.upper(tag)
	self._objDesc.Text = desc

	-- Check system statuses
	local isReady = true
	local loadError: string? = nil
	local worldError: string? = nil

	if player ~= nil then
		if player:GetAttribute("BuzzerReady") == false then
			isReady = false
		end
		loadError = player:GetAttribute("BuzzerLoadError") :: string?
		worldError = player:GetAttribute("BuzzerWorldError") :: string?
	end

	local isSaveBlocked = (snap ~= nil and snap.saveStatus == "SAVE_UNAVAILABLE") or (loadError == "SAVE_UNAVAILABLE")

	if not isReady then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.CharcoalDark
		self._statusText.Text = "LOADING BUZZEROS..."
	elseif isSaveBlocked then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.Coral
		self._statusText.Text = "SAVE BLOCKED: ACTION PAUSED"
	elseif stateData.status == "ConnectionUncertain" then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.Amber
		self._statusText.Text = "CONNECTION UNCERTAIN: REFRESHING"
	elseif worldError ~= nil then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.Coral
		self._statusText.Text = "WORLD ASSET PROBLEM"
	elseif loadError ~= nil then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.Coral
		self._statusText.Text = `SESSION ERROR: {loadError}`
	elseif stateData.activeDenial ~= nil then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.Amber
		self._statusText.Text = `TERMINAL: {stateData.activeDenial}`
	elseif stateData.activeError ~= nil then
		self._statusBanner.Visible = true
		self._statusBanner.BackgroundColor3 = Theme.Colors.Coral
		self._statusText.Text = string.upper(stateData.activeError)
	else
		self._statusBanner.Visible = false
	end

	self:_updateLayout()
end

-- Sets whether BuzzerOS desktop is currently open (subtly dimming the HUD)
function Hud:SetDashboardOpen(isOpen: boolean, reducedMotion: boolean?)
	self._isDashboardOpen = isOpen
	local targetAlpha = if isOpen then 0.65 else 0

	if reducedMotion then
		self._root.GroupTransparency = targetAlpha
	else
		Theme.tween(self._root, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = targetAlpha,
		})
	end
end

function Hud:Destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	self._gui:Destroy()
end

return Hud