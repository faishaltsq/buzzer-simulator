--!strict
-- Buzzer Simulator — GameTypes (BS-01, types only; contract source: docs/03).
-- No runtime router, remotes, or session logic in BS-01. Types frozen at IC-0.

export type RequestId = string

export type FitKind = "strong" | "weak"

export type MissionStatus = "accepted" | "resolvingPost" | "readyToClaim" | "claimed"

export type PostMode = "organic" | "mission"

export type SaveStatus = "healthy" | "SAVE_UNAVAILABLE" | "BUSY"

export type DashboardSessionId = string

-- v1 Profile (03 profile contract). Persisted payload only; envelope wraps it.
export type MutationOutcome = {
	requestId: RequestId,
	action: CommandAction,
	intent: string, -- canonical bounded action+payload digest
	ok: true,
	code: "OK",
	revision: number,
	resultIds: { string }?, -- minimal post/run/purchase identity for replay
}

export type WorkerEntry = {
	hireId: string,
	roleId: "trainee",
	slotIndex: number, -- 1..2
}

export type ActiveMission = {
	missionId: string,
	runId: string,
	contextId: string,
	status: MissionStatus,
	accumulatedImpact: number, -- nonnegative integer
	postCount: number, -- 0..2
}

export type PendingPost = {
	postId: string,
	mode: PostMode,
	missionRunId: string?, -- present when mode == "mission"
	contextId: string,
	templateId: string,
	publishedAt: number, -- server epoch seconds
	settleAt: number,
	finalImpact: number, -- frozen at publish
	organicCuan: number, -- frozen at publish
}

export type OwnPostSummary = {
	postId: string,
	mode: PostMode,
	contextId: string,
	templateId: string,
	finalImpact: number,
	organicCuan: number,
	publishedAt: number,
	missionRunId: string?,
}

export type Profile = {
	balance: number, -- nonnegative integer
	lifetimeEarned: number, -- nonnegative integer
	completedMissions: number, -- nonnegative integer (claims)
	deviceId: string, -- catalog device ID
	propertyId: "bedroom",
	ownedDesks: { number }, -- slot indices 1..2, ascending, unique
	workers: { WorkerEntry }, -- distinct slot indices 1..2
	fractionalIncome: number, -- in [0,1)
	claimedRunIdsWindow: { string }, -- <=32 server-generated run IDs
	recentMutationOutcomes: { MutationOutcome }, -- <=32, durable, same write as action
	missionVariantCounters: { [string]: number }, -- shipped mission IDs -> nonnegative
	nextOrganicSequence: number, -- nonnegative integer
	activeMission: ActiveMission?,
	pendingPost: PendingPost?,
	ownPosts: { OwnPostSummary }, -- <=10 bounded summaries
	nextPostSequence: number, -- nonnegative integer
}

export type Lease = {
	token: string,
	jobId: string,
	expiresAt: number,
}

export type Envelope = {
	schemaVersion: number, -- v1 = 1
	revision: number,
	lastSaveOpId: string,
	updatedAt: number,
	profile: Profile,
	lease: Lease,
}

-- ProfileSnapshot: sanitized read projection (03 network contract).
export type ProfileSnapshot = {
	revision: number,
	serverTime: number,
	balance: number, -- confirmed spendable only
	pendingWorkerCuan: number, -- ephemeral, never spendable
	incomePerSecond: number,
	lifetimeEarned: number,
	completedMissions: number,
	tier: number, -- highest shipped eligible tier
	maxShippedTier: number,
	deviceId: string,
	ownedDesks: { number },
	workers: { WorkerEntry },
	activeMission: ActiveMission?,
	pendingPost: PendingPost?,
	nextOrganicContextId: string,
	ownPosts: { OwnPostSummary },
	feedVersion: number,
	saveStatus: SaveStatus,
}

-- Session metadata: reports CURRENT open session deadline; never opens UI,
-- never extends idle time on its own.
export type DashboardSessionMeta = {
	dashboardSessionId: DashboardSessionId,
	expiresAt: number,
}

-- Reply codes (bounded; retain existing and add SESSION_EXPIRED per 03).
export type ReplyCode =
	"OK"
	| "INVALID_INPUT"
	| "UNKNOWN_ACTION"
	| "SESSION_EXPIRED"
	| "LOCKED"
	| "BUSY"
	| "SAVE_UNAVAILABLE"
	| "NOT_READY"
	| "OUT_OF_RANGE"
	| "INSUFFICIENT_FUNDS"
	| "ALREADY_DONE"
	| "LIMIT_REACHED"

export type SessionBoundAction =
	"AcceptMission"
	| "PublishOrganic"
	| "PublishPost"
	| "ClaimMission"
	| "BuyDevice"
	| "BuyDesk"
	| "HireWorker"
	| "CloseComputer"

export type CommandAction = "GetSnapshot" | SessionBoundAction

-- Exactly-bounded payloads (03 action table). Client supplies IDs/indices only.
export type GetSnapshotPayload = {
	lookupRequestId: RequestId?, -- original mutation ID, NOT a fresh query ID
}

export type AcceptMissionPayload = { missionId: string }
export type PublishOrganicPayload = { templateId: string }
export type PublishPostPayload = { runId: string, templateId: string }
export type ClaimMissionPayload = { runId: string }
export type BuyDevicePayload = { deviceId: string }
export type BuyDeskPayload = { slotIndex: number } -- 1 or 2
export type HireWorkerPayload = { slotIndex: number, roleId: "trainee" } -- slot 1 or 2
export type CloseComputerPayload = {} -- empty, exact shape

export type CommandPayload =
	GetSnapshotPayload
	| AcceptMissionPayload
	| PublishOrganicPayload
	| PublishPostPayload
	| ClaimMissionPayload
	| BuyDevicePayload
	| BuyDeskPayload
	| HireWorkerPayload
	| CloseComputerPayload

-- IC-0 command union: fresh requestId always; dashboardSessionId required for
-- session-bound economic/Close actions, ABSENT on GetSnapshot.
export type GetSnapshotCommand = {
	requestId: RequestId, -- fresh per query
	action: "GetSnapshot",
	payload: GetSnapshotPayload,
}

export type SessionCommand = {
	requestId: RequestId, -- new for every mutation
	action: SessionBoundAction,
	dashboardSessionId: DashboardSessionId,
	payload: PublishOrganicPayload | PublishPostPayload | AcceptMissionPayload | ClaimMissionPayload | BuyDevicePayload | BuyDeskPayload | HireWorkerPayload | CloseComputerPayload,
}

export type CommandEnvelope = GetSnapshotCommand | SessionCommand

-- Lookup result (03): APPLIED/REJECTED carry originalResult; PENDING/UNKNOWN do not.
export type LookupStatus = "APPLIED" | "REJECTED" | "PENDING" | "UNKNOWN"

export type LookupResult = {
	originalRequestId: RequestId,
	status: LookupStatus,
	originalResult: {
		ok: boolean,
		code: ReplyCode,
		revision: number,
		data: { [string]: any }?,
	}?,
}

export type GetSnapshotData = {
	snapshot: ProfileSnapshot,
	lookup: LookupResult?, -- absent without lookupRequestId
}

export type Reply = {
	requestId: RequestId, -- correlates THIS request (query or mutation)
	ok: boolean,
	code: ReplyCode,
	revision: number,
	serverTime: number,
	dashboardSession: DashboardSessionMeta?, -- current session only; never reopens
	data: { [string]: any }?, -- GetSnapshot: {snapshot, lookup}; else action-specific
}

-- Discriminated Snapshot control channel (Snapshot RemoteEvent, FireClient only).
export type StateSnapshotEvent = {
	kind: "State",
	state: ProfileSnapshot,
}

export type OpenComputerEvent = {
	kind: "OpenComputer",
	dashboardSessionId: DashboardSessionId,
	expiresAt: number,
	serverTime: number,
	state: ProfileSnapshot,
}

export type OpenComputerDeniedEvent = {
	kind: "OpenComputerDenied",
	code: "NOT_READY" | "OUT_OF_RANGE" | "SAVE_UNAVAILABLE" | "INVALID_STATE",
}

export type ComputerSessionExpiredEvent = {
	kind: "ComputerSessionExpired",
	dashboardSessionId: DashboardSessionId,
	reason: "IDLE" | "CHARACTER_LOST",
}

export type SnapshotEvent =
	StateSnapshotEvent
	| OpenComputerEvent
	| OpenComputerDeniedEvent
	| ComputerSessionExpiredEvent

return nil