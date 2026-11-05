# M2-A1 readiness — isolated 3D blockout

**Verdict: the coordinate contract is build-ready.** M2-A1 remains **unassigned**
until the director accepts M2-G1. This page is the checklist the implementer
runs; it grants no authorisation.

## Preconditions (all required before any geometry is authored)

1. Director M2-G1 acceptance of this package.
2. Explicit assignment of M2-A1 by the director.
3. Current branch/worktree and shared-file ownership checked; Agent 1's BS-15
   branch untouched.
4. A separate review scene/place — never the shipped gameplay place. Mapping
   into `ServerStorage` alone does not assemble `Workspace.City`.

## Build order (10 steps)

| # | Step | Acceptance |
|---|---|---|
| 1 | House exterior shell + threshold | frozen room byte-identical; window aperture preserved; no ceiling; seam inspectable |
| 2 | Porch and exterior threshold | option B1 returns; grade unchanged; no riser |
| 3 | Street and sidewalks | 32-wide road + 8-stud bands each side; tops at `Y = 0` |
| 4 | Plaza floor | disc r 40 at `(0, 0, 112)`; built as segments, not an invented hollow primitive |
| 5 | Fountain | r 8 basin; 8-stud clearance; no new prompt |
| 6 | Mission kiosk | option B open-frame inside Z6; 3D stoop-to-fountain sightline test |
| 7 | Skyline backdrop | baseline on the shipped copy, candidate on a separate review copy |
| 8 | Future district gate | massing inside the allocated 16 × 16 extent |
| 9 | City anchors | only the 17 parent identities, exact positions, under `City_Anchors` |
| 10 | Review-scene assembly | one translation per zone; no doubles, scripts or external asset references |

For later shop approach review, derive values from `SHOP-APPROACH-PLAN.md`:
lot edge `X = ±56`; counter face `X = ±60`; candidate avatar root `X = ±59`;
baseline host `X = ±68`. These are XZ planning positions, not Studio
reachability proof (P5). Kiosk step 6 uses the canonical Option B specification
in `KIOSK-VISIBILITY-COMPARISON.md` (6 × 6 × 9, two 1-stud posts, centres 5 apart).
Full marker inventory: 17 positioned identities (16 invisible + physical
`City_HomeDoor`) plus 6 signpost markers = 22 invisible + 1 physical = 23 BaseParts.

## Objective acceptance tests

| # | Test | Objective |
|---|---|---|
| A1 | Zone coordinates | every zone edge matches `02` §3.1 exactly |
| A2 | Safe walking paths | 6-stud clear width on all routes; no prop in the spawn throat |
| A3 | Building silhouettes | identifiable at 60 studs by shape + sign colour |
| A4 | Skyline visibility | C1 capture shows the silhouette in the aperture |
| A5 | No floating geometry | every part anchored; nothing above grade unsupported |
| A6 | No window obstruction | north aperture retained; no new solid north wall |
| A7 | No roof camera collision | no roof plane until a camera test proves it safe |
| A8 | Marker inventory integrity | authored subset enumerated against the 23-part full inventory; no duplicates |
| A9 | BaseParts ≤ 450 | counted in the assembled city, markers and pivots included |
| A10 | Frozen bedroom unchanged | names, sizes, transforms and ownership intact |
| A11 | No scripts in generated prefabs | no `Script`, `LocalScript` or remote inside any generated model |
| A12 | No additional production services | no `CityService`, no new remote, no new module in `src/` |
| A13 | Walking time | door → fountain ≤ 12 s measured on foot (parent estimate 6.3 s is a lower bound) |
| A14 | Regression suite | existing suite unchanged and green; exact counts recorded |

## What A1 must not contain

Functional shops, shop hats, production services, animation, prompt logic, UI,
economy, persistence, cosmetics, events, or a detail pass. Stub/no-logic prompt
hosts only; A2+ owns `CityService`, real transitions and mission routing.

## Stop conditions

Stop and report if completing any step would require changing frozen room
geometry, a runtime service, or an unapproved coordinate.
