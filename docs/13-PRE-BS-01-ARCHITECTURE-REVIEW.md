# Buzzer Simulator — Final Pre-BS-01 Architecture Review

## Decision and scope

**Decision: old CRT dashboard terminal, productive smartphone.** The original fantasy is entering BuzzerOS through a physical computer. `OldCRT` occupies `TerminalSlot`; the room-owned `DashboardPromptAnchor` opens BuzzerOS. The player **can publish from that UI**, but the server reads the confirmed `profile.deviceId` for post yield/reveal: the cheap/fast phone at `PhoneSlot` is productive until PC Rumah is bought. PC Rumah costs 220 Cuan, replaces `OldCRT` and becomes the sole productive device. The phone becomes inert decoration. No new equipment tier, equipment-profile field, service or remote is created; the separate idempotency contract adds a bounded outcome ring to the existing profile.

| Option | Progression clarity | Immersion/visual continuity | Implementation cost | Verdict |
|---|---|---|---|---|
| Cheap-phone dock opens BuzzerOS | Minimal risk of perceived free PC; phone→PC visually obvious | Misses the original physical-computer interaction; UI and income source coincide | Lowest: one prompt/mount | Rejected: loses a defining first-minute interaction |
| Nonproductive old CRT opens BuzzerOS; phone earns posts | Requires explicit “CRT = dashboard only; equipped phone = production” onboarding; PC visibly replaces CRT | Physical terminal from first interaction; visible old→modern computer transformation | One reviewed simple prop, phone pad and two display slots; same prompt/controller | Chosen: higher product fidelity for contained asset/UI cost |

**Tradeoff:** A computer visibly present at spawn may be mistaken for an owned PC upgrade. The opening label, shop yield comparison and world art must teach the distinction without relying on a hidden rule. If uncoached V0 players still misread it, revisit access presentation before M1; do not give the CRT free productive yield. BuzzerOS remains a safe-area ScreenGui: visual CRT interaction never forces a tiny monitor GUI or desktop layout on a mobile viewport.

## Frozen network behavior

Only three RemoteEvents: `Command` client→server, `Reply` and `Snapshot` server→that client. The server-owned `DashboardPromptAnchor` triggers `WorldService` validation: exact room/prompt, live character within 12 studs, loaded writable profile and valid lease. On acceptance create a fresh 10-minute dashboard generation, then `Snapshot:FireClient(player,{kind="OpenComputer",dashboardSessionId=...,expiresAt=...,serverTime=...,state=ProfileSnapshot})`. No client `OpenComputer` action or fourth remote. On denial emit `OpenComputerDenied` through `Snapshot`, without state/camera change. `Snapshot.State` only updates projection; it never opens the UI. `Snapshot.ComputerSessionExpired` closes the matching UI generation. Server-side actor and dashboard session checks still apply to every mutation.

`GameTypes` separates `GetSnapshotCommand` (fresh `requestId`, optional `payload.lookupRequestId`, **no** `dashboardSessionId`) from session-bound action commands (required matching `dashboardSessionId`, action-specific payload). `Reply` carries `requestId`, result/code/revision, `serverTime` and optionally the current `{dashboardSessionId,expiresAt}`; this metadata refreshes a **matching client watchdog**, not server activity and never opens UI. The `GetSnapshot` reply contains `{snapshot,lookup?}`; lookup is `{originalRequestId,status,originalResult?}` with APPLIED, REJECTED, PENDING or UNKNOWN. Server persists up to 32 successful client mutation outcomes in the **same write** as the action; definite pre-write rejections live in server memory only. Identical request IDs with different action/payload are rejected. Server-owned settlement/bank IDs are distinct.

**Timeout trace:** A mutation sent as `mut-0001` times out after 6 seconds. A new `GetSnapshot` sent as `qry-0002` may include `{lookupRequestId="mut-0001"}`. The `Reply.requestId` is `qry-0002`; `Reply.data.lookup.originalRequestId` is `mut-0001`. APPLIED uses the durable saved result, REJECTED a definite live rejection, PENDING waits (an identical `mut-0001` retransmit can join that **known** in-flight reservation in the same live session), UNKNOWN cannot prove absence. UNKNOWN **never** authorizes automatic retransmission or a new-ID payout, including after reconnect. Snapshot may settle an already-due post under its **original settlement ID**, not the query ID. While the per-player write lane is busy, a query returns the last confirmed snapshot and the lookup's actual status (PENDING **only** if that ID is reserved) rather than exposing an uncommitted write or waiting indefinitely. On ambiguous saves, keep action blocked until the server reconciles or reports an explicit unavailable state. This favors no duplicate grants over an automatic retry of an unprovable transaction.

**Idle expiration:** Valid user economic actions refresh the 10-minute server deadline at admission, including domain-level insufficient-funds responses; `GetSnapshot`, polling, ticks, invalid traffic and Close do not. Server expiry while UI stays open sends matching `ComputerSessionExpired` and rejects new session-bound commands with `SESSION_EXPIRED`. An action admitted before expiry can finish its durable write; its late reply may update HUD but cannot reopen BuzzerOS. Client expiry watchdog, server event, death and Close all run one idempotent camera/subject/input/movement/focus restore; old-generation notifications and delayed Close cannot affect a newly opened generation. Reopening requires a fresh server-validated prompt. The pending request ledger survives UI closure for reconciliation, not automatic replay.

## Contract map and staged asset ownership

The normative protocol, productive-device invariant and staged Rojo mapping are in [03 Technical Architecture](03-TECHNICAL-ARCHITECTURE.md). [05 UI/UX](05-UI-UX-SPECIFICATION.md) owns CRT posting and viewport/camera states; [06 World and Asset Plan](06-WORLD-AND-ASSET-PLAN.md) owns fixed anchors and the two paid station slots. [07 Roadmap](07-PRODUCTION-ROADMAP.md) owns internal V0 and closed-beta M1 gates. [08 Agent Backlog](08-AGENT-TASK-BACKLOG.md) assigns BS-01 an empty `ServerStorage.WorldPrefabs` Folder in both Rojo projects (`default.project.json`, `test.project.json`) and BS-05 the actual `OldCRT.rbxmx`, bedroom and phone prefabs **plus** both asset mappings; PC/worker prefabs follow in BS-11/BS-12. [09 Testing](09-TESTING-AND-QUALITY.md) requires mapped-instance, CRT/phone/PC visual and equipped-device yield checks. [10 Handoff](10-MVP-IMPLEMENTATION-HANDOFF.md) repeats the staged mappings and bounded BS-01 scope. The historical [12 Design Change Report](12-DESIGN-CHANGE-REPORT.md) is superseded for phone-dock/public-release wording; prices and formulas in [04 Economy](04-INCREMENTAL-ECONOMY.md) remain unchanged.

## DataStore pressure and durability

One successful conditional `UpdateAsync` per mission accept, post publish, due settlement, bonus claim, device/desk purchase and hire. No save for dashboard open/close, ordinary snapshot/lookup or rejected request; `GetSnapshot` can trigger the one due settlement already owed. Worker accrual folds into the next already-required write; while idle it banks by 30 seconds of healthy connected time. Lease renewal (90 seconds) piggybacks on writes. No batching of distinct post/claim/purchase transactions across an unconfirmed client success.

| Scenario, one player | Expected successful writes/min, model | Stress/risk |
|---|---:|---|
| Organic-only PC post every 25s | 4.8 | 13s reveal-only ceiling: 9.23/min |
| Repeated strong campaign every 65s (accept/publish/settle/claim) | 3.69 | 13s reveal-only ceiling: 18.46/min; same-key queue risk |
| Alternating modeled 90s organic+campaign | 4.0 | Bursty accept/settle/claim, not uniform spacing |
| One or two workers, no posts | 2.0 | Same write for both workers; lease piggybacks |
| No workers, no actions | 0.67 | Lease renewal only |
| Each purchase/hire | +1 in its minute | Bursts serialize with pending post/worker bank |

Active worker banks generally piggyback; conservative no-piggyback bound is +2/min. A standard `UpdateAsync` uses read **and** write budgets. Current Creator Hub's nominal one-player standard-store server budget is 100 read and 100 write requests/min (`60+40×players`), with separate experience, per-key throughput and partition pressure.[3] Current per-key write throughput is 4 MB/min.[3] At a **hypothetical** 3 KiB profile per write, the 18.46/min stress case uses about 55.4 KiB/min. Actual profile size and latency remain unmeasured. Headroom in bytes does **not** guarantee fast repeated writes to one key. Preserve a bounded per-player lane and `BUSY`/`SAVE_UNAVAILABLE` backpressure. Fake-store 0ms/6s single-key latency plus throttle/ambiguous-success scenarios and a dev-universe sustained run must record attempts, confirmed writes, budget, queue age, payload size and latency. Adjust admission pacing only if measured; do not change economy or reveal values preemptively. Roblox's data-store best practices recommend reducing and distributing requests and retrying transient failures.[1]

## Release positioning

V0 is a narrow **internal prototype**. M1 still ends at PC Rumah and two workers in one bedroom, with authored contexts and persistence gates; it is a **closed-beta candidate**, not automatic public launch. A wider launch needs actual uncoached playtest evidence on comprehension, pacing, saved balances, real device UX, replay and retention, plus separate director approval. No office, prestige, offline payouts or other M2 mechanic is added to fix unmeasured retention concerns.

## Pre-BS-01 readiness checklist

- [x] Product access decision documented; one productive device invariant and PC replacement clarified in `01`–`06`, `08`–`11`.
- [x] Current contracts use the room-owned `DashboardPromptAnchor`, replaceable `TerminalSlot` and display-only `PhoneSlot` instead of an obsolete phone-dock prompt or generic device slot. Posting from CRT BuzzerOS uses only the equipped `profile.deviceId`.
- [x] `OldCRT.rbxmx` is in V0 inventory, BS-05 assets/mappings and visual tests; BS-01 maps only an empty prefab Folder so neither Rojo build references a missing asset.
- [x] Three-remote protocol, typed `GameTypes` union, explicit OpenComputer server event and session-expiry behavior specified in `03`.
- [x] Mutation retry, fresh snapshot request ID, original-ID lookup, bounded outcome ring and UNKNOWN limit specified in `03`, `05`, `08`–`10`.
- [x] Durable write-pressure estimate and reproducible fake-store/dev-universe acceptance cases specified in `03`, `08`, `09`.
- [x] BS-01 stays source mapping, V0 public catalog, pure rules, *type declarations* and real test runner only; no gameplay, assets, router or DataStore implementation.
- [ ] Before isolated-agent handoff, include these planning files in that agent's checkout/worktree. At this audit, `docs/` is untracked on `master`; no commit or push was requested or made.
- [ ] On assignment: recheck Rojo v7.4+/Studio availability and current Git tree; run real production/test builds and Studio rules specs. No such execution is claimed here.
- [ ] BS-05/BS-06/BS-07 gates must later prove CRT clarity, prompt authorization, timeout/expiry recovery, and camera restoration in Studio. BS-02/BS-04/BS-14 must prove DataStore behavior in fake store and isolated dev universe.

**Readiness decision:** The package is contract-ready for a bounded BS-01 handoff, **not automatically accessible to isolated agents while `docs/` is untracked**. Before assignment, get explicit director authorization and provide the planning files in the agent's checkout. BS-01 execution then needs a Rojo/Studio recheck and real builds/specs. BS-05 has a complete **planned** asset/anchor/visual contract, but assignment depends on reviewed BS-01 device IDs and Rojo project scaffolding; its mapping edits must wait for any BS-02 test-project file ownership to clear. Studio prefab quality and prompt/visual proof are acceptance gates **during** BS-05, not evidence already obtained. No agent is assigned here. This review does not prove a Studio build or approve closed beta/publication.

## Sources

[1] https://create.roblox.com/docs/cloud-services/data-stores/best-practices
[3] https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits
