# BS-15A — DataStore Safety and Guardrail Design

**Document Status:** Architectural Safety Specification (Preflight Only)  
**Scope:** Safeguards for Real Cloud DataStore Operations (BS-15B)  
**Core Mandate:** Absolute isolation of production data, zero secret leakage, fail-closed concurrency safety.

---

## 1. Ten Threat Vectors and Evidence-Based Safety Guardrails

Every guardrail is classified according to its verified operational status:
- **IMPLEMENTED:** Active in candidate source code (`src/`).
- **VERIFIED:** Proven by executable tests (unit specs or offline harness).
- **PLANNED:** Designed as a pre-execution protocol for BS-15B live execution.
- **BLOCKED:** Dependent on unfulfilled external staging prerequisites.

| # | Threat Vector | Risk / Failure Mode | Enforced Safety Guardrail | Implementation & Evidence Basis | Verification Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **Accidental Writes to Production** | Overwriting real player data or consuming production DataStore budgets | **Fail-Closed Luau Assertion:** Test harness asserts `game.GameId == StagingConfig.EXPECTED_STAGING_UNIVERSE_ID`, `game.GameId ~= StagingConfig.FORBIDDEN_PRODUCTION_UNIVERSE_ID`, and `game.PlaceId == StagingConfig.EXPECTED_STAGING_PLACE_ID`. Both Universe IDs must be verified positive integers; production universe ID is mandatory and cannot default to 0. | Script designed for BS-15B pre-execution in `ServerStorage.StagingConfig`; aborts immediately on mismatch or unverified config. | **PLANNED** |
| **2** | **Shared Universe Identity** | Reusing production PlaceId/UniverseId under a staging label | **Platform-Level Scoping:** Roblox partitions DataStores strictly by Universe ID. Staging universe must be provisioned under a separate Creator Dashboard Universe ID. | Universe isolation enforced by Roblox engine backend; dedicated staging ID not yet provisioned. | **BLOCKED** |
| **3** | **Wrong Profile Key** | Mutating unrelated keys or misformatting user keys | **Strict Regex & Key Partition:** Keys must strictly match `^Player_%d+$`. In testing, keys are restricted to designated disposable test user ranges (e.g., `Player_9999901` to `Player_9999999`). | `ProfileStore.luau:666` hardcodes `Player_{userId}`. Validated in `ProfileStore.spec`. Test range partitioning is scheduled for BS-15B. | **IMPLEMENTED & VERIFIED (Unit)** / **PLANNED (Partition)** |
| **4** | **Partial Test Cleanup** | Residual test state corrupting subsequent test runs | **Run-Scoped Identifiers & Clean Release:** Tests use distinct test UserIds per test run. Cleanup executes standard `SessionService:Stop()` to clear leases. No arbitrary or unvalidated key deletion. | Lifecycle cleanup protocol authored in preflight; no cloud execution yet. | **PLANNED** |
| **5** | **Staging/Published Version Mismatch** | Running tests against an outdated or unapproved place version | **Artifact Hash Verification:** Before execution, build SHA-256 of candidate artifact is verified against pinned source commit `fa55baa`. | Local artifact `build/BuzzerSimulator.rbxlx` SHA-256 verified. Cloud place inspection blocked until staging place is published. | **VERIFIED (Local Artifact)** / **BLOCKED (Cloud Place)** |
| **6** | **Throttling (Request Budget 301)** | Exceeding 60 + numPlayers × 10 requests/minute, causing cascading drops | **Budget-Aware Scheduling:** Worker banking is restricted to >= 30s intervals. Retries enforce exponential backoff `{1, 2}` seconds. No tight loops on DataStore calls. | `SessionService.luau:58` (`WORKER_BANK_INTERVAL = 30`), `ProfileStore.luau:37` (`RETRY_BACKOFF_SECONDS = {1, 2}`). Validated in 20-min idle run. | **IMPLEMENTED & VERIFIED (Local)** / **PLANNED (Cloud)** |
| **7** | **Ambiguous DataStore Writes** | Network drop after request dispatch leaves write outcome uncertain | **Reconciliation Read (`UseCache = false`):** ProfileStore re-reads backend with cache disabled. If `lastSaveOpId` matches dispatched operation, write is confirmed without re-applying. | `ProfileStore.luau:143-160, 780-820` (`readBackendFresh`). Validated in `BS10Recovery.spec` (C3/B5). | **IMPLEMENTED & VERIFIED (Unit/Adapter)** / **PLANNED (Cloud)** |
| **8** | **Double Credit** | Re-executing transaction credits wallet twice | **Idempotent Operation IDs:** Every mutation generates a deterministic `operationId`. If `stored.lastSaveOpId == operationId`, transform callback short-circuits with zero mutation. | `ProfileStore.luau:780-820` and `SessionService.luau:1030-1045`. Validated in `ProfileStore.spec` & `SessionService.spec`. | **IMPLEMENTED & VERIFIED (Unit/Adapter)** / **PLANNED (Cloud)** |
| **9** | **Foreign Lease Overwrite** | Server B overwrites data while Server A holds live lease | **Atomic Compare-And-Swap (CAS):** `UpdateAsync` verifies `stored.leaseToken == self._leaseToken` and `now < stored.leaseExpiresAt`. Competing token returns `nil` and throws `LOCKED`. | `ProfileStore.luau:710-740`. Validated in `BS10Recovery.spec` (A4/A5/E1). Multi-server verification blocked until staging servers live. | **IMPLEMENTED & VERIFIED (Unit/Adapter)** / **BLOCKED (Multi-Server)** |
| **10** | **Unsupported-Schema Data Destruction** | Loading future/corrupted schema erases unknown fields | **Fail-Closed Envelope Preservation:** If `schemaVersion ~= 1`, ProfileStore aborts load (`UNSUPPORTED_SCHEMA`) and returns `envelope` untouched without migrating or overwriting. | `ProfileStore.luau:605-612`. Validated in `ProfileStore.spec` ("preserves an unsupported future schema") and `BS10Recovery.spec`. | **IMPLEMENTED & VERIFIED (Unit)** / **PLANNED (Cloud)** |

---

## 2. Pre-Execution Assertion Script (Roblox Luau Compatible)

Standard OS environment functions (`os.getenv()`) are not supported in the sandboxed Roblox Luau runtime. Staging environment parameters are configured via a dedicated `ServerStorage.StagingConfig` ModuleScript that is never replicated to clients. 

Before any cloud operation or test suite execution is permitted in BS-15B, the following assertion script must execute and pass:

```lua
--!strict
-- Pre-flight Safety Gate for Cloud DataStore Execution (Roblox Luau Compatible)
-- Path: tests/StagingSafetyGate.server.luau (or injected via harness)

local ServerStorage = game:GetService("ServerStorage")
local configModule = ServerStorage:FindFirstChild("StagingConfig")
if not configModule or not configModule:IsA("ModuleScript") then
    error("[SAFETY GATE] Critical: ServerStorage.StagingConfig ModuleScript is missing! Halting to protect production.", 0)
end

local StagingConfig = require(configModule) :: any
if typeof(StagingConfig) ~= "table" then
    error("[SAFETY GATE] Critical: StagingConfig must return a table! Halting.", 0)
end

local expectedUniverse = StagingConfig.EXPECTED_STAGING_UNIVERSE_ID
local expectedPlace = StagingConfig.EXPECTED_STAGING_PLACE_ID
local forbiddenUniverse = StagingConfig.FORBIDDEN_PRODUCTION_UNIVERSE_ID

-- Mandatory verified positive integer checks: production universe CANNOT be 0, nil, or unverified
assert(typeof(forbiddenUniverse) == "number" and forbiddenUniverse > 0,
    "[SAFETY GATE] Critical: StagingConfig.FORBIDDEN_PRODUCTION_UNIVERSE_ID must be a verified positive number (cannot be 0 or unverified)")
assert(typeof(expectedUniverse) == "number" and expectedUniverse > 0,
    "[SAFETY GATE] Critical: StagingConfig.EXPECTED_STAGING_UNIVERSE_ID must be a verified positive number")
assert(typeof(expectedPlace) == "number" and expectedPlace > 0,
    "[SAFETY GATE] Critical: StagingConfig.EXPECTED_STAGING_PLACE_ID must be a verified positive number")

-- Mandate strict separation between staging and production universes
assert(expectedUniverse ~= forbiddenUniverse,
    `[SAFETY GATE] Configuration error: Staging Universe ID ({expectedUniverse}) cannot equal Production Universe ID ({forbiddenUniverse})`)

-- Runtime environment assertions against current Roblox DataModel
assert(game.GameId == expectedUniverse,
    `[SAFETY GATE] Aborted! Current GameId ({game.GameId}) does not match staging universe ({expectedUniverse})`)
assert(game.GameId ~= forbiddenUniverse,
    `[SAFETY GATE] CRITICAL: Current GameId matches PRODUCTION universe ({forbiddenUniverse})! Immediate halt.`)
assert(game.PlaceId == expectedPlace,
    `[SAFETY GATE] Aborted! Current PlaceId ({game.PlaceId}) does not match staging place ({expectedPlace})`)

local DataStoreService = game:GetService("DataStoreService")
local ok, store = pcall(function()
    return DataStoreService:GetDataStore("PlayerData")
end)
assert(ok and store ~= nil, "[SAFETY GATE] Failed to obtain DataStore handle 'PlayerData'")
print(`[SAFETY GATE] Passed: Running in verified Staging Universe {game.GameId}, Place {game.PlaceId} (Production Universe {forbiddenUniverse} locked out)`)
```

### StagingConfig Template (`ServerStorage/StagingConfig.luau`)
```lua
--!strict
local StagingConfig = table.freeze({
    EXPECTED_STAGING_UNIVERSE_ID = 0,     -- Director must populate with confirmed staging universe ID (> 0)
    EXPECTED_STAGING_PLACE_ID = 0,        -- Director must populate with confirmed staging place ID (> 0)
    FORBIDDEN_PRODUCTION_UNIVERSE_ID = 0, -- Director must populate with verified production universe ID (> 0; mandatory, cannot default to 0)
    IS_STAGING_ENVIRONMENT = true,
})
return StagingConfig
```

---

## 3. Disposable Keys, Run IDs, and Schema v1 Preservation

### 3.1 Strict Schema v1 Immutability
The production persistence envelope is strictly frozen and governed by `ProfileStore._validateEnvelope` (`src/server/ProfileStore.luau:605-657`). Valid fields in an envelope are:
- `schemaVersion` (must equal `1`)
- `revision` (integer `>= 1`)
- `lastSaveOpId` (non-empty string)
- `updatedAt` (finite non-negative number)
- `profile` (valid profile table or nil under fresh/released states)
- `lease` (table with `token`, `jobId`, `expiresAt`)

**Core Safety Mandate:**
1. **Zero Schema Pollution:** The test harness must **never** inject ad-hoc metadata fields (such as `runId`, `isTest`, or `tombstoneFlag`) into the persistent DataStore envelope or profile. Doing so violates `validateEnvelope` and produces artificial `CORRUPT` or `UNSUPPORTED_SCHEMA` failures.
2. **External Run Tracking:** Test execution metadata (including `runId` UUIDs, test timestamps, and harness metrics) must be tracked externally by the Python test harness and logged directly to local evidence files under `docs/evidence/bs15/`.

### 3.2 Disposable Key Partitioning vs. Deletion
- **No Indiscriminate Deletion (`RemoveAsync`):** In Roblox production, `ProfileStore` never calls `RemoveAsync`. Deleting keys in cloud storage can mask retention anomalies and risks deleting unintended keys if a typo occurs.
- **Dedicated Test Key Partitions:** Rather than wiping keys, each test iteration allocates dedicated, disposable test UserIds:
  - Format: `Player_{testUserId}` where `testUserId` belongs to an authorized test account or allocated disposable test range (e.g., `9999901` through `9999999`).
  - Fresh tests (Case C-01) operate against a previously unused `testUserId` to observe true fresh-key acquisition without requiring key deletion.
- **Safe Teardown via Clean Lease Release:** When a test scenario completes, cleanup is achieved by invoking `SessionService:Stop()` or `ProfileStore:Release()`. This writes the legitimate released state (`lease.token = ""`, `lease.expiresAt = 0`) and leaves a valid, uncorrupted schema v1 envelope in storage.
- **Zero Tombstone Overwrite Policy:** Overwriting keys with tombstones or arbitrary payloads is forbidden. In Case C-14 (unsupported future schema preservation), the dedicated isolated test key (e.g., `Player_9999999`) is verified for hash/state invariance and permanently quarantined as immutable cloud evidence. It is never overwritten with a tombstone or reused for subsequent tests. Cleanup can only be performed via an explicit director-authorized procedure that re-verifies key prefix and payload hash prior to any action.

---

## 4. Data Sanitization and Secret Isolation

1. **Zero Credentials in Git:** API keys, Roblox `.ROBLOSECURITY` cookies, and OAuth client secrets must never be placed in source files, commit messages, or test outputs.
2. **Identifier Masking:** Logs committed to the repository must mask private player identifiers:
   - Real usernames must be anonymized (e.g., `Tester_A`, `Tester_B`).
   - Numerical UserIds in committed markdown evidence must be documented by role rather than private personal accounts.
3. **No Destructive Operations on Production:** Production universe is permanently excluded from any automated or manual tooling execution.
