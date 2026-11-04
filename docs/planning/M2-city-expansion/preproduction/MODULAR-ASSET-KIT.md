# MODULAR ASSET KIT

> **Status**: Pre-production kit specification. **No prefab is authored in this branch.**
> The M2-A1 implementation agent builds these families in `tools/gen_city_prefabs.py`.
> **Consistency target**: the existing generator conventions in
> `tools/gen_world_prefabs.py` (Part primitives, `PALETTE`/`MATERIALS` tokens,
> `Anchored = true`, no scripts, no external assets) and `assets/world/DESIGN.md`.

---

## 1. Why a kit, and what it is not

The city is **958 parts across 9 zones** built by one agent. Reuse is the only way that
ships. But a kit that is too coarse produces the exact failure the brief forbids —
"repetitive box-shaped buildings" — so the kit is deliberately built at the level of
**architectural members**, not buildings:

- A **wall module** is 8 × 10 studs. A shop is 3 of them wide.
- An **awning** is an 8-stud module. A hat is 2–3 of them.
- Nothing in the kit is "a shop". There is no `ShopTemplate.rbxmx`, because that file
  would be the thing that makes the street look copy-pasted.

Composition is what produces the silhouette, and composition happens in the per-zone
prefab builders, not in the kit.

---

## 2. Conventions (all families)

### 2.1 Pivot

**Every module's pivot is the centre of its bottom face.** Local `+X` runs along the
module's length; local `+Z` points **outward**, i.e. toward the street and the player.

This mirrors the existing contract for desk devices ("all desktop equipment models set
their base precisely at `Y = 0` in model space", `docs/design/07` §2.3), so a generator
function can place a module with `CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)` and
never think about half-heights. It also means every module sits on grade with zero
fudging, which is what keeps a 24-module shopfront from developing a 0.05-stud gap at
the pavement.

Rotation: `yaw` only, in 90° steps. **No pitched modules except the Rumah Rapi awning**
(5° baked into the part's CFrame, still pivoted at the wall attach line).

### 2.2 Naming

```text
Kit_<Family>_<Variant><Size>
```

| Piece | Values |
|---|---|
| `Family` | `Wall` `Fac` `Roof` `Door` `Win` `SW` `RD` `Lamp` `Bench` `Plant` `Sign` `Stall` `Counter` `Ftn` `Banner` `Sky` `Cable` `Bin` `Post` |
| `Variant` | `A` `B` `C` (visual variants of the same module) |
| `Size` | the module's length in studs, unpadded (`8`, `16`, `24`) |

Examples: `Kit_Wall_A8`, `Kit_Fac_Band24`, `Kit_Roof_Eave8`, `Kit_Door_A4`,
`Kit_Ftn_Ring8`. Instances inside a prefab keep the same name so `script_grep` in Studio
can find every use of a module across the city.

**Anchors are never kit parts.** They are `City_*` names in `City_Anchors` (§2.5).

### 2.3 Collision

| Class | `CanCollide` | `CanQuery` | `CanTouch` | Families |
|---|---|---|---|---|
| **Structural** | `true` | `true` | `false` | `Wall` `Roof` `Fac` (shell members) `Door` (leaf) `RD` `SW` `Ftn` (basin) |
| **Prop** | `false` | `false` | `false` | `Lamp` `Bench` `Plant` `Sign` `Stall` `Counter` `Ftn` (trim/water) `Banner` `Sky` `Cable` `Bin` `Post` |

This follows `03` zone rule 5 verbatim ("structural parts collide; props do not") and
`assets/world/DESIGN.md` §3.3. Two consequences, both deliberate:

1. **The stock camera ignores every prop.** Non-queryable parts are invisible to the
   camera's collision raycasts, so awnings, signs, cables and banners never push the boom.
   This is what allows a 24-stud-wide canopy over an open shopfront without any camera
   code (`WORLD-LAYOUT-AND-SIGHTLINES.md` §6).
2. **The player can walk through a bench.** That is the approved rule and it is the right
   trade for mobile pathing (no getting stuck on plaza furniture), but it has a visual
   cost. If the director wants solid benches, it is a per-family exception to be recorded
   in `OPEN-DESIGN-DECISIONS.md` D7 — not a silent change.

### 2.4 Streaming grouping

| Family | Lives inside |
|---|---|
| `Wall` `Fac` `Roof` `Door` `Win` `SW` `RD` `Counter` `Stall` | the zone model that owns the building |
| `Lamp` `Bench` `Plant` `Bin` `Post` | the zone model where the instance stands (`CityProps` instances are **composed into** the zone prefab, not parented across zones) |
| `Sign` | the zone model of its building |
| `Ftn` | `City_Zone_TownCenter` |
| `Banner` | `City_Zone_EventPlaza` (permanent mounts), pop-up model (cloth) |
| `Sky` | `City_Backdrop` (`Persistent`) |
| `City_*` anchors | `City_Anchors` (Folder, outside every zone) |

**No cross-prefab references** (`05` §1.1). A shop never parents into another prefab, and
`CityProps` is a *library of modules* the generator calls, not a runtime folder.

### 2.5 Anchors inside a kit-built prefab

Every interactive prefab exposes exactly one `City_Prompt_*` part, and every zone exposes
one `City_Zone_*` root. Both are 1 × 1 × 1 `Transparency = 1` parts with
`Anchored = true`, `CanCollide/CanTouch/CanQuery = false` — identical to the bedroom's
technical markers. The prompt is a child of the anchor, created by the server, never by
the prefab (`05` §1.4 rule 7).

---

## 3. The families

Part counts are **per module instance**, estimate until measured.

### 3.1 `Wall` — exterior wall modules

| Module | Size (X × Y × Z) | Parts | Material | Token | Reuse |
|---|---|---:|---|---|---|
| `Kit_Wall_A8` | 8 × 10 × 0.5 | 1 | SmoothPlastic | `plaster` | every building; the default |
| `Kit_Wall_B8` | 8 × 10 × 0.5 | 1 | SmoothPlastic | `cream` | the house's east/west side yards, gate piers |
| `Kit_Wall_Col` | 0.9 × 10 × 0.9 | 1 | Wood | `wood_dark` | facade pilasters, stall corners |
| `Kit_Wall_Plinth8` | 8 × 0.35 × 0.6 | 1 | SmoothPlastic | `sage_dark` | the FOOT move on every building |
| `Kit_Wall_Corner` | 0.5 × 10 × 0.5 | 1 | SmoothPlastic | `plaster` | 90° corner closure |

Heights are cut, not scaled: `A8` truncated at `y = 12/14/16` by the generator (a wall
module is the *field*, the building height decides where it stops). No half-height
variants — the parapet covers the cut.

### 3.2 `Fac` — shop facade members

| Module | Size | Parts | Material | Token | Job |
|---|---|---:|---|---|---|
| `Kit_Fac_Band24` | 24 × 1.0 × 0.15 | 1 | SmoothPlastic | `navy` | the BAND move, proud of the wall |
| `Kit_Fac_Cheek` | 0.6 × 7.6 × 1.5 | 1 | SmoothPlastic | `plaster` | the RECESS side return (2 per shop) |
| `Kit_Fac_Header` | 24 × 1.5 × 1.5 | 1 | SmoothPlastic | `wood_dark` | the recess's dark soffit — this is what makes the shop opening read as deep |
| `Kit_Fac_Sill` | 24 × 0.35 × 1.5 | 1 | SmoothPlastic | `sage_dark` | recess floor threshold / step |

### 3.3 `Roof` — roof trim, parapet, eave

| Module | Size | Parts | Material | Token | Job |
|---|---|---:|---|---|---|
| `Kit_Roof_Para8` | 8 × 0.6 × 0.9 | 1 | SmoothPlastic | `plaster` | parapet cap |
| `Kit_Roof_Eave8` | 8 × 0.25 × 0.35 | 1 | Wood | `cream` | **the bedroom's cornice profile, reused** (`docs/design/03` §3.1) — the continuity move in `CITY-ART-DIRECTION.md` §10 |
| `Kit_Roof_Cap8` | 8 × 0.15 × 1.1 | 1 | SmoothPlastic | `ink` | the dark line on top of a parapet; 1 part that makes a flat roof read as finished |
| `Kit_Roof_Soffit` | 8 × 0.5 × 1.2 | 1 | Wood | `wood_dark` | the porch soffit at the house |

### 3.4 `Door` and `Win`

| Module | Size | Parts | Material | Token | Notes |
|---|---|---:|---|---|---|
| `Kit_Door_A4` | 4.0 × 7.3 clear | 4 | Wood | `sage` leaf, `cream` frame | frame = 2 jambs + lintel; leaf is separate |
| `Kit_Door_B2` | 2.2 × 6.8 clear | 3 | Wood | `wood` leaf | service/fire door, gate housing, shop back door |
| `Kit_Door_Leaf4` | 3.7 × 7.3 × 0.18 | 1 | Wood | `sage` + `wood_dark` inset | **the only door the player interacts with** (`City_HomeDoor`) |
| `Kit_Win_A4` | 4 × 4 clear | 4 | Wood + Glass | `cream` frame, `screen` pane | frame, mullion, sill, pane |
| `Kit_Win_B2` | 2.0 × 1.4 | 3 | Wood + Glass | `cream`, `screen` | the upper-floor FACE pair |

Doors are **never passable**. `City_HomeDoor` is a closed, collidable leaf; every other
door in the city is decorative or a locked shop back. No door in the city opens.

### 3.5 `SW` — sidewalk sections

| Module | Size | Parts | Material | Token | Notes |
|---|---|---:|---|---|---|
| `Kit_SW_A8` | 8 × 0.4 × 8 | 1 | SmoothPlastic | `plaster` | 0.4 step = the only elevation change allowed, and it is under the player |
| `Kit_SW_Kerb8` | 8 × 0.4 × 0.12 | 1 | SmoothPlastic | `sage_dark` | kerb face against the road |
| `Kit_SW_Edge8` | 8 × 0.05 × 0.1 | 1 | SmoothPlastic | `cream` | painted edge line |

The 0.4-stud kerb is **not** a ramp: Roblox's default character steps 0.4 without a jump,
and the flat-grade contract (`Y = 0` everywhere walkable) is preserved because the *road*
is at `Y = 0` and the sidewalk is a 0.4 riser that the character walks over. If the M2-A1
blockout shows any hop at the kerb, set the sidewalk to `Y = 0` and make the kerb a
painted line only — that is the fallback, and it costs one part per module.

### 3.6 `RD` — road sections

| Module | Size | Parts | Material | Token | Notes |
|---|---|---:|---|---|---|
| `Kit_RD_A8` | 8 × 0.2 × 8 | 1 | SmoothPlastic | `#3A4448` (ink→navy 45%) | 0.2 thick, top at `Y = 0` |
| `Kit_RD_Dash8` | 8 × 0.02 × 0.3 | 1 | SmoothPlastic | `cream` | centre line, 3 dashes per module |
| `Kit_RD_Grate` | 1.0 × 0.05 × 0.6 | 1 | Metal | `metal` | drain grate |

The lane is `32 × 48` = 24 road modules of 8 × 8, or 4 large slabs plus seam lines. Prefer
**6 modules** (4 big + 2 seams) over 24 small ones: the seam count is a part count.

### 3.7 `Lamp` — lamp posts

| Module | Size | Parts | Material | Token | Notes |
|---|---|---:|---|---|---|
| `Kit_Lamp_A13` | 0.5 base, 13.4 tall, 1.4 arm | 4 | Metal | `metal` + `amber` head | base, pole, arm, head. Carries one `PointLight` (not a part) |
| `Kit_Lamp_B8` | 8 tall | 3 | Metal | `metal` | kiosk/plaza short post, no light |

Four lights maximum are attached to lamp posts (L2, L3, L4 + one reserved); the rest of
the posts are unlit dressing. Never 8 lit posts — see the light budget in
`ZONE-VISUAL-SPECS.md`.

### 3.8 `Bench`

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Bench_A5` | 4.0 × 1.6 × 1.2 | 5 | Wood + Metal | `wood` slats, `metal` frame |

Two slats, a back slat, two legs. Non-colliding (walk-through) per §2.3. No `Seat` — the
M2 scope has no sitting animation and a `Seat` without one is a broken promise.

### 3.9 `Plant` — planters

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Plant_A` | 1.0 × 1.6 × 1.0 | 5 | SmoothPlastic | `clay` pot, `sage_dark` leaves |
| `Kit_Plant_B` | 2.0 × 0.5 × 1.0 | 2 | SmoothPlastic | `clay` trough, `sage_dark` hedge |

Matches the bedroom's `PlantPot`/`PlantLeaf` construction (`build_bedroom`), so the
stoop plant and the plaza planters are literally the same shape language.

### 3.10 `Sign`

| Module | Size | Parts | Material | Token | Notes |
|---|---|---:|---|---|---|
| `Kit_Sign_A6` | 6.0 × 1.6 × 0.12 | 1 | SmoothPlastic | `navy` or `ink` face | + 1 `SurfaceGui` (not a part) |
| `Kit_Sign_B4` | 4.0 × 1.0 × 0.12 | 1 | SmoothPlastic | `navy` | utility/kiosk header |
| `Kit_Sign_Blade` | 1.2 × 5.0 × 0.35 | 1 | SmoothPlastic | `amber` | ElectroMart's projecting hat |
| `Kit_Sign_Post` | 0.25 × 9.2 × 0.25 + 0.9 × 0.6 board | 3 | Wood | `wood`, `cream` | freestanding signposts (stamp tour) |

**One `SurfaceGui` per sign, max 8 city-wide** (`CITY-PERFORMANCE-BUDGET.md` §6.3).
Text is `TextLabel` with the project's existing font; no image labels, no decals.

### 3.11 `Stall` — market stalls (event-only in MVP)

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Stall_A` | 4.0 × 3.2 × 2.4 | 8 | Wood + Fabric | `wood` frame, `sage`/`cream` cloth |

Counter, 4 legs, 2 posts, awning. **Stored in `EventPlaza_PopUp.rbxmx` (M2-C)** — the
permanent plaza shell contains the mounts, not the stalls (`04` F2 failure mode: never
leave a half-built stage).

### 3.12 `Counter` — store counters

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Counter_A` | 6.0 × 3.1 × 1.6 | 4 | Wood | `wood_light` top, `wood` front, `wood_dark` sides |
| `Kit_Counter_B` | 3.0 × 3.1 × 1.2 | 3 | Wood | `wood` |

3.1 studs tall (the bedroom's desk surface is 3.35 — a shop counter is slightly lower than
a desk, which is correct and reads correctly against a standing avatar).

### 3.13 `Ftn` — fountain components

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Ftn_Ring8` | 8 × 1.6 × 1.6 (8 around r = 8) | 8 | SmoothPlastic | `plaster` + `cream` cap |
| `Kit_Ftn_Water` | r = 8 disc | 1 | Glass | `glass` @ 0.25 |
| `Kit_Ftn_Pedestal` | 2 × 1.4 | 2 | SmoothPlastic | `cream` |
| `Kit_Ftn_Spout` | 4 × 0.4 × 0.4 | 4 | Metal | `metal` |
| `Kit_Ftn_Trim8` | 8 × 0.2 × 0.2 | 4 | SmoothPlastic | `sage_dark` |

Total fountain = 19 parts. It is the single largest prop in the city and it is worth it:
it is the only landmark in the geometry that is not a building.

### 3.14 `Banner`

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Banner_Post18` | 0.3 × 18 tall | 1 | Metal | `metal` |
| `Kit_Banner_Mount` | 1.4 × 0.3 × 0.3 | 2 | Metal | `metal` |
| `Kit_Banner_Cloth` | 1.2 × 2.4 × 0.05 | 1 | Fabric | `sage` / `cream` |

Poles stand at 18 studs — above the 16-stud building rule but within the "nothing walkable
above 20" rule (`05` §3.3), and they are poles, not mass. Cloth exists only in the pop-up
model; the permanent plaza has mounts only.

### 3.15 `Sky` — skyline silhouettes

| Module | Size | Parts | Material | Token |
|---|---|---:|---|---|
| `Kit_Sky_Slab` | 40–70 × 24–60 × 4 | 1 | SmoothPlastic | `navy` |
| `Kit_Sky_Tower` | 22 × 120 × 16 | 2 | SmoothPlastic | `ink` |
| `Kit_Sky_Antenna` | 0.2 × 6 | 2 | Neon (tip only) | `amber` |
| `Kit_Sky_Haze` | 240 × 80 plane | 1 | SmoothPlastic | `glass` @ 0.15 |
| `Kit_Sky_Apron` | 280 × 0.2 × 176 | 1 | SmoothPlastic | `sage_dark` @ 0.5 |

`Persistent`, `CanCollide = false`, `CanQuery = false`, never reachable. Total 9 parts
(8 approved + 1 apron — `OPEN-DESIGN-DECISIONS.md` D3). The apron exists so the slabs do
not float above the horizon when seen from the window.

### 3.16 Support families

| Module | Parts | Job |
|---|---:|---|
| `Kit_Cable8` | 1 | 0.05-stud catenary; `ink`; the cheapest "lived-in" signal in the city |
| `Kit_Bin` | 2 | plaza/lane bin |
| `Kit_Post_Sign` | 3 | the six landmark signposts (stamp tour anchors) |
| `Kit_Rope` | 3 | queue rope at the boards kiosk (P2) |

---

## 4. Composition recipes

The kit does not build buildings; these recipes do. Part counts are the **module sum**.

### 4.1 A 24-stud shop (ElectroMart, 16 studs tall)

| Move | Composition | Parts |
|---|---|---:|
| MASS | 3 × `Wall_A8` per side wall (2 sides × 3 rows × 2 heights) + 3 back + 1 roof slab | 16 |
| BAND | 1 × `Fac_Band24` | 1 |
| RECESS | 2 × `Fac_Cheek` + 1 × `Fac_Header` + 1 × `Fac_Sill` | 4 |
| HAT | 3 × awning (Fabric, 8 each) + 2 brackets + `Sign_Blade` + `Sign_A6` | 7 |
| FOOT | 3 × `Wall_Plinth8` | 3 |
| FACE | 2 × `Win_B2` (upper floor window pair) | 6 |
| opening | `Door_A4` frame (leaf omitted — open front) | 3 |
| interior | `Counter_A` + 3 shelf tiers × 2 + 4 shelf brackets | 11 |
| light | fluorescent tube fixture (2 parts) + `PointLight` (not a part) | 2 |
| **subtotal shell** | | **53** |
| dressing | CRT stack 4, phone boxes 2, cable coils 2, bell 1, chair 2, spill stack 6 | 17 |
| **total** | | **70** |

Budget 120 → **50 parts of headroom**, which the M2-B dressing pass (signage polish,
additional shelving, awning valance) is allowed to spend and which the part-count test
will measure.

### 4.2 The house exterior (75 parts)

| Move | Composition | Parts |
|---|---|---:|
| shell | 6 wall members (south split around the opening + lintel) | 6 |
| porch | `Roof_Soffit` + 2 × `Fac_Cheek` (0.6 deep variant) | 3 |
| roof | 4 × `Roof_Para8` + 4 × `Roof_Cap8` | 8 |
| foot | 6 × `Wall_Plinth8` (front/sides only) | 6 |
| door | `Door_Leaf4` + `Door_A4` frame | 4 |
| hat | awning (2 modules) + 2 brackets + porch bulb | 5 |
| face | 2 × `Win_B2` (south facade, east of the door) | 6 |
| eave | 3 × `Roof_Eave8` | 3 |
| dressing | plant 6, scooter 6, fence 5, meter 2, AC 2, downpipe 2, doormat 1, number plate 3, lane line 1, mailbox 3, roof vent 1 | 32 |
| anchors | `City_Spawn`, `City_DoorPromptInterior` | 2 |
| **total** | | **75** |

### 4.3 Instance counts per family, per zone

| Family | Z0 | Z1 | Z2 | Z3-a | Z4 | Z5 | Z6 | Z7 | Backdrop | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `Wall` | 20 | 0 | 0 | 19 | 16 | 0 | 0 | 6 | 0 | 61 |
| `Fac` | 3 | 0 | 0 | 5 | 5 | 0 | 0 | 2 | 0 | 15 |
| `Roof` | 11 | 0 | 0 | 4 | 4 | 0 | 2 | 1 | 0 | 22 |
| `Door`/`Win` | 10 | 0 | 0 | 9 | 6 | 0 | 0 | 3 | 0 | 28 |
| `SW`/`RD` | 1 | 15 | 10 | 0 | 2 | 0 | 4 | 2 | 0 | 34 |
| `Lamp` | 0 | 4 | 16 | 0 | 0 | 0 | 0 | 0 | 0 | 20 |
| `Bench` | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 20 |
| `Plant` | 1 | 0 | 6 | 0 | 1 | 0 | 0 | 0 | 0 | 8 |
| `Sign` | 1 | 3 | 0 | 2 | 1 | 1 | 1 | 1 | 0 | 10 |
| `Stall` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 (M2-C) |
| `Counter` | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 2 |
| `Ftn` | 0 | 0 | 19 | 0 | 0 | 0 | 0 | 0 | 0 | 19 |
| `Banner` | 0 | 0 | 4 | 0 | 0 | 3 | 0 | 0 | 0 | 7 |
| `Sky` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 9 | 9 |
| support | 6 | 12 | 15 | 2 | 2 | 4 | 3 | 1 | 0 | 45 |

These are module counts, not part counts; multiply by the per-module cost in §3 to
reproduce the zone budgets in `CITY-PERFORMANCE-BUDGET.md`.

---

## 5. Asset manifest (P0 / P1 / P2)

**P0 = the loop is unplayable without it. P1 = it is a city without it. P2 = polish, cut
first.** Phase column uses the blueprint's phases; nothing here is authorized to build.

| Pri | Asset | Phase | File | Parts | Depends on |
|---|---|---|---|---:|---|
| P0 | House exterior shell + stoop + porch | M2-A | `HouseExterior.rbxmx` | 75 | `Wall` `Roof` `Door` `Fac` |
| P0 | Lane (road, bands, kerbs, 2 lamps, 2 posts) | M2-A | `StreetBlock.rbxmx` | 83 | `RD` `SW` `Lamp` `Post` |
| P0 | Shared kit instances composed into zones | M2-A | (library, not a file) | 60 | `Bench` `Plant` `Bin` `Cable` `Sign` |
| P0 | Boards kiosk | M2-A | `CityBoards.rbxmx` | 28 | `Wall` `Roof` `Sign` `Post` |
| P0 | Anchor set | M2-A | `CityAnchors.rbxmx` | 22 | — |
| P1 | Plaza shell (disc, kerbs, fountain, 4 lamps) | M2-A | `TownCenter.rbxmx` | 62 | `Ftn` `Lamp` `SW` |
| P1 | Plaza props (benches, planters, bins, banners) | M2-B | (composed into `TownCenter`) | 87 | `Bench` `Plant` `Banner` |
| P1 | Skyline backdrop | M2-A | `CityBackdrop.rbxmx` | 9 | `Sky` |
| P1 | Future gate | M2-A | `CityGate.rbxmx` | 21 | `Wall` `Fac` `Door` |
| P1 | ElectroMart | M2-B | `ShopRowElectronics.rbxmx` | 120 | all |
| P1 | Warung Serba Ada | M2-B | `ShopUtility.rbxmx` | 50 | all |
| P1 | Event plaza permanent shell | M2-B | `EventPlaza.rbxmx` | 96 (budget 160) | `Stall` mounts `Banner` |
| P2 | Rumah Rapi | M2-B | `ShopFurniture.rbxmx` | 82 (budget 100) | all |
| P2 | Cosmetic room items ×10 | M2-B | (separate small prefabs) | 6–20 each | charged to the **room** budget, not the city (`07` §5) |
| P2 | Event pop-up dressing | M2-C | `EventPlaza_PopUp.rbxmx` | 60 | `Stall` `Banner_Cloth` |
| P2 | Gaya Depan cosmetics | M2-C | `ShopCosmetics.rbxmx` | 90 | all |
| P2 | Office District shell | M2-C | — | 400 | new kit variants |
| P2 | Transit interaction | M2-C | — | 10 | `City_TransitStop` |

---

## 6. What the kit does not include

- **No `ShopTemplate`.** No building-level module (§1).
- **No meshes, textures, decals, sounds, or uploaded images.** Same gate as every existing
  prefab.
- **No scripts, no remotes, no `BillboardGui`.** The prefab gate in
  `assets/world/DESIGN.md` §3.3 is not relaxed for the city.
- **No `Seat` instances** — no sitting animation exists, and a `Seat` without one is a
  broken interaction.
- **No neon signage**, no emissive panels, no glass curtain walls (§9 of the art direction).
- **No `Concrete` material** in M2-A/B (missing generator token; `OPEN-DESIGN-DECISIONS` D6).
- **No vehicles, doors that open, stairs, balconies, roofs the camera can enter**.

---

## 7. Authoring order for `tools/gen_city_prefabs.py`

The generator is authored in M2-A1, not here. Build the families in this order, because
each step is the first real use of the previous one:

1. `Wall` + `Roof` + `Plinth` — nothing else can be blockouted without walls.
2. `RD` + `SW` + `Kerb` — the lane must exist before anything can be seen from it.
3. `Ftn` + `Lamp` — the two landmarks; the plaza massing is meaningless without them.
4. `Sign` + `Counter` + `Fac` — the shop grammar.
5. `Bench` + `Plant` + `Bin` + `Cable` + `Post` — dressing, only after the massing passes
   the silhouette test.
6. `Sky` — last, because it is the only family that needs a camera test to validate
   (`WORLD-LAYOUT-AND-SIGHTLINES.md` §4.3).
7. `Stall` + `Banner_Cloth` — M2-C, not now.

Each step ends with a `rojo build` of both projects and a part count, because a kit family
that quietly costs 3× its estimate is the failure mode this document exists to prevent.
