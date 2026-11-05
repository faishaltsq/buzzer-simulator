# D4 — Shop prompt approach plan

**Verdict: PROPOSED — keep every prompt host at its baseline coordinate; test
open-front counters with faces 4 studs inside the lot.** No host relocation is
requested. Reachability is **TEST REQUIRED (P5)**, not proven in Studio.

## Canonical shop approach

This is the single source of truth for the proposed approach (absolute X in
studs; west mirrors east). The matrix and board are derived views.

```json
{"lot_edge": 56, "counter_face": 60, "avatar_root": 59, "host": 68, "counter_depth": 4}
```

Lot edge `X = ±56`; counter face `X = ±60`; candidate avatar root `X = ±59`;
baseline host `X = ±68`. The root is 1 stud plaza-side of the face, at the same
Z as its host. This candidate position is not an avatar collision guarantee.

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
| Counter face (proposal) | `X = ±60`, 4 studs inside the lot edge |
| Counter depth (proposal) | 4 studs toward the host: east `X 60…64`, west `X -64…-60` |
| Candidate avatar root | `X = ±59`, same Z as host, 1 stud plaza-side of counter face |

## Approach distances (pre-production estimates)

XZ-only distances at the host's Z; the face and lot edge are reference planes,
not interchangeable avatar standing positions:

| Standing position | To east host `(68, 3, 84)` | Verdict |
|---|---:|---|
| Lot edge `X = 56`, `Z = 84` | 12.0 studs | at the validation limit — **not sufficient** |
| Candidate avatar root `X = 59`, `Z = 84` | 9.0 studs | horizontal estimate only — **TEST REQUIRED** |
| Counter face reference `X = 60`, `Z = 84` | 8.0 studs | reference plane, not avatar root |

The player enters the lot's approach strip before reaching the counter.
West mirrors at avatar `X = -59`, face `X = -60`, host `X = -68`.
`X = ±62` lies inside the proposed counter and is not a standing target.

These are XZ-plane estimates against an invisible marker at `Y = 3`. Real
validation uses the avatar's `HumanoidRootPart` position and a real collision
shell; a lot-centre approximation is not acceptable evidence. For a candidate
horizontal distance of 9, the actual distance is `sqrt(9² + (HRP.Y - 3)²)`;
collision, vertical offset, line of sight and prompt behaviour all require a
real Studio walk-up before P5 can close.

## Collision clearance and obstructions

| Risk | Mitigation |
|---|---|
| Counter blocks the 6-stud route | face at ±60, body extends toward host; keep a ≥ 6-stud clear approach and test the actual avatar envelope |
| Props (crates, bell, CRT) inside the 10-stud ring | keep decorative props `CanCollide = false`, `CanQuery = false` |
| Awning geometry above the prompt | test head/camera clearance and prompt line of sight; height alone does not prove clearance |
| Two prompts within 4 studs | east row hosts are 24 studs apart in Z; nearest-wins plus 4-stud separation per parent R12 |
| Player pushed out of range by collision | route clearance ≥ 6 studs in front of every counter face |

## Explicit amendment path (not requested here)

If a real walk-up fails, record the measured HRP position and collision/visibility
failure before proposing a remedy. Any host move requires a separate explicit
director coordinate amendment. No fallback coordinate or automatic relocation
is approved by this package; the baseline is never silently modified.
