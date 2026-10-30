# BS-06 network router and bootstrap

## Implementation plan

Base: `38afa8534dedc524901e38310c5a85ad63d0f2d9`; branch:
`agent/BS-06-network-bootstrap`. No BS-07 UI, content/economy/schema changes,
replacement persistence, production test clients or merge.

### Ownership and interfaces

- `SessionService.luau`: preserve Start's no-invention behavior; add guarded
  `InitializeStarter()` using the already acquired empty-profile lease,
  conditional Save and stable server-owned initialization identity. Add
  `IsWritable(): (boolean, string?)`, `GetLeaseExpiresAt(): number`, and
  `ReadSnapshot(lookupRequestId?): SnapshotResult` for non-writing read projection.
  Address only demonstrable lane/replay/bounded-memory integration defects.
- `NetRouter.luau`: `new({world, now, monotonic, guid, sendReply,
  sendSnapshot, onConfirmed?})`; `Register(player,session)`,
  `Unregister(player)`, `HandleCommand(player,envelope)`,
  `HandlePrompt(prompt,player)`, `CharacterLost(player)`, `Step()`,
  `PushState(player)`, `Destroy()`. Identity is the actual Player object supplied
  by Roblox, not a caller userId. `EnsureRemotes(replicatedStorage)` idempotently
  creates only Command/Reply/Snapshot in BuzzerRemotes.
- `BootstrapRuntime.luau`: focused internal testable orchestration with injected
  services/clocks/session factory. Own player records/generations, join/remove,
  character connections, world resync, aggregate scheduler, final cleanup.
- `Bootstrap.server.luau`: explicit production construction, service event wiring
  and one aggregate scheduler. Test mapping must not autorun this script.
- `tests/Specs/NetRouter.spec.luau`: malformed/forged remote data, dashboard state
  machine, rate/backpressure, durable replay/nonblocking queries, isolation.
- `tests/Specs/SessionIntegration.spec.luau`: new-key initialization and the narrow
  internal lease/lane compatibility surface, real services over fake transport.
- `tests/Specs/Bootstrap.spec.luau`: lifecycle, delayed writes, scheduler elapsed
  time, leave/shutdown and recoverable world presentation. Existing 320 cases
  stay intact. Production/test Rojo mappings remain explicit.

### Protocol and state machine

Exactly three private RemoteEvents. Exact bounded ASCII command shapes from
GameTypes; no client OpenComputer or intent/userId/score/money fields. All IDs
and payloads are validated before domain calls. Domain-only error codes map to
existing wire codes; GameTypes remains frozen.

A registered loaded player has either no dashboard or one ephemeral generation.
Only the exact room-owned ProximityPrompt with a living nearby character and a
writable leased session can open one. Reopen replaces its ID. A current valid
admitted economic command extends its deadline 600 seconds; reads, close,
background work and malformed traffic do not. Idle/death expire exactly once.
Already-admitted writes finish even if the UI generation expires; replies never
open UI. Old generations cannot mutate or close a newer dashboard.

Router reserves/compares identities before entering yielding session operations.
SessionService remains the durable canonical-intent authority; the router never
forwards supplied intent. Live rejections and reservations are bounded; durable
success replay uses the existing 32-entry ring. Queries correlate their own fresh
ID separately from lookup.originalRequestId. UNKNOWN never causes an automatic
new mutation or retransmission. PENDING reads remain nonblocking.

Initial command admission is 8 requests/second/player. Publish admission is at
least two seconds apart; identical reserved/applied retries are recovery, not a
new publish. Rejected traffic adds no economic write or idle extension.

### Initialization and lifecycle

Join obtains the lease via Start. Only an explicitly confirmed empty new profile
may enter InitializeStarter; failed reads, corrupt/foreign schema and competing
leases never seed data. Initialization reuses the existing store object/token;
repeated calls do not overwrite profiles. After durable confirmation the session
starts without reacquiring its own incompatible lease. Failed initialization
remains unavailable rather than manufacturing confirmed state.

World presentation always follows confirmed deviceId. Failed visuals are surfaced
and retried from confirmed state without charging again. No world IDs are saved.

One approximately 1Hz aggregate scheduler samples monotonic connected time per
player. SessionService retains its single write lane and rate-tagged bounded
<=60-second accrual chunks. Scheduler/command accounting must not overlap or
lose elapsed time across held writes. Banks remain 30 seconds; lease renewals
90 seconds, expiry240; required writes piggyback renewal. Non-writing State
pushes are at most every two seconds except event-driven changes. Player leave
and shutdown stop admissions, dispose connections, finish/reconcile admitted
work best-effort and release only through SessionService.

### Verification plan

Cover every numbered 1-38 security requirement in the assignment using real
SessionService/ProfileStore/domain logic over deterministic injected stores and
clocks where appropriate. Preserve all old test cases. Run both requested Rojo
builds and all suites in native Studio Play. Exercise actual server/client
RemoteEvents with temporary harnesses, including two-client identity isolation,
prompt acceptance/denial, due settlement, duplicate replay and confirmed-only
snapshots. Keep harnesses out of production mappings. Record exact suite counts,
static analyzer availability/results and complete native output.

Real development-universe DataStore G2 remains a separate gate: never enable or
write production keys to obtain test evidence. If isolated universe/API access
is not configured, record that gate BLOCKED/PENDING and complete supported tests.

## Handoff evidence

### Changed and new files

| File | Role |
|---|---|
| `src/server/NetRouter.luau` | New. Exact validation, three private remotes, rate/publish admission, dashboard generations, durable lookup routing. |
| `src/server/BootstrapRuntime.luau` | New. Testable orchestration: join/leave, world sync, one aggregate scheduler, disposable listeners. |
| `src/server/Bootstrap.server.luau` | New. Production wiring only; excluded from the test project. |
| `src/server/SessionService.luau` | Amended: `InitializeStarter`, `IsWritable`, `GetLeaseExpiresAt`, `ReadSnapshot`, `Reconcile`, `CaptureConnectedTime`, lease-scoped server operation IDs, bounded live/accrual caches. |
| `src/server/ProfileStore.luau` | Amended: bounded 64-entry transaction-fingerprint cache (no schema/lease/formula change). |
| `tests/Specs/NetRouter.spec.luau` | New, 89 cases. |
| `tests/Specs/SessionIntegration.spec.luau` | New, 39 cases. |
| `tests/Specs/Bootstrap.spec.luau` | New, 13 cases. |
| `default.project.json`, `test.project.json` | Map the new modules; production omits the test Runner. |
| `docs/14-BS-06-NETWORK-BOOTSTRAP.md` | This plan and handoff. |
| `docs/evidence/BS-06-regressions.txt` | Retained native output for all 461 case passes and ten suite summaries. |
| `docs/evidence/BS-06-native-runtime.json` | Actual two-client Studio runtime result: 31/31 integration checks. |

No UI, world asset, catalog, economy formula, tier, schema or content change.

### NetRouter interfaces

`EnsureRemotes(replicatedStorage)` idempotently creates only `Command`, `Reply`,
`Snapshot` under `BuzzerRemotes`, asserting on conflicting children.
`new({world, now, monotonic, guid, sendReply, sendSnapshot, beforeMutation,
onConfirmed})`; `Register(player, session)`, `Unregister(player)`,
`HandleCommand(player, envelope)`, `HandlePrompt(prompt, player)`,
`CharacterLost(player)`, `Step()`, `PushState(player)`, `Destroy()`.
Identity is the actual `Player` from the event; `sendReply`/`sendSnapshot` are
private `FireClient` transports. `beforeMutation` only samples connected time;
`onConfirmed` only re-syncs world presentation from confirmed state.

### Bootstrap lifecycle

Join → session factory → register the not-yet-started session → `Start()`.
Early requests receive `NOT_READY`; only a confirmed empty-profile lease may
proceed through `InitializeStarter()`. Success synchronizes the room from the
confirmed `deviceId` and marks the profile ready. Presentation failures remain
recoverable and explicit through `BuzzerWorldError`. Character add/remove bind
and dispose per-character connections; death and removal notify the router.
Leave removes the room, unregisters, disconnects every listener and finalizes the
session. One `Heartbeat`-throttled scheduler samples connected time, runs exactly
one background pump per player (`Reconcile` → `Advance(0)` → lease renewal when
due → world recovery → throttled `PushState`), and `BindToClose` performs a
best-effort stop with an explicit failure report.

### Safe starter initialization

`Start` never invents data. `InitializeStarter` requires an explicitly confirmed
empty-profile lease, reuses that same store object and token, writes the frozen v1
starter through the existing conditional `Save` with a stable operation identity,
and then starts without reacquiring the lease. Failed reads, `CORRUPT`,
`UNSUPPORTED_SCHEMA`, competing leases and repeated calls never seed or overwrite.

### Dashboard session state machine

Registered player → no dashboard, or one ephemeral generation. Only the exact
room-owned `ProximityPrompt` with a living character inside 12 studs and a
writable leased session opens one; reopening replaces the ID. A current valid
admitted economic command extends the 600-second deadline; reads, close,
background work and malformed traffic do not. Idle and character loss expire once.
Already-admitted writes finish; late replies carry only current metadata and never
reopen UI. Old generations cannot mutate or close a newer dashboard.

### Duplicate and timeout behavior

Router reserves and compares identities before yielding, never forwards client
intent, and lets `SessionService` derive canonical intent. Live rejections and
reservations are bounded; durable success replay uses the existing 32-entry ring.
Query IDs correlate separately from `lookup.originalRequestId`. `UNKNOWN` never
triggers an automatic retransmit or a new mutation ID. `PENDING` reads are
nonblocking.

### Exact tests per suite (actual Roblox Studio Play)

| Suite | Cases |
|---|---:|
| Rules | 16/16 |
| ProfileStore | 59/59 |
| MissionService | 85/85 |
| EconomyService | 39/39 |
| SessionService | 73/73 |
| WorldService | 30/30 |
| FeedService | 18/18 |
| NetRouter (new) | 89/89 |
| SessionIntegration (new) | 39/39 |
| Bootstrap (new) | 13/13 |
| **Total** | **461/461, 10/10 suites, `BS01_TESTS_PASSED`, zero failures** |

Legacy total is exactly 320; new coverage is 141. Complete case and suite output
was recovered from Studio's durable log and retained in
[`evidence/BS-06-regressions.txt`](evidence/BS-06-regressions.txt). This is filtered
assertion/summary output, not the entire engine/system log. The earlier console
tool response truncated its first case lines; no results were invented or
reconstructed from source.

### Actual Studio runtime verification

`StudioTestService:ExecuteMultiplayerTestAsync(2)` completed with **31/31 checks,
zero failures**, using two real Studio clients, actual Players, private
RemoteEvents, Heartbeat, rooms and all existing server domain modules. Persistence
used an isolated in-memory adapter; this does **not** close real DataStore G2.
The complete result is retained in
[`evidence/BS-06-native-runtime.json`](evidence/BS-06-native-runtime.json).

Observed behavior:

- Both first joins initialized confirmed starter profiles and distinct bedrooms;
  each room retained one CRT and one productive phone.
- Actual client/server requests and replies remained private. A second client
  could neither spoof the first user's identity nor borrow its dashboard ID;
  rejected requests changed neither profile.
- Owned-prompt authorization delivered private `OpenComputer`; the foreign-room
  prompt delivered denial without opening. The automated probe called the server
  prompt handler with the real owned prompt and a living real character.
  Separately, a single-client keyboard **E** interaction exercised actual
  `ProximityPromptService.PromptTriggered` and received the expected opening.
- A real organic publish remained at confirmed balance zero until settlement;
  the aggregate scheduler credited 15 once. Immediate and late same-ID retries
  performed no additional transaction. Lookup query and original mutation IDs
  remained distinct.
- A mission post settled, its claim succeeded, and a confirmed fast-phone purchase
  synchronized the visible phone without replacing the dashboard prompt.
- Removing/re-adding the same actual Player through the server runtime released
  the lease, restored the purchased phone and balance, and replayed the durable
  purchase outcome as `APPLIED`; the second client's profile remained unchanged.
  This checks server-session recreation, **not a transport disconnect/rejoin**.
- Aggregate shutdown completed successfully.

Only the ignored probe build used temporary client transport observers and an
isolated persistence adapter. They are not part of either committed Rojo project;
no production BuzzerOS UI or extra production remote was introduced.

### Builds and static analysis

`rojo build -o build/BuzzerSimulator.rbxlx` and
`rojo build test.project.json -o build/BuzzerTests.rbxlx` both succeed.
`lute lint` returned nonzero with unused-variable warnings (including variables
used only for Instance property writes/import paths). `lute check` also returned
nonzero: Roblox globals/types and Instance-based requires are unresolved, and it
reported additional strict inference diagnostics. These runs are **not** a clean
static analysis gate. No project language server is configured. Native Studio
execution and the passing suites are the exercised runtime evidence.

### Security invariants

Server authority only; client supplies IDs and slot indices. Exact bounded
shapes, ASCII 8..64 request IDs, whitelisted actions, known catalog IDs, slots
1..2, finite numbers, no extra keys, no client intent/userId/price/score/rate.
Private `FireClient` only; no fourth remote and no client `OpenComputer`.
Admission requires a loaded writable session with a current lease; rejected
traffic never writes and never extends idle. One serialized durable lane per
player, server-owned operation IDs scoped per lease generation, conditional
writes, confirmed-only balances. No offline income; connected time is monotonic
and bounded-chunked.

### Unresolved issues

1. **Real DataStore G2: BLOCKED/PENDING.** No isolated published development
   universe is configured; production keys were deliberately never touched.
   Actual backend acquisition, conditional writes, transport rejoin and
   competing-server lease conflicts still need that development configuration.
2. **Static analysis is not a green gate.** `lute check` returned unresolved
   Roblox environment/type diagnostics and additional inference errors. A
   Roblox-aware type-check configuration and review remain necessary.
3. Studio emitted its pre-existing `rbxassetid://203785492` content-type warning
   and local-test account/asset HTTP warnings; the native checks still completed.

The implementation and exercised native-runtime evidence are ready for independent
review. This is not production DataStore release approval. BS-07 was not started;
the implementation branch must not be merged as part of this task.

