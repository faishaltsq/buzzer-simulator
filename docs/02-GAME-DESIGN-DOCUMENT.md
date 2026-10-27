# Buzzer Simulator — Game Design Document

## Contract of the experience
Publishing is the repeatable core verb; a mission is a **bonus objective attached to a post**, not the only source of active Cuan. One authored post settles into an organic payout. The player may publish without an accepted mission, or tag the post to their one active fictional campaign; a qualifying campaign post also advances impact and can make a one-time fixed mission bonus claimable. Hired trainees accrue online Cuan independently. Browse the fictional Buzzline feed, compare the audience/trend clue to three authored approaches, publish once, see the result, and choose the next investment. No per-click earnings, free text, real platforms, or runtime AI.

**Scope:** V0 is an internal technical prototype with one organic context and one mission context. M1 is a content-complete **closed-beta candidate**; wider release requires observed playtests and separate approval. M2+ concepts are not promised purchasable content.

## Three connected loops and objective ladder
1. **Organic:** Read the next displayed audience/trend context in Buzzline; pick one of three templates; `PublishOrganic`; one global post slot resolves; server durably credits `organicCuan` automatically on settlement. Repeat without accepting a mission. A weak fit earns less but never loses Cuan. A post is not a claim button.
2. **Campaign:** Accept one unlocked mission; the server freezes that run's context and brief. `PublishPost` uses the **same** post scoring, organic payout, slot, feed insertion, and settlement as an organic post, then adds impact to that run. A strong post makes its fixed bonus claimable; a weak post requires a second post. `ClaimMission` awards the bonus once. Organic-only posts do not advance a mission even if its brief mentions the same topic.
3. **Worker:** After buying PC Rumah, a desk, and a trainee, an aggregate server scheduler credits 1.5 Cuan/s per owned worker while the writable player session is connected. Staff never auto-complete missions and earn nothing offline. A second desk/trainee doubles the online rate and makes the room look like a home studio.

First-run objective: locate the nonproductive old CRT BuzzerOS terminal, see the owned productive cheap phone beside it, publish one organic post, take food-stall contract, claim, buy fast phone, and see its new payout/model. Later objectives: PC Rumah, tier 1, desk 1, trainee 1, tier 2, desk 2, trainee 2. Objectives point to affordable next steps but do not force a single earning mode. A seeded passive-oriented player must complete the three introductory campaigns for tier 1, but can reach tier 2 and the second worker without repeating missions. Post-M1 agency growth is a separate chapter.

## Fictional Buzzline and context variation
- V0: six authored feed cards, eight bounded NPC identity labels, one organic context and one food-stall mission context. M1: twelve cards, twelve NPC labels, **three organic contexts and three contexts per each of four missions**. Each context names a fictional trend, audience, and readable clue; its three templates are authored. Feed cards link to the relevant context. Pinned clue cards remain discoverable even when the remaining cards rotate.
- Public catalog: mission definitions (`missionId`, `minTier`, `requiredImpact`, `reward`, three templates, three context IDs with trend/audience/clue text keys); organic contexts (`contextId`, trend/audience/clue keys, three template IDs). Private server scoring catalog: each template has authored trend/audience affinity tags. Score each template for the shown context as `2 * trendMatch + audienceMatch` (each match 0 or 1); the **unique highest** score is strong, others weak. Validate exactly one winner for each `(missionId, contextId)` and organic context; reject a catalog with ties at build/startup. Each mission's three contexts make **different** templates strong. V0 ships only first contexts; M1 expands catalog without changing contract shape.
- On `AcceptMission`, assign the next context by a saved per-mission counter modulo the three published contexts; increment that counter as part of accepting and freeze the context in the run. The first food-stall run uses `meal_time`; reconnection never rerolls it. On `PublishOrganic`, select the next organic context from the saved `nextOrganicSequence` modulo catalog count, then increment the sequence in the durable publish. `Snapshot.nextOrganicContextId` advertises it; client cannot choose or reroll context. IDs and ordering must remain stable for saved runs and counters. Adding contexts later needs an explicit compatibility review.
- This prevents **one universal best template**, not mastery of a finite lookup table. Test whether context clues are readable and results teach fit. Do not hide fit behind random trend weights. If learned variants bore players, author new situations; do not add a pseudo-AI system.
- Show authored NPC feed plus at most ten recent own post summaries (mission and organic); no NPC per-second simulation. Player summaries store bounded IDs, final impact, organic payout, and timestamp; display likes/replies/reposts as a presentation split of impact. Fixed reply keys depend on result band. No real handles, uploaded player text, live web data, external links, or generated comments.

### Initial authored campaign inventory
| Mission ID | Scope | Fictional brief | First context | First strong template | Required impact | Fixed bonus | Unlock |
|---|---|---|---|---|---:|---:|---|
| `food_stall_launch` | V0/M1 | Warung Mie Orbit | `meal_time` | `meal_meme` | 100 | 80 | Intro; first mission |
| `fictional_gadget` | M1 | PipPod desk toy | `demo_curious` | `demo_joke` | 130 | 100 | 1 claimed mission |
| `neon_market` | M1 | Pasar Neon | `weekend_plans` | `event_thread` | 160 | 120 | 2 claimed missions |
| `brand_remix` | M1 | KokoPop launch | `before_after` | `comparison_thread` | 220 | 160 | Tier 1 |

Each mission has three authored contexts, each with a unique strong choice among its three templates. **Authoring fixture (not a replicated answer key):**

| Mode/mission | Ordered context IDs | Ordered strong-template IDs | Context signal |
|---|---|---|---|
| Organic | `organic_snack`, `organic_gadget`, `organic_weekend` | `snack_meme`, `demo_bit`, `local_roundup` | Audience and trend change each post |
| `food_stall_launch` | `meal_time`, `office_lunch`, `late_snack` | `meal_meme`, `queue_thread`, `late_night_quip` | Meal trend + student/office audience, then late-shift trend |
| `fictional_gadget` | `demo_curious`, `collectors`, `desk_setup` | `demo_joke`, `collector_thread`, `setup_thread` | Demo trend with two audiences, then desk trend |
| `neon_market` | `weekend_plans`, `bargain_hunters`, `food_walk` | `event_thread`, `price_list`, `food_map` | Weekend trend with two audiences, then food-walk trend |
| `brand_remix` | `before_after`, `nostalgia_wave`, `honest_review` | `comparison_thread`, `nostalgia_story`, `review_thread` | Remix trend with two audiences, then honest-review trend |

The private affinity tags must produce these **unique** winners under `2*trendMatch + audienceMatch`. For each mission, contexts 1 and 2 share a main trend matched by templates 1 and 2; their distinct audiences break the tie. Context 3 uses a separate trend matched by template 3. For food stall, both `meal_meme` and `queue_thread` match the meal trend, while student versus office audience selects the winner; `late_night_quip` matches the late trend. Organic contexts also carry distinct audience/trend keys and select different winning templates. Do not persist an answer key in public Catalog. The first-context choices above are **not** permanent mission answers; later contexts point to the other templates. M1 editorial work must write and review all twelve context clues and three organic contexts. M1 replay uses the same fixed bonus; there is no escalating reward for repeatedly selecting the same mission. ID/copy and fiction undergo an editorial originality review before public release.

## Post state and outcomes
One player has at most one global `pendingPost` (organic or mission) and at most one active mission. The mission states are `available -> accepted -> resolvingPost -> accepted` when impact is short, or `resolvingPost -> readyToClaim -> claimed`; `claimed` resides in history. Accepting a mission while browsing or making organic posts is allowed. Publishing an organic post while a mission is accepted/ready to claim is allowed, but never while **any** post is resolving. A failed or timed-out save preserves/reconciles the pre-command state; client retry never double credits a post.

Server assigns `postId`, context, frozen final impact and organic payout, `publishedAt`, and `settleAt` **once** at publish, and persists the pending post before replying. A settlement checks server time, atomically persists payout, own-post summary, and mission impact/status when applicable, then emits a confirmed balance. No paid post is paid again on refresh/rejoin. A mission cannot publish a third post; a strong first always meets requirement, and two weak posts always meet it. Weak first post never meets requirement even on PC. Claim is a separate one-time bonus mutation, recoverable after rejoin. An organic-only post never requires claiming. Closing BuzzerOS does not pause settlement; reconnect resumes it. Worker accrual and post settlement share a per-player serialized lane.

`Rules.postImpact(requiredImpact, fit, deviceYield)` uses `floor(B*1.20*yield)` for strong and `min(floor(B*0.75*yield), ceil(B*0.94), B-1)` for weak. `Rules.organicCuan(fit, deviceYield)` uses `floor(12 * (1.25 if strong else 0.75) * yield)`. There is **no payout per like** and no random payout reroll. `Catalog.Devices[deviceId].revealSeconds` is 18/16/13 for cheap/fast/PC; reveal is timed display, never active clicking. Exact values and price rationale are in `04`.

## Career, equipment, staff and property
| Tier | Name | Lifetime earned | Claims | Shipped unlock |
|---:|---|---:|---:|---|
| 0 | Buzzer Gabut | 0 | 0 | Organic posts, intro campaigns, cheap/fast phone, PC Rumah purchase |
| 1 | Buzzer Rumahan | 300 | 3 | First worker desk and trainee; `brand_remix` |
| 2 | Studio Rumahan | 1,600 | 3 | Second desk and trainee; home-studio chapter goal |

Current wallet and purchases never demote tier. `tier = highest shipped eligible tier`; M1 `maxShippedTier=2`. Future office/agency tier names and thresholds are editorial concepts **without** priced/unlockable entries in the M1 catalog. Three intro claims teach mission fit; subsequent tier progression can come from organic or passive earnings. Do not tie the second worker to extra mandatory mission farming.

| Equipment/automation | M1 price | Product effect | World effect |
|---|---:|---|---|
| Cheap phone | Starting | Yield 1.00; 18s reveal | Phone pad beside dashboard-only old CRT terminal |
| Fast phone | 50 | Yield 1.60; 16s reveal | Distinct phone model and phone UI detail |
| PC Rumah | 220 | Yield 2.50; 13s reveal | Replaces old CRT at stable dashboard prompt |
| Worker desk 1 + trainee 1 | 180 + 500 | +1.5 Cuan/s while connected | One station + seated visible worker |
| Worker desk 2 + trainee 2 | 250 + 750 | +1.5 Cuan/s more | Second nook + worker; home-studio milestone |

Exactly one player production device is equipped. Buying fast phone changes the productive phone-pad model; buying PC Rumah replaces the old CRT at the fixed dashboard terminal and retires the owned phone to decoration, never stacking device yields. The old CRT is dashboard-only and adds no equipment tier, ownership entry, yield or price. The bedroom has two authored worker slots; each desk enables its corresponding slot; worker cannot be hired without a PC, tier, paid desk, free seat, and funds. No wages, firing, resale, separate NPC economy loops, or offline earnings. A laptop between phone and PC is deliberately **not** in M1; revisit portable equipment only if it adds a distinct mechanic instead of another multiplier.

## Feedback, failure and out-of-scope
Home/Feed shows next organic context, confirmed Cuan, worker rate and any pending unbanked worker Cuan separately. A post shows its fit reason, organic Cuan on confirmed settlement, and optional mission impact/claim state. Shop compares current versus next yield, payout example and world model. A worker purchase shows rate change and occupied seat. Save failure blocks economic controls; never show unconfirmed post credit as spendable. A newly opened UI reads authoritative snapshot, not locally recomputed balances. Reduced motion, readable phone layout, close/reset camera, and input feedback are required by `05`.

M1 excludes real network effects, follower graphs, free-text composer, procedural/AI writing, PvP, multiplayer, offline income, paid boosts, prestige, infinite equipment, separate worker AIs, laptop sidegrade, new property, and fake unshipped office buttons. `03` owns authoritative state/remotes, `04` numbers/simulation, `05` UI, `06` visuals, `08` delivery ownership. Catalog ID/price/threshold changes require a cross-document and test update before coding.
