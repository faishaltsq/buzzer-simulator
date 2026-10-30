--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))

local NetRouter = {}
NetRouter.__index = NetRouter

local CACHE_LIMIT = 64
local IDLE_SECONDS = 600
local WIRE_CODES = {
	OK = true, INVALID_INPUT = true, UNKNOWN_ACTION = true, SESSION_EXPIRED = true,
	LOCKED = true, BUSY = true, SAVE_UNAVAILABLE = true, NOT_READY = true,
	OUT_OF_RANGE = true, INSUFFICIENT_FUNDS = true, ALREADY_DONE = true, LIMIT_REACHED = true,
}
-- Frozen ReplyCode translation: unknown identifiers/mismatched runs are invalid
-- input; occupied/pending domain state is not ready; invalid authored content
-- is unavailable. Unknown internal codes fail closed and are reported locally.
local DOMAIN_CODES = {
	UNKNOWN_MISSION = "INVALID_INPUT", UNKNOWN_TEMPLATE = "INVALID_INPUT",
	UNKNOWN_CONTEXT = "INVALID_INPUT", RUN_MISMATCH = "INVALID_INPUT",
	UNKNOWN_DEVICE = "INVALID_INPUT", UNKNOWN_DESK = "INVALID_INPUT", UNKNOWN_WORKER = "INVALID_INPUT",
	NO_ACTIVE_MISSION = "NOT_READY", MISSION_ACTIVE = "NOT_READY", PENDING_POST = "NOT_READY",
	NOT_DUE = "NOT_READY", NO_PENDING_POST = "NOT_READY", INVALID_CONTENT = "SAVE_UNAVAILABLE",
}
local FIELDS = {
	GetSnapshot = { lookupRequestId = true }, AcceptMission = { missionId = true },
	PublishOrganic = { templateId = true }, PublishPost = { runId = true, templateId = true },
	ClaimMission = { runId = true }, BuyDevice = { deviceId = true }, BuyDesk = { slotIndex = true },
	HireWorker = { slotIndex = true, roleId = true }, CloseComputer = {},
}
local FIELD_COUNTS = {
	GetSnapshot = 1, AcceptMission = 1, PublishOrganic = 1, PublishPost = 2,
	ClaimMission = 1, BuyDevice = 1, BuyDesk = 1, HireWorker = 2, CloseComputer = 0,
}
local ENVELOPE_FIELDS = { requestId = true, action = true, payload = true, dashboardSessionId = true }
local missions: { [string]: boolean } = {}
local devices: { [string]: boolean } = {}
local organicTemplates: { [string]: boolean } = {}
local missionTemplates: { [string]: boolean } = {}
for _, mission in ipairs(Catalog.Missions) do
	missions[mission.missionId] = true
	for _, id in ipairs(mission.templates) do missionTemplates[id] = true end
end
for _, device in ipairs(Catalog.Devices) do devices[device.id] = true end
for _, context in ipairs(Catalog.OrganicContexts) do
	for _, id in ipairs(context.templates) do organicTemplates[id] = true end
end

local function wireCode(code: string): string
	if WIRE_CODES[code] then return code end
	if DOMAIN_CODES[code] then return DOMAIN_CODES[code] end
	warn(`NetRouter: unexpected result code {tostring(code)}`)
	return "SAVE_UNAVAILABLE"
end

local function ascii(value: any, minimum: number, maximum: number): boolean
	return typeof(value) == "string" and #value >= minimum and #value <= maximum
		and string.find(value, "[^%z\1-\127]") == nil
end
local function requestId(value: any): boolean
	return ascii(value, 8, 64)
end

-- Count only the bounded outer dictionaries. Values are checked as scalars
-- below, so cycles/deep client graphs never enter a recursive traversal.
local function exact(value: any, allowed: any, maximum: number): (boolean, number)
	if typeof(value) ~= "table" or getmetatable(value) ~= nil then return false, 0 end
	local count = 0
	for key in next, value do
		count += 1
		if count > maximum or typeof(key) ~= "string" or not allowed[key] then return false, count end
	end
	return true, count
end

local function validate(envelope: any): (any?, string)
	local shape = exact(envelope, ENVELOPE_FIELDS, 4)
	if not shape or not requestId(rawget(envelope, "requestId")) then return nil, "INVALID_INPUT" end
	local action = rawget(envelope, "action")
	if not ascii(action, 1, 32) then return nil, "INVALID_INPUT" end
	local fields = FIELDS[action]
	if fields == nil then return nil, "UNKNOWN_ACTION" end
	local payload = rawget(envelope, "payload")
	local payloadOk, count = exact(payload, fields, FIELD_COUNTS[action])
	if not payloadOk then return nil, "INVALID_INPUT" end
	local sessionId = rawget(envelope, "dashboardSessionId")
	if action == "GetSnapshot" then
		if sessionId ~= nil then return nil, "INVALID_INPUT" end
		local lookup = rawget(payload, "lookupRequestId")
		if lookup ~= nil and (not requestId(lookup) or lookup == envelope.requestId) then return nil, "INVALID_INPUT" end
	elseif not ascii(sessionId, 1, 64) or count ~= FIELD_COUNTS[action] then
		return nil, "INVALID_INPUT"
	end
	if action == "AcceptMission" and (not ascii(payload.missionId, 1, 64) or not missions[payload.missionId]) then
		return nil, "INVALID_INPUT"
	elseif action == "BuyDevice" and (not ascii(payload.deviceId, 1, 64) or not devices[payload.deviceId]) then
		return nil, "INVALID_INPUT"
	elseif action == "PublishOrganic" and (not ascii(payload.templateId, 1, 64) or not organicTemplates[payload.templateId]) then
		return nil, "INVALID_INPUT"
	elseif action == "PublishPost" and (not ascii(payload.templateId, 1, 64) or not missionTemplates[payload.templateId]) then
		return nil, "INVALID_INPUT"
	end
	if (action == "PublishPost" or action == "ClaimMission") and not ascii(payload.runId, 1, 64) then
		return nil, "INVALID_INPUT"
	end
	if (action == "BuyDesk" or action == "HireWorker") and payload.slotIndex ~= 1 and payload.slotIndex ~= 2 then
		return nil, "INVALID_INPUT"
	end
	if action == "HireWorker" and payload.roleId ~= "trainee" then return nil, "INVALID_INPUT" end
	local copy = {}
	for key, value in next, payload do copy[key] = value end
	return { requestId = envelope.requestId, action = action, payload = copy, dashboardSessionId = sessionId }, "OK"
end

local function sameIntent(entry: any, command: any): boolean
	if entry.action ~= command.action then return false end
	for field in pairs(FIELDS[command.action]) do
		if entry.payload[field] ~= command.payload[field] then return false end
	end
	return true
end

local function alive(player: any): boolean
	local character = player.Character
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart")
end

local function resultData(data: any): any?
	-- Session mutation results expose only bounded durable result identifiers.
	if typeof(data) ~= "table" or typeof(data.resultIds) ~= "table" then return nil end
	local ids = {}
	for index = 1, math.min(#data.resultIds, 8) do
		local id = data.resultIds[index]
		if typeof(id) == "string" and #id <= 128 then table.insert(ids, id) end
	end
	return { resultIds = ids }
end

function NetRouter.EnsureRemotes(storage: Instance): any
	local folder: Instance? = nil
	for _, child in ipairs(storage:GetChildren()) do
		if child.Name == "BuzzerRemotes" then
			assert(folder == nil and child:IsA("Folder"), "NetRouter: conflicting BuzzerRemotes")
			folder = child
		end
	end
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "BuzzerRemotes"
		folder.Parent = storage
	end
	local remotes: any = {}
	for _, child in ipairs(folder:GetChildren()) do
		assert((child.Name == "Command" or child.Name == "Reply" or child.Name == "Snapshot")
			and child:IsA("RemoteEvent") and remotes[child.Name] == nil, "NetRouter: conflicting remote child")
		remotes[child.Name] = child
	end
	for _, name in ipairs({ "Command", "Reply", "Snapshot" }) do
		if remotes[name] == nil then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
			remotes[name] = remote
		end
	end
	return remotes
end

function NetRouter.new(options: any): any
	assert(options.world and options.sendReply and options.sendSnapshot, "NetRouter: world and private transports required")
	return setmetatable({
		_world = options.world, _now = options.now or os.time, _monotonic = options.monotonic or os.clock,
		_guid = options.guid or function() return HttpService:GenerateGUID(false) end,
		_sendReply = options.sendReply, _sendSnapshot = options.sendSnapshot,
		_onConfirmed = options.onConfirmed, _beforeMutation = options.beforeMutation,
		_records = {}, _destroyed = false,
	}, NetRouter)
end

function NetRouter:Register(player: any, session: any)
	assert(not self._destroyed, "NetRouter: destroyed")
	self._records[player] = {
		session = session, dashboard = nil, cache = {}, order = {},
		windowStart = self._monotonic(), count = 0, lastPublish = -math.huge, lastPush = -math.huge,
	}
end

function NetRouter:Unregister(player: any)
	self._records[player] = nil
end

function NetRouter:_send(player: any, record: any, callback: any, message: any): boolean
	if self._records[player] ~= record then return false end
	local ok, err = pcall(callback, player, message)
	if not ok then warn(`NetRouter transport: {tostring(err)}`) end
	return ok
end

function NetRouter:_expire(player: any, record: any, reason: string)
	local dashboard = record.dashboard
	if dashboard == nil then return end
	record.dashboard = nil
	self:_send(player, record, self._sendSnapshot, {
		kind = "ComputerSessionExpired", dashboardSessionId = dashboard.id, reason = reason,
	})
end

function NetRouter:_current(player: any, record: any)
	if record.dashboard == nil then return end
	if not alive(player) or player.Character ~= record.dashboard.character then
		self:_expire(player, record, "CHARACTER_LOST")
	elseif self._monotonic() >= record.dashboard.deadline then
		self:_expire(player, record, "IDLE")
	end
end

function NetRouter:_reply(player: any, record: any, id: string, result: any, data: any?): boolean
	if self._records[player] ~= record then return false end
	self:_current(player, record)
	local read = record.session:ReadSnapshot()
	local dashboard = record.dashboard
	return self:_send(player, record, self._sendReply, {
		requestId = id, ok = result.ok, code = wireCode(result.code),
		revision = result.revision or (if read.snapshot then read.snapshot.revision else 0), serverTime = self._now(),
		dashboardSession = if dashboard then { dashboardSessionId = dashboard.id, expiresAt = dashboard.expiresAt } else nil,
		data = data,
	})
end

function NetRouter:_remember(record: any, command: any): any?
	while #record.order >= CACHE_LIMIT do
		local index = nil
		for i, id in ipairs(record.order) do
			if not record.cache[id].pending then index = i break end
		end
		if index == nil then return nil end
		local id = table.remove(record.order, index)
		record.cache[id] = nil
	end
	local entry = { action = command.action, payload = command.payload, pending = true }
	record.cache[command.requestId] = entry
	table.insert(record.order, command.requestId)
	return entry
end

function NetRouter:_lookup(record: any, id: string, lookup: any): any
	-- A confirmed session result always outranks the router's older local state.
	if lookup ~= nil and lookup.status == "APPLIED" then
		local original = lookup.originalResult
		return { originalRequestId = id, status = "APPLIED", originalResult = {
			ok = true, code = "OK", revision = original.revision, data = resultData(original.data),
		} }
	end
	local entry = record.cache[id]
	if entry ~= nil and entry.action ~= "GetSnapshot" and entry.action ~= "CloseComputer" then
		if entry.pending then return { originalRequestId = id, status = "PENDING" } end
		if entry.result ~= nil then
			return { originalRequestId = id, status = if entry.result.ok then "APPLIED" else "REJECTED", originalResult = {
				ok = entry.result.ok, code = wireCode(entry.result.code), revision = entry.result.revision,
				data = resultData(entry.result.data),
			} }
		end
	end
	if lookup ~= nil and lookup.status == "REJECTED" then
		return { originalRequestId = id, status = "REJECTED", originalResult = {
			ok = false, code = wireCode(lookup.originalResult.code), revision = lookup.originalResult.revision,
			data = resultData(lookup.originalResult.data),
		} }
	end
	return { originalRequestId = id, status = if lookup and lookup.status == "PENDING" then "PENDING" else "UNKNOWN" }
end

function NetRouter:HandleCommand(player: any, envelope: any): boolean
	local record = self._records[player]
	if record == nil then return false end
	self:_current(player, record)
	local now = self._monotonic()
	if now - record.windowStart >= 1 then record.windowStart, record.count = now, 0 end
	record.count = math.min(record.count + 1, 9)
	local id = if typeof(envelope) == "table" then rawget(envelope, "requestId") else nil
	if not requestId(id) then return false end
	if record.count > 8 then return self:_reply(player, record, id, { ok = false, code = "BUSY" }) end
	local command, code = validate(envelope)
	if command == nil then return self:_reply(player, record, id, { ok = false, code = code }) end
	local action = command.action
	local entry = record.cache[id]
	if entry ~= nil and not sameIntent(entry, command) then
		return self:_reply(player, record, id, { ok = false, code = "INVALID_INPUT" })
	end
	if action == "GetSnapshot" then
		local own = record.session:ReadSnapshot(id)
		if entry == nil and own.lookup ~= nil and own.lookup.status ~= "UNKNOWN" then
			return self:_reply(player, record, id, { ok = false, code = "INVALID_INPUT" })
		end
		if entry == nil then
			entry = self:_remember(record, command)
			if entry == nil then return self:_reply(player, record, id, { ok = false, code = "BUSY" }) end
		end
		local read = record.session:Snapshot(command.payload.lookupRequestId)
		entry.pending = false
		if self._records[player] ~= record then return false end
		if not read.ok or read.snapshot == nil then return self:_reply(player, record, id, read) end
		local lookup = if command.payload.lookupRequestId then self:_lookup(record, command.payload.lookupRequestId, read.lookup) else nil
		return self:_reply(player, record, id, read, { snapshot = read.snapshot, lookup = lookup })
	end
	if action ~= "CloseComputer" then
		local loaded = record.session:ReadSnapshot()
		if not loaded.ok or loaded.snapshot == nil then
			return self:_reply(player, record, id, { ok = false, code = "NOT_READY" })
		end
		-- The session's authoritative encoder also bounds escaped ASCII. Check
		-- before idle admission; never forward the computed intent to Mutate.
		local encodable = pcall(record.session._canonicalIntent, action, command.payload)
		if not encodable then
			return self:_reply(player, record, id, { ok = false, code = "INVALID_INPUT" })
		end
	end
	local dashboard = record.dashboard
	if dashboard == nil or dashboard.id ~= command.dashboardSessionId then
		return self:_reply(player, record, id, { ok = false, code = "SESSION_EXPIRED" })
	end
	if action == "CloseComputer" then
		if entry == nil then
			local prior = record.session:ReadSnapshot(id)
			if prior.lookup ~= nil and prior.lookup.status ~= "UNKNOWN" then
				return self:_reply(player, record, id, { ok = false, code = "INVALID_INPUT" })
			end
			entry = self:_remember(record, command)
			if entry == nil then return self:_reply(player, record, id, { ok = false, code = "BUSY" }) end
		end
		entry.pending = false
		record.dashboard = nil
		return self:_reply(player, record, id, { ok = true, code = "OK" })
	end
	if entry ~= nil and entry.pending then return self:_reply(player, record, id, { ok = false, code = "BUSY" }) end
	local prior = record.session:ReadSnapshot(id)
	if entry ~= nil and entry.result ~= nil
		and (entry.result.ok or prior.lookup == nil or prior.lookup.status ~= "APPLIED") then
		return self:_reply(player, record, id, entry.result, resultData(entry.result.data))
	end
	local recovery = entry ~= nil or (prior.lookup ~= nil and prior.lookup.status ~= "UNKNOWN")
	if not recovery then
		local writable, denied = record.session:IsWritable()
		if not writable then return self:_reply(player, record, id, { ok = false, code = denied or "NOT_READY" }) end
		if (action == "PublishOrganic" or action == "PublishPost") and now - record.lastPublish < 2 then
			return self:_reply(player, record, id, { ok = false, code = "BUSY" })
		end
	end
	entry = entry or self:_remember(record, command)
	if entry == nil then return self:_reply(player, record, id, { ok = false, code = "BUSY" }) end
	entry.pending = true
	if not recovery then
		dashboard.deadline = now + IDLE_SECONDS
		dashboard.expiresAt = self._now() + IDLE_SECONDS
		if action == "PublishOrganic" or action == "PublishPost" then record.lastPublish = now end
	end
	-- No yielding operation may occur between admission and reservation. Runtime's
	-- hook captures connected time without writing; domain owns its only write lane.
	local ok, result = pcall(function(): { ok: boolean, code: string, revision: number?, data: any?, lookup: string? }
		if self._beforeMutation ~= nil then self._beforeMutation(player) end
		if self._records[player] ~= record then return { ok = false, code = "LOCKED" } end
		return record.session:Mutate({ requestId = id, action = action, payload = command.payload })
	end)
	entry.pending = false
	if not ok then error(result, 0) end
	if result.ok or result.lookup == "REJECTED" then entry.result = result end
	if self._records[player] ~= record then return false end
	if result.ok then
		local read = record.session:ReadSnapshot()
		if self._onConfirmed ~= nil then
			local synced, err = pcall(self._onConfirmed, player, read.snapshot)
			if not synced then warn(`NetRouter confirmed presentation: {tostring(err)}`) end
		end
		self:_send(player, record, self._sendSnapshot, { kind = "State", state = read.snapshot })
	end
	return self:_reply(player, record, id, result, resultData(result.data))
end

function NetRouter:HandlePrompt(prompt: any, player: any): boolean
	local record = self._records[player]
	if record == nil then return false end
	self:_current(player, record)
	local send = self._send :: typeof(NetRouter._send)
	local function deny(code: string): boolean
		send(self, player, record, self._sendSnapshot, { kind = "OpenComputerDenied", code = code })
		return false
	end
	local read = record.session:ReadSnapshot()
	if not read.ok or read.snapshot == nil then return deny("NOT_READY") end
	local writable, code = record.session:IsWritable()
	if not writable then return deny(if code == "SAVE_UNAVAILABLE" then "SAVE_UNAVAILABLE" else "NOT_READY") end
	if not alive(player) then return deny("INVALID_STATE") end
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return deny("INVALID_STATE") end
	local ok, valid, detail = pcall(function()
		if self._world.GetPrompt(player) ~= prompt then return false, "identity" end
		return self._world.ValidateDashboardPrompt(player, prompt)
	end)
	if not ok then
		warn(`NetRouter prompt world: {tostring(valid)}`)
		return deny("INVALID_STATE")
	end
	if not valid then
		return deny(if typeof(detail) == "string" and string.find(detail, "studs", 1, true) then "OUT_OF_RANGE" else "INVALID_STATE")
	end
	if self._records[player] ~= record then return false end
	local id = self._guid()
	assert(ascii(id, 1, 64), "NetRouter: invalid generated dashboard ID")
	local expiresAt = self._now() + IDLE_SECONDS
	record.dashboard = { id = id, expiresAt = expiresAt, deadline = self._monotonic() + IDLE_SECONDS, character = player.Character }
	return send(self, player, record, self._sendSnapshot, {
		kind = "OpenComputer", dashboardSessionId = id, expiresAt = expiresAt, serverTime = self._now(), state = read.snapshot,
	})
end

function NetRouter:CharacterLost(player: any)
	local record = self._records[player]
	if record ~= nil then self:_expire(player, record, "CHARACTER_LOST") end
end

function NetRouter:Step()
	for player, record in pairs(self._records) do self:_current(player, record) end
end

function NetRouter:PushState(player: any): boolean
	local record = self._records[player]
	if record == nil or self._monotonic() - record.lastPush < 2 then return false end
	local read = record.session:ReadSnapshot()
	if not read.ok or read.snapshot == nil then return false end
	record.lastPush = self._monotonic()
	return self:_send(player, record, self._sendSnapshot, { kind = "State", state = read.snapshot })
end

function NetRouter:Destroy()
	self._destroyed = true
	table.clear(self._records)
end

return NetRouter
