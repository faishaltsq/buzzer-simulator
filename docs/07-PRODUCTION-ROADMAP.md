# Buzzer Simulator — Production Roadmap

## Delivery policy
**V0 is an internal technical prototype, not a public game.** Its vertical slice proves publishing both with and without a mission, confirmed Cuan, first phone upgrade, visible world feedback, and persistence. **M1 is a content-complete closed-beta candidate** with PC Rumah, rotating contexts, two online workers and an actual home-studio goal. Wider release requires measured closed-beta playtests and a separate director decision. Estimates below are planning ranges for one director coordinating agents, not calendar promises. Art direction and real Studio/phone review remain critical path. Each shared core file has one owner at a time.

| Stage | Rough focused effort | Depends on | Deliverable and exit gate |
|---|---|---|---|
| P0 foundation | 2–4 dev-days | Rojo pin, Studio check | Shared catalog/context/rules/profile v1 contract, Rojo production/test builds and real rules assertions; no scene |
| V0A first connected loop | 5–8 dev-days | P0 | Bedroom `OldCRT.rbxmx` at `TerminalSlot` with `DashboardPromptAnchor`; cheap/fast phone at `PhoneSlot` provides the sole yield even when publishing through CRT BuzzerOS. Both Rojo projects resolve reviewed V0 prefabs; one organic context/post payout, first food-stall context/bonus, fast-phone purchase and model swap; Studio Play evidence |
| V0B durability | 3–5 dev-days | V0A | Global pending-post recovery, organic settlement and claim idempotency, DataStore lease, reload of all transitions, forced-failure UI; no blank overwrite |
| V0C UX/art prototype | 2–4 dev-days | V0B | Mobile/PC camera/input, first-run observation, phone visuals, asset review. Explicit internal prototype sign-off **only** |
| M1 context and PC | 4–6 dev-days | V0C | Three organic contexts, four missions x three contexts, 12 feed cards, PC Rumah and visible/payout progression, tiers 1–2, three-style simulator |
| M1 first worker | 3–5 dev-days | M1 context/PC | Paid desk 1, trainee 1, banked 1.5 Cuan/s, online-only behavior and visible worker |
| M1 second worker/home studio | 2–4 dev-days | First worker | Paid desk 2, trainee 2, tier-2 gate, 3 Cuan/s total, two occupied seats and chapter-complete objective |
| M1 closed-beta hardening | 3–6 dev-days | Home studio | All closed-beta gates in `09`, content/editing review, real lower-end phone, dev/staging rejoin and rollback rehearsal; director beta Go/No-Go |
| M2+ expansion | Separately estimated | Measured M1 balances/player needs | Office/property/equipment or fresh mechanics; no locked placeholder cost |

More agent concurrency cannot parallelize core contract review, Studio art inspection, or DataStore integration. Cut decorative feed cards or extra audio first; do **not** cut the organic loop, PC earning multiplier, second worker, trusted saves, responsive UI, or server validation while still calling it a content-complete M1. If M1 scope misses the gate, keep it private and replan the closed-beta milestone; wider publication remains a separate decision.

## Integration checkpoints
- **IC-0 foundation:** Production/test Rojo builds; pure rules specs run with nonzero assertion count; contexts, device yield and v1 schema frozen for dependent tasks.
- **IC-1 server posting:** Fake-store and Studio tests prove organic credit once, campaign post organic credit once, food-stall 80 bonus once, phone purchase 50 once, and cross-mode global post slot.
- **IC-2 world/UI:** Spawn, `OldCRT` prompt and productive phone, organic Create initiated inside CRT BuzzerOS with equipped-phone payout, mission composer, claim, purchase, PC replacement at stable `DashboardPromptAnchor`, and close/death/expiry camera recovery work end to end on phone/PC viewports.
- **IC-3 durability:** Dev-universe rejoin at published/settling/paid/claimed/purchased states; lease collision and failed settlement/worker-bank writes block false spendable balance. V0C sign-off remains internal.
- **IC-4 M1 economy:** Catalog agrees with `04`; PC/desk/2-worker affordability and tier gates reproduce all three active/balanced/passive scenario rows. Real playtest checks pacing and context comprehension rather than trusting the simulation alone.
- **IC-5 closed beta:** On the **exact** candidate build, rerun security, saved-profile recovery, asset/permissions, phone performance, uncoached first-session, second-session, idle 20-minute, write-pressure and rollback gates before a limited beta. Collect actual playtest evidence before any wider-release decision; do not add M2 retention features at this gate.

Codex reviews each merge against contracts and actual test output; never accept a subagent's self-reported success. A failing checkpoint blocks work that relies on it.

## Cuts, risks and mitigations
**Protect:** one publishing mechanic shared between organic and mission; rotating strong template by context; earned Cuan on gear; home PC before staff; two staff seats for a truthful closed-beta incremental arc. **Cut first:** extra decorative feed cards above clue minimum, custom profile art, audio variations, notifications, analytics, unshipped office props. M2 concepts and paid boosts do not belong in M1.

| Risk | Severity | Early signal | Response |
|---|---|---|---|
| Confirmed-credit loss / duplicate post | Critical | credit rolls back after success, repeated settlement | Conditional save, operation ID, global pending post, fake failure/rejoin tests |
| Worker bank misrepresented | High | pending shown as spendable, offline catch-up | Separate preview/banked display; 30s checkpoint; zero offline test |
| Organic mode feels like tapping | High | same choice pressed without reading contexts | Improve clue/result rotation and pay differential; no per-click Cuan |
| Content cap reached rapidly | High | second hire < targeted window, high end-wallet | Three-style simulation and real sessions; do not guess M2 prices |
| Room too crowded with two workers | High | mobile camera hides PC/prompt or workers clip | Blockout both slots before art approval; keep bedroom single prefab |
| Security/lease race | Critical | forged score or double claim on reconnect | Server-only mapping, strict remotes, serialized conditional writes |
| Mobile UI/performance | High | Create/claim hidden, frame spikes | Safe insets, low-end phone profiling, bounded feed/rigs |
| Agent file conflicts | Medium | diverging shared catalog/schema | Freeze IC-0, one owner and serial merges |

## Release and rollback
Use separate unpublished dev universe for API-backed tests, then a limited closed-beta candidate. Check one-player place setting, asset permissions, profile schema, remotes, rollback-capable reader, and exact tested build. Open beta access **only** with director approval; wider publication requires separate playtest evidence and approval. If a later build loses saves, revert the place version to the last known-good reader; do not run destructive migration or reset Cuan to solve a design problem. Verify actual Roblox release/rollback controls at release time; none was executed in this planning phase.
