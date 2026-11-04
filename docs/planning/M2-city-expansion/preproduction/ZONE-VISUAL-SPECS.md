# ZONE VISUAL SPECIFICATIONS

> **Status**: Pre-production art spec. Extents and anchors come from
> `02-WORLD-STRUCTURE.md`; budgets reconcile against `CITY-PERFORMANCE-BUDGET.md`.
> **Read with**: `CITY-ART-DIRECTION.md` (the rules), `MODULAR-ASSET-KIT.md` (the parts).
> **Part counts are estimates** until measured in Studio. Nothing here is built.

Every zone uses the same template so the implementation agent never has to infer a
category: purpose, style, palette, materials, silhouette, signage, light, furniture,
interaction, camera, visibility, budget, essential vs optional.

Palette tokens are the 3D tokens from `docs/design/02-COLOR-AND-MATERIALS.md` §3
(`plaster #DBD3BE`, `cream #E9DEC7`, `wood #99704B`, `wood_light #B48B60`,
`wood_dark #654A37`, `sage #84977E`, `sage_dark #506C56`, `navy #344451`, `ink #202A2D`,
`amber #ECBA6F`, `metal #6E7773`, `glass #96B2B1`, `screen #273F3E`, `clay #A67358`).

---

## Light allocation (city-wide, fixed)

`05` §3.5 caps the city at **8 `PointLight`s, 2 with `Shadows`**. This package spends all
eight in M2-A/B, with **zero** shadow casters until frame time is measured:

| ID | Host | Position | Colour | Range | Brightness | Shadows |
|---|---|---|---|---:|---:|---|
| L1 | house porch bulb | `(-6.0, 8.6, 15.2)` | `amber` | 12 | 0.45 | off |
| L2 | lane lamp (west side) | `(-20, 13.4, 40)` | `amber` | 20 | 0.60 | off |
| L3 | plaza lamp NE | `(20, 13.4, 96)` | `amber` | 22 | 0.70 | off |
| L4 | plaza lamp SW | `(-20, 13.4, 128)` | `amber` | 22 | 0.70 | off |
| L5 | boards kiosk hanging lamp | `(10, 7.2, 68)` | `amber` | 10 | 0.50 | off |
| L6 | ElectroMart fluorescent tube | `(58, 7.6, 84)` | `amber` (desaturated 5%) | 14 | 0.55 | off |
| L7 | Rumah Rapi counter lamp | `(-58, 6.8, 84)` | `amber` | 10 | 0.45 | off |
| L8 | gate amber strip | `(0, 7.6, 166)` | `amber` | 16 | 0.50 | off |

**The cap is spent at M2-A/B.** M2-C's Cosmetics lot has no light left (see
`CITY-PERFORMANCE-BUDGET.md` §6.2). The two shadow casters are earned after measurement,
and the only candidates are L3 and L4 — the plaza, where contact shadows under the
benches actually sell the space.

Every light lives under `City_LightGroup` inside `Workspace.City` (a `Folder`, mirroring
the bedroom's `LightGroup` convention). No `SurfaceLight`, no `SpotLight`, no `Neon` used
as a light.

---

## Z0 — Home & Threshold

| Field | Specification |
|---|---|
| **Extent** | `x -24…+24`, `z -24…+16`; shell offset 0.6 outside the 24×24 room |
| **Purpose** | Make the frozen room read as a real house from outside; define the only threshold in the game |
| **Style** | Compact Indonesian shophouse-house: flat parapet roof, deep porch, one shop-like ground floor that is actually a home |
| **Dominant** | `plaster` wall field (the room's own wall tone, unmodified) |
| **Secondary** | `cream` trim + cornice-derived eave; `sage` door leaf; `wood_dark` door inset; `clay` planters |
| **Accent** | `amber` handle + one bulb (two amber touches, no more) |
| **Materials** | `SmoothPlastic` walls, `Wood` trim/door/fence, `Metal` meter/AC/downpipe, `Fabric` (none), `Glass` (none — the house has no exterior window in M2-A) |
| **Silhouette** | Wide (24) low (11.9) mass with a 2.5-stud-deep **porch void** in the centre-left; the only building in the city whose silhouette has a hole in it at eye level |
| **Signage** | None. A 0.9 × 0.5 `cream` number plate with two `ink` bars (a stylised `07`), at `(-8.2, 7.6, 13.4)` — no text, so it costs one `SurfaceGui` less than every shop |
| **Lighting** | L1 porch bulb; the awning is the only shade plane on the facade |
| **Furniture** | potted plant ×1 (6 parts, east of the door), doormat (1), scooter (6, side yard, angled 15° off the wall), meter box + conduit (2), AC unit (2), downpipe ×2 (2), low front fence (5, west side yard only), mailbox (3, P1) |
| **Interaction** | `City_DoorPromptInterior` `(-6, 3.65, 8)` "Keluar Rumah"; `City_HomeDoor` `(-6, 3.65, 16)` "Masuk Rumah" (physical). Both server-owned, `MaxActivationDistance = 10`, `RequiresLineOfSight = false`. Locked state before `cityUnlocked`: prompt visible, activation shows honest copy (`01` §E.1) |
| **Camera** | **No roof plane.** Parapet at `y 11.9`, 0.5 thick. The porch soffit at `y 7.9` is 0.5 thick and must not extend past `z 13.35` (it would block the boom). Keep `x -8…-2, z 17…24` clear of props so the exit boom never hits anything |
| **Visible from** | Z1 (dominant, 24 studs wide), the plaza at 100+ studs (only the parapet line and awning). From inside: only the north skyline |
| **Budget** | graybox **14** / dressed **75** / approved **90** |
| **Essential (P0)** | shell 6 walls, parapet ×4, stoop slab, porch cheeks ×2, `City_HomeDoor` leaf, door jambs + lintel, awning + 2 brackets |
| **Optional (P1)** | scooter, mailbox, laundry line, plant, doormat, AC, downpipe, meter, fence |
| **Cut first (P2)** | mailbox (3), doormat (1), roof vent (1) — 5 parts, if the 450 ceiling is tight |

**The three continuity rules from `CITY-ART-DIRECTION.md` §10 apply literally here:** same
`plaster`, eave trim at the room's cornice dimensions (0.25 × 0.35), same `sage` door leaf.

---

## Z1 — Gang Melati (residential lane)

| Field | Specification |
|---|---|
| **Extent** | `x -24…+24`, `z +16…+64`; lane `x -16…+16`, 8-stud band each side |
| **Purpose** | Orientation and pacing beat. Teaches the city's scale in 3.5 seconds |
| **Style** | A shared kampung lane with no front sidewalk: the road surface *is* the pedestrian surface, and the 8-stud bands are side-yard terraces. This is why the stoop opens straight onto the lane — it is not a missing sidewalk, it is the section |
| **Dominant** | `ink`-tinted asphalt at 45% toward `navy` (`#3A4448`) |
| **Secondary** | `cream` edge lines, `sage_dark` kerb face, `plaster` band paving |
| **Accent** | `amber` on the one hanging shop sign and the lamp's pool |
| **Materials** | `SmoothPlastic` road/paving, `Metal` lamp + drains + bike, `Wood` sign board, `Fabric` (none) |
| **Silhouette** | Two 12-stud side-yard walls converging: the lane is the city's only **corridor**, and its definition comes from the house on one end and the kiosk at the far end |
| **Signage** | One faded fictional shop sign hanging off the east wall at `(18, 9.2, 34)` — `warung kopi` lettering at 40% wear, no light, no prompt. It exists so the lane has an owner |
| **Lighting** | L2 (west side, `z 40`). One light for 48 studs of lane is deliberate: the sun does the work and the lamp is the dusk promise |
| **Furniture** | lamp post ×1 (4 parts + L2), signposts ×2 (3 parts each + anchors), overhead cable ×3 (catenary from the house to the east wall), parked delivery bike (5), puddle ×2 (2), cat on the transformer box (2), drain grate ×4 (4), neighbour porch (6, west side yard, non-interactive) |
| **Interaction** | None. **No shop entrances on this street in MVP** (`03` Z1 rule) — it must stay a corridor so the plaza lands as a reveal. The two signposts accept the landmark-stamp prompt when `cityUnlocked` (F4) |
| **Camera** | Lane is 32 wide; the boom never touches a wall except at the stoop. Cables are 0.05-stud parts at `y 9.5`, `CanCollide = false` and `CanQuery = false` — the stock camera passes through them |
| **Visible from** | Z0 (from the stoop, the whole lane), Z2 (from the kiosk, looking back — the house's parapet closes the view = a good "home is that way" read) |
| **Budget** | graybox **5** / dressed **83** / approved **80** (3 over — see `CITY-PERFORMANCE-BUDGET.md` §4) |
| **Essential (P0)** | road slab, sidewalk bands, kerbs, 2 lamp posts, 2 signposts, centre line |
| **Optional (P1)** | cables, hanging sign, bike, puddles, cat, drain grates, neighbour porch |
| **Cut first (P2)** | cat (2), 2 of 4 drain grates (2), one puddle (1) |

**Wet-asphalt note:** `SmoothPlastic` with low specular, no reflection trick. The "wet"
read comes from the puddles and the low sun's streak, not from a texture.

---

## Z2 — Alun-Alun (town centre)

| Field | Specification |
|---|---|
| **Extent** | `x -56…+56`, `z +64…+160`; disc r = 40 at `(0, 0, 112)`; fountain r = 8 |
| **Purpose** | The hub and the landmark. Where the player understands "this is a town" |
| **Style** | A small municipal square built and re-built by the same contractor for thirty years: two paving tones, one working fountain, four lamps, no landscaping budget |
| **Dominant** | `plaster` paving field (`#DBD3BE` at 100%) |
| **Secondary** | `cream` banding in a 4-stud radial pattern; `sage_dark` kerb ring; `navy` bench frames |
| **Accent** | `glass` water plane (the only non-pane use of `glass` is the fountain's water, `Transparency = 0.25`, which is *not* the window contract value — it is a separate part type and must be authored separately) |
| **Materials** | `SmoothPlastic` paving + fountain body, `Metal` lamp posts + bins, `Wood` bench slats, `Glass` water |
| **Silhouette** | Horizontal: a 112 × 96 field with exactly one vertical object (the fountain's 4-stud spout) and four 13.4-stud lamps at the cardinal-ish points. The plaza's read is *emptiness framed by awnings* — it is the only zone with no wall |
| **Signage** | None in the plaza itself. The boards kiosk (Z6) carries all the text. This is what makes the kiosk the thing you read |
| **Lighting** | L3 (NE) + L4 (SW) — the two shadow-caster candidates |
| **Furniture** | bench ×4 (5 parts each), planter ×6 (3 each, `clay` + `sage_dark`), bin ×3 (2 each), banner mount ×4 (2 each, empty until an event), paving medallion (6, a 16-stud ring at the disc centre offset to `(0, 96)` so it does not sit under the fountain), signpost ×3, transit shelter (10) + sign (2) |
| **Interaction** | Fountain inspect at `(0, 3, 104)` → one authored flavour line, no reward (if the director approves a flavour line at all; otherwise the fountain is silent and the bench is the only interaction). Bench sit is **cosmetic-only, P2**, and requires a client animation the project does not have — do not build it in M2-A |
| **Camera** | The fountain is 2 studs tall, the camera passes over it. Nothing structural above `y 8.2` except the lamps (thin, non-colliding). The boards kiosk must not be inside the plaza disc — it is on the 8-stud apron at `z 64…72` |
| **Visible from** | Everywhere. This is the zone that must survive being seen from 100 studs away: the disc's `cream` banding is what reads at that range, not the props |
| **Budget** | graybox **8** / dressed **149** with a 1-part paving disc, or **207** with the segmented rim (shell 120 + props 87) / approved **220** (140 shell + 80 props) |
| **Essential (P0)** | disc, rim, paving bands, kerbs, fountain basin + water + pedestal, 4 lamps, boards apron |
| **Optional (P1)** | benches, planters, bins, banner mounts, medallion, signposts |
| **Cut first (P2)** | medallion (6), 2 planters (6), 1 bin (2) |

**Density:** keep a **6-stud clear ring** around the fountain and a **4-stud clear** lane
from the kiosk to the fountain (`03` Z2 rule). The "1 prop per 4×4 studs" line is not a
real constraint here — 10,752 sq studs would permit 672 props (`CITY-PERFORMANCE-BUDGET`
§5.3). The real constraint is the 80-part prop budget.

---

## Z3 — East shop row (three 24-stud lots at `x 56…80`)

Shared: open front at `x = 56`, 24-stud depth, 24-wide lots, heights 16 / 14 / 12.
The player stands on the plaza edge at `x = 56` and reads three hats in a row.

### Z3-a — Toko Listrik Pak Bud (ElectroMart) · `z 72…96` · M2-B

| Field | Specification |
|---|---|
| **Purpose** | Physical face of the **existing** device/desk/hire ladder |
| **Style** | The one shop that upgraded: 16 studs (tallest), a blade sign, an aluminium-framed opening, a fluorescent tube that is too bright |
| **Dominant** | `plaster` upper floor |
| **Secondary** | `navy` band + sign backing; `sage` awning; `metal` door frame |
| **Accent** | `amber` blade sign + lettering (the brightest sign in the city, and the only projecting one) |
| **Materials** | `SmoothPlastic` walls, `Metal` frame/shutter/fixtures, `Wood` counter, `Fabric` awning |
| **Silhouette** | 16-stud mass + a 5-stud-tall × 1.2-wide **blade sign** projecting 3 studs at `y 9.0` — visible broadside from the lane's north end and from the stoop's right edge. This is the landmark shop |
| **Signage** | Blade sign (`amber` field, `ink` letters, 5.0 × 1.2, vertical) + awning signboard (`navy` field, `amber` letters, 6.0 × 1.6). Two signs, different planes — allowed only here |
| **Lighting** | L6 fluorescent tube under the awning. Do **not** put a `Neon` strip along the counter — it would out-read the HUD |
| **Furniture** | counter (4), shelves ×3 tiers (6), CRT stack in the window — reuse the `OldCRT` **silhouette geometry**, never the prefab instance (3 boxes, 4 parts), phone boxes (2), cable coils (2), counter bell (1), pavement chair facing the plaza (2), broken CRT stack with `RUSAK` tag (6, spill) |
| **Interaction** | `City_Prompt_ElectroMart` → existing `Upgrades` tab, filtered and pre-scrolled. **No price table, no discount, no new item.** Locked before `neon_market`: prompt exists, activation shows "Pak Bud belum kenal kamu." Server validates anchor identity + ≤ 12 studs + living character |
| **Camera** | Open front: the camera can enter the shop front and never hits a wall. Blade sign at `y 9.0` is above any boom |
| **Visible from** | The plaza (56 studs, dead ahead of the east row), the lane's south end (blade sign only), the gate (blade sign 84 studs away — the only shop sign readable from the gate; intentional, it is the "you can go back" landmark) |
| **Budget** | graybox 6 / dressed **120** / approved **120** |
| **P0** | shell, counter, shelf tiers, awning, blade sign, opening |
| **P1** | CRT stack, boxes, coils, bell, chair, spill stack |
| **P2** | counter bell, one cable coil |

### Z3-b — Gaya Depan (cosmetics) · `z 96…120` · **M2-C, not in this package**

Specified only so the lot is not built wrong now: 14 studs, **pergola hat** (4 exposed
rafters, no cloth), `coral` sign border (the city's only coral), a mirror wall (2 parts,
`Glass` at 0.35), 3 hanging outfit silhouettes (Part-composed). No light allocated —
the cap is spent (§Light allocation). **Do not build in M2-A/B.**

### Z3-c — Warung Serba Ada (utility) · `z 120…144` · M2-B

| Field | Specification |
|---|---|
| **Purpose** | Free orientation and convenience; zero economy |
| **Style** | The smallest and the most improvised: 12 studs, a flat awning with a snack rail, a radio nobody turns off |
| **Dominant** | `navy` (the only navy-walled shop — `navy` is the utility livery) |
| **Secondary** | `cream` trim, `wood` counter |
| **Accent** | `amber` lettering |
| **Silhouette** | 12-stud mass, lowest in the row, with **goods hanging over the pavement** (5 small boxes on a rail at `y 8.0`) — the only overhead spill in the city |
| **Signage** | `4.0 × 1.0` board, `navy` field, `amber` letters, plus a hand-written menu card (1 part, `cream`) |
| **Lighting** | none (the awning's shade is the read) |
| **Furniture** | counter (4), hanging snack rail (5), radio (2), crate stack (3), menu card (1), hand-written schedule (1) |
| **Interaction** | `City_Prompt_Utility` → free utility panel: map card, event reminder toggle, `Pulang` shortcut (same fade). Nothing is charged (`04` S4) |
| **Camera** | The snack rail at `y 8.0` is above the boom; it is non-colliding |
| **Visible from** | The plaza's SE corner. It is deliberately the least visible shop — the player finds it by walking the row |
| **Budget** | dressed **50** / approved **50** |

---

## Z4 — Rumah Rapi (furniture & decor) · `x -80…-56`, `z 72…96` · M2-B

| Field | Specification |
|---|---|
| **Extent** | 24 × 24, open front at `x = -56`, facing east toward the plaza |
| **Purpose** | The first place to spend on looks instead of power |
| **Style** | Cozy, not luxury: a family furniture shop with bolts of fabric, a sample chair on the pavement, and a rug rack that is the shop's whole window display |
| **Dominant** | `wood` (walnut shelving face — the only shop whose facade field is timber) |
| **Secondary** | `sage` fabric bolts + valance; `cream` trim |
| **Accent** | `amber` counter lamp (L7) and sign lettering |
| **Materials** | `Wood` shelving + chair + rack, `Fabric` bolts + rugs + valance, `SmoothPlastic` walls, `Metal` lamp |
| **Silhouette** | 12 studs (lowest building in the city) with a **5° pitched awning** and a **3-strip fabric valance** hanging 0.8 studs — the only soft edge in the skyline |
| **Signage** | `6.0 × 1.6` board, `wood_dark` field, `cream` letters |
| **Lighting** | L7 counter lamp |
| **Furniture** | shelving ×3 (9), fabric bolts ×6 (6), sample chair (4), rug rack + 3 rolls (8, spill 1.5 studs onto the pavement), plant corner (5), counter (4), `SOLD` tag (1) |
| **Interaction** | `City_Prompt_RumahRapi` → cosmetic catalog panel (new UI, M2-B) → server-confirmed cosmetic ownership → decor placement by a future `DecorService`. **Cosmetic only:** `effect = "none"` asserted by spec (`08` §7). Locked before `fictional_gadget` |
| **Camera** | Pitched awning lead edge at `y 8.2`, valance to `y 7.4`. Non-colliding. The spill goods are 1.5 studs out at `x -56…-54.5` — keep them out of the walking lane between the plaza and the shop |
| **Visible from** | The plaza centre (56 studs), the lane's south end (the valance reads as a soft horizontal, the only one) |
| **Budget** | dressed **82** (my bottom-up) / approved **100** |
| **P0** | shell, awning + valance, shelving, counter, sign |
| **P1** | bolts, chair, rug rack, plant corner |
| **P2** | `SOLD` tag, extra bolt |

**Economy boundary:** if an item would change comfort, yield, reveal, or worker rate, it
is rejected by design (`03` Z4). The shop never touches the 350-part room budget past 195
remaining parts (`07` §5).

---

## Z5 — Event Plaza (Lapangan) · `x -136…-80`, `z 104…164` · M2-B

| Field | Specification |
|---|---|
| **Extent** | 56 × 60 open lot + the 24-stud connector `x -80…-56`, `z 104…164` |
| **Purpose** | A stage for authored, time-boxed events; the cheapest "the world changed" signal |
| **Style** | A neighbourhood field with a permanent low stage and a truss that is always there even when nothing is happening |
| **Dominant** | `sage_dark` stage face + `plaster` apron |
| **Secondary** | `navy` truss, `cream` banner cloth |
| **Accent** | `amber` event board |
| **Materials** | `SmoothPlastic` stage, `Metal` truss + banner poles, `Fabric` banners |
| **Silhouette** | The only **horizontal** structure in the city: a 24 × 10 stage, 2 studs tall, under a 10-stud-wide × 18-tall truss. From the plaza it reads as a frame against the sky — the opposite of every shop |
| **Signage** | `Jadwal minggu ini` board (2 parts + `SurfaceGui`), 2 wooden signposts, no countdown, no "join" counter |
| **Lighting** | none allocated (cap spent). The stage at 17:20 is lit by the sun; when an event runs, the pop-up model may carry **2 `SurfaceLight`-free** `PointLight`s **only if** L3/L4 are temporarily disabled — document the swap in M2-C |
| **Furniture** | stage (8), truss frame (6), banner poles ×3 (6), banner mount ×4 (8), fold-out stalls ×6 (stored, alternate model, **not** in the permanent shell), empty-lot schedule board (3), crowd silhouettes (P2, non-colliding, 0 in M2-A/B) |
| **Interaction** | `City_Prompt_EventPlaza` at `(-108, 3, 110)` → read-only schedule until an event is active. Never a disabled silent prompt: the copy says what it is |
| **Camera** | Stage is 2 studs; the truss is 18 and sits at `z 146…156`, away from every path. Nothing to clip |
| **Visible from** | The plaza (the connector is the only sightline), the gate (obliquely, 90 studs). It must not be visible from the lane — the lane ends at the kiosk |
| **Budget** | dressed **96** permanent / approved **160** permanent (+60 pop-up in M2-C) |
| **Rule** | If no event is active, the plaza shows the **empty lot plus the schedule board** — never a half-built stage (`04` F2 failure mode) |

---

## Z6 — Mission & Daily Boards · `x -12…+12`, `z 64…72`

| Field | Specification |
|---|---|
| **Purpose** | The physical delivery point for campaign briefs; the reason to leave the room |
| **Style** | Two cork boards under one awning on two posts, standing on the plaza's north apron. Not a building — a piece of street furniture that happens to be the most important object in the city |
| **Dominant** | `cream` paper field over `wood` cork frame |
| **Secondary** | `sage` awning; `sage_dark` posts |
| **Accent** | `amber` pinned cards ×2 + the hanging lamp (L5) |
| **Materials** | `Wood` frame/posts, `SmoothPlastic` awning + paper, `Fabric` (none) |
| **Silhouette** | 12 studs wide × 8 tall, two panels, four legs of daylight underneath — the only structure you can see **through** |
| **Signage** | 8 pinned `cream` cards (2 amber), one chalk headline band, one `SELESAI`-stamped card, one rain-wrinkled card. All `SurfaceGui` or Part-composed lettering, max 3 readable signs in frame |
| **Lighting** | L5 hanging lamp under the awning |
| **Furniture** | 2 board panels + frames (4), 2 posts (2), cross rail (1), awning (3), lamp (3), 8 cards (8), chalk band (1), queue rope (3, P2), header sign (2) |
| **Interaction** | `City_Prompt_Boards` `(0→10, 3, 68)` → mission list (existing `Missions` surface) or a compact board panel. Accepts; **never publishes**. If a mission is already active the panel shows "Resume", not a second accept (`06` §5) |
| **Camera** | Under the awning at `y 7.9` the boom pinches; the awning is non-colliding so it passes. The kiosk's open legs mean the camera never gets trapped |
| **Visible from** | The stoop (57 studs — S1, the first activity), the plaza (behind you when you leave it) |
| **Budget** | dressed **28** / approved **40** |
| **Rule** | The board must not become a second composer (`03` Z6) |

**FINDING F2 (see `WORLD-LAYOUT-AND-SIGHTLINES.md` §4.2):** build the kiosk 12 studs wide
at `x +4…+16` and move the prompt to `(10, 3, 68)`, so the stoop → fountain sightline is
clear. If the director keeps the approved `x -12…+12` footprint, the fountain is hidden
from the stoop and acceptance #2 must be reworded as a sequence.

---

## Z7 — Future District Gate · `x -8…+8`, `z 160…176`

| Field | Specification |
|---|---|
| **Purpose** | Sell the horizon. Promise a district without shipping one |
| **Style** | A concrete-and-steel service gate between two piers, roller shutter 70% closed, one amber strip. It has been "coming soon" for years and the poster is faded |
| **Dominant** | `plaster` pier faces + `metal` shutter |
| **Secondary** | `ink` behind the shutter (a 4-stud gap at the bottom showing darkness), `cream` stencil |
| **Accent** | `amber` strip light (L8) |
| **Materials** | `SmoothPlastic` piers, `Metal` shutter + housing, `Wood` poster frame |
| **Silhouette** | Two 18-stud piers (the tallest things at the end of the city) with a 16-stud opening between them; the **only thing in the city that frames the sky** instead of competing with it |
| **Signage** | Half-worn `SEGERA` stencil (1), faded district map poster (2). **No price, no date, no countdown, no unlock button** (`09` §7) |
| **Lighting** | L8 amber strip under the lintel |
| **Furniture** | shutter panels ×6, housing, 2 strip lights, poster, stencil, steam vent grate, guard stool with no guard (2, P2) |
| **Interaction** | `City_Prompt_FutureGate` `(0, 3, 168)` → "Distrik berikutnya belum dibuka." One honest locked prompt, nothing else |
| **Camera** | Piers at 18 studs are the only structures the boom could hit, and they are 140+ studs from any normal path. The shutter gap is 4 studs at the bottom — no camera can enter it |
| **Visible from** | The plaza (56 studs, dead centre), the lane (156 studs — a silhouette at the end of the axis, which is what makes the lane feel like it goes somewhere) |
| **Budget** | dressed **21** / approved **30** |

---

## North skyline backdrop (non-zone) · `z -192…-112`

| Field | Specification |
|---|---|
| **Purpose** | Fix V-03 (the window looks at empty sky) and hide the edge of the world |
| **Style** | Four flat silhouette slabs, one taller Agency Tower, one haze plane, two antenna tips. A painting, not architecture |
| **Palette** | `navy` slabs at 100%, `ink` tower, `sage_dark` one distant hill, haze plane at `glass` 15% |
| **Materials** | `SmoothPlastic` only. No `Neon` except two 0.1-stud antenna tips |
| **Silhouette** | Step-down from west to east: 3 low slabs (24–60 studs tall), the tower at 120, then two short slabs. From the window the tower is the only vertical |
| **Signage** | none (a skyline with a sign is a billboard) |
| **Lighting** | none. The sun does it; the antenna tips blink via a client script in M2-A2 (not M2-A — no client code in the blockout) |
| **Interaction** | none, ever. `CanCollide = false`, `CanQuery = false`, `CanTouch = false` |
| **Camera** | 108+ studs from the room, outside every walkable bound. Must never be reachable |
| **Budget** | **9 parts** (8 approved + 1 ground apron; see `OPEN-DESIGN-DECISIONS.md` D3) |
| **Rule** | **FINDING F3 applies:** place the tower at `x = -34.3` on the `z = -152` plane and extend the slabs to `x -120…+120`, or the window sees nothing (0.00° overlap with the aperture) |
