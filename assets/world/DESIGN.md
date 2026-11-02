# ASSETS/WORLD — WORLD PREFAB CONVENTIONS & ARCHITECTURE

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../../docs/DESIGN.md)

---

## 1. Directory Purpose & Rojo Integration

The `assets/world/` directory contains all authoritative 3D world environment and equipment prefabs for *Buzzer Simulator*.

These prefabs are synchronized directly into Roblox Studio via Rojo:

```json
"ServerStorage": {
  "$className": "ServerStorage",
  "WorldPrefabs": {
    "$className": "Folder",
    "Bedroom": { "$path": "assets/world/Bedroom.rbxmx" },
    "OldCRT": { "$path": "assets/world/OldCRT.rbxmx" },
    "PhoneCheap": { "$path": "assets/world/PhoneCheap.rbxmx" },
    "PhoneFast": { "$path": "assets/world/PhoneFast.rbxmx" }
  }
}
```

**CRITICAL INVARIANT**: Never rename, move, or delete files in this folder. Doing so breaks `default.project.json`, `test.project.json`, and all server spawning logic in `src/server/WorldService.luau`.

---

## 2. Prefab Inventory & Specifications

| Prefab File | Role | BaseParts | PrimaryPart | Pivot Offset Y | Detailed Spec Link |
|---|---|---:|---|---:|---|
| [`Bedroom.rbxmx`](Bedroom.rbxmx) | Complete player studio environment | 155 | None (Folder) | 0.00 | [`assets/design/specs/Bedroom.md`](../design/specs/Bedroom.md) |
| [`OldCRT.rbxmx`](OldCRT.rbxmx) | Non-productive BuzzerOS terminal | 52 | `MonitorBody` | +1.40 | [`assets/design/specs/OldCRT.md`](../design/specs/OldCRT.md) |
| [`PhoneCheap.rbxmx`](PhoneCheap.rbxmx) | Starter productive phone | 25 | `Body` | +1.00 | [`assets/design/specs/PhoneCheap.md`](../design/specs/PhoneCheap.md) |
| [`PhoneFast.rbxmx`](PhoneFast.rbxmx) | Tier 1 upgraded productive phone | 23 | `Body` | +1.10 | [`assets/design/specs/PhoneFast.md`](../design/specs/PhoneFast.md) |

---

## 3. World Prefab Rules & Technical Invariants

### 3.1. Local Coordinates & Orientation
- **Local Screen Vector**: All desktop monitors, screens, and phone displays must be authored facing **local $-Z$**.
- **Room Placement Rotation**: When spawning devices on desk anchors, `WorldService.luau` applies a $180^\circ$ Y-axis rotation (`CFrame.Angles(0, math.pi, 0)`), orienting screens cleanly toward $+Z$ (the approaching player).
- **Desk Working Height**: The upper surface of the desk is fixed at **$Y = 3.35$ studs**. All desktop items set their bottom contact plane at $Y = 0$ in model space.

### 3.2. Structural Anchors
`Bedroom.rbxmx` must contain the 12 immutable anchors:
- `Spawn`, `PlayerDesk`, `DashboardPromptAnchor`, `TerminalSlot`, `PhoneSlot`, `WorkerDeskSlot1`, `WorkerSeat1`, `WorkerDeskSlot2`, `WorkerSeat2`, `CameraFocus`, `Door`, `LightGroup`.
- All technical anchors must enforce:
  - `Transparency = 1`
  - `Anchored = true`
  - `CanCollide = false`
  - `CanTouch = false`
  - `CanQuery = false`

### 3.3. Security & Clean Model Gate
Every file in `assets/world/` must be a clean, inert container:
- **No `Script` or `LocalScript` instances**.
- **No `RemoteEvent` or `RemoteFunction` instances**.
- **No external asset URLs** (`rbxassetid://`).
- Built-in Roblox materials only (`SmoothPlastic`, `Wood`, `Metal`, `Fabric`, `Glass`, `Neon`).

### 3.4. Lighting Rules
- All point lights must live inside the `LightGroup` folder in `Bedroom.rbxmx`.
- Maximum 4 light sources per room.
- `Shadows = true` is enforced on all light sources.
- No unshielded neon slabs or ambient light overrides.
