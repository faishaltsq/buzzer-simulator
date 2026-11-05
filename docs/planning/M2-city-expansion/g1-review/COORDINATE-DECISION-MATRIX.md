# Coordinate decision matrix — M2-G1 (D1–D8)

Each row states the recommendation, the frozen baseline that survives it, and the
approval required before an M2-A1 implementer may act. Nothing here is approved
by the agent. `PROPOSED` means unverified and awaiting director or Studio
evidence; `FROZEN` means already merged and unchanged by this package.

Legend: **FROZEN** = merged baseline · **PROPOSED** = recommendation only ·
**TEST REQUIRED** = cannot be proven in 2D planning.

## D1 — Skyline / backdrop alignment

| Item | Value |
|---|---|
| Baseline | Backdrop X `+16…+160`, Z `-192…-112`, height ≤ 120, 8 parts, `Persistent` |
| Proposal | Backdrop X `-120…+120`, same Z extent |
| Recommendation | Adopt the **centred** backdrop as the A1 candidate, built on a separate review copy |
| Frozen | Baseline extent stays canonical until director accepts the change |
| Approval | Director + isolated Studio camera view from `CameraFocus` |

Full derivation: [`SKYLINE-COMPARISON.md`](SKYLINE-COMPARISON.md).
Summary: the desk camera at `(7.0, 5.5, 3.0)` projects the window aperture
(`X 0.1…5.9`, `Y 3.1…7.9` at `Z = -12.08`) onto the `Z = -152` plane as
`X ≈ -63.92…-4.31` (M2-A0 reference `-65.33…-3.33`, from its rounded reference
camera). The baseline backdrop
covers **0 %** of that slice; the proposal covers **100 %**. 2D projection is
not proof of live-camera visibility, so the coordinate is **PROPOSED**.

## D2 — Mission kiosk vs fountain visibility

| Item | Value |
|---|---|
| Baseline | Z6 `X -12…+12`, `Z +64…+72`; prompt `City_Prompt_Boards (0, 3, 68)` |
| Options | A solid board kiosk · B narrow open-frame kiosk |
| Option A dimensions | 12 × 6 × 9 studs; 2 supports, width 1, centre spacing 11; ~32 parts |
| Option B dimensions | 6 × 6 × 9 studs; 2 supports, width 1, centre spacing 5; ~30 parts |
| Recommendation | **Option B** — narrow open-frame inside the frozen Z6 extent |
| Frozen | Zone extent, prompt anchor, prompt identity |
| Approval | Director design acceptance and explicit later M2-A1 assignment; any extent change also needs a coordinate decision |

Dimensions above are derived from the single source of truth:
[`KIOSK-VISIBILITY-COMPARISON.md`](KIOSK-VISIBILITY-COMPARISON.md) § Canonical kiosk specification.
Visibility and readability remain hypotheses pending Studio proof (P2).

## D3 — House exterior and porch

| Item | Value |
|---|---|
| Baseline | `City_HomeDoor (-6, 3.65, 16)`, `City_DoorPromptInterior (-6, 3.65, 8)`, shell offset 0.6 outward, aperture `X -7.85…-4.15`, `Y 0…7.3`, stop at `Y = 11.9` |
| Recommendation | Option **B1** — 0.6-stud offset shell with 2.56-stud recess bridged by return walls, no roof plane |
| Frozen | `Door` part (`3.7 × 7.3 × 0.18`, collidable), room walls, camera anchors, window aperture |
| Approval | Director on the porch/return treatment; shell offsets already parent-specified |

Full spec: [`HOUSE-EXTERIOR-SPEC.md`](HOUSE-EXTERIOR-SPEC.md).

## D4 — Shop prompt reachability

| Item | Value |
|---|---|
| Baseline | Prompt hosts east `+68`, west `-68`; 10-stud activation, ≤ 12-stud server validation |
| Recommendation | Lot edge `X = ±56`; counter face `X = ±60`; candidate avatar root `X = ±59`; baseline host `X = ±68`. Same-Z horizontal avatar-host estimate 9 studs; face-host reference 8; edge-host reference 12 |
| Frozen | Host coordinates until an explicit amendment is accepted |
| Approval | Explicit coordinate amendment for any host move |

Full plan: [`SHOP-APPROACH-PLAN.md`](SHOP-APPROACH-PLAN.md).
Its canonical shop approach owns these derived values. Reachability is
**TEST REQUIRED (P5)**: actual HRP height, collision and line of sight are not
proven in Studio. No automatic host relocation is proposed.

## D5 — Streaming readiness

| Item | Value |
|---|---|
| Baseline | Parent intent: `Atomic` zone models, `Persistent` backdrop, `Player:RequestStreamAroundAsync` in the later transition phase |
| Recommendation | Checklist-driven verification during A1; no streaming service in M2-G1 or A1 |
| Frozen | No claim about `StreamingEnabled` from absent project properties |
| Approval | None in M2-G1; A2+ owns the transition service |

Checklist: [`CAMERA-AND-STREAMING-CHECKLIST.md`](CAMERA-AND-STREAMING-CHECKLIST.md).

## D6 — Camera experience

| Item | Value |
|---|---|
| Baseline | Existing camera controller, spawn facing `+Z` |
| Recommendation | Nine fixed capture poses with acceptance criteria; no new controller |
| Frozen | No camera override is shipped by A1 |
| Approval | None in M2-G1; M2-G2 uses the captures |

Compositions: [`CAMERA-AND-STREAMING-CHECKLIST.md`](CAMERA-AND-STREAMING-CHECKLIST.md) § Camera.

## D7 — Performance and part budget

| Item | Value |
|---|---|
| Baseline | M2-A 448 · M2-B +510 · cumulative 958 · hard cap 1,200 · A1 blockout ≤ 450 |
| Recommendation | Single-count ledger; markers counted once inside the allocation; no invented cut list |
| Frozen | Bedroom budget (≤ 350 incl. equipment) stays separate |
| Approval | Director reconciliation if a measured A1 count exceeds 450 |

Ledger: [`PART-BUDGET-LEDGER.md`](PART-BUDGET-LEDGER.md).

## D8 — Cosmetics and events

| Item | Value |
|---|---|
| Baseline | No cosmetic ownership persistence, no event reward persistence, no new schema, prices, worker systems or income bonuses in A1 |
| Recommendation | Defer every feature needing new persistent data to M2-B/M2-C with explicit design, migration and idempotency contracts |
| Frozen | Economy, DataStore schema, catalog |
| Approval | M2-G3 (shop/event review) and M2-G4 (schema) gates |

Deferred list: [`DIRECTOR-APPROVAL-REQUEST.md`](DIRECTOR-APPROVAL-REQUEST.md) § Deferred.

## Authoritative coordinate table

This is the single proposed M2-G1 contract table. `Status` is `FROZEN` only where
the parent already merged the value; otherwise `PROPOSED`. Positions are studs at
grade `Y = 0` unless noted.

| Object | Zone | Baseline | Proposed | Size / footprint | Pivot | Facing | Collision | Streaming | Status | Reason | Validation |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `City_HomeDoor` | Z0 | `(-6, 3.65, 16)` | — | 3.7 × 7.3 × 0.18 echo | exterior face | +Z | collide (outside only) | zone-local | FROZEN | physical return surface | exact transform byte-check |
| `City_DoorPromptInterior` | Z0 | `(-6, 3.65, 8)` | — | invisible host | interior wall plane | — | none | zone-local | FROZEN | "Keluar Rumah" host | name uniqueness |
| `City_Spawn` | Z0/Z1 | `(-6, 0.6, 20)` | — | invisible marker | root height | +Z | none | zone-local | FROZEN | door exit destination | ≥ 4 studs clear of shell/door |
| House exterior shell | Z0 | — | 24×24 wrap, 0.6 outward | walls + returns | zone origin | — | outside faces | zone-local | PROPOSED | continuation of bedroom | window aperture retained; no interior ceiling |
| Porch / stoop | Z0 | — | grade slab at `Z 13.35…16` | 0.6 thick | shell-local | — | walkable | zone-local | PROPOSED | bridge 2.56 recess | no elevation change |
| `City_Zone_Street` | Z1 | `(0, 0, 40)` | — | invisible | street centerline | — | none | zone-local | FROZEN | telemetry | name uniqueness |
| Street road + bands | Z1 | — | 32 + 8 + 8, tops `Y=0` | 48 wide × 48 | zone origin | — | collide | zone-local | PROPOSED | traversal | 6-stud clear route |
| `City_Zone_TownCenter` | Z2 | `(0, 0, 112)` | — | invisible | plaza center | — | none | zone-local | FROZEN | telemetry | name uniqueness |
| Plaza disc | Z2 | — | center `(0,0,112)`, r 40 | 80 × 80 | plaza center | — | walkable | zone-local | PROPOSED | hub | 6-stud ring kept clear |
| Fountain | Z2 | — | cylinder r 8 at center | r 8 | plaza center | — | collide | zone-local | PROPOSED | landmark | 8-stud clearance, no new prompt |
| `City_Prompt_Boards` | Z6 | `(0, 3, 68)` | — | invisible host | kiosk face | +Z | none | zone-local | FROZEN | mission surface | prompt identity + distance |
| `CityBoards` kiosk | Z6 | — | option B, X -3…+3, Z 65…71, height 9 | 6 × 6 footprint; ~30 parts within allocation 40 | zone origin | +Z | supports only | zone-local | PROPOSED | canonical D2 spec above | fountain visibility 3D test |
| `City_Zone_ShopEast` | Z3 | `(68, 0, 108)` | — | invisible | row root | — | none | zone-local | FROZEN | telemetry | name uniqueness |
| `City_Prompt_ElectroMart` | Z3 | `(68, 3, 84)` | keep at +68 | invisible host | behind face X +60 | -X (plaza) | none | zone-local | FROZEN | existing Upgrades | real HRP distance ≤ 12 |
| `City_Prompt_RumahRapi` | Z4 | `(-68, 3, 84)` | keep at -68 | invisible host | behind face X -60 | +X (plaza) | none | zone-local | FROZEN | cosmetic shop | real HRP distance ≤ 12 |
| `City_Prompt_Cosmetics` | Z3 | `(68, 3, 108)` | — | invisible host | behind face X +60 | -X (plaza) | none | zone-local | FROZEN | future shop (M2-C) | host only in A1 |
| `City_Prompt_Utility` | Z3 | `(68, 3, 132)` | — | invisible host | behind face X +60 | -X (plaza) | none | zone-local | FROZEN | map/return | host only in A1 |
| `City_Zone_ShopWest` | Z4 | `(-68, 0, 84)` | — | invisible | row root | — | none | zone-local | FROZEN | telemetry | name uniqueness |
| `City_Zone_EventPlaza` | Z5 | `(-108, 0, 134)` | — | invisible | plaza center | — | none | zone-local | FROZEN | telemetry | name uniqueness |
| `City_Prompt_EventPlaza` | Z5 | `(-108, 3, 110)` | — | invisible host | board face | +X | none | zone-local | FROZEN | read-only schedule | host only in A1 |
| `City_Zone_FutureGate` | Z7 | `(0, 0, 168)` | — | invisible | gate center | — | none | zone-local | FROZEN | telemetry | name uniqueness |
| `City_Prompt_FutureGate` | Z7 | `(0, 3, 168)` | — | invisible host | gate face | -Z | none | zone-local | FROZEN | locked copy | honest copy, no timer |
| CityGate shell | Z7 | — | X -8…+8, Z 160…176 | ≤ 30 parts | zone origin | -Z | collide | zone-local | PROPOSED | teaser | fits allocated extent |
| Skyline backdrop | backdrop | X +16…+160, Z -192…-112 | X -120…+120 (candidate) | ≤ 8 parts, h ≤ 120 | parent origin | — | none | Persistent | PROPOSED | fixes V-03 | Studio camera view |
| `City_TransitStop` | Z2 | `(24, 0, 96)` | — | invisible | stop center | — | none | zone-local | FROZEN | future transit | name uniqueness |
| `City_Signpost_01…06` | various | per placement | — | invisible ×6 | per placement | — | none | zone-local | PROPOSED | stamp anchors | no duplicate marker |

Duplicate-anchor and containment checks for this table are asserted in
`verify_g1_review.py` (unique identities, zone containment, frozen values
unchanged).
