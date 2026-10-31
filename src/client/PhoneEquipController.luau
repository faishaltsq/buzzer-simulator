--!strict
-- Buzzer Simulator — PhoneEquipController (BS-09)
-- Cosmetic, session-local handheld phone. A phone is an owned productive device,
-- not permanently stationary furniture: this controller lets the character hold
-- the phone that the confirmed profile already owns.
--
-- This module is presentation only. It never reads or writes economy state,
-- never awards Cuan, and never touches the server-owned world prefabs
-- destructively — the docked phone is hidden with a client-local transparency
-- modifier and restored on unequip.
-- Contract sources: docs/05, docs/06, docs/08 (BS-09).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Presentation = require(Shared:WaitForChild("Presentation"))
local Theme = require(script.Parent:WaitForChild("ui"):WaitForChild("Theme"))

local player = Players.LocalPlayer

local PhoneEquipController = {}
PhoneEquipController.__index = PhoneEquipController

-- Palette taken from the approved world prefabs (walnut body, sage screen,
-- cream keycaps) so the handheld reads as the same object as the docked phone.
local PALETTE = {
	cheapBody = Color3.fromRGB(180, 139, 96),
	cheapKey = Color3.fromRGB(242, 229, 213),
	cheapScreen = Color3.fromRGB(168, 182, 156),
	fastBody = Color3.fromRGB(48, 52, 60),
	fastScreen = Color3.fromRGB(242, 229, 213),
	fastAccent = Color3.fromRGB(242, 188, 121),
}

-- Hand-sized silhouette, in studs. Deliberately smaller than the desk prefab
-- (2 studs tall) and larger than a real phone so it reads at third-person
-- distance without clipping the torso.
local PHONE_SIZE = {
	cheap = Vector3.new(0.52, 1.02, 0.16),
	fast = Vector3.new(0.5, 1.04, 0.11),
}

-- Grip offsets. C0 places the phone body just past the closed fist with the
-- screen facing outward from the palm. R6 arms are thicker and shorter than
-- R15 hands, so they get their own offset.
local GRIP = {
	R15 = CFrame.new(0, -0.42, 0.02) * CFrame.Angles(math.rad(-96), 0, 0),
	R6 = CFrame.new(0, -0.5, 0.05) * CFrame.Angles(math.rad(-96), 0, 0),
}

-- Procedural pose offsets applied to the shoulder Motor6D C0. Animations write
-- Motor6D.Transform, so offsetting C0 raises the arm additively and restoring
-- C0 returns the rig to untouched default animation behaviour.
local POSE = {
	equip = CFrame.Angles(math.rad(-62), 0, math.rad(-10)),
	use = CFrame.Angles(math.rad(-14), 0, 0),
}

local EQUIP_SECONDS = 0.28
local USE_SECONDS = 0.7

local function isReducedMotion(): boolean
	local ok, enabled = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and enabled == true
end

local function part(parent: Instance, name: string, size: Vector3, color: Color3, offset: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = offset
	p.Parent = parent
	return p
end

-- ===== cosmetic model =====
-- Built in code from primitives: no toolbox asset, no uploaded mesh, no script
-- inside the model, and no asset ID that could be unavailable.
local function buildCosmetic(deviceId: string): Model
	local isFast = deviceId == "phone_fast"
	local size = if isFast then PHONE_SIZE.fast else PHONE_SIZE.cheap
	local model = Instance.new("Model")
	model.Name = if isFast then "HeldPhoneFast" else "HeldPhoneCheap"

	local body = part(model, "Body", size, if isFast then PALETTE.fastBody else PALETTE.cheapBody, CFrame.identity)
	model.PrimaryPart = body

	if isFast then
		-- Modern touchscreen: one large lit panel and a camera bump.
		part(model, "Screen", Vector3.new(size.X - 0.08, size.Y - 0.16, 0.02), PALETTE.fastScreen,
			CFrame.new(0, 0.02, -size.Z / 2 - 0.005))
		part(model, "ScreenGlow", Vector3.new(size.X - 0.16, 0.22, 0.02), PALETTE.fastAccent,
			CFrame.new(0, size.Y / 2 - 0.16, -size.Z / 2 - 0.012))
		part(model, "CameraBump", Vector3.new(0.22, 0.22, 0.04), PALETTE.fastBody,
			CFrame.new(-size.X / 2 + 0.16, size.Y / 2 - 0.16, size.Z / 2 + 0.02))
	else
		-- Retro keypad handset: small screen plus a visible key grid.
		part(model, "Screen", Vector3.new(size.X - 0.1, 0.3, 0.02), PALETTE.cheapScreen,
			CFrame.new(0, size.Y / 2 - 0.24, -size.Z / 2 - 0.005))
		for row = 0, 2 do
			for column = -1, 1 do
				part(model, "Key", Vector3.new(0.1, 0.1, 0.02), PALETTE.cheapKey,
					CFrame.new(column * 0.14, 0.06 - row * 0.15, -size.Z / 2 - 0.005))
			end
		end
	end

	for _, child in ipairs(model:GetChildren()) do
		if child ~= body and child:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = child
			weld.Parent = child
		end
	end
	return model
end

-- ===== controller =====
export type ControllerOptions = {
	parent: Instance,
}

function PhoneEquipController.new(options: ControllerOptions): any
	local self = setmetatable({}, PhoneEquipController)
	self._state = "Stowed"
	self._deviceId = nil
	self._model = nil :: Model?
	self._weld = nil :: Weld?
	self._shoulder = nil :: Motor6D?
	self._shoulderBase = nil :: CFrame?
	self._character = nil :: Model?
	self._dockedHidden = false
	self._connections = {}
	self._dashboardOpen = false
	self._preferEquipped = false
	self._poseTween = nil :: Tween?

	-- Small contextual control. Sits on the right edge at mid height: clear of
	-- the Cuan card (top left), objective pill (top centre), status banner
	-- (top right), hint banner (bottom centre), thumbstick (bottom left) and
	-- jump button (bottom right).
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuzzerPhoneControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2
	gui.Parent = options.parent
	self._gui = gui

	local button = Instance.new("TextButton")
	button.Name = "PhoneEquipButton"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -14, 0.56, 0)
	button.Size = UDim2.new(0, 128, 0, 40)
	button.BackgroundColor3 = Theme.Colors.CharcoalDark
	button.BackgroundTransparency = 0.08
	button.Font = Theme.Fonts.Bold
	button.TextSize = 13
	button.TextColor3 = Theme.Colors.Cream
	button.Text = "Equip phone"
	button.Selectable = true
	button.AutoButtonColor = true
	button.Parent = gui
	Theme.applyCorner(button, Theme.Radii.Pill)
	Theme.applyStroke(button, Theme.Colors.Border, 1)
	button.Activated:Connect(function()
		self:Toggle()
	end)
	self._button = button

	-- Gamepad affordance. ButtonY is unused by Roblox defaults and by this
	-- game's terminal prompt (which is a ProximityPrompt on E), so it cannot
	-- swallow prompt input.
	ContextActionService:BindAction("BuzzerOS_TogglePhone", function(_name, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonY)
	pcall(function()
		ContextActionService:SetTitle("BuzzerOS_TogglePhone", "Phone")
	end)

	table.insert(self._connections, player.CharacterAdded:Connect(function(character)
		self:_onCharacter(character)
	end))
	table.insert(self._connections, player.CharacterRemoving:Connect(function()
		self:_teardownModel()
		self._character = nil
		self._shoulder = nil
		self._shoulderBase = nil
	end))
	if player.Character ~= nil then
		self:_onCharacter(player.Character)
	end

	-- World re-sync: the server may replace the docked phone at any time, so the
	-- local hide is re-applied to whatever is currently in PhoneSlot.
	table.insert(self._connections, Workspace.ChildAdded:Connect(function()
		if self._dockedHidden then
			task.defer(function()
				self:_applyDockedHidden(true)
			end)
		end
	end))

	self:_render()
	return self
end

function PhoneEquipController:_onCharacter(character: Model)
	self:_teardownModel()
	self._character = character
	self._shoulder = nil
	self._shoulderBase = nil
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid == nil then
		return
	end
	table.insert(self._connections, humanoid.Died:Connect(function()
		self:_teardownModel()
		self._state = "Stowed"
		self._preferEquipped = false
		self:_applyDockedHidden(false)
		self:_render()
	end))
	if self._preferEquipped then
		task.defer(function()
			self:Equip()
		end)
	end
	self:_render()
end

function PhoneEquipController:_resolveRig(): (BasePart?, Motor6D?)
	local character = self._character
	if character == nil or character.Parent == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hand: BasePart? = nil
	if humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15 then
		hand = character:FindFirstChild("RightHand") :: BasePart?
	else
		hand = character:FindFirstChild("Right Arm") :: BasePart?
		if hand == nil then
			hand = character:FindFirstChild("RightHand") :: BasePart?
		end
	end
	local shoulder: Motor6D? = nil
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and (descendant.Name == "RightShoulder" or descendant.Name == "Right Shoulder") then
			shoulder = descendant
			break
		end
	end
	return hand, shoulder
end

function PhoneEquipController:_gripFor(hand: BasePart): CFrame
	local humanoid = self._character and self._character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return GRIP.R15
	end
	-- R6 arm parts are wider than an R15 hand; scale the offset with the part so
	-- a custom-rig avatar does not end up with a floating phone.
	local width = hand.Size.X
	local factor = math.clamp(width / 1.0, 0.8, 1.6)
	return GRIP.R6 * CFrame.new(0, -0.06 * factor, 0)
end

function PhoneEquipController:_attachModel()
	local deviceId = self._deviceId
	if deviceId == nil or self._model ~= nil then
		return
	end
	local hand = self:_resolveRig()
	if hand == nil then
		return
	end
	local model = buildCosmetic(deviceId)
	model.Parent = self._character
	self._model = model
	local root = model.PrimaryPart
	if root == nil then
		model:Destroy()
		self._model = nil
		return
	end
	local weld = Instance.new("Weld")
	weld.Name = "PhoneGrip"
	weld.Part0 = hand
	weld.Part1 = root
	weld.C0 = self:_gripFor(hand)
	weld.Parent = root
	self._weld = weld
end

function PhoneEquipController:_teardownModel()
	if self._weld ~= nil then
		self._weld:Destroy()
		self._weld = nil
	end
	if self._model ~= nil then
		self._model:Destroy()
		self._model = nil
	end
end

function PhoneEquipController:_poseTo(offset: CFrame?, seconds: number)
	local shoulder = self._shoulder
	local base = self._shoulderBase
	if shoulder == nil or base == nil then
		return
	end
	if self._poseTween ~= nil then
		self._poseTween:Cancel()
		self._poseTween = nil
	end
	local target = if offset == nil then base else base * offset
	if isReducedMotion() or seconds <= 0 then
		shoulder.C0 = target
		return
	end
	local tween = TweenService:Create(shoulder, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = target,
	})
	self._poseTween = tween
	tween:Play()
end

-- ===== docked presentation =====
function PhoneEquipController:_phoneSlot(): Instance?
	local folder = Workspace:FindFirstChild(`BuzzerRoom_{player.UserId}`)
	if folder == nil then
		return nil
	end
	local room = folder:FindFirstChild("Room") or folder
	return room:FindFirstChild("PhoneSlot", true)
end

-- Client-local only: LocalTransparencyModifier never replicates, so the
-- server-owned model is never modified or destroyed.
function PhoneEquipController:_applyDockedHidden(hidden: boolean)
	local slot = self:_phoneSlot()
	if slot == nil then
		return
	end
	for _, descendant in ipairs(slot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function PhoneEquipController:_setDockedHidden(hidden: boolean)
	self._dockedHidden = hidden
	self:_applyDockedHidden(hidden)
end

-- ===== public state =====
function PhoneEquipController:GetState(): string
	return self._state
end

function PhoneEquipController:SetDevice(deviceId: string?)
	if typeof(deviceId) ~= "string" or deviceId == self._deviceId then
		return
	end
	local wasEquipped = self._state == "Equipped" or self._state == "Using" or self._state == "Equipping"
	self._deviceId = deviceId
	if wasEquipped then
		-- A confirmed purchase changed the productive device while a cosmetic
		-- was in hand: swap the visual without touching economy state.
		self:_teardownModel()
		self._state = "Equipped"
		self:_attachModel()
	end
	self:_render()
end

function PhoneEquipController:Equip()
	if self._state == "Equipped" or self._state == "Equipping" or self._state == "Using" then
		return
	end
	local hand, shoulder = self:_resolveRig()
	if hand == nil then
		return
	end
	self._character = self._character or player.Character
	self._shoulder = shoulder
	self._shoulderBase = if shoulder ~= nil then shoulder.C0 else nil
	self._state = "Equipping"
	self._preferEquipped = true
	self:_attachModel()
	self:_poseTo(POSE.equip, EQUIP_SECONDS)
	self:_render()
	task.delay(EQUIP_SECONDS, function()
		if self._state == "Equipping" then
			self._state = "Equipped"
			self:_setDockedHidden(true)
			self:_render()
		end
	end)
end

function PhoneEquipController:Unequip()
	if self._state == "Stowed" or self._state == "Unequipping" then
		return
	end
	self._state = "Unequipping"
	self._preferEquipped = false
	self:_poseTo(nil, EQUIP_SECONDS)
	self:_setDockedHidden(false)
	self:_render()
	task.delay(EQUIP_SECONDS, function()
		if self._state == "Unequipping" then
			self:_teardownModel()
			self._state = "Stowed"
			self:_render()
		end
	end)
end

function PhoneEquipController:Toggle()
	if self._state == "Stowed" then
		self:Equip()
	else
		self:Unequip()
	end
end

-- Presentational only: a locally admitted publish press is not a confirmed
-- server transaction, so this is a short flourish, never the 16/18s reveal.
function PhoneEquipController:PlayUse()
	if self._state ~= "Equipped" then
		return
	end
	self._state = "Using"
	self:_poseTo(POSE.equip * POSE.use, 0.18)
	self:_render()
	task.delay(USE_SECONDS, function()
		if self._state == "Using" then
			self._state = "Equipped"
			self:_poseTo(POSE.equip, 0.22)
			self:_render()
		end
	end)
end

-- Called before the CRT camera transition. Returns false if the visual could
-- not be cleaned up, so the caller can still proceed: closing BuzzerOS must
-- never be blocked by a cosmetic failure.
function PhoneEquipController:StowForDashboard(): boolean
	self._preferEquipped = self._state == "Equipped" or self._state == "Using" or self._state == "Equipping"
	local ok = pcall(function()
		if self._state ~= "Stowed" then
			self:Unequip()
		end
	end)
	return ok
end

function PhoneEquipController:RestoreAfterDashboard()
	if not self._preferEquipped then
		return
	end
	if self._character == nil or self._character.Parent == nil then
		self._preferEquipped = false
		return
	end
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		self._preferEquipped = false
		return
	end
	self:Equip()
end

function PhoneEquipController:SetDashboardOpen(isOpen: boolean)
	self._dashboardOpen = isOpen
	self:_render()
end

function PhoneEquipController:_render()
	local equipped = self._state == "Equipped" or self._state == "Using" or self._state == "Equipping"
	self._button.Text = if equipped then "Stow phone" else "Equip phone"
	self._button.Visible = not self._dashboardOpen
	local label = self._deviceId and (Presentation.Devices[self._deviceId] or self._deviceId) or "phone"
	self._button:SetAttribute("Equipped", equipped)
	self._button:SetAttribute("Device", label)
	self._button:SetAttribute("PhoneState", self._state)
end

function PhoneEquipController:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	pcall(function()
		ContextActionService:UnbindAction("BuzzerOS_TogglePhone")
	end)
	self:_teardownModel()
	self._gui:Destroy()
end

PhoneEquipController.PHONE_SIZE = PHONE_SIZE
PhoneEquipController.GRIP = GRIP
PhoneEquipController.POSE = POSE
PhoneEquipController.buildCosmetic = buildCosmetic

return PhoneEquipController
