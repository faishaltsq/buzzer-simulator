# BS-07 BuzzerOS UI Shell & World HUD

## Implementation Plan & Handoff

Base: `fc0b28fb84c71968a0bf35ea05a7c614ef38a209` (`origin/master`); branch: `agent/BS-07-ui-shell-hud`.
Milestone: **BS-07 — Premium BuzzerOS UI Shell & HUD**.

---

### 1. Source Files Created and Modified

| File | Status | Description |
|---|---|---|
| `src/client/App.client.luau` | New | Client entry script under `StarterPlayerScripts`. Owns network connections to `BuzzerRemotes`, camera transitions to `TerminalSlot`/`CameraFocus`, watchdog loop, character lifecycle, and HUD/Desktop coordination. |
| `src/client/ClientState.luau` | New | Pure client state container and reducer. Tracks dashboard status, authoritative snapshot, latest accepted revision, session ID, deadline watchdog, timeout handling, and request correlation. |
| `src/client/ui/Theme.luau` | New | Visual tokens, palette (Charcoal, Cream, Walnut, Sage, Navy, Amber, Lime, Coral), typography scale, spacing scale, corner radii, and TweenService helpers. |
| `src/client/ui/Hud.luau` | New | World HUD visible during normal bedroom gameplay. Renders confirmed spendable Cuan, unbanked worker carry, online rate, tier badge, objective pill, interaction reminder, and system status banner (loading/save-blocked/connection). Dims smoothly when BuzzerOS opens. |
| `src/client/ui/Desktop.luau` | New | Complete responsive BuzzerOS dashboard shell. Supports wide desktop layout with left navigation rail and compact mobile layout with 4-tab bottom navigation bar and accessible "More" drawer. Houses Home overview page and BS-08/BS-09/M1 informational preview placeholders. |
| `tests/Specs/ClientState.spec.luau` | New | Deterministic client state unit test suite covering 25 test cases across snapshots, OpenComputer, stale expiries, watchdog timeouts, camera lifecycle, request correlations, and mutation reconciliations. |
| `default.project.json` | Modified | Mapped `StarterPlayer.StarterPlayerScripts` to `src/client`. |
| `test.project.json` | Modified | Mapped `StarterPlayer.StarterPlayerScripts` to `src/client` so client state specs execute in the native test runner. |
| `.gitignore` | Modified | Added `__pycache__/` to ignore temporary Python bytecode. |
| `assets/ui/review/*.jpg` | New | 9 native Roblox Studio screenshots capturing desktop, mobile, states, camera framing, and world restoration. |

---

### 2. UI Architecture

BuzzerOS adheres to the **Cozy Retro Tech** visual design language:
- **No external reactive framework:** Built entirely with native Roblox GUI instances (`ScreenGui`, `Frame`, `TextLabel`, `TextButton`, `ScrollingFrame`, `CanvasGroup`, `UIPadding`, `UICorner`, `UIStroke`, `UIListLayout`, `UISizeConstraint`).
- **Separation of Concerns:**
  - `ClientState`: Pure state container with subscriptions. Zero GUI coupling.
  - `Hud`: Presentational layer for World HUD. Subscribes to `ClientState` changes and player attributes (`BuzzerReady`, `BuzzerLoadError`, `BuzzerWorldError`).
  - `Desktop`: Presentational layer for BuzzerOS window shell, navigation rail/tabs, and content pages. Responsive to viewport size changes.
  - `App.client.luau`: Composition root coordinating services, PlayerModule controls, camera transitions, and remote events.

---

### 3. Client State Machine Design

The client state machine tracks six explicit statuses:
- `Closed`: Normal world gameplay. HUD visible at full opacity; Desktop disabled.
- `Opening`: Valid server `OpenComputer` received. Camera smoothly tweens toward computer; HUD dims; Desktop prepares entrance.
- `Open`: Camera focused on CRT; Desktop shell fully interactive; user can navigate tabs.
- `Closing`: User clicked Close or pressed Escape. Camera restores to Custom; player controls re-enabled; Desktop closes.
- `Expired`: Session deadline or local watchdog elapsed. Stale generation protected; UI closes and controls restore immediately.
- `ConnectionUncertain`: A mutation reached the 6-second timeout threshold. Mutations are locked pending reconciliation query.

**State Machine Invariants:**
- `Snapshot.kind == "State"` pushes state updates without ever opening the dashboard.
- Only `Snapshot.kind == "OpenComputer"` initiates transitions to `Opening`.
- Newer generation replacement keeps camera captured without duplicate transitions or control toggles.
- Stale session expiries are rejected without affecting newer sessions.

---

### 4. Snapshot & Reply Handling Summary

- **State Ordering:** Tracked by `latestRevision`. An out-of-order older snapshot (`revision < latestRevision`) is dropped and never regresses confirmed balance.
- **Spendable vs. Pending Balance:** `state.balance` represents confirmed spendable Cuan. `state.pendingWorkerCuan` is strictly unbanked/non-spendable and never added to spendable balance.
- **Request Correlation:**
  - Every outgoing command generates an 8–64 character ASCII `requestId` (via GUID).
  - Queries (`GetSnapshot`) and mutations (`BuyDevice`, `CloseComputer`, etc.) are tracked in `inFlightRequests`.
  - Replies match on `reply.requestId`.
  - `reply.code == "SESSION_EXPIRED"` cleanly transitions the dashboard to `Expired`.
  - Matching `reply.dashboardSession` refreshes the local watchdog deadline; mismatched or stale session metadata is rejected.
  - Mutation timeouts (6 seconds) convert the in-flight mutation to `uncertainMutations` and fire a `GetSnapshot` query with `lookupRequestId`. `APPLIED`/`REJECTED` resolves the mutation; `PENDING` is preserved; `UNKNOWN` never triggers duplicate retransmissions.

---

### 5. Camera Restoration Strategy

- **On Opening:**
  1. Capture original camera state (`CameraType`, `CFrame`, `CameraSubject`, `FieldOfView`).
  2. Disable player controls via `PlayerModule:GetControls():Disable()`.
  3. Resolve player's bedroom anchors: `CameraFocus` and `TerminalSlot`.
  4. Compute target CFrame: `CFrame.lookAt(CameraFocus.Position, TerminalSlot.Position + Vector3.new(0, 1.4, 0))`.
  5. Set `CameraType = Enum.CameraType.Scriptable` and smoothly tween over 0.32 seconds (or snap if reduced motion enabled).
- **On Restoration (Close / Escape / Expiry / Death / Respawn):**
  1. Cancel active camera tween if running.
  2. Restore `CameraSubject` (safely handling humanoid respawn to avoid destroyed instances).
  3. Restore `CameraType = Custom` and `FieldOfView = 70`.
  4. Enable player controls via `controls:Enable()`.
  5. Idempotent execution: restoration executes exactly once per open cycle (`preCameraState.captured` guard).

---

### 6. Responsive Layout Implementation

The layout dynamically adjusts based on the active viewport width:
- **Wide Viewport (>= 640px):**
  - Left navigation rail (width 180px) displaying all 6 tabs with active highlights.
  - Centered header with brand, clock, and Close button.
  - Generous content margins with fixed size constraint (`MinSize: 320x340`, `MaxSize: 1100x720`).
- **Narrow Viewport (< 640px / Mobile Portrait & Landscape):**
  - Left navigation rail is hidden.
  - Content area expands to full window width with safe bottom clearance.
  - Fixed bottom navigation bar with 4 primary targets: [Home, Feed, Create, More].
  - Accessible "More" drawer slides up to present [Missions, Upgrades, Workers].
  - Touch targets maintain a minimum of 44×44 reference pixels.

---

### 7. Animation & Microinteractions

- **Window Opening:** Gentle scale (`0.85` to `0.9`) with back easing and backdrop fade over 0.28 seconds.
- **HUD Dimming:** Uses `CanvasGroup.GroupTransparency` (0 to 0.65) to subtly dim the HUD while keeping room context visible.
- **Button Feedback:** Hover background shifts, active pressed states, and crisp borders.
- **Reduced Motion Support:** Respects `GuiService.ReducedMotionEnabled` by bypassing nonessential tweens and count animations.

---

### 8. Test Execution & Verification

Native Roblox Studio Play test runner execution (`ServerScriptService.Runner`):

| Suite | Tests | Result |
|---|---:|---|
| `Bootstrap.spec.luau` | 17 | PASS |
| `ClientState.spec.luau` | 25 | PASS |
| `EconomyService.spec.luau` | 39 | PASS |
| `FeedService.spec.luau` | 18 | PASS |
| `MissionService.spec.luau` | 85 | PASS |
| `NetRouter.spec.luau` | 89 | PASS |
| `ProfileStore.spec.luau` | 59 | PASS |
| `Rules.spec.luau` | 16 | PASS |
| `SessionIntegration.spec.luau` | 45 | PASS |
| `SessionService.spec.luau` | 73 | PASS |
| `WorldService.spec.luau` | 30 | PASS |
| **Total Test Cases** | **496** | **496/496 PASS (0 FAIL)** |

Previous baseline: 471 cases.
New total: 496 cases (+25 new deterministic client state test cases).

---

### 9. Visual Quality Review & Screenshots

All 9 required screenshots were captured from real Roblox Studio Play:
1. `assets/ui/review/world-hud-bedroom.jpg` — World HUD visible inside the bedroom.
2. `assets/ui/review/desktop-home.jpg` — BuzzerOS Home screen with confirmed balance, equipped device, and operations summary.
3. `assets/ui/review/desktop-navigation.jpg` — BuzzerOS navigation rail switching tabs to Upgrades preview.
4. `assets/ui/review/mobile-portrait-home.jpg` — Compact portrait mobile layout with bottom navigation bar.
5. `assets/ui/review/mobile-landscape-nav.jpg` — Mobile landscape layout with accessible "More" drawer open.
6. `assets/ui/review/hud-loading-state.jpg` — HUD displaying "LOADING BUZZEROS..." state.
7. `assets/ui/review/hud-save-blocked.jpg` — HUD displaying "SAVE BLOCKED: ACTION PAUSED" banner in coral.
8. `assets/ui/review/camera-facing-computer.jpg` — Scriptable camera framed directly at the CRT computer at `TerminalSlot`.
9. `assets/ui/review/camera-restored-world.jpg` — Camera restored to Custom character view after closing BuzzerOS.

---

### 10. Rojo Build Verification

- `rojo build -o build/BuzzerSimulator.rbxlx`: **SUCCESS**
- `rojo build test.project.json -o build/BuzzerTests.rbxlx`: **SUCCESS**

---

### 11. Open Project Gates & Risk Assessment

- **Real DataStore G2:** Remains **OPEN / PENDING** (requires live cloud publication / isolated dev universe API keys; local Studio emits expected DataStore access notice).
- **Static Analysis Gate:** Remains **OPEN / PENDING** (Roblox-aware Selene/Luau type-check runner pending environment setup).
- **Scope Discipline:** No BS-08 posting logic, BS-09 shop purchasing, or M1 worker simulation was implemented. All future tabs are non-interactive informational placeholders.

---

### 12. Final Verdict

**VERDICT: PASS (Milestone BS-07 Complete)**
All 496 tests passing, both Rojo builds clean, complete responsive BuzzerOS shell and HUD implemented and verified in Roblox Studio with 9 captured screenshots.
