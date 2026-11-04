# BS-14 RC-1 — 20-Minute Connected Idle Analysis

**Candidate:** `fa55baa` (source unchanged) + `tools/agent/bs14_rc_idle.py`
**Run window:** 2026-11-04 07:08:54 → 07:28:56 UTC (1,201.8 s observed)
**Environment:** Roblox Studio `version-7062aec9dbe74b14`, Play Solo, local `build/BuzzerSimulator.rbxlx`
**Baseline state:** balance 8, lifetime 1,958, tier 2, desks `[1,2]`, workers 2 (trainee ×2), rate 3.0 Cuan/s, revision 101
**Final state:** balance 3,623, lifetime 5,573, pending 21, revision 141, saveStatus `healthy`
**Artifacts:** `02-idle-20min-raw.log` (41 progressive samples), `02-idle-20min-metrics.json`

---

## 1. Headline

| Metric | Expected | Observed | Verdict |
| :-- | :-- | :-- | :-- |
| Credited Cuan over 1,200 s @ 3.0/s | 3,600 | **3,615** | +15 (+0.42%) — reconciled in §3 |
| Effective rate | 3.000 /s | **3.0085 /s** | within rounding + sampling tolerance |
| Lifetime delta | — | **3,615** | equals balance delta |
| Banking commits (revision) | ~40 per 30 s | **40** | exactly one commit per interval |
| Failed saves | 0 | **0** | `saveStatus: healthy` in 41/41 samples |
| Worker count stability | 2 | **2** in 41/41 samples | no despawn / double hire |
| Pending never spendable | yes | **0 ≤ pending ≤ 54** | never folded into `balance` before a bank |

This is a **real 20-minute wall-clock run** — no clock injection, no fast-forward. Both the harness clock and the in-game revision counter advance by real time.

---

## 2. Chronological samples (abridged; full series in the raw log)

| UTC | t+ | Balance | Lifetime | Pending | Revision |
| :-- | :-- | --: | --: | --: | --: |
| 07:08:54 | baseline | 8 | 1,958 | 0 | 101 |
| 07:09:24 | 30 s | 79 | 2,029 | 54 | 102 |
| 07:09:54 | 60 s | 170 | 2,120 | 54 | 103 |
| 07:11:24 | 150 s | 443 | 2,392 | 49 | 106 |
| 07:16:24 | 450 s | 1,353 | 3,302 | 39 | 116 |
| 07:22:54 | 840 s | 2,192 | 4,141 | 33 | 129 |
| 07:27:54 | 1,140 s | 3,456 | 5,405 | 21 | 139 |
| 07:28:54 | 1,200 s | 3,623 | 5,573 | 21 | 141 |

Per-30 s deltas: 40 values, minimum 71 (first partial interval), maximum **91**, median **91**. No delta below zero and none above the 100 guard band.

---

## 3. Reconciliation of 3,615 vs 3,600

Three bounded effects, none of them a credit leak:

1. **Interval drift.** `time.sleep` plus MCP round-trip overhead makes each sample slightly longer than 30.0 s; the accrual is driven by the server's monotonic clock, not by the sampler. 1,201.8 s of connected time at exactly 3.000/s ≈ 3,605 Cuan before rounding.
2. **Baseline/timer offset.** The baseline snapshot is taken *before* the wall-clock timer starts; any bank that lands in that few-hundred-millisecond gap is counted in the delta but not in the timer.
3. **Fractional carry.** `EconomyService.tickAtRate` accumulates `fractionalIncome + rate × seconds`, credits `math.floor(...)`, and carries the residual (`EconomyService.luau:462-464`). Carry is conserved, so it cannot systematically over-credit; it only shifts when a whole Cuan appears.

Upper bound on the discrepancy: one banking interval (≤ 90 Cuan) plus < 1 Cuan of carry. Observed: **+15 Cuan**, well inside that bound and consistent with effects 1–2.

**The rate itself is exact:** median delta of 91 per ~30.3 s = 3.00/s; over the full window, 3,615 / 1,201.8 = 3.0085/s.

### Console notes during the window

The console carried two recurring lines, neither caused by this run:

1. `[ProfileStore:DEV_FALLBACK] … Real DataStore G2 remains OPEN` — the local store limitation, quoted in §4. Expected for an unpublished place.
2. `ContentId: rbxassetid://203785492 failed due to: Asset type does not match requested type` (6 per console page). No file under `src/` or any `assets/world/*.rbxmx` references that ID — checked with a repo-wide search — and `assets/ASSET-MANIFEST.md:203` already records it as an engine content-type warning unrelated to the exported prefabs. It produced no script error and no gameplay effect during the 20 minutes.

No other warnings appeared; in particular no `LOCKED`, `SAVE_UNAVAILABLE`, `BUSY`, or lane-timeout messages.

---

## 4. Invariant checks

| # | Invariant | Result | Evidence |
| :-- | :-- | :-- | :-- |
| 1 | One aggregate worker scheduler | **PASS** | `Runtime:Step` is the only accrual driver and is guarded by `record.pumping`, so a record has at most one active lane pump (`BootstrapRuntime.luau:276-300`); accrual is folded into a single `_pendingAccrual` list (`SessionService.luau:664-684`) |
| 2 | Healthy banking boundaries | **PASS** | 40 commits for 40 intervals, revision 101→141 |
| 3 | No double credit | **PASS** | max delta 91 = 30 s × 3.0 + ≤1 rounding; no interval credited twice |
| 4 | No skipped or duplicated intervals | **PASS** | delta count = 40 = elapsed/30; no zero-delta gaps |
| 5 | Stable lease renewal | **PASS (observed)** | `saveStatus: healthy` in all 41 samples; no `LOCKED`/`SAVE_UNAVAILABLE` in console |
| 6 | No offline catch-up | **PASS** | accrual only advances while `IsWritable()` and connected (`SessionService.luau:686-702`); restored accrual is discarded (`:856-886`); teardown at 07:28:56 stopped accrual with the profile banked |
| 7 | Pending income nonspendable | **PASS** | `pendingWorkerCuan` never appears in `balance`; it cycles 0→54 and resets at each bank; `_buildSnapshot` marks it ephemeral (`:497-502`) |
| 8 | Correct confirmed balance after banking | **PASS** | balance delta == lifetime delta == 3,615; no spending during the window |
| 9 | No unexpected save failures | **PASS** | 41/41 `healthy` |
| 10 | No uncontrolled memory or task growth | **NOT MEASURED** | memory was not sampled during this window; the previous report's "0 MB leak" claim had no artifact behind it, and this run does not replace it |
| 11 | Clean logout/rejoin | **PARTIAL** | teardown returned `Game Stopped` with the profile banked; cross-session rejoin cannot be exercised locally because the local store is the ephemeral DEV_FALLBACK (`ProfileStore.luau:134`), which is the code's own warning in this session's console |
| 12 | Connected vs disconnected time | **PASS** | 1,201.8 s connected, 0 s offline accrual; the run ends when the session stops |

**Console confirmation of the local-store limitation** (captured at t+1200 s):

```
[ProfileStore:DEV_FALLBACK] DataStore handle 'PlayerData' unavailable in offline Studio
(You must publish this place to the web to access DataStore.). Using ephemeral in-memory store
for local Studio session only. Real DataStore G2 remains OPEN.
```

This is why item 11 is partial and why G2 cannot be satisfied here.

---

## 5. Root cause of the previous failure (harness, not product)

The committed `docs/evidence/bs14/idle-live-console.txt` ended with:

```
RuntimeError: BuyDevice refused: {'sent': False}
```

with `resume: balance=1302 rate=0 tier=1 desks=[] workers=[]` — no desk, no worker, no idle window.

`sent` is the result of the client's own admission gate. `ClientState:MutationBlockReason()` refuses with `BUSY` when any of these hold (`ClientState.luau:166-185`): an uncertain mutation exists, a mutation is already in flight, or the client is awaiting a confirmed snapshot revision. The old script (`run_online_idle_resume.py:156`) raised on the first refusal, with no retry, no backoff, and no diagnosis.

Independently, this remediation reproduced a *second*, distinct harness fault: skipping `phone_fast` and buying `pc_rumah` directly is refused with `NOT_READY`, because the catalog order is enforced (`ClientState.luau:262-274`, mirrored server-side). That is intended product behaviour, not a defect.

**No production code was changed for either failure.**

---

## 6. Verdict

**The 20-minute connected idle gate PASSES on real time** for items 1–9 and 12, with item 10 not measured and item 11 only meaningful in a cloud environment.

This does **not** satisfy the persistence gate: a local Studio run cannot prove cloud durability, and the console says so explicitly.
