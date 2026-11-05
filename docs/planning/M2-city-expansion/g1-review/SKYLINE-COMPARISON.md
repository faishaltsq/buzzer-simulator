# D1 — Skyline / backdrop alignment comparison

**Verdict: PROPOSED (candidate), pending director acceptance and one isolated
Studio camera view.** The baseline remains canonical until then. This page
carries the arithmetic; the drawing lives in `G1-DESIGN-REVIEW-preview.svg`
panel 2 and its editable source `G1-DESIGN-REVIEW.excalidraw`.

## Verified inputs (read-only, from `assets/world/Bedroom.rbxmx`)

| Anchor | Value | Note |
|---|---|---|
| `CameraFocus` | `(7.0, 5.5, 3.0)` | desk camera part; reference eye point, not a live camera pose |
| `WindowGlass` | center `(3.0, 5.5, -12.08)`, size `5.8 × 4.8 × 0.08` | north window aperture |
| Aperture X | `0.1 … 5.9` | center ± half width |
| Aperture Y | `3.1 … 7.9` | center ± half height |
| `Door` | `(-6, 3.65, 11.6)`, `3.7 × 7.3 × 0.18`, collidable | frozen, never edited |

## Projection arithmetic

Straight rays from `CameraFocus` through the aperture corners onto the candidate
backdrop mid-plane `Z = -152` (midpoint of the parent extent `-192…-112`):

```
dz_window = -12.08 - 3.0 = -15.08
dz_plane  = -152.0 - 3.0 = -155.0
ratio     = dz_plane / dz_window ≈ 10.279
X(x)      = 7.0 + (x - 7.0) * ratio
```

| Aperture edge | Projected X at Z = -152 | M2-A0 reference |
|---|---:|---:|
| left `X = 0.1` | ≈ **-63.92** | -65.33 |
| right `X = 5.9` | ≈ **-4.31** | -3.33 |

Slice width ≈ **59.6** studs. Vertical span `Y ≈ -19.17 … 30.17` at that plane.
The ≈1.3-stud difference against the M2-A0 figures comes from the parent's
rounded reference camera; both agree the slice is entirely **negative X**, and
the parent reference midpoint `-34.33` (recomputed `-34.11`) sits in the
proposed span and outside the baseline span.

## Coverage at the backdrop plane

| Candidate | X extent | Covers the slice? |
|---|---|---|
| Baseline `FROZEN` | `+16 … +160` | **0 %** — the slice ends at X ≈ -2.87, left of +16 |
| Proposed `PROPOSED` | `-120 … +120` | **100 %** — contains `-64.93 … -2.87` with margin both sides |

A tower reference at `X = -34.33` (slice midpoint) sits inside the proposed span
and outside the baseline span.

## Compatibility with the background contract

| Constraint | Baseline | Proposed |
|---|---|---|
| Z extent | `-192…-112` | unchanged |
| Height ≤ 120 | yes | yes |
| Non-walkable, non-collidable, no prompt | yes | yes |
| ≥ 120 studs from playable space | yes (Z ≤ -112 vs city north edge Z = -24) | yes |
| ≤ 8 parts, `Persistent` | yes | yes |
| Intersects walkable envelope (X -136…+80, Z -24…176) | no (Z disjoint) | no (Z disjoint) |
| Intersects the exterior house shell (24×24 around origin) | no | no |

**Exterior-house intersection: none.** The house occupies `X/Y/Z` around the
frozen room at `Z ≥ -24`; the backdrop plane starts at `Z = -112`. The only
shared surface is the window aperture, which the proposal keeps open.

## What is *not* proven

- The live camera pose, FOV and boom length. `CameraFocus` is a part, not the
  runtime camera; a yaw change does not rotate the camera (parent D6).
- Actual tower heights and haze placement.
- That angular 2D overlap equals 3D visibility for the whole aperture volume.

## Recommendation

Build the **centred candidate `X = -120…+120`** on a separate review copy during
M2-A1 step 5, capture the desk view, and freeze the extent only if the capture
shows the skyline inside the aperture. If the capture fails, retain the baseline
extent and reopen D1 — do not weaken the criterion.
