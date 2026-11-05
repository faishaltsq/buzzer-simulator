# D7 — BasePart ledger (allocation, not a measured count)

**Verdict: allocations are internally consistent and A1 has headroom; no cut
list is pre-authorised.** Nothing in this ledger is a measured Studio count —
measured counts are produced by the A1 build and recorded separately.

## Phase arithmetic (parent values, re-derived)

| Phase | Line | BaseParts |
|---|---|---:|
| M2-A | HouseExterior | 90 |
| M2-A | StreetBlock | 80 |
| M2-A | TownCenter shell | 140 |
| M2-A | CityBoards | 40 |
| M2-A | CityGate | 30 |
| M2-A | Backdrop | 8 |
| M2-A | Shared props instances across zones | 60 |
| **M2-A total** | | **448** |
| M2-B | TownCenter props | 80 |
| M2-B | ElectroMart | 120 |
| M2-B | Rumah Rapi (conditional) | 100 |
| M2-B | Event plaza permanent | 160 |
| M2-B | Utility | 50 |
| **M2-B addition** | | **510** |
| **Cumulative city** | | **958** |
| **City hard cap** | | **1,200** |
| **Unallocated headroom** | | **242** |

## Single-count ledger — what must be counted once

| Category | Where counted | Notes |
|---|---|---|
| Visible geometry | inside its owning prefab allocation | shell, road, paving, fountain massing |
| Invisible anchor parts | inside the owning prefab allocation, once | 16 markers + 6 signposts = 22 invisible |
| Physical doors | inside the owning prefab allocation | `City_HomeDoor` is one of the house's parts |
| Pivot parts | inside the owning prefab allocation, once | never author world coordinates then `PivotTo` again |
| Copied modular props | inside the 60 shared pool, once per placed instance | a pool, not 60 extra parts on top of zone counts |
| Sign geometry | inside the owning zone allocation | one `SurfaceGui` per hosted face |
| Temporary review objects | counted separately, removed before final evidence | never folded into the ledger |

## Marker inventory

| Set | Count |
|---|---|
| Positioned part identities in the parent anchor table | 17 (16 invisible + physical `City_HomeDoor`) |
| Full design inventory with six signposts | **22 invisible + 1 physical = 23 BaseParts** |
| `City_LightGroup` | Folder — **not** a BasePart |

The old "448 + 22 = 470 overrun" argument is unsupported: the parent never
excluded markers from the 448, so marker cost is reserved *inside* the
allocation and measured. A1 authors a subset; that subset is enumerated
explicitly in the A1 evidence.

## A1 ceiling

| Value | Meaning |
|---|---|
| A1 blockout ceiling | **≤ 450** BaseParts in the assembled city, markers and pivot parts included |
| Relationship to 448 | 448 is the full M2-A foundation estimate, not a separate dressed A1 ceiling |

## If a measured A1 count exceeds 450

Reduce decoration, never the silhouette, in this order:

1. **Shared props pool first** — benches, planters, ropes, chalk detail. They
   carry no layout proof.
2. **Sign geometry** — one authored sign per zone; drop secondary signage.
3. **Kiosk and gate dressing** — keep massing, drop the flag banner, lamp and
   queue rope.
4. **Fountain detail** — keep the r = 8 basin; drop the ring segments beyond
   what the sightline test needs.

Never cut: the house shell, the road and bands, the plaza disc, the fountain
basin, the kiosk supports, the gate silhouette, the backdrop, or any marker the
checklist requires. If the overrun survives decoration cuts, stop and
reconcile with the director — do not invent a new mandatory stop gate.

## Bedroom boundary

The bedroom budget (≤ 350 BaseParts including equipment and client worker rigs)
is separate and is not 350 minus Bedroom's 155; remaining capacity depends on
the furnished configuration. Cosmetic room items are charged to the room total,
never to the city budget.
