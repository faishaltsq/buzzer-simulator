# D3 — House exterior and porch spec

**Verdict: PROPOSED option B1 — 0.6-stud offset shell with return walls
bridging the 2.56-stud recess, no roof plane.** The frozen room, the `Door`
part and the camera anchors are untouched by every option below.

## Frozen inputs

| Item | Value | Rule |
|---|---|---|
| Room | 24 × 24 around origin | never edited |
| `Door` part | `(-6, 3.65, 11.6)`, `3.7 × 7.3 × 0.18`, `CanCollide = true` | never resized, rotated, un-collided or reparented |
| `City_HomeDoor` | `(-6, 3.65, 16)` on the exterior face | preserved |
| `City_DoorPromptInterior` | `(-6, 3.65, 8)` inside | preserved |
| Door plane | `Z = 11.51 … 11.69` | no walk-through passage |
| North window | aperture preserved | a solid new north wall invalidates D1 |
| Shell | offset **0.6** outward, no z-fighting | parent §7.1 |
| Doorway cut | `X ∈ [-7.85, -4.15]`, `Y ∈ [0, 7.3]` | parent §7.1 |
| Top | stop at `Y = 11.9`, shallow parapet, **no interior ceiling** | parent §7.1 |
| Grade | city starts at `Z = 16` — a 4-stud stoop | parent §7.1 |

## Front facade silhouette

| Band | Height (Y) | Treatment |
|---|---|---|
| Stoop / threshold | `0 … 0.6` | grade-continuous slab `Z 13.35…16`, no riser |
| Wall body | `0.6 … 8.0` | plaster/cream cladding echoing the bedroom wall tone |
| Door surround | `0 … 7.3` | frame returns around the `[-7.85, -4.15]` aperture |
| Window band | `3.1 … 7.9` | aperture kept open at the north face |
| Frieze | `8.0 … 11.9` | plain band, sage door colour carried to the frame |
| Parapet | `11.9 … 12.5` | shallow cap, no roof plane until a camera test proves it safe |

Silhouette width 24 studs, depth 24 studs; height ≤ 12.5 studs so the mobile
chase camera never clips it at the stoop.

## Entrance frame and door alignment

`City_HomeDoor` stays at `(-6, 3.65, 16)`, centred in the aperture. The exterior
leaf is a **new** part echoing `3.7 × 7.3 × 0.18`; the frozen interior `Door` is
never touched. The exterior leaf is closed and opaque — no visual passage
through the room.

## Porch / stoop options

| Option | Treatment | Tradeoff |
|---|---|---|
| A — flush slab | Slab `Z 13.35…16` at grade, door leaf recessed 2.56 studs | 2 BaseParts; visible recess shadow at the door |
| **B1 — returns (recommended)** | Flush slab + two return walls `X ∈ [-7.85, -4.15]` bridging the 2.56 recess, meeting the leaf at `Z = 15.91` | 4–6 BaseParts; seam reads as a door frame, no shadow gap |
| B2 — full porch | Slab plus a low stoop wall and a step nosing | 8–10 BaseParts; risks an unapproved elevation change — rejected |

B1 keeps the threshold at grade (no riser, no elevation change) and makes the
seam inspectable in the blockout, which is the A1 evidence requirement.

## Side elevation and window aperture

Side elevation shows the 0.6 offset as a visible shadow gap, the parapet cap,
and the north window band at `Y 3.1…7.9`. The exterior shell must not add a
ceiling, a roof plane or any north wall filling the aperture — both D1 skyline
candidates depend on that opening.

## Safe exterior spawn area

`City_Spawn (-6, 0.6, 20)` is 4 studs south of `City_HomeDoor`, inside Z0
(`Z -24…+16` is the zone; spawn at `Z = 20` is in the Z1 throat, clear of the
shell). Spawn must be ≥ 4 studs clear of the shell, the `Door`, the
`City_HomeDoor` part and any prop — asserted in the readiness checklist.
