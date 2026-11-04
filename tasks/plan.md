# BS-14 Implementation Plan — Closed Beta Candidate Gate (G5)

## Overview
Execute BS-14 Closed Beta Candidate Gate on baseline commit `27213d4` (merged master).
Verify the exact content-complete M1 candidate for limited closed beta across four core pillars:
1. Cloud DataStore & Write-Pressure Validation (Tier 3 dev universe / Tier 2 fallback resilience, lease locking, rollback reader).
2. Real Mobile & Low-End Profiling (360x640, 390x844, 768x1024, 1280x720; >=44x44 targets, 287 BaseParts, idle memory/frame stability).
3. Unguided Playtest Verification (uncoached fresh journey through 7 chapter steps, second session re-entry, progression cues).
4. Security & Protocol Regression (full 20-suite regression, forged payload rejection, distance enforcement, session expiry, client-server boundary audit).

## Key Architectural Invariants & Constraints
- Candidate commit baseline: `27213d4` on branch `agent/BS-14-closed-beta-candidate-gate`.
- Zero unreviewed production code changes; only evidenced bug fixes if defect detected.
- Agent 2 worktree (`C:/Users/cubeb/orca/workspaces/Buzzer Simulator Roblox/Agent-2`) remains isolated on `agent/M2-city-world-blueprint` with zero production impact.
- Budget ceilings: BaseParts <= 350 (live: 287), UI touch targets >= 44x44, frame rate >= 30 FPS.
- Persistence classification: Tier 1 (spec mocks), Tier 2 (offline Studio fallback), Tier 3 (dev universe cloud DataStore), Tier 4 (production).

## Task Breakdown

### Phase 1: Security & Protocol Regression Audit
- [x] Task 1.1: Verify full 20-suite Luau regression test baseline (all 682 specs / 747 tests pass).
- [x] Task 1.2: Run dedicated security penetration probe script in Studio:
      - Client payload forgery (negative/NaN Cuan, invalid slot, unknown template).
      - Server prompt distance boundary enforcement (>12 studs rejected).
      - Cross-mode double publish and rate-limit backpressure.
      - Session expiry enforcement (600s idle timeout lock).
- [x] Task 1.3: Document security regression findings in `docs/evidence/bs14/security-regression.txt`.

### Phase 2: Cloud DataStore & Write-Pressure Validation
- [x] Task 2.1: Audit DataStore schema compatibility and rollback reader:
      - Test schema v1 deserialization of profiles with missing/extra fields.
      - Ensure forward/backward compatibility without data loss.
- [x] Task 2.2: Evaluate Cloud DataStore connectivity (Tier 3 dev universe `10774181892` vs Tier 2 offline Studio dev fallback).
- [x] Task 2.3: Execute write-pressure simulation script:
      - Single-key write pacing (<= 6 writes/min baseline, burst handling).
      - 30s worker bank interval synchronization without write starvation.
- [x] Task 2.4: Document persistence and write-pressure evidence in `docs/evidence/bs14/datastore-pressure.txt`.

### Phase 3: Real Mobile & Low-End Profiling
- [x] Task 3.1: Multi-viewport audit across devices:
      - Mobile Portrait (360x640, 390x844).
      - Mobile Landscape (640x360).
      - Tablet (768x1024).
      - Desktop (1280x720, 1920x1080).
- [x] Task 3.2: Measure touch targets and UI reachability:
      - Confirm all actionable buttons (Create, Claim, Buy, Tab navigation, Close) >= 44x44 px.
      - Validate safe area margins and mobile navigation bar visibility.
- [x] Task 3.3: Measure rendering and memory metrics:
      - BasePart count verification (287 / 350 parts).
      - Extended connected idle run (script execution time, memory leak check).
- [x] Task 3.4: Capture photographic evidence for `docs/evidence/bs14/`.

### Phase 4: Unguided Playtest & Player Journey Evaluation
- [x] Task 4.1: Run automated unguided player journey from fresh account:
      - Discovery of OldCRT prompt and BuzzerOS.
      - First organic publish (`organic_snack`) and payout.
      - Acceptance and completion of Food Stall mission (`meal_time`).
      - Fast phone purchase and yield recognition.
      - PC Rumah purchase and terminal swap.
      - Desk 1 + Trainee 1 hire; Desk 2 + Trainee 2 hire.
      - Home Studio chapter completion.
- [x] Task 4.2: Second session re-entry check:
      - Clean disconnect and reconnect state validation.
      - HUD clarity audit (canonical names and contextual hints).
- [x] Task 4.3: Log unguided playtest timeline and metrics in `docs/evidence/bs14/playtest-journey.json`.

### Phase 5: Closed-Beta Candidate Gate Decision (Go / No-Go)
- [x] Task 5.1: Compile comprehensive Go/No-Go release readiness matrix in `docs/evidence/bs14/RELEASE-CANDIDATE-BS14.md`.
- [x] Task 5.2: Rank unresolved risks and operational mitigations.
- [x] Task 5.3: Verify candidate build reproducibility and deliver final report to Director.
