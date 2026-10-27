# Buzzer Simulator — Incremental Economy

## Balance model and invariants
All figures are **design hypotheses from a deterministic scratch simulation**, not player measurements. M1 has three reachable tiers (0–2), three production devices, four campaigns, three organic contexts, two workstations, and two online trainees. No paid boosts, offline rewards, inflation multiplier for replay, or uncapped purchase button. A strong choice on a mission post earns **organic Cuan plus** the fixed bonus only when the run is claimed. An organic-only post earns the same organic Cuan but no mission bonus. Money is credited on server-confirmed settlement; clicking publish or watching counts earns nothing by itself.

- `postImpact(B, fit, yield)`: strong `floor(B * 1.20 * yield)`; weak `min(floor(B * 0.75 * yield), ceil(B * 0.94), B - 1)`. `B >= 100` for all M1 missions. Strong first post always clears `B`; weak first never clears it; even two weak starter posts clear it. Impact only drives readable engagement and campaign completion, **not** extra spendable Cuan.
- `organicCuan(fit, yield) = floor(12 * fitMultiplier * yield)`, with strong `1.25`, weak `0.75`. Payout is **per settled post** in either posting mode. One global pending-post slot; no simultaneous mission/organic publishes; no payout for a failed save. Context/fit comes from server-only authored template affinity tags: `score = 2*trendMatch + audienceMatch`, with 0/1 matches and a unique maximum per context; client cannot submit tags or scores. No monetary noise or reroll.
- `ClaimMission` adds exactly `reward[missionId]` to balance and lifetime earned once per run and increments completed claims once. An unclaimed ready mission does not prevent organic publishing; an organic post does not advance it. Two-post cap applies to each campaign run.
- Worker rate = `1.5 * ownedWorkerCount Cuan/s` for 0–2 workers while the profile is writable and connected. Use one aggregate scheduler, `floor(fractionalIncome + rate * connectedSeconds)` with residual carry. **Bank** worker ticks with a conditional save at most every 30 seconds while healthy; UI displays banked balance and separately labeled unbanked accrual, never treats an unconfirmed tick as spendable. A purchase or claim first includes pending accrued worker Cuan in its durable write. On failed checkpoint, retain/reconcile in-memory pending accrual and block economic actions; a crash can lose up to one unsaved worker window (target <=30 seconds), not confirmed post/claim/purchase credit. No wall-clock catch-up after disconnect.
- Highest shipped tier requires `lifetimeEarned >= threshold` and `completedMissions >= threshold`; spending does not demote. Lifetime includes organic, mission, and banked worker earnings, **not** purchases. Start at zero Cuan. Whole-number currency and safe integer/finite guards remain; stop growth before `1e12` and avoid unsupported false precision in UI.

## Authored M1 values
| Production device | Scope | Cost | Yield multiplier | Reveal | Strong organic payout | Weak organic payout | World state |
|---|---|---:|---:|---:|---:|---:|---|
| Cheap phone | V0/M1 start | 0 | 1.00 | 18s | 15 | 9 | Productive phone beside dashboard-only CRT |
| Fast phone | V0/M1 | 50 | 1.60 | 16s | 24 | 14 | Clear phone replacement |
| PC Rumah | M1 | 220 | 2.50 | 13s | 37 | 22 | Replaces nonproductive CRT at terminal slot |

Payout examples use the exact floor formula above. Two upgrades increase strong post Cuan from 15 to 24 to 37 (**1.6x**, then **1.54x** actual integer payout) and shorten reveal modestly. Mission bonuses do **not** scale with equipment; double-dipping through organic Cuan plus bonus is enough. Old rule that devices mostly changed countdown/impact was not a convincing incremental purchase. A laptop would be a redundant intervening tier; M1 ships PC Rumah early instead. The old CRT is a dashboard-only access prop; the owned cheap phone alone grants starting yield. PC Rumah replaces the CRT and becomes the sole productive device.

| Mission | Required impact | Bonus on one claimed run | Unlock |
|---|---:|---:|---|
| `food_stall_launch` | 100 | 80 | First guided mission |
| `fictional_gadget` | 130 | 100 | At least 1 claim |
| `neon_market` | 160 | 120 | At least 2 claims |
| `brand_remix` | 220 | 160 | Tier 1 |

Replay retains bonus. A player can choose organic-only, but three early claims are required to open staff; **no extra claims** are needed to reach tier 2. Mission choice context rotates per run so one memorized choice is not permanently strong. Weak mission posts still earn smaller organic Cuan, but need an extra post for the bonus.

| Career tier | Lifetime Cuan | Claims | Unlock | Release |
|---:|---:|---:|---|---|
| 0 Buzzer Gabut | 0 | 0 | Cheap/fast phone, organic, intro missions, PC Rumah | V0 starter / M1 PC |
| 1 Buzzer Rumahan | 300 | 3 | Desk 1, trainee 1, `brand_remix` | M1 |
| 2 Studio Rumahan | 1,600 | 3 | Desk 2, trainee 2, home-studio chapter | M1 |

PC Rumah is **not** tier-locked: price and exact-next-device ownership gate it. Tier 1 still requires three introductory claims; the three non-remix first plays with starter/fast strong posts yield more than 300 lifetime Cuan. Tier 2 can be earned from connected workers or organic posting without new claims. No M2+ numeric catalog is locked: continued M1 earnings can accumulate, so pricing a future office from guessed balances would create instant-unlock or punitive inflation. Decide later tiers from observed wallet distribution and new content. Preserve accrued balances; do not quietly reset them.

| Automation purchase | Gate | Cost | Marginal output | Personal room effect |
|---|---|---:|---:|---|
| Worker desk 1 | PC Rumah + tier 1 | 180 | Enables slot 1 | First desk and chair |
| Trainee 1 | Desk 1 + tier 1 | 500 | +1.5 Cuan/s | One seated worker |
| Worker desk 2 | Trainee 1 + tier 2 | 250 | Enables slot 2 | Second compact nook |
| Trainee 2 | Desk 2 + tier 2 | 750 | +1.5 Cuan/s | Two working figures; chapter goal |

Both workers are the same simple role and rig; seat count is the authored bedroom cap (2). Marginal first bundle costs **680 Cuan** for 1.5/s (no-activity payback **7:33**); first hire alone costs **500 / 1.5 = 5:33**. Second bundle costs **1,000** for another 1.5/s (payback **11:07**); no wages, refund, stacking device yields, or hidden productivity stat. These ratios describe recouping spent Cuan, **not** economic profit over active alternatives. At PC, strong organic-only pace of 37 per 25 modeled seconds is 1.48/s; a first worker at 1.5/s is useful while browsing/idle but does not replace a good mission cycle (37+160 per modeled 65 seconds, about 3.03/s before staff). Workers are online-only; disconnect yields zero.

## Reproducible three-style scratch simulation
**Initial state:** zero wallet, no workers, cheap phone, first organic context strong. Each modeled publishing action completes and gets its confirmed payout at its end. First action is one organic post on cheap phone. Then mission order is food (80), gadget (100), market (120), remix (160); once available, repeat remix. All picks are strong. The model uses **no concurrent post slots**. Durations include reveal plus reading/navigation/claim where relevant: campaign 80s cheap, 70s fast, 65s PC; organic 30s cheap, 28s fast, 25s PC. Only reveal times (18/16/13s) are in-game rules; remaining overhead is a scenario assumption, not artificial wait/cooldown code.

At every finished action or 30-second worker bank, auto-buy the next affordable purchase in this order: fast phone, PC Rumah, desk 1, trainee 1, desk 2, trainee 2; repeat while successive purchases are affordable. Eligibility applies even if wallet is sufficient. Worker bank boundaries are global connected-session times `30, 60, 90...` seconds. Fractional output carries; purchase checks can occur after a bank with no player action. No rewards while disconnected and no fast-forwarded offline income. The three **policies** differ:
- **Active:** After first organic tutorial post, publish/claim missions continuously.
- **Balanced:** After first organic tutorial post, alternate mission and organic posts.
- **Passive-focused:** After first organic post, complete exactly three intro missions to unlock tier 1; publish organic posts until trainee 1 is affordable; then remain connected and idle for tier 2/second worker.

| Policy | Fast phone | PC Rumah | Desk 1 | Trainee 1 | Desk 2 | Trainee 2 |
|---|---:|---:|---:|---:|---:|---:|
| Active | 1:50 | 4:10 | 5:15 | 7:25 | 10:40 | 11:45 |
| Balanced | 1:50 | 3:56 | 5:26 | 9:31 | 12:31 | 14:01 |
| Passive-focused | 1:50 | 4:10 | 5:00 | 10:50 | 18:20 | 22:20 |

At **10 connected minutes after the first hire**, modeled incremental earnings by source (second worker can join inside this window):
| Policy | Mission bonuses | Organic posts | Banked workers | Total | Worker share |
|---|---:|---:|---:|---:|---:|
| Active | 1,440 | 333 | 1,335 | 3,108 | 43.0% |
| Balanced | 960 | 481 | 1,392 | 2,833 | 49.1% |
| Passive-focused | 0 | 0 | 870 | 870 | 100% |

The passive row banks 870, not exactly 900, because the last partial 30-second bank is still unconfirmed at that observation instant. The first worker remains useful even if the player does no new posts. More staff makes the late-game worker fraction larger; early active PC play is faster than idle. Treat these times as **conditional outputs** of the exact policy/durations, not guaranteed player outcomes. A weak choice can require another reveal and earn less; slow readers change timings; context-copy quality determines real engagement. The authored PC/desk/hire costs and three intro claims are cross-checked by scenario, not proven fun.

## Live balance probes and expansion rule
During BS-11/BS-13 create a Python-standard-library `tools/economy_sim.py` reproducing the policy above and checking **all three** milestone rows and source subtotals against the shipped Luau catalog. Sweep slow-reading durations, weak-first mission choices, phone/PC purchase orders, 0/1/2 workers, 30-second checkpoint phase, early disconnect/rejoin, and first/second worker payback. Assert nonnegative balance, no earned Cuan before confirmed settlement, no double claim/paid post, and eventual worker access for all three policies. Simulation asserts consistency, not retention.

In uncoached Studio/dev-universe playtests record times to first organic payout, first claim, phone, PC, each desk/hire; organic versus mission versus worker Cuan; number of weak choices; connected idle time; wallet at end of session and after rejoin. Compare distributions by device/experience, not one average. If active second-hire arrives too quickly, improve content/goal pacing before adding a fake cost wall; if organic-only becomes spam, change context feedback or post cadence rather than inventing arbitrary currency penalties. If staff payback feels trivial or punishing, adjust rate/cost together and regenerate simulations. M2 property/equipment prices require measured M1 balances and a new authored chapter, not an uncapped inflation curve.
