--!strict
-- BS-06 orchestration. Domain state and every durable write stay in SessionService.
local function sibling(name: string): any
	for _, serviceName in ipairs({ "ServerScriptService", "ServerStorage" }) do
		local found = game:GetService(serviceName):FindFirstChild(name)
		if found then
			return require(found)
		end
	end
	error(`BootstrapRuntime: {name} module not found`, 0)
end
local NetRouter = sibling("NetRouter")
local Runtime = {}
Runtime.__index = Runtime

local function disconnectAll(connections: { any })
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

export type Options = {
	players: any,
	prompts: any,
	replicatedStorage: any,
	heartbeat: any,
	bindToClose: ((() -> ()) -> ()),
	world: any,
	sessionFactory: (any) -> any,
	now: () -> number,
	monotonic: () -> number,
	guid: () -> string,
	spawn: ((() -> ()) -> ())?,
	wait: ((number) -> ())?,
	report: ((string) -> ())?,
	sendReply: ((any, any) -> ())?,
	sendSnapshot: ((any, any) -> ())?,
	shutdownSeconds: number?,
}

function Runtime.new(options: Options): any
	local self: any = setmetatable({}, Runtime)
	self._options = options
	self._spawn = options.spawn or function(fn) task.spawn(fn) end
	self._wait = options.wait or task.wait
	self._report = options.report or warn
	self._records = {}
	self._closing = {}
	self._connections = {}
	self._started = false
	self._stopping = false
	self._stopped = false
	self._finalizationFailed = false
	self._lastStep = options.monotonic()
	self._remotes = NetRouter.EnsureRemotes(options.replicatedStorage)
	self._router = NetRouter.new({
		world = options.world,
		now = options.now,
		monotonic = options.monotonic,
		guid = options.guid,
		sendReply = options.sendReply or function(player, message)
			self._remotes.Reply:FireClient(player, message)
		end,
		sendSnapshot = options.sendSnapshot or function(player, message)
			self._remotes.Snapshot:FireClient(player, message)
		end,
		beforeMutation = function(player)
			local record = self._records[player]
			if record and record.ready then
				record.session:CaptureConnectedTime()
			end
		end,
		onConfirmed = function(player)
			local record = self._records[player]
			if record and record.ready then
				self:_syncWorld(record)
			end
		end,
	})
	return self
end

function Runtime:_attribute(player: any, name: string, value: any)
	player:SetAttribute(name, value)
end

function Runtime:_current(record: any): boolean
	return not self._stopping and self._records[record.player] == record and not record.removing
end

function Runtime:_placeCharacter(record: any)
	local character = record.character
	if not self:_current(record) or not record.ready or not character or record.player.Character ~= character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local anchor = self._options.world.GetAnchor(record.player, "Spawn")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and anchor and anchor:IsA("BasePart") then
		if record.placedCharacter ~= character then
			character:PivotTo(anchor.CFrame * CFrame.new(0, 3, 0))
			root.AssemblyLinearVelocity = Vector3.zero
			record.placedCharacter = character
		end
	end
end

function Runtime:_bindCharacter(record: any, character: any)
	disconnectAll(record.characterConnections)
	self._router:CharacterLost(record.player)
	record.character = character
	record.placedCharacter = nil
	local boundHumanoid: any = nil
	local function bindParts()
		if not self:_current(record) or record.character ~= character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid ~= boundHumanoid then
			boundHumanoid = humanoid
			table.insert(record.characterConnections, humanoid.Died:Connect(function()
				if record.character == character then self._router:CharacterLost(record.player) end
			end))
		end
		self:_placeCharacter(record)
	end
	table.insert(record.characterConnections, character.ChildAdded:Connect(bindParts))
	table.insert(record.characterConnections, character.AncestryChanged:Connect(function()
		if character.Parent == nil and record.character == character then
			self._router:CharacterLost(record.player)
		end
	end))
	bindParts()
end

function Runtime:_syncWorld(record: any): boolean
	if not self:_current(record) or not record.ready then return false end
	local world = self._options.world
	local profile = record.session:GetConfirmedProfile()
	if not profile then return false end
	record.lastWorldAttempt = self._options.monotonic()
	local ok, success, detail = pcall(function()
		if world.GetRoom(record.player) == nil then
			return world.Spawn(record.player, profile)
		elseif record.presentedDevice ~= profile.deviceId then
			return world.SyncDevice(record.player, profile.deviceId)
		end
		return true, nil
	end)
	if ok and success then
		record.presentedDevice = profile.deviceId
		self:_attribute(record.player, "BuzzerWorldError", nil)
		self:_placeCharacter(record)
		return true
	end
	record.presentedDevice = nil
	local message = if ok then tostring(detail) else tostring(success)
	self:_attribute(record.player, "BuzzerWorldError", message)
	self._report(`BS-06 world presentation for {record.player.UserId}: {message}`)
	return false
end

function Runtime:AddPlayer(player: any)
	if self._stopping or self._records[player] then return end
	local record: any = {
		player = player, session = nil, loading = true, ready = false,
		removing = false, pumping = false, stopping = false,
		connections = {}, characterConnections = {}, lastWorldAttempt = -math.huge,
	}
	self._records[player] = record
	self:_attribute(player, "BuzzerReady", false)
	self:_attribute(player, "BuzzerLoadError", nil)
	table.insert(record.connections, player.CharacterAdded:Connect(function(character)
		if self:_current(record) then self:_bindCharacter(record, character) end
	end))
	table.insert(record.connections, player.CharacterRemoving:Connect(function(character)
		if record.character == character then
			self._router:CharacterLost(player)
			disconnectAll(record.characterConnections)
			record.character = nil
			record.placedCharacter = nil
		end
	end))
	if player.Character then self:_bindCharacter(record, player.Character) end
	self._spawn(function()
		local completed, failure = xpcall(function()
			local session = self._options.sessionFactory(player)
			record.session = session
			if not self:_current(record) then
				record.loading = false
				self:_tryStop(record)
				return
			end
			self._router:Register(player, session)
			local result = session:Start()
			if not self:_current(record) then
				record.loading = false
				self:_tryStop(record)
				return
			end
			if not result.ok and result.code == "NOT_READY" then
				result = session:InitializeStarter()
			end
			record.loading = false
			if not self:_current(record) then
				self:_tryStop(record)
				return
			end
			if not result.ok then
				self:_attribute(player, "BuzzerLoadError", result.code)
				self._report(`BS-06 session start for {player.UserId}: {result.code}: {tostring(result.detail)}`)
				return
			end
			record.ready = true
			self:_syncWorld(record)
			self:_attribute(player, "BuzzerReady", true)
			self._router:PushState(player)
		end, debug.traceback)
		if not completed then
			record.loading = false
			self._report(`BS-06 player initialization error: {failure}`)
			if self:_current(record) then
				self:_attribute(player, "BuzzerLoadError", "SAVE_UNAVAILABLE")
			else
				self:_tryStop(record)
			end
		end
	end)
end

function Runtime:HandleCommand(player: any, envelope: any)
	if self._stopping then return end
	self._router:HandleCommand(player, envelope)
end

function Runtime:_tryStop(record: any)
	if record.loading or record.stopping or not self._closing[record] then return end
	if not record.session then
		self._closing[record] = nil
		return
	end
	record.stopping = true
	self._spawn(function()
		local ok, result = pcall(function() return record.session:Stop() end)
		record.stopping = false
		if ok and result.ok then
			self._closing[record] = nil
		elseif not ok or result.code ~= "BUSY" then
			self._finalizationFailed = true
			-- No false success: a failed final bank/lease release remains explicit.
			self._report(`BS-06 finalization for {record.player.UserId}: {if ok then tostring(result.code) else tostring(result)}`)
			self._closing[record] = nil
		end
	end)
end

function Runtime:RemovePlayer(player: any)
	local record = self._records[player]
	if not record then return end
	if record.session and record.ready then record.session:CaptureConnectedTime() end
	record.removing = true
	record.ready = false
	self._records[player] = nil
	self._router:Unregister(player)
	disconnectAll(record.connections)
	disconnectAll(record.characterConnections)
	local ok, success, detail = pcall(self._options.world.Remove, player)
	if not ok or not success then self._report(`BS-06 room cleanup: {tostring(if ok then detail else success)}`) end
	self._closing[record] = true
	self:_tryStop(record)
end

function Runtime:Step()
	if self._stopping then return end
	-- Expiration is nonyielding and runs even if a durable lane pump is held.
	self._router:Step()
	for _, record in pairs(self._records) do
		if record.ready then
			record.session:CaptureConnectedTime()
			if not record.pumping then
				record.pumping = true
				self._spawn(function()
					local ok, failure = xpcall(function()
						if not self:_current(record) then return end
						local session = record.session
						-- Reconcile only the exact retained proposal, never rerun UNKNOWN commands.
						session:Reconcile()
						local writable = session:IsWritable()
						if writable then session:Advance(0) end
						if not self:_current(record) then return end
						writable = session:IsWritable()
						if writable and self._options.now() >= session:GetLeaseExpiresAt() - 240 + 90 then
							session:RenewLease()
						end
						if not self:_current(record) then return end
						if self._options.monotonic() - record.lastWorldAttempt >= 2 then
							self:_syncWorld(record)
						end
						self._router:PushState(record.player)
					end, debug.traceback)
					record.pumping = false
					if not ok then self._report(`BS-06 scheduler error: {failure}`) end
				end)
			end
		end
	end
	for record in pairs(self._closing) do self:_tryStop(record) end
end

function Runtime:Start()
	if self._started then return end
	assert(not self._stopping, "cannot restart a stopped runtime")
	self._started = true
	local options = self._options
	table.insert(self._connections, self._remotes.Command.OnServerEvent:Connect(function(player, envelope, ...)
		if select("#", ...) ~= 0 then
			self:HandleCommand(player, nil)
		else
			self:HandleCommand(player, envelope)
		end
	end))
	table.insert(self._connections, options.prompts.PromptTriggered:Connect(function(prompt, player)
		if not self._stopping then self._router:HandlePrompt(prompt, player) end
	end))
	table.insert(self._connections, options.players.PlayerAdded:Connect(function(player) self:AddPlayer(player) end))
	table.insert(self._connections, options.players.PlayerRemoving:Connect(function(player) self:RemovePlayer(player) end))
	table.insert(self._connections, options.heartbeat:Connect(function()
		local now = options.monotonic()
		if now - self._lastStep >= 1 then
			self._lastStep = now
			self:Step()
		end
	end))
	options.bindToClose(function() self:Stop() end)
	for _, player in ipairs(options.players:GetPlayers()) do self:AddPlayer(player) end
end

function Runtime:Stop(): boolean
	if self._stopped then return true end
	if self._stopping then return false end
	self._stopping = true
	disconnectAll(self._connections)
	local players = {}
	for player in pairs(self._records) do table.insert(players, player) end
	for _, player in ipairs(players) do self:RemovePlayer(player) end
	self._router:Destroy()
	local deadline = self._options.monotonic() + (self._options.shutdownSeconds or 25)
	while next(self._closing) ~= nil and self._options.monotonic() < deadline do
		for record in pairs(self._closing) do self:_tryStop(record) end
		self._wait(.1)
	end
	local complete = next(self._closing) == nil and not self._finalizationFailed
	if not complete then self._report("BS-06 shutdown deadline reached; unresolved leases remain protected") end
	self._stopped = complete
	return complete
end

return Runtime
