# D5 + D6 — Camera and streaming checklist

Two verification contracts for M2-A1. Nothing here is claimed as a runtime
fact: every row is either a **read** (do this in Studio/A1 and record the value)
or a **test** (do this and record pass/fail). No streaming service, camera
controller or remote is created by M2-G1.

## D5 — Streaming readiness

### Reads (record the actual value; never infer from an absent property)

| # | Check | How | Acceptance |
|---|---|---|---|
| S1 | `StreamingEnabled` on the built review place | read the place property in Studio, not the Rojo JSON | value recorded verbatim, whatever it is |
| S2 | Lighting/technology settings | read the place settings | recorded; no legacy-renderer forcing |
| S3 | Client-side stream behaviour at the door | playtest, observe | no zone pops mid-transition |
| S4 | `Player:RequestStreamAroundAsync` availability and context | verify the current API and whether the call belongs to the client or server during A2 integration | documented before A2 writes any code |

### Build properties (A1 authoring rules)

| # | Check | Acceptance |
|---|---|---|
| S5 | Zone models are **atomic** — one model per zone, no model split across a boundary | assembled by a single `CFrame.new(origin)` per zone |
| S6 | Backdrop is **Persistent** intent | never streamed out while the player is at the desk |
| S7 | Anchor parts live under `City_Anchors` (a Folder) | a Folder does **not** exempt them from client streaming |
| S8 | No duplicate marker in both a zone prefab and the marker export | scoped lookup, never a global `FindFirstChild` |
| S9 | Prompt identity is server-owned | identity survives client replication |

### Transition behaviour (A2+ obligations, recorded here as requirements)

| # | Requirement |
|---|---|
| S10 | Safe arrival: destination validated against ground with a short raycast; no spawn inside geometry |
| S11 | Retry and failure handling: hold the fade until the zone is ready; bounded retries; on failure return the player to the original position |
| S12 | Return transitions: camera and input restored **once**, even across repeated activation, death and respawn |
| S13 | Rejoin stays indoors until the player chooses to leave again |

## D6 — Camera experience: nine compositions

Baseline: the **existing** camera controller and `+Z` spawn facing. No new
controller, no override shipped by A1. Each row is one fixed capture pose to be
taken in Studio and archived under `docs/evidence/m2-a1/`.

| # | Composition | Camera position (world studs) | Look at | Must see | Must not see | Acceptance |
|---|---|---|---|---|---|---|
| C1 | Bedroom window → skyline | at `CameraFocus (7, 5.5, 3)` | north through aperture | skyline, haze, one tower | street, shop backs, NPCs | silhouette inside the aperture; fails ⇒ reopen D1 |
| C2 | Interior door approach | room centre `(0, 5.5, 6)` | door plane `(-6, 3.65, 11.6)` | door, prompt host | plaza, shops | host discoverable at activation distance |
| C3 | First exterior arrival | `City_Spawn (-6, 4.5, 20)` | +Z down the street | street, boards, plaza hint | interior seams | grounded character, usable camera |
| C4 | Residential lane | mid-street `(0, 5, 44)` | +Z | kiosk, plaza edge, gate far | bedroom interior | 6-stud clear route visible |
| C5 | Mission kiosk | 10 studs north of `(0, 3, 68)` | kiosk face | both boards, fountain through the bays | overlapping prompts | fountain visible ⇒ D2 option B confirmed |
| C6 | Town centre fountain | plaza north edge `(0, 5, 84)` | `(0, 0, 112)` | fountain, kiosk behind | floating geometry | landmark reads at 60 studs |
| C7 | Shops (east row) | plaza edge `(50, 5, 108)` | `(68, 0, 108)` | counter, sign, prompt | interior of a shop | prompt legible from standing position |
| C8 | Future district gate | `(0, 5, 150)` | `(0, 0, 168)` | gate, skyline above | a passable opening | closed silhouette, honest copy |
| C9 | Return home | stoop `(-6, 4.5, 16.5)` | north face | `City_HomeDoor`, leaf, prompt | frozen `Door` | prompt reachable at ≤ 10 studs |

Mobile captures repeat C1, C3 and C4 at 640×360 and 360×640; desktop captures
use the same poses. A capture is evidence only when the file, pose and mode are
recorded together.

## Camera invariants

1. Character yaw does not rotate the existing camera — do not treat a yaw fix
   as a camera fix.
2. Record stock-camera placement at exit and return before any override is
   considered.
3. No zone may require the camera to enter geometry (mobile rule, parent `03`).
4. Any temporary camera binding used for capture is unbound before the evidence
   is declared complete.
