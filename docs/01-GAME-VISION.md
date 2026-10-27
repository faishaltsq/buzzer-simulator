# Buzzer Simulator — Game Vision

## Product thesis
A single-player Roblox incremental/idle tycoon with a fictional social-media skin. Begin in a cramped bedroom with a cheap phone. Publish short posts for organic Cuan, take optional fictional client campaigns for bonus Cuan, and hire visible staff for online passive Cuan. Reinvest in a better phone, **PC Rumah**, and two home-studio workstations. Every purchase must change earning capacity or unlock automation, and also change the room. BuzzerOS is the player's software; Buzzline is a text-first fictional feed. No real social-platform integration, free-text player posts, or per-click money.

**Audience assumption:** Players who enjoy a short readable simulator session, optional active decisions, visible upgrades, and a useful idle rate on PC, mobile, and tablet. Session length and retention require playtests; no monetization in the first release.

## Design pillars and tradeoffs
1. **Post with or without a contract.** One publishing mechanic always earns organic Cuan on server-settled posts. A campaign adds an optional fixed claim bonus. Neither requires tapping during a timer; only one post can resolve at a time.
2. **Choices vary with context.** Each post shows an audience and fictional trend; three authored approaches have context-dependent fit. The same template is not best in all contexts. Skilled players can learn the finite set; deception or opaque randomness is not a retention strategy.
3. **Gear grows income.** Device yield multiplies organic payout and visible reach; reveal time also drops. Cheap phone to fast phone to PC Rumah is the shipped M1 equipment path. A laptop between phone and PC would delay the home-computer milestone while adding an asset and another price wall; defer it rather than invent a sidegrade.
4. **Idle is real but not dominant.** One trainee yields 1.5 Cuan/s and two yield 3 Cuan/s while connected. Missions speed up progression; a seeded idle player can still reach the second worker without repeating campaigns. No offline earnings or mandatory timed claims for workers.
5. **World and software agree.** The first interaction prompt is an old CRT running **only** the BuzzerOS dashboard. The owned cheap phone on its pad produces the posts. Buying PC Rumah replaces the CRT and makes it the one productive device; the stable prompt survives. No free PC-level income.
6. **Bounded, honest chapters.** M1 ends with a two-worker home studio in the original room, not a fake agency or endless upgrade catalog. Future property/office tiers require a separate content and balance decision based on actual saved balances.

Warm satire targets absurd fictional briefs and platform mechanics, not real people. Buzzline uses original names, icons, layout, and copy; Threads is only a text-first interaction reference. The server owns Cuan, posts, claims, purchases, hires, and persistence even with one player per server.

## Scope and success
**V0 internal technical prototype, not public-release MVP:** Bedroom, nonproductive old CRT/dashboard prompt, productive cheap phone, BuzzerOS, six feed posts, **one organic context**, one food-stall mission context, one shared publish/settle path, first fast-phone purchase, physical swap, save/rejoin and failure handling. It proves both active income paths, not a durable long-term game. No worker, productive PC, second room, or marketing claim of replay depth.

**M1 content-complete closed-beta candidate:** Three organic contexts, four repeatable missions with three audience/trend contexts each, twelve curated feed posts, three career tiers (0–2), cheap/fast phone and PC Rumah, two desks and two trainees in one furnished bedroom, aggregate online income, mobile UX, persistence/security/performance gates, and a visible two-worker home-studio chapter goal. Wider release requires real closed-beta player evidence and a separate director decision; this inventory is a target, not a claim of completed content.

**M2+ separately approved:** New room/office and upgraded equipment when fresh mechanics, art, balance, and saved-balance distributions justify them. No automatic prestige, invented post-M1 prices, multiplayer, offline payout, or live social APIs.

## First-session progression hypothesis
First 30 seconds: find the old CRT terminal, learn that the adjacent owned cheap phone earns posts, and publish one organic post before choosing any mission. Next: complete food-stall campaign, claim its 80-Cuan bonus, buy the 50-Cuan fast phone, observe yield and physical change. Reach PC Rumah through organic posts or campaigns; tier 1 then enables the first desk and trainee. Later, lifetime earnings unlock a second station and trainee. Modeled strong-fit PC and first-hire windows appear in `04`; they are **not** observed playtest results. Rejoin restores the exact accepted/resolving/paid/owned state; an unconfirmed write never masquerades as saved income.

## Product risks and probes
- **Organic post spam:** One global pending post, server-timed resolution, and a visible context that changes. If players mindlessly press the same option, rewrite clues and fit before adding more randomness or currency.
- **Early worker too weak:** Compare first desk+hire cost to an online passive rate and to active PC income; measure whether hire feels noticeable.
- **Late worker too easy for active players:** Record Cuan surplus and second-worker times; avoid fixed future prices before observing balances.
- **Thin public content:** V0 proves plumbing only. M1 needs varied contexts, two staff purchases, a visible home-studio endpoint, and repeat-session tests.
- **Tool/art risk:** Agent-generated geometry is a prototype; review prefabs in Studio and test on a real phone. Do not trade away persistence, accessibility, or authorization to add content.

## Navigation
`02` defines behavior; `03` authoritative contracts; `04` balance and three-style simulation; `05` UX; `06` room/assets; `07` stages; `08` agent tasks; `09` tests; `10` implementation handoff; `11` decisions; `12` historical incremental redesign; `13` final pre-BS-01 architecture review and checklist. These documents authorize no implementation.
