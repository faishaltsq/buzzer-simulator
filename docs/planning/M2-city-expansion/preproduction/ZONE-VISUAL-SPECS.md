# Zone visual specifications

**Planning only.** Exact extents and anchor positions are inherited from the parent
`../02-WORLD-STRUCTURE.md`. Budget allocations are maintained only in
[CITY-PERFORMANCE-BUDGET.md](CITY-PERFORMANCE-BUDGET.md), not separate bottom-up guesses.
No shop, stage or decoration is added to A1 just because its later design is listed here.

| Zone / phase | Visual identity | Primary elements | Interaction boundary | Camera / proof |
|---|---|---|---|---|
| Z0 Home, A | Existing plaster/cream with sage door | Exterior cladding, stoop, porch returns if needed, low parapet; optional plant and house number after blockout | New interior prompt host and physical exterior HomeDoor; no modification to frozen Door | Preserve north window opening. No interior ceiling or untested roof. Check indoor orbit and stoop views |
| Z1 Street, A | Ink/navy road, plaster/cream bands, restrained metal lamps | 32-stud road and 8-stud flush bands; two poles; suggested signpost locations | Traversal; later stamp-tour behaviour is not A1 | Six-stud clear route; no prop in spawn throat; measure door-to-board approach |
| Z2 TownCenter, A shell / B props | Plaster paving with cream banding, quiet central fountain | Disc r=40 at (0,112), fountain r=8, lamps; later benches, planters and inert transit shelter | No new fountain prompt or earning surface in A1 | Keep clearance around basin. Build actual rings as segments, not an invented hollow cylinder primitive. Check view from stoop and plaza |
| Z3 East row, B/C | Related but distinct shop silhouettes | ElectroMart amber projecting sign; utility compact navy counter; cosmetics reserved for C | Existing upgrades flow for electronics; utility is free; no new shop price table | Open-front approach must satisfy unchanged 10/12 prompt distances. Do not assume lot midpoint equals counter |
| Z4 West row, B conditional | Timber, sage fabric, pitched awning | Furniture shelving, sample rug/chair, small counter | Cosmetics require explicit catalog, placement and persistence decisions; no stat effects | Optional spill stays outside required walking clearance; no room-budget bypass |
| Z5 EventPlaza, B | Low permanent stage and simple frame | Empty usable venue, schedule board, connector; event-only stalls deferred | Read-only schedule until an approved event path exists | No fake countdown or participation counts. Frame and lighting inside zone/budget |
| Z6 Boards, A | Cream cards, timber frame, sage small awning | Paired boards, open supports; minimal massing in A1 | Later selects/accepts missions; never a composer or second reward engine | Test fountain visibility in 3D before deciding a kiosk move. Any move outside Z6 requires approval |
| Z7 FutureGate, A | Compact plaster/metal closed silhouette | Shutter, lintel, honest future-district sign in detail pass | Locked copy only in later interaction phase; no timer, price or passable opening | Fit massing within allocated zone; no unapproved 18-stud piers outside its extent |
| Backdrop, A | Navy/sage skyline silhouette | At most eight parts under parent budget, non-colliding, non-interactive | No prompts, no rewards | Baseline and proposed X spans distinguished on board. Test actual window aperture, reference camera and heights before closing V-03 |

## Essential versus optional

A1 essential: house/street/plaza massing, backdrop, threshold hosts, minimal kiosk
landmark and anchors needed to inspect baseline coordinates. Gate massing can mark its
reserved extent without adding logic. Scope additions beyond parent task files must be
explicitly agreed; never quietly expand A1 into A-final.

A-final dressing: awnings, primary zone signs, sparse street props, benches and lamps
within phase allocation. Shops, event dressing, cosmetic assets, zone HUD, return-home
chip and NPCs remain in their assigned later phases.

Optional detail is cut before structures, safe paths, marker identity, prompt access or
mobile readability. A decorative object must not imply earning, a locked purchase or a
feature that the phase does not implement.

## Common technical conventions

Original anchored primitive geometry. Structural barriers collide/query; decorative
props follow the parent's non-collide/non-query rule. Markers are invisible and neither
colliding, touchable nor queryable. Geometry never embeds scripts, remotes or external
asset references. Native material choices and sign hosts follow the art-direction file.
Parent Atomic roots and Persistent backdrop intent remain; physical runtime settings
and resulting client visibility are measured, not inferred from this folder structure.
