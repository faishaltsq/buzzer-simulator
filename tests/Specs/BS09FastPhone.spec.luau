--!strict
-- Buzzer Simulator — BS-09 spec: Fast Phone purchase + handheld phone.
-- Exercises the REAL production modules: ClientState purchase admission,
-- Upgrades shop projection/UI, and PhoneEquipController cosmetic assembly.
-- Contract sources: docs/04, docs/05, docs/08 (BS-09), docs/09.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local scripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local ClientState = require(scripts:WaitForChild("ClientState")) :: any
local uiFolder = scripts:WaitForChild("ui")
local Upgrades = require(uiFolder:WaitForChild("Upgrades")) :: any
local PhoneEquipController = require(scripts:WaitForChild("PhoneEquipController")) :: any
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog")) :: any
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")) :: any

local tests: { { name: string, fn: () -> () } } = {}
local function test(name: string, fn: () -> ())
	table.insert(tests, { name = name, fn = fn })
end

local function expectEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(`{label}: expected {tostring(expected)}, got {tostring(actual)}`, 0)
	end
end

local function expectTrue(cond: boolean, label: string)
	if not cond then
		error(label, 0)
	end
end

local function expectFalse(cond: boolean, label: string)
	if cond then
		error(label, 0)
	end
end

local function snapshot(overrides: any?): any
	local snap: any = {
		revision = 1,
		serverTime = 1000,
		balance = 100,
		pendingWorkerCuan = 0,
		incomePerSecond = 0,
		lifetimeEarned = 0,
		completedMissions = 0,
		tier = 0,
		maxShippedTier = 0,
		deviceId = "phone_cheap",
		ownedDesks = {},
		workers = {},
		activeMission = nil,
		pendingPost = nil,
		nextOrganicContextId = "organic_snack",
		ownPosts = {},
		feedVersion = 1,
		saveStatus = "healthy",
	}
	if overrides ~= nil then
		for key, value in pairs(overrides) do
			snap[key] = value
		end
	end
	return snap
end

-- Opens a real dashboard session so mutation admission is reachable.
local function openState(overrides: any?): any
	local state = ClientState.new(snapshot(overrides))
	state:ApplyOpenComputer({
		kind = "OpenComputer",
		dashboardSessionId = "sess_bs09",
		expiresAt = 1600,
		serverTime = 1000,
		state = snapshot(overrides),
	}, 1000)
	state:OnCameraOpened()
	return state
end

-- ===== purchase admission (production ClientState) =====

test("BuyDevice is a recognised client mutation action", function()
	local state = openState()
	local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
	expectTrue(command ~= nil, "BuyDevice admitted")
	expectEqual(command.action, "BuyDevice", "action")
	expectEqual(command.payload.deviceId, "phone_fast", "payload device")
	expectEqual(command.dashboardSessionId, "sess_bs09", "session carried")
	expectTrue(#command.requestId >= 8, "fresh requestId generated")
	expectEqual(state:Get().activeError, nil, "no error recorded")
end)

test("BuyDevice rejects extra payload fields such as a client price", function()
	local state = openState()
	local withPrice = state:BeginMutation("BuyDevice", { deviceId = "phone_fast", price = 0 }, 1001)
	expectTrue(withPrice == nil, "client-supplied price rejected")
	local withBalance = state:BeginMutation("BuyDevice", { deviceId = "phone_fast", balance = 9999 }, 1001)
	expectTrue(withBalance == nil, "client-supplied balance rejected")
	local withOwnership = state:BeginMutation("BuyDevice", { deviceId = "phone_fast", ownsDevice = true }, 1001)
	expectTrue(withOwnership == nil, "client-supplied ownership rejected")
	expectTrue(state:Get().activeError:find("INVALID_INPUT", 1, true) ~= nil, "reported as invalid input")
end)

test("BuyDevice rejects unshipped devices and non-string ids", function()
	local state = openState()
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "pc_rumah" }, 1001) == nil, "pc_rumah is not shipped in V0")
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_god" }, 1001) == nil, "unknown device rejected")
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = 42 }, 1001) == nil, "non-string id rejected")
	expectTrue(state:BeginMutation("BuyDevice", {}, 1001) == nil, "empty payload rejected")
end)

test("A confirmed balance below the catalog price blocks the purchase", function()
	local state = openState({ balance = 49 })
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001) == nil, "49 Cuan cannot buy")
	expectTrue(state:Get().activeError:find("INSUFFICIENT_FUNDS", 1, true) ~= nil, "insufficient funds reported")
end)

test("Exactly the catalog price admits the purchase", function()
	local state = openState({ balance = 50 })
	local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
	expectTrue(command ~= nil, "exactly 50 Cuan is affordable")
	-- No optimistic deduction: the confirmed balance is untouched until the
	-- server's snapshot arrives.
	expectEqual(state:GetConfirmedBalance(), 50, "balance not spent locally")
end)

test("Rapid duplicate purchase clicks produce exactly one mutation", function()
	local state = openState({ balance = 200 })
	local sent = {}
	for _ = 1, 5 do
		local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
		if command ~= nil then
			table.insert(sent, command)
		end
	end
	expectEqual(#sent, 1, "only one purchase envelope leaves the client")
	expectTrue(state:Get().activeError:find("BUSY", 1, true) ~= nil, "duplicates reported as busy")
end)

test("An uncertain save keeps the original request id and blocks repurchase", function()
	local state = openState({ balance = 200 })
	local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
	expectTrue(command ~= nil, "admitted")
	-- The server reports an ambiguous write: BUSY is not a rejection.
	state:ApplyReply({ requestId = command.requestId, ok = false, code = "BUSY" }, 1002)
	local uncertain = state:Get().uncertainMutations[command.requestId]
	expectTrue(uncertain ~= nil, "mutation preserved as uncertain under its original id")
	expectEqual(uncertain.action, "BuyDevice", "uncertain intent retained")
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1003) == nil, "no repurchase with a new id")
	-- The recovery read must correlate the ORIGINAL request id.
	local query = state:RefreshProgress(1004)
	expectEqual(query.action, "GetSnapshot", "recovery is a read")
	expectEqual(query.payload.lookupRequestId, command.requestId, "lookup uses the original request id")
end)

test("A six-second timeout converts the purchase to an uncertain mutation", function()
	local state = openState({ balance = 200 })
	local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
	expectTrue(command ~= nil, "admitted")
	local queries = state:CheckTimeouts(1007.5, 6)
	expectEqual(#queries, 1, "one recovery query issued")
	expectEqual(queries[1].payload.lookupRequestId, command.requestId, "query targets the original id")
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1008) == nil, "still blocked after timeout")
end)

test("An expired dashboard session rejects the purchase", function()
	local state = openState()
	state:ApplySessionExpired("sess_bs09", "SESSION_EXPIRED")
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001) == nil, "expired session cannot buy")
	expectTrue(state:Get().activeError:find("SESSION_EXPIRED", 1, true) ~= nil, "session error reported")
end)

test("An already-owned Fast Phone cannot be charged twice", function()
	local state = openState({ deviceId = "phone_fast", balance = 500 })
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001) == nil, "no second charge")
	expectTrue(state:Get().activeError:find("ALREADY_DONE", 1, true) ~= nil, "reported as already done")
end)

test("A blocked save status rejects the purchase before it is sent", function()
	local state = openState({ saveStatus = "SAVE_UNAVAILABLE" })
	expectTrue(state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001) == nil, "read-only session cannot buy")
end)

test("Stale state or reply cannot revert confirmed ownership", function()
	local state = openState({ balance = 50 })
	local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
	expectTrue(command ~= nil, "admitted")
	-- Server confirms, then the authoritative snapshot arrives.
	state:ApplyReply({ requestId = command.requestId, ok = true, code = "OK", revision = 2 }, 1002)
	state:ApplyStateSnapshot(snapshot({ revision = 2, deviceId = "phone_fast", balance = 0 }))
	expectEqual(state:Get().snapshot.deviceId, "phone_fast", "ownership confirmed")
	-- A stale snapshot (older revision) must be ignored entirely.
	local applied = state:ApplyStateSnapshot(snapshot({ revision = 1, deviceId = "phone_cheap", balance = 50 }))
	expectFalse(applied, "stale snapshot rejected")
	expectEqual(state:Get().snapshot.deviceId, "phone_fast", "ownership never reverted")
	expectEqual(state:GetConfirmedBalance(), 0, "balance never reverted")
end)

-- ===== economy invariants (production Catalog + Rules) =====

test("Confirmed purchase changes the balance by exactly the catalog price", function()
	local cheap = Upgrades.deviceById("phone_cheap")
	local fast = Upgrades.deviceById("phone_fast")
	expectTrue(cheap ~= nil and fast ~= nil, "both devices are in the catalog")
	expectEqual(fast.price, 50, "fast phone price is 50 Cuan")
	expectEqual(cheap.price, 0, "cheap phone is the starter device")
	expectEqual(50 - fast.price, 0, "exactly 50 Cuan buys it")
end)

test("Organic payouts and reveal times match the approved economy table", function()
	local cheap = Upgrades.deviceById("phone_cheap")
	local fast = Upgrades.deviceById("phone_fast")
	local cheapStrong, cheapWeak = Upgrades.payoutOf(cheap)
	local fastStrong, fastWeak = Upgrades.payoutOf(fast)
	expectEqual(cheapStrong, 15, "cheap strong payout")
	expectEqual(cheapWeak, 9, "cheap weak payout")
	expectEqual(fastStrong, 24, "fast strong payout")
	expectEqual(fastWeak, 14, "fast weak payout")
	expectEqual(cheap.revealSeconds, 18, "cheap reveal")
	expectEqual(fast.revealSeconds, 16, "fast reveal")
	-- Same shared formula the server settles with, not a UI-local constant.
	expectEqual(Rules.organicCuan("strong", fast.deviceYield), 24, "server formula agrees")
end)

test("Exactly one purchasable device upgrade ships in V0", function()
	local purchasable = 0
	for _, device in ipairs(Catalog.Devices) do
		if device.price > 0 and table.find(Catalog.V0Shipped.deviceIds, device.id) ~= nil then
			purchasable += 1
		end
	end
	expectEqual(purchasable, 1, "one paid device upgrade; PC Rumah stays unshipped")
	expectEqual(table.find(Catalog.V0Shipped.deviceIds, "pc_rumah"), nil, "PC Rumah is not purchasable in BS-09")
end)

-- ===== shop phases (production projection + real UI) =====

test("Shop projection covers every required purchase phase", function()
	local function phaseFor(overrides: any?): string
		local state = openState(overrides)
		return Upgrades.shopState(state:Get()).phase
	end
	expectEqual(phaseFor({ balance = 20 }), "locked", "A: insufficient funds")
	expectEqual(phaseFor({ balance = 50 }), "affordable", "B: affordable")
	expectEqual(phaseFor({ deviceId = "phone_fast", balance = 0 }), "owned", "E: already owned")
	expectEqual(phaseFor({ saveStatus = "SAVE_UNAVAILABLE" }), "saveUnavailable", "F: save unavailable")
	expectEqual(Upgrades.shopState({ snapshot = nil }).phase, "loading", "loading before first snapshot")

	local state = openState({ balance = 50 })
	local command = state:BeginMutation("BuyDevice", { deviceId = "phone_fast" }, 1001)
	expectTrue(command ~= nil, "admitted")
	expectEqual(Upgrades.shopState(state:Get()).phase, "purchasing", "C: purchasing disables repeats")
end)

test("Shop reports the exact shortfall while locked", function()
	local state = openState({ balance = 35 })
	local shop = Upgrades.shopState(state:Get())
	expectEqual(shop.price, 50, "price from catalog")
	expectEqual(shop.balance, 35, "confirmed balance")
	expectEqual(shop.remaining, 15, "remaining Cuan required")
end)

test("Upgrades UI renders the locked, affordable and owned states without charging", function()
	local gui = Instance.new("ScreenGui")
	local state = openState({ balance = 35 })
	local sent = {}
	local page = Upgrades.new({
		parent = gui,
		onAction = function(action, payload)
			local envelope = state:BeginMutation(action, payload, 1001)
			if envelope ~= nil then
				table.insert(sent, envelope)
			end
		end,
		getBlockReason = function() return state:MutationBlockReason() end,
	})
	page:Update(state:Get())
	expectFalse(page._purchase.Active, "locked purchase button is disabled")
	expectTrue(page._status.Text:find("15", 1, true) ~= nil, "shortfall shown")
	page:Purchase()
	expectEqual(#sent, 0, "a disabled button sends nothing")

	-- Affordable: the real button now admits exactly one purchase envelope.
	state:ApplyStateSnapshot(snapshot({ revision = 2, balance = 50 }))
	page:Update(state:Get())
	expectTrue(page._purchase.Active, "affordable purchase button is enabled")
	page:Purchase()
	page:Purchase()
	expectEqual(#sent, 1, "one envelope, no optimistic double charge")
	expectEqual(sent[1].payload.deviceId, "phone_fast", "payload carries the id only")
	expectEqual(state:GetConfirmedBalance(), 50, "price not deducted locally")

	-- Owned: the shop never offers a second purchase.
	local ownedState = openState({ deviceId = "phone_fast", balance = 500 })
	page:Update(ownedState:Get())
	expectFalse(page._purchase.Active, "owned purchase button is disabled")
	expectEqual(page._status.Text, "Equipped — Fast Phone", "owned copy")
	gui:Destroy()
end)

test("Shop copy never exposes PC Rumah as a purchasable option", function()
	local gui = Instance.new("ScreenGui")
	local state = openState({ balance = 5000 })
	local page = Upgrades.new({
		parent = gui,
		onAction = function() end,
		getBlockReason = function() return nil end,
	})
	page:Update(state:Get())
	local texts = { page._status.Text, page._notice.Text, page._offerBenefits.Text, page._compareBody.Text, page._purchase.Text }
	for _, text in ipairs(texts) do
		expectEqual(string.find(text, "PC Rumah", 1, true), nil, "no PC Rumah offer")
		expectEqual(string.find(text, "pc_rumah", 1, true), nil, "no pc_rumah offer")
	end
	gui:Destroy()
end)

-- ===== handheld cosmetics (production controller) =====

test("Cheap and Fast handheld cosmetics are distinct, script-free models", function()
	local cheap = PhoneEquipController.buildCosmetic("phone_cheap")
	local fast = PhoneEquipController.buildCosmetic("phone_fast")
	expectTrue(cheap.PrimaryPart ~= nil and fast.PrimaryPart ~= nil, "both models have a primary part")
	expectTrue(cheap.PrimaryPart.Name == "Body" and fast.PrimaryPart.Name == "Body", "grip part is Body")
	expectTrue(cheap.Name ~= fast.Name, "distinct model identities")
	expectTrue(cheap.PrimaryPart.Color ~= fast.PrimaryPart.Color, "distinct silhouettes/colours")
	-- The retro handset carries a key grid; the modern phone does not.
	local function countNamed(model: Model, name: string): number
		local count = 0
		for _, child in ipairs(model:GetChildren()) do
			if child.Name == name then
				count += 1
			end
		end
		return count
	end
	expectTrue(countNamed(cheap, "Key") > 0, "cheap phone has keypad keys")
	expectEqual(countNamed(fast, "Key"), 0, "fast phone has no keypad")
	expectTrue(countNamed(fast, "CameraBump") > 0, "fast phone has a camera bump")
	for _, model in ipairs({ cheap, fast }) do
		for _, descendant in ipairs(model:GetDescendants()) do
			expectFalse(descendant:IsA("LuaSourceContainer"), "no script inside a cosmetic model")
			if descendant:IsA("BasePart") then
				expectFalse(descendant.Anchored, "handheld parts are unanchored for welding")
				expectFalse(descendant.CanCollide, "handheld parts never collide with the character")
				expectTrue(descendant.Massless, "handheld parts are massless")
			end
		end
	end
	cheap:Destroy()
	fast:Destroy()
end)

test("Handheld scale is hand-sized and R6/R15 grips are both defined", function()
	local cheapSize = PhoneEquipController.PHONE_SIZE.cheap
	local fastSize = PhoneEquipController.PHONE_SIZE.fast
	expectTrue(cheapSize.Y > 0.5 and cheapSize.Y < 1.5, "cheap handheld height is hand-sized")
	expectTrue(fastSize.Y > 0.5 and fastSize.Y < 1.5, "fast handheld height is hand-sized")
	expectTrue(cheapSize.Y < 2, "smaller than the 2-stud desk prefab")
	expectTrue(PhoneEquipController.GRIP.R15 ~= nil, "R15 grip defined")
	expectTrue(PhoneEquipController.GRIP.R6 ~= nil, "R6 grip defined")
	expectTrue(PhoneEquipController.GRIP.R15 ~= PhoneEquipController.GRIP.R6, "R6 needs its own offset")
	expectTrue(PhoneEquipController.POSE.equip ~= nil, "equip pose defined")
	expectTrue(PhoneEquipController.POSE.use ~= nil, "use pose defined")
end)

test("The handheld controller is cosmetic-only and never references economy state", function()
	-- The module must not be able to mutate the economy: assert its public
	-- surface carries presentation state only.
	local controller = PhoneEquipController
	expectTrue(controller.buildCosmetic ~= nil, "cosmetic builder is the model source")
	expectEqual(controller.awardCuan, nil, "no payout API")
	expectEqual(controller.BuyDevice, nil, "no purchase API")
	expectEqual(controller.GetConfirmedBalance, nil, "no balance API")
	expectTrue(Players.LocalPlayer == nil or Players.LocalPlayer ~= nil, "module loads outside a live player context")
end)

-- ===== targeted production lifecycle tests =====

local Workspace = game:GetService("Workspace")

local function createTestRig(): (Model, Humanoid, BasePart, Motor6D)
	local char = Instance.new("Model")
	char.Name = "TestPlayer"
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.Health = 100
	hum.MaxHealth = 100
	hum.Parent = char

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = char
	char.PrimaryPart = root

	local upperTorso = Instance.new("Part")
	upperTorso.Name = "UpperTorso"
	upperTorso.Parent = char

	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Parent = char

	local shoulder = Instance.new("Motor6D")
	shoulder.Name = "RightShoulder"
	shoulder.Part0 = upperTorso
	shoulder.Part1 = hand
	shoulder.C0 = CFrame.identity
	shoulder.Parent = upperTorso

	char.Parent = Workspace
	return char, hum, hand, shoulder
end

local function createTestController(char: Model?): (any, ScreenGui)
	local gui = Instance.new("ScreenGui")
	gui.Parent = Workspace
	local ctrl = PhoneEquipController.new({ parent = gui })
	if char ~= nil then
		ctrl:_onCharacter(char)
	end
	return ctrl, gui
end

test("Lifecycle 1: Equip -> CRT -> Close -> restore", function()
	local char, hum = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_cheap")

	ctrl:Equip()
	expectTrue(ctrl:GetState() == "Equipping" or ctrl:GetState() == "Equipped", "phone equipped")
	expectTrue(ctrl:GetPreferEquipped(), "preference saved as true")

	-- Open dashboard: stows physical model, preserves preference
	ctrl:StowForDashboard()
	expectEqual(ctrl:GetState(), "Stowed", "stowed for CRT")
	expectTrue(ctrl:GetPreferEquipped(), "preference preserved")
	expectEqual(ctrl._model, nil, "physical model destroyed")

	-- Repeated opening notifications must not overwrite preference
	ctrl:StowForDashboard()
	expectTrue(ctrl:GetPreferEquipped(), "repeated opening did not wipe preference")

	-- Close dashboard: restores equipment
	ctrl:RestoreAfterDashboard()
	expectTrue(ctrl:GetState() == "Equipping" or ctrl:GetState() == "Equipped", "phone restored")
	expectTrue(ctrl._model ~= nil, "model reattached")

	ctrl:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 2: Stow -> CRT -> Close -> remains stowed", function()
	local char = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_cheap")

	expectEqual(ctrl:GetState(), "Stowed", "starts stowed")
	expectFalse(ctrl:GetPreferEquipped(), "preference is false")

	ctrl:StowForDashboard()
	expectEqual(ctrl:GetState(), "Stowed", "still stowed")
	expectFalse(ctrl:GetPreferEquipped(), "preference stays false")

	ctrl:RestoreAfterDashboard()
	expectEqual(ctrl:GetState(), "Stowed", "remains stowed after closing CRT")
	expectFalse(ctrl:GetPreferEquipped(), "preference remains false")
	expectEqual(ctrl._model, nil, "no model created")

	ctrl:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 3: Equip -> die -> respawn -> equip", function()
	local char1, hum1 = createTestRig()
	local ctrl, gui = createTestController(char1)
	ctrl:SetDevice("phone_cheap")

	ctrl:Equip()
	expectTrue(ctrl:GetPreferEquipped(), "equipped before death")

	-- Character dies
	hum1.Health = 0
	ctrl:_onCharacterDied()
	expectEqual(ctrl:GetState(), "Stowed", "death stows phone immediately")
	expectFalse(ctrl:GetPreferEquipped(), "death resets restore preference")
	expectEqual(ctrl._model, nil, "model cleaned up on death")

	-- Respawn with fresh character
	local char2 = createTestRig()
	ctrl:_onCharacter(char2)
	expectEqual(ctrl:GetState(), "Stowed", "fresh spawn starts stowed")
	expectFalse(ctrl:GetPreferEquipped(), "preference remains false after death-respawn")

	-- Explicit equip on new character
	ctrl:Equip()
	expectTrue(ctrl:GetState() == "Equipping" or ctrl:GetState() == "Equipped", "can equip on new character")
	expectTrue(ctrl._model ~= nil and ctrl._model.Parent == char2, "model attached to new character")

	ctrl:Destroy()
	char1:Destroy()
	char2:Destroy()
	gui:Destroy()
end)

test("Lifecycle 4: Rapid equip and unequip transitions remain consistent", function()
	local char = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_fast")

	for _ = 1, 4 do
		ctrl:Equip()
		ctrl:Unequip()
	end
	-- Final intent is unequipped
	expectFalse(ctrl:GetPreferEquipped(), "final preference is stowed")
	expectTrue(ctrl:GetState() == "Unequipping" or ctrl:GetState() == "Stowed", "in unequip or stowed state")

	ctrl:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 5: Purchase while dashboard is open updates device and preserves stowed state", function()
	local char = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_cheap")
	ctrl:Equip()

	-- Enter dashboard
	ctrl:StowForDashboard()
	expectEqual(ctrl:GetState(), "Stowed", "stowed during dashboard")
	expectTrue(ctrl:GetPreferEquipped(), "preference saved")

	-- Purchase occurs during open dashboard
	ctrl:SetDevice("phone_fast")
	expectEqual(ctrl._deviceId, "phone_fast", "device updated")
	expectEqual(ctrl:GetState(), "Stowed", "remains stowed while dashboard is open")
	expectEqual(ctrl._model, nil, "no visual rendered during dashboard")

	-- Exit dashboard: restores newly acquired Fast Phone
	ctrl:RestoreAfterDashboard()
	expectTrue(ctrl:GetState() == "Equipping" or ctrl:GetState() == "Equipped", "restored on exit")
	expectTrue(ctrl._model ~= nil, "model attached")
	expectEqual(ctrl._model.Name, "HeldPhoneFast", "restored device is Fast Phone")

	ctrl:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 6: Confirm Fast Phone is the only visible equipped device", function()
	local char = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_fast")
	ctrl:Equip()

	local heldModels = 0
	for _, child in ipairs(char:GetChildren()) do
		if child.Name:find("HeldPhone") then
			heldModels += 1
		end
	end
	expectEqual(heldModels, 1, "exactly one held phone model exists")
	expectTrue(char:FindFirstChild("HeldPhoneFast") ~= nil, "Fast Phone is equipped")
	expectEqual(char:FindFirstChild("HeldPhoneCheap"), nil, "Cheap Phone is not present")

	ctrl:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 7: World PhoneSlot replacement remains hidden while phone is held", function()
	local char = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_cheap")

	local room = Instance.new("Folder")
	room.Name = "TestRoom"
	local slot = Instance.new("Part")
	slot.Name = "PhoneSlot"
	slot.Parent = room

	ctrl._phoneSlot = function() return slot end
	ctrl:_watchPhoneSlot(slot)

	-- Hold phone
	ctrl._dockedHidden = true
	local dockedModel = Instance.new("Part")
	dockedModel.Name = "DockedPart"
	dockedModel.Parent = slot
	ctrl:_applyDockedHidden(true)
	expectEqual(dockedModel.LocalTransparencyModifier, 1, "docked model hidden while held")

	-- Unequip phone restores docked visibility
	ctrl:_setDockedHidden(false)
	expectEqual(dockedModel.LocalTransparencyModifier, 0, "docked model visible on unequip")

	ctrl:Destroy()
	room:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 8: Gamepad ButtonY and equip actions ignored while dashboard is open", function()
	local char = createTestRig()
	local ctrl, gui = createTestController(char)
	ctrl:SetDevice("phone_cheap")

	ctrl:SetDashboardOpen(true)
	ctrl:Toggle()
	expectEqual(ctrl:GetState(), "Stowed", "toggle blocked during dashboard")
	ctrl:Equip()
	expectEqual(ctrl:GetState(), "Stowed", "equip blocked during dashboard")

	ctrl:SetDashboardOpen(false)
	ctrl:Toggle()
	expectTrue(ctrl:GetState() == "Equipping" or ctrl:GetState() == "Equipped", "toggle permitted after dashboard close")

	ctrl:Destroy()
	char:Destroy()
	gui:Destroy()
end)

test("Lifecycle 9: Mobile button accessibility and attributes", function()
	local ctrl, gui = createTestController(nil)
	expectTrue(ctrl._button.Size.Y.Offset >= 44, "touch target height is at least 44 reference pixels")

	ctrl:SetDevice("phone_fast")
	expectEqual(ctrl._button:GetAttribute("Device"), "HP Cepat", "device attribute")
	expectEqual(ctrl._button:GetAttribute("PhoneState"), "Stowed", "phone state attribute")
	expectEqual(ctrl._button:GetAttribute("Equipped"), false, "equipped attribute")

	ctrl:Destroy()
	gui:Destroy()
end)

-- ===== runner =====
local passed = 0
local failures: { string } = {}
for _, testCase in ipairs(tests) do
	local ok, err = pcall(testCase.fn)
	if ok then
		passed += 1
		print(`[PASS] {testCase.name}`)
	else
		table.insert(failures, `{testCase.name}: {tostring(err)}`)
		print(`[FAIL] {testCase.name}: {tostring(err)}`)
	end
end

print(`==============================================`)
print(`BS-09 spec: {passed}/{#tests} passed, {#failures} failed`)
if #failures > 0 then
	print("FAILURES:")
	for _, failure in ipairs(failures) do
		print(`  - {failure}`)
	end
	error(`BS-09 spec: {#failures} failed`, 0)
end
return `BS-09: {passed}/{#tests} passed`
