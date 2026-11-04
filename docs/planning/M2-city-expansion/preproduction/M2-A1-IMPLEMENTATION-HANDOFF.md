# M2-A1 IMPLEMENTATION HANDOFF

> **Status**: Handoff package. **Nothing here is authorized to build yet.**
> `M2-A1 — City Coordinate Contract + Blockout` starts only after **M2-G1** (coordinate +
> anchor contract accepted) and **BS-14 Go**, per `07` §3 and `08` §5–§6.
> **Audience**: the implementation agent that builds the graybox city.
> **Rule**: everything needed is in this folder. If a value is not here or in
> `02-WORLD-STRUCTURE.md`, it is not decided — stop and ask, do not invent.

---

## 1. Preconditions (all must be true before the first line of code)

| # | Gate | Owner | Status |
|---|---|---|---|
| 1 | **BS-14 closed-beta Go** — city content must not appear in the beta candidate | Agent 1 + director | pending |
| 2 | **M2-G1** coordinate + anchor contract accepted, including the five corrections in `OPEN-DESIGN-DECISIONS.md` D1–D3, D5–D6 | director | pending |
| 3 | `tools/gen_world_prefabs.py` and `assets/world/` are **not** being edited by another agent | director | verify at start |
| 4 | `default.project.json` / `test.project.json` are not being edited by another agent (shared files — serialize) | director | verify at start |
| 5 | Latest `origin/master` fetched; branch cut from it | implementer | — |

**New worktree.** If Agent 1 is still active, work in a separate git worktree:
`git worktree add ../Agent-3 -b agent/M2-A1-city-blockout origin/master`.

---

## 2. Deliverables

| Path | Action | Notes |
|---|---|---|
| `tools/gen_city_prefabs.py` | **create** | deterministic generator, stdlib only, same conventions as `gen_world_prefabs.py` |
| `assets/world/city/HouseExterior.rbxmx` | create | shell + stoop + porch (§5) |
| `assets/world/city/StreetBlock.rbxmx` | create | road, bands, kerbs, 2 lamps, 2 signposts |
| `assets/world/city/TownCenter.rbxmx` | create | disc, rim, fountain massing, 4 lamps, 4 benches |
| `assets/world/city/CityBackdrop.rbxmx` | create | 9 parts, `Persistent` |
| `assets/world/city/CityGate.rbxmx` | create | piers, lintel, shutter |
| `assets/world/city/CityBoards.rbxmx` | create | kiosk massing |
| `assets/world/city/CityAnchors.rbxmx` | create | the 22 `City_*` markers only |
| `default.project.json` | **modify** | map the 7 new prefabs into `ServerStorage.WorldPrefabs` — **serialize** |
| `test.project.json` | **modify** | same mapping — **serialize** |
| `docs/evidence/m2-a1/*.png` | create | the 8 captures in `FIRST-EXIT-STORYBOARD.md` §6 |
| `docs/evidence/m2-a1/perf.json` + `.txt` | create | the measurements in `CITY-PERFORMANCE-BUDGET.md` §9 |
| `docs/planning/M2-city-expansion/02-WORLD-STRUCTURE.md` | modify **only if** a coordinate is proven wrong | a correction is a contract change: record it, do not silently patch |

**Not in M2-A1** (`10` scope): `CityService.luau`, door prompt logic, any `src/` edit, any
client script, any shop, any UI, any test file, any economy value.

---

## 3. Production order and dependency graph

Build in this order. Each step ends with a `rojo build` **and** a part count. A step that
overshoots its estimate by >20% stops the line.

```text
T1 contract constants + generator skeleton
 │
 ├─► T2 HouseExterior ────────────────┐
 │        │                            │
 │        └─► T4 StreetBlock ──────────┤
 │                   │                 │
 │                   └─► T5 TownCenter ┤
 │                            │        │
 │                            ├─► T6 CityBoards
 │                            │        │
 │                            └─► T7 CityGate
 │                                     │
 ├─► T8 CityBackdrop ─────────────────┤
 │                                     │
 └─► T9 CityAnchors ───────────────────┤
                                       ▼
                              T10 assemble Workspace.City
                                       │
                              T11 streaming + camera tests
                                       │
                              T12 captures + perf record
                                       │
                              T13 regression gate + handoff
```

| Task | Depends on | Parallel-safe with |
|---|---|---|
| T1 constants | — | — |
| T2 `HouseExterior` | T1 | T8, T9 |
| T4 `StreetBlock` | T1 | T8, T9 |
| T5 `TownCenter` | T1 | T6, T7 |
| T6 `CityBoards` | T1 | T5, T7 |
| T7 `CityGate` | T1 | T5, T6 |
| T8 `CityBackdrop` | T1 | all |
| T9 `CityAnchors` | T1 (needs final anchor table) | all |
| T10 assemble | T2, T4, T5, T6, T7, T8, T9 | — |
| T11 tests | T10 | — |
| T12 captures | T11 | — |
| T13 gate | T12 | — |

**The prefab order is not arbitrary.** The house must exist before the lane is judged
(the lane's read is defined by the house at one end), and the lane must exist before the
plaza (the plaza's first impression is the end of the corridor).

---

## 4. Generator requirements (`tools/gen_city_prefabs.py`)

Copy `gen_world_prefabs.py`'s structure verbatim: `PALETTE`, `MATERIALS`, `item`,
`vector`, `color`, `part`, `model`, `anchor`, `light`, `rounded`, one `build_*()` per
prefab, `main()` writing `.rbxmx`. Do not import it — a second generator file keeps the
city's conventions auditable and leaves `gen_world_prefabs.py` untouched (`10` Files).

### 4.1 Required constants

```python
GRID = 8                    # structure module
MAJOR = 16                  # zone origins, street centreline, plaza centre, gate
GRADE = 0                   # Y of all walkable ground
LANE      = dict(x0=-16, x1=16, z0=16, z1=64)        # 32-wide road
BAND      = dict(w=8)                                 # 8-stud band each side
LOT       = dict(w=24, d=24)                          # shop lot
PLAZA     = dict(cx=0, cz=112, r=40, fountain_r=8)
GATE      = dict(x0=-8, x1=8, z0=160, z1=176)
HOUSE     = dict(half=12.0, wall=0.5, shell_offset=0.6, shell_thickness=0.5,
                 door_x=-6.0, door_w=3.7, door_h=7.3,door_z=11.6, stoop_z=16.0,
                 parapet_y=11.9, porch_face_z=13.35)
BACKDROP  = dict(x0=-120, x1=120, z0=-192, z1=-112)   # proposed; see D3
TOWER     = dict(x=-34.3, z=-152)                     # window-centre sightline
```

### 4.2 Required self-check

`main()` must assert and print:

1. every zone origin is a multiple of `MAJOR` (where the contract says 16);
2. every structure edge lands on a multiple of `GRID`;
3. the shell's south face is at `HOUSE["porch_face_z"]` and the leaf is at `stoop_z ± 0.09`;
4. the fountain centre is `(0, 112)` and its radius is 8;
5. the backdrop's `x` span brackets the window aperture's visible slice
   (`-65.3 … -3.3` at `z = -152`) — fail loudly if it does not, because that is the whole
   point of the backdrop;
6. the emitted part count per prefab, and the total, printed as `prefab: N parts`.

### 4.3 Rules the generator must enforce

- `Anchored = true` on every part (no exceptions).
- Structural parts `CanCollide = true`, `CanQuery = true`; props `false`/`false`
  (`MODULAR-ASSET-KIT.md` §2.3).
- Every invisible marker: `Transparency = 1`, `CanCollide/CanTouch/CanQuery = false`.
- No `Script`/`LocalScript`/`ModuleScript`/`Remote*`/`BillboardGui`/`Decal`/`Texture`/
  `MeshPart` descendants — same gate as `assets/world/DESIGN.md` §3.3.
- No `SurfaceGui` in M2-A1 (signs are M2-A1-adjacent but the MeshGui budget belongs to
  M2-B dressing; a blockout with signs is not a blockout).
- Materials: `SmoothPlastic`, `Wood`, `Metal`, `Fabric`, `Glass`, `Neon` only — **no
  `Concrete`** (no token exists; `OPEN-DESIGN-DECISIONS.md` D6).
- No part dimension below `0.05` studs.

### 4.4 Prefab pivots

| Prefab | Pivot | Placement |
|---|---|---|
| `HouseExterior` | `(0, 0, 0)` (room origin) | identity |
| `StreetBlock` | `(0, 0, 40)` | `CFrame.new(0, 0, 40)` |
| `TownCenter` | `(0, 0, 112)` | `CFrame.new(0, 0, 112)` |
| `CityBoards` | `(0, 0, 68)` | `CFrame.new(0, 0, 68)` |
| `CityGate` | `(0, 0, 168)` | `CFrame.new(0, 0, 168)` |
| `CityBackdrop` | `(0, 0, -152)` | `CFrame.new(0, 0, -152)` |
| `CityAnchors` | `(0, 0, 0)` | identity (absolute coordinates) |

**Geometry is authored in world coordinates inside each prefab, with the pivot at the zone
origin.** Placement is then a single `CFrame.new(origin)` — never hand-nudged (`05` §1.1).

---

## 5. Coordinate checklist

Tick every line in Studio, not in the source.

### Z0 — house
- [ ] room still 24 × 24 × 10, all four walls at `±12`, thickness 0.5; the room's wall
      outer face is therefore `z = 12.25`
- [ ] shell inner face at **12.85** (12.25 + 0.6 offset), shell outer face at **13.35**
      (0.5 thick) — the 0.6 gap is what prevents z-fighting with the interior walls
- [ ] doorway aperture `x -7.85…-4.15`, `y 0…7.3`, aligned to `Door`
- [ ] `City_HomeDoor` leaf at `(-6, 3.65, 16)`, `3.7 × 7.3 × 0.18`, opaque, collidable
- [ ] porch cheeks at `x -8.5…-7.85` and `-4.15…-3.5`, `z 13.35…16`
- [ ] stoop slab `z 12.85…16`, top at `y = 0`
- [ ] parapet top at `y = 11.9`, **no roof plane**
- [ ] `City_DoorPromptInterior` at `(-6, 3.65, 8)`, invisible
- [ ] `City_Spawn` at `(-6, 0.6, 20)`; facing per D11 (default `+Z`, recommended `−Z`)

### Z1 — lane
- [ ] road `x -16…+16`, `z 16…64`, top `y = 0`
- [ ] bands `x -24…-16` and `+16…+24`, 0.4 riser
- [ ] kerbs on the road edge, `cream` edge line at `x = ±16`
- [ ] 2 lamp posts, 2 signpost anchors at the coordinates in `WORLD-LAYOUT` §9
- [ ] 6-stud clear path down the centre, no prop within it

### Z2 — plaza
- [ ] disc centre `(0, 112)`, `r = 40`
- [ ] fountain centre `(0, 112)`, basin `r = 8`, rim top `y = 1.6`
- [ ] 8-stud clear ring around the fountain
- [ ] 4 lamps at `(±20, ·, 96)` and `(±20, ·, 128)`
- [ ] boards apron `z 64…72` paved before the disc starts at `z = 72`
- [ ] transit shelter `(24, 96)` **inside the paved disc** — see D9 before dressing it

### Z6 / Z7
- [ ] kiosk 12 studs wide at `x +4…+16`, `z 65…71` (proposed; default is `x -12…+12`)
- [ ] gate piers at `x -13…-9` and `+9…+13`, 18 studs tall (they sit outside Z7's 16-stud
      walkable aperture — they are the structure the aperture is cut through)
- [ ] shutter spans `x -8…+8`, 70% closed, 4-stud gap at the bottom, `ink` behind it

### Backdrop
- [ ] `z -192…-112`, `x -120…+120` (proposed), 9 parts
- [ ] tower at `(-34.3, ·, -152)`, 120 studs tall
- [ ] apron 1 part at `y = -0.1`, `600 × 0.2 × 200`, non-collide, `CastShadow = false`
- [ ] nothing collidable, queryable or reachable

### Anchors
- [ ] 22 markers present, each exactly once, none sharing a name with the bedroom's 12
- [ ] `City_*` prefix on all of them
- [ ] all invisible, anchored, non-colliding, non-touchable, non-queryable

---

## 6. Door safety tests (must pass before handoff)

The frozen `Door` and the room are the highest-risk objects in the repository. These are
**assertions the implementer writes as a throwaway Studio command or a spec** — M2-A1 adds
no test files, so run them interactively and paste the output into the evidence file.

| # | Test | Assertion |
|---|---|---|
| D-1 | **Frozen door untouched** | `Door.Size == Vector3.new(3.7, 7.3, 0.18)`, `Door.Position == Vector3.new(-6, 3.65, 11.6)`, `Door.CanCollide == true`, `Door.Transparency == 0`, `Door.Parent.Name == "Bedroom"` |
| D-2 | **Room part count unchanged** | the cloned room still contains **155** `BasePart`s |
| D-3 | **No prompt on the frozen door** | `Door:FindFirstChildOfClass("ProximityPrompt") == nil` |
| D-4 | **Prompt identity** | the exit prompt's parent is `Directory.City_Anchors.City_DoorPromptInterior`, not a zone model |
| D-5 | **Distance validation** | a request from 13 studs is rejected; from 11 studs is accepted (server constant ≤ 12) |
| D-6 | **Destination clearance** | `City_Spawn` is ≥ 4 studs clear of the shell, the `Door`, the `City_HomeDoor` leaf, and every prop: cast a 3-stud sphere overlap at `(-6, 3, 20)` and assert empty |
| D-7 | **Ground check** | a downward ray from `(-6, 6, 20)` hits the stoop/grade within 0.5 studs of `y = 0` |
| D-8 | **No pass-through** | walking south into the `Door` at `z = 11.6` stops the character; walking north from the stoop into `City_HomeDoor` stops it |
| D-9 | **Return destination** | indoors destination is `Spawn (0, 0.6, 6)`, and the camera resolve is identical to a fresh join |

D-1 and D-2 are the ones that catch the real failure: an agent that "just nudges the door
2 studs to make the shell line up". That is the single most expensive mistake available in
this milestone.

---

## 7. Visual acceptance criteria

The blockout passes M2-G2 only if all of these are true **in genuine Studio Play captures**:

| # | Criterion | Shot |
|---|---|---|
| V1 | From the stoop at spawn state, the house reads as a house: parapet line, eave, awning, porch void, door | S4 |
| V2 | From the stoop, the kiosk is identifiable at 57 studs | S5 |
| V3 | From the plaza's north edge, the fountain is the centre of the frame and nothing occludes it | S7 |
| V4 | From the plaza, both shop rows read as rows (mass + band + recess), not as walls | S7 |
| V5 | From `CameraFocus`, the window shows **backdrop silhouettes, not sky** | window |
| V6 | No camera clipping at the door, the porch, or the plaza at three pitches (−20°, 0°, +20°) | S4/S10 |
| V7 | No gap between the shell and the room's walls; no z-fighting on any plane | S4 close |
| V8 | The gate frames the horizon from the plaza and is not walkable past | S7 |
| V9 | Nothing you can see from the window is city geometry | window |
| V10 | The lane's far end shows exactly one bright object | S5 |

---

## 8. Measurements to capture

Run in Studio (`execute_luau`, `Edit` mode) **after** `Workspace.City` is assembled:

```lua
local city = workspace:FindFirstChild("City")
local parts, transparent, guis, lights, shadowed = 0, 0, 0, 0, 0
for _, d in ipairs(city:GetDescendants()) do
    if d:IsA("BasePart") then
        parts += 1
        if d.Transparency < 1 then transparent += 1 end
    elseif d:IsA("SurfaceGui") then
        guis += 1
    elseif d:IsA("PointLight") then
        lights += 1
        if d.Shadows then shadowed += 1 end
    end
end
print(("CITY parts=%d transparent=%d surfacegui=%d lights=%d shadowed=%d")
    :format(parts, transparent, guis, lights, shadowed))

for _, zone in ipairs(city:GetChildren()) do
    local n = 0
    for _, d in ipairs(zone:GetDescendants()) do
        if d:IsA("BasePart") then n += 1 end
    end
    print(("%-28s %d"):format(zone.Name, n))
end
```

Record into `docs/evidence/m2-a1/perf.json`:

```json
{
  "measured_at": "<ISO timestamp>",
  "place": "build/BuzzerSimulator.rbxlx",
  "lighting_technology": "<read Lighting.Technology>",
  "streaming_enabled": null,
  "city": {"parts": 0, "transparent": 0, "surfacegui": 0, "lights": 0, "shadowed": 0},
  "zones": {},
  "fps": {"desktop": [], "mobile_portrait": [], "mobile_landscape": []},
  "walk_times_s": {"door_to_kiosk": 0, "door_to_fountain": 0, "door_to_gate": 0},
  "estimates_vs_measured_note": "estimates from CITY-PERFORMANCE-BUDGET.md §3"
}
```

**`streaming_enabled` and `lighting_technology` are not optional.** Both are currently
unknown (findings F5 and §6.1) and every downstream performance claim depends on them.

---

## 9. Streaming tests

Given the recommendation to keep streaming **off** (`CITY-PERFORMANCE-BUDGET.md` §7):

| # | Test | Expected |
|---|---|---|
| S-1 | With streaming off, walk the whole city | no pop, nothing missing, backdrop visible from the window |
| S-2 | Toggle `StreamingEnabled = true` on a copy of the place, `StreamingTargetRadius 256` | zones appear whole, never half-built |
| S-3 | With streaming on, stand at the window indoors | backdrop still visible (it is `Persistent`) |
| S-4 | With streaming on, walk out the door | record whether the destination zone is present at the moment of the `CFrame` set |
| S-5 | Confirm `ModelStreamingMode` on each zone | `Atomic`; backdrop `Persistent` |

S-4 is the measurement that decides D4. Record it either way, even if streaming ships off.

---

## 10. Mobile screenshot requirements

| Capture | Device | Resolution | Must show |
|---|---|---|---|
| stoop, spawn state | iPhone 14 emulation, portrait | 390 × 844 | house facade, touch controls visible |
| stoop, spawn state | iPhone 14 emulation, landscape | 844 × 390 | house facade |
| lane | portrait | 390 × 844 | the corridor and its single bright end |
| plaza | portrait | 390 × 844 | fountain, paving banding |
| window, from `CameraFocus` | desktop | 1280 × 720 | silhouettes only |

Portrait captures need `PlayerGui.ScreenOrientation = Portrait` set on the review player.
That is a temporary review setting, not production code (`assets/ASSET-MANIFEST.md` §BS-05).

---

## 11. Integration files and ownership

| File | Owner | Serialize? |
|---|---|---|
| `tools/gen_city_prefabs.py` (new) | this task | no (new file) |
| `assets/world/city/*.rbxmx` (new dir) | this task | no (new files) |
| `default.project.json` | **shared** | **yes** |
| `test.project.json` | **shared** | **yes** |
| `src/server/Bootstrap.server.luau` | **shared** — M2-A4, not M2-A1 | yes |
| `src/server/CityService.luau` | M2-A4, not M2-A1 | no (new) |
| `tests/Specs/CityService.spec.luau` | M2-A4, not M2-A1 | no (new) |
| `docs/planning/M2-city-expansion/02-WORLD-STRUCTURE.md` | director | only on a proven coordinate error |

The Rojo mapping to add (both projects, same block):

```json
"CityHouseExterior": { "$path": "assets/world/city/HouseExterior.rbxmx" },
"CityStreetBlock":   { "$path": "assets/world/city/StreetBlock.rbxmx" },
"CityTownCenter":    { "$path": "assets/world/city/TownCenter.rbxmx" },
"CityBoards":        { "$path": "assets/world/city/CityBoards.rbxmx" },
"CityGate":          { "$path": "assets/world/city/CityGate.rbxmx" },
"CityBackdrop":      { "$path": "assets/world/city/CityBackdrop.rbxmx" },
"CityAnchors":       { "$path": "assets/world/city/CityAnchors.rbxmx" }
```

Distinct names — never replace `Bedroom`, `OldCRT`, `PhoneCheap`, `PhoneFast`, `PCRumah`,
`WorkerDesk1/2`, `Trainee1/2` (`08` §6 rule 4).

---

## 12. Known blockers and open questions

| # | Blocker | Blocks | Resolution |
|---|---|---|---|
| B1 | BS-14 Go not issued | the whole milestone | director |
| B2 | M2-G1 not accepted | authoring any prefab | director |
| B3 | **F1** `City_HomeDoor` floats 2.56 studs off the shell | the house prefab | build the porch (3 parts) — recommended, no coordinate change |
| B4 | **F2** the kiosk occludes the fountain from the stoop | the kiosk + acceptance #2 | shift the kiosk +10 east, or reword the acceptance |
| B5 | **F3** the approved backdrop covers 0° of the window aperture | V-03 closure, V5, V9 | mirror to `x -120…+120`, tower at `x = -34.3` |
| B6 | **F6** shop prompts 12 studs behind the counter line | M2-B only (prompts are M2-A4) | move to `x = ±58` |
| B7 | `Lighting.Technology` unrecorded | any shadow budget, and the bedroom's shadow claims | read it in Studio, record it |
| B8 | Streaming settings absent from both Rojo projects | streaming behaviour, S-4 | keep off, record the decision (D4) |
| B9 | No `Concrete` token in `MATERIALS` | any concrete surface | do not use `Concrete` (D6) |
| B10 | 22 anchor parts outside the 448 | the 450 ceiling | cut 22 P2 dressing parts, or approve 480 (D5) |
| B11 | The fade requires a client `ScreenGui` | the door transition look | instant cut in M2-A; fade in M2-A4 with a client controller |

---

## 13. Definition of done

- [ ] all seven prefabs + `CityAnchors` generated, deterministic, rebuildable
- [ ] `rojo build` passes for **both** projects
- [ ] M2-A1 part count ≤ **150** (estimate 122), and ≤ 450 hard stop
- [ ] every line of §5 ticked in Studio
- [ ] D-1 … D-9 pass, output pasted into evidence
- [ ] V1 … V10 pass on genuine captures
- [ ] `perf.json` filled, including `lighting_technology` and `streaming_enabled`
- [ ] S-1 … S-5 recorded
- [ ] the existing test suite runs unchanged, zero new failures (`10` T9)
- [ ] `git status` shows only: `tools/gen_city_prefabs.py`, `assets/world/city/*`,
      the two project files, and `docs/evidence/m2-a1/*`
- [ ] **no** `src/`, `tests/`, `assets/world/` (existing), `Catalog.luau`,
      `EconomyService.luau`, `WorldService.luau`, `ProfileStore.luau`, `NetRouter.luau` edit

---

## 14. What to stop and ask about

Stop the line and ask the director if any of these happens — do not improvise:

1. A coordinate in `02` cannot be built without moving a zone or the door.
2. The blockout exceeds 180 parts.
3. The window still shows sky after the backdrop is placed as approved.
4. The house cannot be made to read as a house at 122 parts.
5. The door transition would require touching the frozen `Door` part.
6. Two prompts stack at the kiosk/fountain cluster.
7. Anything suggests adding a shop, a UI surface, a client script, or an economy value to
   make the blockout "feel finished".
