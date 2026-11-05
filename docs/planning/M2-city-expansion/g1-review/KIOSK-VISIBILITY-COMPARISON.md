# D2 — Mission kiosk vs fountain visibility

**Verdict: option B (narrow open-frame) recommended, inside the frozen Z6
extent.** No prompt or zone move is proposed, so no director approval is needed
to build it; the extent/prompt freeze is the guard.

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
| Width | 12 studs (full Z6 width, `X -6…+6`) |
| Height | 9 studs (two cork boards stacked + awning) |
| Support spacing | 12 studs between two full-height side panels |
| Player approach | straight on from the north (door side), stops at the prompt |
| Camera obstruction risk | **high** — the 12-wide × 9-high mass sits on the fountain axis from the stoop |
| Route clearance | 6-stud ring preserved only if the kiosk is centred; approach funnels |
| Estimated BaseParts | ~32 |
| Sign readability | best — full cork area, one glance reads both boards |
| Fountain visibility | **partially obstructed** from the stoop and mid-lane |

## Option B — narrow open-frame board kiosk

| Field | Value |
|---|---|
| Width | 6 studs (`X -3…+3`), boards edge-on to the axis |
| Height | 9 studs |
| Support spacing | 4 posts at `X = -3, -1, +1, +3`, 3.0-stud bays |
| Player approach | straight on; player can step to either board face |
| Camera obstruction risk | **low** — open bays leave ≥ 3 studs of see-through at every height band |
| Route clearance | 6-stud ring fully open on both flanks; no funnel |
| Estimated BaseParts | ~30 |
| Sign readability | good — 6-stud board width is still ~2 screens of mobile text at 10 studs |
| Fountain visibility | **preserved** through the bays; verify in 3D |

## Recommendation and its limits

Option B wins on the three stated priorities (fountain visibility, unobstructed
walking, mobile readability) and stays inside the frozen zone and prompt.

**Not proven in 2D:** whether the fountain is actually occluded by option A, or
fully visible through option B. Angular overlap is a hypothesis; board height,
leg openings and the player camera decide it. M2-A1 step 4 therefore carries a
**3D stoop-to-fountain sightline test** with option B built first, and a move to
the alternative `X = 4…16` placement is rejected by this package because it
exceeds the Z6 east bound (12) and would need an extent decision *and* a prompt
move — both director decisions, neither requested here.
