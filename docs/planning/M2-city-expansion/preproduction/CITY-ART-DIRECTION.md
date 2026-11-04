# City art direction — Gang Melati at dusk

**Proposal for visual review, not an applied lighting change.** Parent references:
`../03-ZONE-SPECIFICATIONS.md`, `../05-TECHNICAL-PRODUCTION-AND-PERFORMANCE.md` and
`docs/design/02-COLOR-AND-MATERIALS.md`.

## Visual thesis

A modest Indonesian neighbourhood outside a rented home studio. Warm plaster, timber,
sage awnings and restrained amber signage connect the city to the bedroom. The city
must read as inhabited without relying on crowded props, uploaded textures or NPC rigs.

## Palette and materials

Use existing world tokens, not newly mixed geometry colours: plaster walls, cream trim,
wood/wood_light counters, wood_dark recesses, sage cloth, sage_dark plants, navy signs,
ink cables, metal hardware, clay pots. Amber is an accent, not a wall field. Diagram
annotation colours are not additions to the game's palette. Coral styling for the future
cosmetics shop is deferred to its own copy/palette approval.

SmoothPlastic is the default; Wood for joinery, Metal for hardware, Fabric for soft
awnings. The parent city plan permits Concrete; a new city generator may add the correct
native token locally without changing the existing world generator. Glass and Neon are
restricted to approved pane/indicator use; prefer opaque simulated water in A1. No
external meshes, texture IDs, image IDs, sounds or executable descendants in prefabs.

## Architectural grammar

Each shop combines a mass, a horizontal sign band, a recessed open counter, an identifiable
awning, a plinth and a simple upper-window rhythm. These are composition rules, not a
six-BasePart total. Shops remain open-front kiosks; no closed interiors, stairs or
walkable roofs. Heights stay within the parent's 12–16-stud envelope.

| Building | Distinct read | Phase |
|---|---|---|
| House | Low parapet, small stoop, sage exterior door | A |
| ElectroMart | Narrow projecting amber sign, flat awning | B |
| Rumah Rapi | Soft pitched cloth awning, rug display | B, conditional cosmetic approval |
| Utility | Compact navy sign and counter | B |
| Cosmetics | Open-frame canopy; reserved lot only in A/B | C |
| Boards | Freestanding paired panels, daylight around supports | A |
| Gate | Compact closed shutter and lintel; no access promise | A |

Do not make adjacent shop hats and heights identical. Preserve negative space around
paths, not repeated boxes with different text. Detail is added only after silhouette
review from the plaza and the approach lane.

## Signs, props and light

Use one primary SurfaceGui sign per shop, world-occluded (`AlwaysOnTop = false`), with
plain authored copy; no floating BillboardGui or price-bearing teaser. Extra signs need
an explicit count and screenshot readability check, not a fabricated universal cap.
A SurfaceGui has one host face; separate signposts cannot share one Gui on different
world parts. Part-composed lettering also costs BaseParts and must be counted.

Choose sparse storytelling: a plant at the stoop, a delivery bike, a repaired CRT shell
at the electronics counter, a rug at the furniture counter, and the inert bus-stop sign.
These are optional dressing, not new interactions. Avoid props that obstruct the return
prompt or visually imply earning.

Dusk is an aesthetic target, not an exact sun azimuth. ClockTime, latitude, renderer and
place settings must be inspected together in Studio. Do not change global lighting to
style the city without checking the bedroom. Keep the parent's city cap of eight
PointLights, at most two shadow-enabled; no guaranteed shadow quality or FPS claim.

## Visual acceptance

Recognisable shop silhouettes; visible lane destination; no floating door or shell seams;
window opening not covered by exterior cladding; no roof that traps the normal camera;
readable signs in portrait and landscape; coherent bedroom palette; no fake unlock price.
All are exercised in Studio during the owning implementation phase. The masterplan is
only a planning drawing, never evidence that these conditions already pass.
