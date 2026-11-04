# BS-14 RC-1 — Regression Summary (G0)

**Candidate:** `fa55baa4a417097b6d4f8a032c602bcf1c1df19e` (source unchanged by this remediation; only `tools/` and `docs/` were added)
**Executed:** 2026-11-04 06:22 UTC (13:22 local, UTC+07)
**Environment:** Roblox Studio `version-7062aec9dbe74b14`, Rojo 7.7.1, Python 3.14.7, Windows 11
**Runner:** `python tools/agent/check_all_suites.py --studio-id <id> --timeout 150`

---

## 1. Result

| Metric | Value |
| :-- | :-- |
| Suites found | **20 / 20 expected** |
| Runtime tests executed | **748** |
| Failures | **0** |
| Source-defined test cases | 683 |
| Static assertion calls | ~3147 |
| Structured result runId | `1fbf063e-7911-4d64-845d-ae615672c283` |
| Completion marker | `BS01_TESTS_PASSED:1fbf063e-…` |
| Saved console | `06-regression-console.log` — 511 lines, 461 `[PASS]`, 1 `BS_REGRESSION_RESULT`, sha256 `c92568d92e70bb439e44c71d05e87a924f57e915752caac3368ebdf824e32aa9` |

The console log is **not truncated**: it starts at the first `[PASS]` line of the run and ends with the structured result plus the trailing client notice. The previous artifact (`docs/evidence/bs14/g0-regression-raw.txt`) began with `[TRUNCATED DUE TO LENGTH LIMIT]` and could not be re-checked; this one can.

## 2. Per-suite results

| Suite | Result |
| :-- | :-- |
| AppClientIntegration | 11/11 |
| BS09FastPhone | 36/36 |
| BS10Recovery | 42/42 |
| BS11M1Content | 12/12 |
| BS12WorkerEconomy | 21/21 |
| BS13HomeStudio | 44/44 |
| Bootstrap | 17/17 |
| ClientState | 30/30 |
| ComposerIntegration | 14/14 |
| EconomyService | 39/39 |
| FeedService | 18/18 |
| MissionService | 85/85 |
| NetRouter | 89/89 |
| PostingState | 57/57 |
| Presentation | 9/9 |
| ProfileStore | 59/59 |
| Rules | 16/16 |
| SessionIntegration | 46/46 |
| SessionService | 73/73 |
| WorldService | 30/30 |

## 3. Build artifacts

| Artifact | Command | SHA-256 |
| :-- | :-- | :-- |
| `build/BuzzerSimulator.rbxlx` | `rojo build default.project.json -o build/BuzzerSimulator.rbxlx` | `9c8c431d28a1e2347c08cda76450a129071c7166f1bf9ab08f7b7bc30ed3e833` |
| `build/BuzzerTests.rbxlx` | `rojo build test.project.json -o build/BuzzerTests.rbxlx` | `79d72e28685216cd4035fd586284edcf4bd106615b378433a2c4bd4d1a2b1b1c` |

Both builds were regenerated from `fa55baa` for this run; the suite ran against the freshly built test place, not a stale committed artifact.

## 4. Economy simulation (model-level)

`python tools/economy_sim.py` →

- **Invariants: PASS** — including "two-worker 30 s bank == 90 Cuan", "mixed 1→2 worker interval (10 s @1.5 + 20 s @3.0 == 75 Cuan)", "purchase during pending accrual preserves unbanked carry", "disconnect loss bounded to ≤ 30 s", and payback timings (first hire 5:33, bundle 1 7:33, bundle 2 11:07).
- **Documented-target agreement: 25/33**, with 8 deltas in `docs/04-INCREMENTAL-ECONOMY.md` pacing targets, e.g. Balanced Trainee 2 documented 14:01 vs computed 13:00; Passive Desk 2 documented 18:20 vs computed 18:00.

**This is reported, not reconciled.** Acceptance criteria were not edited to match the model, and Catalog constants were not changed to match the doc. The deltas are small and all in the "player progresses slightly earlier than documented" direction; they are a documentation-drift item (P2), not a blocker.

## 5. Phase 6 checklist status

| # | Required check | Status | Where |
| :-- | :-- | :-- | :-- |
| 1 | Production Rojo build | **PASS** | §3 |
| 2 | Test Rojo build | **PASS** | §3 |
| 3 | Complete Studio regression | **PASS** | §1–2 |
| 4 | Structured run ID + marker match | **PASS** | runId `1fbf063e-…` appears in marker and JSON |
| 5 | Regression checker self-tests | **PASS (existing suite)** | `check_all_suites.py` validates structured JSON; exercised by this run |
| 6 | Economy simulation | **PASS with doc deltas** | §4 |
| 7 | Security remote validation | see `07-security-results.md` | live probe run |
| 8 | Starter → Home Studio journey | **PASS** | `05-automated-journey-summary.md` |
| 9 | Camera open/close/death recovery | **NOT RE-RUN** | requires interactive camera checks; `BS09FastPhone` covers the phone controller, not camera restore |
| 10 | Two-worker banking at 3.0 Cuan/s | **PASS** | `02-idle-20min-metrics.json` |
| 11 | Unknown write response reconciliation | **PASS at spec layer** | `BS10Recovery.spec` D1–D9, `ProfileStore.spec` ambiguous-write cases |
| 12 | Session expiration and replay checks | **PASS at spec layer** | `BS10Recovery.spec` D4/D5 + live SEC-10 probe |

Item 9 is the one Phase-6 check this remediation did not execute; it is a UI/camera behaviour that needs a Play session with scripted camera assertions and was not covered by any existing runner.

## 6. Change-safety note

No file under `src/` was modified by this remediation. The candidate's gameplay, economy, networking and persistence code is byte-identical to PR #9's merge commit, so the suite result above applies to the exact artifact under review; the build hashes in §3 identify it.
