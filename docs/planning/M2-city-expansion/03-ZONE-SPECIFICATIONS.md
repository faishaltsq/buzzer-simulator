# 03 — Functional Zone Specifications

> **Covers**: §C Functional Zones.
> **Status**: Planning. Part counts are **test budgets**, not platform limits.

Each zone uses the same template: purpose, gameplay role, interactions, visuals,
required assets, nice-to-haves, and budget. All zones sit on the coordinate
contract in `02-WORLD-STRUCTURE.md`.

---

## Zone index

| ID | Zone | Type | Budget (BaseParts) | Phase |
|---|---|---|---|---|
| Z0 | Home & Threshold | private base + facade | 90 (shell) | M2-A |
| Z1 | Residential Street | traversal / orientation | 80 | M2-A |
| Z2 | Town Center | hub / landmark | 220 | M2-A shell, M2-B dressing |
| Z3 | ElectroMart | gameplay shop | 120 | M2-B |
| Z4 | Rumah Rapi | cosmetic shop | 100 | M2-B |
| Z5 | Event Plaza | event venue | 160 | M2-B |
| Z6 | Mission & Daily Boards | mission delivery | 40 | M2-A |
| Z7 | Future District Gate | teaser | 30 | M2-A |
| — | North skyline backdrop | non-walkable vista | 8 | M2-A |

**Total M2-B ceiling: 958 BaseParts** (city only) = 848 zone parts + 60 shared
props kit + 50 utility lot, against a hard test cap of 1,200. The bedroom's
existing ≤ 350 budget is untouched.

---

## Z0 — Home & Threshold

| Field | Specification |
|---|---|
| **Purpose** | Make the frozen bedroom read as a real house from outside, and define the threshold between private and public. |
| **Gameplay role** | The only door. Entry/exit prompt. No economy. |
| **Extent** | `x -22…+22`, `z -22…+22`; shell offset 0.6 studs outside the 24×24 room. |
| **Example interactions** | Interior prompt `Keluar Rumah` on `City_DoorPromptInterior`; exterior prompt `Masuk Rumah` on `City_HomeDoor`. Locked-state copy when `cityUnlocked == false`. |
| **Visuals** | Cream plaster cladding, walnut door surround, sage awning, one hanging bulb, house number plate, potted plant, low stoop step, scooter prop. Warm amber bulb tint. |
| **Required prefabs** | `HouseExterior.rbxmx` (shell + facade + stoop), `City_DoorPrompts` (anchor parts only). |
| **Nice-to-have** | Mailbox that shows the day's board headline; shoe rack; drying laundry line (3 parts). |
| **Budget** | 90 BaseParts shell + 6 anchor parts. |
| **Camera risk** | Roof/parapet may intersect orbit camera. **No interior ceiling**; parapet at `y = 11.9`; optional roof plane only after a camera test. |

**Acceptance:** from the stoop, the player sees street + board kiosk + fountain;
from the desk, the window shows skyline only.

---

## Z1 — Residential Street ("Gang")

| Field | Specification |
|---|---|
| **Purpose** | Orientation corridor and pacing beat. Teaches the city scale on first exit. |
| **Gameplay role** | Traversal only. Signage, no purchases. 3.6-second walk to the boards. |
| **Extent** | `x -20…+20`, `z +18…+64`; 24-stud road + 8-stud sidewalks. |
| **Example interactions** | Two signposts (`City_Signpost_01/02`), a lamp post light, one non-interactive neighbor porch. |
| **Visuals** | Wet asphalt (SmoothPlastic, low specular), painted center line, sage awnings on both sides, hanging cables between poles, faded fictional shop sign, one parked delivery bike. |
| **Required prefabs** | `StreetBlock.rbxmx`. |
| **Nice-to-have** | Puddle decals (2 Parts), cat on a wall (non-colliding), distant radio hum (rights-reviewed, optional). |
| **Budget** | 80 BaseParts. |
| **Rule** | No shop entrances on this street in MVP; it must stay a corridor so the town center lands as a reveal. |

---

## Z2 — Town Center ("Alun-Alun Kecil")

| Field | Specification |
|---|---|
| **Purpose** | The city's heart and fast-travel landmark. Where the player understands "this is the hub". |
| **Gameplay role** | Mission + daily boards, bus stop (inert), landmark stamps, event announcements. |
| **Extent** | `x -56…+56`, `z +64…+160`; plaza disc radius 38 at `(0, 0, 112)`. |
| **Example interactions** | Board kiosk prompt, 3 signposts, bench sit (cosmetic animation, optional), fountain inspect (flavor line), bus stop read. |
| **Visuals** | Circular paved plaza (two-tone stone), low fountain with 8-stud basin, 4 benches, 3 lamp posts, flag banner over the board kiosk, warm evening tone, visible shop awnings on both sides as sightlines. |
| **Required prefabs** | `TownCenter.rbxmx`, `CityProps.rbxmx` (benches, lamps, bins). |
| **Nice-to-have** | Market stalls that appear only during events (Z5 prefab reused); chalk board with handwritten (authored) copy; pigeons (2 Parts). |
| **Budget** | 220 BaseParts (shell 140 + props 80). |
| **Density rule** | Max 1 prop per 4×4 studs in walkable area; keep a 6-stud clear ring around the fountain and board kiosk. |

---

## Z3 — ElectroMart ("Toko Listrik Pak Bud")

| Field | Specification |
|---|---|
| **Purpose** | A physical storefront for the **existing** upgrade catalog. |
| **Gameplay role** | Gameplay shop. Opens the existing BuzzerOS `Upgrades` tab, filtered and pre-scrolled. **No new prices, no new items.** |
| **Extent** | `x +56…+84`, `z +72…+96`; open-front kiosk, 24-stud facade, 12-stud counter depth. |
| **Example interactions** | `City_Prompt_ElectroMart` → server confirms anchor + distance → client opens `Upgrades`. Locked until `neon_market` completed (copy: "Pak Bud belum kenal kamu"). |
| **Visuals** | Amber sign, sage awning, CRT stack on shelves (reuse `OldCRT` silhouette geometry, not the prefab instance), phone boxes, cable coils, counter bell, fluorescent tube (one PointLight, no shadows). |
| **Required prefabs** | `ShopRowElectronics.rbxmx` (shell + counter + shelf boxes only; **no product models from `assets/world/`**). |
| **Nice-to-have** | A working CRT on the counter showing BuzzerOS logo (SurfaceGui, client-only); price tags as authored text. |
| **Budget** | 120 BaseParts. |
| **Economy boundary** | This shop is a **doorway to existing UI**. It never holds its own price table. |

> The east row has two further 24-stud lots at `z 96–120` (Cosmetics, M2-C) and
> `z 120–144` (Utility, M2-B). They share the same facade depth and kit; see
> `04-EVENTS-AND-SHOPS.md` for their shop specs.

---

## Z4 — Rumah Rapi (Furniture & Decor)

| Field | Specification |
|---|---|
| **Purpose** | Cosmetic expression for the bedroom. The first place players can spend on looks instead of power. |
| **Gameplay role** | Cosmetic shop. Sells room props that are **visual only**: no Cuan, no yield, no reveal, no worker effect. |
| **Extent** | `x -84…-56`, `z +72…+96`; open-front kiosk. |
| **Example interactions** | `City_Prompt_RumahRapi` → opens a cosmetic catalog panel (new UI, M2-B) → purchase confirms a decor item placed in the room by a future `DecorService`. Locked until `fictional_gadget` completed. |
| **Visuals** | Walnut shelving, sage fabric bolts, a sample chair, a rug rack, a plant corner, warm desk lamp. Cozy, not luxury. |
| **Required prefabs** | `ShopFurniture.rbxmx`; cosmetic item prefabs are **separate, small, and director-approved** (see `07`, asset priority). |
| **Nice-to-have** | A mirror that shows the player's avatar; a "before/after" photo board of the room. |
| **Budget** | 100 BaseParts. |
| **Economy boundary** | Cosmetics only. If an item would change comfort/stats, it is rejected by design. |

---

## Z5 — Event Plaza

| Field | Specification |
|---|---|
| **Purpose** | A stage for limited-time authored events and seasonal dressing. |
| **Gameplay role** | Event venue. Hosts pop-ups, campaign weeks, festival overlays. Reuses existing mission rewards or grants cosmetic stamps. |
| **Extent** | `x -140…-84`, `z +104…+164`; 56×60 open plaza, 16-stud connector to town center. |
| **Example interactions** | Event board prompt (read-only until an event is active), stage inspect, 2 signposts, NPC crowd (client-local). |
| **Visuals** | Low stage (2 studs), string lights, banner rig, 6 fold-out stalls stored as an alternate model, empty lot when idle so it doesn't look broken. |
| **Required prefabs** | `EventPlaza.rbxmx` (permanent shell), `EventPlaza_PopUp.rbxmx` (event-only dressing, streamed in on demand). |
| **Nice-to-have** | Confetti burst on event claim (client particles, capped), stage microphone prop, crowd silhouettes (non-colliding). |
| **Budget** | 160 BaseParts permanent + 60 event dressing. |
| **Rule** | Never leave a half-built event in the world. If no event is active, the plaza shows the empty lot plus a "Jadwal minggu ini" board. |

---

## Z6 — Mission & Daily Boards

| Field | Specification |
|---|---|
| **Purpose** | The physical delivery point for campaign briefs. The reason to leave the room every session. |
| **Gameplay role** | Mission delivery. Adds a brief to the existing mission queue; **publishing still happens at the terminal**. |
| **Extent** | `x -12…+12`, `z +66…+76`, inside the town center south edge, facing the arriving player. |
| **Example interactions** | `City_Prompt_Boards` → opens the mission list (existing `Missions` tab) or a compact board panel; daily brief shows one rotating authored entry with a visible reset time. |
| **Visuals** | Two cork boards under a sage awning, pinned paper cards, a hanging lamp, chalk headline, a small queue rope. No floating 3D text. |
| **Required prefabs** | `CityBoards.rbxmx` (30 parts) + anchors. |
| **Nice-to-have** | A stamped "SELESAI" card for the last completed mission; a clock showing the next daily reset. |
| **Budget** | 40 BaseParts. |
| **Rule** | The board must not become a second composer. It only selects/accepts. |

---

## Z7 — Future District Gate

| Field | Specification |
|---|---|
| **Purpose** | Sell the horizon. Tell the player the world continues without shipping it. |
| **Gameplay role** | Locked teaser. One prompt with honest copy. No purchase, no timer, no fake progress bar. |
| **Extent** | `x -8…+8`, `z +160…+176`; 16-stud gate between two low walls, a closed roller shutter, a sign. |
| **Example interactions** | `City_Prompt_FutureGate` → "Distrik berikutnya belum dibuka." Optional: shows the next district name and a vague condition only if the director approves the copy. |
| **Visuals** | Concrete gate, amber strip light, faded district map poster, "SEGERA" stencil, steam vent. |
| **Required prefabs** | `CityGate.rbxmx`. |
| **Nice-to-have** | Distant tower visible above the gate; a guard stool with no guard (humor). |
| **Budget** | 30 BaseParts. |
| **Rule** | No locked button that implies a price. No countdown. No "unlock for X" copy. |

---

## North skyline backdrop (non-zone)

| Field | Specification |
|---|---|
| **Purpose** | Fix V-03: the bedroom window currently looks at raw sky. |
| **Gameplay role** | None. Aspirational vista; hides the edge of the world. |
| **Extent** | `x +10…+160`, `z -200…-120`, height ≤ 120; **never walkable**. |
| **Visuals** | 3–4 flat silhouette slabs (navy/sage), one taller Agency Tower shape, haze plane, two blinking antenna lights. |
| **Required prefabs** | `CityBackdrop.rbxmx` (≤ 8 parts, `Persistent` streaming). |
| **Budget** | 8 BaseParts. |
| **Rule** | Must never be reachable, collidable, or interactable. It is a painting. |

---

## Zone density & readability rules (all zones)

1. **One silhouette per building.** A player should identify a shop from 60
   studs by shape + sign color, not by reading.
2. **Sign color mapping:** ElectroMart = amber, Rumah Rapi = walnut/sage,
   Cosmetics = coral accent, Utility = navy, Boards = cream paper.
3. **No closed interiors.** Every shop is an open-front counter. This avoids
   camera clipping, interior lighting cost, and door-streaming bugs.
4. **No floating 3D text.** Signs are `SurfaceGui` or Part-composed lettering.
5. **Collision:** structural parts collide; props do not
   (`CanCollide = false`, `CanQuery = false`).
6. **Night readability:** every zone needs one warm light source; total city
   `PointLight` count ≤ 8, only 2 with `Shadows = true`.
7. **Mobile first:** no zone requires the camera to enter geometry; no zone
   requires more than one screen of reading.
