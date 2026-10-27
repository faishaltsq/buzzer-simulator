# Buzzer Simulator — Agent Task Backlog

## Rules and interface freeze
**Planning only.** Do not assign any task until the director explicitly authorizes implementation. Branch `agent/BS-XX-short-name`, one owner per shared file, hand over exact diff and actual test output. Codex reviews contracts and merges serially. No concurrent edits to `Catalog`, `GameTypes`, `Rules`, `ProfileStore`, `NetRouter`, or `App.client`. Common DoD: executable specified tests with nonzero assertions, production/test Rojo builds where available, Studio/device evidence when stated, changed file list, no secrets or unknown-origin assets, director/Codex review. A static build is not a Play test. Use isolated dev universe for DataStore tests.

**IC-0 shared contract:** Three remotes and `GameTypes` union in `03`: fresh command IDs, optional lookup ID only on `GetSnapshot`, ephemeral `dashboardSessionId`, typed Snapshot control variants and `SESSION_EXPIRED`; v1 profile with `pendingPost`, context counters, two owned desk slots, two worker slots, and `recentMutationOutcomes` (<=32 saved successful results); one global post slot; `Rules.postImpact`, `Rules.organicCuan`, `Rules.eligibleTier`; `Catalog.Devices[*].revealSeconds`; public contexts but server-only affinity tags. Freeze after BS-01, amend `02`/`03`/`04`/`10` with tests **before** any later contract change. V0 has only one organic and one mission context; v1 shapes support M1 expansion without migration. `rojo build -o build/BuzzerSimulator.rbxlx` is the standard static gate.

## P0 and V0 tasks
### BS-01 — Foundation and pure rules (first assignment)
- **Objective:** Build minimal Rojo v7.4+ layout, authored V0 catalog and pure rule tests; **no gameplay scripts** in this task.
- **Context/dependencies:** Empty tracked code repository; read `02`–`04` and `10`. Rojo/Studio must be checked at execution time; no current build claim.
- **Files:** Create `default.project.json`, `test.project.json`, `.gitignore`, `src/shared/{GameTypes,Catalog,Rules}.luau`, `tests/Rules.spec.luau`, `tests/Runner.server.luau`. Test runner excluded from production mapping.
- **Functionality / inputs / outputs:** V0 public catalog: `food_stall_launch` context `meal_time` with impact 100, bonus 80, three templates including `meal_meme`; organic context `organic_snack` with three templates including `snack_meme`; cheap/fast device yield 1/1.6, reveal 18/16, fast cost 50; planned tier thresholds 300/3 and 1600/3. Pure `Rules.postImpact(B, fit, deviceYield)`, `Rules.organicCuan(fit, deviceYield)`, `Rules.eligibleTier(lifetimeEarned, completedMissions, maxShippedTier)`; `fit` strong|weak, finite validated numbers, no randomness. `GameTypes` defines v1 Profile and network discriminated unions exactly as in `03`; no runtime router in BS-01.
- **API contract:** `postImpact(100,strong,1)=120`, `(100,weak,1)=75`, weak at yield2.5 =94 and remains <100; two starter weak posts >=100. Organic strong/weak Cuan: cheap 15/9, fast 24/14, PC planned 37/22. Do not expose private affinities/answer key; BS-03 owns `ScoringCatalog`.
- **Constraints:** No network/UI/scene/DataStore/service, service container, generated text, runtime randomizer, or test runner in production; one-player setting is not authorization.
- **Acceptance:** Catalog validates IDs, context/template counts, device order and tier gates; numerical assertions above, exact reveal seconds, tier clamp to max shipped; invalid/nonfinite inputs fail rather than pay. Both Rojo projects include an empty `ServerStorage.WorldPrefabs` Folder; neither maps a nonexistent `OldCRT.rbxmx` before BS-05. Review typed `GetSnapshot {lookupRequestId?}`, distinct command/lookup IDs, `SnapshotEvent` variants, `recentMutationOutcomes` entry, and optional versus required dashboard session fields against `03`; no implementation of transport.
- **Validation:** Build production and test projects; execute actual test runner in Studio Play and report assertion count/zero failures. If tools unavailable, mark blocked with exact cause; no invented output.
- **DoD:** IC-0 exported signatures and source mapping reviewed by Codex, plus common DoD.

### BS-02 — Profile persistence and lease
- **Objective:** Safely load/save v1 without reconnect overlap or blank fallback.
- **Context/dependencies:** BS-01 v1 shapes/catalog; fake-store adapter before dev-universe API test.
- **Files:** Create `src/server/ProfileStore.luau`, `tests/ProfileStore.spec.luau`; adjust `test.project.json` only for runner wiring.
- **Functionality / inputs / outputs:** `Load(userId)`, `Save(userId,profile,operationId)`, `Release(userId,profile,operationId)` return explicit success/error. Conditional `UpdateAsync`, 240s lease/90s renewal, revision and last-save operation ID, immutable copies, bounded retry and v1 validation.
- **API contract:** Failed load yields no starter profile; lease conflict `LOCKED`; unsupported/corrupt data preserved; unknown write result retried/reconciled with same operation ID; full v1 validates global pending post, context counters, owned slots, worker slot uniqueness, and <=32 successful mutation-outcome entries durably written in the same operation as their mutation.
- **Constraints:** No `SetAsync`, live-universe API tests, callback yields or unbounded retry; no client sees lease token.
- **Acceptance:** New key round-trip, stale revision/token rejection, ambiguous write idempotent, release/rejoin, future schema blocked; no silently erased pending post or paid desk.
- **Validation:** Fake-adapter/failure tests, two Rojo builds, isolated dev-universe Studio save/rejoin, Codex lease review.
- **DoD:** IC-3 persistence prerequisites reviewed; common DoD.

### BS-03 — Shared post/mission/feed state
- **Objective:** Implement one post settlement path for organic and mission-tagged posts, without network/UI.
- **Context/dependencies:** BS-01 rules/contexts, BS-02 shape/adapter; SessionService will persist pure mutations.
- **Files:** Create `src/server/{ScoringCatalog,MissionService,FeedService}.luau`, `tests/{MissionService,FeedService}.spec.luau`.
- **Functionality / inputs / outputs:** Pure `accept(profile,missionId,runId,now)`, `publishOrganic(profile,templateId,now)`, `publishMission(profile,runId,templateId,now)`, `settle(profile,now)`, `claim(profile,runId)` return explicit code/updated profile; FeedService projects bounded authored/own cards. `ScoringCatalog` stores template trend/audience affinity; `2*trendMatch+audienceMatch` chooses unique strong fit.
- **API contract:** First food run gets `meal_time`, first organic post gets `organic_snack`; counters persist; one global pending post; organic credit on durable settlement for both modes; mission bonus only on claim; `postId` from nextPostSequence; exact same outcome after rejoin. Strong one post/weak two, max ten own summaries, 32 claimed-run IDs.
- **Constraints:** No user text, separate pay-per-mode implementation, per-NPC loop, direct DataStore call, or client-replicated affinity tags. Reject catalog tie/no-winner at startup.
- **Acceptance:** Organic post credits 15 only once; mission strong credits 15 at settle then 80 once at claim; weak earns 9 per post and needs two; organic cannot advance an active mission; cross-mode pending lock; rejoin at each transition no reroll; bounded feed and counter cycle tested with M1 fixture.
- **Validation:** Fake-clock boundary tests, rules/build, Codex state and content-mapping review.
- **DoD:** IC-1 pure posting contract reviewed; common DoD.

### BS-04 — Economy and player session
- **Objective:** Own serialized commands, banked Cuan, purchases, tier and aggregate worker accrual.
- **Context/dependencies:** BS-02/03 contracts; no remotes yet.
- **Files:** Create `src/server/{SessionService,EconomyService}.luau`, `tests/{SessionService,EconomyService}.spec.luau`.
- **Functionality / inputs / outputs:** `SessionService:Start/Mutate/Snapshot/Stop`; `EconomyService.buyDevice/buyDesk/hireWorker/tick` produce validated profile changes. One server scheduler and one per-player lane. Piggyback worker income/lease renewal on due durable actions; otherwise bank worker income by <=30s connected intervals. Expose banked balance and separately non-spendable pending accrual.
- **API contract:** V0 includes only fast-phone purchase in shipped Catalog. Implement device/desk/worker validation against catalog entries; test future PC, desk and trainee values through explicit M1 fixtures (PC220/yield2.5; desks180/250; hires500/750; rate1.5 each), not public V0 buttons. `lifetimeEarned` counts confirmed organic/mission/worker Cuan, not spending.
- **Constraints:** One server scheduler, no per-NPC threads/offline catch-up, mutable in-flight profile, unconfirmed balance presented as spendable, or negative wallet. Process connected monotonic time in `dt<=60` chunks **without dropping a remaining connected interval**; validate finite values and do not expose staff/PC until BS-11–13 content is approved.
- **Acceptance:** First organic+food settles 15+15+80=110, phone50 leaves60; fixture-based PC yield changes15->37 strong; desk/hire checks both slots in fixture; 30 connected seconds with one fixture worker banks45, two bank90; failed bank leaves confirmed balance unchanged and blocks economy.
- **Validation:** Fake time/store, concurrent command and tick tests, single-key write-delay/throttle and bank-piggyback assertions from `09`, Rojo builds, Codex currency and retry review.
- **DoD:** Server-owned economy and freeze behavior reviewed; common DoD.

### BS-05 — Bedroom, dashboard terminal and V0 phone art
- **Objective:** Produce a traversable bedroom with one nonproductive old CRT dashboard terminal, an owned productive phone pad, distinct phone models, and room geometry that leaves space for PC replacement and two seats.
- **Context/dependencies:** Reviewed BS-01 device IDs/project skeleton and `03` fixed anchors. Asset blockout may run in an isolated branch during BS-02–04; serialize the Rojo project-file edits/merge with BS-02 test-project wiring and any other owner of those files.
- **Files:** Create `assets/world/{Bedroom,OldCRT,PhoneCheap,PhoneFast}.rbxmx`, `src/server/WorldService.luau`, `assets/ASSET-MANIFEST.md`, `tests/WorldService.spec.luau` where fake anchors suffice; update `default.project.json` and `test.project.json` to map these four existing prefabs by name under `ServerStorage.WorldPrefabs`.
- **Functionality / inputs / outputs:** `Spawn(player,profile)`, `SyncDevice(player,deviceId)`, `ValidateDashboardPrompt(player,prompt)`, `Remove(player)`; stable `DashboardPromptAnchor`, `TerminalSlot` and `PhoneSlot`; reserve two valid worker slots for M1. BuzzerOS at `OldCRT` may initiate posting; server `profile.deviceId` alone supplies yield/reveal, not the prompt or visual model.
- **API contract:** Server validates the exact room-owned prompt, living player within 12 studs, loaded writable profile and valid lease; CRT at terminal is dashboard-only, cheap/fast phone at phone pad is the single productive model; PC replaces CRT without creating/moving prompt; sync saved device ID on join.
- **Constraints:** Part kit first, reviewed prefab and human screenshot approval, no hidden scripts or Workspace wholesale sync; author actual PC asset only in BS-11.
- **Acceptance:** Both Rojo builds resolve `Bedroom.rbxmx`, `OldCRT.rbxmx`, `PhoneCheap.rbxmx` and `PhoneFast.rbxmx` under `ServerStorage.WorldPrefabs`; the room clones one `OldCRT` at `TerminalSlot` and keeps `DashboardPromptAnchor` outside the replaceable model. CRT prompt works with cheap and fast phones; label/placement distinguishes dashboard access from equipped-device yield; phone models visibly differ; PC replacement footprint and two future worker slots fit without blocking the route; initial room contains no free productive PC.
- **Validation:** Production/test Rojo builds and mapped-instance inspection, Studio Play prompt probes, CRT plus cheap/fast-phone screenshots on PC/phone emulator, no-dual-yield fixture, bedroom two-seat blockout and asset manifest review. PC replacement screenshot belongs to BS-11 after `PCRumah.rbxmx` exists.
- **DoD:** Room blockout includes two future seats; human art sign-off; common DoD.

### BS-06 — Network router and bootstrap
- **Objective:** Wire three remotes, services, server CRT prompt and player lifecycle.
- **Context/dependencies:** BS-02–05 merged; freeze protocol before client work.
- **Files:** Create `src/server/{NetRouter,Bootstrap.server}.luau`, `tests/NetRouter.spec.luau`; `src/shared/GameTypes.luau` only with Codex-reviewed amendment.
- **Functionality / inputs / outputs:** Enumerated actions in `03` including `PublishOrganic`, `BuyDesk {slotIndex}`, `HireWorker {slotIndex,roleId}`; only a validated server `DashboardPromptAnchor` trigger sends `Snapshot:FireClient(player,{kind="OpenComputer",dashboardSessionId=...,expiresAt=...,serverTime=...,state=...})`; player load/leave/BindToClose; worker bank timer, due-post settlement and 10-minute idle expiry. Posting inside CRT BuzzerOS uses confirmed `profile.deviceId`, never CRT yield.
- **API contract:** `Command {requestId,action,payload,dashboardSessionId?}`, `Reply {requestId,ok,code,revision,serverTime,dashboardSession?,data?}`, typed `Snapshot` variants. New `GetSnapshot` ID plus optional original mutation lookup ID; `Reply.data.snapshot/lookup` as in `03`. Validate exact actor/session/prompt; reserve in-flight IDs before lane, replay 32 saved successful outcomes plus live rejects; expiry cannot cancel an admitted save or open UI on state query.
- **Constraints:** Validate actor/session/shape/catalog/rate, never client score/price/worker amount; no yield inside pure profile mutation; tear down listeners on leave.
- **Acceptance:** Forged score, rate, price, context, timestamp or other user ID cannot pay; double organic publish/claim cannot duplicate; remote spam or distant prompt denied; second Studio test client cannot mutate first. Prompt opens via `Snapshot` only; denied prompt does not move camera; query correlation ID differs from original ID; stale session commands/Close rejected after reopen.
- **Validation:** Router specs for typed events, same-ID different-intent rejection and delayed reply/session expiry, Rojo builds, Studio server/client and two-client authorization probe; Codex security review.
- **DoD:** IC-1 wired server slice; common DoD.

### BS-07 — UI shell, HUD and phone/PC camera
- **Objective:** Build responsive BuzzerOS shell before content screens.
- **Context/dependencies:** BS-06 snapshot-event union, BS-05 stable dashboard prompt anchor.
- **Files:** Create `src/client/App.client.luau`, `src/client/ui/{Hud,Desktop,Theme}.luau`; `tests/ClientState.spec.luau` for any pure reducer.
- **Functionality / inputs / outputs:** Handle `Snapshot` OpenComputer/Denied/Expired and pushed State, Close/Escape/death/idle expiry, navigation, confirmed Cuan vs pending worker preview, tier/rate/objective, blocked/error state and viewport-responsive shell.
- **API contract:** Client sends only action IDs/template IDs/slot indices, not money/score/time. A timed-out mutation keeps its original ID; `GetSnapshot` gets a **fresh** ID and optionally looks up the original. Same-ID retransmit only to join a known PENDING reservation in the same live session; UNKNOWN never auto-retries or triggers a new payout ID. A matching `Reply.dashboardSession` refreshes the local watchdog, not the server deadline. Expiry/late replies cannot reopen UI or lose/restage camera; server-only confirmed spendable balance.
- **Constraints:** Safe-inset ScreenGui in PlayerGui, gamepad/touch/keyboard focus, 44x44 reference targets, Roblox menu intact; no reactive framework dependency.
- **Acceptance:** 360x640 portrait and 1280x720 PC Home at the CRT and purchased PC; previous camera/movement restored on close/death/idle expiry; stale expiry cannot close a newly opened UI; blocked banner visible.
- **Validation:** Rojo builds, Studio Play emulator/controller and screen captures, Codex lifecycle review.
- **DoD:** IC-2 shell ready; common DoD.

### BS-08 — Organic and mission composer
- **Objective:** Finish V0 two active-income loops through one shared post UI.
- **Context/dependencies:** BS-03/06 state and BS-07 shell; V0 one context per mode.
- **Files:** Create `src/client/ui/{Feed,Missions}.luau` with shared composer owned by Missions UI or an extracted module **only if both call sites require it**; modify `src/client/App.client.luau` after BS-07 merge; pure UI tests as needed.
- **Functionality / inputs / outputs:** Six feed cards, Home/Create organic action, mission accept and tagged post, server-timed 18/16s reveal, separate confirmed organic payout and 80 bonus claim, readable trend/audience fit reason.
- **API contract:** `PublishOrganic {templateId}`, `PublishPost {runId,templateId}`; nextOrganicContextId from snapshot; only one pendingPost; client never sends payout/context ID.
- **Constraints:** No free-text post box, no second client-only timer or simulated credit, no blocking modal through reveal.
- **Acceptance:** Organic post credited with no mission; mission post credited organic once + bonus once; weak mission requires second post; organic post during active mission doesn't advance mission; reopen/rejoin shows same context/outcome.
- **Validation:** Studio full two-mode journey, fake-clock/reducer specs, slow-network and duplicate-tap evidence, touch checks.
- **DoD:** IC-1/2 first playable posting loop; common DoD.

### BS-09 — V0 fast-phone shop and world integration
- **Objective:** Close first incremental loop with 50-Cuan upgrade and clearly higher organic yield.
- **Context/dependencies:** BS-08, BS-04 purchase service, BS-05 models.
- **Files:** Create `src/client/ui/Upgrades.luau`; modify `src/client/App.client.luau` and `src/server/WorldService.luau` only for integration defects; targeted tests.
- **Functionality / inputs / outputs:** Confirmed affordability/purchase, before/after 15->24 strong organic Cuan and 18->16s reveal, phone model swap and HUD/objective update.
- **API contract:** `BuyDevice {deviceId:"phone_fast"}` with server price50; no client price. World resync keyed by saved device ID.
- **Constraints:** Presentation failure reported/repairable on reopen/rejoin; never double-charge when model fails.
- **Acceptance:** Guided organic15 + mission organic15 + bonus80 =110; after phone cost50 balance60; next strong phone post earns24; model unique and visible.
- **Validation:** IC-2 Studio journey, server output, before/after screenshots, Rojo builds.
- **DoD:** V0A playable, not yet durable/public; common DoD.

### BS-10 — V0 recovery, reliability and polish
- **Objective:** Prove prototype across post settlement, claim, purchase, reconnect and failure.
- **Context/dependencies:** BS-09 integration complete; one branch owns affected core files.
- **Files:** Modify `src/server/{ProfileStore,SessionService,Bootstrap.server,MissionService}.luau`, `src/client/App.client.luau`, corresponding tests and assets only when defect requires review.
- **Functionality / inputs / outputs:** Recover organic/mission pending, paid posts, active/claimable/claimed runs, purchased phone; reconcile ambiguous save; restore camera, input, blocked state.
- **API contract:** v1 schema/remote changes need a documented amendment first. Lease/revision/operation ID and conditional save from `03` stay intact.
- **Constraints:** Never create blank save on failed load; dev data separate from live; do not mark V0 public-ready.
- **Acceptance:** IC-3 state rejoin matrix, fake read/write failure, no double post/claim, confirmed wallet survives reconnect, unbanked worker not present in V0.
- **Validation:** Fake-store suite, dev-universe API-backed rejoin, phone/PC emulator, Codex cross-system diff review.
- **DoD:** V0 internal technical prototype signed off with unresolved risks; common DoD.

## M1 tasks after V0 director approval
### BS-11 — Context catalog, PC Rumah, three-style balance
- **Objective:** Expand content/equipment to M1, then verify modeled affordability before first staff implementation.
- **Context/dependencies:** BS-10 verified; owns sequential catalog changes; `04` is numeric source.
- **Files:** Modify `src/shared/{Catalog,Rules}.luau` only as needed, `src/server/{ScoringCatalog,MissionService,FeedService,WorldService}.luau`, `src/client/ui/{Feed,Missions,Upgrades}.luau`; create `assets/world/PCRumah.rbxmx` and `tools/economy_sim.py`; update both Rojo mappings, tests and asset manifest.
- **Functionality / inputs / outputs:** Three organic contexts, four missions/three contexts each, 12 authored feed cards, unique strong fit from 2*trendMatch+audienceMatch, PC price220/yield2.5/reveal13, tier 1 300/3 and tier 2 1600/3 (worker slot2 remains locked until BS-13).
- **API contract:** Same PublishOrganic/PublishPost payloads and v1 counters; strong mission fit rotates across its three template IDs; public catalog contains no private affinity tags. `BuyDevice` exact-next phone_fast->pc_rumah.
- **Constraints:** No laptop sidegrade, M2 office button, unsupported context ID reorder, or post UI duplication; preserve two-post mission guarantee.
- **Acceptance:** All 12 mission contexts and three organic contexts have one unique winner; no single mission template wins every run; PC earns37 strong/22 weak; PC replaces CRT at stable prompt, with phone inert and no dual yield; three-style simulated milestone rows match `04`.
- **Validation:** Catalog validator, mission/feed rules, Studio all four missions with rotated replay, `python tools/economy_sim.py` (three policies + slow/weak sweeps), Codex editorial/economy review.
- **DoD:** IC-4 content/PC ready without staff dependencies; common DoD.

### BS-12 — First desk, trainee and banked online income
- **Objective:** Implement one paid worker seat and credible idle progression.
- **Context/dependencies:** BS-11 complete; v1 ownedDesks/workers already specified in `03`.
- **Files:** Modify `src/shared/Catalog.luau`, `src/server/{EconomyService,SessionService,WorldService,Bootstrap.server,NetRouter}.luau`, `src/client/App.client.luau`; create `src/client/ui/Workers.luau`, `assets/world/{WorkerDesk,Trainee}.rbxmx`; update both Rojo mappings, tests and asset manifest.
- **Functionality / inputs / outputs:** Desk1 cost180, hire1 cost500, +1.5 Cuan/s only while connected; 30s durable banking and nonspendable pending display; rig occupies first authored seat.
- **API contract:** `BuyDesk {slotIndex:1}`, `HireWorker {slotIndex:1,roleId:"trainee"}`; profile contains ownedDesks `[1]`, workers `[slot1]`; `Snapshot.incomePerSecond=1.5` after hire.
- **Constraints:** One aggregate scheduler, no offline pay/per-rig worker loop; no client-proposed Cuan. Failed bank stays unspendable and blocks economy.
- **Acceptance:** No desk/no PC/no funds denies hire; after hire 30 healthy seconds bank45; disconnect 30s earns zero; first worker visible; profile/rejoin round trip; modeled first-hire active7:25/balanced9:31/passive10:50 under exact assumptions.
- **Validation:** Fake-clock bank/phase tests, dev-store rejoin/failure, Studio phone profiling, Codex review.
- **DoD:** IC-4 first worker proved; common DoD.

### BS-13 — Second workstation and home-studio goal
- **Objective:** Make M1 a real incremental chapter rather than stop at one hire.
- **Context/dependencies:** BS-12 stable; `04` defines tier2 threshold and second cost/rate.
- **Files:** Modify `src/shared/Catalog.luau`, `src/server/{EconomyService,WorldService}.luau`, `src/client/ui/{Workers,Upgrades}.luau`, objectives in `src/client/App.client.luau`; update bedroom/worker prefab variants and tests.
- **Functionality / inputs / outputs:** At lifetime1600/3 claims, desk2 cost250 and hire2 cost750; two distinct occupied seats, rate3 Cuan/s, chapter-complete goal with continued organic/missions/online income.
- **API contract:** `BuyDesk {slotIndex:2}`, `HireWorker {slotIndex:2,roleId:"trainee"}`; cannot skip slot1, hire two in slot1, exceed cap2, or credit worker without owned desk.
- **Constraints:** Reuse same worker service/rig; no new room prefab, role, per-NPC loop or empty office UI. Do not alter schema without reviewed amendment.
- **Acceptance:** Active/balanced/passive second-hire scenario 11:45/14:01/22:20 under `04` assumptions; 30 healthy seconds bank90 with two; no offline earnings; two visible non-clipping workers on mobile; profile restore after rejoin.
- **Validation:** Fake-clock/seat tests, dev-store rejoin, Studio art/performance/phone captures, balance simulator and Codex review.
- **DoD:** IC-4 M1 home-studio arc complete; common DoD.

### BS-14 — Closed-beta candidate gate
- **Objective:** Verify the exact content-complete candidate for limited closed beta and fix only evidenced defects.
- **Context/dependencies:** BS-13 merged; no concurrent core edits; director alone decides closed-beta access. Wider publication requires a separate decision after beta evidence.
- **Files:** Evidence record in `docs/09-TESTING-AND-QUALITY.md` or separate release record; targeted source/test defect fixes only.
- **Functionality / inputs / outputs:** Run G0–G5 tests, mobile/low-end performance, uncoached first and second sessions, 20-minute online idle, sustained single-key DataStore/write-latency and failure/rollback drill, asset/content originality audit.
- **API contract:** No unreviewed contract changes; any change returns to owning task and reruns dependent gates.
- **Constraints:** No synthetic evidence, fake build log, real-data reset, or publish based only on Rojo build.
- **Acceptance:** IC-5 `09` closed-beta Go/No-Go evidence, unresolved risks ranked, exact candidate build and rollback reader recorded; explicit director **closed-beta** approval. Wider release requires later real player evidence and separate approval, not M2 scope.
- **Validation:** Codex whole-tree review, Studio Play/dev-store rejoin, real lower-end phone, security probes and final git diff/test log review.
- **DoD:** Closed-beta gate passed or candidate remains private; common DoD.

## Allocation and review
Trial GLM, DeepSeek, StepFun, or Codex on a bounded same-task fixture: compilable Luau, contract fidelity, test discovery, Studio tool reliability, asset quality, and revision responsiveness. No fixed model hierarchy. Codex coordinates short assignments and re-runs tests against the merged branch; agents with verified Studio access may own art/UI with human review. A task blocked on real verification is blocked, not "mostly done". No commit, push, or publication is implicit in this plan.
