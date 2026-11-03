# M2 — City Expansion Blueprint

> **Document status**: Planning only. Not implementation authority.
> **Target**: Buzzer Simulator M2 ("Kota") — the chapter after the M1 home studio.
> **Branch**: `agent/M2-city-world-blueprint`
> **Baseline**: `origin/master` @ `b1e8800` (BS-12 merged; BS-13 in progress by Agent 1).
> **Owner**: Agent 2 (world expansion planning). Production owner: director.

---

## 1. What this package is

A production-ready **design and production blueprint** for expanding Buzzer Simulator
beyond the frozen 24×24 bedroom into a compact stylized city hub.

It contains:

| File | Contents |
|---|---|
| [`01-VISION-AND-PROGRESSION.md`](01-VISION-AND-PROGRESSION.md) | World vision, indoor→indoor+outdoor loop, progression gates |
| [`02-WORLD-STRUCTURE.md`](02-WORLD-STRUCTURE.md) | Map structure, coordinate contract, travel, ASCII diagrams |
| [`03-ZONE-SPECIFICATIONS.md`](03-ZONE-SPECIFICATIONS.md) | Seven zone specs: purpose, interactions, visuals, assets |
| [`04-EVENTS-AND-SHOPS.md`](04-EVENTS-AND-SHOPS.md) | Five event types, four shop types, economy boundaries |
| [`05-TECHNICAL-PRODUCTION-AND-PERFORMANCE.md`](05-TECHNICAL-PRODUCTION-AND-PERFORMANCE.md) | Prefab/modularity, streaming, anchors, M2-A/B/C scope, budgets |
| [`06-UI-UX-INTEGRATION.md`](06-UI-UX-INTEGRATION.md) | HUD, prompts, minimap decision, return-home affordances |
| [`07-ROADMAP-RISKS-ASSETS.md`](07-ROADMAP-RISKS-ASSETS.md) | Milestone roadmap, MVP order, risk register, asset priority list |
| [`08-INTEGRATION-DEPENDENCIES.md`](08-INTEGRATION-DEPENDENCIES.md) | Frozen contracts, Agent 1 coordination, file-ownership matrix |
| [`09-FUTURE-EXPANSION-HOOKS.md`](09-FUTURE-EXPANSION-HOOKS.md) | Office/influencer/agency/transit/rooftop/festival hooks |
| [`10-M2-A1-TASK-BREAKDOWN.md`](10-M2-A1-TASK-BREAKDOWN.md) | Executable task list for the recommended next milestone |

It contains **no code, no prefab binaries, and no economy constants**.

---

## 2. Executive summary

The city is a **short walk outside the door**, not a second game.

- **Bedroom stays the command center.** All publishing, mission claiming, and
  purchases still resolve through the existing BuzzerOS surfaces. The city
  never gets a second composer or a second wallet.
- **City work is "go get, come back."** The player leaves to collect campaign
  briefs, read the daily board, buy visible cosmetics, and stamp landmarks,
  then returns home to publish and bank. This preserves the M1 loop and gives
  the exterior a reason to exist.
- **Compact by contract.** 224 × 198 studs of walkable city, one 16-stud
  building module, longest meaningful walk ≈ 10 seconds. No MMO scale, no
  vehicles in MVP, no seamless open world.
- **Zero new economy numbers in this blueprint.** Shops surface the *existing*
  `Catalog` entries. Event rewards reuse existing mission rewards or grant
  cosmetics only. Any new price, tier, or bonus is a separate director decision.
- **Zero schema changes required for M2-A/B entry and content gating.** The
  city gate is derived from fields that already exist (`tier`, `workers`,
  `completedMissions`). Only future districts need a new flag table.

**Recommended next implementation milestone:** `M2-A1 — City Coordinate
Contract + Blockout` (see `07`, §3). It is a blockout-only spike that locks the
coordinate contract, the door threshold, and the streaming behavior before any
shop or UI work is commissioned.

---

## 3. Hard boundaries (inherited)

From `docs/01`, `docs/03`, `docs/06`, `docs/DESIGN.md`, and this task:

1. The 12 bedroom anchors in `Bedroom.rbxmx` are **frozen**. Their names,
   pivots, sizes, and parenting never change.
2. `src/`, `assets/world/`, `tools/gen_world_prefabs.py`, `Catalog.luau`,
   economy services, and existing tests are **not modified by this planning
   work**.
3. No new economy prices, progression tiers, or item bonuses without director
   approval.
4. No MMO, multiplayer, live social API, offline earnings, or free-text posts.
5. One player per server remains the product assumption (ADR-01). The city is
   a single static world; the bedroom remains a per-player clone at the origin.
6. All art is Roblox-native `BasePart` primitives + built-in materials. No
   external meshes, textures, audio IDs, or Toolbox assets.

---

## 4. Approval gates

| Gate | Owner | Blocks |
|---|---|---|
| G1 — Coordinate + anchor contract accepted | Director + technical art | Any city prefab authoring |
| G2 — M2-A blockout visually signed off in Studio | Director | M2-A merge |
| G3 — Shop/event copy + economy boundary accepted | Director | M2-B shop content |
| G4 — Schema v2 decision (city flags) | Director | M2-C districts, future gates |
| G5 — Real-device performance evidence | Director | Any public city release |

Nothing in this package authorizes a merge into `master` beyond the documents
themselves.

---

## 5. Relationship to Agent 1 / BS-13

Agent 1 owns BS-13 (second workstation, home-studio goal) and the M1 economy
freeze. This blueprint:

- does not edit `Catalog.luau`, `EconomyService.luau`, or tests;
- assumes **no change** to the shipped M1 catalog;
- flags every future implementation touchpoint in
  [`08-INTEGRATION-DEPENDENCIES.md`](08-INTEGRATION-DEPENDENCIES.md);
- recommends M2 implementation begins only after the BS-14 closed-beta gate
  produces a Go with measured M1 balances.
