# BS-10 V0 Recovery, Reliability, Persistence & Failure Hardening

## 1. Executive Summary & Architecture

Milestone BS-10 hardens and mathematically verifies the end-to-end recovery, persistence, concurrency, and fault tolerance guarantees for *Buzzer Simulator Roblox* across all shipped V0 loops:
1. **Core Economic Invariant**: Confirmed economic transactions are never duplicated and never silently lost (`balance_delta == sum(confirmed_credits) - sum(confirmed_debits)` across all session crashes, rejoins, and lease takeovers).
2. **Server-Owned Settlement**: Organic and campaign posts freeze payout and impact at publish time. Settlements use deterministic, stable operation identities (`settle-<postId>`), ensuring that retries due to transport loss or throttling credit Cuan exactly once.
3. **Hardware Purchase Idempotency**: Fast Phone purchases deduct 50 Cuan once, bind device ownership durably, and replay cached outcomes on duplicate or retried requests without second deductions.
4. **Ambiguous Write Reconciliation**: 32-entry bounded durable mutation ring records applied mutations. A 6-second client timeout moves mutations to `uncertainMutations`, disables double-clicks, and emits progress queries (`lookupRequestId`) that resolve to `APPLIED`, `REJECTED`, or explicit `UNKNOWN`.
5. **Session Lease Concurrency & Shutdown**: Strict 240s lease duration with 90s lease renewal in SessionService. Competing servers receive `LOCKED`. Expired leases are safely assumed without profile data loss. Server shutdown (`Stop`) reconciles and flushes pending mutations before releasing leases.
6. **Client Input & Camera Resilience**: Client camera and control capture are hardened against network denials (`OpenComputerDenied`), session expiration, watchdog timeouts, and character parent removal (`AncestryChanged`).

---

## 2. File Map & Code Changes

| File | Change | Description |
|---|---|---|
| `src/client/ClientState.luau` | **Modified** | Hardened `ApplyOpenComputerDenied(code)` to protect active (`Open`) and in-flight (`Opening`) dashboard sessions from untagged late denials while preserving safe cleanup for genuinely aborted opening (`AbortOpening` and denial while `Closed`). |
| `src/client/App.client.luau` | **Modified** | Bound `character.AncestryChanged` to trigger `state:OnCharacterLost()` and camera/control restoration on parent removal (`nil`), ensuring players never get stuck when characters despawn without `Humanoid.Died`. Wired `OpenComputerDenied` to only restore camera/controls when status is `Closed` and denial applied, protecting active sessions. |
| `tests/Specs/BS10Recovery.spec.luau` | **New** | 41 comprehensive unit and integration tests covering load failures, corrupt payloads, unsupported schemas, lease collisions, post reveal survival, Fast Phone retry idempotency, ambiguous write reconciliation, client timeout lookups, shutdown safety, late denial / generation replacement protection, and full multi-rejoin player journeys. |
| `build/BuzzerTests.rbxlx` | **Rebuilt** | Test place updated with `BS10Recovery.spec.luau` and hardened client scripts via Rojo. |
| `build/BuzzerSimulator.rbxlx` | **Rebuilt** | Main production place updated with hardened client scripts via Rojo. |

---

## 3. Test Execution Results & Count Reconciliation

### Test Count Reconciliation
- **Baseline Across 16 Specs**: Exactly **626 tests** (590 pre-BS-09 baseline + 36 BS-09 tests).
- **BS-10 New Test Suite**: Exactly **41 tests** in `tests/Specs/BS10Recovery.spec.luau` (including focused regression tests for late denial and session generation replacement).
- **True Test-Runner Total**: Exactly **667 tests across 17 suites**. 0 failed, 100% passing.

### Roblox Studio Play Mode Runner Output
All 17 test suites passed natively in Roblox Studio Play mode (`BuzzerTests.rbxlx`, Studio runner `Runner.server.luau`):

```
[SUITE PASS] AppClientIntegration.spec: AppClientIntegration: 9/9 passed
[SUITE PASS] BS09FastPhone.spec: BS-09: 36/36 passed
[SUITE PASS] BS10Recovery.spec: BS-10: 41/41 passed
[SUITE PASS] Bootstrap.spec: Bootstrap: 17/17 passed
[SUITE PASS] ClientState.spec: ClientState: 30/30 passed
[SUITE PASS] ComposerIntegration.spec: 14/14 passed
[SUITE PASS] EconomyService.spec: EconomyService: 39/39 passed
[SUITE PASS] FeedService.spec: FeedService: 18/18 passed
[SUITE PASS] MissionService.spec: MissionService: 85/85 passed
[SUITE PASS] NetRouter.spec: NetRouter: 89/89 passed
[SUITE PASS] PostingState.spec: PostingState: 57/57 passed
[SUITE PASS] Presentation.spec: Presentation: 9/9 passed
[SUITE PASS] ProfileStore.spec: ProfileStore: 59/59 passed
[SUITE PASS] Rules.spec: Rules: 16/16 passed
[SUITE PASS] SessionIntegration.spec: SessionIntegration: 45/45 passed
[SUITE PASS] SessionService.spec: SessionService: 73/73 passed
[SUITE PASS] WorldService.spec: WorldService: 30/30 passed
==============================================
BS-01 suites: 17/17 passed, 0 failed
BS01_TESTS_PASSED
```

---

## 4. Phase Breakdown of BS-10 Test Coverage

### Phase A: Load Integrity & DataStore Faults (6 Tests)
- **A1**: A failed backend read returns `SAVE_UNAVAILABLE` and never initializes a blank profile over existing data.
- **A2**: Corrupt profile data is rejected as `CORRUPT` and preserved byte-for-byte in DataStore for support inspection.
- **A3**: An unsupported future schema version (e.g. v99) is rejected as `UNSUPPORTED_SCHEMA` and never overwritten.
- **A4**: A live foreign lease blocks a secondary server with `LOCKED` without modifying data.
- **A5**: An expired lease (>240s) is cleanly acquired by a new server and confirmed balance is preserved.
- **A6**: A key vanishing between read and write aborts with `SAVE_UNAVAILABLE` rather than seeding a blank profile.

### Phase B: Post Reveal Survival & Settlement Idempotency (5 Tests)
- **B1**: An organic post pending reveal survives a server crash/rejoin and settles exactly once at scheduled time.
- **B2**: Settlement retries use stable `settle-<postId>` operation identity; transient write failures retry and credit once.
- **B3**: A post that is not yet due is never settled early across a rejoin.
- **B4**: A campaign post survives a rejoin; mission claim succeeds once and duplicate claim attempts are refused.
- **B5**: Ambiguous settlement write where the response is lost is resolved by idempotent verification; payout never duplicates.

### Phase C: Fast Phone Purchase & Retry Idempotency (6 Tests)
- **C1**: Fast Phone purchase (50 Cuan) survives rejoin; balance is deducted once and lifetime earnings remain unaffected.
- **C2**: An identical retried purchase request replays as `OK` without performing a second write or balance deduction.
- **C3**: An ambiguous purchase write whose response was lost resolves cleanly on client retry without double charging.
- **C4**: A different purchase request for an already-owned device is rejected as `ALREADY_DONE` with zero deduction.
- **C5**: An unaffordable purchase request is rejected as `INSUFFICIENT_FUNDS` without writing to DataStore.
- **C6**: Spoofed device requests attempting to skip tiers (`pc_rumah`) or buy unknown devices (`phone_platinum`) are rejected.

### Phase D: Ambiguous Writes & Client Reconciliation (9 Tests)
- **D1**: Query lookup for an applied request returns `APPLIED` with original result and performs no store write.
- **D2**: Query lookup for an unrecorded request returns `UNKNOWN` and never falsely implies rejection.
- **D3**: A rejected mutation is cached in session memory as `REJECTED` and replayed with its original error code.
- **D4**: Reusing a `requestId` with differing action/payload is rejected as `INVALID_INPUT`, never replayed.
- **D5**: The durable mutation outcome ring cannot exceed 32 entries (32 entries load successfully, 33 entries fail validation as `CORRUPT`).
- **D6**: 6-second client timeout reserves mutation intent in `uncertainMutations` and emits a progress query (`lookupRequestId`).
- **D7**: An `APPLIED` lookup reply clears the client uncertain mutation, updates confirmed balance, and unblocks buttons.
- **D8**: An `UNKNOWN` lookup reply preserves uncertainty and prevents speculative resending.
- **D9**: An uncertain mutation blocks further economic actions in `ClientState` with a `BUSY` reason.

### Phase E: Competing Leases, Clean Handoff & Shutdown Safety (5 Tests)
- **E1**: Two server sessions competing for the same key: second `Start` returns `LOCKED` while the first holds the lease.
- **E2**: Clean release handoff transfers lease authority immediately when the first session calls `Stop()`.
- **E3**: Stale save from a server that lost its lease is rejected as `LOCKED` and never overwrites newer server state.
- **E4**: `Stop()` is strictly idempotent; calling twice avoids redundant writes or release attempts.
- **E5**: `Stop()` with an unresolved write failure retains the lease token so rejoin reconciliation can resolve it.

### Phase F: Client Session, Camera & Control Recovery (9 Tests)
- **F1**: Genuinely aborted opening via `AbortOpening` (e.g. missing room anchors) resets status to `Closed` with `CloseComputer` command; denial while `Closed` records denial code with zero camera capture.
- **F2**: Late `OpenComputerDenied` arriving after successful `OpenComputer` cannot close or invalidate an active (`Open`) session.
- **F3**: Late `OpenComputerDenied` arriving during in-flight `Opening` cannot abort the accepted session; transition completes to `Open`.
- **F4**: Late `OpenComputerDenied` arriving after session generation replacement preserves the replacement generation (`sess-2`).
- **F5**: Server session expiration during `Open` status transitions to `Expired` and closes the dashboard.
- **F6**: Local watchdog expiration (exceeding server lease duration) transitions to `Expired` and clears session state.
- **F7**: `SAVE_UNAVAILABLE` save status blocks mutation requests locally in `ClientState`.
- **F8**: Stale expiration notifications from older session generations are safely ignored.
- **F9**: Character loss (parenting to `nil` or death) resets dashboard state to `Closed` and invalidates the session.
### Phase G: End-to-End Multi-Step Recovery Journey (1 Test)
- **G1**: Complete player journey across three server rejoins (Server 1: Organic Post -> Server 2: Campaign Post & Claim -> Server 3: Fast Phone Purchase -> Server 4: Fast Phone Organic Yield Verification) conserves Cuan exactly:
  - Start: 0 Cuan
  - Post 1: +15 Cuan (Balance: 15)
  - Post 2 & Claim: +15 organic + 80 reward (Balance: 110)
  - Buy Fast Phone: -50 Cuan (Balance: 60)
  - Post 3 (Fast Phone): +24 Cuan (Balance: 84)
  - Final Confirmed Balance: 84 Cuan (Durable backend: 84 Cuan).

---

## 5. Gate G2 Live DataStore Verification Status

- **Status**: `G2_BLOCKED_SETUP`
- **Observed Engine Response**: `false: You must publish this place to the web to access DataStore.`
- **Reason**: Local offline Studio places (`.rbxlx`) cannot communicate with Roblox cloud DataStoreService without being linked to an active cloud Universe with Studio API Access enabled.
- **Strict Boundary**: In `src/server/ProfileStore.luau`, the ephemeral in-memory fallback is restricted to local offline Studio playtests. A fake store adapter cannot substitute for real cloud persistence validation under Gate G2.

### 5.1 G2 Scenario-by-Scenario Verification Matrix

| Scenario ID | Name | Target Invariant & Actions | Expected State / Balances | Execution Mode | Result | Blocker / Notes |
|---|---|---|---|---|---|---|
| **G2-01** | Fresh Account | Initial join, verify starter profile, clean exit, rejoin | 0 Cuan, `phone_cheap`, revision 1. Rejoin preserves identity. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-02** | Organic Pending Recovery | Post organic content, disconnect before 18s reveal, rejoin post-deadline | +15 Cuan (Balance: 15). No duplicate credit on reconnect. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-03** | Campaign Pending Recovery | Accept Food Stall mission, publish mission post, disconnect before reveal | Run ID, post count, and context consistent. Single payout (+15). | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-04** | Claim Persistence | Claim 80 Cuan mission reward, disconnect/rejoin, attempt duplicate claim | Balance: 110 (15+15+80). Claimed status persists. Duplicate claim refused. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-05** | Fast Phone Purchase | Buy Fast Phone for 50 Cuan, verify deviceId & cosmetic, rejoin, retry | Balance: 60, `phone_fast` equipped, cosmetic updated. Duplicate purchase refused. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-06** | Post-Upgrade Payout | Publish organic post with Fast Phone, disconnect/rejoin | +24 Cuan payout (Balance: 84). Final balance persists across restart. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-07** | Lease Behavior | Multi-session concurrency, clean logout vs stop, verify foreign lease lockout | Exclusive lease lock (240s), clean handoff on stop, no data overwrite. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-08** | Failure Recovery | Controlled failure injection on dev key (simulated read/write error) | Failed read preserves existing data, no unconfirmed Cuan, stable op ID. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |
| **G2-09** | Client & Device Recovery | Reopen BuzzerOS, test camera/control restoration, character respawn, viewports | Camera restores, controls active, UI opens, 1280x720 & 390x844 responsive. | Cloud DataStore | `BLOCKED` | Awaiting dev universe publishing and Studio API access. |

### 5.2 Confirmed Balance & Revision History (Modeled Journey)

1. Initial Join: 0 Cuan, `phone_cheap`, Revision 1
2. Organic Post Settlement: +15 Cuan → Balance: 15 Cuan, Revision 2
3. Mission Post Settlement: +15 Cuan → Balance: 30 Cuan, Revision 3
4. Mission Reward Claim: +80 Cuan → Balance: 110 Cuan, Revision 4
5. Fast Phone Purchase: -50 Cuan → Balance: 60 Cuan, Device: `phone_fast`, Revision: 5
6. Fast Phone Organic Settlement: +24 Cuan → Balance: 84 Cuan, Revision: 6
7. Final Rejoin Verification: 84 Cuan, Device: `phone_fast`, Revision: 6

Economic Invariant: $\Delta\text{Balance} = (15 + 15 + 80 + 24) - 50 = 84\text{ Cuan}$ (Verified in offline spec `BS10Recovery.spec.luau`).

### 5.3 Required Development Universe Setup Instructions

To unblock live DataStore verification without modifying production:
1. Open Roblox Studio and open `build/BuzzerSimulator.rbxlx`.
2. Select **File > Publish to Roblox As...**
3. Create a **NEW private development experience** named `Buzzer Simulator [DEV - BS-10]`. (Do not publish to production/master universe).
4. Navigate to **Home > Game Settings > Security** (or **File > Experience Settings > Security**).
5. Toggle **Enable Studio Access to API Services** = **ON**.
6. Toggle **Allow HTTP Requests** = **ON**.
7. Click **Save**.
8. In Studio Assistant Settings > MCP Servers, ensure **Enable Studio as MCP server** is checked.
9. Keep Studio open with the place loaded to allow agent MCP execution.

---

## 6. Risk Registry & Operational Procedures

| Risk | Impact | Mitigation |
|---|---|---|
| **DataStore Throttling During Peak Hours** | High | `ProfileStore` implements 3 maximum save attempts with 1s and 2s backoff (`{ 1, 2 }`) on ambiguous/failed writes. Unresolved operations report `SAVE_UNAVAILABLE` without corrupting local memory. |
| **Server Crash Mid-Mutation** | High | Durable 32-entry outcome ring records applied mutations before acknowledging to client. On rejoin, retried requests find cached outcomes and replay without double-charging. |
| **Split-Brain Server Execution** | Critical | Exclusive lease locking with 240s timeout and 90s lease renewal in `SessionService`. Servers verify lease token on every `UpdateAsync` transform; stale servers are rejected with `LOCKED`. |
| **Client Network Hiccups During Purchase** | Medium | Client 6s timeout moves pending requests to `uncertainMutations` and polls with `lookupRequestId`. UI disables duplicate clicks. |
| **Character Despawn / Streaming Drop** | Low | `AncestryChanged` listener on Character detects parent removal to `nil`, restoring camera and UserInputService controls immediately. |

---

## 7. Final V0 Internal Technical Prototype Recommendation

- **Milestone Code State**: Fully implemented, hardened, and verified via 17 Studio test suites (667/667 passing unit/integration tests).
- **Rojo Builds**: Production (`build/BuzzerSimulator.rbxlx`) and Test (`build/BuzzerTests.rbxlx`) build cleanly without errors.
- **Gate G2 Status**: `G2_BLOCKED_SETUP`. Real cloud DataStore persistence requires human operator to complete private development universe publishing and enable Studio Access to API Services.
- **Release Readiness**: **NOT READY FOR PUBLIC RELEASE**. V0 is an internal technical prototype. Public release is gated on live cross-server persistence smoke testing in the dedicated development universe.
