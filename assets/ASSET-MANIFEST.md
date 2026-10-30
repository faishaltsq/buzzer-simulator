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

## Layout notes

- 24 x 24 stud room, 10 studs tall, fully enclosed with a ceiling.
- Clear walkable route from `Spawn` (0, 0.6, 6) north to the desk at (7, 3.2, -4).
- Desk against the east wall; `TerminalSlot` on the desk, `PhoneSlot` beside it.
- `DashboardPromptAnchor` sits 1.6 studs in front of the terminal, on the room
  side, so it survives a CRT replacement unchanged.
- Two worker stations reserved along the west wall at (-8, 3.2, -8) and
  (-8, 3.2, -2), each with a seat, both clear of the spawn-to-desk route.
- `CameraFocus` at (7, 5.5, 3) looks at the desk from the room side.
- No free productive PC at initial spawn. `TerminalSlot` holds only `OldCRT`.

## Known limitations

1. **Roblox Studio visual acceptance is pending human verification.** A Rojo
   build proves place assembly, not art quality. The director must review each
   exported prefab in Studio (docs/06 gate 2).
2. **Screenshots not captured.** No Studio Play run was performed, so no
   bedroom/CRT/phone imagery exists yet.
3. **Phone/tablet emulator perspectives pending.**
4. **`PCRumah.rbxmx` does not exist** and is deliberately not mapped. BS-11
   authors it and swaps `TerminalSlot`.
5. **Worker desk/chair kits are reserved anchors only.** No physical desk or
   seat geometry is placed at `WorkerDeskSlot*` / `WorkerSeat*`; they are
   capacity markers for BS-12/BS-13.
6. **No audio.** docs/06 gate 5 defers original audio to a later task.
7. **Part count is 39** in the bedroom, well under the 250-part V0 budget, but
   not yet profiled on a lower-end phone.

## Regeneration

```
python tools/gen_world_prefabs.py
```

The generator is deterministic and checked in, so the prefabs can be rebuilt
and diffed. It emits one `<Properties>` block per `<Item>`, which is the shape
Roblox Studio and Rojo expect.
