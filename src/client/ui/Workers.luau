--!strict
-- Buzzer Simulator — Workers UI (BS-12)
-- Staffing and workstation management for BuzzerOS. Presentation only: every number
-- shown is projected from Catalog and the confirmed ProfileSnapshot, and purchases
-- are admitted through the shared ClientState mutation lane.
-- Contract sources: docs/04, docs/05, docs/06 (BS-12).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Composer = require(script.Parent:WaitForChild("PostComposer"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local Workers = {}
Workers.__index = Workers

local DESK_1_PRICE = Catalog.DeskPrices[1]
local TRAINEE_1_PRICE = Catalog.HirePrices[1]
local WORKER_1_RATE = Catalog.WorkerRatePerWorker

export type WorkersState = {
	balance: number,
	pendingWorkerCuan: number,
	incomePerSecond: number,
	tier: number,
	deviceId: string,
	hasPc: boolean,
	desk1Owned: boolean,
	trainee1Hired: boolean,
	desk1Phase: string,
	trainee1Phase: string,
	desk1Remaining: number,
	trainee1Remaining: number,
	saveStatus: string,
	awaiting: boolean,
	blockReason: string?,
}

-- Pure projection of workers/operations state from client state.
function Workers.projectState(stateData: any): WorkersState
	local snapshot = if typeof(stateData) == "table" then stateData.snapshot else nil
	local balance = if snapshot ~= nil and typeof(snapshot.balance) == "number" then snapshot.balance else 0
	local pending = if snapshot ~= nil and typeof(snapshot.pendingWorkerCuan) == "number" then snapshot.pendingWorkerCuan else 0
	local rate = if snapshot ~= nil and typeof(snapshot.incomePerSecond) == "number" then snapshot.incomePerSecond else 0
	local tier = if snapshot ~= nil and typeof(snapshot.tier) == "number" then snapshot.tier else 0
	local deviceId = if snapshot ~= nil and typeof(snapshot.deviceId) == "string" then snapshot.deviceId else "phone_cheap"
	local hasPc = deviceId == "pc_rumah"

	local desk1Owned = false
	if snapshot ~= nil and typeof(snapshot.ownedDesks) == "table" then
		for _, slot in ipairs(snapshot.ownedDesks) do
			if slot == 1 then
				desk1Owned = true
				break
			end
		end
	end

	local trainee1Hired = false
	if snapshot ~= nil and typeof(snapshot.workers) == "table" then
		for _, w in ipairs(snapshot.workers) do
			if (w :: any).slotIndex == 1 then
				trainee1Hired = true
				break
			end
		end
	end

	local awaiting = typeof(stateData) == "table" and stateData.awaitingSnapshotRevision ~= nil
	local saveStatus = if snapshot ~= nil and typeof(snapshot.saveStatus) == "string" then snapshot.saveStatus else "healthy"

	local state: WorkersState = {
		balance = balance,
		pendingWorkerCuan = pending,
		incomePerSecond = rate,
		tier = tier,
		deviceId = deviceId,
		hasPc = hasPc,
		desk1Owned = desk1Owned,
		trainee1Hired = trainee1Hired,
		desk1Phase = "loading",
		trainee1Phase = "loading",
		desk1Remaining = math.max(0, DESK_1_PRICE - balance),
		trainee1Remaining = math.max(0, TRAINEE_1_PRICE - balance),
		saveStatus = saveStatus,
		awaiting = awaiting,
		blockReason = nil,
	}

	if snapshot == nil then
		return state
	end

	-- Check in-flight and uncertain actions
	local deskInFlight = false
	local hireInFlight = false
	if typeof(stateData) == "table" then
		for _, req in pairs(stateData.inFlightRequests or {}) do
			if (req :: any).isMutation then
				if (req :: any).action == "BuyDesk" then deskInFlight = true end
				if (req :: any).action == "HireWorker" then hireInFlight = true end
			end
		end
		for _, req in pairs(stateData.uncertainMutations or {}) do
			if (req :: any).action == "BuyDesk" then deskInFlight = true end
			if (req :: any).action == "HireWorker" then hireInFlight = true end
		end
	end

	-- Desk 1 Phase
	if desk1Owned then
		state.desk1Phase = "owned"
	elseif saveStatus ~= "healthy" then
		state.desk1Phase = "saveUnavailable"
	elseif deskInFlight or awaiting then
		state.desk1Phase = "purchasing"
	elseif not hasPc then
		state.desk1Phase = "need_pc"
	elseif tier < 1 then
		state.desk1Phase = "need_tier"
	elseif balance >= DESK_1_PRICE then
		state.desk1Phase = "affordable"
	else
		state.desk1Phase = "locked"
	end

	-- Trainee 1 Phase
	if trainee1Hired then
		state.trainee1Phase = "hired"
	elseif saveStatus ~= "healthy" then
		state.trainee1Phase = "saveUnavailable"
	elseif hireInFlight or awaiting then
		state.trainee1Phase = "purchasing"
	elseif not hasPc then
		state.trainee1Phase = "need_pc"
	elseif not desk1Owned then
		state.trainee1Phase = "need_desk"
	elseif tier < 1 then
		state.trainee1Phase = "need_tier"
	elseif balance >= TRAINEE_1_PRICE then
		state.trainee1Phase = "affordable"
	else
		state.trainee1Phase = "locked"
	end

	return state
end

local function card(parent: Instance, name: string, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.Colors.CharcoalDark
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
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
	label.LayoutOrder = offset
	label.Size = UDim2.new(1, 0, 0, height)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Theme.Fonts.Regular
	label.Text = text
	label.TextColor3 = Theme.Colors.Cream
	label.TextSize = Theme.TextSizes.Small
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Parent = parent
	return label
end

function Workers.new(options: { parent: Instance, onAction: (string, any) -> (), getBlockReason: (() -> string?)? }): any
	local self = setmetatable({}, Workers)
	self._onAction = options.onAction
	self._getBlockReason = options.getBlockReason
	self._state = nil
	self._lastDeskPhase = nil
	self._lastHirePhase = nil

	self.Root = Composer.stack(options.parent, "Page_Workers", true)

	-- Overview Card
	local overview = card(self.Root, "OverviewCard", 110)
	tag(overview, "Tag", "STAFF & PASSIVE INCOME", Theme.Colors.Amber)
	local title = body(overview, "Title", "Home Studio Operations", 18, 20)
	title.Font = Theme.Fonts.Black
	title.TextSize = Theme.TextSizes.Subtitle
	self._overviewStats = body(overview, "Stats", "Online rate: +0.0 Cuan/s · Pending: 0 Cuan\nBanked durably every 30 connected seconds.", 42, 54)
	self._overviewStats.TextColor3 = Theme.Colors.CreamMuted

	-- Workstation 1 Card
	local deskCard = card(self.Root, "Desk1Card", 170)
	self._deskCard = deskCard
	self._deskTag = tag(deskCard, "Tag", "WORKSTATION 1 · MEJA KERJA", Theme.Colors.Sage)
	local deskTitle = body(deskCard, "Title", "Worker Desk 1", 18, 20)
	deskTitle.Font = Theme.Fonts.Black
	deskTitle.TextSize = Theme.TextSizes.Subtitle
	self._deskPrice = body(deskCard, "Price", `Price: {DESK_1_PRICE} Cuan`, 42, 18)
	self._deskPrice.TextColor3 = Theme.Colors.Amber
	self._deskDesc = body(
		deskCard,
		"Desc",
		"Dedicated timber workstation for 1 trainee assistant.\nPrerequisites: PC Rumah equipped · Tier 1 (300 Lifetime Cuan + 3 Claims)",
		64,
		42
	)
	self._deskDesc.TextColor3 = Theme.Colors.CreamMuted
	self._deskStatus = body(deskCard, "Status", "Loading status...", 110, 18)
	self._deskStatus.Font = Theme.Fonts.Bold
	self._deskStatus.TextColor3 = Theme.Colors.Amber

	self._buyDeskButton = Composer.button(self.Root, "BuyDesk1", `Purchase Worker Desk 1 · {DESK_1_PRICE} Cuan`, function()
		self:BuyDesk()
	end)

	-- Trainee 1 Card
	local traineeCard = card(self.Root, "Trainee1Card", 170)
	self._traineeCard = traineeCard
	self._traineeTag = tag(traineeCard, "Tag", "STAFF 1 · ASISTEN MAGANG", Theme.Colors.Sage)
	local traineeTitle = body(traineeCard, "Title", "Trainee Assistant 1", 18, 20)
	traineeTitle.Font = Theme.Fonts.Black
	traineeTitle.TextSize = Theme.TextSizes.Subtitle
	self._traineePrice = body(traineeCard, "Price", `Hiring fee: {TRAINEE_1_PRICE} Cuan`, 42, 18)
	self._traineePrice.TextColor3 = Theme.Colors.Amber
	self._traineeDesc = body(
		traineeCard,
		"Desc",
		"Produces +1.5 Cuan/second continuously while connected online.\nPrerequisites: Worker Desk 1 Owned · Tier 1",
		64,
		42
	)
	self._traineeDesc.TextColor3 = Theme.Colors.CreamMuted
	self._traineeStatus = body(traineeCard, "Status", "Loading status...", 110, 18)
	self._traineeStatus.Font = Theme.Fonts.Bold
	self._traineeStatus.TextColor3 = Theme.Colors.Amber

	self._hireWorkerButton = Composer.button(self.Root, "HireTrainee1", `Hire Trainee Assistant 1 · {TRAINEE_1_PRICE} Cuan`, function()
		self:HireWorker()
	end)

	-- Workstation 2 (Future Milestone) Card
	local desk2Card = card(self.Root, "Desk2Card", 110)
	tag(desk2Card, "Tag", "WORKSTATION 2 · STUDIO RUMAHAN", Theme.Colors.CreamMuted)
	local desk2Title = body(desk2Card, "Title", "Worker Desk 2 & Trainee 2", 18, 20)
	desk2Title.Font = Theme.Fonts.Black
	desk2Title.TextSize = Theme.TextSizes.Subtitle
	desk2Title.TextColor3 = Theme.Colors.CreamMuted
	local desk2Desc = body(
		desk2Card,
		"Desc",
		"Locked until future studio expansion milestone (Tier 2).\nEnables second trainee for +3.0 Cuan/s aggregate passive rate.",
		42,
		46
	)
	desk2Desc.TextColor3 = Theme.Colors.CreamMuted

	self._notice = Composer.label(self.Root, "WorkersNotice", "", 14, Theme.Colors.CreamMuted)
	self._refresh = Composer.button(self.Root, "RefreshWorkers", "Refresh confirmed progress", function()
		self._onAction("GetSnapshot", {})
	end)
	self._refresh.BackgroundColor3 = Theme.Colors.CharcoalLight
	self._refresh.TextColor3 = Theme.Colors.Cream

	return self
end

function Workers:BuyDesk()
	if not self._buyDeskButton.Active then
		return
	end
	local proj = self._projected
	if proj == nil or proj.desk1Phase ~= "affordable" then
		return
	end
	self._onAction("BuyDesk", { slotIndex = 1 })
end

function Workers:HireWorker()
	if not self._hireWorkerButton.Active then
		return
	end
	local proj = self._projected
	if proj == nil or proj.trainee1Phase ~= "affordable" then
		return
	end
	self._onAction("HireWorker", { slotIndex = 1, roleId = "trainee" })
end

function Workers:Update(stateData: any)
	self._state = stateData
	local proj = Workers.projectState(stateData)
	self._projected = proj

	-- Overview stats
	self._overviewStats.Text = string.format(
		"Online rate: +%.1f Cuan/s · Unbanked accrual: %s Cuan\nSpendable confirmed balance: %s Cuan. Pending is not spendable.",
		proj.incomePerSecond,
		Theme.formatNumber(proj.pendingWorkerCuan),
		Theme.formatNumber(proj.balance)
	)

	local blockReason = self._getBlockReason and self._getBlockReason() or nil

	-- Update Desk 1 Card & Button
	local deskBtnEnabled = false
	local deskBtnText = `Purchase Worker Desk 1 · {DESK_1_PRICE} Cuan`
	if proj.desk1Phase == "owned" then
		self._deskStatus.Text = "INSTALLED · WORKSTATION 1 ACTIVE"
		self._deskStatus.TextColor3 = Theme.Colors.Lime
		self._deskTag.Text = "OWNED · INSTALLED"
		deskBtnText = "Workstation 1 Installed"
	elseif proj.desk1Phase == "purchasing" then
		self._deskStatus.Text = "Saving purchase... waiting for server confirmation."
		self._deskStatus.TextColor3 = Theme.Colors.Amber
		self._deskTag.Text = "PROCESSING"
		deskBtnText = "Saving Desk Purchase..."
	elseif proj.desk1Phase == "need_pc" then
		self._deskStatus.Text = "Requires PC Rumah production terminal."
		self._deskStatus.TextColor3 = Theme.Colors.Amber
		self._deskTag.Text = "LOCKED · NEEDS PC RUMAH"
	elseif proj.desk1Phase == "need_tier" then
		self._deskStatus.Text = "Requires Tier 1 (300 Lifetime Cuan + 3 Mission Claims)."
		self._deskStatus.TextColor3 = Theme.Colors.Amber
		self._deskTag.Text = "LOCKED · NEEDS TIER 1"
	elseif proj.desk1Phase == "locked" then
		self._deskStatus.Text = `Need {Theme.formatNumber(proj.desk1Remaining)} more Cuan (Price: {DESK_1_PRICE}).`
		self._deskStatus.TextColor3 = Theme.Colors.Amber
		self._deskTag.Text = "LOCKED · INSUFFICIENT CUAN"
	elseif proj.desk1Phase == "affordable" then
		self._deskStatus.Text = `Ready to build · {DESK_1_PRICE} Cuan`
		self._deskStatus.TextColor3 = Theme.Colors.Lime
		self._deskTag.Text = "AVAILABLE TO PURCHASE"
		deskBtnEnabled = true
	else
		self._deskStatus.Text = "Loading workstation status..."
		self._deskStatus.TextColor3 = Theme.Colors.CreamMuted
		self._deskTag.Text = "LOADING"
	end
	Composer.setEnabled(self._buyDeskButton, deskBtnEnabled and blockReason == nil)
	self._buyDeskButton.Text = deskBtnText

	-- Update Trainee 1 Card & Button
	local traineeBtnEnabled = false
	local traineeBtnText = `Hire Trainee Assistant 1 · {TRAINEE_1_PRICE} Cuan`
	if proj.trainee1Phase == "hired" then
		self._traineeStatus.Text = "ON DUTY · ACCRUING +1.5 CUAN/S"
		self._traineeStatus.TextColor3 = Theme.Colors.Lime
		self._traineeTag.Text = "HIRED · ON DUTY"
		traineeBtnText = "Trainee 1 on Duty (+1.5 Cuan/s)"
	elseif proj.trainee1Phase == "purchasing" then
		self._traineeStatus.Text = "Saving hire... waiting for server confirmation."
		self._traineeStatus.TextColor3 = Theme.Colors.Amber
		self._traineeTag.Text = "PROCESSING"
		traineeBtnText = "Saving Trainee Hire..."
	elseif proj.trainee1Phase == "need_pc" then
		self._traineeStatus.Text = "Requires PC Rumah production terminal."
		self._traineeStatus.TextColor3 = Theme.Colors.Amber
		self._traineeTag.Text = "LOCKED · NEEDS PC RUMAH"
	elseif proj.trainee1Phase == "need_desk" then
		self._traineeStatus.Text = "Requires Worker Desk 1 to be purchased first."
		self._traineeStatus.TextColor3 = Theme.Colors.Amber
		self._traineeTag.Text = "LOCKED · NEEDS DESK 1"
	elseif proj.trainee1Phase == "need_tier" then
		self._traineeStatus.Text = "Requires Tier 1 (300 Lifetime Cuan + 3 Mission Claims)."
		self._traineeStatus.TextColor3 = Theme.Colors.Amber
		self._traineeTag.Text = "LOCKED · NEEDS TIER 1"
	elseif proj.trainee1Phase == "locked" then
		self._traineeStatus.Text = `Need {Theme.formatNumber(proj.trainee1Remaining)} more Cuan (Price: {TRAINEE_1_PRICE}).`
		self._traineeStatus.TextColor3 = Theme.Colors.Amber
		self._traineeTag.Text = "LOCKED · INSUFFICIENT CUAN"
	elseif proj.trainee1Phase == "affordable" then
		self._traineeStatus.Text = `Ready to hire · {TRAINEE_1_PRICE} Cuan (+1.5 Cuan/s)`
		self._traineeStatus.TextColor3 = Theme.Colors.Lime
		self._traineeTag.Text = "AVAILABLE TO HIRE"
		traineeBtnEnabled = true
	else
		self._traineeStatus.Text = "Loading staffing status..."
		self._traineeStatus.TextColor3 = Theme.Colors.CreamMuted
		self._traineeTag.Text = "LOADING"
	end
	Composer.setEnabled(self._hireWorkerButton, traineeBtnEnabled and blockReason == nil)
	self._hireWorkerButton.Text = traineeBtnText

	-- Notice
	self._notice.Text = blockReason or (stateData and stateData.activeError) or "Server-reported pending accrual is not spendable. Banking is attempted every 30 connected seconds (or with a saved action); only confirmed saves increase balance."

	-- Subtle confirmation styling
	self:_animateConfirmations(proj.desk1Phase, proj.trainee1Phase)
end

function Workers:_animateConfirmations(deskPhase: string, hirePhase: string)
	if self._lastDeskPhase == "purchasing" and deskPhase == "owned" then
		Theme.applyStroke(self._deskCard, Theme.Colors.Lime, 2)
		task.delay(1.2, function()
			if self._deskCard.Parent ~= nil then
				Theme.applyStroke(self._deskCard, Theme.Colors.Border, 1)
			end
		end)
	end
	if self._lastHirePhase == "purchasing" and hirePhase == "hired" then
		Theme.applyStroke(self._traineeCard, Theme.Colors.Lime, 2)
		task.delay(1.2, function()
			if self._traineeCard.Parent ~= nil then
				Theme.applyStroke(self._traineeCard, Theme.Colors.Border, 1)
			end
		end)
	end
	self._lastDeskPhase = deskPhase
	self._lastHirePhase = hirePhase
end

function Workers:Tick(_serverNow: number) end

function Workers:Destroy()
	self.Root:Destroy()
end

Workers.DESK_1_PRICE = DESK_1_PRICE
Workers.TRAINEE_1_PRICE = TRAINEE_1_PRICE
Workers.WORKER_1_RATE = WORKER_1_RATE

return Workers
