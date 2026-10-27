# Buzzer Simulator — UI/UX Specification

## Two surfaces, one economy
**World HUD:** Server-confirmed spendable Cuan, separately labeled unbanked worker accrual, online Cuan/s, current tier, one objective, and the next world prompt. Never combine unbanked worker preview with spendable balance. The HUD remains dimly visible when BuzzerOS is open. If profile/save is blocked, show exact blocked state and disable economic actions.

**BuzzerOS:** Interact with `OldCRT` at `TerminalSlot` through the stable `DashboardPromptAnchor` to open the client `ScreenGui`. The CRT is dashboard-only: the player **can compose and publish from BuzzerOS there**, while the server calculates post yield and reveal time from the equipped `profile.deviceId` (cheap/fast phone shown at `PhoneSlot` until PC purchase). PC Rumah replaces the CRT at `TerminalSlot` and becomes the sole productive device; the phone remains inert. The screen's compact/wide layout follows the **real viewport**, not the equipment tier: mobile users at the CRT still get a phone-safe UI, and desktop users with a cheap phone still get a readable wide UI. It is the same software, not a free productive PC or tiny `SurfaceGui`. The prompt remains on `DashboardPromptAnchor` through the PC swap. Explain “Old CRT: BuzzerOS only; posts use your equipped phone” on the first interaction, then show the PC's payout improvement at purchase. Original warm charcoal/cream, lime interactions, coral rewards, clear native sans-serif typography and distinct fictional Buzzline iconography; a Threads-like text-first feed is inspiration only, not an interface copy. Roblox documents client on-screen containers and safe insets.[6]

## Screens and release inventory
| Surface | V0 internal prototype | M1 closed-beta candidate | Action and empty state |
|---|---|---|---|
| World HUD | yes | yes | Cuan/worker rate and objective; load/save blocked messaging |
| Home | yes | yes | Next organic context, resume pending post/mission, next upgrade |
| Buzzline Feed | 6 cards + own posts | 12 cards + <=10 own posts | Visible trend/audience/clue; no real-network links |
| Create Post | 1 organic context | 3 cycling organic contexts | Three authored templates, one `PublishOrganic`, result and exact Cuan |
| Missions | 1 definition/1 context | 4 definitions/3 contexts each | Accept/resume; same post composer tagged to run; separate bonus claim |
| Upgrades | Fast phone | Fast phone + PC Rumah + desk 1/2 | Old/new yield, 15/24/37 strong Cuan example, cost, world change |
| Workers | no | 2 trainees in 2 slots | Buy desk/hire, occupancy, confirmed 1.5/3 Cuan/s, online-only |
| Analytics/profile/notifications | no | no | Excluded until distinct value exists |

V0 tests the organic payout and mission claim on one shared publish/settle path; its single context is **not** public replay depth. M1's second worker and visually furnished bedroom deliver a home-studio chapter end, not an agency UI full of unavailable tabs.

## Navigation and states
On PC use Home/Feed/Create/Missions/Upgrades/Workers with a readable central column; phone uses a compact bottom bar with at most four visible entries and a reachable More panel for remaining destinations. Do **not** hide Create behind Missions: organic posting is the base loop. Provide persistent Back and Close above safe-area bottom. Preserve tab when reopening within one session; rebuild pending/confirmed state from server snapshot after reconnect or stale reply. Desk prompt is Roblox `ProximityPrompt`; server separately validates actor and distance.[4][7]

```text
World -> OldCRT dashboard -> Home -> Feed clue -> Create in BuzzerOS (equipped phone determines yield) -> organic result (+confirmed Cuan)
Home -> Missions -> accept -> same composer tagged with run -> post result (+organic Cuan)
                                      -> claim mission (+one fixed bonus)
Home -> Upgrades -> phone/PC/desk confirmed -> close -> visible world replacement
Home -> Workers -> hire confirmed -> worker rig + Cuan/s -> second home-studio station
Esc/Close: dismiss confirm first, then close BuzzerOS and restore world controls
```

One global publish slot: while either mode resolves, Create and Mission Publish show the pending post and cannot publish again. The player can inspect Feed, Upgrades, Missions and worker stats during reveal; no forced 18-second blocking modal. If an accepted mission exists, organic publishing does not advance it, and mission tagging is explicit on the compose button. Result copy states strong/weak fit, organic Cuan, and mission progress separately. Weak campaign post offers a second post; a ready bonus offers Claim, but organic-only posts need no claim. The next organic context is visible *before* selection and advances only after a confirmed publish; reopening BuzzerOS never rerolls it. A mission brief displays the frozen run-specific trend/audience clue; successive runs can favor different templates. Do not present one template as permanently best.

| Component | Inputs | Required states |
|---|---|---|
| `HudBalance` | confirmed balance, pendingWorkerCuan, incomePerSecond | loading/ready/save-blocked; pending clearly non-spendable |
| `ObjectiveChip` | tier, purchased devices/desks, workers | next purchase/complete; direct to relevant tab |
| `FeedPostCard` | authored feed and <=10 own summaries | clue prominent, fixed replies, compact phone list |
| `OrganicComposer` | nextOrganicContextId, three templates | context/choice/pending/result, no free text |
| `MissionCard` | run context, bonus, tier | available/locked/active/claimable, separate organic result |
| `EngagementReveal` | pendingPost times and impact | server-timed 18/16/13s, reopen/leave recovery, reduced motion |
| `UpgradeCard` | server price/ownership/yield/reveal | locked/affordable/pending/owned, before/after Cuan example |
| `WorkerCard` | slot, desk, rate, balance | blocked/affordable/pending/hired; clear first/second desk gate |
| `StatusBanner` | lease/save/connection | retry/blocked, never show a guessed spendable credit |

Use `Reply` to confirm publish/purchase/claim and `Snapshot.kind="State"` for pushed authoritative state; `Snapshot.kind="OpenComputer"` alone opens UI. Server may push state no faster than every 2 seconds while active. On a 6-second mutation timeout, show “Connection uncertain. Refreshing progress”; send a **new** `GetSnapshot` request ID with `payload.lookupRequestId` set to the original mutation ID. APPLIED/REJECTED resolves; PENDING waits or joins the same in-flight reservation using the identical original ID within the same live session. UNKNOWN **never** authorizes automatic retransmit/new-ID payout, even within a session. A `GetSnapshot` reply reconciles state (and may trigger an already-due settlement) but cannot itself reopen UI. Keep confirmed wallet/HUD updated from the greatest snapshot revision even if UI is closed; do not treat an unbanked worker preview as spendable. On a failed save, block spending and posting. If a visual model fails after purchase, report a sync problem and reconcile from saved ownership; never charge a second time.

## Input, camera and accessibility
Use `ScreenGui` in `PlayerGui`, safe-area insets, flexible widths, `UITextSizeConstraint`, scroll frames, input focus order, controller/touch/keyboard paths, and a persistent touch Close control.[6][11] On server `OpenComputer`, locally store camera type/subject, movement settings and input/focus, transition toward the old CRT or purchased PC for roughly 0.25–0.4 seconds, then enable BuzzerOS. On `ComputerSessionExpired`, local expiry deadline, `SESSION_EXPIRED` reply, Close/death/respawn/character removal, immediately disable mutation buttons, close BuzzerOS and restore exactly once even if the transition was interrupted. A stale expiry for a previous session ID cannot close a newly opened session. Update the local 10-minute watchdog from matching `Reply.dashboardSession.expiresAt` and `serverTime` after a valid user action; querying state does **not** extend the server deadline. A late reply or `GetSnapshot` updates HUD/reconciliation only; player must activate the terminal prompt again to reopen. Do not disable the Roblox system menu or rely on 3D text for essential instructions.

Test 360×640 portrait, 640×360 landscape, 768×1024 tablet, 1280×720 and 1920×1080 PC emulator targets; these are design probes, not platform guarantees. Keep touch targets >=44×44 reference pixels, body text around 14–16 reference pixels, and no clipped bottom action on a notched phone. Result reason must be text, not only color/audio; reduced-motion disables count easing. Worker preview must be distinguishable from banked Cuan for low vision and on reconnect.

## UX questions and source notes
Observe without coaching: time-to-CRT prompt, whether players mistake the old CRT for a free productive PC, first organic post/credit, whether the player understands mission bonus versus organic payout, phone/PC model recognition, first/second worker motivation, close/reopen/idle expiry, and comprehension of alternating audience/trend clues. Test a slow network and one real low-end phone before any wider-release decision. If organic Create feels like a repetitive button, revise context/reward feedback rather than add a tap-to-earn shortcut.

## Sources
[4] https://create.roblox.com/docs/scripting/security/client-server-boundary
[6] https://create.roblox.com/docs/ui/on-screen-containers
[7] https://create.roblox.com/docs/ui/proximity-prompts
[11] https://create.roblox.com/docs/ui/size-modifiers
