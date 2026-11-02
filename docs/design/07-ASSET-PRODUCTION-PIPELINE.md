# 07 — ASSET PRODUCTION & INTEGRATION PIPELINE

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Asset Pipeline Architecture

*Buzzer Simulator* implements a deterministic, code-first asset generation and integration pipeline. No assets are imported from untrusted web sources or manually dragged from the Roblox Toolbox.

Every 3D prefab is generated programmatically from Python scripts or vetted Luau builders, exported as a standard Roblox XML model file (`.rbxmx`), tracked directly in Git, and synchronized via Rojo:

```
+-----------------------------------------------------------------------------------+
|                           ASSET PRODUCTION LIFECYCLE                              |
+-----------------------------------------------------------------------------------+
|  1. CODE AUTHORING (tools/gen_world_prefabs.py)                                   |
|     - Uses standard Python library (xml.etree.ElementTree)                        |
|     - Defines exact dimensions, CFrame matrices, colors, materials, and anchors   |
+-----------------------------------------------------------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------------------+
|  2. DETERMINISTIC XML SERIALIZATION (.rbxmx)                                      |
|     - Formats clean, deterministic Roblox XML model files                         |
|     - Writes directly into assets/world/*.rbxmx                                   |
+-----------------------------------------------------------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------------------+
|  3. ROJO PROJECT MAPPING (default.project.json & test.project.json)               |
|     - Maps assets/world/*.rbxmx into ServerStorage.WorldPrefabs                   |
|     - Builds place files: build/BuzzerSimulator.rbxlx & build/BuzzerTests.rbxlx   |
+-----------------------------------------------------------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------------------+
|  4. STATIC & RUNTIME VERIFICATION (StudioMCP / Test Runner)                       |
|     - Verifies part counts, pivot offsets, named anchors, and lack of scripts     |
|     - Runs automated regression test suite across all specs                       |
+-----------------------------------------------------------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------------------+
|  5. HUMAN ART DIRECTOR INSPECTION                                                 |
|     - Multi-angle visual review in Roblox Studio Play mode                        |
|     - Mobile emulator inspection (iPhone 14 portrait 390x844 & landscape 844x390) |
|     - Signs off visual acceptance criteria in docs/evidence/                      |
+-----------------------------------------------------------------------------------+
```

---

## 2. Coordinate System & Placement Conventions

To avoid orientation bugs or model interpenetration during dynamic swaps:

1. **Room Orientation**:
   - The player spawns facing $-Z$ (North, looking toward the window and desk).
   - Furniture against the North wall faces $+Z$ (South, toward the approaching player).
2. **Local Screen Orientation**:
   - In all equipment models (`OldCRT`, `PhoneCheap`, `PhoneFast`, and future `PCRumah`), displays are authored facing **local $-Z$**.
   - `WorldService.luau` applies a standard $180^\circ$ rotation around Y (`CFrame.Angles(0, math.pi, 0)`), orienting the screen directly toward $+Z$ (the player).
3. **Desk Plane Contract ($Y = 3.35$)**:
   - The top surface of `DeskTop` is locked at $Y = 3.35$ studs in room space.
   - All desktop equipment models set their base precisely at $Y = 0$ in model space, with the `PrimaryPart` positioned at half-height.
   - When placed, `WorldService` applies an authoritative vertical offset equal to the model's pivot offset, ensuring zero millimeters of floating air and zero millimeters of desk clipping:

```
+---------------------------------------------------------------------------------------+
|                               MODEL PIVOT SPECIFICATIONS                              |
+-------------------+-------------------+-------------------+---------------------------+
| Prefab Name       | PrimaryPart Name  | PrimaryPart Local | Pivot Offset in           |
|                   |                   | Position (X,Y,Z)  | WorldService.luau         |
+-------------------+-------------------+-------------------+---------------------------+
| `OldCRT`          | `MonitorBody`     | `(0, 1.40, 0)`    | `yOffset = 1.40`          |
| `PhoneCheap`      | `Body`            | `(0, 1.00, 0)`    | `yOffset = 1.00`          |
| `PhoneFast`       | `Body`            | `(0, 1.10, 0)`    | `yOffset = 1.10`          |
| `PCRumah` (BS-11) | `MonitorStand`    | `(0, 1.00, 0)`    | `yOffset = 1.00` (target) |
+-------------------+-------------------+-------------------+---------------------------+
```

---

## 3. Strict Security & Hygiene Standards

All exported `.rbxmx` models must pass strict security sanitization:
1. **Zero Embedded Executables**: World prefabs must contain **no `Script`**, **no `LocalScript`**, and **no `ModuleScript`** instances. Logic belongs exclusively in `src/server/` and `src/client/`.
2. **Zero Unauthorized Network Remotes**: No `RemoteEvent`, `RemoteFunction`, or `BindableEvent` instances inside models.
3. **Zero External Assets**: No unauthorized `MeshPart` meshes, texture IDs, decal IDs, or sound IDs. Built-in Roblox materials and primitive CSG parts are strictly required.
4. **Anchor Integrity**: Every single `BasePart` in world prefabs must enforce `Anchored = true`. Physical unanchored simulation is strictly prohibited.
5. **Collision Optimization**:
   - Invisible anchors and decorative accessories enforce `CanCollide = false`, `CanTouch = false`, and `CanQuery = false`.
   - Structural barriers enforce `CanCollide = true` and `CanQuery = true`.

---

## 4. Part Budgets & Performance Ceilings

Performance on mobile devices is governed by measurable targets verified through real-device profiling (targeting steady $\ge 30\text{ FPS}$ on baseline mobile hardware without persistent $>100\text{ms}$ script stalls), rather than assumed guarantees from part counts alone.

To ensure geometric efficiency, asset budgets strictly separate the **V0 Starter Room** from the **M1 Expanded Studio**:

### 4.1. V0 Starter Room Part Budget ($\le 250$ BaseParts)
In V0 (including BS-09), the starter room consists of the bedroom shell, the OldCRT access terminal, and one owned productive phone (Cheap or Fast):
- `Bedroom.rbxmx`: 155 BaseParts (including 10 technical anchors and 3 light diffusers)
- `OldCRT.rbxmx`: 52 BaseParts
- Equipped Phone: 25 BaseParts (`PhoneCheap`) or 23 BaseParts (`PhoneFast`)
- **Total V0 Furnished Room**: **230–232 BaseParts** (strictly compliant with the $\le 250$ BasePart V0 ceiling).

### 4.2. M1 Expanded Studio Part Budget ($\le 340\text{--}350$ BaseParts)
In M1, the bedroom expands into a functional home studio with hardware replacement, passive worker stations, and animated trainee rigs:
- `Bedroom.rbxmx`: 155 BaseParts
- `PCRumah.rbxmx`: 60 BaseParts maximum (replaces 52-part `OldCRT`; net addition: +8 BaseParts)
- Inert Phone Prop: 23 BaseParts (retained on desk pad as inert keepsake)
- Worker Workstation 1 (`WorkerDeskSlot1` + `WorkerSeat1`): ~30 BaseParts
- Worker Workstation 2 (`WorkerDeskSlot2` + `WorkerSeat2`): ~30 BaseParts
- Client-Side Ambient Trainee Rigs: 2 R15 visual rigs (~15–20 visual parts each, purely client-side with zero server physics or controllers)
- **Total M1 Expanded Studio**: **~320–340 BaseParts** (strictly within the $\le 350$ BasePart M1 ceiling).

```
+---------------------------------------------------------------------------------------------------+
|                                   ASSET BUDGET ALLOCATIONS                                        |
+-------------------------------+-------------------+-------------------+---------------------------+
| Asset Component               | Actual Shipped    | Maximum Ceiling   | Compliance Status         |
+-------------------------------+-------------------+-------------------+---------------------------+
| `Bedroom.rbxmx`               | 155 BaseParts     | 175 BaseParts     | **PASS (Within)**         |
| `OldCRT.rbxmx`                | 52 BaseParts      | 60 BaseParts      | **PASS (Within)**         |
| `PhoneCheap.rbxmx`            | 25 BaseParts      | 30 BaseParts      | **PASS (Within)**         |
| `PhoneFast.rbxmx`             | 23 BaseParts      | 30 BaseParts      | **PASS (Within)**         |
| Total Furnished Room (V0)     | 232 BaseParts     | **250 BaseParts** | **PASS (Within V0)**      |
| Total Furnished Room (BS-09)  | 230 BaseParts     | **250 BaseParts** | **PASS (Within V0)**      |
| `PCRumah.rbxmx` (BS-11)       | 0 (Planned)       | 60 BaseParts      | **BUDGETED (M1)**         |
| Worker Station 1 & 2 (BS-12)  | 0 (Planned)       | 35 BaseParts/desk | **BUDGETED (M1)**         |
| Trainee Rigs x2 (BS-13)       | 0 (Planned)       | Client-only rigs  | **BUDGETED (M1)**         |
| Total Expanded Studio (M1)    | ~320 BaseParts    | **350 BaseParts** | **BUDGETED (Within M1)**  |
+-------------------------------+-------------------+-------------------+---------------------------+
```

---

## 5. Authoring & Integration Procedure for Future Assets

When introducing new assets (e.g. `PCRumah` in BS-11, `WorkerStation` in BS-12):

1. **Implement Generator Function**: Add a new builder function in `tools/gen_world_prefabs.py` utilizing existing `PALETTE` and `MATERIALS` tables.
2. **Execute Generation Script**:
   ```bash
   python tools/gen_world_prefabs.py
   ```
3. **Verify Rojo Mapping**: Ensure the new `.rbxmx` path is registered in both `default.project.json` and `test.project.json` under `ServerStorage.WorldPrefabs`.
4. **Execute Dual Rojo Builds**:
   ```bash
   rojo build default.project.json -o build/BuzzerSimulator.rbxlx
   rojo build test.project.json -o build/BuzzerTests.rbxlx
   ```
5. **Inspect in Studio Play**:
   - Verify pivot height ($Y$ offset) matches slot upper surface.
   - Check multi-angle camera sightlines for visual clipping or z-fighting.
   - Capture mobile portrait ($390 \times 844$) and desktop ($1280 \times 720$) review screenshots.
6. **Archive Evidence & Update Manifest**:
   - Save screenshots into `assets/world/review/` or `assets/ui/review/`.
   - Update `assets/ASSET-MANIFEST.md` with SHA-256 hashes, part counts, and review timestamps.
