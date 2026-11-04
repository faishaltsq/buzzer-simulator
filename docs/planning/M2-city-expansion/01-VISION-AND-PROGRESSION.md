# 01 — World Vision, Loop Integration & Progression

> **Covers**: §A World Vision, §D Gameplay Loop Integration, §E Progression Design.
> **Status**: Planning. No economy constants are introduced here.

---

## A. World Vision

### A.1 The fantasy

> *"The room is where the work happens. The city is where the work comes from."*

M1's fantasy is a solitary buzzer turning a rented bedroom into a working home
studio. It is intimate, slightly cramped, and entirely self-contained: the
player is the whole economy.

M2 adds the missing half of that fantasy — **the world that reacts to the
work**. The bedroom is the desk; the city is the street, the clients, the
competition, and the audience. The player is no longer a person posting into a
void. They live above a shophouse in a small Indonesian-flavored town where the
electronics shop owner knows their name, the mission board has a queue of
absurd local briefs, and the plaza fills up when a campaign lands.

The city must never feel like a lobby. It is a **neighborhood**: small,
walkable, hand-placed, and visibly low-budget in the same charming way the
bedroom is. Warm plaster, sage awnings, amber signage, wet asphalt at dusk,
one working fountain, three shops, a bus stop that is always "coming soon".

### A.2 Why the city exists in the loop

| Without the city (M1) | With the city (M2) |
|---|---|
| All content is behind one screen | Content has a place; briefs are physical objects |
| Upgrades are menu rows | Upgrades have a storefront and a walk |
| Progression ends at the bedroom walls | Progression has a horizon (districts, venue, tower) |
| The room's window looks at empty sky | The window looks at a real skyline (fixes V-03) |
| Session rhythm is post → post → post | Session rhythm is post → errand → post |

The city is **not** a second progression track. It is the *spatial delivery
system* for the existing one.

### A.3 How the exterior complements the indoor studio

| Bedroom (private) | City (public) |
|---|---|
| Focus, silence, the terminal | Noise, signs, other people's problems |
| Publishing and claiming | Collecting briefs and buying things |
| Worker rigs, passive income | Ambient NPCs, no economy role |
| Camera locked to a small room | Camera opens up; landmark sightlines |
| Personal upgrades, visible at the desk | Public identity: cosmetics, storefronts, signs |
| Home base, always one prompt away | Temporary, purposeful, always returnable |

The design contract: **anything that earns happens indoors; anything that
directs earning happens outdoors.**

### A.4 Why this improves retention and progression

1. **A reason to re-enter the world after the first post.** The daily board and
   the mission queue rotate outside the room. Checking them is a 20-second trip,
   not a menu refresh.
2. **A visible goal beyond the second trainee.** The M1 endpoint (two workers,
   full room) becomes a *threshold*: the door unlocks and the camera pulls back.
   That is a chapter break players can see.
3. **Cheap novelty.** Re-dressing one plaza is far cheaper than authoring a new
   room, and it reads as a live world.
4. **Session shape.** The 10-second walk creates a natural pause between post
   cycles without adding a timer or a modal.
5. **Cosmetic expression without power creep.** The room and avatar can be
   decorated from city shops with zero effect on Cuan, which protects the M1
   balance the director is currently freezing.

---

## D. Gameplay Loop Integration

### D.1 The loop before M2

```text
        ┌──────────────────────────────────────────────┐
        │                 BEDROOM                      │
        │                                              │
        │  CRT/PC prompt → BuzzerOS → Create post      │
        │        ↑                         ↓           │
        │  claim bonus ← reveal result ← server settle │
        │        ↓                                     │
        │  Upgrades / Workers (BuzzerOS tabs)          │
        └──────────────────────────────────────────────┘
                     one screen, one room
```

### D.2 The loop after M2

```text
                 ┌───────────────────────────────┐
                 │        BEDROOM (base)         │
                 │  terminal → BuzzerOS → post   │
                 │  claim → upgrade → hire       │
                 └───────────┬───────────────────┘
                             │  Door prompt ("Keluar")
                             │  ~10 s walk, fade, no loading screen
                             ▼
        ┌────────────────────────────────────────────────────┐
        │                    CITY HUB                        │
        │                                                    │
        │  Mission Board ──► brief added to BuzzerOS queue   │
        │  Daily Board   ──► one rotating authored brief     │
        │  ElectroMart   ──► opens the EXISTING Upgrades tab │
        │  Rumah Rapi    ──► cosmetic room decor (no stats)  │
        │  Event Plaza   ──► timed authored challenge        │
        │  Signposts     ──► landmark stamps (cosmetic)      │
        │  Future Gate   ──► locked, visible, unexplained    │
        └───────────┬────────────────────────────────────────┘
                    │  Door prompt ("Masuk") / HUD return chip
                    ▼
                 back to BEDROOM to publish
```

### D.3 Why the player leaves

| Reason | Frequency | Payoff |
|---|---|---|
| Daily Brief Board rotated | once per real day | one authored brief, existing reward class |
| Mission queue has a new brief | after each claim | next campaign available |
| A shop has a visible new item | after a milestone | cosmetic or existing upgrade |
| Plaza event window is open | 2–3× per week | authored challenge + plaza dressing |
| A landmark is unstamped | once per landmark | cosmetic stamp, no stats |
| Curiosity / sightline | first 3 sessions | orientation, skyline, "what's the tower?" |

Every reason has a **timer or a state flag the player can see from the door**,
so leaving is a decision, not a wander.

### D.4 Why the player comes back

1. **Publishing only works at the terminal.** The existing contract
   (`DashboardPromptAnchor` → BuzzerOS) is unchanged. The city has no composer.
2. **Workers bank while connected**, and the HUD income chip is the strongest
   reason to stay near the desk (existing behavior, unchanged).
3. **The objective chip points home** whenever an outdoor task becomes
   "publish the brief you just picked up".
4. **Door is always one prompt away.** Return-home is never more than a
   10-second walk plus one interaction.

### D.5 How city activities feed progression (without new numbers)

| City activity | What it changes | Existing state used |
|---|---|---|
| Mission Board | Makes the next authored mission available/visible | `MissionService` queue, `completedMissions` |
| Daily Brief | Reuses one existing mission reward | existing `Catalog.Missions[].reward` |
| ElectroMart | Opens the existing Upgrades tab | `Catalog.Devices`, `DeskPrices`, `HirePrices` |
| Rumah Rapi | Adds cosmetic-only room props | *new cosmetic catalog — director approval* |
| Event Plaza | Reuses an existing reward or a cosmetic stamp | existing mission reward / cosmetic table |
| Signposts | Cosmetic stamps only | *new cosmetic-only stamp table* |
| Future Gate | Nothing yet; sells the horizon | none (locked visual only) |

**Rule:** if a city feature cannot point at an existing field or an explicitly
approved cosmetic table, it does not ship. No parallel currency.

### D.6 Anti-"decorative-only" checklist

A city feature is allowed only if at least **two** of these are true:

- it changes what the player can publish next;
- it changes what the player owns or looks like;
- it changes where the player goes next session;
- it is visible from the bedroom window or the door;
- it removes a menu step (storefront replaces a tab hunt).

If none are true, it is set dressing — allowed only inside a zone budget, never
as a headline feature.

### D.7 Session rhythm target

| Phase | Where | Typical duration |
|---|---|---|
| Publish 1–2 posts | Bedroom | 40–60 s |
| Check objective / workers | Bedroom HUD | 5 s |
| Errand run (board + one shop) | City | 30–60 s |
| Return + publish brief | Bedroom | 20–40 s |
| Optional plaza event | City | 60–120 s |

The walk is deliberately **shorter than one post reveal** (13–18 s). Leaving
never wastes a reveal; the player can walk out, read a board, and be back before
the post settles. This is the single most important pacing constraint in M2.

---

## E. Progression Design

### E.1 What unlocks city access

**Derived gate, no schema change:**

```text
cityUnlocked =
  profile.tier >= 2                  -- "Studio Rumahan" (existing tier)
  AND #profile.workers >= 2          -- both trainees hired (existing field)
  AND #profile.ownedDesks >= 2       -- both desks owned (existing field)
```

- Uses only fields that already exist and are already validated.
- Tier 2 is already authored in `Catalog.Tiers` (1600 lifetime / 3 claims) and
  shipped via `Catalog.H2Shipped` since BS-13 (PR #7).
- The second worker is the M1 chapter endpoint (BS-13), so the door opens
  exactly when the home-studio chapter closes.
- No new tier, no new price, no new counter.
- `Catalog.Shipped` now carries `maxShippedTier = 2`,
  `maxShippedDeskSlot = 2`, `maxShippedWorkerSlot = 2`, so every term of the
  gate is reachable on the current build.

**Director decision still open — do not change the gate without approval:**

| Option | Gate | Benefit | Cost |
|---|---|---|---|
| **A (current default)** | Entire city opens after Tier 2 + two desks + two trainees | Clean chapter break; protects M1 closed-beta pacing; the door is a visible reward | Players who never finish M1 never see the city |
| **B** | Residential street + boards accessible earlier (e.g. Tier 1); shops/plaza/events gated after Home Studio | Early wonder; gives mid-M1 players a change of scenery | Splits the chapter break; risks distracting from unmeasured M1 pacing; needs a second gate surface |

**Recommendation: A.** The city is the next chapter, not a mid-chapter
distraction. The M1 endpoint is already a strong visible goal (two trainees,
full room), and the door unlocking exactly there makes the transition legible.
Option B should only be adopted if BS-14 playtests show players stalling
*without* looking for more world.

Both options are documented here; the documents implement **A** only. Option B
is not silently implemented anywhere in this package.

**Door behavior before unlock:** the door prompt is visible and locked, with
honest copy — *"The city opens when the studio is running. Hire your second
trainee."* This teases the chapter break without a fake button. It also gives
the HUD objective chip a natural next step.

### E.2 What is available immediately on first entry

| Content | Gate |
|---|---|
| Residential street, town center, plaza exterior | cityUnlocked |
| Mission Board with already-authored M1 missions | cityUnlocked |
| Signpost stamp tour (cosmetic) | cityUnlocked |
| Daily Brief Board (read) | cityUnlocked |
| Home door (return) | always |
| Future Gate (visual) | cityUnlocked, locked |

### E.3 What stays locked inside the city

| Content | Gate | Rationale |
|---|---|---|
| ElectroMart purchase counter | existing mission `neon_market` completed | the shop owner "knows" you after the market job |
| Rumah Rapi (furniture) | existing mission `fictional_gadget` completed | gadget review earns the decor contact |
| Event Plaza events | existing mission `brand_remix` completed | the plaza is for players who finished a campaign arc |
| Cosmetics kiosk | tier 2 (already true at entry) | keeps the first visit light |
| Future districts | director decision (schema v2) | not authored |

All of these reuse `completedMissions`, which is already persisted. No flags,
no migration, no new counters.

### E.4 Why this is post-M1 progression, not M1 padding

- M1's promise is: *two workers, a full room, a finished home studio.*
- M2's promise is: *the studio is now a business with a street address.*
- The gate sits exactly on M1's endpoint, so M2 cannot dilute the closed-beta
  measurements Agent 1 and the director are about to collect.
- The city's first hour contains **no new power**: it contains orientation,
  cosmetics, and the next queue of briefs. Power still comes from the existing
  device/desk/trainee ladder.

### E.5 Unlocking future districts / venues

Recommended shape (requires director approval, `M2-C` or later):

| Unlock | Trigger | Cost | Schema? |
|---|---|---|---|
| Office District | authored city quest chain (3 briefs) | none | needs `cityUnlocks` flags |
| Rooftop Venue | complete all 6 landmark stamps | none | cosmetic table only |
| Agency Tower lobby | chapter milestone (future) | director-authored | new chapter, later |
| Transit Gate | Office District unlocked | none | same flag table |

The schema change is deliberately deferred to the **last** milestone so M2-A/B
can ship with a frozen profile.

### E.6 Post-M1 progression curve (conceptual, no numbers)

```text
M1 chapter         M2 chapter                        M2+ chapter
──────────►        ──────────────►                   ──────────►
room complete  →   street → shops → plaza → gate  →  office / agency
(2 trainees)       (cosmetic + briefs)   (locked)     (future, unpriced)
```

The curve is **horizontal, not exponential**: the city adds *places and
expression*, not a new multiplier wall. This is intentional — the director has
not yet observed M1 end-wallet distributions, and any vertical M2 cost would be
a guess (ADR-12).

### E.7 Explicit non-goals

- No prestige/reset.
- No city currency.
- No offline city income.
- No district that grants a Cuan multiplier.
- No numeric price, reward, or tier authored in this package.
