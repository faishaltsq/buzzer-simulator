# 07 — Roadmap, Risks & Asset Priority

> **Covers**: deliverable 2 (milestone roadmap), 3 (MVP production order),
> 4 (risk list), 5 (best next milestone), optional asset priority list.
> **Status**: Planning. Estimates are ranges for one director coordinating
> agents, not calendar promises.

---

## 1. Milestone roadmap

```text
            ┌──────────────────────────────────────────────────────────┐
            │  BS-14 closed-beta Go  (Agent 1 + director)              │
            └───────────────────────────┬──────────────────────────────┘
                                        │
   ┌────────────────────────────────────▼─────────────────────────────┐
   │ M2-A  EXTERIOR FOUNDATION                                        │
   │  A1 coordinate + anchor freeze + blockout   (1–2 dev-days)       │
   │  A2 house shell + street                    (1–2 dev-days)       │
   │  A3 town center + boards + gate + backdrop  (2–3 dev-days)       │
   │  A4 CityService clone + door prompts + gate (1–2 dev-days)       │
   │  A5 visual/perf sign-off                    (0.5–1 dev-day)      │
   └────────────────────────────────────┬─────────────────────────────┘
                                        │
   ┌────────────────────────────────────▼─────────────────────────────┐
   │ M2-B  FUNCTIONAL CITY HUB                                        │
   │  B1 ElectroMart + Upgrade routing           (2–3 dev-days)       │
   │  B2 Warung utility panel                    (1–2 dev-days)       │
   │  B3 daily brief + landmark stamps           (2 dev-days)         │
   │  B4 Rumah Rapi cosmetic catalog + panel     (3–4 dev-days)       │
   │  B5 zone labels + return chip + polish      (1–2 dev-days)       │
   └────────────────────────────────────┬─────────────────────────────┘
                                        │
   ┌────────────────────────────────────▼─────────────────────────────┐
   │ M2-C  EXPANDED DISTRICTS  (requires schema v2 + director)       │
   │  C1 cityUnlocks schema + reader + rollback  (2–3 dev-days)       │
   │  C2 pop-up + themed-week events             (3–4 dev-days)       │
   │  C3 cosmetics shop + try-on                 (3–4 dev-days)       │
   │  C4 transit + rooftop venue + district stub (3–5 dev-days)       │
   └──────────────────────────────────────────────────────────────────┘
```

| Milestone | Scope | Exit evidence |
|---|---|---|
| **M2-A** | Static city foundation, door loop, unlock gate | Walk-out/return video on phone + desktop; part count; FPS; director visual sign-off |
| **M2-B** | Shops, boards, daily brief, stamps, labels | Full loop observed; cosmetic survives rejoin; no double charge; mobile screenshots |
| **M2-C** | Districts, events, transit, cosmetics | Migration + rollback rehearsal; district gate unforgeable; re-profiled performance |

---

## 2. Suggested MVP production order

Do these in order. Do not parallelize across the art/contract boundary.

1. **Freeze the coordinate + anchor contract** (`02`) — this is the cheapest
   possible moment to prevent rework.
2. **Blockout** house shell + street + town center with grey parts only.
   Walk it on a phone. Confirm the door threshold, sightlines, and walk time.
3. **Sign off the blockout** (G2). No texture, no sign, no prop until this
   passes.
4. **Add the boards kiosk** and the existing mission surface routing. This is
   the first *functional* reason to leave.
5. **Add the door prompts + `cityUnlocked` gate** using existing profile
   fields. Prove no schema change is needed.
6. **Add streaming roots** and verify no pop at the door.
7. **Detail pass**: street props, plaza fountain/benches, signage, backdrop.
8. **ElectroMart** (existing Upgrades routing) — the cheapest "real shop".
9. **Warung** (free utility + map card + return shortcut).
10. **Daily brief + landmark stamps** — content reuse, no economy.
11. **Rumah Rapi** cosmetics — only after the director approves a cosmetic
    table and a placement path.
12. **Zone labels + return chip** — last, because they depend on final zone
    bounds.

Rationale: every step after 3 is independently revertible, and the loop becomes
playable at step 5 — before any shop exists.

---

## 3. Best next implementation milestone

### `M2-A1 — City Coordinate Contract + Blockout`

**Why this one:**

- It is the only step where a mistake forces a full city re-layout.
- It needs no economy decision, no schema change, and no new UI.
- It produces a screenshot that answers the hardest design question: *does the
  house read as a house from outside, and does the street read as a city?*
- It can run in parallel with M1 hardening without touching Agent 1's files.

**Scope**

| In | Out |
|---|---|
| `HouseExterior`, `StreetBlock`, `TownCenter` grey blockout | Textures, signs, props |
| `CityBackdrop` silhouette | Shop interiors |
| Door threshold geometry + stub prompts (no logic) | `CityService`, save changes, HUD changes |
| Coordinate table validated in Studio | Any economy or catalog edit |
| Phone + desktop screenshots | Public build |

**Acceptance**

1. Player can walk from the bedroom door to the fountain in ≤ 12 s.
2. From the stoop, the boards kiosk and fountain are visible.
3. From the desk, the window shows the backdrop, not the street.
4. No camera clipping at the door or in the plaza.
5. Blockout part count ≤ 450.
6. Existing bedroom tests still pass (nothing was touched).

**Rough effort:** 1–2 dev-days including Studio review.

---

## 4. Risk register

| ID | Risk | Severity | Likelihood | Early signal | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R1 | Door threshold misalignment (shell vs. frozen `Door`) | High | Medium | visible gap/step at the stoop | Freeze coordinates; blockout before art; single `HouseExterior` prefab | Tech art |
| R2 | Roof/parapet clips orbit camera | High | Medium | camera pushes into geometry at the desk | No interior ceiling; parapet ≤ 11.9; camera test in A1 | Tech art + director |
| R3 | Streaming pops the room or a zone at the door | High | Medium | half-built shop, missing walls | `Atomic` room/zones, `Persistent` backdrop, `RequestStreamAroundAsync` | Engineering |
| R4 | City becomes a second economy surface | Critical | Medium | shop holds its own price table | Prompt → existing UI only; no new constants; review gate G3 | Director |
| R5 | Cosmetic items accidentally affect stats | Critical | Low | yield/reveal changes after purchase | Cosmetic catalog schema with explicit `effect = none`; spec test | Engineering |
| R6 | Schema v2 migration corrupts profiles | Critical | Low (M2-C only) | old profile fails to load | Versioned reader + rollback rehearsal; defer to last milestone | Director + engineering |
| R7 | Scope creep into districts | High | High | "just one more shop" | Phase gates; M2-C requires director approval | Director |
| R8 | Mobile FPS below target | High | Medium | < 30 FPS at plaza | Per-zone budgets, ≤ 8 lights, ≤ 6 NPCs, real-phone profiling | Engineering |
| R9 | City feels decorative / boring | High | Medium | players leave once and never return | Boards + daily brief + stamps; anti-decorative checklist in `01` | Design |
| R10 | Walk feels like a chore | Medium | Medium | players use return shortcut constantly | Keep walk ≤ 12 s; put content on the path; never gate the door behind a long walk | Design |
| R11 | Art time exceeds solo capacity | Medium | High | one zone takes > 3 dev-days | Kit-of-parts reuse, silhouette-first, cut props not structure | Tech art |
| R12 | Prompt overlap at the board/fountain cluster | Medium | Low | two prompts stacked on mobile | One prompt per anchor; nearest-wins; 4-stud separation | Engineering |
| R13 | Ambient NPCs cost more than they add | Low | Medium | frame drops, weird pathing | Client-local, ≤ 6, waypoints only, no collision | Engineering |
| R14 | City distracts from M1 before the gate | Medium | Low | players ask "how do I get out?" constantly | Locked door with honest copy; HUD objective stays indoor-first | Design |
| R15 | Multiplayer assumption changes | High | Low | future shared servers | Document that the city is static and the room is per-player at origin; relocation would be a separate ADR | Director |
| R16 | Fourth wall broken by fake community numbers | Medium | Low | "1,204 players" copy | Author only local, verifiable state | Design |
| R17 | Seasonal art cost with no return | Medium | Medium | festival dressing > 3 dev-days | Fund festivals only after base city is live and measured | Director |
| R18 | Door teleport races with streaming/character load | Medium | Low | player falls through the street | Hold fade until zone is ready; validate ground with a short raycast | Engineering |

---

## 5. Asset priority list

Priority = **P0 must exist for the loop**, **P1 makes it a city**,
**P2 polish/horizon**.

| Priority | Asset | Phase | Parts | Notes |
|---|---|---|---|---|
| P0 | `HouseExterior` | M2-A | 90 | wraps the frozen room; no interior ceiling |
| P0 | `StreetBlock` | M2-A | 80 | corridor + 2 signposts |
| P0 | `CityProps` (kit) | M2-A | 60 | benches, lamps, bins, awnings |
| P0 | `CityBoards` | M2-A | 40 | mission + daily |
| P1 | `TownCenter` shell | M2-A | 140 | paving + fountain + lamps |
| P1 | `TownCenter` props | M2-B | 80 | benches, planters, banners |
| P1 | `CityBackdrop` | M2-A | 8 | window vista, fixes V-03 |
| P1 | `CityGate` | M2-A | 30 | locked teaser |
| P1 | `ShopRowElectronics` | M2-B | 120 | opens existing Upgrades |
| P1 | `ShopUtility` | M2-B | 50 | free map + return |
| P1 | `EventPlaza` permanent | M2-B | 160 | empty-lot fallback |
| P2 | `ShopFurniture` | M2-B | 100 | cosmetic-only |
| P2 | cosmetic room items ×10 | M2-B | 6–20 each | director-approved table |
| P2 | `EventPlaza_PopUp` | M2-C | 60 | event dressing |
| P2 | `ShopCosmetics` | M2-C | 90 | try-on |
| P2 | district shell | M2-C | 400 | Office District stub |
| P2 | transit stop interaction | M2-C | 10 | fast travel |
| P2 | rooftop venue | M2-C+ | 120 | theme-based |

**Not in any phase:** vehicles, enterable towers, elevators, NPC crowds with
dialogue, animated billboards, uploaded images, external meshes.

---

## 6. Definition of done (per milestone)

A milestone is done only when:

1. It runs on a real phone and desktop at ≥ 30 FPS.
2. The new content is reachable from the door without a guide.
3. No existing test regressed.
4. No new economy constant shipped without director approval.
5. The prefab has no scripts and no external assets.
6. A screenshot exists in `docs/evidence/` for the visual claim.
7. The blueprint is updated if any contract changed.
