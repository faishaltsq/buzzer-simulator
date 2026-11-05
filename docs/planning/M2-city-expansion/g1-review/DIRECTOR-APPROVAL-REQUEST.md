# Director approval request — M2-G1

Agent 2 requests decisions on the items below. Each item states what stays
frozen until it lands. **No item in this package is approved by the agent.**

## Decisions requested

| # | Decision | Agent 2 recommendation | Stays frozen until decided |
|---|---|---|---|
| R1 | **D1 backdrop extent** | Adopt the centred candidate `X = -120…+120` for the A1 review copy; freeze only after the C1 Studio capture | baseline `X = +16…+160` remains canonical; V-03 stays open |
| R2 | **D2 kiosk design** | Build option B (narrow open-frame) first inside the frozen Z6 | zone extent and `City_Prompt_Boards (0, 3, 68)` unchanged; no extent change is requested |
| R3 | **D3 porch treatment** | Option B1 — flush slab + return walls bridging the 2.56-stud recess; no roof plane | `City_HomeDoor (-6, 3.65, 16)`, frozen `Door`, camera anchors, window aperture |
| R4 | **D4 shop hosts** | Keep hosts at `±68`; counters face the plaza at `X = ±60`; amend to `±58` only if a real walk-up fails | host coordinates and the 10/12-stud contract |
| R5 | **D1 verification pose** | Accept the nine capture poses (C1–C9) as the M2-A1 evidence set | no camera override is shipped |

## Pending — test required (cannot be closed in 2D planning)

| # | Item | Blocking evidence |
|---|---|---|
| P1 | Live camera visibility of the proposed skyline | C1 capture from `CameraFocus` in an isolated Studio view |
| P2 | Fountain occlusion by the kiosk (either option) | 3D stoop-to-fountain sightline test with option B built |
| P3 | `StreamingEnabled` and lighting values on the built review place | direct Studio read; never inferred from an absent Rojo property |
| P4 | Stock exit/return camera placement | recorded capture before any override is discussed |
| P5 | Shop prompt reachability with a real avatar root | A1 walk-up measurement; the XZ estimate is not proof |

## Explicitly not requested (do not infer approval)

- No M2-A1 implementation authorisation.
- No `CityService`, remote, prompt logic or transition service.
- No economy, catalog, DataStore schema or profile change.
- No published Roblox place.
- No change to Agent 1's BS-15 branch.
- No kiosk move outside Z6, and no prompt relocation.

## Deferred to future milestones (D8)

| Feature | Milestone | Gate |
|---|---|---|
| Cosmetic ownership persistence | M2-B/M2-C | M2-G3 shop/event review + approved storage and replay semantics |
| Event reward persistence | M2-B/M2-C | M2-G3 + idempotency contract |
| New profile schema (`cityUnlocks` v2) | M2-C | M2-G4 schema decision |
| New upgrade prices / worker systems / income bonuses | not scheduled | director decision; A1 adds none of these |

Recommendation: defer every feature that needs new persistent data until its
design, migration and idempotency contracts are explicitly approved.

## After this package lands

1. Director reviews the boards (`G1-DESIGN-REVIEW-preview.svg`) and this request.
2. Accepted items update the parent contract; rejected items keep the baseline.
3. M2-A1 may then be assigned, using `M2-A1-READINESS.md` as its checklist.
4. M2-G2 (blockout visual sign-off) remains separate from M2-G1 acceptance.
