# First exit storyboard — evidence by phase

**Experience targets, not a scripted cutscene or observed timings.** Use the existing
camera controller; the parent travel contract owns transition behaviour. No camera
controller, fade overlay or prompt logic is introduced in A1.

| Shot | Player / reference view | Required read | Proof owner |
|---|---|---|---|
| S1 Studio complete | Inside, after existing tier/desk/worker condition | Existing home studio remains unchanged; city gate derived server-side, not a new saved flag | A2+ integration |
| S2 Door approach | Room centre and door approach | Interior host discoverable at activation distance; no prompt attached to frozen Door | A1 host placement; A2+ prompt behaviour |
| S3 Transition | Interior prompt activated | Validate exact host/prompt, living character and ≤12-stud distance; no client destination | A2+ server/client transition |
| S4 Arrival | Actual City_Spawn with stock camera | Safe grounded character, usable camera, controls restored; facade seams not visible | A1 manual review placement; A2+ transition capture |
| S5 Lane | Exterior stoop looking +Z | Clear lane toward boards; fountain visibility checked, not guaranteed by drawing | A1 geometry |
| S6 Boards | Approaching kiosk | Identifiable panels and an unobstructed path; no competing stacked prompts | A1 geometry; A2+ mission surface |
| S7 Plaza | Plaza north edge and centre | Fountain landmark and reserved row positions; no new shops in A1 | A1 massing; B shop visuals |
| S8 Shops | Open counter approach | Appropriate prompt from actual standing position, existing purchase authorization path | B |
| S9 Horizon | Window reference and future gate | Window skyline remains visible; future district is honestly closed | A1 geometry; later locked-copy wiring |
| S10 Return | Exterior HomeDoor to indoor Spawn | Ground/clearance check, camera/input restore once, normal indoor respawn behaviour | A2+ |

## Transition invariants retained from parent

A2+ uses same-place server-authoritative placement, not TeleportService and not passage
through the closed wall. Preserve the specified fade/accessibility behaviour and
streaming hold, one retry, and safe failure at the original position. A fade is a small
transition overlay, not automatically a new navigation screen prohibited by the UX plan.
If client work is required earlier than a broad ownership table suggests, explicitly
assign it to transition integration rather than removing the requirement.

Handle death, respawn, repeated activation, stale responses, and failed streaming without
leaving input/camera locked. Destination uses measured avatar root height and real ground /
overlap checks, not the marker's Y=0.6 as a root centre. Door and room are never edited.

Changing character facing alone does not guarantee an exterior camera shot. Record the
actual controller response; temporary evidence cameras must not be confused with the
player's arrival camera or left in production.

## Evidence set for A1

Desktop 1280×720: stoop looking cityward, exterior house, plaza, door approach and window
from CameraFocus. Mobile emulation: 640×360 and 360×640 parent-required views. Optional
iPhone 14 views supplement, not replace, those dimensions. Record device/emulator,
viewport, camera pose, build, mode, counts and walk timings in the manifest.

A1 may use temporary manual placement for geometry review; label it explicitly. No
successful exit/return service is claimed before A2+ exists. Only genuine Studio views
close visual runtime criteria; generated masterplan previews are concept evidence only.
A real phone performance check is separate from emulator layout inspection.

No mandatory 90-second path, unobserved camera boom length or fixed horizontal FOV is
asserted here. Measure first-run behaviour in the owning milestone.
