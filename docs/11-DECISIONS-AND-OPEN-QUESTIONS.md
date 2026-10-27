# Buzzer Simulator — Decisions and Open Questions

## Decision status
These are **accepted for planning**, not implementation or publication approval. This revision supersedes the old mission-only/laptop-first balance before any code or persisted profile exists. Proposed v1 schema changes are **not a migration**. Director sign-off and proof gates still precede work. A load-bearing change needs an ADR amendment, catalog fixture update, targeted tests, and synchronized `02`/`03`/`04`/`08`/`10` contract review.

| ID | Planning decision | Alternatives and tradeoff |
|---|---|---|
| ADR-01 | One player per server; per-user server-owned profiles | Shared place deferred. Lease and user checks still mandatory for reconnect overlap. |
| ADR-02 | Curated fictional Buzzline, bounded own posts, no free text/AI | Less endless novelty, far lower moderation/performance cost; invest in authored readable trends/audiences. |
| ADR-03 | Server-frozen outcome, timed reveal, persisted settlement | No client-supplied likes/Cuan; 30s worker bank and post/claim saves add DataStore writes but prevent false confirmed payouts. |
| ADR-04 **amended** | **One post path earns organic Cuan; optional campaign adds fixed claim bonus; staff add online idle Cuan** | Mission-only was a finite task list, not an incremental economy. No per-click money; publishing has one global slot. |
| ADR-05 **amended** | Cheap phone -> fast phone -> **PC Rumah**; laptop not M1; 2 seats in one bedroom | Earlier PC gives a visible multiplier and staff prerequisite. Deferring laptop removes an asset/price wall; second seat adds some art/testing but gives closed-beta idle depth. |
| ADR-06 | Conditional `UpdateAsync`, same-key 240s lease/90s renewal, durable commands/settlements and 30s worker banking | More writes and explicit preview UI versus last-writer-wins or misleading spendable ticks. Confirm budget in dev universe.[1][2][3] |
| ADR-07 | Rojo v7.4+ Luau plus reviewed Studio-exported prefab models | Git-friendly code; art still needs Studio/human review.[8][13][14] |
| ADR-08 **amended** | BuzzerOS `ScreenGui` opens from **nonproductive old CRT**, later replaced by bought PC Rumah; cheap phone produces starting posts | Restores the physical computer fantasy. Costs one simple reviewed prop and a separate phone pad; explicit copy avoids implying free PC yield. Viewport, not device tier, selects UI layout.[6] |
| ADR-09 **amended** | One aggregate worker scheduler, 1.5/s each, two locally animated rigs max in M1 | Better first-worker payback than 0.75/s; still no NPC-specific earnings threads or offline accrual. |
| ADR-10 **amended** | Internal V0 proof then **content-complete closed-beta** M1 candidate with 3 contexts/mission and two trainees | More content/visual scope than previous M1; closed-beta observation precedes a separate wider-release decision. |
| ADR-11 **new** | Server-only `2*trendMatch+audienceMatch`, unique authored winner per context | One best template per context can be learned; rotating readable contexts prevents one permanent answer without opaque random scoring or runtime AI. |
| ADR-12 **new** | Candidate M1 tiers 0/1/2 only; no guessed M2 prices or prestige | Measured M1 end wallets must inform next chapter; hoarded online Cuan can trivialize future costs. Preserve balances; future content needs actual new goals. |
| ADR-13 **new** | `Snapshot` carries server-initiated OpenComputer/denial/expiry; `GetSnapshot` optionally looks up an original mutation ID under its own fresh request ID | No fourth remote or read query pretending to be the mutation. Session generation prevents stale close/command after reopen; bounded outcome ring limits reconnect certainty. |
| ADR-14 **new** | Piggyback worker bank and lease renewal on due durable actions; isolate idle 30s bank | Reduces write pressure without making confirmed payout speculative. Measure hot-key latency in closed beta before changing reveal or rewards.[1][3] |

## Assumptions to verify
1. Rojo v7.4+ CLI and actual Studio Play/test-runner access can be established. Studio executable exists, but a current plugin/MCP connection, build and live DataStore are unverified.
2. Private unpublished dev universe isolates Studio API writes from production data. One-player place cap is configured at release, not by Luau.
3. An 18-second cheap-phone reveal leaves room for reading the next context instead of dead waiting; phone/PC cycle times in `04` include assumed reading overhead, not enforced waits.
4. Affinity tags can produce one unique winner for **all** shipped context fixtures, with trend and audience both changing choices. The concrete context IDs and first winners are specified in `02`.
5. Modeled first worker times (7:25 active, 9:31 balanced, 10:50 passive-focused) and second worker times (11:45, 14:01, 22:20) are **simulation outputs**, not observed UX or retention results.
6. Old CRT, separate phone pad and two worker nooks fit a readable, walkable single-bedroom layout at mobile quality; art/placement might force a different room plan before M1 approval.
7. No offline Cuan/monetization in first release. A worker's banked balance updates <=30s in healthy sessions; a crash may lose an unsaved worker window. Confirmed post/claim/buy credits must survive rejoin.
8. Fictional brand/tier names and UI copy remain editorial; persisted IDs/context order may not be casually renamed after saves exist.

## Open questions with default and decision gate
| Question | Default | Gate |
|---|---|---|
| Does organic posting feel distinct from missions? | Shared composer, 3 organic contexts, automatic payout; mission optional bonus. | V0 first-run and M1 repeat-session observation; rewrite contexts if players spam one choice. |
| Are trend/audience clues readable on phone? | Show both plainly and an outcome explanation. | Real-phone uncoached choice comprehension, not a catalog count alone. |
| Are 18/16/13-second reveals too long/short? | Keep table in `04`. | V0/M1 idle-abandonment and measured post-cycle distributions; change timing and simulation together. |
| Is first/second worker ROI meaningful? | 680/1.5 and 1000/1.5 no-activity payback. | Observe purchase timing, passive share and voluntary use after hire; adjust cost/rate **together**. |
| Can two rigs fit without blocking terminal/phone? | Two authored bedroom slots in M1. | BS-05 blockout and BS-13 real phone visual/performance sign-off; keep M1 in closed beta if not. |
| Should staff earn offline? | No in M1. | Later analysis of rejoin motivation, save/timestamp abuse, and economy inflation. |
| How to price office/later equipment? | No numbers or buttons in M1. | Measured wallet distribution, new authored content, backward-compatible save/rollback design. |
| Is multiplayer/monetization warranted? | Neither in M1. | Separate product hypothesis, abuse/economy analysis and architecture decision. |

## Cross-document change control
`01` product thesis; `02` behavior/context IDs; `03` network/schema/trust; `04` prices/formulas/simulation; `05` screens; `06` room/asset slots; `07` gates; `08` task ownership; `09` tests; `10` copy-ready handoff; `12` historical redesign; `13` current pre-BS-01 decisions/readiness. Prices/tiers/context order/worker rates require synchronized catalog fixtures, simulator and test updates. A post/worker persistence change requires `03`, `08`, `09`, `10` and migration fixtures **if** data has shipped. No plan text may be called verified gameplay without Studio and dev-store evidence.

## Sources
[1] https://create.roblox.com/docs/cloud-services/data-stores/best-practices
[2] https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing
[3] https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits
[6] https://create.roblox.com/docs/ui/on-screen-containers
[8] https://rojo.space/docs/v7/project-format
[13] https://rojo.space/docs/v7/sync-details
[14] https://github.com/rojo-rbx/rojo/blob/master/CHANGELOG.md
