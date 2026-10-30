--!strict
-- Buzzer Simulator — ClientState (BS-07)
-- Pure client state container and reducer for BuzzerOS shell & HUD.
-- Contract sources: docs/03, docs/05, docs/14.

local HttpService = game:GetService("HttpService")

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

-- 1. Apply State snapshot (Snapshot.kind == "State")
-- Never opens the dashboard; updates confirmed balance and metadata if revision >= latestRevision.
function ClientState:ApplyStateSnapshot(snapshot: any): boolean
	if snapshot == nil or typeof(snapshot.revision) ~= "number" then
		return false
	end
	if snapshot.revision < self._data.latestRevision then
		-- Out-of-order older revision; drop to prevent balance regression.
		return false
	end

	self._data.snapshot = snapshot
	self._data.latestRevision = snapshot.revision
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

	if event.state ~= nil and typeof(event.state.revision) == "number" then
		if event.state.revision >= self._data.latestRevision then
			self._data.snapshot = event.state
			self._data.latestRevision = event.state.revision
		end
	end

	self._data.dashboardSessionId = sessionId
	self._data.expiresAt = event.expiresAt
	self._data.serverTime = event.serverTime

	local remaining = if typeof(event.expiresAt) == "number" and typeof(event.serverTime) == "number"
		then math.max(0, event.expiresAt - event.serverTime)
		else 600
	self._data.localWatchdogTime = localNow + remaining
	self._data.activeDenial = nil
	self._data.activeError = nil

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

function ClientState:ApplyReply(reply: any, localNow: number): boolean
	if reply == nil or typeof(reply.requestId) ~= "string" then
		return false
	end

	-- Correlate in-flight request
	local inFlight = self._data.inFlightRequests[reply.requestId]
	local requestSessionId = if inFlight ~= nil then inFlight.dashboardSessionId else nil
	if inFlight ~= nil then
		self._data.inFlightRequests[reply.requestId] = nil
	end

	-- Handle SESSION_EXPIRED reply
	if reply.code == "SESSION_EXPIRED" then
		-- Expire only if this request was bound to the active dashboard session,
		-- or if the reply explicitly targets the current session.
		local currentSid = self._data.dashboardSessionId
		local targetSessionId = requestSessionId
		if targetSessionId == nil and reply.dashboardSession ~= nil and typeof(reply.dashboardSession.dashboardSessionId) == "string" then
			targetSessionId = reply.dashboardSession.dashboardSessionId
		end

		if currentSid ~= nil and targetSessionId == currentSid then
			self._data.closedGenerations[currentSid] = true
			self._data.dashboardSessionId = nil
			self._data.status = "Expired"
			self._data.expiresAt = nil
			self._data.localWatchdogTime = nil
			self:_notify()
			return true
		else
			-- Uncorrelated old reply or reply for an already-closed generation:
			-- Never close or expire a newer/active session.
			if targetSessionId ~= nil then
				self._data.closedGenerations[targetSessionId] = true
			end
			return false
		end
	end

	-- Revision check: never regress confirmed state
	if typeof(reply.revision) == "number" and reply.revision > self._data.latestRevision then
		self._data.latestRevision = reply.revision
	end

	-- Dashboard metadata in reply: refreshes watchdog ONLY if matching current active session
	if reply.dashboardSession ~= nil and typeof(reply.dashboardSession.dashboardSessionId) == "string" then
		if reply.dashboardSession.dashboardSessionId == self._data.dashboardSessionId then
			self._data.expiresAt = reply.dashboardSession.expiresAt
			local srvTime = reply.serverTime or localNow
			local diff = math.max(0, reply.dashboardSession.expiresAt - srvTime)
			self._data.localWatchdogTime = localNow + diff
		end
	end

	-- Reconcile GetSnapshot data
	if reply.data ~= nil and typeof(reply.data) == "table" then
		if reply.data.snapshot ~= nil and typeof(reply.data.snapshot.revision) == "number" then
			if reply.data.snapshot.revision >= self._data.latestRevision then
				self._data.snapshot = reply.data.snapshot
				self._data.latestRevision = reply.data.snapshot.revision
			end
		end

		if reply.data.lookup ~= nil and typeof(reply.data.lookup.originalRequestId) == "string" then
			local lookup = reply.data.lookup
			self._data.resolvedLookups[lookup.originalRequestId] = lookup

			if lookup.status == "APPLIED" or lookup.status == "REJECTED" then
				self._data.uncertainMutations[lookup.originalRequestId] = nil
				if self._data.status == "ConnectionUncertain" and next(self._data.uncertainMutations) == nil then
					self._data.status = if self._data.dashboardSessionId ~= nil then "Open" else "Closed"
					self._data.activeError = nil
				end
			elseif lookup.status == "UNKNOWN" then
				-- Never retry or re-issue on UNKNOWN
				self._data.uncertainMutations[lookup.originalRequestId] = nil
				if self._data.status == "ConnectionUncertain" and next(self._data.uncertainMutations) == nil then
					self._data.status = if self._data.dashboardSessionId ~= nil then "Open" else "Closed"
					self._data.activeError = nil
				end
			end
		end
	end

	self:_notify()
	return true
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
		dashboardSessionId = dashboardSessionId or self._data.dashboardSessionId,
	}
end

-- 12. Check request timeouts (6-second timeout for mutations)
function ClientState:CheckTimeouts(localNow: number, timeoutSecs: number?): { { action: string, requestId: string, payload: any } }
	local limit = timeoutSecs or 6
	local queriesToSend: { { action: string, requestId: string, payload: any } } = {}

	for reqId, req in pairs(self._data.inFlightRequests) do
		if (localNow - req.timestamp) >= limit then
			self._data.inFlightRequests[reqId] = nil
			if req.isMutation then
				-- Mark mutation uncertain
				self._data.uncertainMutations[reqId] = {
					requestId = reqId,
					action = req.action,
					timestamp = req.timestamp,
				}
				self._data.status = "ConnectionUncertain"
				self._data.activeError = "Connection uncertain. Refreshing progress..."

				-- Generate fresh query to reconcile
				local queryReqId = ClientState.GenerateRequestId("recon")
				table.insert(queriesToSend, {
					action = "GetSnapshot",
					requestId = queryReqId,
					payload = { lookupRequestId = reqId },
				})
			end
		end
	end

	if #queriesToSend > 0 then
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
	if self._data.snapshot ~= nil and self._data.snapshot.saveStatus == "SAVE_UNAVAILABLE" then
		return true
	end
	return false
end

return ClientState