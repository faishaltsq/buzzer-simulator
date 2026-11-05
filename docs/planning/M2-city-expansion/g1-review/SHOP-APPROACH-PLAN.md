# D4 — Shop prompt approach plan

**Verdict: PROPOSED — keep every prompt host at its baseline coordinate; build
open-front counters whose plaza-facing face sits at the lot edge so a player
standing in the plaza is inside the existing 10-stud activation and 12-stud
validation contract.** No host relocation is requested.

## Contract (frozen)

| Parameter | Value | Source |
|---|---|---|
| Activation distance | 10 studs (client prompt) | `WorldService` constant |
| Server validation | ≤ 12 studs, anchor re-resolved by name | `WorldService` constant |
| Prompt identity | server-created, parented to the anchor | parent §05 |
| Hosts | `City_Prompt_ElectroMart (68, 3, 84)`, `City_Prompt_RumahRapi (-68, 3, 84)`, `City_Prompt_Cosmetics (68, 3, 108)`, `City_Prompt_Utility (68, 3, 132)` | parent `02` §7 |

## Geometry under the parent table

| Item | Value |
|---|---|
| East lot (Z3) | `X +56 … +80`, `Z +72 … +144`, 24 wide × 24 deep per lot |
| West lot (Z4) | `X -80 … -56`, `Z +72 … +96` |
| Plaza-facing lot edge (east) | `X = +56` |
| Plaza-facing lot edge (west) | `X = -56` |
| Host X (east) | `+68` — 12 studs inside the lot from the plaza edge |
| Host X (west) | `-68` — 12 studs inside the lot from the plaza edge |
| Facade depth | 24 studs, open front, no interior |
| Counter depth (proposal) | 4 studs, face at the lot edge |

## Approach distances (pre-production estimates)

Measured from the plaza-facing lot edge, where a player naturally stands:

| Standing position | To east host `(68, 3, 84)` | Verdict |
|---|---:|---|
| Lot edge `X = 56`, `Z = 84` | 12.0 studs | at the validation limit — **not sufficient** |
| Lot edge + 1 stud `X = 57`, `Z = 84` | 11.0 studs | inside 12, outside 10 |
| Counter face `X = 60`, `Z = 84` | 8.0 studs | inside 10 — **target standing position** |
| Mid-lot `X = 62`, `Z = 84` | 6.0 studs | comfortable |

The counter face at `X = 60` is the design target: the player walks up to the
counter, not into the lot. West mirrors at `X = -60`.

These are XZ-plane estimates against an invisible marker at `Y = 3`. Real
validation uses the avatar's `HumanoidRootPart` position and a real collision
shell; a lot-centre approximation is not acceptable evidence.

## Collision clearance and obstructions

| Risk | Mitigation |
|---|---|
| Counter blocks the 6-stud route | counter depth 4 studs from the face, flush with the lot edge |
| Props (crates, bell, CRT) inside the 10-stud ring | keep decorative props `CanCollide = false`, `CanQuery = false` |
| Awning geometry above the prompt | awning at `Y ≥ 3.6`, never inside the 10-stud sphere |
| Two prompts within 4 studs | east row hosts are 24 studs apart in Z; nearest-wins plus 4-stud separation per parent R12 |
| Player pushed out of range by collision | route clearance ≥ 6 studs in front of every counter face |

## Explicit amendment path (not requested here)

If a real walk-up fails, the documented amendment is to move the **east row**
hosts to `X = +58` (and west to `X = -58`) — still inside the lot, 2 studs
closer to the plaza, and 10 studs from the lot edge. That is a director
decision recorded in `DIRECTOR-APPROVAL-REQUEST.md`; the baseline is never
silently modified.
