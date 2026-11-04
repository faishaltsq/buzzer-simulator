# 02 — World Structure, Coordinate Contract & Travel

> **Covers**: §B World Structure.
> **Status**: Planning. Coordinates below are the **proposed freeze** for M2-G1.
> Distances and part counts are estimates until measured in Studio.

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

   x=-136     -80   -56      -24    0    +24    +56   +80
     │          │     │        │     │     │      │     │
 -24 ┼──────────┴─────┴────────┼─────┼─────┼──────┼─────┴──────  HOME PLOT
     │                    ┌────┴─────────┴────┐            │      (Z0)
     │                    │  BEDROOM 24×24    │            │
     │                    │  Spawn (0,.6,6)   │            │
     │                    │  Door (-6,·,11.6) │            │
     │                    └─────────┬─────────┘            │
  16 ┼──────────────────────────────┼──────────────────────┼─ threshold
     │                       ┌──────┴──────┐               │
     │        sidewalk       │  GANG /     │      sidewalk │      STREET
     │                       │  STREET     │               │      (Z1)
     │                       │  z 16–64    │               │
  64 ┼───────────────────────┴──────┬──────┴───────────────┼─
     │                              │                      │
     │   ┌────────────┐      ┌──────┴───────┐      ┌──────┐│
     │   │ RUMAH RAPI │      │  MISSION     │      │ELECTRO│      SHOPS
     │   │ (furniture)│      │  + DAILY     │      │ MART │      (Z3/Z4)
     │   │  z 72–96   │      │  BOARDS      │      │z72–96│
     │   └─────┬──────┘      │  (0,·,68)    │      └──┬───┘│
     │         │             └──────┬───────┘         │    │
     │         │        ┌───────────┴───────────┐     │    │
     │         │        │     TOWN CENTER       │     │    │      TOWN
     │         │        │   fountain · benches  │  ┌──┴───┐      CENTER
     │         │        │   z 64–160            │  │COSMET│      (Z2)
     │         │        │       (0,0,112)       │  │z96–120│
 104 ┼─────────┼────────┤      bus (24,96)      ├──┴──────┘
     │  ┌──────┴─────┐  │                       │  ┌──────┐ │
     │  │ EVENT      │  │                       │  │UTILITY│ │
     │  │ PLAZA      │◄─┤  24-stud connector    │  │z120–144│
     │  │ z104–164   │  │                       │  └──────┘ │
     │  │ (-108,134) │  └───────────┬───────────┘           │
 160 ┼──┴────────────┴─────────────┼───────────────────────┼─
     │                              │                       │
     │                    ┌─────────┴─────────┐             │      GATE
     │                    │  FUTURE GATE      │             │      (Z7)
     │                    │  z 160–176        │             │
     │                    └───────────────────┘             │
     └──────────────────────────────────────────────────────────────┘
                          +Z  (south / city)
```

**Walkable bounding box:** `x ∈ [-136, +80]`, `z ∈ [-24, +176]` → **216 × 200
studs** (architecture-derived, not yet measured in Studio).

**Estimated travel** (default walk speed, straight line, no obstacles — to be
verified in the M2-A1 blockout): door → event plaza center ≈ 159 studs ≈
**9.9 s**; door → town-center fountain ≈ 100 studs ≈ 6.3 s; door → mission
board ≈ 56 studs ≈ **3.5 s**. These are estimates until measured.

---

## 3. Coordinate contract (proposed freeze for M2-G1)

All values are studs, `Y = 0` is the flat grade. No ramps, stairs, or elevation
changes in M2-A/B — they cost camera and collision work and buy nothing.

| Key | Value | Notes |
|---|---|---|
| Grid module | **8 studs** for all structure footprints and prop placement; **16 studs** for major lines (zone origins, street centerline, plaza center, gate) | every structure edge is a multiple of 8; zone origins are multiples of 16 where the layout allows |
| Anchor offsets | 4 studs allowed inside a structure | a prompt on a 24-wide counter lands on a 4-stud offset by design |
| Grade | `Y = 0` everywhere walkable | room floor is already `Y = 0` |
| Street width | **32-stud road** + 8-stud sidewalk each side | total 48 |
| Lot width | 24 studs | three lots per row |
| Facade depth | 24 studs | open-front kiosks, no closed interiors |
| Building height | 12–16 studs | readable from mobile chase camera |
| Plaza disc | center `(0, 0, 112)`, radius 40 (estimate) | fountain radius 8 |
| Zone margin | 4 studs of empty walkable buffer | prevents props blocking paths |
| Max skyline height | 120 studs, non-walkable, ≥ 120 studs away | backdrop only |

### 3.1 Zone extents

| Zone | X | Z | Walkable area |
|---|---|---|---|
| Z0 Home plot | -24 … +24 | -24 … +16 | 48 × 40 |
| Z1 Street (gang) | -24 … +24 | +16 … +64 | 48 × 48 |
| Z2 Town center | -56 … +56 | +64 … +160 | 112 × 96 |
| Z3 East shop row | +56 … +80 | +72 … +144 | 24 × 72 |
| Z4 West furniture row | -80 … -56 | +72 … +96 | 24 × 24 |
| Z5 Event plaza | -136 … -80 | +104 … +164 | 56 × 60 |
| Z6 Boards kiosk | -12 … +12 | +64 … +72 | inside Z2 |
| Z7 Future gate | -8 … +8 | +160 … +176 | 16 × 16 |
| Backdrop (non-walkable) | +16 … +160 | -192 … -112 | none |

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

**Frozen geometry fact (verified in `Bedroom.rbxmx`):** `Door` is a closed,
physical, **collidable** prop — size `3.7 × 7.3 × 0.18` at
`(-6, 3.65, 11.6)`, `CanCollide = true`, `CanQuery = true`,
`Transparency = 0`, `Material = Wood`. The player cannot walk through it, and
M2 must not open, move, resize, un-collide, rename, or reparent it.

**Therefore M2-A1 uses a `ProximityPrompt` plus a server-validated position
transition — never physical passage through the `Door`.**

```text
Interior side                              Exterior side
─────────────                              ─────────────
Prompt on City_DoorPromptInterior    →     server-validated CFrame to
(-6, 3.65, 8)  "Keluar Rumah"              City_Spawn (-6, 0.6, 20)
10-stud activation, ≤12 server check       facing +Z (city)
                                           fade 0.25–0.35 s

Prompt on City_HomeDoor (physical)   →     server-validated CFrame to
(-6, 3.65, 16)  "Masuk Rumah"              bedroom Spawn (0, 0.6, 6)
                                           facing -Z (desk)
```

Transition contract (all six are acceptance-tested in M2-A1, `10`):

1. **Discoverability.** The interior prompt is visible from the room centre and
   the door approach; the exterior prompt is visible from the stoop. Prompt
   `MaxActivationDistance = 10`, `RequiresLineOfSight = false`.
2. **Server-authoritative validation.** The server re-resolves the anchor by
   name, checks the prompt is the server-owned instance, checks a living
   character, and measures root-to-anchor distance ≤ 12 studs. Client-supplied
   positions are ignored.
3. **Safe destination.** Destination = anchor position + measured root height
   (≈ 3 studs; **measure in Studio, do not hard-code 0.6**), followed by a short
   downward raycast to confirm ground and a small overlap check. If the check
   fails, the transition is refused.
4. **Camera and controls restoration.** Input/focus is captured before the
   fade and restored exactly once after placement; camera returns to the
   character controller. A second toggle must not double-restore or leave the
   camera locked.
5. **No clipping / no spawn inside solid geometry.** The destination must be
   ≥ 4 studs clear of the shell, the `Door`, the `City_HomeDoor` part, and any
   prop. Re-test after every blockout change.
6. **No soft-lock.** If streaming is not ready, the fade holds and retries
   once; on failure the player stays in place with controls restored and a
   non-blocking retry message. Death/respawn still uses the existing indoor
   `Spawn`.

Additional rules:

- **Same place, no `TeleportService`, no loading screen.** It is a fade +
  `CFrame` set; the room clone already exists for this player.
- **Spawn on rejoin is always indoors** at the frozen `Spawn` anchor. Player
  location is not persisted (no schema change, no edge cases on rejoin).
- **The prompts are new instances** parented to `City_DoorPromptInterior` and
  `City_HomeDoor` — never to the frozen `Door`.
- No `Touched` handler, no collision toggling, no teleport pad, no physical
  doorway widening.

### 4.2 Walking

- Default Roblox walk speed. No sprint (sprint would make the city feel tiny
  and trivialize the walk rhythm).
- No NPC collision in corridors. Ambient NPCs are non-colliding.
- Sidewalk edges are visual only; the road is walkable. No vehicles in M2-A/B.
- Every zone is reachable in a straight-ish line from the plaza; no dead ends
  except the Future Gate (intentional).

### 4.3 Transit (M2-C only, optional)

A bus stop at `(24, 0, 96)` becomes a fast-travel point once a second district
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
    ├── City_Backdrop              (Model, Persistent — 8 parts)
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
| `City_Spawn` | `(-6, 0.6, 20)` | door exit destination, facing +Z |
| `City_HomeDoor` | `(-6, 3.65, 16)` | exterior door part + "Masuk Rumah" prompt (physical) |
| `City_DoorPromptInterior` | `(-6, 3.65, 8)` | interior "Keluar Rumah" prompt host (invisible) |
| `City_Zone_Street` | `(0, 0, 40)` | zone root/telemetry (street centerline) |
| `City_Zone_TownCenter` | `(0, 0, 112)` | zone root/telemetry |
| `City_Zone_ShopEast` | `(68, 0, 108)` | zone root/telemetry |
| `City_Zone_ShopWest` | `(-68, 0, 84)` | zone root/telemetry |
| `City_Zone_EventPlaza` | `(-108, 0, 134)` | zone root/telemetry |
| `City_Zone_FutureGate` | `(0, 0, 168)` | zone root/telemetry |
| `City_Prompt_Boards` | `(0, 3, 68)` | mission + daily board interaction |
| `City_Prompt_ElectroMart` | `(68, 3, 84)` | opens existing Upgrades |
| `City_Prompt_RumahRapi` | `(-68, 3, 84)` | opens cosmetic furniture shop |
| `City_Prompt_Cosmetics` | `(68, 3, 108)` | opens cosmetic avatar shop |
| `City_Prompt_Utility` | `(68, 3, 132)` | map / reminders / return-home |
| `City_Prompt_EventPlaza` | `(-108, 3, 110)` | event schedule + active pop-up |
| `City_Prompt_FutureGate` | `(0, 3, 168)` | locked copy only |
| `City_TransitStop` | `(24, 0, 96)` | bus stop marker (inert until M2-C) |
| `City_Signpost_01…06` | per placement | landmark stamp anchors |
| `City_LightGroup` | Folder | city lights (not a BasePart) |

**Never reuse** `Spawn`, `PlayerDesk`, `DashboardPromptAnchor`, `TerminalSlot`,
`PhoneSlot`, `WorkerDeskSlot1/2`, `WorkerSeat1/2`, `CameraFocus`, `Door`,
`LightGroup` in the city.

### 7.1 Door threshold geometry

The bedroom's `Door` part sits from `z = 11.51` to `z = 11.69` and is
**collidable**. The city grade starts at `z = 16` (a **4-stud stoop** between
the door plane and the street grade). No player ever walks through the `Door`;
the transition is the validated prompt + CFrame in §4.1. The exterior house
shell must:

- wrap the 24×24 room from the outside, offset **0.6 studs** outward so no
  face z-fights with the interior walls;
- cut a doorway aligned to `x ∈ [-7.85, -4.15]`, `y ∈ [0, 7.3]`;
- keep the `Door` part exactly as authored (`3.7 × 7.3 × 0.18` at
  `(-6, 3.65, 11.6)`, `CanCollide = true`) — never resize, rotate, un-collide,
  or reparent it;
- put `City_HomeDoor` and its prompt on the **exterior face** at `z = 16`, and
  `City_DoorPromptInterior` inside the room at `z = 8`; both are new parts;
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
