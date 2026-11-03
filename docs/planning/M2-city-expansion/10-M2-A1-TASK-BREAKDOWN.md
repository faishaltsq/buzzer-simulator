# 10 — M2-A1 Task Breakdown (Recommended Next Milestone)

> **Purpose**: Turn the recommended first milestone (`07`, §3) into an
> executable, reviewable task list for the implementation session.
> **Status**: Planning. This branch implements none of it.
> **Precondition**: director accepts the coordinate + anchor contract (G1).

---

## Scope

Blockout-only city foundation: house shell, street, town-center massing,
backdrop, door threshold. No shops, no events, no cosmetics, no HUD, no
economy, no schema.

**Out of scope (do not implement while here):**

- any edit to `Catalog.luau`, `EconomyService.luau`, `WorldService.luau`,
  `assets/world/*.rbxmx`, `tools/gen_world_prefabs.py`, or existing tests;
- shop prefabs, cosmetic catalog, event system, minimap, zone labels;
- any new price, tier, reward, or bonus.

---

## Files

| Path | Action | Responsibility |
|---|---|---|
| `tools/gen_city_prefabs.py` | Create | deterministic blockout generator |
| `assets/world/city/HouseExterior.rbxmx` | Create | shell + stoop + facade |
| `assets/world/city/StreetBlock.rbxmx` | Create | road, sidewalks, 2 poles |
| `assets/world/city/TownCenter.rbxmx` | Create | paving, fountain massing, 4 lamps |
| `assets/world/city/CityBackdrop.rbxmx` | Create | 8-part skyline silhouette |
| `assets/world/city/CityAnchors.rbxmx` | Create | `City_*` anchor parts only |
| `docs/evidence/m2-a1/*.png` | Create | desktop + phone blockout shots |
| `docs/planning/M2-city-expansion/02-WORLD-STRUCTURE.md` | Modify only if a coordinate proven wrong | contract correction |

Do **not** touch `default.project.json` in this task unless the blockout is
loaded through Rojo; if it is, that edit is serialized with the current
project-file owner.

---

## Tasks

### T1 — Freeze the contract in the generator

- Encode the coordinate table (`02`, §3) as constants: grid 16, grade 0,
  street `z 18–64`, town center `z 64–160`, gate `z 160–176`, lot width 24,
  facade depth 24.
- Add a generator self-check that asserts every zone pivot matches the table.
- **Verify:** running the generator prints the constants and passes the
  self-check; no `.rbxmx` exported yet.

### T2 — Generate `HouseExterior` blockout

- Wrap the 24×24 room with a 0.6-stud offset shell.
- Cut a doorway at `x -7.85…-4.15`, `y 0…7.3`, aligned to `Door`.
- Parapet at `y = 11.9`; **no roof plane**.
- **Verify:** export, open in Studio, walk to the stoop from inside; no gap at
  the door frame, no z-fighting, no camera clip.

### T3 — Generate `StreetBlock` blockout

- Road `x -12…+12`, sidewalks 8 studs each side, `z 18–64`.
- Two lamp poles, two signpost anchor parts.
- **Verify:** walk from stoop to plaza edge in ≤ 4 s; no prop blocks a 6-stud
  clear path.

### T4 — Generate `TownCenter` blockout

- Paving disc radius 38 at `(0, 0, 112)`; fountain cylinder radius 8.
- Four lamps, four benches (massing only).
- **Verify:** fountain and boards kiosk visible from the stoop; 8-stud clear
  ring around the fountain.

### T5 — Generate `CityBackdrop`

- 8 parts max, `z -200…-120`, one tower mass, two antenna tips.
- `ModelStreamingMode = Persistent` when assembled.
- **Verify:** from the desk camera, the window shows silhouettes, not sky; no
  part is reachable or collidable.

### T6 — Add `City_*` anchors

- Only the anchors listed in `02`, §7, at their exact positions.
- All invisible, anchored, non-colliding, non-touchable, non-queryable.
- **Verify:** a Studio command lists every anchor exactly once; none shares a
  name with the bedroom's 12.

### T7 — Assemble `Workspace.City` and streaming modes

- Folder `City`, per-zone models `Atomic`, backdrop `Persistent`.
- **Verify:** toggle streaming in Studio; no half-visible zone; backdrop
  remains visible indoors.

### T8 — Screenshot evidence

- Desktop 1280×720: stoop view, plaza view, window view.
- Phone 640×360 and 360×640: stoop view, door view.
- **Verify:** files exist in `docs/evidence/m2-a1/`; part count recorded.

### T9 — Regression guard

- Run the existing test suite unchanged.
- Record the exact command and output.
- **Verify:** zero new failures; no modified test files.

### T10 — Review handoff

- Post the screenshots, part count, walk times, and the contract diff.
- Stop. Do not add shops, events, or UI.

---

## Acceptance checklist (mirrors `07`, §3)

- [ ] Door → fountain ≤ 12 s
- [ ] Boards kiosk + fountain visible from the stoop
- [ ] Window shows backdrop, not street
- [ ] No camera clipping at door/plaza
- [ ] Blockout ≤ 450 BaseParts
- [ ] Existing tests untouched and green
- [ ] No economy/schema/HUD change
- [ ] Desktop + phone evidence captured

---

## Estimated effort

1–2 dev-days including Studio review. If it exceeds 3 dev-days, the coordinate
contract is wrong — stop and re-open G1 rather than pushing through.
