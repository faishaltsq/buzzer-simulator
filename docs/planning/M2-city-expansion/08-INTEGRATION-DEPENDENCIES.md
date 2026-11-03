# 08 — Integration Dependencies & Agent Coordination

> **Covers**: coordination boundary with Agent 1 (BS-13), frozen contracts,
> future file-ownership matrix, and sequencing.
> **Status**: Planning. This file is advisory for implementation milestones.

---

## 1. Coordination statement for Agent 1

Agent 2 (this branch) **does not touch**:

- `src/` (any file)
- `assets/world/` (any file)
- `assets/ui/` (any file)
- `tools/gen_world_prefabs.py`
- `tools/economy_sim.py`
- `src/shared/Catalog.luau`
- `src/server/EconomyService.luau`
- `src/server/WorldService.luau`
- `src/server/MissionService.luau`
- `tests/` (any file)
- `default.project.json`, `test.project.json`

Agent 1 can continue BS-13 without merge risk from this branch. The only files
added here are Markdown under `docs/planning/M2-city-expansion/`.

This branch **opens a documentation-only PR** and **does not merge
automatically**.

---

## 2. Frozen contracts M2 depends on (cannot change)

| Contract | Source | M2 dependency |
|---|---|---|
| Bedroom dimensions 24×24 | `docs/design/03` | house shell geometry |
| 12 bedroom anchor names/pivots | `docs/design/03`, `WorldService.REQUIRED_ANCHORS` | door threshold, shell wrap |
| `Door` anchor `(-6, 3.65, 11.6)`, size `3.7 × 7.3 × 0.18` | `Bedroom.rbxmx` | exterior doorway alignment |
| `Spawn` anchor `(0, 0.6, 6)` | `Bedroom.rbxmx` | indoor respawn / return destination |
| `DashboardPromptAnchor` prompt model | `WorldService` | publishing stays indoors |
| Prompt distance 10 / validation 12 | `WorldService` | city prompt constants |
| Room cloned per player at origin | `WorldService.Spawn` | city must be static and offset |
| One player per server | ADR-01 | no player-vs-player city collision |
| M1 catalog prices/yields/tiers | `Catalog.luau` | shops surface, never redefine |
| Tier 2 = `lifetimeRequired 1600`, `claimsRequired 3` | `Catalog.Tiers` | city unlock gate |
| `completedMissions`, `ownedDesks`, `workers`, `tier` fields | profile v1 | city content gates |
| Existing `Upgrades`/`Missions`/`Workers` surfaces | `src/client/ui` | shop routing |
| No external assets, palette tokens | `docs/DESIGN.md`, `docs/design/02` | all city art |

**Any change to the left column requires a blueprint amendment and a director
decision, not a silent edit.**

---

## 3. What M2 implementation will eventually touch

Listed so ownership can be serialized. Nothing here happens in this PR.

| File / area | M2 phase | Change | Risk |
|---|---|---|---|
| `assets/world/city/*.rbxmx` (new dir) | M2-A | new prefabs | Low (new files) |
| `tools/gen_city_prefabs.py` (new file) | M2-A | new generator | Low (new file) |
| `default.project.json`, `test.project.json` | M2-A | map city prefabs into `ServerStorage.WorldPrefabs` | **Serialize** — shared file |
| `src/server/CityService.luau` (new) | M2-A | static clone, anchors, prompts, unlock gate | Medium |
| `src/server/Bootstrap.server.luau` | M2-A | wire `CityService` | **Serialize** — shared |
| `src/server/NetRouter.luau` | M2-A/B | city prompt/state messages | **Serialize** — high risk |
| `src/server/ProfileStore.luau` | M2-C | schema v2 `cityUnlocks` | **Critical** |
| `src/client/ui/Hud.luau` | M2-B | zone label, return chip | Medium |
| `src/client/ui/Desktop.luau` | M2-B | shop routing into existing tabs | Medium |
| `src/client/CityController.luau` (new) | M2-B | zone detection, fade, map card | Low |
| `src/client/ui/Decor.luau` (new) | M2-B | cosmetic panel + placement preview | Medium |
| `src/shared/CityCatalog.luau` (new) | M2-B | cosmetic-only item table | Medium (director approval) |
| `tests/Specs/CityService.spec.luau` (new) | M2-A | new specs only | Low |

**Never touched:** `Catalog.luau`, `EconomyService.luau`, `MissionService.luau`,
`ScoringCatalog.luau`, `Rules.luau`, `assets/world/Bedroom.rbxmx`.

---

## 4. Dependency on BS-13 (Agent 1)

| BS-13 outcome | M2 impact |
|---|---|
| Tier 2 remains the chapter end | unlock gate unchanged |
| `workers` stores two entries with `slotIndex` 1/2 | gate `#workers >= 2` unchanged |
| `ownedDesks` stores `{1, 2}` | gate `#ownedDesks >= 2` unchanged |
| Any change to worker completion semantics | update `cityUnlocked` derivation; no schema change |
| Any change to `Catalog.Tiers` values | **re-derive the gate from the new values; do not hard-code 2** |
| BS-13 adds a new persisted field | check whether the gate should use it; avoid duplicate state |

**Rule:** the gate is derived from *existing* fields, not new ones. If BS-13
introduces a chapter-complete flag, prefer that flag over a two-field
heuristic — but that is a director decision.

---

## 5. Dependency on BS-14 (closed-beta gate)

- M2 content must **not** appear in the closed-beta candidate build.
- The M2 docs may be merged before BS-14, but no city prefab or service ships
  in the beta branch.
- The BS-14 Go/No-Go evidence should include one qualitative probe:
  *"After the second trainee is hired, do players look for more world?"*
  If no player asks, M2 sequencing should be reconsidered.

---

## 6. Sequencing rules for merge

1. This docs-only PR may merge any time after review; it changes no behavior.
2. M2-A implementation waits for BS-14 Go.
3. Shared-file edits (`default.project.json`, `Bootstrap.server.luau`,
   `NetRouter.luau`) are serialized: one owner at a time, exactly as the M1
   policy already requires.
4. City prefabs are added to `ServerStorage.WorldPrefabs` under distinct names;
   never replace `Bedroom`/`OldCRT`/`PhoneCheap`/`PhoneFast`/`PCRumah`.
5. `CityService` clones the city **once per server**, never per player.
6. No new remote event without a NetRouter review; prefer reusing existing
   state/snapshot flows for shop routing.
7. Existing tests must not be edited to accommodate M2. New behavior gets new
   specs.

---

## 7. Data & security dependencies

| Concern | Requirement |
|---|---|
| Unlock gate | Computed **server-side** from the saved profile; never trusted from the client |
| Prompt identity | Server-created prompt on a named anchor; client cannot fabricate |
| Distance check | Server validates ≤ 12 studs from the anchor (existing constant) |
| Shop purchase | Existing server-confirmed path; city UI cannot grant items |
| Cosmetic ownership | Server-confirmed; client previews only |
| Cosmetic effect | Provably none: `effect = "none"` in the cosmetic table, asserted by a spec |
| District unlock (M2-C) | Server-side flag; forged client flags rejected |
| City state | Static geometry; no per-player city save |
| Player location | Not persisted; rejoin spawns indoors |

---

## 8. Open questions for the director

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | Does the city unlock at tier 2 + two workers, or at tier 2 alone? | tier 2 + two workers (chapter break) |
| Q2 | Is a new `cityUnlocks` schema field approved for M2-C? | No; M2-C blocked |
| Q3 | Is a cosmetic-only catalog approved for M2-B? | No; Rumah Rapi deferred to M2-C |
| Q4 | Does the city ship before or after closed beta? | After BS-14 Go |
| Q5 | Are Indonesian-language zone names final? | Yes for MVP; copy review later |
| Q6 | Is a skyline backdrop allowed to be `Persistent`? | Yes (8 parts) |
| Q7 | Do we accept one open-front shop model (no interiors)? | Yes (camera/mobile win) |
| Q8 | Should the locked door appear before tier 2? | Yes, with honest copy |

---

## 9. Hand-off package for the M2-A implementer

1. This folder (`docs/planning/M2-city-expansion/`).
2. The coordinate table (`02`, §3) — treat as a contract.
3. The anchor table (`02`, §7) — treat as a contract.
4. Zone budgets (`05`, §3.2) — treat as a test budget.
5. The blockout acceptance list (`07`, §3).
6. Explicit instruction: **do not edit `Catalog.luau`, economy services, or
   existing tests.**
