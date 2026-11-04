# CITY ART DIRECTION — "Gang Melati, 17:20"

> **Status**: Pre-production. Direction proposal for M2-G1/G2 approval, not build authority.
> **Owner**: Agent 2 (world art). Production owner: director.
> **Scope**: the M2-A and M2-B city only. The bedroom is frozen and is not re-authored here.
> **Basis**: `docs/design/01-ART-DIRECTION.md`, `docs/design/02-COLOR-AND-MATERIALS.md`,
> `docs/design/03-WORLD-ENVIRONMENT.md`, `docs/planning/M2-city-expansion/01…10`.

---

## 1. The thesis

The bedroom is a **room someone made out of nothing**. The city is a **street someone
built out of what was lying around**.

Every city element must be explainable by that sentence. A shop with a hand-lettered
board, a gate that says "SEGERA" and has said it for a while, a fountain that works
and a bus stop that does not — these are all the same joke, told at different scales:
*this place is real, and it is a little bit broke.*

The city is **not** a lobby, a hub menu, or a Roblox generic town. It is the street
outside a rented room in a small Indonesian town at 17:20, and the player is standing
on its stoop.

### 1.1 The three rules that generate everything else

1. **Warm low sun, cool shade, one accent.** The whole city is lit by a sun 22° above
   the west-southwest horizon. Everything in shade goes cool and slightly blue. Amber
   appears only where a human put a light or a sign. Anything that needs neon to be
   readable is wrong and gets rebuilt.
2. **Silhouette before surface.** If a shop cannot be named at 60 studs from its mass
   and its hat alone, no amount of signage saves it. Detail is added only after the
   6-part massing test passes (§5).
3. **Hand-built, never generated.** Every repetition needs a reason and one deliberate
   break. A row of three identical shopfronts is a failure even if each one is
   individually fine. The kit gives rhythm; §6 gives the variation rules that stop it
   becoming a copy-paste.

---

## 2. Light

| Setting | Value | Why |
|---|---|---|
| Time of day | **17:20** (`Lighting.ClockTime ≈ 17.33`) | Low sun, long shadows, warm plaster; still bright enough that mobile screens do not crush the darks |
| Sun azimuth | ~250° (WSW) | Light rakes **along** the east shop row, so the awnings on the west row throw shade toward the plaza; every facade gets one lit plane and one shaded plane |
| Sun elevation | ~22° | Long shadows across the lane, but nothing so long that the plaza is a shadow pit |
| `Lighting.Brightness` | 2 (proposal) | Measure in Studio; the room already reads warm, the street must not be brighter than the room |
| `OutdoorAmbient` | `#8FA0A8`-ish cool grey-blue | Shade must go cool, not black. This is the single setting that sells "evening" |
| `GlobalShadows` | true | The bedroom already relies on contact shadows |
| `Atmosphere` | one, `Density` low (≤ 0.3), `Haze` mild | Distance separation for the skyline only. No bloom, no `ColorCorrection` stack, no `DepthOfField` |
| `Technology` | whatever the shipped place already uses — **do not change it for the city** | Changing lighting technology re-lights the bedroom, which is out of scope and would invalidate its sign-off |

**Why the bedroom window stays cool.** The room's north window (`SoftDaylight`,
`#D0E3E0`) is a cool fill. At 17:20 a north-facing window *is* cool — it only sees
sky, never the sun. So the city being warm and the window being cool is not an
inconsistency; it is the one physically correct thing in an otherwise stylised world,
and it is what makes the window read as a real opening rather than a teleport.

**Light-source budget** (see `CITY-PERFORMANCE-BUDGET.md` §6): the city adds **6
`PointLight`s total, 0 with `Shadows = true` in M2-A**. The bedroom already runs three
shadow casters and its south wall is 20 studs from the stoop; a fourth and fifth
shadow caster in the same shadow-mapped region is where mobile frame time goes. The
city's night read is carried by `Neon` indicator strips ≤ 0.1 studs, `SurfaceGui`
signs with `LightInfluence = 1`, and the low sun — not by lamps that only matter after
dark, which this game never reaches.

---

## 3. Palette in use

Sixteen world tokens exist (`docs/design/02` §3). The city uses **eleven** of them, and
each has a job. A token used outside its job is a review rejection.

| Token | Job on a building | Never |
|---|---|---|
| `plaster` `#DBD3BE` | upper-floor wall field, the default building skin | on ground-plane surfaces |
| `cream` `#E9DEC7` | trim: cornices, window frames, sign borders, kerb paint, house numbers | as a large wall field (reads flat and dirty at distance) |
| `wood` `#99704B` | door leaves, bench slats, stall frames, sign posts | as a roof or floor field |
| `wood_light` `#B48B60` | counter tops, shelving faces, window sills | outside arm's reach — it loses contrast at 60 studs |
| `wood_dark` `#654A37` | shadows in joinery: under counters, inside the porch recess, door insets | as an accent — it is structure, not decoration |
| `sage` `#84977E` | **awnings**, valances, banner cloth, the door leaf's exterior face | as wall paint |
| `sage_dark` `#506C56` | awning underside, plinth/kerb at the base of every building, plant leaves | as a sign background (too close to the shade tone) |
| `navy` `#344451` | the **band**: upper-floor panels, shop sign backings, utility livery, deep recesses | on anything that must read bright |
| `ink` `#202A2D` | voids, cables, drain grates, shutter gaps, sign lettering on cream | as a wall field |
| `amber` `#ECBA6F` | signage lettering and bulbs **only** — the accent | as a wall colour |
| `metal` `#6E7773` | lamp posts, roller shutter, drain covers, scooter frame, brackets | as a large surface |
| `glass` `#96B2B1` | window panes at `Transparency = 0.35` (bedroom contract) | anything but panes |
| `clay` `#A67358` | terracotta planters only | anywhere else |
| `screen` `#273F3E` | upper-floor glass seen from outside (dark pane), CRT recesses inside shop windows | as a wall |

**Reserved and forbidden in city geometry:**

- **`lime` `#8CB369` never appears in the city.** Lime is the HUD's income language
  ("this earns"). Putting it on a shop awning would tell the player a non-interactive
  prop is a purchase. It is reserved for `Hud.luau`.
- **`coral` `#D97D64` appears on exactly one sign** (Gaya Depan, M2-C) because coral is
  the warning colour in the UI and the cosmetics shop is the one shop allowed to feel
  slightly wrong.
- **`phosphor` `#B1CEA6` never appears outdoors.** It is the CRT's screen light. Outdoors
  it would read as a second terminal.

**Ratio discipline per frame:** 60% plaster/cream field, 20% sage + navy structure,
12% wood, 6% amber, 2% ink/other. If a screenshot is more than ~10% amber, the shot is
lit wrong, not decorated enough.

---

## 4. Materials

`SmoothPlastic`, `Wood`, `Metal`, `Fabric`, `Glass`, `Neon` — the same five-plus-one the
bedroom uses (`docs/design/02` §5).

| Material | City job | Constraint |
|---|---|---|
| `SmoothPlastic` | walls, signage boards, paving, counters, kerbs, props | the default; no studs/flat-shaded trickery |
| `Wood` | door leaves, bench slats, window frames, stall timber, sign posts | grain runs with the member's long axis |
| `Metal` | lamp posts, shutters, grates, brackets, scooter, pipework | matte; **no reflective panels** |
| `Fabric` | awnings, valances, banners, rug rolls, market cloth | only overhead or soft goods — never a hard surface |
| `Glass` | panes only, `Transparency = 0.35` | one pane per opening, no layered glass |
| `Neon` | indicator strips ≤ **0.1 studs**, antenna tips, gate strip light | never a light source, never > 0.1 studs, never a sign |

**`Concrete` is deliberately not used in M2-A/B.** `05` §1.3 permits it, but
`tools/gen_world_prefabs.py` `MATERIALS` has no `Concrete` token (see
`OPEN-DESIGN-DECISIONS.md` D6). Adding the token is a `tools/` edit that belongs to the
generator owner, and at 24-stud scale `Concrete`'s texture reads as noise on mobile.
Paving is `SmoothPlastic` in two tones.

**No textures, no decals, no meshes, no uploaded images.** Same gate as every existing
prefab (`assets/world/DESIGN.md` §3.3).

---

## 5. Shape grammar — the 6-part building

Every building in the city is built from the same six moves, in this order, and the
generic-box failure is impossible if all six are present:

| # | Move | Geometry | Parts | Job |
|---|---|---|---|---|
| 1 | **MASS** | 24 wide × 12–16 tall × 24 deep box, `plaster` | 1–3 | the volume |
| 2 | **BAND** | a 1.0-stud horizontal `navy` or `sage_dark` band at y 7.6–8.6, 0.15 proud of the wall | 1 | separates open ground floor from solid upper floor; this one line is what makes the mass read as a *shop* and not a *shed* |
| 3 | **RECESS** | ground floor inset **1.5 studs** behind the facade plane, under the band | shell change (0 extra) | casts its own shade line; every shop gets a real, dark, cool interior without a closed room |
| 4 | **HAT** | awning (lead edge y = **8.2**) + signboard (y 8.9–10.5), widths per §7 | 4–7 | the only thing that differs in silhouette; the identity |
| 5 | **FOOT** | a 0.35-stud `sage_dark` plinth along the base of every wall | 4 | stops buildings floating on the pavement and hides the grade seam |
| 6 | **FACE** | upper floor: a pair of 2.0 × 1.4 windows, `screen` panes, `cream` frames, 1.0 apart | 6 | gives the street a face at distance, and repeats as rhythm |

**Heights:** 12 / 14 / 16 studs, and **neighbours must differ by ≥ 2 studs**.
The city's tallest walkable structures are the ElectroMart at 16 and the two gate piers
at 18; banner poles reach 18 but are poles, not mass (`05` §3.3 allows nothing walkable
above 20).

### 5.1 The silhouette test (gate for every building)

Render the building as **6 boxes maximum**, flat grey, no materials, against the sky.
At 60 studs and at a 20° downward camera, a player must be able to say which building
it is. If the answer requires a sign, the massing is wrong and goes back to blockout.

This is exactly the M2-A1 acceptance the blockout must pass — it is why the blockout is
not "a box per shop".

### 5.2 The "hat" — the one thing that must never repeat

| Building | Hat type | Written as |
|---|---|---|
| House (Z0) | flat awning over the stoop + a hanging bulb | 3 parts, asymmetric, no sign |
| ElectroMart (Z3-a) | **blade sign**: a 1.2 × 5.0 × 0.35 box projecting 3 studs off the facade at y 9.0, plus a flat awning | the only projecting vertical in the city |
| Rumah Rapi (Z4) | **pitched awning** (5°) with a 3-strip `sage` fabric valance hanging 0.8 studs | the only pitched hat |
| Warung (Z3-c) | flat awning with a **hanging snack rail** (5 small boxes) | the only shop with goods over the pavement overhead |
| Gaya Depan (Z3-b, M2-C) | **pergola**: 4 exposed rafters over the opening, no cloth | the only open-frame hat |
| Boards kiosk (Z6) | freestanding double board under its own 1.5-stud awning on two posts | the only structure with no mass behind it |
| Gate (Z7) | a **lintel**, no awning | the only thing that frames the horizon |

---

## 6. Variation rules (the anti-copy-paste contract)

The kit (`MODULAR-ASSET-KIT.md`) makes repetition cheap, which is exactly why it needs
rules:

1. **No two adjacent buildings share a height.** 14 / 12 / 16 across a row.
2. **No two buildings share a hat type.** §5.2.
3. **One shop per row breaks the facade line.** The "spill": goods 1.5 studs out on the
   pavement. Rumah Rapi spills rugs and a sample chair; ElectroMart spills a broken CRT
   stack (tagged `RUSAK`, so it is clearly not for sale). M2-C's Gaya Depan spills
   nothing — its break is the pergola.
4. **Each shop owns exactly one accent colour** and no other shop uses it. Amber
   lettering on `navy` is the *shared* system; the accent is the sign's border or its
   blade-sign face.
5. **Windows are the rhythm, not the variation.** The same window pair repeats in the
   same relative position on every upper floor — that repetition is what makes the
   street read as one street. The variation lives in the hats and heights, never in the
   windows.
6. **The west row is quieter than the east row.** One shop, one awning, one spill, one
   lamp. It exists so that the east row's three-lot rhythm has something to be louder
   than.

---

## 7. Signage

One sign per building. No exceptions, no secondary signs, no A-boards with prices.

| Field | Rule |
|---|---|
| Host | one `Part` (`navy` or `ink` face) + one `SurfaceGui` per sign, `LightInfluence = 1`, `AlwaysOnTop = false` |
| Size | 6.0 × 1.6 studs (shop), 4.0 × 1.0 (utility/kiosk), mounted under the awning at y 8.9 |
| Type | `TextLabel`, `Font = Enum.Font.GothamBold` (or the font already used by `Theme.luau` — match it, do not introduce a second face) |
| Contrast | cream/amber text on navy: `#F2E5D5` on `#34465A` ≥ 9:1; amber on navy = 5.64:1 (already verified in `02` §6) |
| Language | **Indonesian in the world, English in the UI.** Never both on one surface. `Open BuzzerOS` stays English because it is UI; `Toko Listrik Pak Bud` is world. |
| Street signage | `cream` paper cards on the boards kiosk, hand-lettered feel via slightly asymmetric placement (± 0.15 stud jitter), no textures |
| Forbidden | 3D text, billboards, `BillboardGui`, uploaded images, English shop names, real brand names, prices on any sign |

**The gate is the only sign allowed to imply a future.** `SEGERA` stencil, a faded
district map, no date, no price, no countdown (`09` §7 hook discipline).

---

## 8. Environmental storytelling inventory

Specific, cheap, and authored. Each one is 1–6 parts and answers "who lives here?".
This is the difference between a city and a level.

| Prop | Where | What it says | Parts |
|---|---|---|---|
| Delivery scooter with a strapped box | house side yard | the player's own side hustle, parked | 6 |
| Two potted plants, one taller than the other | stoop, east side | someone waters them; one is winning | 6 |
| Clothes line strung between two upper windows | west row, above Rumah Rapi | people live above the shops | 3 |
| CRT stack with a handwritten `RUSAK` tag | ElectroMart spill | the owner does not throw anything away | 6 |
| Rug rack with one roll tagged `SOLD` | Rumah Rapi spill | the shop is doing fine, thank you | 5 |
| A card on the boards kiosk that has been rained on | boards kiosk, bottom row | the board is read, not curated | 1 |
| Stamped `SELESAI` card from the last mission | boards kiosk, top row | your work happened here | 1 |
| Cat asleep on the transformer box | lamp post base, plaza edge | the street is warm enough to sleep in | 2 |
| Half-worn `SEGERA` stencil, faded 2019 district map | gate | the gate has been "coming soon" for years | 3 |
| Hand-written schedule reading `Belum beroperasi` | transit shelter | honest, and funnier than a fake timer | 2 |
| A chair outside ElectroMart, facing the plaza | ElectroMart spill | Pak Bud watches the square | 2 |
| One drain grate with a plastic bag caught in it | lane, near the stoop | the lane floods; nobody fixed it | 2 |

**Anti-clutter rule:** a prop that is not on this list, or not in a zone spec
(`ZONE-VISUAL-SPECS.md`), needs a reason in the review. Decorative density is capped by
the part budget, not by the "1 prop per 4×4 studs" line in `03` (see
`CITY-PERFORMANCE-BUDGET.md` §5.3 — that rule permits 672 props in the plaza and is
therefore not a real constraint).

---

## 9. What must never appear

- Neon gradients, emissive signage, bloom, `ColorCorrection` stacking, or any effect
  whose cost is per-screen-pixel rather than per-part.
- Cyberpunk, Tokyo, or generic Western "city" styling. This is a **kampung with a
  shophouse row**, not a downtown.
- Glass curtain walls, towers the player can see the inside of, or anything taller than
  20 studs that is walkable.
- Real or near-real brand names (no convenience-store lookalikes, no energy-drink
  logos). All names are ownable fabrications: `Toko Listrik Pak Bud`, `Rumah Rapi`,
  `Warung Serba Ada`, `Gaya Depan`.
- English shop names, fake community counters (`1,204 buzzers joined`), countdowns,
  "unlock for X" copy, or any prop that implies a price (`04` Part 3).
- Particles as decoration. The only optional particle in M2 is none.
- Closed interiors, doors the player can walk through, stairs, balconies, or roofs the
  camera can enter.
- Anything requiring a texture, decal, mesh, or uploaded asset.

---

## 10. Continuity with the bedroom

The exterior must be recognisably **the same building as the room**, and this is
achieved with three reused facts, not with a new theme:

1. **The same wall tone.** `plaster` is the room's wall colour; the shell exterior uses
   it unmodified. The house is not "a building the room is inside"; it is the room's own
   walls seen from the other side.
2. **The cornice becomes the eave.** The room's perimeter cornices are 0.25 tall × 0.35
   deep (`docs/design/03` §3.1). The house's eave trim uses **exactly those dimensions**,
   so the profile the player has been looking at indoors for the whole of M1 appears
   again outside at 11.9 studs.
3. **The door leaf is `sage`, and it stays `sage`.** `City_HomeDoor` uses the same
   `sage` + `Wood` as the frozen `Door`, with an `amber` handle at the same relative
   height. The player recognises their own door before they read a house number.

**What is allowed to differ:** everything above 11.9 studs (the city has a parapet and
no ceiling), the stoop, and the surroundings. The interior is untouched.

---

## 11. Review: how a shot is rejected

A city screenshot fails visual review if any of these is true:

1. A building cannot be identified in 3 seconds with the sign covered.
2. Amber covers more than ~10% of the frame, or `lime` appears at all.
3. The sky is visible **under** any building (floating geometry).
4. Any two adjacent buildings share a height **and** a hat.
5. A shade face is black instead of cool grey-blue (`OutdoorAmbient` unset).
6. A prop has no story, or a sign has no owner.
7. The frame shows more than 3 readable signs (`05` §3.3).
8. Any surface shows a texture, a decal, or a stretched material.
9. The bed/desk sightline is broken: from `CameraFocus`, the window must show skyline
   only — never the street, a shop back, or the plaza.
10. The shot could be any Roblox town with the shop names changed. That is the failure
    this whole document exists to prevent.

Evidence for sign-off lives in `docs/evidence/m2-a1/` and follows the existing capture
convention (`assets/ASSET-MANIFEST.md` §Verification): desktop 1280×720 + iPhone 14
portrait/landscape, genuine Studio captures, no concept renders.
