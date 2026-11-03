# BS-13 Implementation Plan — Second Workstation & Home Studio

## Overview
Activate Tier 2 ("Studio Rumahan"), Desk 2 (250), Trainee 2 (750), two-worker 3.0 Cuan/s
passive income, second world workstation + cosmetic trainee, Workers UI slot-2 progression
+ Home Studio chapter goal, an independent economy simulator, and a dedicated BS-13 test
suite. Reuse all BS-12 systems; no per-worker loops, no schema change, no new prefab room.

## Key facts from recon
- `WorldService.SyncWorkers` already loops `for slot = 1, 2` with dynamic prefab names
  (`WorkerDesk{slot}` / `Trainee{slot}`); only `PLACEMENT_CONFIG` entries + prefab files
  are missing.
- `EconomyService.buyDesk` lacks the docs/04 "Trainee 1 must be hired before Desk 2" gate.
- `Catalog.M1Shipped` (tier/desk/worker = 1/1/1) must be superseded by a BS-13 shipped
  table (2/2/2); `Catalog.Shipped` repoints. `MissionService` tier gate: only missions
  with minTier<=2 exist and brand_remix (minTier 1) already shipped — safe.
- Client `WorkerAnimationController` matches only folder "Trainee1"; client prefabs come
  from `ReplicatedStorage.WorkerPrefabs` (currently only Trainee1 mapped).
- `ClientState:BeginMutation` BuyDesk lane needs the same Trainee-1 gate for slot 2.
- Worker income is count-based (`1.5 * #workers`) — two-worker rate falls out automatically;
  mixed-rate intervals covered by existing `tickAtRate` + `_pendingAccrual` segments.
- BS-12 tests `Shipped slot caps reject Tier 2 eligible...` and `Desk 2 is locked in BS-12...`
  encode the old shipped config; update to new shipped truth (keep enforcement coverage).
- Part budget: server 239 + Desk2 29 = 268; client 268 + Trainee1 20 + Trainee2 20 = 308 <= 350.

## Task list (write-scope separated)
- [x] Phase 0 preflight (branch `agent/BS-13-second-worker-and-scale` from b1e8800)
- [x] T1 Catalog H2Shipped (2/2/2) + Comments  [me]
- [x] T2 EconomyService buyDesk Trainee-1 gate  [me]
- [x] T3 ClientState BuyDesk Trainee-1 gate  [me]
- [x] T4 Prefabs: WorkerDesk2 + Trainee2 in gen_world_prefabs.py, regen rbxmx, project mappings  [me]
- [x] T5 WorldService PLACEMENT_CONFIG slot 2  [me]
- [x] T6 WorkerAnimationController multi-slot + phase offset; App.client prefab folder  [me]
- [x] T7 Workers UI: desk2/trainee2 cards, chapter tracker, completion state  [me]
- [x] T8 tools/economy_sim.py independent engine  [fixer lane B — verified, exit 0, DIFF traces]
- [x] T9 BS13HomeStudio.spec.luau (44 test() blocks) + BS12 spec shipped-config updates  [me]
- [x] T10 check_all_suites += BS13HomeStudio; ASSET-MANIFEST update; docs/04 DIFF note  [me]
- [x] T11 diff review triangle (running) → Rojo builds ✓ → Studio 20-suite run + gameplay + evidence bs13/  [me + user opens build]
- [x] T12 diff review, commit, push, PR (NO merge)  [me]

## Checkpoints
- After T1-T7: build passes, old suites still green (except known BS-12 shipped-config tests, updated in T9 same pass).
- After T9-T10: local static test count grows; full Studio run green.
- After T11: evidence complete; T12 delivery.

## Risks
- Shipped-cap change ripples into V0/M1 tests using maxShipped* — handle in T9, not piecemeal.
- Sim targets 18:20/22:20 are doc estimates; independent engine may land 18:00/22:00 — record
  proposed docs/04 correction with event-trace evidence; do NOT silently edit targets.
- Studio availability: two live instances; BS-13 needs a fresh rbxlx load — use last-known flow.
