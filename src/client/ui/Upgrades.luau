--!strict
-- Buzzer Simulator — Upgrades (BS-09)
-- Fast Phone equipment shop for BuzzerOS. Presentation only: every number shown
-- is projected from Catalog/Rules or the confirmed ProfileSnapshot, and the
-- purchase is admitted through the shared ClientState mutation lane.
-- Contract sources: docs/04, docs/05, docs/08 (BS-09).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Presentation = require(Shared:WaitForChild("Presentation"))
local Rules = require(Shared:WaitForChild("Rules"))
local Composer = require(script.Parent:WaitForChild("PostComposer"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local Upgrades = {}
Upgrades.__index = Upgrades

-- V0 ships exactly one purchasable device upgrade (BS-09). PC Rumah belongs to
-- BS-11 and must never appear as a purchasable option here.
local TARGET_DEVICE = "phone_fast"

local function deviceById(deviceId: any): any?
	if typeof(deviceId) ~= "string" then
		return nil
	end
	for _, device in ipairs(Catalog.Devices) do
		if (device :: any).id == deviceId then
			return device
		end
	end
	return nil
end

-- Payouts are derived from the same shared formula the server settles with, so
-- the shop can never advertise a number the economy would not pay.
local function payoutOf(device: any): (number, number)
	if device == nil then
		return 0, 0
	end
	return Rules.organicCuan("strong", device.deviceYield), Rules.organicCuan("weak", device.deviceYield)
end

export type ShopState = {
	phase: string,
	current: any?,
	target: any?,
	price: number,
	balance: number,
	remaining: number,
	awaiting: boolean,
}

-- Pure projection of the shop phase from client state. Exported so tests can
-- assert the same function the UI renders from.
function Upgrades.shopState(stateData: any): ShopState
	local snapshot = if typeof(stateData) == "table" then stateData.snapshot else nil
	local target = deviceById(TARGET_DEVICE)
	local current = if snapshot ~= nil then deviceById(snapshot.deviceId) else nil
	local price = if target ~= nil then (target :: any).price else 0
	local balance = if snapshot ~= nil and typeof(snapshot.balance) == "number" then snapshot.balance else 0
	local state: ShopState = {
		phase = "loading",
		current = current,
		target = target,
		price = price,
		balance = balance,
		remaining = math.max(0, price - balance),
		awaiting = typeof(stateData) == "table" and stateData.awaitingSnapshotRevision ~= nil,
	}
	if snapshot == nil then
		return state
	end
	if snapshot.deviceId == TARGET_DEVICE then
		state.phase = "owned"
		return state
	end
	if snapshot.saveStatus ~= "healthy" then
		state.phase = "saveUnavailable"
		return state
	end
	-- An admitted purchase already owns the intent; a second action must not be
	-- offered while it is in flight or still unconfirmed.
	if typeof(stateData) == "table" then
		for _, request in pairs(stateData.inFlightRequests or {}) do
			if (request :: any).isMutation and (request :: any).action == "BuyDevice" then
				state.phase = "purchasing"
				return state
			end
		end
		for _, request in pairs(stateData.uncertainMutations or {}) do
			if (request :: any).action == "BuyDevice" then
				state.phase = "uncertain"
				return state
			end
		end
		if state.awaiting then
			state.phase = "purchasing"
			return state
		end
	end
	state.phase = if balance >= price then "affordable" else "locked"
	return state
end

local function card(parent: Instance, name: string, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.Colors.CharcoalDark
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.Parent = parent
	Theme.applyCorner(frame, Theme.Radii.Medium)
	Theme.applyStroke(frame, Theme.Colors.Border, 1)
	Theme.applyPadding(frame, 12, 14, 12, 14)
	return frame
end

local function tag(parent: Instance, name: string, text: string, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Font = Theme.Fonts.Bold
	label.Text = text
	label.TextColor3 = color or Theme.Colors.Amber
	label.TextSize = Theme.TextSizes.Tiny
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function body(parent: Instance, name: string, text: string, offset: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, offset)
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = Theme.Fonts.Medium
	label.Text = text
	label.TextColor3 = Theme.Colors.Cream
	label.TextSize = Theme.TextSizes.Small
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Parent = parent
	return label
end

function Upgrades.new(options: any): any
	local self = setmetatable({}, Upgrades)
	self._onAction = options.onAction
	self._getBlockReason = options.getBlockReason
	self._lastPhase = nil
	self._state = nil

	self.Root = Composer.stack(options.parent, "Page_Upgrades", true)
	Composer.label(self.Root, "Heading", "Hardware upgrades", 22)
	self._intro = Composer.label(
		self.Root,
		"Intro",
		"One phone produces your posts. Upgrading replaces it; yields never stack.",
		14,
		Theme.Colors.CreamMuted
	)

	-- Comparison card: the single current-to-next step, with one plain-language
	-- explanation of the benefit.
	local compare = card(self.Root, "ComparisonCard", 132)
	tag(compare, "Tag", "EQUIPMENT COMPARISON", Theme.Colors.Amber)
	self._compareBody = body(compare, "Comparison", "", 18, 104)
	Theme.applyStroke(compare, Theme.Colors.Border, 1)

	-- Fast Phone presentation card.
	local offer = card(self.Root, "FastPhoneCard", 176)
	self._offerCard = offer
	self._offerTag = tag(offer, "Tag", "FAST PHONE", Theme.Colors.Sage)
	self._offerName = body(offer, "OfferName", "HP Cepat", 18, 20)
	self._offerName.Font = Theme.Fonts.Black
	self._offerName.TextSize = Theme.TextSizes.Subtitle
	self._offerPrice = body(offer, "OfferPrice", "", 42, 18)
	self._offerPrice.TextColor3 = Theme.Colors.Amber
	self._offerBenefits = body(offer, "OfferBenefits", "", 64, 96)

	self._status = Composer.label(self.Root, "ShopStatus", "Loading confirmed hardware...", 15, Theme.Colors.Amber)
	self._purchase = Composer.button(self.Root, "BuyFastPhone", "Purchase Fast Phone", function()
		self:Purchase()
	end)
	self._notice = Composer.label(self.Root, "ShopNotice", "", 14, Theme.Colors.CreamMuted)
	self._refresh = Composer.button(self.Root, "RefreshHardware", "Refresh confirmed progress", function()
		self._onAction("GetSnapshot", {})
	end)
	self._refresh.BackgroundColor3 = Theme.Colors.CharcoalLight
	self._refresh.TextColor3 = Theme.Colors.Cream

	return self
end

function Upgrades:Purchase()
	if not self._purchase.Active then
		return
	end
	local shop = self._shop
	if shop == nil or shop.phase ~= "affordable" then
		return
	end
	-- IDs only: price, balance, ownership and yield are never sent.
	self._onAction("BuyDevice", { deviceId = TARGET_DEVICE })
end

function Upgrades:_renderComparison(current: any?, target: any?)
	if current == nil or target == nil then
		self._compareBody.Text = "Confirmed hardware is still loading."
		return
	end
	local currentStrong, currentWeak = payoutOf(current)
	local targetStrong, targetWeak = payoutOf(target)
	local currentName = Presentation.Devices[(current :: any).id] or (current :: any).id
	local targetName = Presentation.Devices[(target :: any).id] or (target :: any).id
	self._compareBody.Text = string.format(
		"%s  ->  %s\nStrong post: %d Cuan  ->  %d Cuan\nWeak post: %d Cuan  ->  %d Cuan\nReveal: %ds  ->  %ds\n\nA strong post earns %d more Cuan and reveals %ds faster.",
		currentName,
		targetName,
		currentStrong,
		targetStrong,
		currentWeak,
		targetWeak,
		(current :: any).revealSeconds,
		(target :: any).revealSeconds,
		targetStrong - currentStrong,
		(current :: any).revealSeconds - (target :: any).revealSeconds
	)
end

function Upgrades:Update(stateData: any)
	self._state = stateData
	local shop = Upgrades.shopState(stateData)
	self._shop = shop
	self:_renderComparison(shop.current, shop.target)

	if shop.target == nil then
		self._status.Text = "Fast Phone is not available in this build."
		Composer.setEnabled(self._purchase, false)
		return
	end

	local targetName = Presentation.Devices[TARGET_DEVICE] or TARGET_DEVICE
	local targetStrong, targetWeak = payoutOf(shop.target)
	local reveal = (shop.target :: any).revealSeconds
	self._offerName.Text = targetName
	self._offerPrice.Text = `Price: {Theme.formatNumber(shop.price)} Cuan · Confirmed balance: {Theme.formatNumber(shop.balance)} Cuan`
	self._offerBenefits.Text = string.format(
		"Strong organic payout: %d Cuan\nWeak organic payout: %d Cuan\nReveal time: %ds (was %ds)\nYield multiplier: %.2fx",
		targetStrong,
		targetWeak,
		reveal,
		if shop.current ~= nil then (shop.current :: any).revealSeconds else reveal,
		(shop.target :: any).deviceYield
	)

	local blockReason = self._getBlockReason and self._getBlockReason() or nil
	local enabled = false
	local notice = blockReason or stateData.activeError or "Your confirmed balance is never reduced before the server confirms a purchase."

	if shop.phase == "owned" then
		self._status.Text = "Equipped — Fast Phone"
		self._offerTag.Text = "OWNED · EQUIPPED"
		notice = "You already own the Fast Phone. A second purchase is not offered."
	elseif shop.phase == "purchasing" then
		self._status.Text = "Saving purchase... waiting for server confirmation."
		self._offerTag.Text = "PROCESSING"
		notice = "Price is not deducted locally. The balance updates only after the server confirms the save."
	elseif shop.phase == "uncertain" then
		self._status.Text = "Purchase unconfirmed"
		self._offerTag.Text = "UNCONFIRMED"
		notice = "The earlier purchase is still unconfirmed. Refresh progress; do not buy again."
	elseif shop.phase == "saveUnavailable" then
		self._status.Text = "Saving unavailable — upgrades paused"
		self._offerTag.Text = "READ ONLY"
		notice = "Progress cannot be saved right now. Purchasing is disabled until saving recovers."
	elseif shop.phase == "affordable" then
		self._status.Text = `Ready to buy · {Theme.formatNumber(shop.price)} Cuan`
		self._offerTag.Text = "AVAILABLE"
		enabled = true
	elseif shop.phase == "locked" then
		self._status.Text = `Need {Theme.formatNumber(shop.remaining)} more Cuan`
		self._offerTag.Text = "LOCKED"
		notice = `You have {Theme.formatNumber(shop.balance)} Cuan of the {Theme.formatNumber(shop.price)} Cuan price.`
	else
		self._status.Text = "Loading confirmed hardware..."
		self._offerTag.Text = "LOADING"
	end

	Composer.setEnabled(self._purchase, enabled and blockReason == nil)
	self._purchase.Text = if shop.phase == "owned"
		then "Equipped — Fast Phone"
		elseif shop.phase == "purchasing" then "Saving purchase..."
		else `Purchase Fast Phone · {Theme.formatNumber(shop.price)} Cuan`
	self._notice.Text = notice
	self:_animateConfirmation(shop.phase)
end

-- Restrained confirmation: one short lime pulse on the offer card, then settle.
function Upgrades:_animateConfirmation(phase: string)
	local previous = self._lastPhase
	self._lastPhase = phase
	if not (previous == "purchasing" and phase == "owned") then
		return
	end
	local offer = self._offerCard
	Theme.applyStroke(offer, Theme.Colors.Lime, 2)
	local ok, enabled = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	if ok and enabled == true then
		return
	end
	task.delay(1.2, function()
		if offer.Parent ~= nil and self._lastPhase == "owned" then
			Theme.applyStroke(offer, Theme.Colors.Sage, 1)
		end
	end)
end

function Upgrades:Tick(_serverNow: number) end

function Upgrades:Destroy()
	self.Root:Destroy()
end

Upgrades.TARGET_DEVICE = TARGET_DEVICE
Upgrades.payoutOf = payoutOf
Upgrades.deviceById = deviceById

return Upgrades
