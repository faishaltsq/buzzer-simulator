# WORLD LAYOUT & SIGHTLINES

> **Status**: Pre-production. The geometry below is the approved contract; every number
> that departs from it is marked **FINDING** and is not applied here.
> **Source of truth**: `02-WORLD-STRUCTURE.md` (coordinates), `03-ZONE-SPECIFICATIONS.md`
> (extents). This document draws them and audits them — it never re-derives them.
> **Board**: `CITY-MASTERPLAN.excalidraw` (+ `-preview.svg`, `-preview.png`), generated
> from those tables by `gen_masterplan_board.py`.

---

## 1. How to read the board

The board is **to scale, 1:1 in studs**, at 6 px per stud. It is not a diagram: distances
measured on it are real distances.

| Element | Meaning |
|---|---|
| Cream / grey / green field | a zone's **walkable extent** (the contract rectangle), labelled `Z0…Z7` with its size in studs |
| Dark band at the top | the north skyline backdrop, `z -192…-112`, **non-walkable**; drawn at the proposed `x -120…+120` (finding **F3**) |
| Grey wash above the house | rear yard + horizon apron, `z -200…-24` — the reason the skyline has a floor |
| Solid coloured rectangle | a **building footprint** (shell + facade depth) |
| Pale circle, r = 40 | the plaza disc, centre `(0, 0, 112)` |
| Blue-grey circle, r = 8 | the fountain basin |
| Amber line | the **primary player route**, door → boards → fountain → gate, with side branches to both shop rows and the event plaza |
| Thin sage arrow | a **sightline** (S1–S7); dashed = a sightline that does not exist yet or is under audit |
| Ring (navy) | a `City_Zone_*` root anchor |
| Dot (brick) | a `City_Prompt_*` anchor |
| Dot (amber) | `City_Spawn` |
| Dot (metal) | `City_TransitStop` |
| Small brick dots | the six `City_Signpost_*` anchor positions |

The board carries **eight zone extents, ten building footprints, one plaza, one fountain,
18 anchor positions and 12 storytelling props' hosts**. It does not draw props at prop
scale — at 6 px/stud a 0.4-stud sign is two pixels and would read as noise.

Regenerate with:

```bash
python docs/planning/M2-city-expansion/preproduction/gen_masterplan_board.py
```

The generator reads nothing at runtime; the coordinate tables are literal in the script
and cite their source. If the contract changes, the table changes in both places.

---

## 2. The plan, restated as a checklist

Not a copy of `02` §3 — the implementation checklist an agent can tick off.

| # | Constraint | Value | Verified against |
|---|---|---|---|
| 1 | Walkable bounding box | `x ∈ [-136, +80]`, `z ∈ [-24, +176]` → **216 × 200** | zone extents sum correctly on the board |
| 2 | Grade | `Y = 0` flat, no ramps/stairs | `05` §1.5 |
| 3 | Structure grid | 8-stud module, 16-stud major lines | every zone edge is a multiple of 8 |
| 4 | Lane section | 32-stud road `x -16…+16` + 8-stud band each side | `02` §3, `10` T3 |
| 5 | Lot | 24 wide × 24 deep | `02` §3 |
| 6 | Building height | 12–16 studs; nothing walkable > 20 | `05` §3.3 |
| 7 | Plaza | centre `(0,0,112)`, disc r = 40, fountain r = 8 | `02` §3, `03` Z2 |
| 8 | Bedroom | 24 × 24 at origin, **unchanged** | `Bedroom.rbxmx`, 155 parts |
| 9 | Door | `(-6, 3.65, 11.6)`, `3.7 × 7.3 × 0.18`, `CanCollide = true` | frozen, never touched |
| 10 | Prompts | activation 10 studs, server validation ≤ 12 | `WorldService` constants |

---

## 3. Route: measured, not estimated

Straight-line distance from the frozen `Door` anchor `(-6, 11.6)` at default WalkSpeed
(16 studs/s), no obstacles. These are **arithmetic**, not measurements in Studio — the
blockout must re-time them on foot, because a straight line ignores the kiosk, the
fountain and the plaza edge.

| Destination | Studs | At 16 studs/s | Blueprint estimate | Status |
|---|---:|---:|---:|---|
| Mission board `(0, 68)` | 56.7 | 3.54 s | 3.5 s | **matches** |
| Fountain `(0, 112)` | 100.6 | 6.29 s | 6.3 s | **matches** |
| Future gate `(0, 168)` | 156.5 | 9.78 s | — | new |
| Event plaza centre `(-108, 134)` | 159.3 | 9.96 s | 9.9 s | **matches** |
| ElectroMart front `(56, 84)` | 95.3 | 5.96 s | — | new |
| Rumah Rapi front `(-56, 84)` | 88.0 | 5.50 s | — | new |
| Transit stop `(24, 96)` | 89.6 | 5.60 s | — | new |
| Cosmetics front `(56, 108)` | 114.6 | 7.16 s | — | new |
| Utility front `(56, 132)` | 135.4 | 8.46 s | — | new |

**Read this as a pacing statement, not a performance claim.**

- The *entire* city is reachable inside **10 seconds** from the door. That is inside the
  13–18 s post reveal window (`01` §D.7), so leaving never wastes a reveal.
- The **board at 3.5 s** is the shortest errand in the game and must never take longer.
  If the blockout measures > 5 s on foot, the kiosk is in the wrong place.
- The **utility lot at 8.5 s** is the longest shop errand and is the reason the return
  chip exists (`06` §7) — but only as a hint, never as a free teleport.

---

## 4. Sightlines

### 4.1 The three that must work

| ID | From | To | Distance | Requirement |
|---|---|---|---|---|
| **S1** | stoop `(-6, 16)`, eye 5 | boards kiosk `(0, 68)` | 57 studs | kiosk readable, prompt target identifiable, nothing between |
| **S2** | stoop `(-6, 16)`, eye 5 | fountain `(0, 112)` | 100 studs | water plane and rim visible past the kiosk |
| **S5/S6** | plaza centre `(0,112)` | both shop-row fronts at `x = ±56` | 56–64 studs | at least one awning + sign per row reads as a shop, not a wall |

### 4.2 FINDING F2 — the kiosk sits exactly on the S2 line

The boards kiosk (Z6, `x -12…+12`, `z 64…72`) and the fountain (`x -8…+8`, `z 112`) are
both centred near `x = 0`, and the door is at `x = -6`. From the stoop, the kiosk's
angular span **contains** the fountain's.

| Kiosk width | Kiosk angular span from `(-6, 5)` | Fountain span (r = 8, at 92 studs) | Occluded |
|---|---|---|---|
| `x -12…+12` (full Z6) | −7.1° … +20.6° | −1.2° … +8.7° | **100%** |
| `x -6…+6` (12-stud kiosk, centred) | 0.0° … +14.0° | −1.2° … +8.7° | **88%** |
| `x +4…+16` (12-stud kiosk, **+10 east**) | +11.8° … +24.6° | −1.2° … +8.7° | **0%** |

`07` §3 acceptance #2 asks that "from the stoop, the boards kiosk and fountain are
visible". With the approved layout that is geometrically impossible: **the kiosk is
directly between the player and the landmark.**

**Proposed correction (needs M2-G1 approval):** build the kiosk **12 studs wide at
`x +4…+16`** and move `City_Prompt_Boards` from `(0, 3, 68)` to `(10, 3, 68)`. Z6's zone
extent does not change — it is a zone, not a footprint. Result: the kiosk is 57 studs
ahead and slightly right (still the first thing you notice), and the fountain opens up
to its left the moment you clear the lane.

**Default if unanswered:** keep the approved position, accept that the fountain is
discovered *after* passing the kiosk, and **reword the acceptance criterion** to a
sequence ("kiosk visible from the stoop; fountain visible as you pass it"). Do not build
a kiosk wide enough to block the plaza.

### 4.3 FINDING F3 — the approved backdrop is invisible from the desk

`02` §3.1 and `03` place the skyline at `x +16…+160`, `z -192…-112`. The window aperture
is `x 0…6` at the north wall (`WindowGlass` at `(3, 5.5, -12.08)`), and the room's
camera anchor `CameraFocus` is at `(7, 5.5, 3)` — i.e. **east of the entire window**.

Aperture, measured from `CameraFocus` looking `-Z` (negative = west of the axis):

| Edge | Ray | Angle |
|---|---|---|
| west jamb `x = 0` | `(7,3) → (0,-12)` | **−25.0°** |
| east jamb `x = 6` | `(7,3) → (6,-12)` | **−3.8°** |

Backdrop angular coverage on the `z = -152` plane (155 studs from the camera):

| Backdrop X | Angular span | Overlap with the aperture |
|---|---|---|
| **approved** `+16…+160` | **+3.3° … +44.6°** | **0.00°** |
| proposed `-120…+120` | −39.3° … +36.1° | **21.2° of 21.2° — full** |

So the skyline the plan says "fixes V-03" covers **none** of what the window can see.
The window would still show empty sky to the west, and the tower would sit behind the
player's right shoulder, inside the room.

**Proposed correction:** mirror the backdrop to `x -120…+120` (keep `z -192…-112`,
≤ 9 parts) and place the **Agency Tower mass centred at `x = -34.3`** on the `z = -152`
plane — that is the exact centre of the window's visible slice `x -65.3…-3.3`.
The tower then appears dead centre in the window from the desk, which is the whole point
of `09` §3.

### 4.4 FINDING F4 — the exit spawn faces the camera into the doorway

`City_Spawn` is `(-6, 0.6, 20)` **facing `+Z`** (`02` §7). The default Roblox chase camera
booms ~12 studs behind the subject, i.e. toward `z ≈ 8` — through the exterior door leaf
(`z 15.91…16.09`), the shell, and the room's south wall. The camera resolves this by
stopping at the first obstruction, ≈ 4 studs behind the player, so the first frame
outside is a tight over-the-shoulder with a door filling the lower third. Functional;
not the reveal `FIRST-EXIT-STORYBOARD.md` describes.

Two options, both cheap:

| Option | Change | First frame | Cost |
|---|---|---|---|
| **A (recommended)** | spawn faces **`-Z`** (toward the house) | camera booms into the open lane, ~12 studs south: the player small in frame with their own house facade, stoop, awning and house number filling it — then they turn | one anchor orientation value |
| B | spawn at `(-6, 0.6, 27)` facing `+Z` | camera at `z ≈ 15` still hits the door leaf; frame improves only slightly and the player now starts 7 studs into the lane, losing the stoop beat | one anchor position value |
| C | keep as approved | tight shot; the reveal happens when the player turns | zero |

Option A is a **facing** change, not a position change: the anchor stays at `(-6, 0.6, 20)`
and the unlock contract is untouched. It also puts the "Masuk Rumah" prompt directly in
front of the player on arrival, which is honest — you *can* go straight back in.

**Default if unanswered:** Option C. The first frame is then a close-up and the storyboard
shot S4 is delivered as a *turn*, not an arrival.

---

## 5. Section through the door (the hardest 5 studs in the city)

All values in studs, `+Z` to the right (south).

```text
  room interior            wall      shell        stoop / porch recess              lane
  z = 8                    z = 12    z = 13.35    z = 16                            z = 20
    │                        │          │            │                                │
    │   Door (frozen)        │          │        City_HomeDoor                        │
    │   z 11.51…11.69        │          │        z 15.91…16.09                        │
 ───┼───────┬────────────────┼──────────┼────────────┬────────────────────────────────┼──
    │       │◄── 0.5 ──►│◄─ 0.6 ─►│◄── 2.56 ──►│                                │
    │            wall       gap       porch recess                            floor Y=0
    │
  Door prompt interior   z = 8      (invisible anchor, 3.6 studs in front of the leaf)
  City_Spawn             z = 20
```

Facts this section encodes:

1. **The room's south wall is solid.** `WallSouth` is one `24 × 10 × 0.5` part at
   `z = 12`; the `Door` is a collidable **prop standing in front of it**, at
   `z 11.51…11.69`. There is no hole. (Verified in `assets/world/Bedroom.rbxmx` and
   `tools/gen_world_prefabs.py` `build_bedroom`.)
2. Therefore the "cut a doorway at `x -7.85…-4.15`, `y 0…7.3`" instruction in `02` §7.1
   and `10` T2 is **cosmetic**: the aperture is a niche in the new shell, and behind it
   is 0.6 studs of void and then the back of the frozen plaster wall. Nobody sees
   through it because nobody can go through it.
3. The exterior leaf must be **closed, opaque, and collidable** — otherwise the niche
   shows raw plaster and the house reads as a facade with a hole punched in it.
4. **FINDING F1 — the leaf floats.** The shell's outer face is at `z = 13.35` (0.6 offset
   + 0.5 shell thickness). `City_HomeDoor` is at `z = 16`. The leaf therefore stands
   **2.56 studs off the wall**, held by nothing.

**Fix (keeps the approved coordinate):** build the stoop as a **recessed porch**: two
cheek walls at `x -8.5…-7.85` and `x -4.15…-3.5`, `z 13.35…16`, plus a soffit at
`y 7.9`. That is **3 extra parts** in `HouseExterior` (already inside the 90-part
budget — see `CITY-PERFORMANCE-BUDGET.md` §3) and it gives the door a real 2.5-stud-deep
threshold, which is also what makes the "Keluar Rumah" moment read as stepping out of a
house rather than teleporting onto a pavement.

**Alternative (contract change, not recommended):** move `City_HomeDoor` to
`z = 13.45` and `City_Spawn` to `z = 19`. Cheaper geometrically, but it removes the only
architectural reason the stoop exists.

### 5.1 Prompt reachability at the door

| Prompt | Anchor | Player stands | Distance | Within 10? |
|---|---|---|---:|---|
| `Keluar Rumah` | `(-6, 3.65, 8)` | room centre `(0, 0.6, 6)` | 6.4 | yes |
| `Keluar Rumah` | `(-6, 3.65, 8)` | at the door `(-6, 0.6, 11)` | 2.7 (planar) | yes |
| `Masuk Rumah` | `(-6, 3.65, 16)` | `City_Spawn` `(-6, 0.6, 20)` | 4.0 | yes |
| `Masuk Rumah` | `(-6, 3.65, 16)` | lane, 10 studs out | 10.2 | **no — correct**, the prompt is a door prompt |

The interior prompt at `z = 8` is 3.6 studs inside the leaf, so a player standing *at*
the door still sees it (2.7 studs) and cannot trigger it from the far side of the room
(6.4 studs at the room centre, 13+ at the desk). That is the intended behaviour: the
prompt exists where the door is.

---

## 6. Camera behaviour (no controller changes in M2-A0)

The city is designed **against the stock camera only**. No `CameraType.Scriptable`, no
per-frame bindings, no occlusion fades (`06` §1: no new full-screen UI, no camera code in
M2-A).

| Situation | What the stock camera does | What the art must do |
|---|---|---|
| Standing on the stoop | boom extends south into the open lane, unobstructed | nothing may occupy `x -8…-2`, `z 17…24` above y 0 — keep the spawn throat clear of props |
| Walking down the lane | boom into the lane behind, fine | lamp posts and signposts are thin and `CanCollide = false`, so the boom passes |
| At a shop front | boom may hit the awning above the player | **awnings, banners, signs and cables are non-colliding props** (`03` rule 5), so the stock camera ignores them; do not make them `CanCollide` to "fix" anything |
| Under a doorway | boom pinches to ~2 studs | acceptable; never place a prompt inside a 3-stud-wide opening |
| In the plaza | boom free | the fountain is 2 studs tall; the camera may pass over it |
| Fighting the parapet | boom above the room may sit behind the 11.9 parapet | parapet is 0.5 thick; verify in A1 that the orbit never shows the parapet's back face as a black wall |

**Hard rule:** nothing structural may be added above `y = 8.2` within 3 studs of any
walkable path, except the awning system (which is non-colliding). This is the one
constraint that keeps the stock camera working for free.

---

## 7. Visibility matrix

"What you must see / must not see", extended from `02` §8.

| From | Looking | Must see | Must not see |
|---|---|---|---|
| `CameraFocus` `(7,5.5,3)` | `-Z` through the window | skyline slabs, one tower, haze | any city geometry, any shop back, the plaza |
| `Spawn` `(0,0.6,6)` | `+Z` | the door, its jambs, the wall | the street through the door (the wall is solid) |
| Stoop `(-6,·,16)` | `+Z` | lane, lamp, boards kiosk at 57 studs, **fountain past it (F2)** | the bedroom interior, any shell seam |
| Stoop, turned around | `-Z` | the house: door, awning, number, stoop, scooter | the parapet's back face, the shell/wall gap |
| Plaza `(0,·,112)` | `±X` | both shop rows: one awning + one sign each | the backs of the shop masses, the lot seams |
| Plaza | `+Z` | the gate at 56 studs, framing the horizon | a walkable path past the gate |
| Plaza | `-Z` | the lane leaving north, the kiosk's back | the bedroom's south facade (it is 100+ studs away and occluded by the kiosk — verify) |
| Event plaza `(-108,·,134)` | `+X` | the 24-stud connector back to the plaza | the east shop row (128 studs, through the plaza — acceptable if occluded) |

---

## 8. Streaming grouping on the board

How the drawn rectangles map to `Workspace.City` children (`02` §6):

| Board element | Streaming root | `ModelStreamingMode` |
|---|---|---|
| Z0 house + stoop + porch | `City_Zone_Home` | `Atomic` |
| Z1 lane | `City_Zone_Street` | `Atomic` |
| Z2 plaza + fountain + transit shelter | `City_Zone_TownCenter` | `Atomic` |
| Z3 three lots (`z 72–144`) | `City_Zone_ShopEast` | `Atomic` |
| Z4 one lot (`z 72–96`) | `City_Zone_ShopWest` | `Atomic` |
| Z5 stage + connector | `City_Zone_EventPlaza` | `Atomic` |
| Z6 kiosk | inside `City_Zone_TownCenter` | (inherits) |
| Z7 gate | `City_Zone_FutureGate` | `Atomic` |
| Dark band | `City_Backdrop` | `Persistent` |
| all `City_*` anchors | `City_Anchors` (Folder) | n/a |

**Anchors are deliberately outside every zone model.** A prompt parented inside an
`Atomic` model would be re-created every time the model streams; keeping anchors in
their own folder means the server resolves and creates prompts exactly once per server,
and a zone streaming in can never produce a duplicate prompt.

> **FINDING F5 (streaming is currently unconfigured):** neither `default.project.json`
> nor `test.project.json` declares a `Workspace` node, so `StreamingEnabled` is at its
> place default (**false**) and none of the `ModelStreamingMode` values above take
> effect. See `CITY-PERFORMANCE-BUDGET.md` §7 for the recommendation (keep streaming
> off for a 216 × 200 city) and `OPEN-DESIGN-DECISIONS.md` D4.

---

## 9. Anchor register (A-numbers used on the board)

| # | Anchor | X | Z | Kind | Zone |
|---|---|---:|---:|---|---|
| A1 | `City_Spawn` | −6 | 20 | spawn | Z0 |
| A2 | `City_HomeDoor` | −6 | 16 | physical door | Z0 |
| A3 | `City_DoorPromptInterior` | −6 | 8 | prompt host (invisible) | Z0 |
| A4 | `City_Zone_Street` | 0 | 40 | zone root | Z1 |
| A5 | `City_Zone_TownCenter` | 0 | 112 | zone root | Z2 |
| A6 | `City_Zone_ShopEast` | 68 | 108 | zone root | Z3 |
| A7 | `City_Zone_ShopWest` | −68 | 84 | zone root | Z4 |
| A8 | `City_Zone_EventPlaza` | −108 | 134 | zone root | Z5 |
| A9 | `City_Zone_FutureGate` | 0 | 168 | zone root | Z7 |
| A10 | `City_Prompt_Boards` | 0 → **10** | 68 | prompt | Z6 |
| A11 | `City_Prompt_ElectroMart` | 68 → **58** | 84 | prompt | Z3 |
| A12 | `City_Prompt_RumahRapi` | −68 → **−58** | 84 | prompt | Z4 |
| A13 | `City_Prompt_Cosmetics` | 68 → **58** | 108 | prompt | Z3 |
| A14 | `City_Prompt_Utility` | 68 → **58** | 132 | prompt | Z3 |
| A15 | `City_Prompt_EventPlaza` | −108 | 110 | prompt | Z5 |
| A16 | `City_Prompt_FutureGate` | 0 | 168 | prompt | Z7 |
| A17 | `City_TransitStop` | 24 | 96 | inert marker | Z2 |
| A18 | `City_Signpost_01…06` | per placement | — | stamp anchors | all |

The bold values are **proposed** (F2 and F6); the board draws the approved position and
marks the proposals separately. Every Y value is `0` for roots, `3` for prompts, `0.6`
for the spawn, `3.65` for door parts (`02` §7).

**FINDING F6 — shop prompt anchors are 12 studs behind their own counter line.** A
24-stud-deep facade with the open front at `x = ±56` and the prompt at `x = ±68` puts the
anchor **12 studs** inside the shop, against a `MaxActivationDistance` of **10** and a
server check of **12**. A player standing on the pavement at `x = 57` is 11 studs from the
anchor and sees **no prompt at all**; even at the counter they are exactly at the limit.
Move all four shop prompts to `x = ±58` (2 studs inside the front edge, on the counter).
Full analysis in `OPEN-DESIGN-DECISIONS.md` D1.
