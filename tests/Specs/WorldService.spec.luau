--!strict
-- Buzzer Simulator — WorldService spec (BS-05).
-- Executed by tests/Runner.server.luau in the test project only.
-- Contract sources: docs/03 "World and interface ownership", docs/06
-- "World and Asset Plan", BS-05 in docs/08.
--
-- The spec loads the REAL authored .rbxmx prefabs through the harness, so it
-- exercises actual prefab assembly rather than a stand-in. Service logic is
-- additionally tested in isolation with synthetic anchors.
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local WorldService = require(ServerStorage:WaitForChild("WorldService"))
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))

-- ===== harness =====
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

-- ===== fake player =====
-- WorldService reads only UserId, Name and Character; real Players are engine-owned.
local function makePlayer(userId: number, name: string): any
	return { UserId = userId, Name = name, Character = nil }
end

local function namedInstance(className: string, name: string): any
	local instance = Instance.new(className)
	instance.Name = name
	return instance
end

local function profileWith(deviceId: string): any
	return {
		balance = 0,
		lifetimeEarned = 0,
		completedMissions = 0,
		deviceId = deviceId,
		propertyId = "bedroom",
		ownedDesks = {},
		workers = {},
		fractionalIncome = 0,
		claimedRunIdsWindow = {},
		recentMutationOutcomes = {},
		missionVariantCounters = {},
		nextOrganicSequence = 0,
		activeMission = nil,
		pendingPost = nil,
		ownPosts = {},
		nextPostSequence = 1,
	}
end

-- ===== prefab existence =====
test("Every required prefab exists under WorldPrefabs", function()
	local folder = ServerStorage:FindFirstChild("WorldPrefabs")
	expectTrue(folder ~= nil, "WorldPrefabs folder exists")
	for _, name in ipairs({ "Bedroom", "OldCRT", "PhoneCheap", "PhoneFast" }) do
		local prefab = (folder :: any):FindFirstChild(name)
		expectTrue(prefab ~= nil, `prefab {name} exists`)
	end
end)

test("The bedroom prefab carries every required anchor", function()
	local folder = ServerStorage:FindFirstChild("WorldPrefabs")
	local bedroom = (folder :: any):FindFirstChild("Bedroom")
	expectTrue(bedroom ~= nil, "Bedroom prefab exists")
	for _, anchor in ipairs(WorldService.REQUIRED_ANCHORS) do
		local found = false
		local stack: { any } = { bedroom }
		while #stack > 0 do
			local node = table.remove(stack)
			for _, child in ipairs(node:GetChildren()) do
				if child.Name == anchor then
					found = true
				end
				table.insert(stack, child)
			end
		end
		expectTrue(found, `anchor {anchor} exists in Bedroom`)
	end
end)

test("No exported prefab contains a script or remote", function()
	local folder = ServerStorage:FindFirstChild("WorldPrefabs")
	for _, name in ipairs({ "Bedroom", "OldCRT", "PhoneCheap", "PhoneFast" }) do
		local prefab = (folder :: any):FindFirstChild(name)
		expectTrue(prefab ~= nil, `prefab {name} exists`)
		local stack: { any } = { prefab }
		while #stack > 0 do
			local node = table.remove(stack)
			for _, child in ipairs(node:GetChildren()) do
				expectTrue(
					not child:IsA("Script")
						and not child:IsA("LocalScript")
						and not child:IsA("ModuleScript"),
					`{name} contains no script descendants`
				)
				expectTrue(not child:IsA("RemoteEvent"), `{name} contains no remotes`)
				table.insert(stack, child)
			end
		end
	end
end)

-- ===== Spawn =====
test("Spawn clones the room and places exactly one CRT", function()
	local player = makePlayer(1001, "SpawnTester")
	local ok, err = WorldService.Spawn(player, profileWith("phone_cheap"))
	expectEqual(ok, true, "spawn ok")
	expectEqual(err, nil, "no error")
	local room = WorldService.GetRoom(player)
	expectTrue(room ~= nil, "room folder exists")
	-- Exactly one CRT.
	local crtCount = 0
	local stack: { any } = { room }
	while #stack > 0 do
		local node = table.remove(stack)
		for _, child in ipairs(node:GetChildren()) do
			if child.Name == "OldCRT" then
				crtCount += 1
			end
			table.insert(stack, child)
		end
	end
	expectEqual(crtCount, 1, "exactly one CRT is spawned")
	WorldService.Remove(player)
end)

test("Spawn presents exactly one equipped productive phone", function()
	local player = makePlayer(1002, "PhoneTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local room = WorldService.GetRoom(player)
	local phoneCount = 0
	local stack: { any } = { room }
	while #stack > 0 do
		local node = table.remove(stack)
		for _, child in ipairs(node:GetChildren()) do
			if child.Name == "PhoneCheap" or child.Name == "PhoneFast" then
				phoneCount += 1
			end
			table.insert(stack, child)
		end
	end
	expectEqual(phoneCount, 1, "exactly one productive phone is presented")
	WorldService.Remove(player)
end)

test("Spawn is idempotent and never duplicates the room", function()
	local player = makePlayer(1003, "DupeTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local firstRoom = WorldService.GetRoom(player)
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local secondRoom = WorldService.GetRoom(player)
	expectEqual(firstRoom == secondRoom, true, "the same room instance is reused")
	-- Only one room folder exists in Workspace.
	local folders = 0
	for _, child: any in ipairs(Workspace:GetChildren()) do
		if child.Name == `BuzzerRoom_{player.UserId}` then
			folders += 1
		end
	end
	expectEqual(folders, 1, "exactly one room folder")
	WorldService.Remove(player)
end)

test("Spawn fails cleanly when the Bedroom prefab is missing", function()
	local folder = ServerStorage:FindFirstChild("WorldPrefabs")
	local bedroom = (folder :: any):FindFirstChild("Bedroom")
	expectTrue(bedroom ~= nil, "Bedroom exists before the test")
	bedroom.Parent = nil
	local player = makePlayer(1004, "MissingPrefab")
	local ok, err = WorldService.Spawn(player, profileWith("phone_cheap"))
	expectEqual(ok, false, "spawn refused")
	expectTrue(err ~= nil and err:find("Bedroom") ~= nil, "the error names the missing prefab")
	expectEqual(WorldService.GetRoom(player), nil, "no room was created")
	-- Restore.
	bedroom.Parent = folder
	WorldService.Remove(player)
end)

-- ===== SyncDevice =====
test("Cheap-to-fast phone synchronization swaps the model", function()
	local player = makePlayer(1005, "SwapTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local slot = WorldService.GetAnchor(player, "PhoneSlot")
	expectTrue(slot ~= nil, "PhoneSlot exists")
	local firstModel = nil
	for _, child in ipairs((slot :: any):GetChildren()) do
		firstModel = child.Name
	end
	expectEqual(firstModel, "PhoneCheap", "cheap phone presented first")

	local ok, err = WorldService.SyncDevice(player, "phone_fast")
	expectEqual(ok, true, "sync to fast ok")
	expectEqual(err, nil, "no error")
	local secondModel = nil
	for _, child in ipairs((slot :: any):GetChildren()) do
		secondModel = child.Name
	end
	expectEqual(secondModel, "PhoneFast", "fast phone presented after sync")
	WorldService.Remove(player)
end)

test("Repeated SyncDevice is idempotent", function()
	local player = makePlayer(1006, "IdempotentTester")
	WorldService.Spawn(player, profileWith("phone_fast"))
	local slot = WorldService.GetAnchor(player, "PhoneSlot")
	for _ = 1, 5 do
		WorldService.SyncDevice(player, "phone_fast")
	end
	local count = 0
	for _, child in ipairs((slot :: any):GetChildren()) do
		if child.Name == "PhoneFast" then
			count += 1
		end
	end
	expectEqual(count, 1, "repeated sync never stacks phones")
	WorldService.Remove(player)
end)

test("A saved device restores correctly on rejoin", function()
	local player = makePlayer(1007, "RejoinTester")
	-- First session: the player owns the fast phone.
	WorldService.Spawn(player, profileWith("phone_fast"))
	WorldService.Remove(player)
	-- Rejoin with the same saved profile.
	WorldService.Spawn(player, profileWith("phone_fast"))
	local slot = WorldService.GetAnchor(player, "PhoneSlot")
	local model = nil
	for _, child in ipairs((slot :: any):GetChildren()) do
		model = child.Name
	end
	expectEqual(model, "PhoneFast", "the saved device is restored")
	WorldService.Remove(player)
end)

test("An invalid device is refused without touching the slot", function()
	local player = makePlayer(1008, "InvalidDevice")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local slot = WorldService.GetAnchor(player, "PhoneSlot")
	local ok, err = WorldService.SyncDevice(player, "phone_ultra")
	expectEqual(ok, false, "unknown device refused")
	expectTrue(err ~= nil, "an error is reported")
	local model = nil
	for _, child in ipairs((slot :: any):GetChildren()) do
		model = child.Name
	end
	expectEqual(model, "PhoneCheap", "the slot is untouched")
	-- pc_rumah is authored catalog data but has no V0 phone presentation.
	local okPc, errPc = WorldService.SyncDevice(player, "pc_rumah")
	expectEqual(okPc, false, "unshipped PC has no V0 phone presentation")
	expectTrue(errPc ~= nil and errPc:find("pc_rumah") ~= nil, "the error names the device")
	WorldService.Remove(player)
end)

test("SyncDevice fails cleanly when a phone prefab is missing", function()
	local folder = ServerStorage:FindFirstChild("WorldPrefabs")
	local fast = (folder :: any):FindFirstChild("PhoneFast")
	expectTrue(fast ~= nil, "PhoneFast exists before the test")
	fast.Parent = nil
	local player = makePlayer(1009, "MissingPhone")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local ok, err = WorldService.SyncDevice(player, "phone_fast")
	expectEqual(ok, false, "sync refused")
	expectTrue(err ~= nil and err:find("PhoneFast") ~= nil, "the error names the missing prefab")
	-- The slot still holds the cheap phone, so the player is never stranded.
	local slot = WorldService.GetAnchor(player, "PhoneSlot")
	local model = nil
	for _, child in ipairs((slot :: any):GetChildren()) do
		model = child.Name
	end
	expectEqual(model, "PhoneCheap", "the previous phone is retained")
	fast.Parent = folder
	WorldService.Remove(player)
end)

-- ===== ValidateDashboardPrompt =====
test("A valid player-owned prompt is accepted", function()
	local player = makePlayer(1010, "PromptOk")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local prompt = WorldService.GetAnchor(player, "DashboardPromptAnchor")
	expectTrue(prompt ~= nil, "the prompt anchor exists")
	-- A living character standing next to the prompt.
	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	rootPart.Position = prompt.Position
	rawset(player, "Character", character)
	local ok, err = WorldService.ValidateDashboardPrompt(player, prompt)
	expectEqual(ok, true, "a valid prompt is accepted")
	expectEqual(err, nil, "no error")
	WorldService.Remove(player)
end)

test("A non-anchor prompt is rejected", function()
	local player = makePlayer(1011, "PromptWrong")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local terminal = WorldService.GetAnchor(player, "TerminalSlot")
	expectTrue(terminal ~= nil, "TerminalSlot exists")
	local ok, err = WorldService.ValidateDashboardPrompt(player, terminal :: any)
	expectEqual(ok, false, "a non-anchor prompt is rejected")
	expectTrue(err ~= nil and err:find("DashboardPromptAnchor") ~= nil, "the error names the anchor")
	WorldService.Remove(player)
end)

test("A prompt belonging to another player is rejected", function()
	local owner = makePlayer(1012, "Owner")
	local intruder = makePlayer(1013, "Intruder")
	WorldService.Spawn(owner, profileWith("phone_cheap"))
	WorldService.Spawn(intruder, profileWith("phone_cheap"))
	local ownerPrompt = WorldService.GetAnchor(owner, "DashboardPromptAnchor")
	expectTrue(ownerPrompt ~= nil, "the owner's prompt exists")
	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	rootPart.Position = ownerPrompt.Position
	rawset(intruder, "Character", character)
	local ok, err = WorldService.ValidateDashboardPrompt(intruder, ownerPrompt :: any)
	expectEqual(ok, false, "another player's prompt is rejected")
	expectTrue(err ~= nil and err:find("does not belong") ~= nil, "the error explains ownership")
	WorldService.Remove(owner)
	WorldService.Remove(intruder)
end)

test("A dead character is rejected", function()
	local player = makePlayer(1014, "DeadTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local prompt = WorldService.GetAnchor(player, "DashboardPromptAnchor")
	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	humanoid.Health = 0
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	rootPart.Position = prompt.Position
	rawset(player, "Character", character)
	local ok, err = WorldService.ValidateDashboardPrompt(player, prompt)
	expectEqual(ok, false, "a dead character is rejected")
	expectTrue(err ~= nil and err:find("alive") ~= nil, "the error names the cause")
	WorldService.Remove(player)
end)

test("A distant character is rejected", function()
	local player = makePlayer(1015, "DistantTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local prompt = WorldService.GetAnchor(player, "DashboardPromptAnchor")
	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	-- 20 studs away, beyond the 12-stud limit.
	rootPart.Position = prompt.Position + Vector3.new(20, 0, 0)
	rawset(player, "Character", character)
	local ok, err = WorldService.ValidateDashboardPrompt(player, prompt)
	expectEqual(ok, false, "a distant character is rejected")
	expectTrue(err ~= nil and err:find("studs") ~= nil, "the error reports the distance")
	WorldService.Remove(player)
end)

test("A character-less player is rejected", function()
	local player = makePlayer(1016, "NoCharacter")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local prompt = WorldService.GetAnchor(player, "DashboardPromptAnchor")
	rawset(player, "Character", nil)
	local ok, _err = WorldService.ValidateDashboardPrompt(player, prompt)
	expectEqual(ok, false, "no character is rejected")
	WorldService.Remove(player)
end)

-- ===== prompt identity and cleanup =====
test("Prompt identity is unchanged during device sync", function()
	local player = makePlayer(1017, "StablePrompt")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	local before = WorldService.GetAnchor(player, "DashboardPromptAnchor")
	WorldService.SyncDevice(player, "phone_fast")
	local after = WorldService.GetAnchor(player, "DashboardPromptAnchor")
	expectEqual(before == after, true, "the prompt anchor instance is identical")
	-- And it is still valid after the swap.
	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	rootPart.Position = after.Position
	rawset(player, "Character", character)
	local ok, _ = WorldService.ValidateDashboardPrompt(player, after)
	expectEqual(ok, true, "the prompt still validates after a device sync")
	WorldService.Remove(player)
end)

test("Remove cleans up player-owned instances", function()
	local player = makePlayer(1018, "CleanupTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	expectTrue(WorldService.GetRoom(player) ~= nil, "room exists before removal")
	local ok, err = WorldService.Remove(player)
	expectEqual(ok, true, "remove ok")
	expectEqual(err, nil, "no error")
	expectEqual(WorldService.GetRoom(player), nil, "room is gone")
	-- And it is idempotent.
	local okAgain, _ = WorldService.Remove(player)
	expectEqual(okAgain, true, "a second remove is a no-op")
end)

test("The room contains no scripts after spawn", function()
	local player = makePlayer(1019, "NoScriptsTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	expectEqual(WorldService.HasScripts(player), false, "no scripts inside the spawned room")
	WorldService.Remove(player)
end)

-- ===== economy isolation =====
test("WorldService never mutates the economy or the profile", function()
	local player = makePlayer(1020, "EconomyTester")
	local profile = profileWith("phone_cheap")
	profile.balance = 110
	local before = profile.balance
	WorldService.Spawn(player, profile)
	WorldService.SyncDevice(player, "phone_fast")
	WorldService.Remove(player)
	expectEqual(profile.balance, before, "balance is untouched")
	expectEqual(profile.deviceId, "phone_cheap", "deviceId is untouched")
end)

test("The terminal is never a productive device", function()
	-- The CRT carries no yield, multiplier or currency source: only the two
	-- phones are mapped to a productive presentation.
	local mapped = WorldService.PHONE_PREFAB_BY_DEVICE
	expectEqual(mapped.phone_cheap, "PhoneCheap", "cheap phone is productive")
	expectEqual(mapped.phone_fast, "PhoneFast", "fast phone is productive")
	expectEqual(mapped.pc_rumah, nil, "the PC has no V0 mapping")
	expectEqual(mapped.OldCRT, nil, "the CRT is never a productive device")
	-- And no catalog device other than the two phones maps to a presentation.
	for _, device in ipairs(Catalog.Devices) do
		local id = (device :: any).id
		if id ~= "phone_cheap" and id ~= "phone_fast" then
			expectEqual(mapped[id], nil, `{id} has no V0 phone presentation`)
		end
	end
end)

test("The initial room contains no free productive PC", function()
	local player = makePlayer(1021, "NoFreePC")
	WorldService.Spawn(player, profileWith("phone_cheap"))
	-- No PCRumah instance anywhere in the room.
	local found = false
	local stack: { any } = { WorldService.GetRoom(player) }
	while #stack > 0 do
		local node = table.remove(stack)
		for _, child in ipairs(node:GetChildren()) do
			if child.Name == "PCRumah" then
				found = true
			end
			table.insert(stack, child)
		end
	end
	expectEqual(found, false, "no free productive PC at initial spawn")
	WorldService.Remove(player)
end)

-- ===== BS-05 Visual Correctness & World Placement Regressions =====

test("CRT world position near TerminalSlot with desk and floor clearances", function()
	local player = makePlayer(1022, "CRTPlacementTester")
	local ok, err = WorldService.Spawn(player, profileWith("phone_cheap"))
	expectEqual(ok, true, "Spawn succeeds")
	expectEqual(err, nil, "no spawn error")

	local terminalSlot = WorldService.GetAnchor(player, "TerminalSlot") :: any
	expectTrue(terminalSlot ~= nil, "TerminalSlot exists")

	local crt = terminalSlot:FindFirstChild("OldCRT") :: any
	expectTrue(crt ~= nil, "OldCRT is parented to TerminalSlot")
	expectEqual(crt.ClassName, "Model", "OldCRT is a Model")
	expectTrue(crt.PrimaryPart ~= nil, "OldCRT has a PrimaryPart")

	local crtPivot = crt:GetPivot()
	local slotPos = terminalSlot.Position
	expectTrue(math.abs(crtPivot.Position.X - slotPos.X) < 0.1, "CRT X matches TerminalSlot")
	expectTrue(math.abs(crtPivot.Position.Z - slotPos.Z) < 0.1, "CRT Z matches TerminalSlot")
	expectTrue(math.abs(crtPivot.Position.Y - (slotPos.Y + 1.4)) < 0.1, "CRT Y is offset by half-height 1.4")

	local bbCFrame, bbSize = crt:GetBoundingBox()
	expectTrue(bbSize.Y >= 2.5 and bbSize.Y <= 3.0, "CRT height matches expected ~2.8 studs")
	local bottomY = bbCFrame.Position.Y - bbSize.Y / 2
	-- Desk top surface is at Y = 3.35 (desk center 3.2 + thickness 0.3/2)
	expectTrue(bottomY >= 3.30, "CRT rests on top of desk without penetrating")
	expectTrue(bottomY > 2.0, "CRT has clear clearance from bedroom floor (Y=0.5)")

	WorldService.Remove(player)
end)

test("Cheap and fast phone positions near PhoneSlot replacing model cleanly", function()
	local player = makePlayer(1023, "PhonePlacementTester")
	local ok, err = WorldService.Spawn(player, profileWith("phone_cheap"))
	expectEqual(ok, true, "Spawn succeeds")
	expectEqual(err, nil, "no spawn error")

	local phoneSlot = WorldService.GetAnchor(player, "PhoneSlot") :: any
	expectTrue(phoneSlot ~= nil, "PhoneSlot exists")

	-- Initial phone_cheap placement
	local cheapModel = phoneSlot:FindFirstChild("PhoneCheap") :: any
	expectTrue(cheapModel ~= nil, "PhoneCheap is placed")
	expectEqual(cheapModel.ClassName, "Model", "PhoneCheap is a Model")
	local cheapPivot = cheapModel:GetPivot()
	local slotPos = phoneSlot.Position
	expectTrue(math.abs(cheapPivot.Position.X - slotPos.X) < 0.1, "PhoneCheap X matches PhoneSlot")
	expectTrue(math.abs(cheapPivot.Position.Z - slotPos.Z) < 0.1, "PhoneCheap Z matches PhoneSlot")
	expectTrue(math.abs(cheapPivot.Position.Y - (slotPos.Y + 1.0)) < 0.1, "PhoneCheap Y is offset by half-height 1.0")
	local cheapBB, cheapSize = cheapModel:GetBoundingBox()
	expectTrue(cheapBB.Position.Y - cheapSize.Y / 2 >= 3.30, "PhoneCheap rests on desk")

	-- Sync to phone_fast
	local okSync, errSync = WorldService.SyncDevice(player, "phone_fast")
	expectEqual(okSync, true, "SyncDevice succeeds")
	expectEqual(errSync, nil, "no sync error")

	expectEqual(#phoneSlot:GetChildren(), 1, "PhoneSlot has exactly one child after sync")
	expectEqual(phoneSlot:FindFirstChild("PhoneCheap"), nil, "PhoneCheap was destroyed")
	local fastModel = phoneSlot:FindFirstChild("PhoneFast") :: any
	expectTrue(fastModel ~= nil, "PhoneFast is placed")
	expectEqual(fastModel.ClassName, "Model", "PhoneFast is a Model")

	local fastPivot = fastModel:GetPivot()
	expectTrue(math.abs(fastPivot.Position.X - slotPos.X) < 0.1, "PhoneFast X matches PhoneSlot")
	expectTrue(math.abs(fastPivot.Position.Z - slotPos.Z) < 0.1, "PhoneFast Z matches PhoneSlot")
	expectTrue(math.abs(fastPivot.Position.Y - (slotPos.Y + 1.1)) < 0.1, "PhoneFast Y is offset by half-height 1.1")
	local fastBB, fastSize = fastModel:GetBoundingBox()
	expectTrue(fastBB.Position.Y - fastSize.Y / 2 >= 3.30, "PhoneFast rests on desk")

	WorldService.Remove(player)
end)

test("One terminal prompt across repeated Spawn and SyncDevice with stable identity", function()
	local player = makePlayer(1024, "PromptStabilityTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))

	local prompt1 = WorldService.GetPrompt(player)
	expectTrue(prompt1 ~= nil, "prompt exists initially")
	expectEqual((prompt1 :: any).ClassName, "ProximityPrompt", "prompt is a ProximityPrompt")

	local anchor = WorldService.GetAnchor(player, "DashboardPromptAnchor") :: any
	expectTrue(anchor ~= nil, "DashboardPromptAnchor exists")
	expectEqual(#anchor:GetChildren(), 1, "anchor has exactly one child initially")

	-- Repeated Spawn (idempotent)
	local okSpawn2, _ = WorldService.Spawn(player, profileWith("phone_cheap"))
	expectEqual(okSpawn2, true, "second Spawn succeeds")
	local prompt2 = WorldService.GetPrompt(player)
	expectEqual(prompt1, prompt2, "prompt identity is stable across repeated Spawn")
	expectEqual(#anchor:GetChildren(), 1, "anchor still has exactly one child after repeated Spawn")

	-- SyncDevice
	local okSync, _ = WorldService.SyncDevice(player, "phone_fast")
	expectEqual(okSync, true, "SyncDevice succeeds")
	local prompt3 = WorldService.GetPrompt(player)
	expectEqual(prompt1, prompt3, "prompt identity is stable across SyncDevice")
	expectEqual(#anchor:GetChildren(), 1, "anchor still has exactly one child after SyncDevice")

	WorldService.Remove(player)
end)

test("Prompt accessibility, action text and living player validation", function()
	local player = makePlayer(1025, "PromptAccessTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))

	local prompt = WorldService.GetPrompt(player) :: any
	expectTrue(prompt ~= nil, "prompt exists")
	expectEqual(prompt.Name, "DashboardPrompt", "prompt Name is DashboardPrompt")
	expectEqual(prompt.ActionText, "Open BuzzerOS", "ActionText is Open BuzzerOS")
	expectTrue(tonumber(prompt.MaxActivationDistance) :: number >= 10, "MaxActivationDistance >= 10")

	local anchor = WorldService.GetAnchor(player, "DashboardPromptAnchor") :: any

	-- Character setup
	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	rootPart.Position = anchor.Position + Vector3.new(0, 0, 4) -- 4 studs away
	rawset(player, "Character", character)

	local ok, err = WorldService.ValidateDashboardPrompt(player, prompt)
	expectEqual(ok, true, "ValidateDashboardPrompt succeeds with ProximityPrompt instance")
	expectEqual(err, nil, "no error")

	-- Distance measured from anchor Part
	rootPart.Position = anchor.Position + Vector3.new(0, 0, 15) -- 15 studs away > 12
	local okDist, errDist = WorldService.ValidateDashboardPrompt(player, prompt)
	expectEqual(okDist, false, "rejected beyond 12 studs")
	expectTrue(errDist ~= nil and errDist:find("15 studs away") ~= nil, "reports measured distance from anchor")

	WorldService.Remove(player)
end)

test("Correct scale, orientation facing player (+Z), and physical clearance between CRT and phone", function()
	local player = makePlayer(1026, "OrientationClearanceTester")
	WorldService.Spawn(player, profileWith("phone_cheap"))

	local terminalSlot = WorldService.GetAnchor(player, "TerminalSlot") :: any
	local phoneSlot = WorldService.GetAnchor(player, "PhoneSlot") :: any
	local crt = terminalSlot:FindFirstChild("OldCRT") :: any
	local phone = phoneSlot:FindFirstChild("PhoneCheap") :: any

	-- Orientation: LookVector.Z > 0.9 (facing south towards approaching player at +Z)
	local crtPivot = crt:GetPivot()
	local phonePivot = phone:GetPivot()
	expectTrue(crtPivot.LookVector.Z > 0.9, "CRT screen faces player (+Z)")
	expectTrue(phonePivot.LookVector.Z > 0.9, "Phone screen faces player (+Z)")

	-- Upright: UpVector.Y > 0.9
	expectTrue(crtPivot.UpVector.Y > 0.9, "CRT is upright")
	expectTrue(phonePivot.UpVector.Y > 0.9, "Phone is upright")

	-- Physical separation/clearance on desk
	local crtBB, crtSize = crt:GetBoundingBox()
	local phoneBB, phoneSize = phone:GetBoundingBox()
	local crtMinX = crtBB.Position.X - crtSize.X / 2
	local phoneMaxX = phoneBB.Position.X + phoneSize.X / 2
	expectTrue(crtMinX > phoneMaxX, "CRT and phone have distinct horizontal clearance on desk")
	local clearance = crtMinX - phoneMaxX
	expectTrue(clearance > 0.5, "At least 0.5 studs clearance between CRT and phone")

	WorldService.Remove(player)
end)

test("Prompt cannot be spoofed from another player's room via ProximityPrompt instance", function()
	local owner = makePlayer(1027, "PromptOwner")
	local intruder = makePlayer(1028, "PromptIntruder")
	WorldService.Spawn(owner, profileWith("phone_cheap"))
	WorldService.Spawn(intruder, profileWith("phone_cheap"))

	local ownerPrompt = WorldService.GetPrompt(owner) :: any
	expectTrue(ownerPrompt ~= nil, "owner's prompt exists")

	local character = namedInstance("Model", "Character")
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	local rootPart = namedInstance("Part", "HumanoidRootPart")
	rootPart.Parent = character
	local ownerAnchor = WorldService.GetAnchor(owner, "DashboardPromptAnchor") :: any
	rootPart.Position = ownerAnchor.Position
	rawset(intruder, "Character", character)

	local ok, err = WorldService.ValidateDashboardPrompt(intruder, ownerPrompt)
	expectEqual(ok, false, "another player's ProximityPrompt is rejected")
	expectTrue(err ~= nil and err:find("does not belong") ~= nil, "error explains room ownership")

	WorldService.Remove(owner)
	WorldService.Remove(intruder)
end)

-- ===== run =====
local passed, failed = 0, 0
for _, t in ipairs(tests) do
	local ok, err = pcall(t.fn)
	if ok then
		passed += 1
		print(`[PASS] {t.name}`)
	else
		failed += 1
		print(`[FAIL] {t.name}: {tostring(err)}`)
	end
end
print(`==============================================`)
print(`WorldService spec: {passed}/{passed + failed} passed, {failed} failed`)
if failed > 0 then
	error("WorldService spec failed", 0)
end
return `WorldService: {passed}/{passed + failed} passed`
