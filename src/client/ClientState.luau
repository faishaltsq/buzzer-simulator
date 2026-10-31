--!strict
-- Buzzer Simulator — ClientState (BS-08)
-- Owns confirmed snapshots, dashboard lifecycle, and mutation admission/recovery.

local HttpService = game:GetService("HttpService")
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Catalog"))
local GameTypes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameTypes"))

export type DashboardStatus =
	"Closed"
	| "Opening"
	| "Open"
	| "Closing"
	| "Expired"
	| "ConnectionUncertain"

export type TabName =
	"Home"
	| "Feed"
	| "Create"
	| "Missions"
	| "Upgrades"
	| "Workers"

export type InFlightRequest = {
	requestId: string,
	action: string,
	timestamp: number,
	isMutation: boolean,
	lookupRequestId: string?,
	dashboardSessionId: string?,
}

export type UncertainMutation = {
	requestId: string,
	action: string,
	timestamp: number,
	dashboardSessionId: string?,
}

export type StateData = {
	status: DashboardStatus,
	snapshot: any?, -- ProfileSnapshot
	latestRevision: number,
	dashboardSessionId: string?,
	expiresAt: number?,
	serverTime: number?,
	localWatchdogTime: number?,
	closedGenerations: { [string]: boolean },
	currentTab: TabName,
	activeDenial: string?,
	activeError: string?,
	mutationNotice: string?,
	awaitingSnapshotRevision: number?,
	cameraCaptured: boolean,
	inFlightRequests: { [string]: InFlightRequest },
	uncertainMutations: { [string]: UncertainMutation },
	resolvedLookups: { [string]: any },
}

local ClientState = {}
ClientState.__index = ClientState

function ClientState.new(initialSnapshot: any?): any
	local self = setmetatable({}, ClientState)
	local initRev = if initialSnapshot ~= nil and typeof(initialSnapshot.revision) == "number"
		then initialSnapshot.revision
		else 0

	self._data = {
		status = "Closed" :: DashboardStatus,
		snapshot = initialSnapshot,
		latestRevision = initRev,
		dashboardSessionId = nil :: string?,
		expiresAt = nil :: number?,
		serverTime = nil :: number?,
		localWatchdogTime = nil :: number?,
		closedGenerations = {} :: { [string]: boolean },
		currentTab = "Home" :: TabName,
		activeDenial = nil :: string?,
		activeError = nil :: string?,
		mutationNotice = nil :: string?,
		awaitingSnapshotRevision = nil :: number?,
		cameraCaptured = false,
		inFlightRequests = {} :: { [string]: InFlightRequest },
		uncertainMutations = {} :: { [string]: UncertainMutation },
		resolvedLookups = {} :: { [string]: any },
	}
	self._listeners = {} :: { (StateData) -> () }
	return self
end

function ClientState:Get(): StateData
	return self._data
end

function ClientState:GetStatus(): DashboardStatus
	return self._data.status
end

function ClientState:Subscribe(listener: (StateData) -> ()): () -> ()
	table.insert(self._listeners, listener)
	listener(self._data)
	return function()
		for i, fn in ipairs(self._listeners) do
			if fn == listener then
				table.remove(self._listeners, i)
				break
			end
		end
	end
end

function ClientState:_notify()
	for _, listener in ipairs(self._listeners) do
		listener(self._data)
	end
end

-- Generates an 8..64 character ASCII request ID.
function ClientState.GenerateRequestId(prefix: string?): string
	local p = prefix or "req"
	local guid = HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 16)
	return `{p}_{guid}`
end

local MUTATION_FIELDS: { [string]: { [string]: boolean } } = {
	AcceptMission = { missionId = true },
	PublishOrganic = { templateId = true },
	PublishPost = { runId = true, templateId = true },
	ClaimMission = { runId = true },
}
local REPLY_MESSAGES: { [string]: string } = {
	INVALID_INPUT = "This selection is no longer valid. Refresh progress and choose again.",
	UNKNOWN_ACTION = "This action is not available.",
	SESSION_EXPIRED = "The computer session ended. Use a terminal to reopen it.",
	LOCKED = "This action is locked.",
	BUSY = "The server is busy. Refresh progress before trying again.",
	SAVE_UNAVAILABLE = "Saving is unavailable. Progress is read-only.",
	NOT_READY = "This action is not ready. Refresh progress to see the current state.",
	OUT_OF_RANGE = "Move back to the computer terminal.",
	INSUFFICIENT_FUNDS = "There is not enough confirmed Cuan for this action.",
	ALREADY_DONE = "This action has already completed.",
	LIMIT_REACHED = "This action has reached its limit.",
}

local function errorText(code: string): string
	return `{code}: {REPLY_MESSAGES[code] or "The action was rejected. Refresh progress."}`
end

local function missionDefinition(id: any): any?
	if table.find(Catalog.V0Shipped.missionIds, id) == nil then return nil end
	for _, mission in ipairs(Catalog.Missions) do
		if mission.missionId == id then return mission end
	end
	return nil
end

function ClientState:MutationBlockReason(): string?
	local data = self._data
	if data.status ~= "Open" or data.dashboardSessionId == nil then
		return errorText("SESSION_EXPIRED")
	end
	if next(data.uncertainMutations) ~= nil then
		return "BUSY: An earlier action is still unconfirmed. Refresh progress; do not send it again."
	end
	for _, request in pairs(data.inFlightRequests) do
		if request.isMutation then return "BUSY: An action is already being sent." end
	end
	if data.awaitingSnapshotRevision ~= nil then
		return "BUSY: Action accepted. Waiting for confirmed progress."
	end
	if data.snapshot == nil then return errorText("NOT_READY") end
	if data.snapshot.saveStatus ~= "healthy" then
		return errorText(if data.snapshot.saveStatus == "BUSY" then "BUSY" else "SAVE_UNAVAILABLE")
	end
	return nil
end

function ClientState:_rejectMutation(message: string): nil
	self._data.activeError = message
	self:_notify()
	return nil
end

function ClientState:BeginMutation(action: string, payload: any, localNow: number): GameTypes.SessionCommand?
	local fields = MUTATION_FIELDS[action]
	if fields == nil then return self:_rejectMutation(errorText("UNKNOWN_ACTION")) end
	self:CheckLocalWatchdog(localNow)
	local blocked = self:MutationBlockReason()
	if blocked ~= nil then return self:_rejectMutation(blocked) end
	if typeof(payload) ~= "table" or getmetatable(payload) ~= nil then
		return self:_rejectMutation(errorText("INVALID_INPUT"))
	end
	local fieldCount = 0
	for key, value in pairs(payload) do
		if not fields[key] or typeof(value) ~= "string" or #value == 0 or #value > 64 then
			return self:_rejectMutation(errorText("INVALID_INPUT"))
		end
		fieldCount += 1
	end
	if fieldCount ~= (if action == "PublishPost" then 2 else 1) then
		return self:_rejectMutation(errorText("INVALID_INPUT"))
	end

	local snapshot = self._data.snapshot
	local active = snapshot.activeMission
	if action == "AcceptMission" then
		local definition = missionDefinition(payload.missionId)
		if definition == nil then return self:_rejectMutation(errorText("INVALID_INPUT")) end
		if active ~= nil or (snapshot.pendingPost ~= nil and snapshot.pendingPost.mode == "mission") then
			return self:_rejectMutation("NOT_READY: A campaign is already active or resolving.")
		end
		if snapshot.tier < definition.minTier or snapshot.completedMissions < definition.unlockClaims then
			return self:_rejectMutation("LOCKED: This campaign is not unlocked yet.")
		end
	elseif action == "PublishOrganic" then
		if snapshot.pendingPost ~= nil then
			return self:_rejectMutation("NOT_READY: Wait for the current post to finish revealing.")
		end
		local eligible = false
		for _, context in ipairs(Catalog.OrganicContexts) do
			if context.contextId == snapshot.nextOrganicContextId
				and table.find(Catalog.V0Shipped.organicContextIds, context.contextId) ~= nil
				and table.find(context.templates, payload.templateId) ~= nil then
				eligible = true
				break
			end
		end
		if not eligible then return self:_rejectMutation(errorText("INVALID_INPUT")) end
	else
		if active == nil then return self:_rejectMutation("NOT_READY: Accept a campaign first.") end
		if payload.runId ~= active.runId then
			return self:_rejectMutation("INVALID_INPUT: This campaign run changed. Refresh progress.")
		end
		local definition = missionDefinition(active.missionId)
		if definition == nil or table.find(definition.contexts, active.contextId) == nil then
			return self:_rejectMutation(errorText("INVALID_INPUT"))
		end
		if action == "PublishPost" then
			if snapshot.pendingPost ~= nil then
				return self:_rejectMutation("NOT_READY: Wait for the current post to finish revealing.")
			end
			if active.postCount >= 2 then
				return self:_rejectMutation("LIMIT_REACHED: A campaign allows at most two posts.")
			end
			if active.status ~= "accepted" and active.status ~= "resolvingPost" then
				return self:_rejectMutation("NOT_READY: This campaign is not accepting posts.")
			end
			if table.find(definition.templates, payload.templateId) == nil then
				return self:_rejectMutation(errorText("INVALID_INPUT"))
			end
		elseif active.status ~= "readyToClaim" then
			return self:_rejectMutation("NOT_READY: This campaign is not ready to claim.")
		end
	end

	local command: any = {
		action = action,
		requestId = ClientState.GenerateRequestId("mutation"),
		dashboardSessionId = self._data.dashboardSessionId,
		payload = table.clone(payload),
	}
	self:TrackRequest(command.requestId, action, true, localNow, nil, command.dashboardSessionId)
	self._data.activeError = nil
	self._data.mutationNotice = "Sending action..."
	self:_notify()
	return command
end

function ClientState:_acceptSnapshot(snapshot: any): boolean
	if typeof(snapshot) ~= "table" or typeof(snapshot.revision) ~= "number"
		or snapshot.revision < self._data.latestRevision then
		return false
	end
	self._data.snapshot = snapshot
	self._data.latestRevision = snapshot.revision
	local waiting = self._data.awaitingSnapshotRevision
	if waiting ~= nil and snapshot.revision >= waiting then
		self._data.awaitingSnapshotRevision = nil
		self._data.mutationNotice = "Progress confirmed."
	end
	return true
end

-- A Reply revision is not a snapshot. Only confirmed projections advance this watermark.
function ClientState:ApplyStateSnapshot(snapshot: any): boolean
	if not self:_acceptSnapshot(snapshot) then return false end
	self:_notify()
	return true
end

-- 2. Apply OpenComputer (Snapshot.kind == "OpenComputer")
-- Only this server event initiates opening of BuzzerOS.
function ClientState:ApplyOpenComputer(event: any, localNow: number): boolean
	if event == nil or typeof(event.dashboardSessionId) ~= "string" or #event.dashboardSessionId == 0 then
		return false
	end
	local sessionId = event.dashboardSessionId
	if self._data.closedGenerations[sessionId] then
		-- Stale generation already closed locally.
		return false
	end

	local wasOpenOrOpening = (self._data.status == "Open" or self._data.status == "Opening")
	local previousSessionId = self._data.dashboardSessionId
	if previousSessionId ~= nil and previousSessionId ~= sessionId then
		self._data.closedGenerations[previousSessionId] = true
	end

	self:_acceptSnapshot(event.state)

	self._data.dashboardSessionId = sessionId
	self._data.expiresAt = event.expiresAt
	self._data.serverTime = event.serverTime

	local remaining = if typeof(event.expiresAt) == "number" and typeof(event.serverTime) == "number"
		then math.max(0, event.expiresAt - event.serverTime)
		else 600
	self._data.localWatchdogTime = localNow + remaining
	self._data.activeDenial = nil
	self._data.activeError = if next(self._data.uncertainMutations) ~= nil
		then "BUSY: An earlier action is still unconfirmed. Refresh progress."
		else nil

	if wasOpenOrOpening then
		-- Replaced generation in-flight. Retain open state; do not recapture camera.
		self._data.status = "Open"
	else
		-- Fresh open cycle.
		self._data.status = "Opening"
		self._data.cameraCaptured = false
	end

	self:_notify()
	return true
end

-- 3. Apply OpenComputerDenied (Snapshot.kind == "OpenComputerDenied")
function ClientState:ApplyOpenComputerDenied(code: string): boolean
	self._data.activeDenial = code
	self:_notify()
	return true
end

-- 4. Apply ComputerSessionExpired (Snapshot.kind == "ComputerSessionExpired")
function ClientState:ApplySessionExpired(sessionId: string, _reason: string?): boolean
	if sessionId ~= self._data.dashboardSessionId then
		-- Stale expiry for an older session; ignore.
		return false
	end

	self._data.closedGenerations[sessionId] = true
	self._data.status = "Expired"
	self._data.dashboardSessionId = nil
	self._data.expiresAt = nil
	self._data.localWatchdogTime = nil
	self:_notify()
	return true
end

-- 5. Check local watchdog expiration
function ClientState:CheckLocalWatchdog(localNow: number): boolean
	if self._data.status ~= "Open" and self._data.status ~= "Opening" then
		return false
	end
	if self._data.localWatchdogTime == nil or localNow < self._data.localWatchdogTime then
		return false
	end

	local sid = self._data.dashboardSessionId
	if sid ~= nil then
		self._data.closedGenerations[sid] = true
	end
	self._data.status = "Expired"
	self._data.dashboardSessionId = nil
	self._data.expiresAt = nil
	self._data.localWatchdogTime = nil
	self:_notify()
	return true
end

-- 6. Close dashboard locally (Close button, Escape, etc.)
-- Returns CloseComputer payload if there was an active session to close.
function ClientState:CloseLocally(): { action: string, requestId: string, dashboardSessionId: string, payload: any }?
	local currentSid = self._data.dashboardSessionId
	if currentSid ~= nil then
		self._data.closedGenerations[currentSid] = true
	end

	local wasActive = (self._data.status == "Open" or self._data.status == "Opening")
	self._data.status = "Closing"
	self._data.dashboardSessionId = nil
	self._data.expiresAt = nil
	self._data.localWatchdogTime = nil

	self:_notify()

	if wasActive and currentSid ~= nil then
		local closeReqId = ClientState.GenerateRequestId("close")
		self:TrackRequest(closeReqId, "CloseComputer", false, os.clock(), nil, currentSid)
		return {
			action = "CloseComputer",
			requestId = closeReqId,
			dashboardSessionId = currentSid,
			payload = {},
		}
	end
	return nil
end

-- 7. Abort Opening transition (e.g., missing room anchors)
-- Immediately terminates Opening state by setting status to Closed, invalidates session,
-- marks generation as closed, records activeError, notifies subscribers,
-- and returns CloseComputer command to close session on server.
function ClientState:AbortOpening(errorMessage: string?): { action: string, requestId: string, dashboardSessionId: string, payload: any }?
	local currentSid = self._data.dashboardSessionId
	if currentSid ~= nil then
		self._data.closedGenerations[currentSid] = true
	end

	self._data.status = "Closed"
	self._data.dashboardSessionId = nil
	self._data.expiresAt = nil
	self._data.localWatchdogTime = nil
	self._data.cameraCaptured = false
	if errorMessage ~= nil then
		self._data.activeError = errorMessage
	end

	self:_notify()

	if currentSid ~= nil then
		local closeReqId = ClientState.GenerateRequestId("close")
		self:TrackRequest(closeReqId, "CloseComputer", false, os.clock(), nil, currentSid)
		return {
			action = "CloseComputer",
			requestId = closeReqId,
			dashboardSessionId = currentSid,
			payload = {},
		}
	end
	return nil
end

-- 7. Camera opened hook
function ClientState:OnCameraOpened(): boolean
	if self._data.status ~= "Opening" then
		return false
	end
	self._data.status = "Open"
	self._data.cameraCaptured = true
	self:_notify()
	return true
end

-- 8. Camera restored hook
function ClientState:OnCameraRestored()
	self._data.cameraCaptured = false
	if self._data.status == "Closing" or self._data.status == "Expired" then
		self._data.status = "Closed"
	end
	self:_notify()
end

-- 9. Character lost (death, removal, respawn)
function ClientState:OnCharacterLost(): boolean
	local currentSid = self._data.dashboardSessionId
	if currentSid ~= nil then
		self._data.closedGenerations[currentSid] = true
	end
	local wasActive = (self._data.status == "Open" or self._data.status == "Opening")
	self._data.status = "Closed"
	self._data.dashboardSessionId = nil
	self._data.expiresAt = nil
	self._data.localWatchdogTime = nil
	self:_notify()
	return wasActive
end

function ClientState:_resolveMutation(requestId: string, result: any)
	self._data.inFlightRequests[requestId] = nil
	self._data.uncertainMutations[requestId] = nil
	if result.ok then
		if result.revision > self._data.latestRevision then
			self._data.awaitingSnapshotRevision = math.max(self._data.awaitingSnapshotRevision or 0, result.revision)
			self._data.mutationNotice = "Action accepted. Waiting for confirmed progress."
		else
			self._data.mutationNotice = "Progress confirmed."
		end
		self._data.activeError = nil
	else
		self._data.activeError = errorText(result.code)
		self._data.mutationNotice = nil
	end
	if self._data.status == "ConnectionUncertain" and next(self._data.uncertainMutations) == nil then
		self._data.status = if self._data.dashboardSessionId ~= nil then "Open" else "Closed"
	end
end

function ClientState:ApplyReply(reply: any, localNow: number): boolean
	if typeof(reply) ~= "table" or typeof(reply.requestId) ~= "string"
		or typeof(reply.ok) ~= "boolean" or typeof(reply.code) ~= "string" then
		return false
	end
	local inFlight = self._data.inFlightRequests[reply.requestId]
	local uncertain = self._data.uncertainMutations[reply.requestId]
	if inFlight == nil and uncertain == nil then return false end
	if reply.ok and typeof(reply.revision) ~= "number" then return false end

	local original = uncertain or inFlight
	local expiredSessionId = nil
	if uncertain ~= nil or (inFlight ~= nil and inFlight.isMutation) then
		if not reply.ok and (reply.code == "SAVE_UNAVAILABLE" or reply.code == "BUSY") then
			-- The wire omits SessionService's PENDING/UNKNOWN marker for failed writes.
			self._data.inFlightRequests[reply.requestId] = nil
			self._data.uncertainMutations[reply.requestId] = {
				requestId = reply.requestId,
				action = original.action,
				timestamp = original.timestamp,
				dashboardSessionId = original.dashboardSessionId,
			}
			self._data.activeError = `{reply.code}: The action is still unconfirmed. Refresh progress; do not send it again.`
			self._data.mutationNotice = nil
		else
			self:_resolveMutation(reply.requestId, reply)
			if reply.code == "SESSION_EXPIRED" then expiredSessionId = original.dashboardSessionId end
		end
	else
		self._data.inFlightRequests[reply.requestId] = nil
		if reply.code == "SESSION_EXPIRED" then expiredSessionId = inFlight.dashboardSessionId end
		if reply.ok and inFlight.action == "GetSnapshot" and typeof(reply.data) == "table" then
			self:_acceptSnapshot(reply.data.snapshot)
			local lookup = reply.data.lookup
			-- Query correlation and original-ID correlation are both required.
			if typeof(lookup) == "table" and inFlight.lookupRequestId ~= nil
				and lookup.originalRequestId == inFlight.lookupRequestId then
				local id = inFlight.lookupRequestId
				local pending = self._data.inFlightRequests[id]
				local unresolved = self._data.uncertainMutations[id]
					or (if pending ~= nil and pending.isMutation then pending else nil)
				if unresolved ~= nil then
					local result = lookup.originalResult
					if (lookup.status == "APPLIED" and typeof(result) == "table" and result.ok == true
							and result.code == "OK" and typeof(result.revision) == "number")
						or (lookup.status == "REJECTED" and typeof(result) == "table" and result.ok == false
							and typeof(result.code) == "string") then
						self._data.resolvedLookups[id] = lookup
						self:_resolveMutation(id, result)
						if result.code == "SESSION_EXPIRED" then expiredSessionId = unresolved.dashboardSessionId end
					elseif lookup.status == "PENDING" or lookup.status == "UNKNOWN" then
						self._data.resolvedLookups[id] = lookup
						self._data.activeError = if lookup.status == "PENDING"
							then "BUSY: The earlier action is still pending. Refresh progress to check again."
							else "BUSY: The earlier action is still unconfirmed. Refresh progress; do not send it again."
						self._data.mutationNotice = nil
					end
				end
			end
		elseif not reply.ok then
			self._data.activeError = errorText(reply.code)
		end
	end

	if expiredSessionId ~= nil then
		self._data.closedGenerations[expiredSessionId] = true
		if expiredSessionId == self._data.dashboardSessionId then
			self._data.status = "Expired"
			self._data.dashboardSessionId = nil
			self._data.expiresAt = nil
			self._data.localWatchdogTime = nil
			self:_notify()
			return true
		end
		self:_notify()
		return false
	end
	-- Metadata never establishes a session or revives a closed generation.
	local metadata = reply.dashboardSession
	if reply.code ~= "SESSION_EXPIRED" and typeof(metadata) == "table"
		and self._data.dashboardSessionId ~= nil
		and metadata.dashboardSessionId == self._data.dashboardSessionId
		and typeof(metadata.expiresAt) == "number" then
		self._data.expiresAt = math.max(self._data.expiresAt or 0, metadata.expiresAt)
		local serverTime = if typeof(reply.serverTime) == "number" then reply.serverTime else localNow
		self._data.localWatchdogTime = localNow + math.max(0, self._data.expiresAt - serverTime)
	end
	self:_notify()
	return reply.code ~= "SESSION_EXPIRED"
end

-- 11. Register in-flight request
function ClientState:TrackRequest(
	requestId: string,
	action: string,
	isMutation: boolean,
	localNow: number,
	lookupRequestId: string?,
	dashboardSessionId: string?
)
	self._data.inFlightRequests[requestId] = {
		requestId = requestId,
		action = action,
		timestamp = localNow,
		isMutation = isMutation,
		lookupRequestId = lookupRequestId,
		dashboardSessionId = if action == "GetSnapshot" then nil else dashboardSessionId or self._data.dashboardSessionId,
	}
end

function ClientState:_progressQuery(localNow: number, originalRequestId: string?): GameTypes.GetSnapshotCommand
	local command: GameTypes.GetSnapshotCommand = {
		action = "GetSnapshot",
		requestId = ClientState.GenerateRequestId("progress"),
		payload = if originalRequestId ~= nil then { lookupRequestId = originalRequestId } else {},
	}
	self:TrackRequest(command.requestId, command.action, false, localNow, originalRequestId)
	return command
end

function ClientState:RefreshProgress(localNow: number): GameTypes.GetSnapshotCommand
	local originalId: string? = nil
	local oldest = math.huge
	for id, request in pairs(self._data.uncertainMutations) do
		if request.timestamp < oldest or (request.timestamp == oldest and (originalId == nil or id < originalId)) then
			originalId = id
			oldest = request.timestamp
		end
	end
	if originalId == nil then
		for id, request in pairs(self._data.inFlightRequests) do
			if request.isMutation
				and (request.timestamp < oldest or (request.timestamp == oldest and (originalId == nil or id < originalId))) then
				originalId = id
				oldest = request.timestamp
			end
		end
	end
	local command = self:_progressQuery(localNow, originalId)
	self:_notify()
	return command
end

-- Timeouts reserve the original intent. Only explicit reads are sent afterward.
function ClientState:CheckTimeouts(localNow: number, timeoutSecs: number?): { GameTypes.GetSnapshotCommand }
	local limit = timeoutSecs or 6
	local timedOutMutations: { string } = {}
	for requestId, request in pairs(self._data.inFlightRequests) do
		if localNow - request.timestamp >= limit then
			self._data.inFlightRequests[requestId] = nil
			if request.isMutation then
				self._data.uncertainMutations[requestId] = {
					requestId = requestId,
					action = request.action,
					timestamp = request.timestamp,
					dashboardSessionId = request.dashboardSessionId,
				}
				table.insert(timedOutMutations, requestId)
			end
		end
	end
	local queriesToSend: { GameTypes.GetSnapshotCommand } = {}
	for _, requestId in ipairs(timedOutMutations) do
		table.insert(queriesToSend, self:_progressQuery(localNow, requestId))
	end
	if #queriesToSend > 0 then
		self._data.activeError = "BUSY: Connection uncertain. Refreshing progress; do not send the action again."
		self._data.mutationNotice = nil
		self:_notify()
	end
	return queriesToSend
end

-- 13. Set active navigation tab
function ClientState:SetTab(tab: TabName)
	self._data.currentTab = tab
	self:_notify()
end

-- 14. Accessors
function ClientState:GetConfirmedBalance(): number
	if self._data.snapshot ~= nil and typeof(self._data.snapshot.balance) == "number" then
		return self._data.snapshot.balance
	end
	return 0
end

function ClientState:GetPendingWorkerCuan(): number
	if self._data.snapshot ~= nil and typeof(self._data.snapshot.pendingWorkerCuan) == "number" then
		return self._data.snapshot.pendingWorkerCuan
	end
	return 0
end

function ClientState:GetIncomePerSecond(): number
	if self._data.snapshot ~= nil and typeof(self._data.snapshot.incomePerSecond) == "number" then
		return self._data.snapshot.incomePerSecond
	end
	return 0
end

function ClientState:GetTier(): number
	if self._data.snapshot ~= nil and typeof(self._data.snapshot.tier) == "number" then
		return self._data.snapshot.tier
	end
	return 0
end

function ClientState:IsSaveBlocked(): boolean
	if self._data.snapshot ~= nil and self._data.snapshot.saveStatus ~= "healthy" then
		return true
	end
	return false
end

return ClientState