# OPEN DESIGN DECISIONS

> **Status**: Pre-production. Every item below is a **finding against the approved
> blueprint**, with the evidence, the options, a recommendation and a safe default.
> **Nothing here has been applied.** The approved documents are unmodified; this file is the
> change request.
> **Decision owner**: director. Technical owner: Agent 2.

---

## 0. First, two documents-reconciled notes (not decisions)

These are not open questions — they are readings of the existing numbers that are easy to
get wrong, recorded so the next reader does not re-derive a wrong total.

| Note | Correct reading |
|---|---|
| `03`'s zone index sums to **468** for M2-A, but `05` §2 says **448** | 468 includes Z2 = 220, which is 140 shell + 80 props. The 80 props are M2-B. 468 − 80 + 60 (`CityProps`, which the index does not list) = **448** ✔ |
| **Z3 = 120** covers "the east shop row" | It covers the **ElectroMart lot only**. The utility lot (50, M2-B) and cosmetics lot (90, M2-C) are separate prefabs. `448 + 510 = 958` ✔, and `510 = 80 + 120 + 100 + 160 + 50` ✔ |
| The **450** figure is a *blockout* ceiling (`07` §3 #5) | It is being used as if it were the M2-A *dressed* ceiling. See D5 and `CITY-PERFORMANCE-BUDGET.md` §1 |

---

## 1. Decision register

| ID | Finding | Blocks | Default if unanswered | Recommendation |
|---|---|---|---|---|
| **D1** | Shop prompt anchors sit 12 studs behind the counter line, against a 10-stud activation distance | M2-B (shop routing) | keep approved `x = ±68`, accept that prompts do not appear from the pavement | **move to `x = ±58`** |
| **D2** | `City_HomeDoor` floats 2.56 studs off the shell face | M2-A1 (house) | keep the coordinate, build a 3-part porch | **build the porch** |
| **D3** | The approved backdrop covers **0.00°** of the window aperture | M2-A1 (backdrop), V-03 closure | keep `x 16…160`, V-03 stays open | **mirror to `x -120…+120`, tower at `x = -34.3`, budget 9 parts** |
| **D4** | Streaming is unconfigured in both Rojo projects; the `Atomic`/`Persistent` plan is inert | M2-A (streaming tests) | leave unset (i.e. off) | **keep off for M2-A/B, record, revisit at M2-C** |
| **D5** | 22 anchor parts are outside the 448 → M2-A is 470 against a 450 ceiling | M2-A1 exit gate | cut 22 P2 parts | **cut the 22 P2 parts; keep 450** |
| **D6** | `05` permits `Concrete`; the generator has no token | any concrete surface | do not use it | **exclude `Concrete` from M2-A/B** |
| **D7** | All props are non-colliding, so the player walks through benches | M2-B plaza dressing | keep `03` rule 5 | **keep** (mobile pathing beats visual solidity) |
| **D8** | 10 `SurfaceGui`s are specified against a ≤ 8 budget | M2-B signage | merge two | **merge signposts into one Gui; Part-compose the gate stencil** |
| **D9** | `City_TransitStop (24, 96)` sits on plaza paving with no road | M2-C transit | keep the coordinate, dress as an angkot stop | **keep + painted curb (3 parts)** |
| **D10** | A 12-stud kiosk at `x = 0` occludes 88–100% of the fountain from the stoop | M2-A1 (kiosk), acceptance #2 | keep approved `x -12…+12`, reword acceptance as a sequence | **shift the kiosk +10 east (`x +4…+16`)** |
| **D11** | Spawn facing `+Z` points the chase camera into the doorway | M2-A4 (transition), S4 money shot | keep `+Z` | **face `-Z` at `City_Spawn`** |
| **D12** | The 8-light cap is fully spent at M2-A/B; M2-C has none left | M2-C | discover it late | **M2-C cosmetics shop is unlit (it is a pergola)** |
| **D13** | The 0.3 s door fade needs a client `ScreenGui`, which M2-A does not have | M2-A4 transition | instant cut | **instant cut in M2-A; fade in M2-A4 with a client controller** |
| **D14** | `Lighting.Technology` is unrecorded; point-light shadows may be inert | any shadow budget | budget 0 shadow casters | **read and record it in Studio before deciding** |

**If the director answers nothing, the "Default" column is what gets built.** No default
requires a blueprint edit to `02`, `03` or `05`.

---

## D1 — Shop prompt anchors are unreachable from the pavement

**Severity: High.** Affects M2-B (ElectroMart, Rumah Rapi, Cosmetics, Utility).

**Evidence.** A shop lot is 24 studs deep (`02` §3). The open front of the east row is at
`x = 56`; the prompt anchor is at `x = 68`. A player standing on the pavement at `x = 57`
is **11 studs** from the anchor. `MaxActivationDistance = 10` and the server rejects `> 12`.
Result: **no prompt from the pavement**, and even at `x = 58` (past the counter line) the
distance is exactly 10.

| Lot | Front | Anchor (approved) | Distance from front | Player must stand at |
|---|---|---:|---:|---|
| ElectroMart | `x = 56` | 68 | 12 | `x ≥ 58` — inside the shop |
| Cosmetics | `x = 56` | 68 | 12 | `x ≥ 58` |
| Utility | `x = 56` | 68 | 12 | `x ≥ 58` |
| Rumah Rapi | `x = -56` | −68 | 12 | `x ≤ -58` |

**Options.**

| Option | Change | Cost |
|---|---|---|
| A (rec.) | move the four shop prompt anchors to `x = ±58`, `y = 3`, `z` unchanged | four values in the anchor table; no geometry change; `City_Zone_Shop*` roots stay at the lot centroid |
| B | keep the anchors and raise `MaxActivationDistance` to 14 | violates the shared 10/12 prompt constants (`WorldService`) and makes every other prompt in the game longer-reaching |
| C | shrink the facade depth to 16 | contradicts `02` §3's frozen 24-stud facade depth and breaks lot interchangeability |

**Recommendation A.** The anchor is a *prompt host*, not a building centroid; the zone root
already marks the centroid, so nothing is lost.

---

## D2 — The exterior door floats 2.56 studs off the house

**Severity: Medium.** Affects M2-A1 (house) and every exterior shot.

**Evidence.** Shell inner face `z = 12.85`, outer face `z = 13.35` (0.6 offset + 0.5
thickness). `City_HomeDoor` is at `z = 16`, depth 0.18 → its near face is at `z = 15.91`.
**Gap = 2.56 studs with nothing in it.** A closed door leaf standing free of its wall is the
single most obvious "this is a blockout" tell in the build. The room's south wall is also
solid (`WallSouth`), so there is no aperture behind it either way.

**Options.**

| Option | Geometry | Parts | Consequence |
|---|---|---:|---|
| **A (rec.)** | two porch cheeks `x -8.5…-7.85` and `-4.15…-3.5`, `z 13.35…16`, plus a soffit at `y 7.9` | **3** | the door becomes the outer face of a real 2.5-stud porch; the "step out" beat gains its threshold; within the 90-part house budget |
| B | move `City_HomeDoor` to `z = 13.45` and `City_Spawn` to `z = 19` | 0 | coordinate change to two approved anchors; removes the architectural reason the stoop exists |
| C | leave it | 0 | a floating door in the first frame of the city |

**Recommendation A.** 3 parts, no coordinate change, and it is the only option that makes
the stoop mean something.

---

## D3 — The skyline is not where the window is looking

**Severity: High.** This is the V-03 closure. Affects M2-A1 (backdrop) and `09` §3's entire
horizon fantasy.

**Evidence.** Window aperture `x 0…6` at `z = -12` (`WindowGlass (3, 5.5, -12.08)`,
`WallNorthLeft/Right` leave exactly that gap). Room camera anchor `CameraFocus (7, 5.5, 3)`
is **east of the whole aperture**.

| Direction | Angular span from `CameraFocus` |
|---|---|
| window aperture | −25.02° … −3.81° (west of the `-Z` axis) |
| approved backdrop `x +16…+160` at `z = -152` | +3.32° … +44.63° |
| **overlap** | **0.00°** |

The backdrop is entirely behind the player's right shoulder; the window still shows sky.
Two further consequences: the visible slice at `z = -152` is `x -65.3…-3.3`, so the Agency
Tower must sit at **`x = -34.3`** to be centred in the window, not near `x = +3`.

**Options.**

| Option | Change | Cost |
|---|---|---|
| **A (rec.)** | backdrop `x -120…+120` (keep `z -192…-112`), tower at `(-34.3, ·, -152)`, plus **1** ground-apron part so the slabs do not float above the horizon | boundary change to a non-walkable, non-collidable decorative band; backdrop **8 → 9 parts** |
| B | keep `x 16…160`, rotate the room's window… impossible (room is frozen) | — |
| C | keep `x 16…160`, accept that V-03 is not fixed | the window keeps showing empty sky, which is the finding this whole hook exists to close |

**Recommendation A.** The backdrop is a painting; moving a painting to face the window costs
one part and one coordinate. It does not touch any walkable zone, anchor, or contract value
that gameplay depends on. The 8 → 9 part change stays inside the `09` §7 hook rule
("≤ 10 BaseParts").

---

## D4 — Streaming is off, and the plan assumes it is on

**Severity: Medium.** Affects M2-A acceptance and `08` §3's file ownership.

**Evidence.** Neither `default.project.json` nor `test.project.json` declares a `Workspace`
node, so `StreamingEnabled` is at the place default (`false`); `ModelStreamingMode` on the
city models is therefore inert. `05` §1.2 requires a client
`Workspace:RequestStreamAroundAsync` at the door — a **client** API — which means
streaming-on introduces `CityController.luau` into M2-A, a file `08` §3 schedules for M2-B.

**Options.**

| Option | Consequence |
|---|---|
| **A (rec.)** | keep `StreamingEnabled = false` for M2-A/B. Set `ModelStreamingMode` anyway (free, documents intent). Revisit when the city exceeds 1,200 parts or a second district exists (M2-C). No client script in M2-A. |
| B | enable streaming now: add a `Workspace` node with the properties, accept the client controller dependency in M2-A, and accept a pop-risk at the door for a 216 × 200 city |
| C | leave it unset and say nothing | the `Atomic`/`Persistent` language in `02`/`05` stays misleading |

**Recommendation A.** For a 216 × 200 stud, 958-part city, streaming is insurance against a
problem the city does not have. The correct engineering move is to record the decision with
its revisit trigger, not to build a client controller to honour a setting nobody needs yet.

**Whichever way this goes, S-4 in `M2-A1-IMPLEMENTATION-HANDOFF.md` §9 must be measured and
recorded.**

---

## D5 — M2-A is 20 parts over its own ceiling because of the anchors

**Severity: High.** Affects the M2-A exit gate.

**Evidence.** `448` counts geometry from `07` §5's asset list, which has no anchor entry.
The city has **22 invisible anchor markers** (16 `City_*` + 6 signposts; `City_HomeDoor` is
real geometry already inside the 90-part house). The bedroom charges its 10 markers inside
its own 155-part budget. Charging the city the same way: **448 + 22 = 470 vs 450 → 20 over.**

**Options.**

| Option | Change | Consequence |
|---|---|---|
| **A (rec.)** | cut **22 parts of P2 dressing** | every approved number survives |
| B | raise the M2-A ceiling 450 → 480 | a contract change with a named cause; needs M2-G1 |
| C | do not charge anchors to the city budget | contradicts `assets/ASSET-MANIFEST.md`'s own accounting; do not |

**Recommended cut list (22 parts), all P2:**

| Cut | Zone | Parts |
|---|---|---:|
| mailbox | Z0 | 3 |
| doormat | Z0 | 1 |
| roof vent | Z0 | 1 |
| cat on the transformer box | Z1 | 2 |
| 2 of 4 drain grates | Z1 | 2 |
| 1 puddle | Z1 | 1 |
| paving medallion | Z2 | 6 |
| 2 of 6 planters | Z2 | 6 |
| **total** | | **22** |

Nothing in this list is on the critical path, in a sightline, or referenced by a spec. If
the P2 art is later wanted back, it comes out of measured headroom, not out of the budget.

---

## D6 — `Concrete` is permitted but has no generator token

**Severity: Low.** Affects any paving/sidewalk surface choice.

**Evidence.** `05` §1.3 allows `SmoothPlastic, Wood, Metal, Fabric, Concrete`.
`tools/gen_world_prefabs.py` `MATERIALS = {"SmoothPlastic": 256, "Wood": 512,
"WoodPlanks": 528, "Metal": 1088, "Fabric": 1312, "Neon": 288, "Glass": 1568}` — **no
`Concrete`**. A city generator that emits `Concrete` needs a token edit in a file this task
must not touch, owned by another agent.

**Recommendation:** exclude `Concrete` from M2-A/B. Paving is `SmoothPlastic` in two tones,
which also reads better at 24-stud scale on mobile (Concrete's texture becomes noise at that
size). If a later phase wants it, add `"Concrete": 816` to `MATERIALS` as a one-line change
in the generator's own milestone.

---

## D7 — The player walks through benches

**Severity: Low.** Affects the plaza's feel, not its function.

**Evidence.** `03` zone rule 5: "structural parts collide; props do not
(`CanCollide = false`, `CanQuery = false`)". Applied literally, plaza benches, planters,
stalls and counters are intangible.

**Tradeoff.** Non-colliding props: the player never gets stuck on furniture, which matters
most on mobile with imprecise virtual sticks, and the camera never resolves against a bench.
Colliding props: the player cannot walk through a bench, which reads better in a screenshot
and worse when a thumb-stick drags them into one.

**Recommendation:** **keep `03` rule 5 as written.** The camera benefit (§2.3 of the kit doc)
is worth more than the solidity, and the existing bedroom already uses the same convention
for decorative accessories.

If the director disagrees, the correct shape is a *split*, not a blanket change: `CanCollide =
true, CanQuery = false` for bench/planter/stall/counter **only** — never `CanQuery = true` on
anything the camera can reach.

---

## D8 — Ten signs, eight `SurfaceGui`s

**Severity: Medium.** Affects the M2-B signage pass and a documented budget.

**Evidence.** `CITY-PERFORMANCE-BUDGET.md` §6.3 sets a ≤ 8 `SurfaceGui` budget (each is a
separate texture target). `ZONE-VISUAL-SPECS.md` specifies: house number, lane hanging sign,
kiosk header, ElectroMart (2), Rumah Rapi, utility, gate stencil, event board = **10**.

**Options.**

| Option | Merges | Result |
|---|---|---|
| **A (rec.)** | one `SurfaceGui` hosts all 6 signposts as `TextLabel`s on separate faces; the gate `SEGERA` stencil is Part-composed (5 thin parts) instead of a Gui | 8 Guis, +5 parts on the gate (21 → 26, budget 30) |
| B | drop the house number plate's text (it is already Part-composed in `ZONE-VISUAL-SPECS` Z0) and the utility's menu card | 8 Guis, 0 extra parts, loses two small storytelling beats |
| C | raise the budget to 10 | +2 texture targets; needs a measured justification |

**Recommendation A.** It keeps every storytelling beat and pays in parts, not in texture
memory — and the gate already has 9 parts of headroom.

---

## D9 — The bus stop has no road

**Severity: Low now; it becomes a visual joke the wrong way in M2-C.**

**Evidence.** `City_TransitStop` is at `(24, 0, 96)`. The only vehicular surface in the city
is the lane `x -16…+16`, `z 16…64`. `(24, 96)` is 28.8 studs from the plaza centre `(0, 112)`,
i.e. **inside the `r = 40` paved disc**. A bus shelter standing on pedestrian paving.

**Options.**

| Option | Change | Consequence |
|---|---|---|
| **A (rec.)** | keep the coordinate; dress it as an **angkot** (minibus) stop with a 3-part painted curb line and a hand-written `Belum beroperasi` schedule | authentic to the setting, no coordinate change, 3 extra parts (already inside the Z2 estimate) |
| B | move it to the lane at `(22, 0, 52)` | a real bus stop needs a real road; but it puts a 10-part shelter in the 48-stud corridor and crowds the lane's single-bright-object rule |
| C | defer it to M2-C entirely | the town centre loses one of its two "the world continues" props |

**Recommendation A.** The joke works better on a plaza anyway: an angkot stop that no angkot
visits is exactly the kind of half-broken municipal detail the art direction is built on.

---

## D10 — The boards kiosk hides the fountain

**Severity: High.** Affects M2-A1 geometry and `07` §3 acceptance #2.

**Evidence** (eye at `(-6, 5)`, kiosk at `z = 68`, fountain `r = 8` at `z = 112`):

| Kiosk | Kiosk span | Fountain span | Occluded |
|---|---|---|---|
| `x -12…+12` | −7.1° … +20.6° | −1.2° … +8.7° | **100%** |
| `x -6…+6` | 0.0° … +14.0° | −1.2° … +8.7° | **88%** |
| `x +4…+16` | +11.8° … +24.6° | −1.2° … +8.7° | **0%** |

**Options.**

| Option | Change | Consequence |
|---|---|---|
| **A (rec.)** | build the kiosk 12 studs wide at `x +4…+16`; move `City_Prompt_Boards` to `(10, 3, 68)`; Z6's zone extent unchanged | both landmarks readable from the stoop; the kiosk sits slightly right of the axis, which is compositionally better than dead-centre |
| B | keep `x -12…+12`; reword acceptance #2 to a sequence ("kiosk from the stoop, fountain as you pass") | no coordinate change; loses the one shot that proves the plaza |
| C | move Z6 entirely off the axis | a zone-extent change — the most expensive option by far |

**Recommendation A.** It is a 10-stud shift of a piece of street furniture inside a zone whose
extent does not move.

---

## D11 — The spawn faces the camera into the doorway

**Severity: Medium.** Affects the first frame of the city (shot S4) and nothing else.

**Evidence.** `City_Spawn (-6, 0.6, 20)` faces `+Z`. The stock chase camera booms ~12.5 studs
**behind** the subject, i.e. toward `z ≈ 7.5` — through the exterior leaf (`15.91…16.09`),
the porch, the shell and the room's south wall. The camera resolves against the first
obstruction (the leaf), landing ~4 studs behind the player.

| Facing | First frame |
|---|---|
| `+Z` (approved) | tight over-the-shoulder; the door fills the lower third; the lane is a distant slot |
| **`-Z` (rec.)** | the camera booms 12 studs into the open lane; **the house fills the frame** — parapet, eave, awning, porch, number, stoop |

**Options.**

| Option | Change | Consequence |
|---|---|---|
| **A (rec.)** | face `City_Spawn` at `-Z` (toward the house); position unchanged at `(-6, 0.6, 20)` | the money shot for one orientation value; "Masuk Rumah" is in front of the player on arrival, which is honest |
| B | move the spawn to `(-6, 0.6, 27)`, keep `+Z` | the boom still hits the leaf; the frame improves only slightly and the player loses the stoop beat |
| C | keep as approved | functional, unremarkable; S4 is delivered as a turn, not an arrival |

**Recommendation A.** Position, unlock contract and prompt ranges are untouched — only the
character's initial yaw changes.

---

## D12 — There is no light budget left for M2-C

**Severity: None now; High if discovered during M2-C.**

**Evidence.** `05` §3.5 caps the city at 8 `PointLight`s. `ZONE-VISUAL-SPECS.md` allocates all
eight (L1–L8) across M2-A/B. The Cosmetics lot (M2-C) is a ninth location.

**Recommendation:** the Cosmetics shop is **unlit by design** — its hat is an open pergola,
it faces east into the low sun, and its whole read is daylight through rafters. If M2-C still
wants a light, retire L7 (Rumah Rapi's counter lamp) and share the plaza's ambient. Record
this now so it is a decision, not a surprise.

---

## D13 — The fade needs a client surface M2-A does not have

**Severity: Medium.** Affects M2-A4 (door transition) only.

**Evidence.** `02` §4.1 specifies a 0.25–0.35 s fade. A fade is a full-screen `Frame` in a
`ScreenGui` — a client UI element. `06` §1 says M2-A adds **no new full-screen UI**, and
`08` §3 schedules `CityController.luau` for M2-B.

**Options.**

| Option | Consequence |
|---|---|
| **A (rec.)** | **instant cut** in M2-A. The camera is never between two positions, so a hard cut reads as an edit, not a glitch. Also the reduced-motion path, promoted to default. |
| B | add a single transparent full-screen `Frame` + one tween in M2-A4, and accept a client controller in M2-A | one file, ~30 lines; the fade is 0.3 s of polish for it |

**Recommendation A.** Revisit in M2-A4 if the cut reads badly on device; the reduced-motion
branch has to exist either way, so the instant cut is never wasted work.

---

## D14 — `Lighting.Technology` is unknown, so shadow claims are unverified

**Severity: Medium.** Affects the light budget and the credibility of the bedroom's shadow
language.

**Evidence.** Neither Rojo project declares a `Lighting` node. Point-light shadows only
render under `Lighting.Technology = Future`; under `Voxel`/`ShadowMap` the `Shadows` property
is accepted and ignored. `docs/design/03` §4 states "`Shadows = true` is enforced on all
fixtures to produce soft contact shadows" — which only holds under `Future`.

This is **not** a claim that the bedroom looks wrong; it is a claim that nobody has recorded
which lighting technology ships. Action, not a decision:

1. Open the built place in Studio, read `Lighting.Technology`, record it in
   `docs/evidence/m2-a1/perf.json`.
2. If it is `Future`: the shadow budget is real, and L3/L4 are the only promotion candidates.
3. If it is not: budget **zero** shadow casters, and stop citing "contact shadows" as a city
   requirement — the read must come from materials and the low sun.

---

## 2. What is *not* open

These were checked and are consistent; do not re-open them without new evidence.

| Item | Verdict |
|---|---|
| Walkable extents 216 × 200 and the zone rectangles | all edges are multiples of 8 and sum correctly |
| Route times in `02` §2 (3.5 / 6.3 / 9.9 s) | reproduced exactly from the door anchor at 16 studs/s |
| `448 / 510 / 958 / 1,200` arithmetic | internally consistent once Z2 is phase-split (§0) |
| The 24-stud lot and 24-stud facade depth | consistent across all four shops and three east lots |
| Z6's apron position (`z 64…72`, outside the `r = 40` disc which starts at `z = 72`) | correct — the kiosk stands on a paved apron, not on the plaza |
| The plaza-to-event-plaza 24-stud connector (`x -80…-56`, `z 104…164`) | free of Z4 (which ends at `z = 96`) |
| The door→gate axis (`x ≈ -6…0`) | walkable end to end; the only dead end is the gate, which is intentional |
| The bedroom's 12 anchors | untouched; the city adds 22 new names, none colliding |
