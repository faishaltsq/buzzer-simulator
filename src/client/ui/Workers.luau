--!strict
-- Buzzer Simulator — Workers UI (BS-12, extended BS-13)
-- Staffing and workstation management for BuzzerOS. Presentation only: every number
-- shown is projected from Catalog and the confirmed ProfileSnapshot, and purchases
-- are admitted through the shared ClientState mutation lane.
-- Contract sources: docs/04, docs/05, docs/06 (BS-12), docs/04 Home Studio chapter (BS-13).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Composer = require(script.Parent:WaitForChild("PostComposer"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local Workers = {}
Workers.__index = Workers

local DESK_PRICES = Catalog.DeskPrices
local HIRE_PRICES = Catalog.HirePrices
local WORKER_RATE = Catalog.WorkerRatePerWorker
local MAX_WORKER_SLOTS = 2

export type WorkersState = {
	balance: number,
	pendingWorkerCuan: number,
	incomePerSecond: number,
	tier: number,
	deviceId: string,
	hasPc: boolean,
	deskOwned: { [number]: boolean },
	traineeHired: { [number]: boolean },
	deskPhase: { [number]: string },
	traineePhase: { [number]: string },
	deskRemaining: { [number]: number },
	traineeRemaining: { [number]: number },
	workersHired: number,
	chapter: { [string]: boolean },
	chapterDoneCount: number,
	chapterComplete: boolean,
	saveStatus: string,
	awaiting: boolean,
	blockReason: string?,
}

-- Pure projection of the eight canonical M1 "Studio Rumahan" chapter steps
-- (docs/04, BS-13 Phase 6.4). Order matters; the UI renders it 1:1.
local CHAPTER_ORDER = {
	"pcOwned", "tier1", "desk1", "trainee1", "tier2", "desk2", "trainee2",
}
local CHAPTER_LABELS = {
	pcOwned = "Equip PC Rumah",
	tier1 = "Reach Tier 1",
	desk1 = "Purchase Desk 1",
	trainee1 = "Hire Trainee 1",
	tier2 = "Reach Tier 2",
	desk2 = "Purchase Desk 2",
	trainee2 = "Hire Trainee 2",
}

function Workers.chapterProgress(snapshot: any): ({ [string]: boolean }, number, boolean)
	local steps: { [string]: boolean } = {}
	if snapshot == nil then
		return steps, 0, false
	end
	local lifetime = if typeof(snapshot.lifetimeEarned) == "number" then snapshot.lifetimeEarned else 0
	local claims = if typeof(snapshot.completedMissions) == "number" then snapshot.completedMissions else 0
	local tier = if typeof(snapshot.tier) == "number" then snapshot.tier else 0
	steps.pcOwned = snapshot.deviceId == "pc_rumah"
	steps.tier1 = tier >= 1
	steps.tier2 = tier >= 2
	local ownedDesks = if typeof(snapshot.ownedDesks) == "table" then snapshot.ownedDesks else {}
	for _, slot in ipairs(ownedDesks) do
		if slot == 1 then steps.desk1 = true end
		if slot == 2 then steps.desk2 = true end
	end
	local workers = if typeof(snapshot.workers) == "table" then snapshot.workers else {}
	for _, w in ipairs(workers) do
		if (w :: any).slotIndex == 1 then steps.trainee1 = true end
		if (w :: any).slotIndex == 2 then steps.trainee2 = true end
	end
	local done = 0
	for _, key in ipairs(CHAPTER_ORDER) do
		if steps[key] then done += 1 end
	end
	-- Chapter completeness derives from the confirmed profile only; mirror the
	-- server-side tier derivation contract (thresholds from Catalog.Tiers).
	local tier1Ok = lifetime >= Catalog.Tiers[2].lifetimeRequired and claims >= Catalog.Tiers[2].claimsRequired
	local tier2Ok = lifetime >= Catalog.Tiers[3].lifetimeRequired and claims >= Catalog.Tiers[3].claimsRequired
	-- `== true` normalizes the and-chain so a missing final step yields
	-- false, never nil (declared return type is boolean).
	local complete = (steps.pcOwned and tier1Ok and steps.desk1 and steps.trainee1
		and tier2Ok and steps.desk2 and steps.trainee2) == true
	return steps, done, complete
end

local function hasSlotIn(list_table: any, slotIndex: number, key: string?): boolean
	if typeof(list_table) ~= "table" then return false end
	for _, value in ipairs(list_table) do
		if key == nil then
			if value == slotIndex then return true end
		else
			if (value :: any)[key] == slotIndex then return true end
		end
	end
	return false
end

-- Pure projection of workers/operations state from client state.
function Workers.projectState(stateData: any): WorkersState
	local snapshot = if typeof(stateData) == "table" then stateData.snapshot else nil
	local balance = if snapshot ~= nil and typeof(snapshot.balance) == "number" then snapshot.balance else 0
	local pending = if snapshot ~= nil and typeof(snapshot.pendingWorkerCuan) == "number" then snapshot.pendingWorkerCuan else 0
	local rate = if snapshot ~= nil and typeof(snapshot.incomePerSecond) == "number" then snapshot.incomePerSecond else 0
	local tier = if snapshot ~= nil and typeof(snapshot.tier) == "number" then snapshot.tier else 0
	local deviceId = if snapshot ~= nil and typeof(snapshot.deviceId) == "string" then snapshot.deviceId else "phone_cheap"
	local hasPc = deviceId == "pc_rumah"

	local deskOwned: { [number]: boolean } = {}
	local traineeHired: { [number]: boolean } = {}
	for slot = 1, MAX_WORKER_SLOTS do
		deskOwned[slot] = hasSlotIn(if snapshot ~= nil then snapshot.ownedDesks else nil, slot)
		traineeHired[slot] = hasSlotIn(if snapshot ~= nil then snapshot.workers else nil, slot, "slotIndex")
	end

	local workersHired = if snapshot ~= nil and typeof(snapshot.workers) == "table" then #snapshot.workers else 0
	local chapter, chapterDone, chapterComplete = Workers.chapterProgress(snapshot)
	local saveStatus = if snapshot ~= nil and typeof(snapshot.saveStatus) == "string" then snapshot.saveStatus else "healthy"
	local awaiting = typeof(stateData) == "table" and stateData.awaitingSnapshotRevision ~= nil

	-- In-flight/uncertain mutations are matched per slot so a Desk 1 save does
	-- not blink Desk 2 into "purchasing".
	local deskInFlight: { [number]: boolean } = {}
	local hireInFlight: { [number]: boolean } = {}
	if typeof(stateData) == "table" then
		for _, req in pairs(stateData.inFlightRequests or {}) do
			local request = req :: any
			if request.isMutation and (request.action == "BuyDesk" or request.action == "HireWorker") then
				local slot = if typeof(request.payload) == "table" and typeof(request.payload.slotIndex) == "number"
					then request.payload.slotIndex else 1
				if request.action == "BuyDesk" then deskInFlight[slot] = true else hireInFlight[slot] = true end
			end
		end
		for _, req in pairs(stateData.uncertainMutations or {}) do
			local request = req :: any
			if request.action == "BuyDesk" or request.action == "HireWorker" then
				local slot = if typeof(request.payload) == "table" and typeof(request.payload.slotIndex) == "number"
					then request.payload.slotIndex else 1
				if request.action == "BuyDesk" then deskInFlight[slot] = true else hireInFlight[slot] = true end
			end
		end
	end

	local state: WorkersState = {
		balance = balance,
		pendingWorkerCuan = pending,
		incomePerSecond = rate,
		tier = tier,
		deviceId = deviceId,
		hasPc = hasPc,
		deskOwned = deskOwned,
		traineeHired = traineeHired,
		deskPhase = {},
		traineePhase = {},
		deskRemaining = {},
		traineeRemaining = {},
		workersHired = workersHired,
		chapter = chapter,
		chapterDoneCount = chapterDone,
		chapterComplete = chapterComplete,
		saveStatus = saveStatus,
		awaiting = awaiting,
		blockReason = nil,
	}
	for slot = 1, MAX_WORKER_SLOTS do
		state.deskRemaining[slot] = math.max(0, DESK_PRICES[slot] - balance)
		state.traineeRemaining[slot] = math.max(0, HIRE_PRICES[slot] - balance)
	end

	if snapshot == nil then
		for slot = 1, MAX_WORKER_SLOTS do
			state.deskPhase[slot] = "loading"
			state.traineePhase[slot] = "loading"
		end
		return state
	end

	for slot = 1, MAX_WORKER_SLOTS do
		-- Desk slot phases. Prerequisite chain (docs/04): PC -> tier -> prior
		-- desk -> prior trainee (slot 2 only) -> funds.
		if deskOwned[slot] then
			state.deskPhase[slot] = "owned"
		elseif saveStatus ~= "healthy" then
			state.deskPhase[slot] = "saveUnavailable"
		elseif (deskInFlight[slot] or false) or awaiting then
			state.deskPhase[slot] = "purchasing"
		elseif not hasPc then
			state.deskPhase[slot] = "need_pc"
		elseif tier < slot then
			state.deskPhase[slot] = "need_tier"
		elseif slot > 1 and not deskOwned[slot - 1] then
			state.deskPhase[slot] = "need_first_desk"
		elseif slot > 1 and not traineeHired[slot - 1] then
			state.deskPhase[slot] = "need_first_worker"
		elseif balance >= DESK_PRICES[slot] then
			state.deskPhase[slot] = "affordable"
		else
			state.deskPhase[slot] = "locked"
		end

		-- Trainee slot phases. Prerequisite chain: PC -> desk -> tier (mirrors
		-- docs/04 hire gates; sequential worker progression is server-checked).
		if traineeHired[slot] then
			state.traineePhase[slot] = "hired"
		elseif saveStatus ~= "healthy" then
			state.traineePhase[slot] = "saveUnavailable"
		elseif (hireInFlight[slot] or false) or awaiting then
			state.traineePhase[slot] = "purchasing"
		elseif not hasPc then
			state.traineePhase[slot] = "need_pc"
		elseif not deskOwned[slot] then
			state.traineePhase[slot] = "need_desk"
		elseif tier < slot then
			state.traineePhase[slot] = "need_tier"
		elseif slot > 1 and not traineeHired[slot - 1] then
			state.traineePhase[slot] = "need_first_worker"
		elseif balance >= HIRE_PRICES[slot] then
			state.traineePhase[slot] = "affordable"
		else
			state.traineePhase[slot] = "locked"
		end
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

local SLOTS = { 1, 2 }

function Workers.new(options: { parent: Instance, onAction: (string, any) -> (), getBlockReason: (() -> string?)? }): any
	local self = setmetatable({}, Workers)
	self._onAction = options.onAction
	self._getBlockReason = options.getBlockReason
	self._state = nil
	self._lastDeskPhase = {}
	self._lastHirePhase = {}
	self._lastChapterComplete = false

	self.Root = Composer.stack(options.parent, "Page_Workers", true)

	-- Home Studio Chapter Card (BS-13)
	local chapterCard = card(self.Root, "ChapterCard", 90)
	self._chapterCard = chapterCard
	self._chapterTag = tag(chapterCard, "Tag", "M1 CHAPTER · STUDIO RUMAHAN", Theme.Colors.Amber)
	self._chapterTitle = body(chapterCard, "Title", "Home Studio Progress 0 / 7", 18, 20)
	self._chapterTitle.Font = Theme.Fonts.Black
	self._chapterTitle.TextSize = Theme.TextSizes.Subtitle
	for index, key in ipairs(CHAPTER_ORDER) do
		local stepLabel = body(chapterCard, `Step_{key}`, `{index}. {CHAPTER_LABELS[key]}`, 40 + index, 16)
		stepLabel.TextSize = Theme.TextSizes.Tiny
		self._chapterSteps = self._chapterSteps or {}
		self._chapterSteps[key] = stepLabel
	end

	-- Overview Card
	local overview = card(self.Root, "OverviewCard", 110)
	tag(overview, "Tag", "STAFF & PASSIVE INCOME", Theme.Colors.Amber)
	local title = body(overview, "Title", "Home Studio Operations", 18, 20)
	title.Font = Theme.Fonts.Black
	title.TextSize = Theme.TextSizes.Subtitle
	self._overviewStats = body(overview, "Stats", "Trainees: 0 / 2 · Online rate: +0.0 Cuan/s\nUnbanked accrual: 0 Cuan · Every 30 connected seconds banks durably.", 42, 54)
	self._overviewStats.TextColor3 = Theme.Colors.CreamMuted

	-- Workstation + Staff cards per slot
	self._deskCards = {}
	self._deskTags = {}
	self._deskStatuses = {}
	self._deskButtons = {}
	self._traineeCards = {}
	self._traineeTags = {}
	self._traineeStatuses = {}
	self._traineeButtons = {}

	for slot in ipairs(SLOTS) do
		local deskCard = card(self.Root, `Desk{slot}Card`, 170)
		self._deskCards[slot] = deskCard
		self._deskTags[slot] = tag(deskCard, "Tag", `WORKSTATION {slot} · MEJA KERJA`, Theme.Colors.Sage)
		local deskTitle = body(deskCard, "Title", `Worker Desk {slot}`, 18, 20)
		deskTitle.Font = Theme.Fonts.Black
		deskTitle.TextSize = Theme.TextSizes.Subtitle
		local deskPrice = body(deskCard, "Price", `Price: {DESK_PRICES[slot]} Cuan`, 42, 18)
		deskPrice.TextColor3 = Theme.Colors.Amber
		local deskPrereq = if slot == 1
			then "Prerequisites: PC Rumah equipped · Tier 1 (300 Lifetime Cuan + 3 Claims)"
			else "Prerequisites: PC Rumah · Tier 2 (1600 Lifetime Cuan + 3 Claims) · Desk 1 + Trainee 1"
		local deskDesc = body(deskCard, "Desc", `Dedicated timber workstation for 1 trainee assistant.\n{deskPrereq}`, 64, 42)
		deskDesc.TextColor3 = Theme.Colors.CreamMuted
		self._deskStatuses[slot] = body(deskCard, "Status", "Loading status...", 110, 18)
		self._deskStatuses[slot].Font = Theme.Fonts.Bold
		self._deskStatuses[slot].TextColor3 = Theme.Colors.Amber

		self._deskButtons[slot] = Composer.button(self.Root, `BuyDesk{slot}`, `Purchase Worker Desk {slot} · {DESK_PRICES[slot]} Cuan`, function()
			self:BuyDesk(slot)
		end)

		local traineeCard = card(self.Root, `Trainee{slot}Card`, 170)
		self._traineeCards[slot] = traineeCard
		self._traineeTags[slot] = tag(traineeCard, "Tag", `STAFF {slot} · ASISTEN MAGANG`, Theme.Colors.Sage)
		local traineeTitle = body(traineeCard, "Title", `Trainee Assistant {slot}`, 18, 20)
		traineeTitle.Font = Theme.Fonts.Black
		traineeTitle.TextSize = Theme.TextSizes.Subtitle
		local traineePrice = body(traineeCard, "Price", `Hiring fee: {HIRE_PRICES[slot]} Cuan`, 42, 18)
		traineePrice.TextColor3 = Theme.Colors.Amber
		local traineePrereq = if slot == 1
			then "Prerequisites: Worker Desk 1 Owned · Tier 1"
			else "Prerequisites: Worker Desk 2 Owned · Tier 2 · Trainee 1 on duty"
		local traineeDesc = body(traineeCard, "Desc", `Produces +{WORKER_RATE} Cuan/second while connected online.\n{traineePrereq}`, 64, 42)
		traineeDesc.TextColor3 = Theme.Colors.CreamMuted
		self._traineeStatuses[slot] = body(traineeCard, "Status", "Loading status...", 110, 18)
		self._traineeStatuses[slot].Font = Theme.Fonts.Bold
		self._traineeStatuses[slot].TextColor3 = Theme.Colors.Amber

		self._traineeButtons[slot] = Composer.button(self.Root, `HireTrainee{slot}`, `Hire Trainee Assistant {slot} · {HIRE_PRICES[slot]} Cuan`, function()
			self:HireWorker(slot)
		end)
	end

	self._notice = Composer.label(self.Root, "WorkersNotice", "", 14, Theme.Colors.CreamMuted)
	self._refresh = Composer.button(self.Root, "RefreshWorkers", "Refresh confirmed progress", function()
		self._onAction("GetSnapshot", {})
	end)
	self._refresh.BackgroundColor3 = Theme.Colors.CharcoalLight
	self._refresh.TextColor3 = Theme.Colors.Cream

	return self
end

function Workers:BuyDesk(slotIndex: number)
	local button = self._deskButtons[slotIndex]
	if button == nil or not button.Active then return end
	local proj = self._projected
	if proj == nil or proj.deskPhase[slotIndex] ~= "affordable" then return end
	self._onAction("BuyDesk", { slotIndex = slotIndex })
end

function Workers:HireWorker(slotIndex: number)
	local button = self._traineeButtons[slotIndex]
	if button == nil or not button.Active then return end
	local proj = self._projected
	if proj == nil or proj.traineePhase[slotIndex] ~= "affordable" then return end
	self._onAction("HireWorker", { slotIndex = slotIndex, roleId = "trainee" })
end

local DESK_STATUS_COPY: { [string]: (WorkersState, number) -> (string, Color3, string) } = {
	loading = function(_proj, _slot)
		return "Waiting for the first confirmed progress snapshot...", Theme.Colors.CreamMuted, "LOADING"
	end,
	owned = function(proj, slot)
		return `INSTALLED · WORKSTATION {slot} ACTIVE`, Theme.Colors.Lime, `OWNED · INSTALLED`
	end,
	purchasing = function(_proj, _slot)
		return "Saving purchase... waiting for server confirmation.", Theme.Colors.Amber, "PROCESSING"
	end,
	saveUnavailable = function(_proj, _slot)
		return "Server storage is not accepting saves. Use Refresh once the save recovers.", Theme.Colors.Amber, "SAVE UNAVAILABLE"
	end,
	need_pc = function(_proj, _slot)
		return "Requires PC Rumah production terminal.", Theme.Colors.Amber, "LOCKED · NEEDS PC RUMAH"
	end,
	need_tier = function(proj, slot)
		local need = if slot == 1 then "Tier 1 (300 Lifetime Cuan + 3 Mission Claims)" else "Tier 2 (1600 Lifetime Cuan + 3 Mission Claims)"
		return `Requires {need}.`, Theme.Colors.Amber, `LOCKED · NEEDS TIER {slot}`
	end,
	need_first_desk = function(_proj, slot)
		return `Requires Worker Desk {slot - 1} to be purchased first.`, Theme.Colors.Amber, `LOCKED · NEEDS DESK {slot - 1}`
	end,
	need_first_worker = function(_proj, slot)
		return `Requires Trainee {slot - 1} to be hired first.`, Theme.Colors.Amber, `LOCKED · NEEDS TRAINEE {slot - 1}`
	end,
	locked = function(proj, slot)
		return `Need {Theme.formatNumber(proj.deskRemaining[slot])} more Cuan (Price: {DESK_PRICES[slot]}).`, Theme.Colors.Amber, "LOCKED · INSUFFICIENT CUAN"
	end,
	affordable = function(_proj, slot)
		return `Ready to build · {DESK_PRICES[slot]} Cuan`, Theme.Colors.Lime, "AVAILABLE TO PURCHASE"
	end,
}

local TRAINEE_STATUS_COPY: { [string]: (WorkersState, number) -> (string, Color3, string) } = {
	loading = function(_proj, _slot)
		return "Waiting for the first confirmed progress snapshot...", Theme.Colors.CreamMuted, "LOADING"
	end,
	hired = function(_proj, slot)
		return `ON DUTY · ACCRUING +{WORKER_RATE} CUAN/S`, Theme.Colors.Lime, "HIRED · ON DUTY"
	end,
	purchasing = function(_proj, _slot)
		return "Saving hire... waiting for server confirmation.", Theme.Colors.Amber, "PROCESSING"
	end,
	saveUnavailable = function(_proj, _slot)
		return "Server storage is not accepting saves. Use Refresh once the save recovers.", Theme.Colors.Amber, "SAVE UNAVAILABLE"
	end,
	need_pc = function(_proj, _slot)
		return "Requires PC Rumah production terminal.", Theme.Colors.Amber, "LOCKED · NEEDS PC RUMAH"
	end,
	need_desk = function(_proj, slot)
		return `Requires Worker Desk {slot} to be purchased first.`, Theme.Colors.Amber, `LOCKED · NEEDS DESK {slot}`
	end,
	need_tier = function(_proj, slot)
		local need = if slot == 1 then "Tier 1 (300 Lifetime Cuan + 3 Mission Claims)" else "Tier 2 (1600 Lifetime Cuan + 3 Mission Claims)"
		return `Requires {need}.`, Theme.Colors.Amber, `LOCKED · NEEDS TIER {slot}`
	end,
	need_first_worker = function(_proj, slot)
		return `Requires Trainee {slot - 1} to be hired first.`, Theme.Colors.Amber, `LOCKED · NEEDS TRAINEE {slot - 1}`
	end,
	locked = function(proj, slot)
		return `Need {Theme.formatNumber(proj.traineeRemaining[slot])} more Cuan (Price: {HIRE_PRICES[slot]}).`, Theme.Colors.Amber, "LOCKED · INSUFFICIENT CUAN"
	end,
	affordable = function(_proj, slot)
		return `Ready to hire · {HIRE_PRICES[slot]} Cuan (+{WORKER_RATE} Cuan/s)`, Theme.Colors.Lime, "AVAILABLE TO HIRE"
	end,
}

function Workers:Update(stateData: any)
	self._state = stateData
	local proj = Workers.projectState(stateData)
	self._projected = proj

	-- Home Studio chapter progress
	for _, key in ipairs(CHAPTER_ORDER) do
		local label = self._chapterSteps[key]
		if label ~= nil then
			local done = proj.chapter[key] == true
			label.Text = `{CHAPTER_LABELS[key]}{if done then "  ✓" else ""}`
			label.TextColor3 = if done then Theme.Colors.Lime else Theme.Colors.CreamMuted
		end
	end
	if proj.chapterComplete then
		self._chapterTitle.Text = "STUDIO RUMAHAN · HOME STUDIO COMPLETE"
		self._chapterTitle.TextColor3 = Theme.Colors.Lime
		self._chapterTag.Text = "M1 CHAPTER COMPLETE"
		self._chapterTag.TextColor3 = Theme.Colors.Lime
	else
		self._chapterTitle.Text = `Home Studio Progress {proj.chapterDoneCount} / {#CHAPTER_ORDER}`
		self._chapterTitle.TextColor3 = Theme.Colors.Cream
		self._chapterTag.Text = "M1 CHAPTER · STUDIO RUMAHAN"
		self._chapterTag.TextColor3 = Theme.Colors.Amber
	end

	-- Overview stats: confirmed staffed count and server-confirmed rates only.
	self._overviewStats.Text = string.format(
		"Trainees: %d / %d · Online rate: +%.1f Cuan/s\nUnbanked accrual: %s Cuan (not spendable) · Confirmed balance: %s Cuan",
		proj.workersHired,
		MAX_WORKER_SLOTS,
		proj.incomePerSecond,
		Theme.formatNumber(proj.pendingWorkerCuan),
		Theme.formatNumber(proj.balance)
	)

	local blockReason = self._getBlockReason and self._getBlockReason() or nil

	for slot in ipairs(SLOTS) do
		-- Desk card
		local deskBtnEnabled = false
		local deskBtnText = `Purchase Worker Desk {slot} · {DESK_PRICES[slot]} Cuan`
		local statusLabel = self._deskStatuses[slot]
		local copier = DESK_STATUS_COPY[proj.deskPhase[slot]]
		if copier ~= nil then
			local text, color, tagText = copier(proj, slot)
			statusLabel.Text = text
			statusLabel.TextColor3 = color
			self._deskTags[slot].Text = tagText
			if proj.deskPhase[slot] == "owned" then
				deskBtnText = `Workstation {slot} Installed`
			elseif proj.deskPhase[slot] == "purchasing" then
				deskBtnText = "Saving Desk Purchase..."
			elseif proj.deskPhase[slot] == "affordable" then
				deskBtnEnabled = true
			end
		else
			statusLabel.Text = "Loading workstation status..."
			statusLabel.TextColor3 = Theme.Colors.CreamMuted
			self._deskTags[slot].Text = "LOADING"
		end
		Composer.setEnabled(self._deskButtons[slot], deskBtnEnabled and blockReason == nil)
		self._deskButtons[slot].Text = deskBtnText

		-- Trainee card
		local traineeBtnEnabled = false
		local traineeBtnText = `Hire Trainee Assistant {slot} · {HIRE_PRICES[slot]} Cuan`
		local traineeLabel = self._traineeStatuses[slot]
		local traineeCopier = TRAINEE_STATUS_COPY[proj.traineePhase[slot]]
		if traineeCopier ~= nil then
			local text, color, tagText = traineeCopier(proj, slot)
			traineeLabel.Text = text
			traineeLabel.TextColor3 = color
			self._traineeTags[slot].Text = tagText
			if proj.traineePhase[slot] == "hired" then
				traineeBtnText = `Trainee {slot} on Duty (+{WORKER_RATE} Cuan/s)`
			elseif proj.traineePhase[slot] == "purchasing" then
				traineeBtnText = "Saving Trainee Hire..."
			elseif proj.traineePhase[slot] == "affordable" then
				traineeBtnEnabled = true
			end
		else
			traineeLabel.Text = "Loading staffing status..."
			traineeLabel.TextColor3 = Theme.Colors.CreamMuted
			self._traineeTags[slot].Text = "LOADING"
		end
		Composer.setEnabled(self._traineeButtons[slot], traineeBtnEnabled and blockReason == nil)
		self._traineeButtons[slot].Text = traineeBtnText
	end

	-- Notice: completion message supersedes the standing banking reminder.
	if proj.chapterComplete then
		self._notice.Text = "HOME STUDIO COMPLETE · The M1 studio chapter is done. Trainees keep working while you are online; organic posting and missions remain available. Further expansion is not yet available."
	elseif blockReason ~= nil then
		self._notice.Text = blockReason
	elseif stateData ~= nil and stateData.activeError ~= nil then
		self._notice.Text = stateData.activeError
	else
		self._notice.Text = "Server-reported pending accrual is not spendable. Banking is attempted every 30 connected seconds (or with a saved action); only confirmed saves increase balance."
	end

	self:_animateConfirmations(proj)
end

function Workers:_animateConfirmations(proj: WorkersState)
	for slot in ipairs(SLOTS) do
		local deskPhase = proj.deskPhase[slot]
		local hirePhase = proj.traineePhase[slot]
		if self._lastDeskPhase[slot] == "purchasing" and deskPhase == "owned" then
			Theme.applyStroke(self._deskCards[slot], Theme.Colors.Lime, 2)
			task.delay(1.2, function()
				if self._deskCards[slot].Parent ~= nil then
					Theme.applyStroke(self._deskCards[slot], Theme.Colors.Border, 1)
				end
			end)
		end
		if self._lastHirePhase[slot] == "purchasing" and hirePhase == "hired" then
			Theme.applyStroke(self._traineeCards[slot], Theme.Colors.Lime, 2)
			task.delay(1.2, function()
				if self._traineeCards[slot].Parent ~= nil then
					Theme.applyStroke(self._traineeCards[slot], Theme.Colors.Border, 1)
				end
			end)
		end
		self._lastDeskPhase[slot] = deskPhase
		self._lastHirePhase[slot] = hirePhase
	end

	-- Chapter completion highlight: static lime stroke after the final hire.
	-- No pulsing or movement: safe under reduced-motion requirements.
	if not self._lastChapterComplete and proj.chapterComplete and self._chapterCard.Parent ~= nil then
		Theme.applyStroke(self._chapterCard, Theme.Colors.Lime, 2)
		task.delay(1.6, function()
			if self._chapterCard.Parent ~= nil then
				Theme.applyStroke(self._chapterCard, Theme.Colors.Border, 1)
			end
		end)
	end
	self._lastChapterComplete = proj.chapterComplete
end

function Workers:Tick(_serverNow: number) end

function Workers:Destroy()
	self.Root:Destroy()
end

Workers.DESK_1_PRICE = DESK_PRICES[1]
Workers.TRAINEE_1_PRICE = HIRE_PRICES[1]
Workers.DESK_2_PRICE = DESK_PRICES[2]
Workers.TRAINEE_2_PRICE = HIRE_PRICES[2]
Workers.WORKER_1_RATE = WORKER_RATE
Workers.CHAPTER_ORDER = CHAPTER_ORDER
Workers.chapterProgress = Workers.chapterProgress

return Workers
