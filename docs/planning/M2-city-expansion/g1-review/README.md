# M2-G1 — City Design Acceptance (Agent 2 review package)

**Status: READY FOR DIRECTOR M2-G1 REVIEW.**
This package completes planning work only. It does not approve M2-G1, does not
assign M2-A1, and does not implement any city geometry, service, prompt or
economy change. Director acceptance is a separate act.

| Field | Value |
|---|---|
| Repository | https://github.com/faishaltsq/buzzer-simulator |
| Baseline | `09eb88d626d73057543fe419a2c0925063d1df09` (origin/master, verified) |
| Branch | `agent/M2-G1-city-design-acceptance` (documentation-only, cut from baseline) |
| Agent | Agent 2 — environment design / technical art / level-design QA |
| Planning basis | `../preproduction/` bundle + parent blueprint `../` |

## Scope boundary (Phase 7, verbatim)

No modification of `src/`, `assets/`, `tests/`, production tools,
`default.project.json`, the Bedroom prefab, catalog/economy services, DataStore
schema, client UI or network remotes. No city gameplay implementation. No M2-A1
geometry. No published Roblox place. No DataStore operations. No automatic
merge. No changes to Agent 1's BS-15 branch.

## Package contents

| File | Answers |
|---|---|
| `COORDINATE-DECISION-MATRIX.md` | D1–D8 director decisions with recommendation, baseline consequence and required approval |
| `SKYLINE-COMPARISON.md` | D1 window projection, coverage arithmetic, baseline vs proposed backdrop |
| `KIOSK-VISIBILITY-COMPARISON.md` | D2 solid vs open-frame kiosk inside frozen Z6 |
| `HOUSE-EXTERIOR-SPEC.md` | D3 facade, threshold, porch/return options, frozen constraints |
| `SHOP-APPROACH-PLAN.md` | D4 prompt reachability at the unchanged 10/12-stud contract |
| `CAMERA-AND-STREAMING-CHECKLIST.md` | D5 + D6 view compositions, streaming and transition verification |
| `PART-BUDGET-LEDGER.md` | D7 allocation ledger and reduction strategy |
| `M2-A1-READINESS.md` | Phase 5 blockout order and objective acceptance tests |
| `DIRECTOR-APPROVAL-REQUEST.md` | The explicit decisions requested, with what stays frozen until each lands |
| `G1-DESIGN-REVIEW-preview.png` / `.svg` | Visual review boards (8 views) |
| `G1-DESIGN-REVIEW.excalidraw` | Editable source of the boards |
| `gen_g1_boards.py` | Deterministic generator for the three exports |
| `verify_g1_review.py` | Focused checks on the new tables and the board exports |

Cross-referenced M2-A0 documents are **not duplicated** here; this package links
to them and only restates the values a decision depends on.

## Verdict

**READY FOR DIRECTOR M2-G1 REVIEW** — the coordinate contract is build-ready,
every open decision has a recommendation with an explicit approval requirement,
and nothing is marked approved by the agent. Four items remain
**TEST REQUIRED** because they cannot be proven in 2D planning (see
`DIRECTOR-APPROVAL-REQUEST.md` § Pending).

## Evidence discipline

- Every number in this package is either quoted from a parent/M2-A0 table or
  derived arithmetically from the verified `Bedroom.rbxmx` anchors
  (`CameraFocus`, `WindowGlass`, `Door`).
- No number here is a measured Roblox Studio count, frame time, or live camera
  capture. `PART-BUDGET-LEDGER.md` keeps allocations distinct from emitted counts.
- The boards are **planning drawings**, not Roblox Studio screenshots, and are
  labelled as such on the sheet itself.
- `python verify_g1_review.py` re-derives the arithmetic and asserts the layout
  invariants of both this package and the M2-A0 bundle.
