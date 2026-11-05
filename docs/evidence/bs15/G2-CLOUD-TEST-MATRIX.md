# BS-15A — Gate G2 Real Cloud DataStore Test Matrix

**Document Status:** Executable Specification (Preflight Only — Awaiting Authorization)  
**Reference Document:** `docs/evidence/bs14-remediation/03-datastore-g2-matrix.md`  
**Execution Context:** Real Roblox Cloud DataStore (`PlayerData`, `Player_{UserId}`)  
**Rule:** Local mock adapters (`DEV_FALLBACK`) must never be counted as cloud verification.

---

## 1. Overview of Verification Layers

- **Layer A & B (Already Verified in BS-14):** In-memory unit specs and injected fault-injection adapters. (Status: PASS, but insufficient alone for G2).
- **Layer C (Studio with Real Cloud APIs Enabled):** Single-client execution in Studio bound to the Staging Universe with `studioAccessToApisAllowed = true`. Validates cloud transactions, engine caching, schema preservation, and write reconciliation against genuine cloud endpoints.
- **Layer D (Published Two-Server Staging):** Two live game server instances hosted on Roblox infrastructure. Validates lease concurrency, cross-server lockout, network disconnect recovery, and clean session handoff.

---

## 2. Layer C — Studio with Real Cloud APIs (Single Client / Cloud Session)

### Case C-01: Fresh-Profile Creation
- **Setup:** Target test key `Player_{testUserId}` is verified empty (`GetAsync` returns `nil`).
- **Actor & Environment:** Studio Play Session, Test Identity `testUserId`, Staging Universe.
- **Operation:** Call `SessionService:Start()`. Observe initial `NOT_READY` empty-lease signal, followed by `SessionService:InitializeStarter()`.
- **Expected Result:** `ProfileStore:Load()` acquires 240s lease with rev 0; `InitializeStarter()` writes starter profile envelope via conditional `UpdateAsync`. Cloud backend stores valid envelope with `schemaVersion = 1`, `balance = 0`, `devices = ["phone_cheap"]`, `revision = 1`.
- **Exact Evidence:** Cloud `GetAsync(..., UseCache=false)` dump; return code `OK`; revision `1`.
- **Cleanup Procedure:** Call `ProfileStore:Release()` or mark key for teardown.
- **Recovery from Partial Execution:** If write fails, call `GetAsync(..., UseCache=false)` to determine whether key was partially written or empty.

---

### Case C-02: Durable Write Verification
- **Setup:** Active session with confirmed starter profile (rev 1).
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Trigger an organic post publish (`PublishOrganic`), wait for settlement, and trigger a durable commit via `SessionService:Mutate()`.
- **Expected Result:** ProfileStore issues conditional `UpdateAsync`. Callback checks lease token match and revision bump. Returns `ok = true`, code `OK`, revision increments to `2`.
- **Exact Evidence:** Timestamped console log showing `UpdateAsync` return; `GetAsync` with `UseCache=false` showing updated `balance` and `recentMutationOutcomes` matching operation.
- **Cleanup Procedure:** Standard session `Stop()`.
- **Recovery from Partial Execution:** If network drops during write, execute fresh read to reconcile against `lastSaveOpId`.

---

### Case C-03: Session Close and Reconnect
- **Setup:** Profile with confirmed revision `N` and active lease on Server 1.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Call `SessionService:Stop()`. Verify clean lease release. Immediately start a new session (`SessionService:Start()`) on the same key.
- **Expected Result:** `Stop()` executes final durable worker bank and releases lease (`leaseToken = nil`, `leaseExpiresAt = 0`). New session `Start()` loads confirmed profile immediately with `code = "OK"` and acquires a fresh lease token without `LOCKED` rejection.
- **Exact Evidence:** Log showing `Stop()` exit code `OK`, followed by `Start()` acquiring new lease token; revision unchanged.
- **Cleanup Procedure:** Stop the second session cleanly.
- **Recovery from Partial Execution:** If `Stop()` fails to release, wait 240s for lease expiry before retrying `Start()`.

---

### Case C-04: Confirmed Balance Persistence
- **Setup:** Test profile with starting balance `B_start`.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Perform organic posts and mission completions resulting in confirmed balance `B_target`. Call `SessionService:Stop()`. Close Studio, reopen Studio, call `SessionService:Start()`.
- **Expected Result:** Upon fresh load, loaded profile `wallet.balance` strictly equals `B_target`. No balance truncation, reset, or inflation.
- **Exact Evidence:** Pre-disconnect snapshot vs post-reconnect snapshot JSON comparison; delta is `0`.
- **Cleanup Procedure:** Record final balance for subsequent tests.
- **Recovery from Partial Execution:** Check cloud DataStore revision and balance to determine last confirmed transaction.

---

### Case C-05: Mission Persistence
- **Setup:** Fresh mission `m_curhat_01` accepted via `SessionService:Mutate("AcceptMission", ...)`.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Progress mission to completed, claim reward via `ClaimMission`. Verify durable save. Disconnect session and reconnect.
- **Expected Result:** Reconnected profile reflects completed mission status: `completedMissions` contains `m_curhat_01`, `activeMission = nil`, claim payout durably retained in wallet.
- **Exact Evidence:** Post-reconnect snapshot inspection: `profile.missions.completed["m_curhat_01"] == true`.
- **Cleanup Procedure:** Retain profile state for device progression tests.
- **Recovery from Partial Execution:** Verify whether claim `operationId` is present in `recentMutationOutcomes`.

---

### Case C-06: Device Persistence
- **Setup:** Profile has balance >= 50 Cuan and Tier 0 requirements.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Execute `BuyDevice` for `phone_fast` (50 Cuan). Verify durable commit. Stop session, restart session.
- **Expected Result:** Reconnected profile has `phone_fast` in `profile.devices`, `profile.activeDevice == "phone_fast"`, and wallet deducted by exactly 50 Cuan.
- **Exact Evidence:** Cloud snapshot shows `devices = ["phone_cheap", "phone_fast"]`.
- **Cleanup Procedure:** None required; device state is persistent.
- **Recovery from Partial Execution:** Re-read backend; ensure idempotency check handles repeated purchase attempts.

---

### Case C-07: Desk and Worker Persistence
- **Setup:** Profile has required Tier and balance for desk and trainee hire.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Execute `BuyDesk` (slot 1), then `HireWorker` (slot 1, `trainee`). Durably commit. Restart session.
- **Expected Result:** Reconnected profile preserves desk ownership (`profile.studio.desks[1].owned == true`) and worker assignment (`profile.studio.workers[1].roleId == "trainee"`).
- **Exact Evidence:** Post-rejoin snapshot JSON verifying desk and worker slots.
- **Cleanup Procedure:** Retain for worker economy tests.
- **Recovery from Partial Execution:** Validate desk and worker slots independently via fresh cloud read.

---

### Case C-08: Derived Worker-Rate Reconstruction
- **Setup:** Profile with 2 active trainees loaded into fresh session.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Call `SessionService:Start()`. Query `EconomyService.incomePerSecond(profile)`.
- **Expected Result:** Economy service computes worker rate dynamically from confirmed worker assignments (e.g., 2 × 1.5 = 3.0 Cuan/s). No static worker rate is stored in DataStore envelope, preventing state drift.
- **Exact Evidence:** Server snapshot inspection: `snapshot.workerRate == 3.0`.
- **Cleanup Procedure:** Normal session teardown.
- **Recovery from Partial Execution:** N/A (read-only calculation).

---

### Case C-09: Confirmed Worker Banking Persistence
- **Setup:** Active session with 2 trainees running for >= 60 connected seconds.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Allow 2 banking intervals (30s each) to execute. Verify durable save confirmation. Force session termination via `Stop()`. Reconnect.
- **Expected Result:** Reconnected profile wallet includes banked worker income. Unbanked pending accrual reflects only residual seconds. Total banked income matches server elapsed intervals.
- **Exact Evidence:** Pre-rejoin vs post-rejoin wallet comparison; banked income audit log.
- **Cleanup Procedure:** Teardown session.
- **Recovery from Partial Execution:** Reconcile unbanked accrual queue against last durable revision.

---

### Case C-10: No Offline Accrual
- **Setup:** Profile with 2 active trainees saved at cloud timestamp `T0`.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Disconnect player. Wait offline for 10 minutes (600 seconds). Reconnect at `T0 + 600`.
- **Expected Result:** `SessionService:Start()` loads profile. Wallet balance remains strictly identical to balance at `T0`. Unbanked accrual starts at 0. Zero offline worker income is awarded.
- **Exact Evidence:** Snapshot comparison between `T0` disconnect and `T0 + 600` connect: `balance(T0 + 600) == balance(T0)`.
- **Cleanup Procedure:** Standard session teardown.
- **Recovery from Partial Execution:** Check that `pendingAccrual` is empty upon startup.

---

### Case C-11: Stale Revision Rejection
- **Setup:** Profile loaded with revision `R = 5`.
- **Actor & Environment:** Studio Test Script, Staging Universe.
- **Operation:** Artificially invoke `ProfileStore:Save` with an expected revision of `R = 4` (simulating a concurrent or lagging write).
- **Expected Result:** Cloud `UpdateAsync` callback evaluates `stored.revision ~= expectedRevision` and returns `nil` (abort write). ProfileStore returns `code = "BUSY"` or `"LOCKED"`. Stored cloud profile is unmodified.
- **Exact Evidence:** DataStore envelope revision remains `5`; returned status `ok = false`.
- **Cleanup Procedure:** Reload profile to re-sync local revision.
- **Recovery from Partial Execution:** Re-fetch current revision with `UseCache=false`.

---

### Case C-12: Duplicate Operation Idempotency
- **Setup:** Active session, operation `op_123` with intent `PublishOrganic`.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Submit `op_123`, confirmed at revision `R`. Immediately re-submit identical operation `op_123` with identical payload.
- **Expected Result:** ProfileStore identifies `stored.lastSaveOpId == "op_123"`. Transformation callback short-circuits, returning existing data without modification or revision increment. Result is returned from cache/snapshot without double credit.
- **Exact Evidence:** Revision remains `R`; wallet credited exactly once; log confirms idempotent bypass.
- **Cleanup Procedure:** Teardown session.
- **Recovery from Partial Execution:** Inspect `recentMutationOutcomes` in envelope.

---

### Case C-13: Ambiguous Write Reconciliation
- **Setup:** Custom test harness injecting network drop immediately after `UpdateAsync` dispatch.
- **Actor & Environment:** Studio Test Harness with injected transport drop, Staging Universe.
- **Operation:** Dispatch mutation `op_ambiguous`. Harness simulates dropped connection before response is returned. ProfileStore initiates retry with same `operationId`.
- **Expected Result:** ProfileStore executes `readBackendFresh` (`UseCache = false`). If write landed in cloud, it reconciles as confirmed without re-applying mutation. If write did not land, retry executes cleanly. Zero double-application.
- **Exact Evidence:** Profile revision increments at most by 1; `operationId` logged once in backend envelope.
- **Cleanup Procedure:** Clean session shutdown.
- **Recovery from Partial Execution:** Backend fresh read to assert envelope integrity.

---

### Case C-14: Unsupported Schema Preservation
- **Setup:** Dedicated isolated test key partition `Player_{isolatedTestUserId}` (e.g., `Player_9999999` in reserved boundary range) seeded with an artificial future-schema envelope: `{ schemaVersion: 99, customField: "future_data", revision: 10 }`.
- **Actor & Environment:** Studio Play Session, Staging Universe.
- **Operation:** Call `SessionService:Start()`.
- **Expected Result:** `ProfileStore:Load()` inspects `schemaVersion == 99`. Refuses load with `code = "UNSUPPORTED_SCHEMA"`. Session fails closed; starter profile is NOT seeded; key in cloud is preserved byte-for-byte.
- **Exact Evidence:** Cloud `GetAsync(..., UseCache=false)` confirms `customField == "future_data"`, `schemaVersion == 99`, and payload SHA-256 unchanged.
- **Cleanup Procedure:** Do NOT overwrite with a tombstone and do NOT execute `RemoveAsync`. The isolated test key is quarantined and retained as immutable cloud evidence of schema preservation. It is never reused for normal tests. Explicit cleanup is permitted only via an authorized teardown procedure that re-verifies key name and payload hash before any modification.
- **Recovery from Partial Execution:** Re-read cloud backend; assert payload matches seeded test envelope byte-for-byte.

---

### Case C-15: Failed Read Safety
- **Setup:** Key `Player_{testUserId}` exists with established balance and assets.
- **Actor & Environment:** Studio Test Session with simulated DataStore service outage on read (`GetAsync` throws error).
- **Operation:** Call `SessionService:Start()`.
- **Expected Result:** `ProfileStore:Load()` fails with `SAVE_UNAVAILABLE`. `SessionService` fails closed. Never seeds starter profile, never overwrites cloud key with empty envelope.
- **Exact Evidence:** Cloud backend data remains intact; client receives `SAVE_UNAVAILABLE` wire error.
- **Cleanup Procedure:** Normal session exit.
- **Recovery from Partial Execution:** Reconnect when service is restored; verify full profile loads.

---

## 3. Layer D — Published Two-Server Staging (Multi-Server Concurrency)

*(See `TWO-SERVER-TEST-PLAN.md` for complete multi-server topologies, timing diagrams, and execution steps).*

### Summary of Layer D Cases:
- **Case D-01: Foreign Lease Conflict:** Server A holds active 240s lease. Server B attempts `SessionService:Start()` on same player -> returns `LOCKED`.
- **Case D-02: Cross-Server Write Exclusion:** Server B attempts mutation on key leased by Server A -> rejected, cloud DataStore unaffected.
- **Case D-03: Clean Server Exit and Lease Handoff:** Server A calls `Stop()`, releases lease cleanly -> Server B immediately starts and acquires lease.
- **Case D-04: Abnormal Disconnect Recovery:** Server A crashes/abruptly closes without `Stop()` -> Server B blocked until 240s lease TTL expires, then successfully acquires.
- **Case D-05: Concurrent Operation Safety:** Server A and Server B race to acquire expired lease -> exactly one server acquires, second receives `LOCKED`.
- **Case D-06: Real Published-Server Rejoin:** Player teleports between live published staging servers -> profile loads seamlessly with zero rollback.
- **Case D-07: Persistence After Server Restart:** Creator Dashboard shuts down all running servers -> player rejoins new server -> all assets and balances intact.

---

## 4. Bidirectional Traceability Matrix

This matrix establishes complete mapping between the 17 authoritative Gate G2 requirements defined in `docs/evidence/bs14-remediation/03-datastore-g2-matrix.md` and the 22 executable cloud test scenarios (15 Layer C + 7 Layer D).

### 4.1 Requirement to Test Scenario Mapping (17 G2 Requirements)

| G2 Req # | G2 Requirement (`03-datastore-g2-matrix.md`) | Primary Cloud Test Case(s) | Layer | Verification Scope |
| :---: | :--- | :--- | :---: | :--- |
| **1** | Fresh profile created and durably saved | **C-01**, **C-02** | C | Initial load returns `NOT_READY`; `InitializeStarter` writes starter profile envelope with `schemaVersion = 1`, `balance = 0`. |
| **2** | Real server exit and new server join | **C-03**, **D-03**, **D-06**, **D-07** | C, D | Clean release handoff transfers lease immediately (`expiresAt = 0`); new server acquires without waiting 240s TTL. |
| **3** | Currency survives rejoin | **C-04**, **D-06** | C, D | Wallet balance invariance across disconnect and live server rejoin; zero inflation or loss. |
| **4** | Mission claims survive rejoin | **C-05**, **D-06** | C, D | Completed missions array and reward payouts durably retained in profile. |
| **5** | Device persistence (`phone_fast`, `pc_rumah`) | **C-06**, **D-06** | C, D | Owned devices array and active device selection preserved after server reconnect. |
| **6** | Both desks survive rejoin | **C-07**, **D-06** | C, D | Desk 1 and Desk 2 ownership retained in `profile.ownedDesks` after rejoin. |
| **7** | Both workers survive rejoin | **C-07**, **D-06** | C, D | Slot 1 and Slot 2 trainee assignments retained in `profile.workers` across sessions. |
| **8** | Worker rate recomputed after rejoin | **C-08** | C | Derived economy rate (1.5 Cuan/s per worker) computed dynamically upon startup, never read from static store field. |
| **9** | Confirmed banking survives rejoin | **C-02**, **C-09**, **D-07** | C, D | 30s banking commits durably saved; unbanked accrual safely recovered on rejoin. |
| **10** | No income earned while offline | **C-10** | C | 10-minute offline period yields 0 balance increase and empty pending accrual queue. |
| **11** | Lease conflicts handled safely | **C-03**, **D-01**, **D-02**, **D-04**, **D-05** | C, D | Foreign active lease returns `LOCKED`; crash forces waiting full 240s TTL; simultaneous start races serialize via atomic CAS. |
| **12** | Stale revisions rejected | **C-11**, **D-02** | C, D | Conditional CAS checks `stored.revision == expectedRevision`; lower/equal revisions rejected without mutation. |
| **13** | Ambiguous writes reconciled | **C-13** | C | Network drop re-reads backend with `UseCache = false`; matches `lastSaveOpId` without double-applying write. |
| **14** | Duplicate operation IDs never double-credit | **C-12** | C | Idempotency guard matches `stored.lastSaveOpId == operationId`, short-circuiting with 0 revision bump or payout. |
| **15** | Failed read never overwrites with starter data | **C-15** | C | DataStore read error returns `SAVE_UNAVAILABLE`; fails closed without seeding starter envelope. |
| **16** | Corrupt / future-schema envelopes preserved | **C-14** | C | `schemaVersion ~= 1` returns `UNSUPPORTED_SCHEMA`; raw data preserved byte-for-byte in cloud storage. |
| **17** | Shutdown and reconnect lose no confirmed transactions | **D-03**, **D-04**, **D-07** | D | `BindToClose` flushes worker accrual before termination; clean rejoin confirms all committed states. |

### 4.2 Scenario to Requirement Traceability (22 Test Scenarios)

| Scenario ID | Layer | Scenario Title | Target G2 Requirements |
| :--- | :---: | :--- | :--- |
| **C-01** | C | Fresh-Profile Creation | Requirement 1 |
| **C-02** | C | Durable Write Verification | Requirements 1, 9 |
| **C-03** | C | Session Close and Reconnect | Requirements 2, 11 |
| **C-04** | C | Confirmed Balance Persistence | Requirement 3 |
| **C-05** | C | Mission Persistence | Requirement 4 |
| **C-06** | C | Device Persistence (`phone_fast`) | Requirement 5 |
| **C-07** | C | Desk and Worker Persistence | Requirements 6, 7 |
| **C-08** | C | Derived Worker-Rate Reconstruction | Requirement 8 |
| **C-09** | C | Confirmed Worker Banking Persistence | Requirement 9 |
| **C-10** | C | No Offline Accrual | Requirement 10 |
| **C-11** | C | Stale Revision Rejection | Requirement 12 |
| **C-12** | C | Duplicate Operation Idempotency | Requirement 14 |
| **C-13** | C | Ambiguous Write Reconciliation | Requirement 13 |
| **C-14** | C | Unsupported Schema Preservation | Requirement 16 |
| **C-15** | C | Failed Read Safety | Requirement 15 |
| **D-01** | D | Foreign Lease Conflict | Requirement 11 |
| **D-02** | D | Cross-Server Write Exclusion | Requirements 11, 12 |
| **D-03** | D | Clean Server Exit and Lease Handoff | Requirements 2, 17 |
| **D-04** | D | Abnormal Disconnect Recovery | Requirements 11, 17 |
| **D-05** | D | Concurrent Operation Safety (Race) | Requirement 11 |
| **D-06** | D | Real Published-Server Rejoin | Requirements 2, 3, 4, 5, 6, 7 |
| **D-07** | D | Persistence After Server Restart | Requirements 2, 9, 17 |
