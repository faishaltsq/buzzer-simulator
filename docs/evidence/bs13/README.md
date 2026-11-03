# BS-13 Evidence — Second Workstation & Home Studio

Genuine Roblox Studio artifacts only. No fabricated or generated substitutes.

| # | Requirement | File | Status | Notes |
|---|---|---|---|---|
| — | Independent economy simulation output | `economy-sim.txt` | captured | Active 11:21, Balanced 13:56, Passive 20:34; sensitivity + event trace |
| 1 | Tier 2 unlock state | `10-tier2-unlock.png` | captured | Desktop mode (1510x642), 5/7 steps green, Desk 2 unlocked |
| 2 | Second workstation purchased, before hire | `20-desk2-before-hire.png` | captured | Desktop mode (1510x642), 6/7 steps green, Trainee 2 unlocked |
| 3 | Both trainees seated and working | `30-both-trainees.png` | captured | World view: Trainee 1 & 2 at desks, +3.0/s HUD |
| 4 | Full upgraded bedroom | `40-full-studio-room.png` | captured | Wide angle: PCRumah, OldCRT, Desk 1, Desk 2, both trainees |
| 5 | Workers page showing 2/2 staff | `50-workers-2of2.png` | captured | Desktop mode (1510x642), 7/7 steps green, 2/2 staff, +3.0 Cuan/s |
| 6 | Confirmed 3.0 Cuan/s rate | `60-rate-3-point-0.png` | captured | Desktop mode (1510x642), confirmed +3.0 Cuan/s rate |
| 7 | Pending vs spendable income | `70-pending-vs-spendable.png` | captured | Desktop mode (1510x642), pending unbanked vs spendable balance |
| 8 | Home Studio chapter complete | `80-chapter-complete.png` | captured | Desktop mode (1510x642), STUDIO RUMAHAN · HOME STUDIO COMPLETE |
| 9 | Mobile portrait UI | `90-mobile-portrait.png` | captured | Narrow portrait viewport (520x940), responsive compact mode |
| 10 | Alternative camera angle, no clipping | `95-alt-camera.png` | captured | Reverse corner room view, no wall clipping |
| 11 | Part count validation | `99-part-count-context.png` | captured | Live count: 285 base parts (budget ≤350) |

## Studio Regression Suite

- **File**: `regression-final.txt`
- **Suites**: 20/20 passed
- **Tests**: 745 runtime tests passed, 0 failed, 0 skipped
- **BS-13 Suite**: `BS13HomeStudio.spec.luau` — 44/44 passed

## Live Gameplay Journey Metrics

Recorded in `journey-evidence.json`:
- **World Mounts**: `WorkerDesk1: 1`, `WorkerDesk2: 1`, `Trainee1: 1`, `Trainee2: 1`, `PCRumah: 1`
- **Part Count**: 285 parts (budget ceiling: 350)
- **30s Bank Yield**: +90 Cuan durable bank confirmed (2 workers × 1.5 Cuan/s × 30s)
- **Rejoin Gate**: Dev-store offline fallback verified (G2 blocked expected offline)
