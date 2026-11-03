# BS-13 Evidence — Second Workstation & Home Studio

Genuine Roblox Studio artifacts only. No fabricated or generated substitutes.

| # | Requirement | File | Status | Notes |
|---|---|---|---|---|
| — | Independent economy simulation output | `economy-sim.txt` | captured | Actual discrete outcomes: Active 11:45, Balanced 13:00, Passive 22:00; Invariants 100% PASSED, Target Agreement: 25/33 matched |
| 1 | Tier 2 unlock state | `10-tier2-unlock.jpg` | captured | Desktop mode (1510x642), 5/7 steps green, Desk 2 unlocked |
| 2 | Second workstation purchased, before hire | `20-desk2-before-hire.jpg` | captured | Desktop mode (1510x642), 6/7 steps green, Trainee 2 unlocked |
| 3 | Both trainees seated and working | `30-both-trainees.jpg` | captured | World view: Trainee 1 & 2 at desks, +3.0/s HUD |
| 4 | Full upgraded bedroom | `40-full-studio-room.jpg` | captured | Wide angle: PCRumah, OldCRT, Desk 1, Desk 2, both trainees |
| 5 | Workers page showing 2/2 staff | `50-workers-2of2.jpg` | captured | Desktop mode (1510x642), 7/7 steps green, 2/2 staff, +3.0 Cuan/s |
| 6 | Confirmed 3.0 Cuan/s rate | `60-rate-3-point-0.jpg` | captured | Desktop mode (1510x642), confirmed +3.0 Cuan/s rate |
| 7 | Pending vs spendable income | `70-pending-vs-spendable.jpg` | captured | Desktop mode (1510x642), pending unbanked vs spendable balance |
| 8 | Home Studio chapter complete | `80-chapter-complete.jpg` | captured | Desktop mode (1510x642), STUDIO RUMAHAN · HOME STUDIO COMPLETE |
| 9 | Mobile portrait Workers UI (Top) | `90-mobile-portrait.jpg` | captured | Narrow portrait viewport (520x940, mobileNav active), showing Home Studio Complete + 2/2 staff + rate |
| 9b| Mobile portrait Workers UI (Scrolled)| `91-mobile-workers.jpg` | captured | Narrow portrait viewport (520x940), scrolled to display Desk 2 and Trainee cards on duty |
| 10 | Alternative camera angle, no clipping | `95-alt-camera.jpg` | captured | Reverse corner room view, no wall clipping |
| 11 | Rejoin session validation | `97-rejoin-fresh-session.jpg` | captured | Fresh local Studio session, ephemeral store reset as expected offline |
| 12 | Part count visual context | `99-part-count-context.jpg` | captured | Live Studio scene context during part count audit |
| 13 | Standalone BasePart count proof | `part-count.txt` | captured | Live count: 287 base parts (budget ≤350), 63 parts margin (82.0% utilization) |

## Studio Regression Suite

- **Summary File**: `regression-final.txt`
- **Raw Console**: `docs/logs/studio_regression_console.log` (33,841 characters untruncated)
- **Verified Run ID**: `ec465cb7-cc1d-4543-ab49-705966761649`
- **Suites**: 20/20 passed
- **Test Metrics**:
  - 682 source-defined test cases
  - 747 runtime test executions (0 failed, 0 skipped)
  - ~3,139 static assertion calls
- **BS-13 Suite**: `BS13HomeStudio.spec.luau` — 44/44 passed
- **UI Regression Suite**: `AppClientIntegration.spec.luau` — 11/11 passed (including HUD tier canonical names & equipment hints)

## Live Gameplay Journey Metrics

Recorded in `journey-evidence.json`:
- **World Mounts**: `WorkerDesk1: 1`, `WorkerDesk2: 1`, `Trainee1: 1`, `Trainee2: 1`, `PCRumah: 1`
- **Part Count**: 287 parts live (budget ceiling: 350, margin: 63 parts, 82.0% utilization)
- **30s Bank Yield**: +90 Cuan durable bank confirmed (2 workers × 1.5 Cuan/s × 30s)
- **Economic Invariants**:
  - First hire payback: 5:33 (500 Cuan / 1.5 Cuan/s)
  - Bundle 1 payback: 7:33 (680 Cuan / 1.5 Cuan/s)
  - Bundle 2 payback: 11:07 (1000 Cuan / 1.5 Cuan/s)
  - Accrual bounded to ≤ 30s disconnect loss

## Four-Tier Persistence Classification

1. **Tier 1 — Unit / Spec Isolation**:
   - In-memory mock store in Luau specs (`tests/Specs/*`, 20 suites, 747 tests passed).
2. **Tier 2 — Local Studio Dev Fallback**:
   - `RunService:IsStudio()` branch in `ProfileStore.luau` activates ephemeral in-memory dev store when cloud DataStore handle is unreachable offline.
   - Resets across Play Solo restarts as expected.
   - Gate G2 is strictly classified as **BLOCKED** in local offline Studio.
3. **Tier 3 — Dedicated Dev Universe Cloud DataStore**:
   - Dedicated development universe live DataStore (Universe `10774181892`, Place `100558697471228`).
   - Verified in BS-10 across scenarios G2-01 through G2-08 with real cloud `DataStoreService`.
4. **Tier 4 — Production Cloud DataStore**:
   - Production universe runtime; real `DataStoreService` mandatory, dev fallback strictly forbidden.

## Frozen Economic & Architectural Constants

- **Desk 2 Price**: 250 Cuan (Prerequisites: PC Rumah, Tier 2, Desk 1 + Trainee 1)
- **Trainee 2 Price**: 750 Cuan (Prerequisites: Desk 2, Tier 2, Trainee 1)
- **Two-Worker Yield**: 3.0 Cuan/s (2 × 1.5 Cuan/s, banks 90 Cuan per 30s connected window)
- **Tier 2 Unlock**: 1,600 Lifetime Cuan + 3 Mission Claims
- **BasePart Budget**: ≤350 BaseParts (Live count: 287 BaseParts)
