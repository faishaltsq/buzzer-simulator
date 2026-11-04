# Decision register — planning complete, implementation gated

This register replaces the initial fourteen-item draft. Unverified diagnoses are now
measurements to perform, not established defects. No proposal is adopted by silence.
The parent blueprint remains unchanged. Director acceptance is a separate act from
completing this planning deliverable.

| ID | Decision or test | Recommended next action | Unchanged baseline / consequence |
|---|---|---|---|
| D1 | Window/backdrop alignment | Review X=-120…120 backdrop with tower reference X=-34.33, Z=-152; validate actual camera and heights | X=16…160 remains baseline; V-03 closure not proven |
| D2 | Kiosk and fountain visibility | Build open/narrow kiosk within Z6 first; inspect from stoop | Keep Z6 X=-12…12 and prompt (0,3,68). A shift to X=4…16 needs extent and anchor approval |
| D3 | Exterior porch | Use return walls to bridge HomeDoor to the chosen shell; preserve window and frozen room | HomeDoor remains (-6,3.65,16); no physical passage through room Door |
| D4 | Shop prompt approach | Prototype counter and walk up using the current 10/12 distances; move hosts to ±58 only if needed and accepted | Hosts remain ±68; parent does not freeze counter geometry |
| D5 | Streaming and transition | Read actual place settings; keep parent streaming intent, add request/hold/retry in A2+ | No inferred streaming=false; no replacement of the fade with an unapproved cut |
| D6 | Spawn camera | Test actual exit/return camera with existing controller | Keep +Z facing; yaw alone is not a camera transition |
| D7 | Budget attribution | Include every live BasePart once; markers fit inside allocation, not automatically on top | 448 A, +510 B, total 958, hard cap 1,200; A1 blockout ≤450 |
| D8 | Cosmetic/event persistence | Before B, define approved storage and replay semantics, or defer those features | No schema expansion or unsupported repeat reward path in A1 |

## Resolved editorial issues

- Correct native stream-readiness API: `Player:RequestStreamAroundAsync` (verify current
  API and owning client/server context during implementation); no Workspace equivalent.
- A Folder of anchors does not guarantee client persistence under streaming.
- Missing Rojo settings do not establish the settings of a live place.
- One SurfaceGui cannot render six signs on six separate part faces simultaneously.
- New city generator may define a native Concrete token locally. It need not modify or
  import the frozen world generator. Parent material approvals still govern.
- Flat grade remains flat; no unapproved kerb risers, tower piers outside zone bounds,
  extra fountain prompt or global lighting changes are introduced by this package.
- Budget allocations already admit invisible parts; the old unbudgeted-anchor overrun
  was unsupported. The old per-module recipes were not measured asset counts.

## Release / ownership gates

BS-14 Go, M2-G1 coordinate acceptance, M2-G2 blockout visual sign-off, M2-G3 shop/event
review, M2-G4 future schema decision and M2-G5 real-device evidence remain distinct.
No commit, document completion or successful board generation substitutes for them.
A1 can be assigned after the required approvals; later services and mutable features
need their own implementation and runtime verification. This package creates none.
