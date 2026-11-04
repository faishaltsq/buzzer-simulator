# M2-A0 — City visual pre-production

**Status: planning package complete; implementation and director acceptance not performed.**
This revision supersedes the initial M2-A0 draft in `d0e7ba6`. It removes unsupported
runtime claims, reconciles scope and budgets, and separates approved coordinates from
proposals. It does not modify the parent blueprint or authorize M2-A1.

## Deliverables

| Document | Owns |
|---|---|
| [Art direction](CITY-ART-DIRECTION.md) | Palette, silhouette, materials and signage |
| [World layout](WORLD-LAYOUT-AND-SIGHTLINES.md) | Coordinate provenance, routes, sightline assumptions |
| [Zone specifications](ZONE-VISUAL-SPECS.md) | Zone-by-zone visual intent |
| [Modular kit](MODULAR-ASSET-KIT.md) | Reusable members, pivot and collision conventions |
| [Performance budget](CITY-PERFORMANCE-BUDGET.md) | Canonical phase allocations and measurement gates |
| [First-exit storyboard](FIRST-EXIT-STORYBOARD.md) | Experience and evidence views by phase |
| [Implementation handoff](M2-A1-IMPLEMENTATION-HANDOFF.md) | Ordered A1 work, limits and tests |
| [Decision register](OPEN-DESIGN-DECISIONS.md) | Unresolved contract choices, no invented approvals |
| [Editable masterplan](CITY-MASTERPLAN.excalidraw) | Native editable scene |
| [PNG preview](CITY-MASTERPLAN-preview.png) / [SVG preview](CITY-MASTERPLAN-preview.svg) | Same scene; not Studio captures |
| [Verification report](VERIFICATION.md) | Actual checks and remaining limitations |

## Source hierarchy

The parent `../README.md`, `../02-WORLD-STRUCTURE.md`, `../03-ZONE-SPECIFICATIONS.md`,
`../05-TECHNICAL-PRODUCTION-AND-PERFORMANCE.md` and `../10-M2-A1-TASK-BREAKDOWN.md`
remain the approved planning sources. Frozen bedroom geometry takes precedence over
illustrative drawings. The decision register records conflicts rather than silently
changing them. Where this package conflicts with the parent, stop at the decision gate.

The map generator reads zone extents and positioned anchors from the parent table.
Solid geometry is the baseline. Dashed red overlays are proposals, not adopted positions.
Shop, stage and kiosk footprints on the map are illustrative massing, not frozen geometry.

## Completion boundary

M2-A0 delivers documents and a verified reproducible drawing, not a working city.
M2-A1 remains gated by explicit assignment, M2-G1 and the BS-14 decision. A merge or an
existing commit is not evidence that those gates passed. Human art approval and Studio,
real-device FPS, streaming and DataStore checks are not claimed by this package.
No new commit, push or merge is required to inspect the finished local revision.

Regenerate: `python docs/planning/M2-city-expansion/preproduction/gen_masterplan_board.py`.
Validate: `python docs/planning/M2-city-expansion/preproduction/verify_preproduction.py`.
