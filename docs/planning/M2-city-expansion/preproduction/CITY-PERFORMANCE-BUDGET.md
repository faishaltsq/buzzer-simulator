# Canonical city performance budget

**Allocations, not generated counts or device measurements.** Parent sources:
`../03-ZONE-SPECIFICATIONS.md`, `../05-TECHNICAL-PRODUCTION-AND-PERFORMANCE.md` and
`../07-ROADMAP-RISKS-ASSETS.md`.

## Phase arithmetic

| M2-A allocation | BaseParts |
|---|---:|
| HouseExterior | 90 |
| StreetBlock | 80 |
| TownCenter shell | 140 |
| CityBoards | 40 |
| CityGate | 30 |
| Backdrop | 8 |
| Shared props instances across zones | 60 |
| **M2-A total** | **448** |

| M2-B addition | BaseParts |
|---|---:|
| TownCenter props | 80 |
| ElectroMart | 120 |
| Rumah Rapi (conditional approval) | 100 |
| Event plaza permanent | 160 |
| Utility | 50 |
| **M2-B addition** | **510** |
| **Cumulative city** | **958** |
| **City hard cap** | **1,200** |
| **Unallocated city headroom** | **242** |

The eight zone-index budgets sum to 848 across A/B, not 468 for A. Add 60 shared props
and 50 utility to reach 958. TownCenter's 220 splits into 140 shell + 80 later props.
Cosmetics and event-only dressing are not additions to the A/B total.

## Counting contract

Count every BasePart once in the assembled Workspace.City, including invisible markers,
physical door, pivot parts and every placed copy of a kit. Library prototypes in storage
are reported separately, not added to the live scene. Count temporary review helpers
separately and remove them before final evidence.

The parent does not prove markers were excluded from 448. Therefore **448+22=470 is not
a demonstrated overrun**. Reserve marker costs *inside* the existing allocation and
measure. The full marker inventory is 22 invisible parts; HomeDoor is already one of the
house's physical parts. If only a subset is authored in A1, enumerate it explicitly.
Do not claim an exact build-up estimate until a deterministic generator produces it.

The 60 shared-kit allocation is a cost pool across placed instances, not 60 extra parts
to add after already counting benches and lamps inside zones. Attribute each part to
one pool; report both physical per-zone counts and ledger allocation to catch double counting.

## A1 versus later gates

A1 remains **blockout ≤450** under the parent acceptance. Prefer the fewest primitives
that prove layout; no new 150/180 stop gate is adopted. A1 contains no functional shops,
shop hats, production services, animation, prompt logic, UI or economy. The 448 number
is the full A foundation estimate, not a separate mandated A1 dressed ceiling of 450.
Reconcile any later overrun with the director rather than inventing a mandatory cut list.

Bedroom budget remains ≤350 including equipment and client worker rigs. It is not 350
minus Bedroom's 155: remaining capacity depends on the actual furnished configuration.
Cosmetic room items are charged to that full room total, never to the city budget.

## Runtime constraints and proof

City lights: ≤8 PointLights, ≤2 with Shadows enabled; allocate from one ledger when
fixtures are authored, leaving future needs to the owning phase. No guarantee about
shadow rendering follows from a property value. Read current place lighting settings;
do not force a legacy renderer mode or relight the bedroom to satisfy a drawing.

No invented SurfaceGui/transparent-part hard cap is imposed here. Count those instances
and profile cost; use one GUI per independently hosted sign, keep world text occluded,
and avoid layered transparent planes. Preserve the parent 6-stud route clearance,
fountain clearance and camera checks. Part counts alone do not prove FPS.

At A1/A-final capture: built-place and per-zone BaseParts; markers included/excluded;
GUI, light and shadow counts; streaming settings; lighting settings; walking times;
portrait/landscape screenshots; desktop and real-device frame-time observations. Label
emulator results as emulator results, never physical-phone performance. Target ≥30 FPS
on the actual baseline device, no persistent >100ms script stalls. Do not invent draw
calls, frame timings, device coverage, DataStore results or human sign-off.
