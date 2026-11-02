# 06 — UI/UX DESIGN SYSTEM & BUZZEROS SPECIFICATION

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Operating Philosophy: Fictional Retro OS

The user interface in *Buzzer Simulator* is designed as a fictional late-90s / early-2000s desktop operating system dubbed:

$$\textbf{BuzzerOS}$$

It deliberately rejects modern generic SaaS flat-design conventions, excessive glowing outlines, aggressive gradients, decorative emojis, and floating glassmorphism. Instead, it prioritizes:
- **Structural Frame Clarity**: Defined windows with distinct title bars, 1px border strokes, and organized content panes.
- **Economic Transparency**: Confirmed spendable Cuan is always visibly separated from unbanked worker previews. Payout breakdowns (organic vs. campaign bonus) are explicitly itemized.
- **Tactile Feedback**: Distinct interactive states (Hover, Press, In-Flight, Confirmed) with snappy easing (0.2–0.3s) and clear audio-visual reinforcement.

---

## 2. Design System Tokens (Implementation: `Theme.luau`)

### 2.1. Color Tokens
All UI colors must reference `Theme.Colors`:

```
+---------------------------------------------------------------------------------------+
|                                  THEME COLOR TOKENS                                   |
+-------------------+---------------+---------------------------------------------------+
| Token             | Value         | Primary Application                               |
+-------------------+---------------+---------------------------------------------------+
| `Charcoal`        | `#30343C`     | Primary window background, desktop workspace      |
| `CharcoalDark`    | `#24272E`     | Side navigation rail, modal backing, deep panels  |
| `CharcoalLight`   | `#3C424C`     | Metric boxes, post cards, content containers      |
| `Border`          | `#4E5662`     | Standard 1px card outlines, divider lines         |
| `BorderLight`     | `#697382`     | Hover outlines, active tab borders                |
| `Cream`           | `#F2E5D5`     | Primary headers, main labels, button text         |
| `CreamMuted`      | `#C8BEB2`     | Secondary descriptions, inactive tabs, timestamps |
| `Walnut`          | `#785843`     | Furniture-related accent banners                  |
| `Sage`            | `#A8B69C`     | Soft brand highlights, tag containers             |
| `Navy`            | `#34465A`     | BuzzerOS title bars, campaign headers             |
| `Amber`           | `#F2BC79`     | Equipped status tags, highlight cards, tier badge |
| `Lime`            | `#8CB369`     | Active publish CTA, confirmed Cuan, online rate   |
| `Coral`           | `#D97D64`     | Save blocked warnings, error alerts, weak fit     |
| `MutedGold`       | `#D4A85C`     | Secondary currency metrics, bonus claims          |
| `Disabled`        | `#5A606A`     | Inactive button backgrounds                       |
| `DisabledText`    | `#828892`     | Inactive button text labels                       |
+-------------------+---------------+---------------------------------------------------+
```

### 2.2. Typography & Text Hierarchy
Fonts are standardized on the Roblox Gotham font family (`Theme.Fonts`):
- `Regular` (`Enum.Font.Gotham`)
- `Medium` (`Enum.Font.GothamMedium`)
- `Bold` (`Enum.Font.GothamBold`)
- `Black` (`Enum.Font.GothamBlack`)

Scale hierarchy (`Theme.TextSizes`):
- **Display** (32px): Large balance amounts, hero metric figures.
- **Header** (26px): Screen titles, major modal headers.
- **Title** (22px): Card headings, section titles.
- **Subtitle** (18px): Tab labels, subheadings, prompt headers.
- **Body** (15px): Standard descriptions, post content, button labels.
- **Small** (13px): Metadata tags, timestamps, secondary clues.
- **Tiny** (11px): System disclaimers, micro status labels.

### 2.3. Spacing, Corner Radii & Elevation
- **Spacing Units** (`Theme.Spacing`):
  - `XS`: 4px | `SM`: 8px | `MD`: 12px | `LG`: 16px | `XL`: 24px | `XXL`: 32px
- **Corner Radii** (`Theme.Radii`):
  - `Small` (4px): Buttons, chips, small tags.
  - `Medium` (8px): Content cards, post containers, metric boxes.
  - `Large` (12px): Primary application window, modal shells.
  - `Pill` (Full 50% radius): Status badges, objective chips.
- **Borders & Elevation**:
  - Surface elevation is conveyed through color shifting (`CharcoalDark` $\rightarrow$ `Charcoal` $\rightarrow$ `CharcoalLight`) paired with a crisp 1px stroke (`Theme.Colors.Border`). Heavy dropshadows are forbidden.

---

## 3. Surface Specifications: World HUD & BuzzerOS

### 3.1. World HUD (`src/client/ui/Hud.luau`)
Always rendered in screen space during exploration; softly dims (`GroupTransparency = 0.5`) when BuzzerOS opens.

```
+-----------------------------------------------------------------------------------+
| [TOP LEFT: FINANCIAL CLUSTER]                               [TOP RIGHT: OBJECTIVE]|
| +-----------------------------------------------+   +---------------------------+ |
| | CUAN: 110 (Confirmed)  | PENDING: +0 (Worker) |   | TIER 0: HOME BUZZER       | |
| | ONLINE: +0.0 Cuan/s    |                      |   | Next: Upgrade to PhoneFast| |
| +-----------------------------------------------+   +---------------------------+ |
|                                                                                   |
|                                                                                   |
|                                                                                   |
| [BOTTOM CENTER: SYSTEM STATUS BANNER] (Conditional)                               |
| +-------------------------------------------------------------------------------+ |
| | [!] Save Blocked: Network disconnected. Economic actions suspended.           | |
| +-------------------------------------------------------------------------------+ |
|                                                    [BOTTOM RIGHT: EQUIP CONTROL]  |
|                                                    +----------------------------+ |
|                                                    | [PHONE ICON] Equip Phone   | |
|                                                    +----------------------------+ |
+-----------------------------------------------------------------------------------+
```

- **Wallet Box**: Renders confirmed balance in bold Cream, online rate in Lime. Unbanked worker income is separately tagged to prevent false spending assumptions.
- **Objective Chip**: Directs players toward the immediate gameplay milestone (e.g., `"Save 50 Cuan for PhoneFast"`).
- **Status Banners**:
  - *Save Blocked*: Coral banner warning that data cannot be saved; disables purchase/publish buttons.
  - *Loading Profile*: Amber banner during initial profile fetch on join.
  - *Connection Uncertain*: Reconnect warning during DataStore recovery.
- **Touch Target Minimum**: Equip phone button enforces $44 \times 44$ reference pixels minimum.

### 3.2. BuzzerOS Window & Navigation Shell (`src/client/ui/Desktop.luau`)
Opens via `ProximityPrompt` at `DashboardPromptAnchor`.

#### Responsive Layout Modes:
1. **Desktop Wide Mode ($\ge 640\text{px}$ width and $\ge 500\text{px}$ height)**:
   - Fixed left-hand vertical navigation rail ($180\text{px}$ width) in `CharcoalDark` (`navRail.Size = UDim2.new(0, 180, 1, 0)`).
   - Central content viewport in `Charcoal` (`contentArea.Size = UDim2.new(1, -180, 1, 0)`, `Position = UDim2.new(0, 180, 0, 0)`).
   - Header bar contains top-right persistent $72 \times 44\text{px}$ Close button (`CloseButton`) labeled "Close" in `CharcoalLight` with Cream text, meeting the $\ge 44\text{px}$ touch target height standard (`closeBtn.Size = UDim2.new(0, 72, 0, 44)`).
   - Navigation rail displays all 6 primary system tabs: `Home`, `Feed`, `Create`, `Missions`, `Upgrades`, `Workers`.
2. **Mobile Compact Mode ($< 640\text{px}$ width or $< 500\text{px}$ height)**:
   - Compact layout active on narrow portrait mobile viewports ($< 640\text{px}$) and short landscape mobile screens ($< 500\text{px}$).
   - Left navigation rail hidden; content area expands to full window width (`UDim2.new(1, 0, 1, -56)`).
   - Header bar retains the $72 \times 44\text{px}$ Close button for immediate dismissal.
   - Bottom horizontal navigation bar (`_mobileNav`, height 56px) provides 4 primary touch targets:
     - `Home` (`MobileNav_Home`)
     - `Feed` (`MobileNav_Feed`)
     - `Create` (`MobileNav_Create`)
     - `More` (`MobileNav_More`)
   - The `More` tab toggles a dedicated drawer menu (`_moreMenu`) containing the secondary destinations:
     - `Missions`
     - `Upgrades`
     - `Workers`
     Selecting any destination in the `More` drawer switches to that tab and closes the drawer.

---

## 4. Screen-by-Screen Functional Specifications

### 4.1. Home Tab (`Overview`)
- **Metric Summary Box**: 3 horizontal cards displaying Confirmed Cuan, Total Posts Published, and Completed Campaigns.
- **Equipped Hardware Card**: Shows active device (Cheap Phone / Fast Phone), current yield multiplier, reveal speed, and an "Upgrade in Shop" quick-link.
- **Active Operations Card**: Shows real-time status of pending posts or accepted missions with progress bars.

### 4.2. Buzzline Feed Tab (`Feed.luau`)
- **Fictional Social Stream**: Displays 6 to 12 authored community posts with topic clues (Food, Tech, Memes, Politics).
- **Campaign Hints**: Highlighted feed cards display audience preferences that hint at high-scoring template choices for organic posts.
- **Own Posts History**: A scrollable history showing the player's last 10 published posts with confirmed payout badges and impact ratings.

### 4.3. Create Post Tab (`PostComposer.luau`)
- **Organic Context Box**: Displays the current trending scenario (e.g. `"Viral Street Food Stall"`).
- **Template Selection**: 3 selectable authored templates (e.g. Meme, Review, Controversy). Clicking selects the card with an Amber border stroke.
- **Publish Action Button**: Large, prominent Lime button (`"Publish Organic Post"`). When pressed, enters an in-flight pending state.
- **Countdown & Result Flow**: Displays real-time server-synced countdown (18s / 16s). On settlement, transitions to a result summary showing Strong/Weak fit and exact credited Cuan.

### 4.4. Missions Tab (`Missions.luau`)
- **Available Campaigns**: List of commercial sponsor contracts.
- **Active Mission Card**: Displays campaign requirements (e.g. Target Impact: 100), bonus payout (e.g. 80 Cuan), and an "Open Composer" button.
- **Claim Bonus Button**: Flashes Amber/Lime when campaign reaches target impact. Clicking confirms the bonus payout once and advances completed campaign count.

### 4.5. Upgrades Shop Tab (`Upgrades.luau`)
- **Hardware Comparison Grid**: Side-by-side spec comparison between current hardware and the next available catalog device.
- **States A through F**:
  - *State A (Locked)*: Player lacks prerequisites.
  - *State B (Affordable)*: Confirmed balance $\ge$ price. Button is Lime: `"Upgrade to Fast Phone · 50 Cuan"`.
  - *State C (Purchasing)*: Clicked; spinner active; clicks disabled.
  - *State D (Confirmed)*: Server acknowledged purchase.
  - *State E (Equipped/Owned)*: Hardware currently in use. Tagged with Amber `"OWNED · EQUIPPED"`.
  - *State F (Save Unavailable)*: Coral warning; purchase disabled due to DataStore lease lock.

---

## 5. Interaction State Machine & Timing Rules

Every interactive UI element conforms to a standard 5-state lifecycle:

```
+-----------------------------------------------------------------------------------+
|                             INTERACTION STATE MACHINE                             |
+-------------------+-----------------------+-------------------+-------------------+
| State             | Visual Treatment      | Stroke Outline    | Motion Duration   |
+-------------------+-----------------------+-------------------+-------------------+
| **Idle**          | Surface color default | `Border` (1px)    | Steady baseline   |
| **Hover**         | +10% lightness        | `BorderLight`(1px)| 0.15s Quad Out    |
| **Pressed**       | -10% darkness, scale  | `BorderLight`(2px)| 0.08s Quad In     |
|                   | down to 0.98          |                   |                   |
| **In-Flight**     | `Disabled` fill with  | `Border` (1px)    | Continuous spin   |
|                   | pulsating spinner     |                   |                   |
| **Confirmed**     | Brief `Lime` flash    | `Lime` (2px)      | 0.35s bounce      |
|                   | then steady state     |                   |                   |
+-------------------+-----------------------+-------------------+-------------------+
```

### Motion & Easing Guidelines:
- **Window Open**: Fade in from `BackgroundTransparency = 1` to `0.45` on backdrop; scale window from `0.95` to `1.0` in $0.25\text{s}$ (Quad Out).
- **Window Close**: Scale window to `0.95` and fade out in $0.18\text{s}$ (Quad In).
- **Reduced Motion**: When `GuiService.ReducedMotionEnabled` is true, all scale tweens are disabled; transitions perform instant binary visibility toggling.
