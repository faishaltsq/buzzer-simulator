# 03 — WORLD ENVIRONMENT & BEDROOM SYSTEM

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Architectural Blueprint & Proportions

The primary setting of *Buzzer Simulator* (V0 through M1) is a single, self-contained rented bedroom measuring exactly:

$$\textbf{24 studs (X)} \times \textbf{10 studs (Y)} \times \textbf{24 studs (Z)}$$

```
-X (West Wall: Reserved Worker Capacity)                    +X (East Wall: Workspace)
+-----------------------------------------------------------------------------------+
| WorkerDeskSlot1          WindowWall (North)                   [Plant]     Bookcase|
| (-8, 3.2, -8)             (3, 5.5, -12)                    (10.65,-9.4)  (-2,-10.9)|
|                                                                                   |
| WorkerSeat1                                                  TerminalSlot         |
| (-8, 1.6, -6.2)                                              (7.4, 3.35, -4)      |
|                                                                    [OldCRT]       |
|                                                              PlayerDesk (7, 3.35, -4)
| WorkerDeskSlot2                                              PhoneSlot            |
| (-8, 3.2, -2)                                                (4.6, 3.35, -3.8)    |
|                                                              DashboardPromptAnchor|
| WorkerSeat2                                                  (7.4, 3.6, -2.4)     |
| (-8, 1.6, -0.2)                                                                   |
|                                                                                   |
|                                  [Central Clear Corridor]                         |
|                                                                                   |
|                                                                                   |
|    BedHeadboard (-7, 1.85, 1.4)                                                   |
|    BedFrame     (-7, 0.95, 5.0)       Spawn Reference        CameraFocus          |
|    [Rug]        (-2, 0.10, 5.0)          (0, 0.6, 6)         (7, 5.5, 3)          |
|                                                                                   |
| Door (-6, 3.65, 11.6)                     WallSouth (0, 5, 12)                    |
+-----------------------------------------------------------------------------------+
-Z (North Wall)                                                     +Z (South Wall)
```

---

## 2. Frozen Room Anchor Contracts (Immutable)

The 12 named anchors in `Bedroom.rbxmx` are hardcoded server-to-client contracts (`WorldService.luau`, `tests/Specs/WorldService.spec.luau`). They must never be renamed, moved, reparented, or resized:

| Anchor Name | World Coordinates (X, Y, Z) | Size (W, H, D) | Orientation | Functional Purpose |
|---|---|---|---|---|
| `Spawn` | `(0.00, 0.60, 6.00)` | `(4.0, 1.0, 4.0)` | Identity | Player initial spawn reference |
| `PlayerDesk` | `(7.00, 3.35, -4.00)` | `(7.0, 0.3, 3.0)` | Identity | Top surface of main player workstation |
| `DashboardPromptAnchor` | `(7.40, 3.60, -2.40)` | `(1.5, 1.5, 0.4)` | Identity | Parent of the BuzzerOS ProximityPrompt |
| `TerminalSlot` | `(7.40, 3.35, -4.00)` | `(3.0, 0.2, 2.6)` | Identity | Mounting slot for OldCRT / future PC Rumah |
| `PhoneSlot` | `(4.60, 3.35, -3.80)` | `(1.4, 0.2, 1.4)` | Identity | Mounting slot for PhoneCheap / PhoneFast |
| `WorkerDeskSlot1` | `(-8.00, 3.20, -8.00)` | `(4.0, 0.4, 2.4)` | Identity | Reserved future desk 1 bounding volume |
| `WorkerSeat1` | `(-8.00, 1.60, -6.20)` | `(2.0, 2.0, 2.0)` | Identity | Reserved future trainee seat 1 volume |
| `WorkerDeskSlot2` | `(-8.00, 3.20, -2.00)` | `(4.0, 0.4, 2.4)` | Identity | Reserved future desk 2 bounding volume |
| `WorkerSeat2` | `(-8.00, 1.60, -0.20)` | `(2.0, 2.0, 2.0)` | Identity | Reserved future trainee seat 2 volume |
| `CameraFocus` | `(7.00, 5.50, 3.00)` | `(1.0, 1.0, 1.0)` | Identity | Pre-BS-07 camera target anchor |
| `Door` | `(-6.00, 3.65, 11.60)` | `(3.7, 7.3, 0.18)` | Identity | Physical entry door prop (CanCollide = true)|
| `LightGroup` | N/A (Folder) | N/A | Identity | Container for all bedroom PointLight sources|

*Note: All anchors except `Door` and `LightGroup` are fully transparent (`Transparency = 1`), anchored, non-colliding (`CanCollide = false`), non-touching (`CanTouch = false`), and non-queryable (`CanQuery = false`).*

---

## 3. Shape Language & Architectural Rules

1. **Open-Ceiling Treatment**: The bedroom has **no solid ceiling lid**. It retains 10-stud walls capped by perimeter wooden cornices (`CorniceNorth/East/West/South`, size 0.35 × 0.25 × 24 studs). This allows standard third-person Roblox camera controllers to orbit freely without awkward clipping, occlusion popping, or camera collision spring bounces.
2. **Plaster & Trim**: Perimeter walls are 0.5-stud thick plaster (`plaster`, Color: `219, 211, 190`). The base of each wall is lined with 0.4-stud tall cream wooden baseboards (`TrimNorth/South/East/West`, Color: `cream`), anchoring walls cleanly to the floor.
3. **Broad Floorboards**: The floor is divided into 12 wide longitudinal boards (1.98 × 0.06 × 23 studs) alternating subtly between `#99704B` and `#A07751`. This deliberate board width prevents high-frequency moiré patterns or noisy checkerboards on low-resolution mobile displays.
4. **Architectural Openings**:
   - **North Window**: An authentic framed opening (5.8 × 4.8 studs) with triple vertical mullions and horizontal rails, flanked by folded sage curtains.
   - **South Door**: A 7.3-stud tall door frame with jambs, lintel, recessed inner panels (`sage_dark`), and an amber metal handle.

---

## 4. Lighting Rig & Light Group Standards

The room’s illumination is governed entirely by three carefully balanced `PointLight` fixtures inside `LightGroup`:

```
+---------------------------------------------------------------------------------------+
|                                    BEDROOM LIGHT RIG                                  |
+-------------------+-------------------+------------+-------+--------------------------+
| Fixture Name      | Mount Position    | Color      | Range | Role                     |
+-------------------+-------------------+------------+-------+--------------------------+
| `RoomWarmth`      | PendantDiffuser   | #FFE8CA    | 23.0  | Ambient domestic warmth; |
|                   | `(1.0, 8.65, 0)`  | (255,232,  | studs | illuminates room core    |
|                   |                   |  202)      |       | Brightness: 0.75         |
+-------------------+-------------------+------------+-------+--------------------------+
| `DeskPool`        | LampDiffuser      | #F2BC79    | 8.0   | Dedicated task pool onto |
|                   | `(10.05, 4.43,    | (242,188,  | studs | CRT keyboard & phone pad |
|                   |   -3.4)`          |  121)      |       | Brightness: 0.40         |
+-------------------+-------------------+------------+-------+--------------------------+
| `SoftDaylight`    | WindowFill        | #D0E3E0    | 17.0  | Subtle cool fill from    |
|                   | `(3.0, 6.0, -11)` | (208,227,  | studs | north exterior window    |
|                   |                   |  224)      |       | Brightness: 0.65         |
+-------------------+-------------------+------------+-------+--------------------------+
```

### Lighting Constraints:
- `Shadows = true` is enforced on all fixtures to produce soft contact shadows under the bed frame, desk apron, and bookshelf.
- Total light sources must never exceed 4 per room in V0/M1 to maintain 60 FPS performance on low-end mobile devices (e.g., iPhone 8 / low-end Android).
- Zero unshielded neon placement geometry is allowed.

---

## 5. Walking Clearance & Empty Space Requirements

1. **Central Walking Corridor**: A minimum clearance width of **4.2 studs** is guaranteed between the player desk edge ($X = 3.85$) and the bed footprint ($X = -4.68$).
2. **Door Approach Corridor**: A 5-stud unobstructed path extends from the door ($X = -6, Z = 11.6$) directly to the room center and desk.
3. **Worker Station Clearance**: The western half of the room ($X = -11.5$ to $X = -4.5$) contains zero furnishings other than the bed. The four future worker anchors (`WorkerDeskSlot1/2`, `WorkerSeat1/2`) sit entirely within empty floor space, verified from $Y = 0$ to $Y = 4.0$ studs.
4. **Collision Envelopes**:
   - Decorative accessories (mug, notebook, pencils, cables, poster) are strictly non-colliding (`CanCollide = false`).
   - Structural furniture (DeskTop, DeskLegs, BedFrame, Headboard, BookcaseSide, Floor, Walls) enforces `CanCollide = true` to prevent character clipping.

---

## 6. Avatar Scale & Ergonomics

All furnishings are built to standard Roblox avatar ergonomics (assuming standard R15/R6 dimensions: ~5 studs height, ~2 studs width, ~1 stud depth):

- **Desk Working Height**: The upper surface of `DeskTop` is frozen at $Y = 3.35$ studs. This allows standard avatar arms to reach the keyboard and phone comfortably while standing or sitting.
- **Bed Height**: The top surface of `Mattress` sits at $Y = 1.88$ studs, allowing natural avatar seating without legs sinking into geometry.
- **Door Clearance**: Height of 7.3 studs and width of 3.7 studs easily accommodates jumping or sprinting avatars without head clipping.
- **ProximityPrompt Reachability**: The `DashboardPrompt` activation distance is set to **10 studs** (server validation requires $\le 12$ studs). A player standing anywhere near the front of the desk triggers the prompt cleanly.

---

## 7. Permitted vs. Forbidden Modifications

| Component | May Be Modified in Future Polish? | Boundary / Constraint |
|---|---|---|
| **Room Dimensions (24×24)** | **NO** | Hardcoded into spatial assumptions and camera sweeps. |
| **12 Named Anchors** | **NO** | Core server contract. Moving or renaming breaks `WorldService`. |
| **Desk Surface Height (Y=3.35)** | **NO** | Frozen placement height for OldCRT, phones, and future PC. |
| **Window Frame / Mullions** | **YES** | May adjust frame thickness or sill bevel without moving opening. |
| **Decorative Props (Mug/Book)**| **YES** | May add subtle dressing props as long as part budget $\le 250$. |
| **Poster Artwork** | **YES** | Geometric abstract designs only; no uploaded external image IDs. |
| **Curtain Drapes** | **YES** | Minor folding tweaks allowed if they don't block desk sightlines. |
| **Ceiling Lid** | **NO** | Adding a solid ceiling lid is strictly forbidden (breaks camera orbit). |
