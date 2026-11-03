# 06 — UI/UX Integration

> **Covers**: §J UI/UX Integration.
> **Status**: Planning. Existing HUD/BuzzerOS contracts are unchanged unless a
> milestone explicitly says otherwise.

---

## 1. Core rule: the HUD does not grow a second brain

M1's HUD is deliberately small: **Cuan balance, unbanked worker accrual, Cuan/s,
tier, one objective, one next prompt.** M2 must not turn it into a map, a quest
log, and a shop directory.

Therefore:

| Surface | M2-A | M2-B | M2-C |
|---|---|---|---|
| World HUD | unchanged | + zone label + return-home chip | + event timer chip |
| BuzzerOS | unchanged | + cosmetic panel entry | + cosmetics try-on |
| New full-screen UI | **none** | utility panel only | city map panel |
| Minimap | **none** | **none** | optional, only if measured necessary |
| 3D floating text | forbidden | forbidden | forbidden |

---

## 2. Minimap decision

**No minimap in M2-A or M2-B.**

Reasons:

1. The city is 224 × 198 studs — smaller than one Roblox minimap circle would
   usefully depict.
2. Every zone is visible from the town center, and the door is always behind
   the player on exit.
3. A minimap costs a full client surface (render target, safe-area layout,
   mobile occlusion) for a problem signposts already solve.
4. It competes with the existing HUD for thumb space on mobile.

**Replacement: the free map card.** Warung Serba Ada gives a static, authored
map card (a `SurfaceGui`/panel image composed of Parts or a UI frame) that
shows the four zones and the door. It is diegetic, cheap, and optional.

**Revisit only if:** uncoached playtests show players repeatedly failing to
find the boards or the door after 3+ sessions. Then add a compass strip, not a
minimap.

---

## 3. Zone labels

M2-B adds a **zone label** to the HUD (small, top-center, under the objective
chip):

| Zone | Label | Sub-label (optional) |
|---|---|---|
| Z0 | `Rumah` | — |
| Z1 | `Gang Melati` | — |
| Z2 | `Alun-Alun` | `Papan misi` |
| Z3 | `Toko Listrik` | — |
| Z4 | `Rumah Rapi` | — |
| Z5 | `Lapangan` | event name when active |
| Z7 | `Distrik Berikutnya` | `Segera` |

Behavior:

- Fade in over 0.25 s on zone entry; fade out after 4 s.
- Never blocks the center of the screen.
- Purely local (client), derived from the player's position vs. zone bounds;
  no server traffic.
- Suppressed while BuzzerOS is open (existing dimmed-HUD rule).

---

## 4. Shop prompts

One `ProximityPrompt` per shop, parented to the shop anchor, server-created.

| Shop | ActionText | ObjectText | Opens |
|---|---|---|---|
| ElectroMart | `Lihat barang` | `Toko Listrik Pak Bud` | existing `Upgrades` tab |
| Rumah Rapi | `Lihat dekorasi` | `Rumah Rapi` | cosmetic panel (M2-B) |
| Gaya Depan | `Coba pakaian` | `Gaya Depan` | try-on panel (M2-C) |
| Warung | `Buka peta` | `Warung Serba Ada` | utility panel |
| Boards | `Baca papan` | `Papan Misi` | mission list / daily brief |
| Future Gate | `Lihat distrik` | `Distrik Berikutnya` | locked copy only |
| Home door | `Masuk Rumah` | — | teleport indoors |
| Interior door | `Keluar Rumah` | — | teleport outdoors |

Rules:

- Activation distance 10 studs; server validates ≤ 12 (existing constants).
- `HoldDuration = 0`, `RequiresLineOfSight = false` (matches the dashboard
  prompt; the anchors sit in open space).
- **One prompt visible at a time** on mobile: if two prompts overlap, the
  nearest wins (Roblox default behavior; verify no stacked prompts at the
  board/fountain cluster).
- Prompt copy is authored, no client-generated strings.
- Locked prompts still exist but show the honest lock reason on activation
  (`CustomPrompt` copy), never a disabled silent prompt.

---

## 5. Mission hotspot prompts

The boards are the only mission hotspot in MVP.

```text
Player at Z6 → prompt "Baca papan"
             → mission list (existing Missions surface)
             → accept brief
             → HUD objective updates: "Publish the Neon Market brief at home"
             → return-home chip appears
```

- The board **does not** let the player publish. Accepting is the whole
  interaction.
- If a mission is already active, the board shows "Resume" rather than a second
  accept.
- If the daily brief is claimable, the board shows a small amber dot — text
  fallback in the panel, not color alone.

---

## 6. Event reminders

| Trigger | Surface | Copy |
|---|---|---|
| Event scheduled within 30 min | `ObjectiveChip` secondary line | `Lapangan buka 19:00` |
| Event active | chip turns amber, one line | `Event lapangan aktif` |
| Event ends in 5 min | one-time banner | `Event berakhir 5 menit lagi` |
| Daily reset | board only | `Brief baru besok` |

Rules:

- No push notifications, no pop-up modals, no sound stingers that block input.
- Reminders are **informational**; the player can ignore them forever.
- The chip never shows two competing calls to action; the objective always
  wins, the event is secondary text.
- All times use the server clock, displayed in the player's local time zone
  label if available, otherwise server time.

---

## 7. Return-home affordance

The city must never trap the player.

| Layer | Affordance |
|---|---|
| Always | The door prompt at `City_HomeDoor` |
| Always | The street points home (visible facade + house number) |
| M2-B | A HUD chip `Kembali ke rumah` appears when the objective is indoor-only and the player is outdoors |
| M2-B | Warung utility panel has a `Pulang` shortcut (teleport with the same fade) |
| Failure | If the door prompt fails, the Warung shortcut still works; if both fail, respawn (existing death path) returns the player indoors |

The return chip is **not** a free teleport from anywhere; it is a hint that
expands into a button only when the player is outdoors and the next required
action is indoors. This keeps the walk meaningful.

---

## 8. Visual hierarchy on mobile

```text
┌─────────────────────────────────────┐
│  [Cuan]            [Tier]           │  existing balance card
│  [Objective chip]                   │
│  Gang Melati                        │  zone label (M2-B, fades)
│                                     │
│                                     │
│           3D WORLD                  │
│                                     │
│                                     │
│  [prompt]                           │  Roblox ProximityPrompt
│  [Kembali ke rumah]                 │  return chip (M2-B)
│  [BuzzerOS bottom bar]              │  existing, only when open
└─────────────────────────────────────┘
```

- Zone label never overlaps the objective chip (stacked, 8 px gap).
- Return chip sits above the safe-area inset, not under the thumb.
- No new persistent buttons in the bottom bar in M2-A/B.

---

## 9. Accessibility

- Zone labels and prompts are text, not color-only.
- Event active state uses text + amber, not amber alone.
- Prompt copy uses plain language, no slang that requires cultural knowledge.
- All new touch targets ≥ 44×44 reference pixels.
- Reduced-motion setting disables the door fade (instant cut) and label fades.
- Screen-reader order: objective → balance → zone → prompt.
- Contrast: reuse existing verified tokens (`Cream` on `Charcoal`, `Amber` on
  `Navy`).

---

## 10. What M2 explicitly does not add

- No city tab in the BuzzerOS bottom bar.
- No second currency display.
- No quest log.
- No floating waypoint markers.
- No "?" NPC dialogue trees.
- No notification center.
- No minimap in MVP.
- No full-screen city map in M2-A/B.
