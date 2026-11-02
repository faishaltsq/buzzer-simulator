# ASSETS/UI — UI ASSET & VISUAL EVIDENCE CONVENTIONS

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../../docs/DESIGN.md)

---

## 1. Directory Purpose & Structure

The `assets/ui/` directory archives authoritative visual review evidence, screenshots, and UI layout captures recorded during milestone gates.

The directory is structured into chronological milestone review folders:

```
assets/ui/
├── review/          # BS-07 UI shell, World HUD, and desktop navigation evidence
├── bs08-review/     # BS-08 organic post composer, missions, and feed evidence
└── bs09-review/     # BS-09 fast phone upgrade shop and handheld equip evidence
```

---

## 2. Review Image Catalog & Evidence Index

### 2.1. BS-07 UI Shell & World HUD Evidence (`assets/ui/review/`)
| Filename | Resolution | Description |
|---|---|---|
| `world-hud-bedroom.jpg` | 1280×720 | World HUD in exploration mode: Cuan balance, tier chip, and clean room view. |
| `desktop-home.jpg` | 1280×720 | BuzzerOS Home screen: 3 metric boxes, equipped hardware card, and operations card. |
| `desktop-navigation.jpg` | 1280×720 | Desktop vertical navigation rail with active tab indicator and hovered state. |
| `hud-loading-state.jpg` | 1280×720 | HUD loading profile banner during initial player join and data fetch. |
| `hud-save-blocked.jpg` | 1280×720 | HUD save blocked alert banner (Coral) when DataStore lease is unavailable. |
| `mobile-portrait-home.jpg` | 390×844 | Mobile portrait layout on iPhone 14: bottom navigation bar and responsive cards. |
| `mobile-landscape-nav.jpg` | 844×390 | Mobile landscape layout with compact navigation and preserved safe-area margins. |
| `camera-facing-computer.jpg`| 1280×720 | Camera transition pose facing OldCRT monitor when opening BuzzerOS. |
| `camera-restored-world.jpg` | 1280×720 | Camera restored to third-person gameplay view following BuzzerOS closure. |

### 2.2. BS-08 Organic Composer & Missions Evidence (`assets/ui/bs08-review/`)
| Filename | Resolution | Description |
|---|---|---|
| `buzzline-feed-desktop.jpg` | 1280×720 | Buzzline Feed tab: authored trend clue cards and player's own post history. |
| `organic-composer-desktop.jpg`| 1280×720 | Create Post tab: active scenario context, 3 selectable templates, and publish button. |
| `three-selectable-templates.jpg`| 1280×720 | Template selection state with Amber focus stroke and impact score preview. |
| `post-resolving-countdown.jpg`| 1280×720 | Live server-synced 18s reveal countdown banner with active progress bar. |
| `confirmed-organic-payout.jpg`| 1280×720 | Payout settlement summary card: Strong fit acknowledged; +15 Cuan credited. |
| `missions-available.jpg` | 1280×720 | Missions tab: sponsor campaign contract list and payout requirements. |
| `accepted-campaign.jpg` | 1280×720 | Accepted mission state with campaign-tagged composer button. |
| `mission-resolving-post.jpg` | 1280×720 | Campaign post resolving countdown with target impact meter. |
| `weak-mission-progress.jpg` | 1280×720 | Weak post result feedback: partial impact score credited; second post allowed. |
| `ready-to-claim-mission.jpg`| 1280×720 | Campaign target reached: "Claim Bonus" CTA active with flashing Amber highlight. |
| `claimed-bonus.jpg` | 1280×720 | Confirmed bonus claim: +80 Cuan credited to wallet; campaign marked complete. |
| `world-hud-confirmed-income.jpg`| 1280×720 | World HUD reflecting 110 confirmed Cuan balance after campaign completion. |
| `mobile-portrait-composer.jpg`| 390×844 | Mobile portrait composer layout with stacked templates and large touch CTA. |
| `mobile-landscape-composer.jpg`| 844×390 | Mobile landscape composer with horizontal template arrangement. |

### 2.3. BS-09 Fast Phone Shop & Handheld Evidence (`assets/ui/bs09-review/`)
| Filename | Resolution | Description |
|---|---|---|
| `shop-affordable.jpg` | 1280×720 | Upgrades tab in State B (Affordable): Fast Phone available for 50 Cuan. |
| `purchase-confirmed.jpg` | 1280×720 | Upgrades tab in State E (Equipped): Fast Phone confirmed owned; balance 60 Cuan. |
| `cheap-phone-hand.jpg` | 1280×720 | Third-person avatar view holding procedural Cheap Phone in bedroom. |
| `fast-phone-hand.jpg` | 1280×720 | Third-person avatar view holding procedural Fast Phone with lit OLED panel. |
| `phone-after-crt-close.jpg`| 1280×720 | Seamless restoration of handheld holding pose after closing BuzzerOS. |
| `phone-after-respawn.jpg` | 1280×720 | Character respawn lifecycle: starts stowed, then equips cleanly with zero leaks. |
| `mobile-equip-controls.jpg`| 390×844 | Mobile portrait view with native touch controls and contextual equip button. |

---

## 3. Image Capture & Evidence Standards

To ensure evidence remains authentic and auditable:
1. **Real Engine Play Captures Only**: Screenshots must be captured during live Roblox Studio Play mode sessions. Pre-rendered concept art or mockups are strictly prohibited in review folders.
2. **Foreground Focus Verification (Rule 22)**: On Windows, Roblox Studio must be active in the foreground (`ShowWindow(hwnd, SW_RESTORE)` + `SetForegroundWindow(hwnd)`) during capture to prevent black-frame DirectX suspension artifacts.
3. **No Retained Overrides (Rule 26)**: Any temporary camera scripts, lighting tweaks, or debug guides used during screenshot capture must be reverted before committing code.
4. **Resolution Standards**:
   - **Desktop Wide**: Exactly $1280 \times 720$ pixels.
   - **Mobile Portrait**: Exactly $390 \times 844$ pixels (iPhone 14 standard).
   - **Mobile Landscape**: Exactly $844 \times 390$ pixels.
