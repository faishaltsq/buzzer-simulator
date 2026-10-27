# Buzzer Simulator — Design Change Report and Consistency Audit

> Historical incremental-economy decision record. `13-PRE-BS-01-ARCHITECTURE-REVIEW.md` supersedes its phone-dock access and public-candidate wording; prices, formulas and three-loop findings here remain unchanged.

## Design correction
The former plan made campaigns the only repeatable active income; equipment mostly shortened a reveal; PC Rumah and the second worker sat after the first release. That was a finite mission game with an idle garnish. The revision makes **one authored post** the shared earning action: organic Cuan at server-confirmed settlement, an **optional** fixed campaign bonus at claim, and workers that bank online Cuan while the player remains connected. It preserves BuzzerOS/Buzzline, the fictional text-first feed, single-player-first server authority, Rojo/Luau ownership, and the small V0 proof.

| Decision | Before | Revised and why |
|---|---|---|
| Main earnings | Mission claim only | Every settled post earns organic Cuan; contract claims add a separate bonus. Posting works without taking a mission. |
| Equipment | 70 phone, 350 laptop; mainly faster reveal | 50 phone, **220 PC Rumah**; yields 1.00/1.60/2.50 and strong organic Cuan 15/24/37. Laptop deferred: another price/asset gate would dilute the home-PC milestone. |
| Access | Generic desk/computer | Owned cheap phone docks at stable desk prompt; BuzzerOS runs on it. No free productive PC. |
| Choices | One fixed strong template per mission | Three contexts per M1 mission; trend and audience affinities pick a unique winner. One memorized template cannot win every context; eventual mastery of a finite set is intentional. |
| Automation | One 0.75/s worker after 900 combined Cuan | Two 1.5/s trainees, purchased in stages for 680 then 1,000 combined Cuan; first bundle idle payback ~7:33. Still online-only and one aggregate scheduler. |
| Release | V0 finite demo, M1 first hire | V0 **internal technical prototype**; M1 public candidate needs PC, 4x3 campaign contexts, 3 organic contexts, two staff seats, mobile/data/performance proof. No fake office promise. |

## Final gameplay and balance at a glance
**Organic:** Show next trend/audience and three approaches; publish; server settles one post and automatically banks `floor(12 * fit * deviceYield)` Cuan, with strong fit `1.25` and weak fit `0.75`. **Campaign:** Tag a post to the one active run; it pays organic Cuan as usual and builds impact. Strong fit completes the mission in one post, weak in two; claim its fixed 80/100/120/160 bonus once. **Worker:** Buy PC, then a paid desk and trainee; bank 1.5 Cuan/s per trainee every <=30 healthy connected seconds. Unbanked worker Cuan is preview-only, not spendable. No offline credit or per-click reward.

Server-only authored affinity uses `2*trendMatch + audienceMatch`, with a required unique winner for each published context. Public catalog exposes readable trend/audience/clue, not private affinity tags. Post impact is display/mission progress, not spendable currency. Devices multiply organic earnings and visible reach; mission bonus stays fixed to prevent uncontrolled stacked multipliers. The initial phone dock is an access point, not a free equipment tier. The two-worker bedroom is an honest **home studio**, not an agency.

| Item | Price | Yield/rate | Gate |
|---|---:|---:|---|
| Fast phone | 50 | organic strong 24/post; reveal16s | Starting cheap phone |
| PC Rumah | 220 | organic strong 37/post; reveal13s | Fast phone owned |
| Desk 1 + trainee 1 | 180 + 500 | 1.5 Cuan/s | PC, tier1: lifetime300 and 3 claims |
| Desk 2 + trainee 2 | 250 + 750 | 3 Cuan/s total | First worker, tier2: lifetime1600 and 3 claims |

**Modeled first session** (strong choices, one opening organic post, 30-second worker banking; all assumptions in `04`):

| Play style | Fast phone | PC Rumah | First worker | Second worker |
|---|---:|---:|---:|---:|
| Active campaigns | 1:50 | 4:10 | 7:25 | 11:45 |
| Balanced posts/campaigns | 1:50 | 3:56 | 9:31 | 14:01 |
| Passive-focused seed, then idle | 1:50 | 4:10 | 10:50 | 22:20 |

Within ten connected minutes after first hire, modeled active/balanced/passive earnings are respectively 3,108 / 2,833 / 870 Cuan; worker shares are 43.0% / 49.1% / 100%. These are deterministic scratch-model **outputs**, not observed session lengths. The passive-focused policy still completes three introductory claims to unlock tier 1, then can unlock tier 2 from online worker income. The passive 870 reflects an unbanked partial checkpoint at the observation instant.

## Scope and architecture amendments
V0 has one organic context, one food-stall mission context, six feed cards, cheap/fast phone, room prompt, shared publish/settle, claim, saved upgrade, and recovery. It is not a commercial feature inventory. M1 requires three organic contexts, four repeatable missions with three contexts each, PC Rumah, tiers 0–2, two workstations/trainees, twelve feed cards, a home-studio end goal, and public Go/No-Go evidence. M2 office, laptop, monetization, prestige, offline Cuan, and multiplayer remain separate decisions. Cuan can accumulate after M1 chapter completion; future prices require measured wallet distributions, not arbitrary preset exponential costs or a balance reset.

Preserved: one-player server setting with per-user authorization; three remote envelopes; server-only score/reward/costs; conditional DataStore `UpdateAsync`, per-user 240s lease and 90s renewal; bounded history, retries and failure freeze; Rojo v7.4+, reviewed `.rbxmx` prefabs, one aggregate worker scheduler, safe-area ScreenGui and manual Studio/device quality gates. **Amended v1 before code:** one global `pendingPost`, saved organic/mission context counters, two owned desk slots and workers, recent mutation IDs, separate banked/pending worker Cuan; new `PublishOrganic`, slot-indexed desk/hire commands; durable settlement before spendable credit. No migration is needed because no profile or code has shipped. A future released-schema change will require migration fixtures and rollback-compatible readers.

## Critical challenges and unresolved risks
1. A finite set of three contexts per mission eventually becomes learnable. The goal is readable context-dependent choice, not perpetual mystery; validate replay enjoyment before adding variants.
2. First worker gives comparable online income to PC organic-only posting (1.5/s versus modeled 37/25 = 1.48/s). Active missions remain faster; second worker may raise idle share substantially. Watch real balance distributions and avoid speculative future price promises.
3. Two visible workers in one bedroom may overcrowd mobile framing. Block out both seats before authoring final art; keep M1 private if visual/phone gate fails.
4. Durable publish+settle and 30-second worker banks cost DataStore writes. Test platform budgets, ambiguous responses and lease contention in a separate dev universe. Unbanked preview can roll back on crash; a confirmed credit cannot.
5. An active player may reach the second worker quickly and then save Cuan without an M2 sink. Do not add a fake cost wall to force a session; gather second-session/hoarded-wallet evidence before planning office pricing.

## Consistency audit of the 11 revised planning documents
| Document | Contract reconciled |
|---|---|
| `01-GAME-VISION.md` | Incremental thesis, three loops, phone-to-PC, internal V0/public M1 scope |
| `02-GAME-DESIGN-DOCUMENT.md` | Shared post behavior, 4x3 mission and 3 organic context IDs, tier/device/worker rules |
| `03-TECHNICAL-ARCHITECTURE.md` | v1 profile, one pending post, remotes, server affinity, durable credits, 30s worker bank |
| `04-INCREMENTAL-ECONOMY.md` | Formulas, exact prices/rates/tiers, active/balanced/passive simulation |
| `05-UI-UX-SPECIFICATION.md` | Organic Create separate from Missions, confirmed vs pending Cuan, phone/PC layout |
| `06-WORLD-AND-ASSET-PLAN.md` | Cheap phone dock, stable prompt, PC footprint, two paid worker slots in one room |
| `07-PRODUCTION-ROADMAP.md` | V0 internal gate, M1 content/first worker/second worker/release gates |
| `08-AGENT-TASK-BACKLOG.md` | BS-01–BS-14 ownership, new posting/PC/staff assignments and checks |
| `09-TESTING-AND-QUALITY.md` | Three-loop tests, context uniqueness, durable payouts, three play styles, release evidence |
| `10-MVP-IMPLEMENTATION-HANDOFF.md` | Updated contract sheet and copy-ready BS-01 prompt; no implementation authorization |
| `11-DECISIONS-AND-OPEN-QUESTIONS.md` | Amended ADRs, explicit tradeoffs, assumptions and later gates |

This matrix is a **document/contract audit**, not evidence that game code, Studio play, assets, DataStore behavior, or player balance are verified. Reconcile the scratch simulation against a future checked-in `tools/economy_sim.py` and actual Luau catalog, then playtest and adjust before M1 release. Stop at planning until the director explicitly authorizes implementation.
