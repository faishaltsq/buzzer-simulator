# Buzzer Simulator — Asset Manifest

BS-05 world prefabs. Every asset below is **original**, authored as a pure
Roblox Part kit with simple materials. No Toolbox models, no imported meshes,
no external asset files, no scripts, no RemoteEvents.

## Inventory

| Prefab | Purpose | Authoring method | Dependencies | Licensing |
|---|---|---|---|---|
| `Bedroom.rbxmx` | Traversable rented bedroom with all stable named anchors | Part kit, 39 BaseParts, `tools/gen_world_prefabs.py` | None | Original, no external assets |
| `OldCRT.rbxmx` | BuzzerOS dashboard-access terminal. **Not** a productive device | Part kit, 8 BaseParts + 1 BillboardGui label | None | Original, no external assets |
| `PhoneCheap.rbxmx` | Starting productive phone: chunky, worn, small dim screen | Part kit, 17 BaseParts | None | Original, no external assets |
| `PhoneFast.rbxmx` | Purchased productive phone upgrade: slimmer, larger bright screen, camera bump | Part kit, 7 BaseParts | None | Original, no external assets |

## Anchor inventory (`Bedroom.rbxmx`)

All twelve anchors required by docs/03 are present and named exactly:

| Anchor | Role |
|---|---|
| `Spawn` | Player spawn reference |
| `PlayerDesk` | Player desk surface |
| `DashboardPromptAnchor` | Stable room-owned dashboard prompt. **Never** inside the CRT prefab |
| `TerminalSlot` | Displays `OldCRT`; reserved footprint for `PCRumah` in BS-11 |
| `PhoneSlot` | Displays the equipped productive phone |
| `WorkerDeskSlot1` | Reserved M1 capacity only |
| `WorkerSeat1` | Reserved M1 capacity only |
| `WorkerDeskSlot2` | Reserved M1 capacity only |
| `WorkerSeat2` | Reserved M1 capacity only |
| `CameraFocus` | Accessible camera position for the future BuzzerOS interface |
| `Door` | Room entry |
| `LightGroup` | Warm ceiling light plus desk lamp |

## Visual direction

Cohesive stylized low-poly rented bedroom / early creator setup. Warm
restrained palette: cool-grey slate walls and floor, reddish-brown wood
furniture and trim, institutional-white CRT, bright-yellow cheap phone,
bright-blue fast phone. Two clearly distinct phone silhouettes so the upgrade
reads at desk distance. A bed, window, shelf, plant and baseboard trim give
the room a lived-in feel without crowding the walkable route.
## Visual Placement and Transforms

Models in model space have their screens facing -Z. Players approach the desk
from the south (+Z). In `WorldService`, each model is positioned relative to its
slot anchor using `Model:PivotTo()` with an upright 180° Y rotation
(`CFrame.Angles(0, math.pi, 0)`) so screens point directly toward the player:

| Model | Slot Anchor | Pivot Y Offset | Rotation | Resting Bottom Y | Desk Clearance |
|---|---|---|---|---|---|
| `OldCRT` | `TerminalSlot` (7.4, 3.35, -4.0) | +1.4 studs | `CFrame.Angles(0, math.pi, 0)` | 3.35 studs | Exact resting fit, 0 desk penetration |
| `PhoneCheap` | `PhoneSlot` (4.6, 3.35, -3.8) | +1.0 studs | `CFrame.Angles(0, math.pi, 0)` | 3.35 studs | Exact resting fit, 0 desk penetration |
| `PhoneFast` | `PhoneSlot` (4.6, 3.35, -3.8) | +1.1 studs | `CFrame.Angles(0, math.pi, 0)` | 3.35 studs | Exact resting fit, 0 desk penetration |

- **Separation on Desk**: With `TerminalSlot` at X = 7.4 and `PhoneSlot` at X = 4.6,
  horizontal clearance between the CRT left bezel (X = 5.8) and phone right edge
  (X = 5.15) is 0.65 studs, preventing any mesh collision or overlap.
- **Floor Clearance**: The CRT bottom rests at Y = 3.35, providing 2.85 studs of
  clearance above the bedroom floor (Y = 0.5).

## Dashboard Prompt (`DashboardPromptAnchor`)

A usable `ProximityPrompt` named `DashboardPrompt` is authored directly inside
`DashboardPromptAnchor` at (7.4, 3.6, -2.4):
- `ActionText`: `"Open BuzzerOS"`
- `ObjectText`: `"BuzzerOS Terminal"`
- `MaxActivationDistance`: `10` studs
- `HoldDuration`: `0` seconds (instant trigger)
- `RequiresLineOfSight`: `false`

### Prompt Validation Contract
- `WorldService.ValidateDashboardPrompt(player, prompt)` accepts either the
  `ProximityPrompt` instance or its anchor `BasePart`.
- Verifies room ownership (`prompt:IsDescendantOf(roomFolder)`).
- Verifies prompt identity matches the server-owned instance or anchor.
- Validates that the player has a living character (`Humanoid.Health > 0` and
  valid `HumanoidRootPart`).
- Measures distance authoritatively from `DashboardPromptAnchor.Position` to
  `HumanoidRootPart.Position` (server limit: 12 studs).

## Layout notes

- 24 x 24 stud room, 10 studs tall, fully enclosed with a ceiling.
- Clear walkable route from `Spawn` (0, 0.6, 6) north to the desk at (7, 3.2, -4).
- Desk against the east wall; `TerminalSlot` on the desk, `PhoneSlot` beside it.
- `DashboardPromptAnchor` sits in front of the terminal at (7.4, 3.6, -2.4), on
  the room side, so it survives any CRT/PC replacement unchanged.
- Two worker stations reserved along the west wall at (-8, 3.2, -8) and
  (-8, 3.2, -2), each with a seat, both clear of the spawn-to-desk route.
- `CameraFocus` at (7, 5.5, 3) looks at the desk from the room side.
- No free productive PC at initial spawn. `TerminalSlot` holds only `OldCRT`.

## Manual Roblox Studio Review Checklist

*Status: Interactive visual review pending human operator verification (headless CI environment).*

To verify in Roblox Studio:
1. Open `build/BuzzerSimulator.rbxlx` in Roblox Studio.
2. Start a Local Test or Play Solo session.
3. Verify the following viewpoints:
   - **Player spawn**: Character spawns cleanly at `Spawn` (0, 0.6, 6) facing north toward the desk with unobstructed walkway.
   - **Desk close-up**: CRT and equipped phone rest upright on top of the desk with no z-fighting, floating, or penetration.
   - **CRT and cheap phone**: Chunky yellow phone with dim screen and cracked corner sits to the left of the beige CRT terminal with distinct physical separation.
   - **CRT and fast phone**: After purchasing/equipping `phone_fast`, the sleek blue phone with bright cyan screen cleanly replaces the cheap phone in the exact same slot without duplicating models.
   - **Overhead showing reserved worker stations**: Both worker desk/seat anchors on the west wall are clearly visible and unobstructed.
   - **Dashboard ProximityPrompt**: Approaching the desk displays the `[E] Open BuzzerOS` prompt on the terminal; triggering it is accepted within 10 studs and rejected beyond 12 studs.
   - **Phone emulator view**: Test in Studio Device Emulator (iPhone / mobile resolution) to ensure terminal label and prompt remain legible.

## Known limitations

1. **Roblox Studio visual acceptance is pending human verification.** Rojo builds
   and Luau unit regressions confirm model transforms, anchor clearances, and
   prompt bindings. The director should perform the manual Studio review checklist
   above.
2. **`PCRumah.rbxmx` does not exist** and is deliberately not mapped. BS-11
   authors it and swaps `TerminalSlot`.
3. **Worker desk/chair kits are reserved anchors only.** No physical desk or
   seat geometry is placed at `WorkerDeskSlot*` / `WorkerSeat*`; they are
   capacity markers for BS-12/BS-13.
4. **No audio.** docs/06 gate 5 defers original audio to a later task.
5. **Part count is 39** in the bedroom, well under the 250-part V0 budget.
## Regeneration

```
python tools/gen_world_prefabs.py
```

The generator is deterministic and checked in, so the prefabs can be rebuilt
and diffed. It emits one `<Properties>` block per `<Item>`, which is the shape
Roblox Studio and Rojo expect.
