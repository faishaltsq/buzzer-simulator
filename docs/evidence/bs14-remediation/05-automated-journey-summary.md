# BS-14 RC-1 — Automated Connected Gameplay Journey

**Candidate:** `fa55baa` + `agent/BS-14-rc1-evidence-remediation`
**Run:** 2026-11-04, Roblox Studio `version-7062aec9dbe74b14`, Play Solo, local `build/BuzzerSimulator.rbxlx`
**Driver:** `tools/agent/bs14_rc_idle.py` (ladder phase), actions sent through the shipped client path `StudioClientBridge → NetRouter → SessionService`
**Artifact:** `02-idle-20min-raw.log` (same session continues into the idle gate)

**Correct label: automated connected gameplay journey.** This is not an unguided human playtest — no human input is involved anywhere, and the mission/template sequence is chosen by the script. The previous release document titled the same class of run "Unguided Player Journey" (`RELEASE-CANDIDATE-BS14.md:134`), which overstated what it proves.

---

## 1. Measured timeline (fresh session, real wall clock)

| UTC | Milestone | Confirmed value from the server-built snapshot |
| :-- | :-- | :-- |
| 06:55:4x | Play Solo started, profile initialised | balance 0, lifetime 0, tier 0 |
| 06:56:0x | Dashboard opened via the real proximity prompt | `invoked-true:true`, desktop visible |
| 06:56:37 | Mission `food_stall_launch` claimed | balance 95, lifetime 95, claims 1 |
| 06:57:04 | Mission `fictional_gadget` claimed | balance 210, lifetime 210, claims 2 |
| 06:57:32 | Mission `neon_market` claimed → **tier 1** | balance 345, lifetime 345, claims 3 |
| 06:58:00 | Mission `brand_remix` claimed | balance 520, lifetime 520, claims 4 |
| 06:58:00 | `phone_fast` purchased (catalog order 2) | deviceId `phone_fast` |
| 06:58:01 | `pc_rumah` purchased (catalog order 3) | deviceId `pc_rumah` |
| 06:58:01 | Desk 1 purchased | ownedDesks `[1]` |
| 07:03:32 | Trainee 1 hired (slot 1) | workers length 1, rate 1.5 Cuan/s |
| 07:08:53 | **Tier 2 reached** (`Studio Rumahan`) | lifetime 1955, tier 2 |
| 07:08:53 | Desk 2 purchased | ownedDesks `[1, 2]` |
| 07:08:54 | Trainee 2 hired (slot 2) | workers length 2, rate **3.0 Cuan/s** |
| 07:08:54 | Idle baseline captured | balance 1005, lifetime 1955, revision 103 |

Ladder wall time: **~15 minutes** from session start to a confirmed 2-desk / 2-worker profile.

---

## 2. What the journey proves

- The shipped client admission gate, remote contract and server mutation lane work end to end from a zero state to chapter completion.
- Device progression is **order-enforced**: `phone_fast` must precede `pc_rumah` (`ClientState.luau:250-274`, "only the exact next device in catalog order"). An attempt to buy `pc_rumah` from `phone_cheap` is refused with `NOT_READY` — verified live during this run's first (incorrect) ordering, then corrected in the harness.
- Desk 2 is gated on owning `pc_rumah`, tier ≥ slot, and desk 1 ownership; worker slot 2 requires desk 2.
- Two workers produce exactly **3.0 Cuan/s** as a derived projection (`1.5 × 2`), computed from the profile, not stored.
- Every purchase settled through the durable lane with `saveStatus: healthy` and no retry storm.

## 3. What it does not prove

| Not proven | Why |
| :-- | :-- |
| Human discoverability of the UI | no human involved |
| Real player pacing/tedium | one scripted run on one host |
| Cloud persistence across servers | local Studio uses the ephemeral DEV_FALLBACK store |
| Real-device rendering and input | separate gate, BLOCKED |
| Rejoin across sessions | ephemeral store resets between Play Solo sessions, so rejoin persistence is proven only by `BS10Recovery.spec` at the service layer |

## 4. Defect found in the previous artifact (not the product)

`docs/evidence/bs14/playtest-journey.json` was produced by the **resume** path of `run_unguided_playtest.py`, whose milestones 0–10 are hardcoded dictionaries containing literal timestamps and literal payout strings (`:176-187`), e.g. `"time": "16:16:55 UTC"` and `"detail": "... balance: 110 Cuan"`. Only the live path (`:155`) stamps real time.

Consequence: the 17-milestone timeline in the previous release report was **partly reconstructed from constants**. It is not a measurement of the run it claims to describe. This run replaces it with values read out of the snapshot at the moment each milestone occurred; timestamps here come from the harness clock, and the balances come from the server.

The old artifact is preserved in Git history and should be read as "automated journey, timeline partly constant" rather than as a log.
