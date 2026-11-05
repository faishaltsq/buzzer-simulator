# D2 — Mission kiosk vs fountain visibility

**Verdict: option B (narrow open-frame) recommended, inside the frozen Z6
extent.** No prompt or zone move is proposed. Design acceptance and any later
M2-A1 implementation still require explicit director authorisation.

## Canonical kiosk specification

This is the single source of truth for candidate dimensions (studs) and part
estimates. The comparison tables, coordinate matrix and generated board are
derived from this contract; none is a measured Studio model.

```json
{
  "A": {"width": 12, "depth": 6, "height": 9, "post_count": 2, "post_width": 1, "post_spacing": 11, "parts": 32},
  "B": {"width": 6, "depth": 6, "height": 9, "post_count": 2, "post_width": 1, "post_spacing": 5, "parts": 30}
}
```

Both footprints occupy `Z +65…+71`. A occupies `X -6…+6`, with side panels
`X -6…-5` and `X +5…+6`. B occupies `X -3…+3`, with posts
`X -3…-2` and `X +2…+3` (4-stud central opening). B's rear sign band spans
`X -3…+3`, `Z 69.5…70.5`, `Y 6…9`; the opening is not clear at every height.

## Constraints (frozen)

| Item | Value |
|---|---|
| Z6 extent | `X -12 … +12`, `Z +64 … +72` (inside Z2) |
| Prompt | `City_Prompt_Boards (0, 3, 68)` |
| Kiosk role | selects/accepts missions; never a second composer |
| Route | kiosk sits on the door → plaza approach; 6-stud clear ring around it |
| Budget | 40 BaseParts (`CityBoards.rbxmx`, 30 parts + anchors) |

## Option A — standard solid board kiosk

| Field | Value |
|---|---|
| Width | 12 studs (`X -6…+6`, half the 24-stud Z6 width) |
| Depth | 6 studs (`Z +65…+71`) |
| Height | 9 studs (two cork boards stacked + awning) |
| Support spacing | 11 studs centre-to-centre; 2 full-height side panels, each 1 stud wide |
| Player approach | straight on from the north (door side), stops at the prompt |
| Camera obstruction risk | **high hypothesis** — the 12-wide × 9-high mass sits on the fountain axis from the stoop |
| Route clearance | 6-stud ring preserved only if the kiosk is centred; approach funnels |
| Estimated BaseParts | ~32 |
| Sign readability | best — full cork area, one glance reads both boards |
| Fountain visibility | partial obstruction predicted; **TEST REQUIRED (P2)** |

## Option B — narrow open-frame board kiosk

| Field | Value |
|---|---|
| Width | 6 studs (`X -3…+3`), boards edge-on to the axis |
| Depth | 6 studs (`Z +65…+71`) |
| Height | 9 studs |
| Support spacing | 5 studs centre-to-centre; 2 posts, each 1 stud wide; 4-stud opening |
| Player approach | straight on; player can step to either board face |
| Camera obstruction risk | **low hypothesis** — central opening below the rear sign band; verify camera ray height |
| Route clearance | ≥ 6-stud clear path required on both flanks; collision proof pending |
| Estimated BaseParts | ~30 |
| Sign readability | good predicted; 360×640 readability **TEST REQUIRED** |
| Fountain visibility | preservation predicted through the opening; **TEST REQUIRED (P2)** |

## Recommendation and its limits

Option B is preferred for the three stated priorities (fountain visibility,
unobstructed walking, mobile readability); these remain hypotheses. Both
candidates stay inside the frozen zone without moving the prompt.

**Not proven in 2D:** whether the fountain is actually occluded by option A, or
fully visible through option B. Angular overlap is a hypothesis; board height,
leg openings and the player camera decide it. M2-A1 build step 6 therefore carries a
**3D stoop-to-fountain sightline test** with option B built first, and a move to
the alternative `X = 4…16` placement is rejected by this package because it
exceeds the Z6 east bound (12) and would need an extent decision *and* a prompt
move — both director decisions, neither requested here.
