# CITY PERFORMANCE BUDGET

> **Status**: Pre-production review of the approved budgets. Every number here is an
> **estimate** until measured in Roblox Studio on the target device.
> **Approved figures reviewed**: M2-A 448 parts, M2-B +510, city total 958, ceiling 1,200,
> M2-A1 blockout ceiling 450 (`05` §2/§3.2, `07` §3/§5, `03` zone index).
> **Nothing in this document changes an approved constraint.** Changes are proposed in
> `OPEN-DESIGN-DECISIONS.md` and require director approval.

---

## 1. The three budgets that are being conflated

Three different "part budgets" are in circulation and they mean different things. Most of
the confusion in `05`/`07` comes from mixing them.

| # | Budget | What it counts | Approved value | Measured when |
|---|---|---|---:|---|
| **B1** | M2-A1 **graybox** | structural massing + required lamps/posts/benches-massing + anchors. No awnings, no signs, no props, no dressing | **≤ 450** (`07` §3 #5, `10` checklist) | after T2–T7 of `10` |
| **B2** | M2-A **dressed** | everything M2-A ships: shell + street + plaza shell + kiosk + gate + backdrop + shared kit | **448** (`05` §2), 450 implied ceiling | M2-A5 visual sign-off |
| **B3** | **whole city** | M2-A + M2-B (shops, plaza props, event shell) | **958**, hard cap **1,200** | M2-B exit gate |

B1 against B2 is the mismatch: **450 is a blockout ceiling being used as if it were the
dressed ceiling.** A blockout that reaches 450 has already spent the entire M2-A budget on
grey boxes. §3 shows the blockout should land near **122 parts**, i.e. 27% of the ceiling —
so the 450 figure protects nothing at the stage where it is applied, and everything at the
stage where it is not.

---

## 2. Where 448 actually comes from (reconciliation)

The zone index in `03` plus the asset list in `07` §5 plus the prefab table in `05` §1.1
can be read three different ways. Only one of them produces 448, and it is the correct one:

```text
HouseExterior        90
StreetBlock          80
TownCenter shell    140      <- 03 says Z2 = 220, but 07 §5 splits 140 shell (M2-A)
CityProps kit        60          + 80 props (M2-B)
CityBoards           40
CityGate             30
CityBackdrop          8
                    ---
M2-A TOTAL          448   == 05 §2 "~448 BaseParts (estimate)"   [exact match]
```

Two arithmetic traps, both of which produce wrong numbers:

1. **Summing `03`'s zone index gives 468, not 448.** The index assigns Z2 = 220 without
   splitting phases; 468 − 80 (the M2-B prop pass) = 388, and 388 + 60 (`CityProps`) = 448.
   The 468 figure is an artefact of phase-splitting, not a budget error.
2. **`958 = 848 + 60 + 50`** double-counts the utility lot if you also believe Z3 = 120
   covers all three east lots. It does not: **Z3's 120 is the ElectroMart lot only.** The
   utilities (50) and cosmetics (90, M2-C) are separate prefabs. Check:
   `448 + 510 = 958` ✔ and `510 = 80 (plaza props) + 120 + 100 (Rumah Rapi) + 160 (event
   plaza) + 50 (utility)` ✔.

So the approved numbers **are** internally consistent. The only genuine gap is §2.1.

### 2.1 The 22 anchor parts are not in the 448

`448` counts geometry from `07` §5's asset list. That list has no entry for anchors. The
city's anchor register (`WORLD-LAYOUT-AND-SIGHTLINES.md` §9) is **22 invisible BaseParts**:
16 `City_*` markers (spawn, interior door prompt, 6 zone roots, 7 prompts, transit) +
6 signposts. `City_HomeDoor` is not one of them — it is a real door leaf and is already
inside the 90-part house budget.

The bedroom charges its 10 technical markers inside its own 155-part budget
(`assets/ASSET-MANIFEST.md`: "155 BaseParts (including 10 technical anchors)"). The city
must do the same thing:

```text
M2-A dressed geometry   448
M2-A anchor markers      22
                        ---
M2-A as merged          470   vs the 450 ceiling  ->  20 parts over
```

**This is the only real overrun in the package, and it is 20 parts.**

Three ways to close it; the recommendation is (a):

| Option | Change | Consequence |
|---|---|---|
| **(a) recommended** | keep the 450 ceiling and cut **22 parts of P2 dressing** (§4.3 cut list) | every approved number survives; the city loses 22 optional parts |
| (b) | raise the M2-A ceiling to 480 | a 30-part contract change with a named cause; needs M2-G1 approval |
| (c) | declare that anchors do not count | contradicts how the bedroom is counted; do not do this |

---

## 3. Bottom-up estimate (what the geometry actually costs)

Module-level build-up using the kit costs in `MODULAR-ASSET-KIT.md` §3–§4. **Estimated,
not measured.**

| Prefab | Phase | Graybox (B1) | Dressed (B2) | Approved | Delta |
|---|---|---:|---:|---:|---:|
| `HouseExterior` | M2-A | 14 | 75 | 90 | −15 |
| `StreetBlock` | M2-A | 19 | 83 | 80 | **+3** |
| `TownCenter` shell | M2-A | 49 | **120** (segmented rim) | 140 | −20 |
| `CityBoards` | M2-A | 5 | 28 | 40 | −12 |
| `CityGate` | M2-A | 9 | 21 | 30 | −9 |
| `CityBackdrop` | M2-A | 4 | 9 | 8 | **+1** |
| `CityProps` (kit instances) | M2-A | 0 | 60 | 60 | 0 |
| **M2-A subtotal** | | **100** | **396** | **448** | **−52** |
| anchor markers | M2-A | 22 | 22 | not budgeted | **+22** |
| **M2-A as merged** | | **122** | **418** | 448 / 450 | **−30** |

| Prefab | Phase | Estimate | Approved | Delta |
|---|---|---:|---:|---:|
| `TownCenter` props | M2-B | 87 | 80 | +7 |
| `ShopRowElectronics` | M2-B | 70 | 120 | −50 |
| `ShopUtility` | M2-B | 40 | 50 | −10 |
| `ShopFurniture` | M2-B | 82 | 100 | −18 |
| `EventPlaza` permanent | M2-B | 96 | 160 | −64 |
| **M2-B subtotal** | | **375** | **510** | **−135** |
| **City total (B3)** | | **793** | **958** | **−165** |

### 3.1 How much of that headroom is real

Not as much as it looks. Every "under" above is an under-estimate of *art*, not of
structure, for three reasons:

1. **The plaza shell is a strategy choice, not a count.** A `Part` with
   `Shape = Cylinder`, rotated 90°, is a **1-part** paving disc. The 140-part allocation
   only makes sense with a **segmented rim**: at `r = 40` the circumference is 251 studs, so
   the kerb ring alone is ~31 eight-stud modules and the paving rim another ~31. That
   difference (17 parts vs ~120) is the entire plaza gap, and it is also the difference
   between a flat grey circle and the `cream` two-tone banding that is the only thing
   readable from 100 studs (`ZONE-VISUAL-SPECS.md` Z2). **Spend this budget.** Both
   variants are legitimate; pick one deliberately in M2-A1 and record which.
2. **My shop estimates are shell + one dressing pass.** The M2-B art pass adds signage
   polish, awning valances, interior shelf dressing and price cards; 50 parts of headroom
   on ElectroMart is roughly what that pass costs.
3. **Every "P1/P2" item is already excluded** from the dressed figure. Dressing up to the
   approved number is available, but only by explicit choice.

**Use the headroom as insurance against the estimate being wrong, not as a licence to add
props.** The measurement in §8 is what converts any of this into fact.

---

## 4. The M2-A1 graybox budget (B1), stated properly

`10` T2–T7 asks for: house shell + stoop + porch, lane with 2 lamp posts and 2 signposts,
plaza disc + fountain massing + 4 lamps + 4 bench massings, kiosk, gate, backdrop, anchors.
That is:

| Component | Parts |
|---|---:|
| house: 6 walls + 4 parapet + stoop + 2 porch cheeks + leaf | 14 |
| lane: road + 2 bands + 2 kerbs + 2 lamp posts (4 each) + 2 signposts (3 each) | 19 |
| plaza: disc + rim + fountain (8+1+2) + 4 lamps + 4 benches massing | 49 |
| kiosk massing | 5 |
| gate: 2 piers + lintel + 6 shutter panels | 9 |
| backdrop: 4 slabs | 4 |
| anchors (16 markers + 6 signposts) | 22 |
| **total** | **122** |

| Gate | Value | Verdict |
|---|---:|---|
| Approved blockout ceiling | 450 | 122 is **27%** of it — no useful signal |
| **Proposed M2-A1 target** | **150** | 122 estimate leaves 23% headroom for massing additions before review |
| **Proposed M2-A1 hard stop** | **180** | above this, the "blockout" has become an art pass and must be re-scoped |

Keeping 450 as the M2-A (dressed) gate is correct and should stay.

### 4.1 What must be true at 122 parts

The blockout is only worth reviewing if it can already answer the art questions:

- [ ] all six silhouette hats are present in massing form (§5.2 of `CITY-ART-DIRECTION.md`)
- [ ] heights are 12/14/16 and no two neighbours match
- [ ] the lane is 32 wide, the plaza disc is `r = 40`, the fountain is `r = 8`
- [ ] the stoop is walkable from the door and 2.56 studs deep
- [ ] the kiosk is 12 studs wide and clear of the S2 line
- [ ] the gate frames the horizon from the plaza
- [ ] from the desk, the window shows backdrop slabs, not sky

If it cannot, the blockout is 6 boxes pretending, and no part count saves it.

---

## 5. Density rules — replacing the ones that do not bind

Three approved density rules are arithmetically incapable of doing anything:

| Approved rule | Source | Why it cannot bind | Replace with |
|---|---|---|---|
| "max 1 decorative prop per 4×4 stud footprint" | `03` Z2 | the plaza is 10,752 sq studs → **672 props** permitted against an 80-part prop budget | **props ≤ 35% of a zone's parts** (§5.1) |
| "max 3 readable signs in one camera frame" | `05` §3.3 | correct, and kept — but it is a *screenshot review* rule, not an authoring rule | keep as written |
| "walkable clear width ≥ 6 studs" | `05` §3.3 | correct and binding | keep as written |

### 5.1 Zone density (proposed)

| Zone | Dressed parts | Max props (35%) | Estimated props | Verdict |
|---|---:|---:|---:|---|
| Z0 house | 75 | 26 | 32 | over — but the house is the one exception (it is a facade, not a room); accept |
| Z1 lane | 83 | 29 | 25 | ok |
| Z2 plaza | 207 | 72 | 87 | **over by 15** — trim 3 planters or 2 benches |
| Z3 ElectroMart | 70 | 24 | 17 | ok |
| Z4 Rumah Rapi | 82 | 29 | 23 | ok |
| Z5 event plaza | 96 | 34 | 20 | ok |
| Z6 kiosk | 28 | 10 | 8 | ok |
| Z7 gate | 21 | 7 | 5 | ok |

### 5.2 The rule that actually protects the camera

**Nothing structural above `y = 8.2` within 3 studs of a walkable path**, except the
awning/prop system, which is non-colliding and non-queryable. This is worth more than any
density number: it is what keeps the stock camera working with zero camera code
(`WORLD-LAYOUT-AND-SIGHTLINES.md` §6).

### 5.3 Sliver rule

No painted line, cable, or trim thinner than **0.05 studs** in any dimension. Slivers cost
a full part to render and alias into noise on a 640-wide viewport. (The bedroom's
`CableAcrossDesk` at 0.045 is existing and out of scope; do not add more.)

---

## 6. Lighting, transparency and materials

### 6.1 Shadow-casting lights — verify before budgeting

`05` §3.5 allows 8 `PointLight`s, 2 with shadows. Two facts change how to spend that:

1. **The bedroom already ships 3 `PointLight`s with `Shadows = true`** (`RoomWarmth`,
   `DeskPool`, `SoftDaylight` — `docs/design/03` §4) and the stoop is 20 studs from that
   wall. Any city shadow caster shares a shadow region with all three.
2. **Point-light shadows only render under `Lighting.Technology = Future`.** Under
   `Voxel` or `ShadowMap`, `PointLight.Shadows = true` is accepted and silently ignored —
   only the sun casts. Neither `default.project.json` nor the bedroom prefab sets
   `Lighting.Technology`, so what actually ships depends on the place's own settings.

**Action for M2-A1:** read `Lighting.Technology` in Studio and record it before any shadow
decision. If it is not `Future`, budget **zero** shadow casters and stop citing "soft
contact shadows" as a city requirement — the read has to come from material and the low
sun instead. If it is `Future`, promote at most L3 and L4, then measure.

### 6.2 The light cap is spent at M2-A/B

`ZONE-VISUAL-SPECS.md` allocates all 8 lights (L1–L8) across M2-A/B. **M2-C's Cosmetics
lot has no light budget left.** Options for M2-C, to be decided then: retire L7 (Rumah
Rapi) in favour of a shared plaza light, or raise the cap to 9 with fresh measurement. Do
not discover this while building the cosmetics shop.

### 6.3 Transparency and `SurfaceGui` — the real per-pixel costs

| Item | City-wide budget | Why |
|---|---:|---|
| Transparent parts (`Transparency < 1`, excluding invisible anchors) | **≤ 40** | transparent geometry is overdraw; 20 window panes + fountain water + haze plane + 2 gate strips = 24 estimated |
| `SurfaceGui` | **≤ 8** | each is a separate texture target; 10 signs are specified, so **two signs must be merged or dropped** — the signposts share one `SurfaceGui` with 6 `TextLabel`s, and the gate's stencil is Part-composed |
| `Neon` parts | ≤ 6 | 0.1-stud indicators + 2 antenna tips + gate strip + 2 ElectroMart tube parts |
| Decals / textures / `ImageLabel`s | **0** | prefab gate |

The `SurfaceGui` count is the one that will bite: `ZONE-VISUAL-SPECS.md` specifies a sign
for the house number, lane, kiosk header, ElectroMart (2), Rumah Rapi, utility, gate, and
event board — that is 10. Consolidate to 8 as above.

### 6.4 Materials are not the lever

Six materials (`SmoothPlastic`, `Wood`, `Metal`, `Fabric`, `Glass`, `Neon`) is **not** a
draw-call problem in Roblox — materials do not batching-split the way shader variants do in
other engines. Adding `Concrete` would not cost performance; it is excluded for the
generator-token reason (`OPEN-DESIGN-DECISIONS.md` D6) and the mobile read, not for speed.
**Do not cite "material variety" as the reason to cut a material.**

---

## 7. Streaming

### 7.1 FINDING — streaming is unconfigured, and that is currently a good thing

Neither `default.project.json` nor `test.project.json` declares a `Workspace` node, so
`StreamingEnabled` is at the place default (**false**), and every
`ModelStreamingMode = Atomic/Persistent` value in `02` §6 and `05` §3.1 is **inert**.

The approved plan assumes streaming on and budgets a client-side
`Workspace:RequestStreamAroundAsync` call at the door (`05` §1.2). That call is a **client**
API, which means streaming-on creates an M2-A dependency on `CityController.luau` — a file
`08` §3 schedules for **M2-B**. Streaming-on therefore *adds* a client script to the
blockout milestone.

For a **216 × 200 stud** city at **958 parts** the honest position is:

| Setting | Recommendation | Reason |
|---|---|---|
| `StreamingEnabled` | **`false` for M2-A and M2-B** | the entire city is ~4% of the parts a streaming target radius is designed for; streaming adds a pop-in risk at the door and a client-script dependency, and buys nothing measurable |
| `ModelStreamingMode` values | **still set them on the models** | free, documents intent, and is correct the day streaming is turned on |
| Revisit trigger | city > 1,200 parts **or** a second walkable district (M2-C) | at that point re-open this decision with measurements |
| If turned on later | `StreamingTargetRadius 256`, `StreamingMinRadius 64`, zones `Atomic`, backdrop `Persistent` | as approved |

If the director keeps streaming on for M2-A, then `RequestStreamOnDoor` must be added to a
new client controller in M2-A and `08` §3's ownership matrix changes. That is a scope
change, not a setting.

### 7.2 `Persistent` on the backdrop

`Persistent` matters only when streaming is on. With streaming off it is a no-op that
documents the intent. Fine either way; do not spend review time on it.

---

## 8. Mobile visibility and camera

### 8.1 What the phone can actually see

At 360 × 640 portrait the horizontal field of view is roughly 40° (Roblox's 70° is
vertical). Standing on the stoop looking south:

| Object | Distance | Width | Angular width | Verdict |
|---|---:|---:|---:|---|
| lane (24-stud walkable) at 20 studs | 20 | 24 | 62° | fills the frame — correct, this is the corridor beat |
| boards kiosk | 57 | 12 | 12° | comfortable first target |
| fountain | 100 | 16 | 9° | readable as a landmark, not as a prompt target |
| gate | 156 | 16 | 5.9° | a silhouette, not an object — correct |
| ElectroMart blade sign | 95 | 5 | 3.0° | **at the edge of legibility on portrait** — this is why the blade sign is 5 studs tall and `amber`; verify on device |

The whole spine fits in portrait. **This is the quantitative basis for "no minimap"**
(`06` §2): nothing on the critical path is outside a 62° cone from the door.

### 8.2 Camera occlusion

No new camera code. The pass condition is simply "the stock camera never becomes unusable":

- awnings, signs, cables, banners are `CanQuery = false` → invisible to camera raycasts;
- no roof plane on any building → the orbit camera never enters geometry from above;
- parapets ≤ 11.9 on the house only, 0.5 thick;
- the plaza has no vertical mass above 13.4 except the fountain (2) and lamps (thin).

The one thing to watch: the **house parapet**. The camera orbiting the player indoors sits
at ~10–12 studs; the parapet top is 11.9. Test three pitches (level, −20°, +20°) at the
room centre and at all four wall sides in M2-A1.

---

## 9. Measurement protocol (this is what turns estimates into facts)

Record all of the following in `docs/evidence/m2-a1/perf.json` (and a human-readable
`.txt`), from a **built place**, not from the generator's own count:

| Metric | How | Target |
|---|---|---|
| Server-side city part count | `#Workspace.City:GetDescendants()` filtered to `BasePart` | M2-A1 ≤ 150; M2-A ≤ 450 |
| Per-prefab part count | count inside each `City_Zone_*` model | matches §3 ± 10% |
| Transparent parts | count `Transparency < 1` excluding anchors | ≤ 40 |
| `SurfaceGui` count | count descendants | ≤ 8 |
| `PointLight` count / shadow casters | count descendants of `City_LightGroup` | 8 / 0 |
| `Lighting.Technology` | read and record | whatever ships; recorded |
| FPS, desktop | 5 sample points: stoop, lane, plaza, each shop front, gate | ≥ 30 sustained |
| FPS, mobile emulation | iPhone 14 portrait + landscape, same 5 points | ≥ 30 sustained |
| Frame time | MicroProfiler, 60 s capture at the plaza | no persistent > 100 ms script stall |
| Walk times | on foot, door → kiosk / fountain / gate / each shop | ≤ the §3 table + 25% |

Roblox does not expose a draw-call counter; use frame time and the MicroProfiler's render
passes. **Do not report a draw-call number you cannot read.**

---

## 10. Summary of concerns, ranked

| # | Concern | Severity | Action |
|---|---|---|---|
| 1 | 22 anchor parts are outside the 448 → 470 vs a 450 ceiling | **High** | cut 22 P2 parts (§4 cut list in `OPEN-DESIGN-DECISIONS.md` D5) or approve 480 |
| 2 | The 450 ceiling is applied to a blockout that should be ~122 parts | **High** | adopt the 150/180/450 three-tier gate (§4) |
| 3 | Shop prompt anchors sit 12 studs behind the counter line | **High** | move to `x = ±58` (D1) |
| 4 | The approved backdrop covers 0° of the window aperture | **High** | mirror to `x -120…+120`, tower at `x = -34` (D3/F3) |
| 5 | `City_HomeDoor` floats 2.56 studs off the shell | **Medium** | porch cheeks, 3 parts (D2/F1) |
| 6 | Streaming is off and its settings are inert; turning it on adds a client script to M2-A | **Medium** | keep off, record, revisit at M2-C (D4) |
| 7 | 10 `SurfaceGui`s specified against a ≤ 8 budget | **Medium** | consolidate signposts + gate stencil (D8) |
| 8 | The light cap is fully spent at M2-A/B; M2-C has none | **Low now, High at M2-C** | decide in M2-C; do not discover it late |
| 9 | `Lighting.Technology` is unrecorded; point-light shadows may be inert | **Medium** | read and record before any shadow budget |
| 10 | Plaza density rule permits 672 props / exceeds the 35% rule by 15 | **Low** | trim 3 planters or 2 benches |
| 11 | `Concrete` is permitted but has no generator token | **Low** | exclude in M2-A/B (D6) |
