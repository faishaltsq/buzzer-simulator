# World layout and sightlines

## Coordinate ownership

`../02-WORLD-STRUCTURE.md` owns zone extents and positioned `City_*` anchors. The drawing
reads those tables directly. Walkable envelope: X -136…80, Z -24…176 (216 × 200 studs).
North is -Z; the city extends south (+Z) from the room. Grade is Y=0; sidewalk tops
stay at grade too. No 0.4-stud risers are silently added.

A city prefab's parts are **local to its zone pivot**. To export world-table coordinates,
subtract the zone origin once. Assemble at `CFrame.new(origin)` once. Never export
absolute coordinates and then translate them again. House and absolute anchor collection
use origin (0,0,0). Preserve exact non-grid anchor exceptions; not every pivot is a
multiple of 16 and not every extent edge is a multiple of 8.

## What the map means

Solid zones and dots use the baseline. Numbered markers identify the 17 explicitly
positioned BasePart entries, including the physical HomeDoor. Signpost positions are
not frozen by the parent; six suggested positions are labelled separately. A translucent
red dashed backdrop is the proposed alternative, not an additional shipped backdrop.
Illustrative kiosk and shop counter blocks are not authored assets.

The amber outdoor route starts at City_Spawn. It does not cross the closed bedroom
wall and does not go through the fountain. Returning indoors is a validated position
transition in A2+, not physical passage through the Door.

## Distances (arithmetic only)

Straight line from frozen Door XZ=(-6,11.6), at nominal WalkSpeed 16 studs/s:

| Target | Distance | Ideal travel |
|---|---:|---:|
| Boards (0,68) | 56.7 studs | 3.54 s |
| Fountain (0,112) | 100.6 studs | 6.29 s |
| Gate (0,168) | 156.5 studs | 9.78 s |
| Event centre (-108,134) | 159.3 studs | 9.96 s |

These are lower-bound estimates, not observed travel times. Path routing, barriers,
prompt handling and turns make a complete errand longer. A1 measures actual walking;
no promise of completing a round trip inside one reveal duration follows from this table.

## Sightline audit

**Window:** from CameraFocus XZ=(7,3), the opening X=0…6 at Z=-12 projects to
X=-65.33…-3.33 at Z=-152. The baseline backdrop X=16…160 does not cover that slice at
that plane. A candidate tower centre is X=-34.33 at Z=-152. This is a 2D ray calculation
from a reference anchor, not proof of the live camera, tower height or full-volume
visibility. Proposed backdrop X=-120…120 needs director acceptance and a Studio view.
The north exterior shell must preserve the window aperture; a solid new north wall
would invalidate either skyline arrangement.

**Kiosk:** baseline Z6 lies on the fountain approach. A centred opaque board may obscure
part of the fountain, but 2D angular overlap is not proof of 3D occlusion. Board heights,
leg openings and the player camera matter. First test a narrower/open kiosk inside Z6;
do not silently shift it outside the zone. Optional X=4…16 placement exceeds the current
Z6 east bound (12), so it requires an extent decision as well as a prompt move.

**Door:** the frozen south wall is solid and the Door is a closed prop. New exterior
geometry may create a porch around HomeDoor at Z=16 without altering either. If shell
inner face is 12.85 and thickness 0.5, its outer face is 13.35 and HomeDoor's near face
15.91: bridge that 2.56-stud recess with returns if this shell treatment is chosen.
This is a design option, not a proven required shell thickness in the parent.

**Shops:** east prompt X=68 is 12 studs from the lot's plaza-facing edge X=56. The
parent does not freeze the exact counter plane, so access is not proven impossible.
Keep an open approach into the kiosk or propose moving the prompt to X=58; west is
mirrored. Use real HumanoidRootPart distance and server identity validation, not a
lot-centre approximation, in runtime tests.

**Camera:** changing character yaw does not guarantee rotation of the existing camera.
Keep baseline spawn facing +Z. Record stock-camera placement at exit/return before
considering any override or alternative yaw. No camera values are claimed as runtime facts.

## Anchors and streaming

There are 17 positioned part identities in the parent table: 16 invisible markers and
one physical HomeDoor. Six signpost markers make a full design inventory of **22
invisible markers + one physical door = 23 BaseParts**. City_LightGroup is a Folder,
not a part. Zone models and same-named root markers are different paths: the latter
live under City_Anchors; exact lookup must be scoped, not a global FindFirstChild.

Keep parent Atomic zone/Persistent backdrop intent. Rojo files without explicit
Workspace properties do **not** prove an existing place's StreamingEnabled value.
Read the built and live place settings. Anchors in a Folder are not exempt from client
streaming. Server-owned prompt identity persists independently of client replication.
Streaming readiness uses `Player:RequestStreamAroundAsync`, not a Workspace method,
in the later transition phase. Preserve the parent hold/retry/failure contract.
