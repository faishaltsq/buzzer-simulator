# Buzzer Simulator — World and Asset Plan

## Visual premise
One stylized, low-poly rented bedroom visibly becomes a busy home studio. A battered **cheap phone** is the first owned productive device, displayed on a phone pad beside an **old CRT computer used only to enter BuzzerOS**. The CRT cannot produce posts or apply a device multiplier; the interface says so. The fast phone changes its silhouette/light at the phone pad. Buying PC Rumah replaces the old CRT with a modern tower/monitor/keyboard at the terminal slot and becomes the only productive device; the phone becomes an inert desk prop. This gives a visible computer-to-computer upgrade without granting free PC earnings or crowding the desk with two live monitors. Trainee stations use a matching Part kit; a second compact nook makes the chapter-end room feel full without needing a second property prefab. Original fictional iconography; no mismatched Toolbox furniture or hidden scripts.

## Room topology and state
M1 uses one reviewed `Bedroom.rbxmx` with named server anchors `Spawn`, `PlayerDesk`, `DashboardPromptAnchor`, `TerminalSlot`, `PhoneSlot`, `WorkerDeskSlot1`, `WorkerSeat1`, `WorkerDeskSlot2`, `WorkerSeat2`, `CameraFocus`, `Door`, `LightGroup`. Both worker slots fit within a walkable bedroom with clear camera sightlines; **two slots are physical capacity, not free desks**. The server-owned prompt stays at the unreplaced `DashboardPromptAnchor`. `TerminalSlot` displays `OldCRT` until PC Rumah is confirmed, then displays only `PCRumah`. `PhoneSlot` displays the equipped cheap/fast phone until the PC purchase, then a nonproductive owned-phone prop. The same profile `deviceId` determines the sole productive device and both visuals; no separate owned-CRT item/schema. Swaps must not collide with the player, block the prompt, or strand a worker. Server clones the room into a per-user Workspace folder and synchronizes device/desks/workers from confirmed profile IDs on join and after purchases. Do not save Part references or store worker animations in profile.

M2 may add a distinct office prefab with the same core anchor contract after a separate review of content, measured player balances, and room-swap recovery. No M1 UI button or numeric M2 price should imply that a not-yet-authored agency is purchasable. A worker rig is local ambient presentation; server income never depends on rig movement or animation.

## Asset inventory and authorship
| Asset family | V0 internal | M1 candidate | Acceptance |
|---|---|---|---|
| Bedroom shell, terminal/phone slots, player route | yes | reused | Walkable; CRT versus productive phone legible; stable prompt |
| Old CRT (`OldCRT.rbxmx`), dashboard only | yes | replaced by PC | Clearly obsolete; no free production; one reviewed simple Part model |
| Cheap/fast phones | yes | reused | Distinct silhouette at spawn/desk distance |
| PC Rumah (`PCRumah.rbxmx`), monitor/keyboard/light | no | yes | Replaces CRT; visibly more productive; same prompt still reachable |
| Worker desk/chair kit, slots 1 and 2 | no | yes | Both seats/nooks fit, no clipping or blocked corridor |
| Trainee rig, reused twice | no | yes | Two distinct occupied desks, no pathfinding/physics economy |
| Feed/brief icons and original flat art | limited | expanded | Readable on narrow phone; all fictional |
| Laptop/office prefab | no | no | Future only if distinct mechanics and art budget justify them |

Agents may block out geometry with Parts but cannot certify cohesive art or imported mesh quality. The director reviews each exported `.rbxmx` prefab in Studio. Strip untrusted Script/LocalScript descendants and extraneous remotes; document externally sourced assets and permissions in `assets/ASSET-MANIFEST.md` **when** assets are created. Prefer reusable Parts and simple materials; unique MeshParts need a visual reason. Rojo supports model files and text sources.[13]

## Practical pipeline and gates
1. Define palette/scale and a reference view from player camera and phone emulator. Studio blockout confirms CRT prompt and phone pad visibility, PC replacement footprint, walking clearance, camera focus, and two valid worker seats.
2. Export approved bedroom/device/desk/trainee prefabs to `assets/world/` and map to `ServerStorage.WorldPrefabs`. Never sync arbitrary Workspace descendants or trust an unreviewed asset.
3. For V0 capture CRT + cheap/fast phone photos; test prompt distance and camera with both phones. For M1 capture CRT-to-PC replacement and first/second desk/hire; the two-worker state must read as a home studio without a HUD explanation.
4. Test reconnect and model recovery after a saved purchase when a local visual swap failed. If a required prefab is missing, surface error and restore the model on next sync; do not quietly strand confirmed ownership.
5. Use original or rights-reviewed short audio for publish/claim/purchase; record IDs/ownership/fallback in the asset manifest. Give a volume/mute control; never block gameplay on sound loading.

Initial **test budgets, not platform limits**: V0 room under 250 placed decorative BaseParts; M1 two simple ambient worker rigs; at most 12 authored feed posts plus ten own summaries; no per-frame room scans or per-worker server economy loops. Profile on a lower-end phone and revise budget based on frame time, memory, overdraw, and replication. Roblox performance guidance recommends event-driven scripts and reuse.[9] Human visual sign-off remains separate from Rojo build success.

## Sources
[9] https://create.roblox.com/docs/performance-optimization/design
[13] https://rojo.space/docs/v7/sync-details
