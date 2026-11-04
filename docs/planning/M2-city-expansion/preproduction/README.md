# M2-A0 — City Visual Pre-Production Package

> **Status**: Pre-production only. **No game code, no prefab, no service, no test, no
> economy value is authored or modified by this package.**
> **Branch**: `agent/M2-A0-city-visual-preproduction`, cut from `master` @
> `fa55baa` (BS-14 merge, PR #9).
> **Parent blueprint**: `docs/planning/M2-city-expansion/` (01–10, merged in PR #8).
> **Owner**: Agent 2 (world art / level design / technical art). Production owner: director.
> **Every part count, distance and frame time in this folder is an estimate** until measured
> in Roblox Studio. The only exceptions are distances and angles, which are arithmetic from
> the frozen coordinates and are labelled as such.

---

## 1. What this package is

The approved blueprint (`01`–`10`) answers *what the city is for*. This package answers
*what the city looks like, how it is assembled, what it costs, and what the player sees
first* — specific enough that the M2-A1 blockout agent never has to interpret a coordinate.

It exists to prevent three specific failure modes:

1. **Generic architecture.** A grey city of identical BoxParts with signs on them.
2. **Expensive rework.** Discovering at art stage that the door does not align, the shop
   prompts are out of reach, or the skyline is not in the window.
3. **Budget surprise.** Discovering at visual sign-off that the dressed M2-A is 20 parts
   over its own ceiling.

All three are addressed with numbers, not adjectives. §3 lists what the review found.

---

## 2. Contents

| File | Contents | Read it if you are… |
|---|---|---|
| [`CITY-ART-DIRECTION.md`](CITY-ART-DIRECTION.md) | The visual bible: light, palette jobs, materials, the 6-part building grammar, variation rules, signage, storytelling props, the anti-list, bedroom continuity, 10 rejection criteria | building or reviewing any city art |
| [`WORLD-LAYOUT-AND-SIGHTLINES.md`](WORLD-LAYOUT-AND-SIGHTLINES.md) | How to read the board; the contract as a checklist; measured route table; S1–S7 sightlines with the camera-aperture audit; door section; camera behaviour; anchor register A1–A18 | laying anything out |
| [`ZONE-VISUAL-SPECS.md`](ZONE-VISUAL-SPECS.md) | Per-zone spec for Z0–Z7 + backdrop: style, palette, materials, silhouette, signage, lighting (L1–L8), furniture, interaction, camera, visibility, budget, P0/P1/P2 | building one zone |
| [`MODULAR-ASSET-KIT.md`](MODULAR-ASSET-KIT.md) | 19 asset families with module dimensions, pivots, naming, tokens, part cost, collision, streaming grouping, reuse; composition recipes; the P0/P1/P2 manifest; the generator authoring order | writing `gen_city_prefabs.py` |
| [`CITY-PERFORMANCE-BUDGET.md`](CITY-PERFORMANCE-BUDGET.md) | Reconciliation of 448/468/450/958/1,200; the three budgets (graybox / dressed / whole city); bottom-up estimate per prefab; light, transparency and `SurfaceGui` budgets; streaming finding; mobile visibility; measurement protocol | signing off a budget or a frame time |
| [`FIRST-EXIT-STORYBOARD.md`](FIRST-EXIT-STORYBOARD.md) | Ten shots with camera positions and in-frame / not-in-frame lists; the 90-second beat sheet; what the blockout can prove vs what needs logic; the evidence capture list | building the first-exit experience |
| [`M2-A1-IMPLEMENTATION-HANDOFF.md`](M2-A1-IMPLEMENTATION-HANDOFF.md) | Preconditions, deliverable list, dependency graph, generator requirements, coordinate checklist, door safety tests D-1…D-9, visual acceptance V1–V10, measurement scripts, streaming tests, integration files, blockers, definition of done | **the next implementation agent** |
| [`OPEN-DESIGN-DECISIONS.md`](OPEN-DESIGN-DECISIONS.md) | 14 findings with evidence, options, recommendation and a safe default; plus what is explicitly *not* open | the director |
| [`CITY-MASTERPLAN.excalidraw`](CITY-MASTERPLAN.excalidraw) | **Editable** top-down masterplan, to scale, 6 px/stud, 127 elements | marking it up |
| [`CITY-MASTERPLAN-preview.png`](CITY-MASTERPLAN-preview.png) | 2380 × 3916 raster preview (rendered from the same scene model) | looking at it without Excalidraw |
| [`CITY-MASTERPLAN-preview.svg`](CITY-MASTERPLAN-preview.svg) | Vector preview, same scene, 1:1 stud scale | printing or diffing |
| [`gen_masterplan_board.py`](gen_masterplan_board.py) | The generator for all three board outputs. One scene model → Excalidraw + SVG + PNG, so they cannot drift. Stdlib + Pillow | regenerating after a coordinate change |

### 2.1 Regenerating the board

```bash
python docs/planning/M2-city-expansion/preproduction/gen_masterplan_board.py
```

It prints the canvas size, the three output paths, the element count and the world span. It
reads no runtime state; the coordinate tables are literal in the script and cite
`02-WORLD-STRUCTURE.md`. If the contract changes, change both.

### 2.2 Reading the board without Excalidraw

`CITY-MASTERPLAN-preview.png` is the same drawing at 1.6× the board resolution. The dark band
at the top is the north skyline (non-walkable); the grey wash above the house is the horizon
apron; amber is the player route; sage arrows are sightlines; navy rings are zone roots; brick
dots are prompts. The board is **to scale** — distances measured on it are stud distances.

---

## 3. What the review found (the short version)

Fourteen findings, all in `OPEN-DESIGN-DECISIONS.md`. Six need a decision before M2-A1:

| ID | Finding | Evidence | Recommendation | Default |
|---|---|---|---|---|
| **D1** | Shop prompt anchors are **12 studs** behind their own counter line, against a **10-stud** activation distance | 24-stud facade depth, anchor at the lot centroid `x = ±68` | move to `x = ±58` | keep approved |
| **D2** | `City_HomeDoor` **floats 2.56 studs** off the shell face | shell outer face `z = 13.35`, leaf at `z = 16` | build a 3-part porch recess | keep coordinate, build porch |
| **D3** | The approved skyline covers **0.00°** of the bedroom window's aperture | aperture −25.0°…−3.8° from `CameraFocus`; backdrop +3.3°…+44.6° | mirror to `x -120…+120`, tower at `x = -34.3`, 8 → 9 parts | V-03 stays open |
| **D5** | M2-A is **20 parts over** its own 450 ceiling | 448 geometry + **22** unbudgeted anchor markers = 470 | cut 22 P2 dressing parts (named list) | cut them |
| **D10** | A kiosk at `x = 0` **occludes 100%** of the fountain from the stoop | −7.1°…+20.6° vs −1.2°…+8.7° | shift the kiosk +10 studs east | reword acceptance as a sequence |
| **D11** | Spawn facing `+Z` points the chase camera **into the doorway** | 12.5-stud boom vs a leaf 4 studs behind the spawn | face `-Z` at `City_Spawn` | keep `+Z` |

The remaining eight (D4 streaming, D6 `Concrete`, D7 walk-through props, D8 ten signs vs
eight `SurfaceGui`s, D9 the bus stop with no road, D12 no light left for M2-C, D13 the fade
needs a client surface, D14 `Lighting.Technology` unrecorded) all have a safe default that
requires no document change.

**Nothing in this package silently modifies an approved coordinate.** Where a correction is
needed it is proposed with its arithmetic, and the default is always the approved value.

---

## 4. Asset and part-count estimates

Full working in `CITY-PERFORMANCE-BUDGET.md` §3. **Estimates, not measurements.**

| Budget | Approved | This package's estimate | Delta |
|---|---:|---:|---:|
| **M2-A1 graybox** (B1) | ≤ 450 (blockout ceiling) | **122** | 27% of the ceiling |
| **M2-A dressed** (B2) | 448 geometry / 450 ceiling | **418** incl. 22 anchors | −30 |
| **M2-B additional** | 510 | **375** | −135 |
| **Whole city** (B3) | 958 / ceiling 1,200 | **793** | −165 |

The M2-B "headroom" is art, not surplus: every P1/P2 dressing pass is excluded from these
figures (§3.1 of the budget doc). Use it as insurance against the estimate being wrong.

| Prefab | Phase | Estimate | Approved |
|---|---|---:|---:|
| `HouseExterior` | M2-A | 75 | 90 |
| `StreetBlock` | M2-A | 83 | 80 |
| `TownCenter` shell | M2-A | 120 | 140 |
| `CityBoards` | M2-A | 28 | 40 |
| `CityGate` | M2-A | 21 | 30 |
| `CityBackdrop` | M2-A | 9 | 8 |
| `CityProps` (kit instances) | M2-A | 60 | 60 |
| anchors | M2-A | 22 | not budgeted |
| `TownCenter` props | M2-B | 87 | 80 |
| `ShopRowElectronics` | M2-B | 70 | 120 |
| `ShopUtility` | M2-B | 40 | 50 |
| `ShopFurniture` | M2-B | 82 | 100 |
| `EventPlaza` permanent | M2-B | 96 | 160 |

### 4.1 Asset families

**20 families** (the 15 requested, with "doors and windows" split into two, plus 4 support
families) and **53 module variants**, in `MODULAR-ASSET-KIT.md` §3:
`Wall` `Fac` `Roof` `Door` `Win` `SW` `RD` `Lamp` `Bench` `Plant` `Sign` `Stall` `Counter`
`Ftn` `Banner` `Sky` + `Cable` `Bin` `Post` `Rope`.

Priority counts: **P0 = 5 assets (268 parts)**, **P1 = 7 assets**, **P2 = 7 assets**.
No building-level template exists — that is deliberate (§1 of the kit doc).

---

## 5. Proposed M2-A1 implementation sequence

Full detail in `M2-A1-IMPLEMENTATION-HANDOFF.md`. Summary:

| # | Task | Gate |
|---|---|---|
| 0 | BS-14 Go + M2-G1 acceptance (incl. D1–D3, D5, D10, D11) | **blocks everything** |
| 1 | `tools/gen_city_prefabs.py` skeleton: constants, palette reuse, self-checks | prints constants, 0 parts |
| 2 | `HouseExterior` (shell, porch, stoop, leaf, facade) | no gap at the door, no camera clip |
| 3 | `StreetBlock` (road, bands, kerbs, 2 lamps, 2 posts) | 6-stud clear path |
| 4 | `TownCenter` (disc, segmented rim, fountain, 4 lamps, 4 bench massings) | fountain visible from the stoop |
| 5 | `CityBoards` (12 studs wide at `x +4…+16`) | does not occlude the fountain |
| 6 | `CityGate` (piers, lintel, shutter) | frames the horizon from the plaza |
| 7 | `CityBackdrop` (9 parts, tower at `x = -34.3`) | **the window shows silhouettes, not sky** |
| 8 | `CityAnchors` (22 markers) | none collides with the bedroom's 12 names |
| 9 | Assemble `Workspace.City`, set `ModelStreamingMode` | — |
| 10 | Door safety tests D-1…D-9 | the frozen `Door` and 155-part room are byte-identical |
| 11 | Visual acceptance V1–V10 on genuine captures | M2-G2 |
| 12 | Measurements → `perf.json` (incl. `Lighting.Technology`, `StreamingEnabled`) | M2-G5 input |
| 13 | Regression: existing suite unchanged, zero new failures | handoff |

**Estimated effort: 1–2 dev-days including Studio review** (`07` §3). If it exceeds 3 days,
the coordinate contract is wrong — stop and re-open M2-G1 rather than pushing through.

---

## 6. Boundaries this package respects

| Rule | How it is respected |
|---|---|
| No `src/`, `assets/`, `tools/`, `tests/`, project-file edits | only `docs/planning/M2-city-expansion/preproduction/` is added |
| No bedroom prefab, `Catalog.luau`, `EconomyService.luau`, `WorldService.luau`, `ProfileStore.luau`, `NetRouter.luau` changes | none read at runtime; all referenced read-only |
| No `CityService` | not created; it is M2-A4 |
| No published place, no deploy | nothing is built or uploaded |
| Separate worktree from Agent 1's BS-14 branch | this branch lives in the `Agent-2` worktree; the BS-14 work is in the primary tree at `agent/BS-14-rc1-evidence-remediation` |
| No new prices, tiers, profile fields | zero economy constants authored; every shop surfaces the existing catalogue |
| Existing tests untouched | no test file is created or modified; M2-A1 adds specs only when M2-A4 does |
| Coordinates preserved | all corrections are *proposed* in `OPEN-DESIGN-DECISIONS.md`, with the approved value as default |

---

## 7. Where the next agent starts

1. Read `OPEN-DESIGN-DECISIONS.md` §1 (the register) — 6 rows need an answer.
2. Read `M2-A1-IMPLEMENTATION-HANDOFF.md` §1 (preconditions) and §3 (dependency graph).
3. Build in the order in §5 above, with the kit in `MODULAR-ASSET-KIT.md`.
4. Stop at the blockout. Do not add shops, UI, services, or economy to make it feel finished.

**Do not start M2-A1 without director authorization and the BS-14 gate.**
