# Project Gap Report: M1/M2 Milestone Status & Roadmap to Production
**Document Version**: 1.0.0  
**Date**: 2026-11-07  
**Branch**: `agent/M2-full-integrated-review`  
**Deliverable Audited**: `build/review/BuzzerSimulator_FULL_REVIEW.rbxlx`

---

## 1. Scope & Objective

This report provides an engineering and design audit of the Buzzer Simulator codebase following the successful assembly of the **Full Integrated Review Place** (`build/review/BuzzerSimulator_FULL_REVIEW.rbxlx`). It catalogues what has been verified as production-ready, identifies architectural and content gaps between the current review build and full production release, and defines the roadmap for subsequent milestones (M2-B, M2-C, and M3).

---

## 2. Milestone Achievement Status

### M1: Bedroom Incremental Core (VERIFIED COMPLETE)
- **BuzzerOS Desktop & Window System**: Fully functional, tab-switched OS dashboard with Feed, Missions, Upgrades/Shop, Workers, and Analytics.
- **Feed & Organic Posting**: Countdown timer, character typing, organic viral mechanics, and payout settlements.
- **Hardware Tiers**: Cheap Phone (`phone_cheap`), Fast Phone (`phone_fast`), and Home PC (`pc_rumah`).
- **Worker Management**: Desks 1 & 2 unlockable; Trainees hireable and productive upon acquiring `pc_rumah`.
- **In-Memory & Production State Logic**: Strict domain invariants, session lease management, monotonic time checks, rate-limiting, and error-handling.
- **Regression Integrity**: 20 test suites, 748 runtime tests, ~3,147 assertions passing at 100%.

### M2-A: Gang Melati City Blockout (VERIFIED COMPLETE)
- **Prefab Architecture**: 9 modular `.rbxmx` prefabs across 6 contiguous zones:
  - `HouseExterior` (Z=0)
  - `StreetBlock` (Z=40)
  - `TownCenter` (Z=112)
  - `CityBoards` (Z=68)
  - `CityGate` (Z=168)
  - `CityBackdrop` (Z=-152, baseline X=88 and centered X=0 variants)
- **Part Budgets**: 289 city BaseParts, 7 PointLights, 100% anchored, zero unanchored parts.
- **Performance**: Stable 60 FPS in Studio Play Solo; total Workspace parts at 617 (budget: 1,000).

---

## 3. Identified Gaps & Production Cutover Requirements

```
+-----------------------------------------------------------------------------------+
|                            Current Review State                                   |
|  [ Bedroom (M1) ] <===> [ ReviewTravelService ] <===> [ Gang Melati Blockout ]    |
|  - In-Memory Profile                                   - 289 BaseParts            |
|  - Local Player Only                                   - Physical geometry only   |
+-----------------------------------------------------------------------------------+
                                       |
                                       v
+-----------------------------------------------------------------------------------+
|                            Required Production State                              |
|  [ Multi-Player Hub ] <===> [ City WorldService ] <===> [ Living Gang Melati ]    |
|  - Cloud ProfileStore                                 - Interactive NPCs          |
|  - Per-Player Apartment Units                         - Street Side-Gigs          |
|  - Spatial Streaming                                  - Kopi / Warung Buffs       |
+-----------------------------------------------------------------------------------+
```

### Gap 1: Interactive City Gameplay & Content (M2-B)
- **Observation**: In the review place, `CityBoards.BoardCork` displays a notification via `City_Prompt_Boards`, but there are no interactive NPCs, coffee shop (Warung Kopi) orders, or street side-gigs.
- **Impact**: The city currently serves as a visual walkthrough and traversal space rather than an active gameplay layer.
- **Required Work**:
  1. **Warung Kopi / Food Stall Interactions**: Add consumable buffs (e.g. coffee for 10% faster typing speed for 5 minutes).
  2. **Street NPCs & Dialogue**: Add pedestrian characters (Pak RT, street vendors, ojek drivers) with dialogue and local gossip that reveal trending social media topics.
  3. **Outdoor Proximity Missions**: Physical tasks in the alley (e.g. photographing street posters for political campaign briefs).

### Gap 2: Multi-Player Room Architecture & Spatial Distribution (M2-B / M2-C)
- **Observation**: The current `WorldService` creates `BuzzerRoom_<UserId>` at origin `(0, 0, 0)`. In a multi-player production server (e.g. 8-16 players), placing all bedrooms at origin would cause overlap unless placed in distinct world coordinates or virtual dimensions.
- **Impact**: Multi-player server collisions or visual bleed-through.
- **Required Work**:
  1. **Apartment Stacking / Grid Offset**: Implement room instance offset algorithm:
     $$P_i = (\Delta x \cdot i, 0, \Delta z \cdot i)$$
     or stack bedrooms into the `HouseExterior` / `Kos-Kosan` second-floor geometry.
  2. **Door Association**: Pair each player's door prompt with their assigned room coordinate.

### Gap 3: DataStore Production Cutover & Cloud Persistence (G2 Milestone)
- **Observation**: `ReviewBootstrap` purposefully overrides DataStoreService with `createInMemoryStoreAdapter()` to satisfy the zero-cloud-DataStore constraint during development and review.
- **Impact**: Progress resets when the session ends; production deployment requires persistent cloud saving.
- **Required Work**:
  1. Verify live Roblox universe configuration (`API Access` enabled in Game Settings).
  2. Connect `default.project.json` to the production universe with ProfileService session locking.
  3. Conduct live cloud persistence smoke testing under G2 criteria.

### Gap 4: Audio & Environmental Polish (M2-C)
- **Observation**: The review place has silent audio and default Studio atmospheric lighting.
- **Impact**: Gang Melati feels visually accurate but lacks the immersive ambient acoustic identity of an Indonesian residential alley (kampung/gang).
- **Required Work**:
  1. **Soundscape**: Add looping ambient sounds (distant motorcycle exhausts, crickets, adzan/mosque call at dusk, birds).
  2. **Lighting Atmosphere**: Add `Atmosphere`, `ColorCorrectionEffect`, and configure `Lighting.Technology = Enum.Technology.Future` with Indonesian golden-hour / warm night palette.

### Gap 5: Mobile HUD & Interaction Controls (M2-B)
- **Observation**: The mobile simulator audit demonstrated clean viewport scaling (360×640 portrait and 640×360 landscape), but door interactions currently rely on default Roblox `ProximityPrompt` circles.
- **Impact**: Proximity prompts can sometimes be small or difficult to tap reliably on small touchscreens.
- **Required Work**:
  1. Add optional on-screen mobile action button when within prompt radius.
  2. Verify touch tap targets exceed minimum $44 \times 44$ pt accessibility standards.

---

## 4. Gating Criteria for Next Milestones

| Milestone | Target Feature Set | Gating Requirement |
| :--- | :--- | :--- |
| **M2-A (Current)** | Static City Blockout & Studio Review Place | **PASSED**: 289 parts, 7 lights, 20/20 test suites, review place delivered. |
| **M2-B** | Interactive Street Gameplay & NPCs | 3 interactive city NPCs, Warung Kopi buff system, multi-player room offsetting. |
| **M2-C** | Living Environment & Audio Polish | Ambient soundscape, Future lighting profile, day/night cycle integration. |
| **G2** | Staging / Cloud Universe Deployment | Live DataStoreService integration, cloud profile migration test, multi-client smoke test. |

---

## 5. Conclusion

The **Full Integrated Review Place** successfully bridges the gap between M1 core code and M2 physical environment. The architecture is clean, highly modular, strictly isolated from production configs, and ready for director sign-off.
