# M2-A1 — executable blockout handoff

**Ready as a planning handoff, not assigned implementation.** Read parent
`../10-M2-A1-TASK-BREAKDOWN.md` first. Parent constraints outrank this supplement.

## Preconditions

Explicit assignment; director M2-G1 acceptance; BS-14 decision required by parent
sequencing; current branch/worktree and shared-file ownership checked. Do not assume
these approvals from the presence of this document or from a merged BS-14 commit.
Open coordinate decisions are in [OPEN-DESIGN-DECISIONS.md](OPEN-DESIGN-DECISIONS.md).
If unresolved, preserve baseline and report the unmet view criterion, not a false pass.

## Allowed files and phase boundary

New deterministic `tools/gen_city_prefabs.py`; city blockout prefabs in
`assets/world/city/`; parent-required HouseExterior, StreetBlock, TownCenter,
CityBackdrop and CityAnchors; review evidence under `docs/evidence/m2-a1/`.
Minimal kiosk/gate massing needed for a view test can be included in owning blockout
models; adding separate new prefab files requires explicit scope agreement.

Prefer a separate review place/project outside production mappings for A1. If Rojo loads
the blockout, serialize any project-file edit with its owner. Never silently ship city
content in the closed-beta place. Mapping into ServerStorage alone does not assemble
Workspace.City; assembly for review must be explicit, temporary and documented.

No src/, existing assets, frozen generator, Catalog, services, tests or economy edit.
A1 has stub/no-logic prompt hosts only. A2+ owns CityService, actual transitions and
mission routing. B owns functional shops, dressing, cosmetic UI and other new gameplay.

## Ordered work and smallest proof

| Step | Work | Evidence / invariant |
|---|---|---|
| 1 | Read actual prefab and project conventions; encode parent tables | Exact coordinate exceptions retained; no blanket 16-grid assertions |
| 2 | Build house shell and threshold | Frozen room byte-identical, exterior north window preserved, no ceiling, porch seam inspectable |
| 3 | Build road and bands | Road 32 wide, bands 8 each, tops at Y=0, safe outdoor spawn approach |
| 4 | Build plaza/fountain massing and kiosk landmark | Bounds and radii match; clear routes; 3D stoop-to-kiosk/fountain test |
| 5 | Build baseline backdrop, compare proposal only on a separate review copy | Actual window pose sees skyline or criterion explicitly fails |
| 6 | Add required marker subset and reserved gate indication | Enumerated full inventory vs authored subset, exact scoped identities |
| 7 | Assemble isolated review place | Correct single translation per zone; no doubles, scripts or external asset references |
| 8 | Run static and native geometry checks, unchanged regression suite | Actual command outputs and suite counts archived |
| 9 | Capture desktop and parent mobile sizes, counts, settings, walk times | Genuine Studio captures and manifest, no emulator-as-phone claim |
| 10 | Handoff and stop | No services, shops, UI, persistence, economy or detail pass smuggled into A1 |

## Transform and marker contract

Export geometry local to the model's zone origin; place at that origin once. Use an
explicit pivot mechanism and count any invisible pivot Part in budget. House origin is
(0,0,0); street (0,0,40); plaza (0,0,112); backdrop per parent table. Never author world
coordinates then call PivotTo with the same origin again.

Parent inventory: 17 positioned part identities, including HomeDoor; 22 invisible
markers when all six signposts are included. City_LightGroup is a Folder. Keep marker
parts under City_Anchors and zone models outside it; identical zone/root names require
scoped lookup. Suggested signpost positions are proposals until accepted. No duplicate
marker in both a zone prefab and the separate marker export.

## A1 proof checklist

- Frozen Bedroom.rbxmx and existing sources/tests unchanged; room anchor names, sizes,
  transforms and ownership remain intact.
- No scripts, remotes, external assets or active prompt logic inside generated models.
- All geometry anchored; physical barriers collide; markers invisible and non-queryable.
- Exact zone bounds and anchors; window aperture retained; no new walkable elevation.
- Blockout BaseParts ≤450, counted in assembled city including markers and pivot parts.
- Door-to-fountain ≤12 seconds measured on foot after temporary exterior placement;
  door prompt transition itself is not claimed.
- Stoop kiosk/fountain, window, door/plaza camera views checked in 3D. Document any failed
  criterion and reopen the relevant decision; do not weaken it just to pass.
- Parent-required desktop/mobile captures complete; screenshots labelled by mode and pose.
- Existing regression suite unchanged and green, exact counts/logs recorded.
- Native place streaming and lighting settings read; no value inferred from absent JSON.

## Later integration tests — explicitly not A1 claims

A2+ must reject forged/distant/dead prompt requests; measure real avatar root clearance;
confirm ground and overlap at both destinations; coordinate Player stream readiness,
fade, retry and original-position failure; restore camera/input once across repeated
activation, death and respawn; keep rejoin indoors; use existing mission surface without
a second composer. B additionally verifies shop auth, confirmed purchases, replay and
cosmetic stat neutrality under approved persistence contracts.

These obligations remain required but cannot pass in a no-logic blockout. Global
DataStore, release and real-device gates remain separate. Stop if completing A1 would
require changing frozen room geometry or a runtime service.
