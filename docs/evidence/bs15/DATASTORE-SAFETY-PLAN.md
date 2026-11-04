# BS-15A — DataStore Safety and Guardrail Design

**Document Status:** Architectural Safety Specification (Preflight Only)  
**Scope:** Safeguards for Real Cloud DataStore Operations (BS-15B)  
**Core Mandate:** Absolute isolation of production data, zero secret leakage, fail-closed concurrency safety.

---

## 1. Ten Threat Vectors and Implemented Guardrails

| # | Threat Vector | Risk / Failure Mode | Enforced Safety Guardrail |
| :--- | :--- | :--- | :--- |
| **1** | **Accidental Writes to Production** | Overwriting real player data or consuming production DataStore budgets | **Pre-flight Assertion in Code:** Any test script must assert `game.GameId == EXPECTED_STAGING_UNIVERSE_ID`. If `GameId` matches production or is unverified, script raises immediate fatal error before requiring `ProfileStore`. |
| **2** | **Shared Universe Identity** | Reusing production PlaceId/UniverseId under a staging label | **Decoupled Universe Mandate:** Staging must exist under its own distinct Creator Dashboard Universe ID. Roblox partitions DataStores strictly by Universe ID; separation is enforced at the platform layer. |
| **3** | **Wrong Profile Key** | Mutating unrelated keys or misformatting user keys | **Strict Regex & Partitioning:** Keys must match `^Player_%d+$`. In testing, keys are restricted to designated disposable test user ranges (e.g., `Player_9999901` to `Player_9999999` or authorized tester UserIds). |
| **4** | **Partial Test Cleanup** | Residual test state corrupting subsequent test runs | **Run-Scoped UUIDs & Tombstoning:** Each test suite run generates a unique `runId` (e.g., `bs15-run-YYYYMMDD-UUID`). Profile envelopes store `runId`. Cleanup uses explicit tombstones rather than bare deletes. |
| **5** | **Staging/Published Version Mismatch** | Running tests against an outdated or unapproved place version | **Artifact Hash Verification:** Before execution, test harness queries place version and compares build commit metadata against pinned candidate SHA `fa55baa`. |
| **6** | **Throttling (Request Budget 301)** | Exceeding 60 + numPlayers × 10 requests/minute, causing cascading drops | **Budget-Aware Scheduling:** Worker banking is restricted to >= 30s intervals. Retries enforce exponential backoff `{1, 2}` seconds. No tight loops on DataStore calls. |
| **7** | **Ambiguous DataStore Writes** | Network drop after request dispatch leaves write outcome uncertain | **Reconciliation Read (`UseCache = false`):** ProfileStore re-reads backend with cache disabled. If `lastSaveOpId` matches dispatched operation, write is treated as confirmed without re-applying. |
| **8** | **Double Credit** | Re-executing transaction credits wallet twice | **Idempotent Operation IDs:** Every mutation generates a deterministic `operationId`. If `stored.lastSaveOpId == operationId`, transform callback short-circuits with zero mutation. |
| **9** | **Foreign Lease Overwrite** | Server B overwrites data while Server A holds live lease | **Atomic Compare-And-Swap (CAS):** `UpdateAsync` verifies `stored.leaseToken == self._leaseToken` and `now < stored.leaseExpiresAt`. Competing token returns `nil` and throws `LOCKED`. |
| **10** | **Unsupported-Schema Data Destruction** | Loading future/corrupted schema erases unknown fields | **Fail-Closed Envelope Preservation:** If `schemaVersion ~= 1`, ProfileStore aborts load (`UNSUPPORTED_SCHEMA`) and returns `envelope` untouched without migrating or overwriting. |

---

## 2. Pre-Execution Assertion Script (Executable Safety Gate)

Before any cloud operation or test suite execution is permitted in BS-15B, the following assertion block must execute and pass in the target environment:

```lua
--!strict
-- Pre-flight Safety Gate for Cloud DataStore Execution
local EXPECTED_STAGING_UNIVERSE = tonumber(os.getenv("ROBLOX_STAGING_UNIVERSE_ID")) or 0
local FORBIDDEN_PRODUCTION_UNIVERSE = 0 -- Set to real production universe ID

assert(EXPECTED_STAGING_UNIVERSE > 0, "[SAFETY GATE] Staging Universe ID must be explicitly configured")
assert(game.GameId == EXPECTED_STAGING_UNIVERSE, `[SAFETY GATE] Aborted! Current GameId ({game.GameId}) does not match staging ({EXPECTED_STAGING_UNIVERSE})`)
assert(game.GameId ~= FORBIDDEN_PRODUCTION_UNIVERSE, "[SAFETY GATE] CRITICAL: Current GameId matches PRODUCTION universe! Immediate halt.")

local DataStoreService = game:GetService("DataStoreService")
local ok, store = pcall(function()
    return DataStoreService:GetDataStore("PlayerData")
end)
assert(ok and store ~= nil, "[SAFETY GATE] Failed to obtain DataStore handle 'PlayerData'")
```

---

## 3. Data Sanitization and Secret Isolation

1. **Zero Credentials in Git:** API keys, Roblox `.ROBLOSECURITY` cookies, and OAuth client secrets must never be placed in source files, commit messages, or test outputs.
2. **Identifier Masking:** Logs committed to the repository must mask private player identifiers:
   - Real usernames must be anonymized (e.g., `Tester_A`, `Tester_B`).
   - Numerical UserIds in committed markdown evidence must be documented by role rather than private personal accounts.
3. **No Destructive Operations on Production:** Production universe is permanently excluded from any automated or manual tooling execution.
