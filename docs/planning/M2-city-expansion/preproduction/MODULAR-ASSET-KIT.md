# Modular asset kit — member-level reuse

**Specification, not an asset inventory.** Build helpers in the new city generator;
do not duplicate or modify the frozen world generator merely to reuse its conventions.
Reuse palette values and serializer patterns where they fit. No generic ShopTemplate,
abstract service or configurable kit runtime is required.

## Coordinate, naming and ownership conventions

Members use local bottom-centre pivots, +X along their width and +Z toward the facade.
Zone exports are local to the zone origin, assembled at that origin once. Rotation and
normal direction must be verified on a sample before multiplying the kit across a row.
Use stable semantic names (e.g. City_Wall_Plain, City_Awning_Flat), with one family owner.
Anchors are not decorative kit pieces and keep their exact City_* identities.

| Family | Nominal dimensions / composition | Reuse / policy |
|---|---|---|
| Wall | 8-stud-wide field, 0.5 thickness; height chosen per building | Plaster; structural. Cut windows as actual openings in shell |
| Facade | Horizontal band plus two recessed returns | Navy band; do not close shop approach |
| Roof trim | 8-stud length; eave profile can echo bedroom cornice | House parapet ≤11.9; no interior roof lid |
| Door | Exterior leaf echoes 3.7 × 7.3 × 0.18 frozen prop | New instance only; closed opaque HomeDoor; do not edit existing Door |
| Window | Frame and pane with aperture retained | No exterior wall across bedroom opening |
| Sidewalk | 8 × 8 or merged band, top Y=0 | No new stair or kerb elevation |
| Road | Merged 32 × 48 lane slab where sufficient | Count seams only when visible and needed |
| Lamp | Base, pole, arm and head | PointLight count separate from BaseParts; city-wide cap applies |
| Bench | Timber seat/back with simple supports | Non-colliding decorative prop under parent policy; no implied sit feature |
| Planter | Pot and compact leaf mass | Sparse; preserve path clearance |
| Sign | Board Part with one world-occluded SurfaceGui on its own face | No shared Gui across independent parts |
| Stall | Simple counter, posts, cloth | Event-only later phase; not permanent A1 geometry |
| Counter | Timber top/front/supports | Prompt distance measured from real approach, not lot bounds |
| Fountain | Basin segments and central mass; simple opaque water in blockout | Roblox Cylinder is not a hollow ring; no fake geometry count |
| Banner | Pole/mount separated from cloth | Optional event cloth not cloned when no event runs |
| Skyline | A few opaque slabs and tower silhouette | Eight-part backdrop allocation includes all authored backdrop parts |
| Support | Cable, bin, signpost and optional queue rope | Author only when a zone needs it; no scaffolding variants |

## Counting and collision

The table gives dimensions and ownership, **not fabricated per-module counts**. The
implementation generator prints actual emitted BaseParts per family/prefab. A wall field
may merge into one Part; a real ring may need several. Count what ships, not the recipe name.
Each placed copy consumes the budget once; the shared-kit pool is not added again after
its placed parts were counted in a zone. Invisible pivot parts count too.

Structural shells, floors and physical door collide and query. Decorative lamps, awnings,
signs and furniture follow the parent prop policy. No blanket guarantee about camera
occlusion follows from these flags: inspect actual camera behaviour. Every authored
city part is anchored. Markers are transparent, non-collide/non-touch/non-query.

The assembled zone owns all its members; no cross-prefab references. Server-created
prompts attach to scoped City_Anchors hosts in the later service phase. A1 exports no
executables or active interaction logic. Setting streaming modes does not make anchor
Folders Persistent; measure replication in the built place.

## Build order

House shell/threshold → flush road/bands → plaza and fountain massing → kiosk landmark →
backdrop/window test → reserved gate extent → marker integrity. Detail and shop families
follow only after blockout acceptance. Stop adding kit families when the owning phase
has no use for them. Production and test mappings are serialized with their file owner.
