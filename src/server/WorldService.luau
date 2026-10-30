--!strict
-- Buzzer Simulator — WorldService (BS-05).
-- Clones the reviewed Bedroom prefab per player, presents the equipped
-- productive phone, and validates the dashboard prompt.
--
-- Contract sources: docs/03 "World and interface ownership", docs/06
-- "World and Asset Plan", BS-05 in docs/08.
--
-- BOUNDARIES (strict):
--   * The old CRT is a BuzzerOS dashboard-access terminal ONLY. It is never a
--     productive device and carries no yield, multiplier or currency source.
--   * The server's confirmed `profile.deviceId` alone determines which phone
--     model is displayed. Terminal art never affects payout, impact or reveal.
--   * The dashboard prompt lives on the stable room-owned
--     `DashboardPromptAnchor`, never inside the replaceable CRT prefab.
--   * This service never charges currency and never mutates the economy.
--   * No RemoteEvents, no dashboard session lifecycle, no worker rigs. BS-06
--     performs runtime wiring and adds authoritative loaded-profile,
--     writable-session and lease checks on top of ValidateDashboardPrompt.
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local WorldService = {}

-- Stable room-owned anchor names (docs/03). These must exist in Bedroom.rbxmx.
local REQUIRED_ANCHORS = {
	"Spawn",
	"PlayerDesk",
	"DashboardPromptAnchor",
	"TerminalSlot",
	"PhoneSlot",
	"WorkerDeskSlot1",
	"WorkerSeat1",
	"WorkerDeskSlot2",
	"WorkerSeat2",
	"CameraFocus",
	"Door",
	"LightGroup",
}

-- Prefab names under ServerStorage.WorldPrefabs.
local PREFAB_BEDROOM = "Bedroom"
local PREFAB_CRT = "OldCRT"
local PREFAB_PHONE_CHEAP = "PhoneCheap"
local PREFAB_PHONE_FAST = "PhoneFast"

-- The productive phone model shown for each equipped device. The CRT is
-- deliberately absent: it is dashboard-only and never a productive device.
local PHONE_PREFAB_BY_DEVICE: { [string]: string } = {
	phone_cheap = PREFAB_PHONE_CHEAP,
	phone_fast = PREFAB_PHONE_FAST,
}

-- docs/03: the player must be within 12 studs of the prompt.
local MAX_PROMPT_DISTANCE = 12

-- Root folder name for a player's cloned world.
local function worldFolderName(userId: number): string
	return `BuzzerRoom_{userId}`
end

-- Resolve the WorldPrefabs folder. Resolved lazily so the module loads under
-- both the production and test Rojo layouts.
local function prefabsFolder(): Folder?
	local storage = ServerStorage:FindFirstChild("WorldPrefabs")
	if storage ~= nil and storage:IsA("Folder") then
		return storage
	end
	return nil
end

local function findPrefab(name: string): Instance?
	local folder = prefabsFolder()
	if folder == nil then
		return nil
	end
	return folder:FindFirstChild(name)
end

-- True when a value is a nonempty string.
local function isNonEmptyString(v: any): boolean
	return typeof(v) == "string" and #v > 0
end

-- Recursively collect descendants by class, without yielding.
local function collectByClass(root: Instance, className: string): { Instance }
	local out: { Instance } = {}
	local stack: { Instance } = { root }
	while #stack > 0 do
		local node = table.remove(stack) :: any
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA(className) then
				table.insert(out, child)
			end
			table.insert(stack, child)
		end
	end
	return out
end

-- Find a named descendant, without yielding.
local function findNamedDescendant(root: Instance, name: string): Instance?
	local stack: { Instance } = { root }
	while #stack > 0 do
		local node = table.remove(stack) :: any
		for _, child in ipairs(node:GetChildren()) do
			if child.Name == name then
				return child
			end
			table.insert(stack, child)
		end
	end
	return nil
end

-- ===== Spawn =====
-- Clone the reviewed Bedroom prefab into a player-owned Workspace folder,
-- place one OldCRT at TerminalSlot, and present the equipped phone at
-- PhoneSlot. Idempotent: an existing room is reused rather than duplicated.
function WorldService.Spawn(player: Player, profile: any): (boolean, string?)
	if not isNonEmptyString(player.Name) then
		return false, "player is required"
	end
	local bedroom = findPrefab(PREFAB_BEDROOM)
	if bedroom == nil then
		-- A missing prefab is a recoverable error: surface it, never strand the
		-- player in an empty room.
		return false, `prefab {PREFAB_BEDROOM} is missing from ServerStorage.WorldPrefabs`
	end

	-- Prevent duplicate world instances.
	local existing = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if existing ~= nil then
		-- Already spawned: resynchronise the device from confirmed state.
		local deviceId = if typeof(profile) == "table" then profile.deviceId else nil
		if isNonEmptyString(deviceId) then
			WorldService.SyncDevice(player, deviceId)
		end
		return true, nil
	end

	local folder = Instance.new("Folder")
	folder.Name = worldFolderName(player.UserId)
	folder.Parent = Workspace

	local room = bedroom:Clone()
	room.Name = "Room"
	room.Parent = folder

	-- Verify every required anchor exists before wiring anything.
	for _, anchorName in ipairs(REQUIRED_ANCHORS) do
		if findNamedDescendant(room, anchorName) == nil then
			folder:Destroy()
			return false, `prefab {PREFAB_BEDROOM} is missing the {anchorName} anchor`
		end
	end

	-- Place exactly one OldCRT at TerminalSlot.
	local terminalSlot = findNamedDescendant(room, "TerminalSlot")
	local crt = findPrefab(PREFAB_CRT)
	if terminalSlot == nil or crt == nil then
		folder:Destroy()
		return false, `prefab {PREFAB_CRT} is missing or TerminalSlot is absent`
	end
	local crtInstance = crt:Clone()
	crtInstance.Name = "OldCRT"
	crtInstance.Parent = terminalSlot

	-- Present the equipped phone from the confirmed profile.
	local deviceId = if typeof(profile) == "table" then profile.deviceId else nil
	if isNonEmptyString(deviceId) then
		local okPhone, errPhone = WorldService.SyncDevice(player, deviceId)
		if not okPhone then
			folder:Destroy()
			return false, errPhone
		end
	end

	return true, nil
end

-- ===== SyncDevice =====
-- Present the phone model for the confirmed deviceId at PhoneSlot. Idempotent:
-- repeated calls with the same device replace rather than stack, so a rejoin or
-- a re-sync never leaves two phones or a stale model.
function WorldService.SyncDevice(player: Player, deviceId: string): (boolean, string?)
	if not isNonEmptyString(deviceId) then
		return false, "deviceId is required"
	end
	local prefabName = PHONE_PREFAB_BY_DEVICE[deviceId]
	if prefabName == nil then
		-- An unknown or not-yet-shipped device (for example pc_rumah before
		-- BS-11) has no V0 phone presentation. This is not an error: BS-11 adds
		-- the PC replacement at TerminalSlot.
		return false, `no V0 phone presentation for device {deviceId}`
	end
	local folder = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if folder == nil then
		return false, "player has no spawned room; call Spawn first"
	end
	local phoneSlot = findNamedDescendant(folder, "PhoneSlot")
	if phoneSlot == nil then
		return false, "PhoneSlot anchor is missing from the room"
	end
	local prefab = findPrefab(prefabName)
	if prefab == nil then
		return false, `prefab {prefabName} is missing from ServerStorage.WorldPrefabs`
	end

	-- Remove any previously presented phone so the slot never holds two models.
	for _, child: any in ipairs(phoneSlot:GetChildren()) do
		child:Destroy()
	end

	local phone = prefab:Clone()
	phone.Name = prefabName
	phone.Parent = phoneSlot
	return true, nil
end

-- ===== ValidateDashboardPrompt =====
-- Validate the exact player-owned prompt, a living character, and a maximum
-- 12-stud distance. BS-06 additionally enforces authoritative loaded-profile,
-- writable-session and lease checks; this function deliberately does not.
function WorldService.ValidateDashboardPrompt(player: Player, prompt: Instance): (boolean, string?)
	if prompt == nil or not prompt:IsA("BasePart") then
		return false, "prompt must be a BasePart"
	end
	-- The prompt must belong to THIS player's room.
	local folder = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if folder == nil then
		return false, "player has no spawned room"
	end
	if not prompt:IsDescendantOf(folder) then
		return false, "prompt does not belong to this player's room"
	end
	-- The prompt must be the stable room-owned DashboardPromptAnchor.
	if prompt.Name ~= "DashboardPromptAnchor" then
		return false, "prompt is not the stable DashboardPromptAnchor"
	end
	-- The player must have a living character.
	local character = player.Character
	if character == nil then
		return false, "player has no character"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return false, "player character is not alive"
	end
	local health = humanoid.Health
	if typeof(health) ~= "number" or health <= 0 then
		return false, "player character is not alive"
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false, "player character has no root part"
	end
	-- Within 12 studs.
	local distance = ((rootPart :: any).Position - (prompt :: any).Position).Magnitude
	if distance > MAX_PROMPT_DISTANCE then
		return false, `player is {math.floor(distance)} studs away; the limit is {MAX_PROMPT_DISTANCE}`
	end
	return true, nil
end

-- ===== Remove =====
-- Clean up the player's owned world instances. Idempotent.
function WorldService.Remove(player: Player): (boolean, string?)
	local folder = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if folder == nil then
		return true, nil
	end
	folder:Destroy()
	return true, nil
end

-- ===== introspection (specs and BS-06 wiring) =====
function WorldService.GetRoom(player: Player): Instance?
	return Workspace:FindFirstChild(worldFolderName(player.UserId))
end

function WorldService.GetAnchor(player: Player, anchorName: string): Instance?
	local folder = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if folder == nil then
		return nil
	end
	return findNamedDescendant(folder, anchorName)
end

-- Count instances of a class inside the player's room.
function WorldService.CountInRoom(player: Player, className: string): number
	local folder = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if folder == nil then
		return 0
	end
	return #collectByClass(folder, className)
end

-- True when the room contains any Script, LocalScript or ModuleScript. Used by
-- specs to prove no untrusted code rides along inside an exported prefab.
function WorldService.HasScripts(player: Player): boolean
	local folder = Workspace:FindFirstChild(worldFolderName(player.UserId))
	if folder == nil then
		return false
	end
	for _, className in ipairs({ "Script", "LocalScript", "ModuleScript" }) do
		if #collectByClass(folder, className) > 0 then
			return true
		end
	end
	return false
end

WorldService.REQUIRED_ANCHORS = REQUIRED_ANCHORS
WorldService.MAX_PROMPT_DISTANCE = MAX_PROMPT_DISTANCE
WorldService.PHONE_PREFAB_BY_DEVICE = PHONE_PREFAB_BY_DEVICE
WorldService.PREFAB_BEDROOM = PREFAB_BEDROOM
WorldService.PREFAB_CRT = PREFAB_CRT
WorldService.PREFAB_PHONE_CHEAP = PREFAB_PHONE_CHEAP
WorldService.PREFAB_PHONE_FAST = PREFAB_PHONE_FAST

return WorldService
