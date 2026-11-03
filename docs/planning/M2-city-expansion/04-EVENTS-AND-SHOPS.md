# 04 — Event & Shop System Concepts

> **Covers**: §F Event System Concepts, §G Shop System Concepts.
> **Status**: Planning. **No numeric price, reward, or timer value is authored
> here.** Every number below is a *class* or a *constraint*, not a constant.

---

## Part 1 — Event systems

### Design constraints (solo dev, one player per server)

1. **No MMO.** No global live counters, no shared server state, no matchmaking.
   "Community" is authored flavor, not simulated population.
2. **No fake numbers.** If a board says "1,204 buzzers joined", that is a lie.
   Use authored fictional names and local, verifiable state instead.
3. **Reuse the mission path.** An event that needs a new economy path is
   rejected. Events select, tag, or re-dress existing content.
4. **Server time, not client time.** Reset windows come from the server clock;
   the client only displays.
5. **Offline-safe.** Missing an event must never delete progress or currency.
6. **One active pop-up at a time.** Overlapping events confuse a 10-second walk.

### Event lifecycle (shared)

```text
Scheduled ──► Visible on board ──► Active ──► Claimed/Expired ──► Archived
   │               │                  │             │
   │               │                  │             └─ reward already granted once
   │               │                  └─ server window open; board shows countdown
   │               └─ name + start time shown, no fake join count
   └─ authored schedule shipped with the build (no live ops backend)
```

Because there is no backend, the schedule is **authored data** (a table of
events with day-of-week/time windows) shipped with the city content. The server
computes "what is active now" from `os.time()`; the client renders it.

### F1 — Daily Brief Board

| Field | Definition |
|---|---|
| Cadence | One brief per real day, resets at a fixed server-local hour |
| Duration | 24 h, claimable once |
| Player action | Walk to Z6, read the board, accept the brief, publish at home, claim |
| Reward | **Reuses one existing mission reward verbatim** (no new constant) |
| Systems needed | Existing mission queue + a daily selector keyed by `os.time()` day index |
| Complexity | Low |
| Failure mode | Player accepts at 23:59 and the day rolls over. Mitigation: the accepted run is frozen with its own ID; expiry does not cancel an accepted run. |
| Why it works | Gives a 20-second reason to leave the room every session, and rotates authored content without new content authoring. |

### F2 — Plaza Pop-Up

| Field | Definition |
|---|---|
| Cadence | 2–3 authored windows per week (e.g., evening blocks) |
| Duration | 20–30 minutes of real time |
| Player action | Walk to Z5; one authored challenge card; publish/claim within the window |
| Reward | Cosmetic stamp + reuse of one existing mission reward class |
| Systems needed | Event window check, plaza dressing swap, one board prompt |
| Complexity | Medium (visual swap + scheduling) |
| Failure mode | Empty plaza looks broken. Mitigation: when idle, show the empty lot + schedule board, never a half-built stage. |
| Why it works | Creates appointment play without a live-ops team; the dressing swap is the cheapest "the world changed" signal available. |

### F3 — Themed Campaign Week

| Field | Definition |
|---|---|
| Cadence | One authored theme per week |
| Duration | 7 days, always-on |
| Player action | Normal play; the theme **weights which existing contexts/missions appear** and re-dresses one plaza banner |
| Reward | No bonus economy; the reward is content variety + one cosmetic banner/stamp |
| Systems needed | Authored rotation table read by the existing context selector (a **read-only** weight, not a new payout path) |
| Complexity | Low–Medium |
| Failure mode | A weight change silently breaks the "strong fit" learning loop. Mitigation: theme only *orders* contexts, never changes scoring or payouts. |
| Why it works | Makes the same four missions feel like a season. |

### F4 — Landmark Stamp Tour

| Field | Definition |
|---|---|
| Cadence | Permanent, once per landmark |
| Duration | Permanent |
| Player action | Visit 6 signposts across all zones; each grants a cosmetic stamp |
| Reward | Cosmetic stamp; completing all 6 opens the Rooftop Venue hook (`09`) |
| Systems needed | 6 anchors + a cosmetic-only stamp table (new, director-approved, no economy) |
| Complexity | Low |
| Failure mode | Players ignore it because it pays nothing. Mitigation: it is a *tour*, not a grind — the stamps are the reward, and the UI shows a small map card, not a progress bar with a payout. |
| Why it works | Teaches the map and gives completionists a reason to visit the far corners. |

### F5 — Seasonal Festival Overlay

| Field | Definition |
|---|---|
| Cadence | 2–4 authored windows per year (director-controlled) |
| Duration | 1–2 weeks |
| Player action | Same as F2, with festival dressing across Z5 and Z2 |
| Reward | Cosmetic-only (banner, stamp, room prop) |
| Systems needed | Reuses F2 + a dressing variant per festival |
| Complexity | Medium (art authoring dominates) |
| Failure mode | Seasonal art costs more than it returns. Mitigation: only fund a festival if the base city is already live and measured. |
| Why it works | The highest-visibility "the game is alive" signal for the lowest systems cost. |

### Event summary

| ID | Name | Cadence | Systems cost | Economy impact |
|---|---|---|---|---|
| F1 | Daily Brief Board | daily | Low | reuses existing reward |
| F2 | Plaza Pop-Up | 2–3×/week | Medium | reuses existing reward + cosmetic |
| F3 | Themed Campaign Week | weekly | Low–Medium | none (ordering only) |
| F4 | Landmark Stamp Tour | permanent | Low | none (cosmetic) |
| F5 | Seasonal Festival | seasonal | Medium | none (cosmetic) |

**MVP event scope:** F1 + F4 only. F2/F3/F5 are M2-C or later.

---

## Part 2 — Shop systems

### Economy boundary (non-negotiable)

| Allowed | Forbidden |
|---|---|
| Surface an existing `Catalog` entry | A new price constant |
| Sell a cosmetic with zero gameplay effect | A cosmetic that changes yield/reveal/worker rate |
| Reuse an existing mission reward | A new currency, token, or event point |
| Free utility (map, reminders) | A paid convenience that skips the walk |
| Director-approved cosmetic table | Randomized loot boxes / gacha |
| Authored weekly rotation | Fake scarcity ("only 3 left!") |

**Purchases are always server-confirmed** through the existing economy path.
A city shop is a **UI doorway**, never a second transaction engine.

### S1 — ElectroMart (electronics, gameplay)

| Field | Definition |
|---|---|
| Role in economy | The physical face of the existing device/desk/hire ladder |
| Visual identity | Amber sign, sage awning, stacked CRT shells, cable coils, one fluorescent tube |
| Likely inventory | Whatever the existing `Catalog` still has unowned: fast phone, PC Rumah, desk 1/2, hire 1/2 |
| Purchase type | **Gameplay** (existing prices, existing effects) |
| Flow | Prompt → server validates anchor + distance → client opens `Upgrades` tab → existing purchase path |
| Locked state | Before `neon_market`: shop is closed, copy explains the owner doesn't know you yet |
| Must not | Hold its own price table, offer a discount, or add an item not in `Catalog` |

### S2 — Rumah Rapi (furniture, cosmetic)

| Field | Definition |
|---|---|
| Role in economy | First cosmetic sink for players with a completed studio |
| Visual identity | Walnut shelving, sage fabric, rug rack, plant corner, warm lamp |
| Likely inventory | Room-only decor: rug variant, poster variant, plant, lamp, shelf clutter, wall clock (all authored Part kits) |
| Purchase type | **Cosmetic** (no stats, no Cuan, no worker effect) |
| Flow | Prompt → cosmetic catalog panel → server-confirmed cosmetic ownership → decor placement in the room |
| Locked state | Before `fictional_gadget`: closed |
| Must not | Change room part budget past 350, block the terminal/phone, or touch frozen anchors |

### S3 — Gaya Depan (cosmetics, cosmetic)

| Field | Definition |
|---|---|
| Role in economy | Avatar expression; long-tail cosmetic sink |
| Visual identity | Coral accent, mirror, small changing screen, hanging outfit silhouettes (Part-composed) |
| Likely inventory | Procedural Part-based accessories only (cap, glasses, jacket color kit). **No uploaded UGC, no external mesh, no real-brand clothing.** |
| Purchase type | **Cosmetic** |
| Flow | Prompt → try-on preview (client-only) → purchase → avatar accessory applied locally + saved cosmetic ID |
| Locked state | Tier 2 (already true at entry) |
| Must not | Use Roblox Marketplace asset IDs or imply real-world brands |

### S4 — Warung Serba Ada (utility, free)

| Field | Definition |
|---|---|
| Role in economy | Convenience and orientation; zero economy impact |
| Visual identity | Navy sign, small counter, hanging snacks, radio, handwritten menu board |
| Likely inventory | Free: city map card, event reminder toggle, "return home" shortcut, board schedule |
| Purchase type | **Utility / free** |
| Flow | Prompt → utility panel; nothing is charged |
| Locked state | None (available at city entry) |
| Must not | Sell a teleport that skips the walk (it would erase the pacing), or charge for the map |

### S5 — Mission & Daily Boards (not a shop)

Listed for completeness: the boards deliver **content**, not goods. They open
the existing mission surface and never transact.

### Shop summary

| ID | Shop | Type | Economy effect | New UI | Phase |
|---|---|---|---|---|---|
| S1 | ElectroMart | gameplay | none (surfaces existing) | no (reuses Upgrades) | M2-B |
| S2 | Rumah Rapi | cosmetic | cosmetic sink | yes (cosmetic panel) | M2-B |
| S3 | Gaya Depan | cosmetic | cosmetic sink | yes (try-on) | M2-C |
| S4 | Warung Serba Ada | utility | none (free) | yes (utility panel) | M2-B |
| S5 | Boards | content | none | partial (mission list) | M2-A |

**MVP shop scope:** S1 + S4 + S5. S2 is the first cosmetic test; S3 is deferred.

---

## Part 3 — Anti-inflation checklist

Before any city purchase ships, answer:

1. Does the item already exist in `Catalog`? → surface it, don't duplicate.
2. Is it cosmetic? → confirm zero effect on yield, reveal, worker rate, tier.
3. Does it add a new persisted field? → director + schema review, not M2-A/B.
4. Can it be bought without walking? → then the walk is pointless; move it.
5. Does the price come from a measured M1 wallet distribution? → if no, do not
   author a price.
6. Does the event reward reuse an existing reward? → if no, reject or make it
   cosmetic-only.

---

## Part 4 — Content authoring cost

| Item | Approx. authoring cost | Notes |
|---|---|---|
| One shop shell | 1–2 dev-days | 100–120 parts, no interior |
| One cosmetic room item | 0.5–1 dev-day | 6–20 parts |
| One avatar accessory | 0.5–1 dev-day | Part-composed only |
| One event pop-up dressing | 1–2 dev-days | reuses plaza |
| One daily brief | 0.25 dev-day | authored text + existing mission tag |
| One festival overlay | 2–4 dev-days | art-dominated |

These are planning ranges for one director coordinating agents, not calendar
promises.
