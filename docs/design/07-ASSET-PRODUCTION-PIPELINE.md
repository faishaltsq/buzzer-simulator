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

To guarantee steady 60 FPS on low-end mobile devices (e.g. iPhone 8, 2GB RAM Android):

```
+---------------------------------------------------------------------------------------+
|                               ASSET BUDGET ALLOCATIONS                                |
+---------------------------+-------------------+-------------------+-------------------+
| Asset Component           | Actual Shipped    | Maximum Ceiling   | Compliance Status |
+---------------------------+-------------------+-------------------+-------------------+
| `Bedroom.rbxmx`           | 155 BaseParts     | 175 BaseParts     | **PASS (Within)** |
| `OldCRT.rbxmx`            | 52 BaseParts      | 60 BaseParts      | **PASS (Within)** |
| `PhoneCheap.rbxmx`        | 25 BaseParts      | 30 BaseParts      | **PASS (Within)** |
| `PhoneFast.rbxmx`         | 23 BaseParts      | 30 BaseParts      | **PASS (Within)** |
| Total Furnished Room (V0) | 232 BaseParts     | **250 BaseParts** | **PASS (Within)** |
| Total Furnished Room (BS-09)| 230 BaseParts   | **250 BaseParts** | **PASS (Within)** |
| `PCRumah.rbxmx` (BS-11)   | 0 (Planned)       | 60 BaseParts      | **BUDGETED**      |
| Worker Station (BS-12)    | 0 (Planned)       | 40 BaseParts/desk | **BUDGETED**      |
+---------------------------+-------------------+-------------------+-------------------+
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
