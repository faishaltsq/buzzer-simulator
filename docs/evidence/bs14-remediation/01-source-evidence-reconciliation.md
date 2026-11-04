# BS-14 RC-1 — Source / Evidence Reconciliation

**Candidate under audit:** `master` @ `fa55baa4a417097b6d4f8a032c602bcf1c1df19e`
**Audited artifact:** `docs/evidence/bs14/RELEASE-CANDIDATE-BS14.md` (`REL-BS14-G5-20261103`)
**Audit date:** 2026-11-04
**Method:** every claim in the release document was traced to the code or artifact that would have to be true for the claim to hold. A claim is marked **FALSE** when the repository contradicts it, **UNSUPPORTED** when no artifact in the repository can establish it, and **TRUE** when a reproducible source path exists.

This document does not change product behaviour. It corrects reporting.

---

## Summary of verdicts

| # | Claim in release doc | Verdict | Source of truth |
| :-- | :-- | :-- | :-- |
| C1 | Active schema is version 2 | **FALSE** | `src/server/ProfileStore.luau:30` |
| C2 | v1 payloads "migrate non-destructively" to v2 | **FALSE** | `src/server/ProfileStore.luau:603-612`, `:797-800` |
| C3 | DataStore name is `BuzzerProfile_v1` | **FALSE** | `src/server/ProfileStore.luau:29` |
| C4 | Key namespace unstated / implied per-place | **UNSUPPORTED** | `src/server/ProfileStore.luau:666` |
| C5 | `SessionService:SetWorkerAccrualEnabled(false)` exists | **FALSE** | zero matches in `src/`, `tests/`, `tools/` |
| C6 | `ProfileStore:SetReadOnly(true)` exists | **FALSE** | zero matches in `src/`, `tests/`, `tools/` |
| C7 | `Catalog.Shipped = Catalog.M1Shipped` is an operational toggle | **FALSE** | `src/shared/Catalog.luau:194` |
| C8 | Worker bank caps "30 minutes offline accrual" | **FALSE** | `src/server/SessionService.luau:58`, `:686-702`, `:856-886` |
| C9 | Ten named security probes (P01–P10) | **FALSE** | `docs/evidence/bs14/security-regression.txt` |
| C10 | 59.9 FPS average on mobile | **MISCLASSIFIED** | `tools/agent/run_mobile_profiling.py:246-250` |
| C11 | Tablet 768×1024 verified clean | **FALSE** | `docs/evidence/bs14/mobile-profiling.json` |
| C12 | "Unguided player journey", 17 milestones | **MISLABELED** | `tools/agent/run_unguided_playtest.py:14,55` |
| C13 | Journey timeline timestamps are measured | **FALSE (partly)** | `tools/agent/run_unguided_playtest.py:176-187` |
| C14 | Regression evidence is a complete console log | **FALSE** | `docs/evidence/bs14/g0-regression-raw.txt:1` |
| C15 | 20-minute connected idle gate passed | **FALSE** | `docs/evidence/bs14/idle-live-console.txt` (traceback) |
| C16 | DataStore resilience 7/7 | **MISCLASSIFIED** | `tools/agent/run_persistence_audit.py:31-47` |
| C17 | Universe 10774181892 / Place 100558697471228 is the target | **UNVERIFIED** | public universe lookup returns no game record |

---

## C1 — Schema version

**Claim** (`RELEASE-CANDIDATE-BS14.md:83`): "**Current Active Schema:** Version 2 (Home Studio Chapter with `ownedDesks`, `workers`, `incomePerSecond`, `pendingWorkerCuan`)."

**Source of truth:** `src/server/ProfileStore.luau:30`

```lua
local SCHEMA_VERSION = 1
```

The shipped v1 profile already carries the Home Studio fields. They are validated as part of the v1 profile schema, not as a new schema generation:

- `tests/Specs/ProfileStore.spec.luau:1891` asserts `expectEqual(ProfileStore.SCHEMA_VERSION, 1, "schema version v1")`.
- `ProfileStore.luau:861` stamps every new envelope with `schemaVersion = SCHEMA_VERSION` (1).

**Verdict:** FALSE. There is no schema v2 anywhere in the repository.

**Correction:** Schema version is **1**. The Home Studio fields (`ownedDesks`, `workers`, `incomePerSecond`, `pendingWorkerCuan`) are part of the v1 profile and were added as optional fields with defaults, which is why no schema bump was required.

**Verification:** source read plus the shipped spec assertion above; the regression suite (rerun for this remediation) includes `ProfileStore.spec` 59/59.

---

## C2 — "Backward compatible migration"

**Claim** (`:84-89`): v1 payloads "parse cleanly and migrate non-destructively"; "Version 2 profile snapshots read by a simulated V1 server reader ignore new worker fields without schema panic or data loss."

**Source of truth:** `ProfileStore.luau:603-612`

```lua
local function validateEnvelope(envelope: any): (boolean, { string })
	...
	if envelope.schemaVersion ~= SCHEMA_VERSION then
		return false, { `unsupported schemaVersion {tostring(envelope.schemaVersion)} (expected {SCHEMA_VERSION})` }
	end
```

and `:797-800`:

```lua
if typeof(raw) == "table" and raw.schemaVersion ~= nil and raw.schemaVersion ~= SCHEMA_VERSION then
	-- Preserve unknown schema data untouched; never migrate here.
	return { ok = false, code = "UNSUPPORTED_SCHEMA", detail = table.concat(problems, "; ") }
end
```

The same guard aborts the conditional write when a foreign schema is seen (`:810-812`, `:1028`, `:1138`), so an unknown-schema record is **preserved, not rewritten**.

**Verdict:** FALSE as written. There is no migration path: a record with any other `schemaVersion` is refused and left byte-for-byte intact. That is a safer contract than the document describes, but it is a different contract.

**Correction:** "The reader accepts `schemaVersion == 1` only. Any other version is surfaced as `UNSUPPORTED_SCHEMA` and the stored value is preserved untouched; no automatic migration exists. A future schema change must ship its own explicit migration and is out of scope for this candidate."

**Verification:** source read of the four guard sites; `ProfileStore.spec` exercises the corrupt/foreign-schema preservation path.

---

## C3 / C4 — DataStore identifier and key namespace

**Claim** (`:182`): "**DataStore Name:** `BuzzerProfile_v1` (with automatic schema v2 compatibility layer)."

**Source of truth:** `ProfileStore.luau:29` and `:666`

```lua
local STORE_NAME = "PlayerData"
...
self._key = `Player_{userId}`
```

**Verdict:** FALSE. The store is `PlayerData`; the key is `Player_<userId>`. `BuzzerProfile_v1` does not exist in the repository and would address a different, empty store if used operationally.

**Correction:** DataStore name **`PlayerData`**, key namespace **`Player_{UserId}`**, one record per player, envelope `{ schemaVersion, revision, lastSaveOpId, updatedAt, profile, lease }`.

**No rename is proposed.** Renaming a live store silently resets every player's profile; the documentation is wrong, not the code.

**Verification:** source read. Note the store name is also emitted in the DEV_FALLBACK warning at `:134`, which appears in local Studio logs.

---

## C5 / C6 — Nonexistent kill switches

**Claim** (`:193-194`): toggling `SessionService:SetWorkerAccrualEnabled(false)` and `ProfileStore:SetReadOnly(true)`.

**Source of truth:** repo-wide search returns **zero** matches for either identifier in `src/`, `tests/`, `tools/`. The full public surface of `SessionService` (36 `function SessionService:` declarations) contains no accrual toggle.

**Verdict:** FALSE. Neither method exists. An operator following this document during an incident would find no such function and would lose the response window.

**Correction:** see `08-rollback-verification.md`. The real, existing controls are: place-version rollback in the Creator Dashboard, `SessionService:IsWritable()` / `Stop()` / `Reconcile()` (lifecycle, not a switch), and the `saveStatus` field surfaced in the snapshot. There is no runtime kill switch in this candidate, and none should be invented under time pressure — a live toggle that stops accrual is a gameplay-authority change and needs its own design and security review.

---

## C7 — "Kill-Switch 1" via `Catalog.Shipped`

**Claim** (`:192`): "Set `Catalog.Shipped = Catalog.M1Shipped` to immediately cap progression."

**Source of truth:** `src/shared/Catalog.luau:194` — `Catalog.Shipped = Catalog.H2Shipped`. `Catalog` is a module inside the place; changing it requires an edit plus a **new place publish**. Nothing at runtime can flip it.

**Verdict:** FALSE as an operational switch. Accurate as a build-time change.

**Correction:** "`Catalog.Shipped` is a compile-time table selection. Capping progression requires a code change and a republish, i.e. the same rollback mechanism as any other build change; it is not an in-game toggle."

---

## C8 — Offline worker accrual

**Claim** (`:204`, risk R03): "Worker bank caps at 30 minutes offline accrual."

**Source of truth:**

- `SessionService.luau:58` — `local WORKER_BANK_INTERVAL = 30`. This is the **connected-session banking cadence**, not an offline cap.
- `SessionService.luau:686-702` — `CaptureConnectedTime` advances accrual from a monotonic clock only while the session `IsWritable()`; it returns early otherwise.
- `SessionService.luau:856-886` — `_discardRestoredAccrual` / `_restoreUnbanked` exist to guarantee an interval is credited **exactly once**; restored accrual is discarded, never paid again.

**Verdict:** FALSE. The authoritative contract is: **worker income exists only during connected, writable sessions. There is no offline accrual, and no offline catch-up.** The 30-second constant is how often pending accrual is banked while connected.

**Correction:** "Worker income accrues only while a player is connected and the session is writable, and is banked to durable storage every 30 s of connected time. There is no offline accrual and no offline catch-up: a player who leaves earns nothing while away."

**Verification:** source read; `BS12WorkerEconomy.spec` and `BS10Recovery.spec` cover accrual-once and restore semantics; the idle gate in `02-idle-20min-analysis.md` measures connected-only accrual end to end.

---

## C9 — Security probe inventory

**Claim** (`:65-76`): ten probes described as P01 balance tampering, P02 template-ID injection, P03 runId spoofing, P04 unearned claim, P05 double-claim race, P06 device tier bypass, P07 unowned desk, P08 cooldown bypass, P09 120-calls-in-1s rate limit, P10 malformed UTF-8 / 4 KB payloads.

**Source of truth:** `docs/evidence/bs14/security-regression.txt` (the artifact the document cites) lists a different set:

| Executed probe | Assertion in `tools/agent/run_security_probes.py` |
| :-- | :-- |
| SEC-01 Unknown action forgery rejected | `:112-113` — `code == "UNKNOWN_ACTION"` |
| SEC-02 Client price injection rejected | `:118-119` — `code == "INVALID_INPUT"` |
| SEC-03 Invalid slot numerics rejected | `:126-128` — three `INVALID_INPUT` results |
| SEC-04 Prompt beyond 12 studs rejected | `:153` — far prompt refused, near prompt accepted |
| SEC-05 Cloned prompt rejected | `:166` — "prompt does not belong to this player's room" |
| SEC-06 Command flood throttled | `:176` — `admitted <= 8 and throttled >= 12` for a 20-call burst |
| SEC-07 Conflicting replay refused | `:182` — `INVALID_INPUT` |
| SEC-08 Insufficient funds purchase refused | `:188` — `INSUFFICIENT_FUNDS` |
| SEC-09 Premature desk 2 blocked | `:194` — `NOT_READY` |
| SEC-10 Expired dashboard refuses mutation | `:203` — `SESSION_EXPIRED` |

**Verdict:** FALSE for the document as written. Only a few descriptions overlap (invalid action, malformed input, replay, throttle, tier gate). The document's SQL-injection examples, `spoofed-run-999` runId, double-claim race, and 4 KB payload limits are **not** what the cited evidence records.

**Correction:** the security section is rebuilt from the executable probes in `07-security-results.md`, and each probe is classified as *live client/server* or *isolated service test*. Claims not backed by an executed probe are removed, not reworded.

---

## C10 — The 59.9 FPS figure

**Claim** (`:129`): "Average Frame Rate: 59.9 FPS (Rock solid 60 FPS target)" under "Mobile Usability & Performance".

**Source of truth:** `tools/agent/run_mobile_profiling.py:246-250`

```lua
local dt = RunService.Heartbeat:Wait()
...
local avgFps = 60 / totalTime
```

This is a **server-side Heartbeat interval estimate** taken inside a Studio Play session. It measures how fast the Studio server heartbeats are scheduled; it says nothing about client rendering on a phone.

**Verdict:** MISCLASSIFIED. Not evidence of Android client performance. It is, at best, evidence that the Studio simulation was not frame-starved.

**Correction:** report as "Studio-simulation heartbeat estimate: 59.9 FPS (server `RunService.Heartbeat`, not a client render measurement)". Real device rendering remains unmeasured — see `04-real-device-report.md` (BLOCKED).

---

## C11 — Tablet layout

**Claim** (`:113`): "Tablet Portrait 768×1024 — Native Floating Window, 0 violations."

**Source of truth:** `docs/evidence/bs14/mobile-profiling.json`

- The entry is named `Tablet Landscape (768x1024)` — a portrait resolution labelled landscape.
- Recorded `viewport` is **724×544**, not 768×1024.
- `target_mode: "wide"`, actual mode compact, `modeMatch: false`.

**Verdict:** FALSE. The tablet row records a mode mismatch and a viewport that is not the labelled one.

**Analysis:** `run_mobile_profiling.py:129-137` resizes the *Studio window* with `win32gui.MoveWindow`, then reads `workspace.CurrentCamera.ViewportSize`. On this host the requested 768×1024 window produced a 724×544 viewport, so the profile never exercised a 768-wide screen. The compact/wide decision is taken from the dashboard window's `AbsoluteSize` (`:157`), not the screen, so a 651×427 floating window is correctly classified compact — the mismatch is a harness artefact plus a mislabeled row, not a proven UI defect. The 768-wide behaviour remains **unverified**.

---

## C12 / C13 — "Unguided" journey

**Claim** (`:134-137`): "An automated fresh player journey…", section titled *Unguided Player Journey*; `:217` "Player Journey: 17/17 Milestones Validated". Note the document already says "automated" in the body while labelling the gate "unguided".

**Source of truth:** `tools/agent/run_unguided_playtest.py:14` obtains `StudioClientBridge` from the local `PlayerGui`, and `:55` drives actions through `act(...)`; the ladder uses a fixed mission/template list. No human input exists anywhere in the path.

**Verdict:** **MISLABELED.** It is an *automated connected gameplay journey through the real client action path*. That is a real and useful test — it is simply not an unguided human playtest, and a human-usability gate cannot be satisfied by it.

**Additional defect (C13):** in the resume path, milestones 0–10 are **hardcoded dictionaries with literal timestamps and literal balance strings** (`:176-187`), e.g. `"time": "16:16:55 UTC", "detail": "... payouts balance: 110 Cuan"`. Only the live path (`:155`) stamps real time. `playtest-journey.json` was produced by the resume path — step details match the literals exactly. Therefore the 17-milestone timeline is **partly reconstructed from constants**, and its timestamps are not measurements of that run.

**Correction:** retain the artifact as "automated connected gameplay journey"; strike the per-milestone timestamps as evidence; human playtesting is BLOCKED (see `05-human-playtest-observations.md`).

---

## C14 — Truncated regression log

**Claim** (`:213-217` and Section 2): 748/748 executed, complete console evidence.

**Source of truth:** `docs/evidence/bs14/g0-regression-raw.txt:1` begins with:

```
[TRUNCATED DUE TO LENGTH LIMIT]
```

**Verdict:** FALSE for "complete console log". The suite totals were real; the raw artifact was clipped, so it cannot be re-checked line by line.

**Correction:** this remediation reran the suite and captured an **untruncated** log (511 lines, 461 `[PASS]` lines, structured result present) — see `06-regression-summary.md`. The old artifact stays in history.

---

## C15 — The 20-minute idle gate

**Claim** (`:130` memory stability; Section 2.1 idle assertions in the earlier draft): the 20-minute connected idle gate passed.

**Source of truth:** `docs/evidence/bs14/idle-live-console.txt` ends with:

```
RuntimeError: BuyDevice refused: {'sent': False}
```

and its resume line shows `balance=1302 rate=0 tier=1 desks=[] workers=[]` — i.e. no desk and no worker ever existed in that run.

**Verdict:** FALSE. The run never reached the 2-worker state, never idled 20 minutes, and never produced idle metrics.

**Root cause (harness, not product):** `run_online_idle_resume.py:156` raised on the first `{'sent': False}`. `sent` is the client admission result of `BeginMutation`; a refusal means the mutation lane was busy or the session was momentarily non-writable. The script had no retry, no backoff, and no diagnosis. That is a harness defect. It is not evidence of a gameplay defect, and the product was not changed for it.

**Correction:** rebuilt harness `tools/agent/bs14_rc_idle.py` retries with backoff and records the refusal reason. Results in `02-idle-20min-metrics.json` / `02-idle-20min-analysis.md`.

---

## C16 — "7/7 DataStore audits"

**Claim** (`:23`): persistence gate PASS with 7/7 audits.

**Source of truth:** `tools/agent/run_persistence_audit.py:31-47` builds an in-memory adapter (`{ data = {}, writes = 0, reads = 0, failNext = 0, delay = 0 }`) with injected failures and `newStore(adapter, ...)`. No `DataStoreService` call is made.

**Verdict:** MISCLASSIFIED. It is a **service-level test with an injected adapter**, not cloud DataStore validation. It is valuable — it proves lease, revision and ambiguous-write handling — but it cannot establish cloud behaviour (throttling, replication, region, studio access).

**Correction:** reclassify as "injected-adapter persistence tests"; the cloud G2 gate is BLOCKED — see `03-datastore-g2-matrix.md`.

---

## C17 — Universe / Place identifiers

**Claim** (`:180-181`): Universe `10774181892`, Place `100558697471228`.

**Verification attempt:** `GET https://games.roblox.com/v1/games?universeIds=10774181892` returns a placeholder record (`id: 0`, `name: "[TITLE UNAVAILABLE]"`, `studioAccessToApisAllowed: false`), i.e. no accessible game backs that universe id.

**Verdict:** UNVERIFIED. Either the ids are stale/invented or the game is private to an account the public API cannot see. No publish or place inspection was performed (not authorized).

**Correction:** record as "target universe identifiers unverified"; do not cite them as release configuration.

---

## Claims that survived audit

| Claim | Basis |
| :-- | :-- |
| 20 suites / 748 runtime tests / 0 failures | rerun for this remediation, untruncated log, runId `1fbf063e-7911-4d64-845d-ae615672c283` |
| Worker rate 1.5 Cuan/s per worker, 3.0 at two workers | `Catalog.luau:88`, `Rules.luau`, `02-idle-20min-metrics.json` |
| Desk prices 180/250, hire prices 500/750 | `Catalog.luau:86-87` |
| Banking every 30 s of connected time | `SessionService.luau:58`, observed in idle samples |
| Save-path failures stay unconfirmed (`SAVE_PATH_CODES`) | `SessionService` guard, `BS10Recovery.spec` B6 |
| No offline accrual | `SessionService.luau:686-702`, `:856-886` |

---

## Consequence for the release document

`RELEASE-CANDIDATE-BS14.md` claimed ten of the seventeen audited items incorrectly and certified the build "RELEASE READY". Under the remediation rules that certification cannot stand: the correct verdict is **BLOCKED — CLOSED BETA NOT AUTHORIZED**, because cloud DataStore, physical-device, human-usability and rollback-rehearsal proof are all absent. The replacement document is `09-release-gate-verdict.md`; the original stays in Git history for audit.
