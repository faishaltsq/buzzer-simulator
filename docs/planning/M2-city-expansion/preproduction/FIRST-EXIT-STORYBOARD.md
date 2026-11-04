# FIRST EXIT — CAMERA & EXPERIENCE STORYBOARD

> **Status**: Pre-production camera plan. **No camera controller is modified in M2-A0.**
> Every shot here is achieved with the **stock Roblox camera** plus static geometry.
> **Read with**: `WORLD-LAYOUT-AND-SIGHTLINES.md` §5–§6 (threshold geometry, camera limits).

---

## 1. The design goal of the first exit

The player has spent the whole of M1 inside a 24 × 24 room. The first time they step out,
the game has to answer three questions in under **six seconds**, without a single word of
tutorial:

1. *Whose house is this?* → it is **yours**, and it is the same building you have been
   living in.
2. *Where am I?* → a lane, with a town at the end of it, and a sign that says what to do.
3. *Why did I come out?* → there is a board 57 studs away with work on it.

If the answer to (1) is missing, the city feels like a level. If (2) is missing, the player
turns around. If (3) is missing, they go back inside and never leave again.

**No cutscene. No camera override. No loading screen. No tutorial modal.** The entire
sequence is geometry + one prompt + one `CFrame`.

---

## 2. Camera assumptions

All shots are described for the **stock `PlayerModule` chase camera**:

| Parameter | Value | Note |
|---|---|---|
| `ZoomDistance` | 12.5 (Roblox default) | the boom length behind the subject |
| Height offset | ~2 studs above the `HumanoidRootPart` | |
| Default pitch | level to −10° | the player controls it |
| Field of view | 70° (vertical) | horizontal ≈ 40° in portrait, ≈ 102° at 16:9 |

Any shot that requires a different FOV, a dolly, or a look-at override is **not in this
plan**. Those belong to a later milestone with a real camera controller, and the `06` §1
rule ("no new full-screen UI in M2-A") plus `05` §3.7 ("all city content is read-only
static geometry except prompt state") both forbid smuggling one in here.

---

## 3. The ten shots

Each shot lists: what the player does, where the camera ends up, what must be in frame,
what must not, and what breaks it.

---

### S1 — "Studio running" (indoor, pre-unlock)

**Player:** at the desk, having just hired the second trainee.
**Camera:** behind the player, inside the room, ~12 studs south at `y ≈ 6`.
**In frame:** desk + `PCRumah` + both worker desks with trainees typing; the `sage` door
on the right edge of frame, closed.
**Must not:** any city geometry through the door (there is none — the wall is solid).
**Purpose:** establish that the door is *right there* and shut.
**Breaks if:** the door is visible but the objective chip does not change when the unlock
fires. The unlock must be legible from inside the room, before the player walks over.

---

### S2 — "The door unlocks"

**Player:** crosses the room toward the door.
**Camera:** follows; the boom is north of the player, looking south at the door wall.
**In frame:** door jambs, `sage` leaf, `amber` handle, and the `Keluar Rumah` prompt
appearing at 10 studs.
**Must not:** the prompt appearing from the far side of the room. From the room centre
`(0, 0.6, 6)` the anchor at `(-6, 3.65, 8)` is 6.4 studs away — **inside** the 10-stud
activation radius. That is intended: the prompt is visible from the middle of the room, so
the player sees the door has become interactive without walking to it.

**Timing:** prompt fades in over 0.2 s (Roblox default). No custom animation.

---

### S3 — "Keluar Rumah"

**Player:** holds the prompt.
**What happens:** server validates (anchor identity, living character, ≤ 12 studs), then
sets the character `CFrame` to `City_Spawn`.
**Shot:** the character is placed; the camera follows in the same frame.
**Must not:** a visible teleport pop. See S4.

**Implementation note — the fade is a client surface.** `02` §4.1 specifies a 0.25–0.35 s
fade. A fade is a full-screen `Frame` in a `ScreenGui`, i.e. **a new client UI element that
M2-A's scope does not include** (`06` §1). Two honest options:

| Option | Result | Cost |
|---|---|---|
| **A (recommended for M2-A1/A4)** | **instant cut** — no overlay at all | zero client UI; the cut reads as an edit, not a glitch, because the camera is never between two positions |
| B | 0.3 s fade overlay | one client `Frame` + one tween; also the natural place for the reduced-motion instant-cut branch |

Reduced motion (`06` §9) requires the instant cut anyway, so Option A is the reduced-motion
path promoted to the default. If the director wants the fade, it is M2-A4 work and needs a
client controller — which `08` §3 schedules for M2-B.

---

### S4 — "Your house, from outside" (the money shot)

**Player:** standing on the stoop at `City_Spawn (-6, 0.6, 20)`.
**Camera:** depends on the facing (§4 of the layout doc, finding F4):

| Spawn facing | Camera lands | Frame |
|---|---|---|
| `+Z` (approved) | boom hits the closed exterior door leaf 4 studs behind the player | tight over-the-shoulder; the door fills the lower third; the lane is a slot in the distance |
| **`-Z` (recommended)** | boom extends 12 studs south into the open lane at `y ≈ 6` | **the house fills the frame**: parapet line at 11.9, eave trim, awning, porch void, house number, plant, stoop, and the player's own back at the bottom |

**In frame (recommended):** the house from outside for the first time. This is the single
image that has to carry the whole M2 chapter.
**Must not:** the parapet's back face; any gap between the shell and the room's walls; the
`Door` prop visible through a hole (there is no hole — §5 of the layout doc).
**Breaks if:** the stoop props (plant, scooter) crowd `x -8…-2, z 17…24` and the camera
resolves against them instead of the open lane.

**Evidence required:** desktop 1280×720 + iPhone 14 landscape 844×390 + portrait 390×844,
from the exact spawn state (not a free camera).

---

### S5 — "The lane" (the turn)

**Player:** turns ~180° and walks south.
**Camera:** swings to the north of the player, boom down the lane.
**In frame:** wet-ish asphalt with a `cream` centre line, one `amber` lamp pool at `z 40`,
the hanging `warung kopi` sign, the cat on the transformer box, and — at the far end — the
kiosk at 57 studs.
**Must not:** the plaza furniture, the shops, or the fountain. The lane is a corridor: it
shows you *one* thing at the end.
**Purpose:** the pacing beat. 3.5 seconds of walk with something to look at.

**Composite check:** the lane's 24-stud walkable width at 20 studs subtends 62° — on a
portrait phone (≈ 40° horizontal FOV) the lane **fills the frame**. That is correct and it
is why the corridor works on mobile without a map.

---

### S6 — "The board" (first activity)

**Player:** arrives at Z6, 57 studs from the door.
**Camera:** behind the player, facing the kiosk.
**In frame:** two cork panels, 8 pinned `cream` cards (2 `amber`), one `SELESAI`-stamped,
one rain-wrinkled; the `Baca papan` prompt; the hanging lamp (L5).
**Must not:** more than 3 readable signs in one frame (`05` §3.3); floating 3D text; a
second prompt stacked with the fountain's.
**Purpose:** the first thing the player *does* outside.
**Breaks if:** the kiosk is centred on `x = 0` and blocks the fountain behind it — at
`x -6…+6` it occludes 88% of the fountain's angular width (`WORLD-LAYOUT-AND-SIGHTLINES`
§4.2). Build it 12 studs wide at `x +4…+16`.

---

### S7 — "The square" (the landmark)

**Player:** clears the kiosk and the plaza opens.
**Camera:** behind the player at the plaza's north edge, boom over open pavement.
**In frame:** the `r = 40` disc with `cream` two-tone banding, the fountain at centre
(19 parts, 2 studs tall, `glass` water), 4 benches, 4 lamps, and the two shop rows
edge-on at `x = ±56` showing one awning and one sign each.
**Must not:** any wall behind the fountain (the plaza's whole job is to be empty); the gate
yet (it is 56 studs further and should be discovered, not revealed).
**Purpose:** the memorable landmark. The fountain is the only vertical object in the
geometry that is not a building, and the two-tone paving is the only thing that reads at
100 studs.

**Frame check:** the fountain is 16 studs wide at 100 studs from the door — **9°** on a
portrait phone. It will read as a landmark but never as a prompt target. That is correct:
the player walks to it because it looks like the middle of town, not because it glows.

---

### S8 — "The one shop that upgraded" (ElectroMart)

**Player:** walks east to the ElectroMart front at `x = 56`.
**Camera:** behind the player, looking east into the open front.
**In frame:** the 16-stud mass (tallest in the city), the **blade sign** projecting 3 studs
at `y 9.0` (readable broadside from the lane's north end), the `navy` band, the `sage`
awning, the fluorescent tube (L6) and the CRT stack in the window.
**Must not:** a price list, a discount banner, or any sign implying a transaction here.
The shop is a doorway to the existing `Upgrades` tab.
**Breaks if:** the prompt anchor is at the lot centroid `x = 68` — 12 studs behind the
counter line, against a 10-stud activation distance, so **the prompt never appears from the
pavement** (`OPEN-DESIGN-DECISIONS.md` D1). Move it to `x = 58`.

---

### S9 — "The quiet row" (Rumah Rapi)

**Player:** crosses the plaza west.
**Camera:** behind the player, looking west.
**In frame:** the lowest building in the city (12 studs), the 5° pitched awning, the
3-strip `sage` valance, the rug rack spilling 1.5 studs onto the pavement with a `SOLD` tag,
the counter lamp (L7), the clothes line above.
**Must not:** the same `sage` awning geometry as the east row (it is the pitched variant,
not the flat one — the hat is the whole point).
**Purpose:** teach that the two rows are different places, not two copies.

---

### S10 — "Masuk Rumah" (the return)

**Player:** walks back to `City_HomeDoor (-6, 3.65, 16)`.
**Camera:** behind the player, boom into the lane, facing north at the house.
**In frame:** the door, the prompt, the house number, the porch recess.
**What happens:** server validates; character `CFrame` set to the frozen bedroom `Spawn`
`(0, 0.6, 6)` facing the desk.
**Must not:** a different camera outcome than a fresh join. The indoor destination must
reproduce the existing spawn behaviour exactly — same anchor, same orientation, same camera
resolve. If the return feels different from logging in, the transition is doing something
it should not.
**Failure path:** if the door prompt fails, the player stays outside with controls intact
and a non-blocking retry message (`02` §4.1 rule 6). Death/respawn still goes to the indoor
`Spawn`.

---

## 4. The 90-second beat sheet

Timecodes assume a player who has just hired the second trainee and is at the desk.

| t | Beat | Screen | What must be true |
|---:|---|---|---|
| 0:00 | Unlock fires | objective chip updates, door prompt becomes active | derived from `tier ≥ 2 ∧ 2 desks ∧ 2 workers` — no new field |
| 0:04 | Player turns toward the door | the door is 8 studs away, prompt already visible from the room centre | prompt radius 10, anchor at `z = 8` |
| 0:08 | Activate | instant cut (or 0.3 s fade) | server-validated; no client position |
| 0:09 | **S4 — your house** | facade, awning, number, stoop | `City_Spawn` facing −Z (recommended) |
| 0:13 | Turn, **S5 — the lane** | corridor, lamp, kiosk at the end | 24-stud walkable width reads |
| 0:17 | Arrive, **S6 — the board** | prompt `Baca papan` | kiosk at `x +4…+16` |
| 0:22 | Panel opens, accept a brief | HUD objective updates, return chip appears | existing mission surface; no second composer |
| 0:30 | **S7 — the square** | fountain, paving banding | disc `r = 40`, fountain `r = 8` |
| 0:45 | **S8 — ElectroMart** | blade sign, open front, prompt | anchor at `x = 58` |
| 1:05 | **S9 — Rumah Rapi** | pitched awning, valance, spill | locked until `fictional_gadget` |
| 1:20 | **S10 — return** | door prompt, then the room | same camera outcome as a fresh join |
| 1:30 | Publish the brief at the desk | existing composer | the loop closes |

**Total: 90 seconds to a complete "leave, get work, come back" cycle**, of which 25 s is
walking. The `01` §D.7 session target is 30–60 s for the errand run; this beat sheet is the
*first* run and is allowed to be slower because everything is new.

---

## 5. What each shot proves (M2-A1 blockout vs M2-A final)

M2-A1 has **no prompts, no logic, no city service** (`10`). So the blockout can only prove
the geometry half:

| Shot | Provable in M2-A1 | Needs M2-A4 (logic) |
|---|---|---|
| S1 | — | unlock chip + prompt state |
| S2 | prompt anchor position (stub prompt, no action) | the activation |
| S3 | — | the transition |
| S4 | **yes** — camera behaviour at the stoop is pure geometry | — |
| S5 | **yes** — the lane read | — |
| S6 | **yes** — kiosk massing vs the fountain line | prompt |
| S7 | **yes** — plaza read, fountain landmark | — |
| S8 | partially — massing and blade sign, no dressing | prompt + shop routing |
| S9 | partially — pitched awning massing | prompt |
| S10 | **yes** — the return camera resolve is geometry | the transition |

The blockout's visual sign-off (M2-G2) is therefore **S4, S5, S6, S7 and S10**, plus the
window shot from `CameraFocus`. Those five frames decide whether the city is worth
building. Everything else is detail.

---

## 6. Evidence capture list

Per the existing convention (`assets/ASSET-MANIFEST.md`, `docs/design/07` §5):

| ID | View | Device | Resolution | Gate |
|---|---|---|---|---|
| `m2a1-s04-desktop` | stoop, at spawn state | desktop | 1280 × 720 | M2-G2 |
| `m2a1-s04-mobile-l` | stoop | iPhone 14 emulation | 844 × 390 | M2-G2 |
| `m2a1-s04-mobile-p` | stoop | iPhone 14 emulation | 390 × 844 | M2-G2 |
| `m2a1-s05-lane` | lane, looking south | desktop | 1280 × 720 | M2-G2 |
| `m2a1-s06-kiosk` | kiosk + fountain behind | desktop | 1280 × 720 | M2-G2 |
| `m2a1-s07-plaza` | plaza from the north edge | desktop | 1280 × 720 | M2-G2 |
| `m2a1-window` | from `CameraFocus`, through the window | desktop | 1280 × 720 | **V-03 closure** |
| `m2a1-s10-return` | at the exterior door | desktop | 1280 × 720 | M2-G2 |

All captures must be genuine Studio Play captures with a real character — not editor-camera
renders, not concept art. The `window` shot is the one that closes the M1 visual finding
V-03, and it must show silhouettes, not sky.

---

## 7. What would make this storyboard fail

1. **The first frame outside is a close-up of a door.** Fix by facing the spawn at −Z
   (S4, finding F4).
2. **The player cannot tell which way the town is.** The lane must have exactly one bright
   thing at its end (the kiosk's amber lamp), and nothing else competing.
3. **The board is not visible from the stoop.** It is at 57 studs and 12 studs wide — 12°
   of arc. It is visible. Do not move it further, and do not build anything over 4 studs
   tall in the lane.
4. **The fountain is behind the kiosk.** Finding F2 — build the kiosk offset east.
5. **The window still shows sky.** Finding F3 — the backdrop covers 0° of the aperture as
   approved.
6. **The return feels different from a login.** The indoor destination must be the frozen
   `Spawn`, unchanged, every time.
