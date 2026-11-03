# 02 — World Structure, Coordinate Contract & Travel

> **Covers**: §B World Structure.
> **Status**: Planning. Coordinates below are the **proposed freeze** for G1.
> No prefab is authored in this branch.

---

## 1. Structure at a glance

The world is one place, two layers:

| Layer | Ownership | Instances | Position |
|---|---|---|---|
| **Bedroom** | Server, per player | 1 clone per player | Unchanged, origin `(0, 0, 0)` |
| **City** | Server, static | 1 per server | `Workspace.City`, laid out around the bedroom door |

The bedroom does not move. The city is built **around** it, starting at the
south threshold (`+Z`), because the frozen `Door` anchor is on the south wall
at `(-6.00, 3.65, 11.60)`.

> Axis reminder from `docs/design/03`: `-Z` = north (window wall),
> `+Z` = south (door wall), `+X` = east (desk wall), `-X` = west (worker wall).

---

## 2. Top-down map (ASCII)

```text
                          -Z  (north / window view)
        ┌──────────────────────────────────────────────────────────┐
        │        distant skyline backdrop (non-walkable)            │
        │        Agency Tower silhouette · hills · haze             │
        └──────────────────────────────────────────────────────────┘

   x=-140      -84   -56      -20    0    +20    +56   +84   +140
     │          │     │        │     │     │      │     │      │
 -22 ┼──────────┴─────┴────────┴─────┴─────┴──────┴─────┴──────┴─  HOME PLOT
     │                    ┌───────────────────┐                   │  (Z0)
     │                    │  BEDROOM 24×24    │                   │
     │                    │  Spawn (0,.6,6)   │                   │
     │                    │  Door (-6,·,11.6) │                   │
     │                    └─────────┬─────────┘                   │
  18 ┼──────────────────────────────┼─────────────────────────────┼─ threshold
     │                       ┌──────┴──────┐                      │
     │        sidewalk       │  GANG /     │      sidewalk        │  STREET
     │                       │  STREET     │                      │  (Z1)
     │                       │  z 18–64    │                      │
  64 ┼───────────────────────┴──────┬──────┴──────────────────────┼─
     │                              │                             │
     │   ┌────────────┐      ┌──────┴───────┐      ┌───────────┐  │
     │   │ RUMAH RAPI │      │  MISSION     │      │ ELECTRO   │  │  SHOPS
     │   │ (furniture)│      │  + DAILY     │      │ MART      │  │  (Z3/Z4)
     │   │  z 72–96   │      │  BOARDS      │      │ z 72–96   │  │
     │   └─────┬──────┘      │  (0,·,70)    │      └─────┬─────┘  │
     │         │             └──────┬───────┘            │        │
     │         │        ┌───────────┴───────────┐        │        │
     │         │        │     TOWN CENTER       │        │        │  TOWN
     │         │        │   fountain · benches  │   ┌────┴─────┐  │  CENTER
     │         │        │   z 64–160            │   │ COSMETICS│  │  (Z2)
     │         │        │                       │   │ z 96–120 │  │
 104 ┼─────────┼────────┤        (0,0,112)      ├───┴──────────┘  │
     │  ┌──────┴─────┐  │                       │   ┌───────────┐  │
     │  │ EVENT      │  │      bus stop         │   │ UTILITY   │  │
     │  │ PLAZA      │◄─┤      (20,·,96)        │   │ z 120–144 │  │
     │  │ z104–164   │  │                       │   └───────────┘  │
     │  └──────┬─────┘  └───────────┬───────────┘                  │
 160 ┼─────────┴────────────────────┼──────────────────────────────┼─
     │                              │                              │
     │                    ┌─────────┴─────────┐                    │  GATE
     │                    │  FUTURE GATE      │                    │  (Z7)
     │                    │  z 160–176        │                    │
     │                    │  "Coming soon"    │                    │
     │                    └───────────────────┘                    │
     └──────────────────────────────────────────────────────────────┘
                          +Z  (south / city)
```

**Walkable bounding box:** `x ∈ [-140, +84]`, `z ∈ [-22, +176]` → 224 × 198 studs.
**Longest meaningful walk** (door → event plaza center): ≈ 162 studs ≈ **10.1 s**
at default walk speed. **Door → town-center fountain:** ≈ 100 studs ≈ 6.3 s.
**Door → mission board:** ≈ 58 studs ≈ **3.6 s**.

---

## 3. Coordinate contract (proposed freeze for G1)

All values are studs, `Y = 0` is the flat grade. No ramps, stairs, or elevation
changes in M2-A/B — they cost camera and collision work and buy nothing.

| Key | Value | Notes |
|---|---|---|
| Grid module | **8 studs** (props), **16 studs** (structures) | every door, lot, and prompt snaps |
| Grade | `Y = 0` everywhere walkable | room floor is already `Y = 0` |
| Street width | 24 studs road + 8 studs sidewalk each side | total 40 |
| Lot width | 24 studs | three lots per row |
| Facade depth | 24 studs | open-front kiosks, no closed interiors |
| Building height | 12–16 studs | readable from mobile chase camera |
| Plaza disc | center `(0, 0, 112)`, radius 38 | fountain radius 8 |
| Zone margin | 4 studs of empty walkable buffer | prevents props blocking paths |
| Max skyline height | 120 studs, non-walkable, ≥ 120 studs away | backdrop only |

### 3.1 Zone extents

| Zone | X | Z | Walkable area |
|---|---|---|---|
| Z0 Home plot | -22 … +22 | -22 … +22 | 44 × 44 |
| Z1 Street (gang) | -20 … +20 | +18 … +64 | 40 × 46 |
| Z2 Town center | -56 … +56 | +64 … +160 | 112 × 96 |
| Z3 East shop row | +56 … +84 | +72 … +144 | 28 × 72 |
| Z4 West furniture row | -84 … -56 | +72 … +96 | 28 × 24 |
| Z5 Event plaza | -140 … -84 | +104 … +164 | 56 × 60 |
| Z6 Boards kiosk | -12 … +12 | +66 … +76 | inside Z2 |
| Z7 Future gate | -8 … +8 | +160 … +176 | 16 × 16 |
| Backdrop (non-walkable) | +10 … +160 | -200 … -120 | none |

### 3.2 Why the city is south and the skyline is north

- The `Door` anchor is fixed on the south wall. The city must grow from it.
- The north window is the bedroom's only opening. Putting the **distant
  skyline** there fixes visual QA finding V-03 ("north window looks at empty
  sky") at almost no cost, and gives the player something aspirational to look
  at while sitting at the desk.
- The skyline is explicitly **not reachable**. It is a promise, not a lie:
  the Agency Tower is a future-district hook (`09`), not a walkable zone.

---

## 4. Travel model

### 4.1 Door (MVP and permanent)

```text
Interior side                          Exterior side
─────────────                          ─────────────
ProximityPrompt on Door anchor   →     CFrame to City_Spawn (0, 0.6, 24)
"Keluar Rumah"                         facing +Z (city)
10-stud activation, 12-stud server    0.25–0.35 s fade, controls restored
validation (existing constant)

ProximityPrompt on City_HomeDoor →     CFrame to bedroom Spawn (0, 0.6, 6)
"Masuk Rumah"                          facing -Z (desk)
```

Rules:

- **Same place, no TeleportService, no loading screen.** The walk is a camera
  fade + CFrame set; the room clone already exists for this player.
- **Spawn on rejoin is always indoors** at the frozen `Spawn` anchor. Player
  location is not persisted (no schema change, no edge cases on rejoin).
- **Door prompts are new instances**; the frozen `Door` part itself is not
  renamed, moved, or reparented. The prompt is parented to a **new**
  `City_HomeDoor` part on the exterior side and to a new invisible
  `City_DoorPromptInterior` part inside the room, not to `Door`.
- Prompt distance and validation reuse the existing 10/12-stud constants.

### 4.2 Walking

- Default Roblox walk speed. No sprint (sprint would make the city feel tiny
  and trivialize the walk rhythm).
- No NPC collision in corridors. Ambient NPCs are non-colliding.
- Sidewalk edges are visual only; the road is walkable. No vehicles in M2-A/B.
- Every zone is reachable in a straight-ish line from the plaza; no dead ends
  except the Future Gate (intentional).

### 4.3 Transit (M2-C only, optional)

A bus stop at `(20, 0, 96)` becomes a fast-travel point once a second district
exists. It teleports between district stops with the same fade used by the
door. Until then it is a dressed, non-interactive prop with a "Belum beroperasi"
sign — an honest placeholder, not a fake button.

---

## 5. Zone relationship diagram

```text
                         ┌──────────────┐
                         │  BEDROOM     │
                         │  (private)   │
                         └──────┬───────┘
                                │ door
                         ┌──────▼───────┐
                         │  STREET      │  orientation, first sightline
                         └──────┬───────┘
                                │
              ┌─────────────────┼──────────────────┐
              │                 │                  │
       ┌──────▼──────┐   ┌──────▼───────┐   ┌──────▼───────┐
       │ RUMAH RAPI  │   │ TOWN CENTER  │   │ ELECTRO MART │
       │ (cosmetic)  │   │ + BOARDS     │   │ (upgrades)   │
       └─────────────┘   └───┬──────┬───┘   └──────┬───────┘
                             │      │              │
                    ┌────────▼──┐ ┌─▼────────┐ ┌───▼────────┐
                    │ EVENT     │ │ BUS STOP │ │ COSMETICS  │
                    │ PLAZA     │ │ (M2-C)   │ │ + UTILITY  │
                    └─────┬─────┘ └──────────┘ └────────────┘
                          │
                    ┌─────▼──────┐
                    │ FUTURE     │
                    │ GATE       │  locked, unexplained
                    └────────────┘
```

Reading the graph: **one spine, one loop, one teaser.** The player never has to
choose between two equally important branches, and the only dead end is the
locked gate.

---

## 6. Streaming roots and hierarchy (proposed)

```text
Workspace
├── BuzzerRoom_<UserId>            (existing; ModelStreamingMode = Atomic)
│   └── Room → Bedroom …
└── City                           (new Folder, one per server)
    ├── City_Zone_Street           (Model, Atomic)
    ├── City_Zone_TownCenter       (Model, Atomic)
    ├── City_Zone_ShopEast         (Model, Atomic)
    ├── City_Zone_ShopWest         (Model, Atomic)
    ├── City_Zone_EventPlaza       (Model, Atomic)
    ├── City_Zone_FutureGate       (Model, Atomic)
    ├── City_Backdrop              (Model, Persistent — ~6 parts)
    └── City_Anchors               (Folder, invisible parts)
```

- **Atomic** prevents a half-streamed shop from showing a floating awning.
- **Persistent** on the backdrop keeps the skyline visible from the window;
  it is tiny by design (≤ 8 parts) and far away.
- Zone models never contain `Script`, `LocalScript`, or `ModuleScript`
  descendants (same rule as `Bedroom.rbxmx`; verified by the future
  `CityService` spec).

---

## 7. City anchor contract (proposed, separate from bedroom's 12)

These are **new** names, prefixed `City_`, so they can never be confused with
the frozen bedroom anchors. All are invisible `BasePart`s
(`Transparency = 1`, `Anchored = true`, `CanCollide = false`,
`CanTouch = false`, `CanQuery = false`) except where marked physical.

| Anchor | Position | Purpose |
|---|---|---|
| `City_Spawn` | `(0, 0.6, 24)` | door exit destination, facing +Z |
| `City_HomeDoor` | `(-6, 3.65, 16)` | exterior door part + "Masuk Rumah" prompt (physical) |
| `City_DoorPromptInterior` | `(-6, 3.65, 8)` | interior "Keluar Rumah" prompt host (invisible) |
| `City_Zone_Street` | `(0, 0, 40)` | zone root/telemetry |
| `City_Zone_TownCenter` | `(0, 0, 112)` | zone root/telemetry |
| `City_Zone_ShopEast` | `(70, 0, 108)` | zone root/telemetry |
| `City_Zone_ShopWest` | `(-70, 0, 84)` | zone root/telemetry |
| `City_Zone_EventPlaza` | `(-112, 0, 134)` | zone root/telemetry |
| `City_Zone_FutureGate` | `(0, 0, 168)` | zone root/telemetry |
| `City_Prompt_Boards` | `(0, 3, 70)` | mission + daily board interaction |
| `City_Prompt_ElectroMart` | `(70, 3, 84)` | opens existing Upgrades |
| `City_Prompt_RumahRapi` | `(-70, 3, 84)` | opens cosmetic furniture shop |
| `City_Prompt_Cosmetics` | `(70, 3, 108)` | opens cosmetic avatar shop |
| `City_Prompt_Utility` | `(70, 3, 132)` | map / reminders / return-home |
| `City_Prompt_EventPlaza` | `(-112, 3, 110)` | event schedule + active pop-up |
| `City_Prompt_FutureGate` | `(0, 3, 168)` | locked copy only |
| `City_TransitStop` | `(20, 0, 96)` | bus stop marker (inert until M2-C) |
| `City_Signpost_01…06` | per placement | landmark stamp anchors |
| `City_LightGroup` | Folder | city lights (not a BasePart) |

**Never reuse** `Spawn`, `PlayerDesk`, `DashboardPromptAnchor`, `TerminalSlot`,
`PhoneSlot`, `WorkerDeskSlot1/2`, `WorkerSeat1/2`, `CameraFocus`, `Door`,
`LightGroup` in the city.

### 7.1 Door threshold geometry

The bedroom's `Door` part sits from `z = 11.51` to `z = 11.69`. The city grade
starts at `z = 18`, leaving a 6-stud stoop. The exterior house shell must:

- wrap the 24×24 room from the outside, offset **0.6 studs** outward so no
  face z-fights with the interior walls;
- cut a doorway aligned to `x ∈ [-7.85, -4.15]`, `y ∈ [0, 7.3]`;
- stop at `y = 11.9` with a shallow parapet — **no interior ceiling** (frozen
  rule), and no roof plane until a camera test proves it does not clip the
  orbit camera;
- keep all shell geometry `CanCollide = true` on the outside only; nothing new
  inside the room.

---

## 8. What the player sees from inside (sightline contract)

| From | Looking | Must see | Must not see |
|---|---|---|---|
| Desk (`CameraFocus`) | -Z, through window | distant skyline, haze, one tower | city street, shop backs, NPCs |
| Spawn | +Z, at door | door, stoop, street hint | plaza, shops |
| Exterior stoop | +Z | street, board kiosk, plaza fountain | bedroom interior geometry seams |

This is testable in a blockout screenshot and belongs in the M2-A visual
sign-off.
