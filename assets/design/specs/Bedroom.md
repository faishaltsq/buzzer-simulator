# ASSET SPECIFICATION: BEDROOM

> **Asset File**: `assets/world/Bedroom.rbxmx`  
> **Generator Script**: `tools/gen_world_prefabs.py` (`build_bedroom`)  
> **Parent Document**: [`docs/DESIGN.md`](../../../docs/DESIGN.md)

---

## 1. Asset Metadata & Purpose

- **Asset Name**: `Bedroom`
- **File Path**: `assets/world/Bedroom.rbxmx`
- **Gameplay Purpose**: Primary world setting for V0 through M1. Serves as the player's personal living space and commercial base of operations. Houses player workstation, sleeping area, architectural openings, and future staff capacity.
- **Ownership**: Server-owned. Cloned per player into `Workspace.BuzzerRoom_<UserId>` upon character join (`src/server/WorldService.luau`).
- **Parent Hierarchy in Studio**:
  ```
  Workspace
  └── BuzzerRoom_<UserId> (Folder)
      ├── Bedroom (Model)
      │   ├── Floor, Floorboard (x12), Walls (x5), Baseboards (x8)
      │   ├── Door, DoorJamb, DoorLintel, DoorInset, DoorHandle
      │   ├── WindowGlass, WindowMullion (x3), WindowRail (x3), WindowSill, Curtains
      │   ├── DeskTop, DeskLegs (x3), DeskAprons, Drawers (x3), DrawerPulls (x3)
      │   ├── BedFrame, BedFeet (x4), Headboard, Mattress, Blanket, Pillows (x2)
      │   ├── BedsideTable, Rug, Bookcase, Books, StorageBox, Poster, Plant, Mug, Cables
      │   ├── Spawn, PlayerDesk, DashboardPromptAnchor (ProximityPrompt), CameraFocus
      │   ├── TerminalSlot, PhoneSlot, WorkerDeskSlot1/2, WorkerSeat1/2
      │   └── LightGroup (Folder)
      │       ├── RoomWarmth (PointLight)
      │       ├── DeskPool (PointLight)
      │       └── SoftDaylight (PointLight)
      ├── OldCRT (Model, placed at TerminalSlot)
      └── PhoneCheap / PhoneFast (Model, placed at PhoneSlot)
  ```

---

## 2. Geometric & Physical Properties

- **Overall Dimensions**: $24.0\text{ studs (W)} \times 10.0\text{ studs (H)} \times 24.0\text{ studs (D)}$.
- **Model Pivot**: Origin $(0, 0, 0)$.
- **PrimaryPart**: None (Container Model).
- **Total BasePart Count**: **155 BaseParts** (including 10 technical anchors and 3 light diffusers).
- **Embedded Scripts / Remotes**: **Exactly 0** (clean data container).
- **Physical Collision Profile**:
  - Floor, perimeter walls, desk legs/top, bed frame, and bookcase side enforce `CanCollide = true`.
  - Decorative accessories (cables, books, plant, mug, poster, light fixtures) enforce `CanCollide = false`.
  - Technical anchors enforce `CanCollide = false`, `CanTouch = false`, `CanQuery = false`.

---

## 3. Materials, Palette & Lighting

- **Roblox Materials Used**:
  - `Wood` / `WoodPlanks`: Floor, baseboards, door, desk, bed frame, bookcase.
  - `SmoothPlastic`: Wall plaster, plant leaves, ceramic mug, lamp base.
  - `Fabric`: Mattress piping, blanket, pillows, rug, storage box, curtains.
  - `Metal`: Drawer pulls, door handle, desk lamp stem.
  - `Glass`: North window pane (`Transparency = 0.35`).
- **Color Palette Breakdown**:
  - Walls & Ceiling Trim: `plaster` (`#DBD3BE`), `cream` (`#E9DEC7`).
  - Floor: `wood_dark` (`#654A37`), alternating with `#A07751`.
  - Furniture Joinery: `wood` (`#99704B`), `wood_light` (`#B48B60`).
  - Textiles & Bedding: `linen` (`#F6ECD8`), `sage` (`#84977E`), `sage_dark` (`#506C56`).
  - Brand & Accents: `navy` (`#344451`), `amber` (`#ECBA6F`), `clay` (`#A67358`).
- **Light Sources (`LightGroup`)**:
  - `RoomWarmth` (PointLight): Mount $(1.0, 8.65, 0)$, Color `#FFE8CA`, Brightness 0.75, Range 23.0 studs, Shadows true.
  - `DeskPool` (PointLight): Mount $(10.05, 4.43, -3.4)$, Color `#F2BC79`, Brightness 0.40, Range 8.0 studs, Shadows true.
  - `SoftDaylight` (PointLight): Mount $(3.0, 6.0, -11.0)$, Color `#D0E3E0`, Brightness 0.65, Range 17.0 studs, Shadows true.

---

## 4. Anchor Contract Verification

All 12 required anchors are present at exact specified coordinates:
1. `Spawn`: $(0.0, 0.6, 6.0)$, size $(4, 1, 4)$
2. `PlayerDesk`: $(7.0, 3.35, -4.0)$, size $(7, 0.3, 3)$
3. `DashboardPromptAnchor`: $(7.4, 3.6, -2.4)$, size $(1.5, 1.5, 0.4)$
4. `TerminalSlot`: $(7.4, 3.35, -4.0)$, size $(3, 0.2, 2.6)$
5. `PhoneSlot`: $(4.6, 3.35, -3.8)$, size $(1.4, 0.2, 1.4)$
6. `WorkerDeskSlot1`: $(-8.0, 3.2, -8.0)$, size $(4, 0.4, 2.4)$
7. `WorkerSeat1`: $(-8.0, 1.6, -6.2)$, size $(2, 2, 2)$
8. `WorkerDeskSlot2`: $(-8.0, 3.2, -2.0)$, size $(4, 0.4, 2.4)$
9. `WorkerSeat2`: $(-8.0, 1.6, -0.2)$, size $(2, 2, 2)$
10. `CameraFocus`: $(7.0, 5.5, 3.0)$, size $(1, 1, 1)$
11. `Door`: $(-6.0, 3.65, 11.6)$, size $(3.7, 7.3, 0.18)$
12. `LightGroup`: Folder containing 3 PointLight diffusers.

---

## 5. Visual Quality Assessment & Acceptance Criteria

- **Current Visual Quality**: High domestic charm. The room conveys warmth and lived-in clutter without blocking navigation. Clear open-ceiling camera orbit.
- **Identified Inconsistencies**:
  - Very thin decorative parts on the rug (`RugStripe` thickness 0.01 stud) and mattress piping (0.07 stud) could shimmer under low-resolution anti-aliasing (documented as finding V-02).
  - Outside the north window is raw engine skybox (documented as finding V-03).
- **Recommended Adjustments**: In future polish passes, thicken rug stripes to 0.035 studs and add an exterior windowsill backdrop card.
- **Visual Acceptance Status**: **ACCEPTED (Technical & Architectural)**; Commercial human art sign-off pending.
