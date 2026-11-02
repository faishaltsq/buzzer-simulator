# 02 — COLOR PALETTE & MATERIAL SYSTEM

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Palette Architecture & Hierarchy

The visual system uses a unified, cross-domain palette spanning UI styling (`src/client/ui/Theme.luau`), procedural handheld equipment (`src/client/PhoneEquipController.luau`), and 3D world prefabs (`tools/gen_world_prefabs.py`).

Colors are never introduced ad-hoc. Every color token has a designated semantic purpose, surface application, and contrast validation.

---

## 2. Master Color Tokens (Implementation Source: `Theme.luau`)

| Token Name | Hex Code | RGB Values | Semantic Role & Surface Application |
|---|---|---|---|
| `Charcoal` | `#30343C` | `48, 52, 60` | Main window backgrounds, BuzzerOS desktop frame, primary card surfaces |
| `CharcoalDark` | `#24272E` | `36, 39, 46` | Deep background, navigation rail background, modal container backdrop |
| `CharcoalLight` | `#3C424C` | `60, 66, 76` | Elevated cards, metric preview containers, input fields, active selections |
| `Border` | `#4E5662` | `78, 86, 98` | Structural dividing lines, card strokes (1px), subtle separators |
| `BorderLight` | `#697382` | `105, 115, 130` | Hover states, focused card outlines, tab indicators |
| `Cream` | `#F2E5D5` | `242, 229, 213` | Primary text, modal headings, light furniture trim, button label text |
| `CreamMuted` | `#C8BEB2` | `200, 190, 178` | Secondary text, card subtitles, inactive tabs, placeholder labels |
| `Walnut` | `#785843` | `120, 88, 67` | Warm timber furniture accent, retro phone body accent |
| `Sage` | `#A8B69C` | `168, 182, 156` | Soft brand accent, monochrome retro phone screens, curtain fabric |
| `Navy` | `#34465A` | `52, 70, 90` | Window title bars, header banners, dark geometric rug foundation |
| `Amber` | `#F2BC79` | `242, 188, 121` | Primary brand accent, task lamp light pool, gold hardware, equipped tags |
| `Lime` | `#8CB369` | `140, 179, 105` | Active economic triggers, positive confirmation, online income rate (Cuan/s) |
| `Coral` | `#D97D64` | `217, 125, 100` | Warning banners, save blocked notices, deletion prompts, debt |
| `MutedGold` | `#D4A85C` | `212, 168, 92` | Secondary financial indicator, milestone achievements |
| `Disabled` | `#5A606A` | `90, 96, 106` | Inactive button fills, unaffordable purchase containers |
| `DisabledText` | `#828892` | `130, 136, 146` | Inactive button text, locked tier descriptions |

---

## 3. World 3D Prefab Palette (`tools/gen_world_prefabs.py`)

World geometry is generated deterministically from an aligned set of earthy tone definitions:

| 3D Token | RGB Values | Hex Equivalent | Usage in 3D Models |
|---|---|---|---|
| `cream` | `233, 222, 199` | `#E9DEC7` | Window mullions, door jambs, CRT monitor shell, ceramic mug |
| `plaster` | `219, 211, 190` | `#DBD3BE` | Bedroom perimeter walls, CRT neck and keyboard base |
| `wood` | `153, 112, 75` | `#99704B` | Desk apron, bed frame, bookcase frame, door panel |
| `wood_light` | `180, 139, 96` | `#B48B60` | Desk upper surface, bedside tabletop, bookshelf shelves, cheap phone body |
| `wood_dark` | `101, 74, 55` | `#654A37` | Bedroom floorboards, desk legs, headboard, drawer carcass, poster frame |
| `sage` | `132, 151, 126` | `#84977E` | Bedroom door face, curtains, blanket drape, CRT on-screen rules |
| `sage_dark` | `80, 108, 86` | `#506C56` | Door insets, blanket fold, plant leaves, lamp base |
| `navy` | `52, 68, 81` | `#344451` | Woven rug body, bedside book cover, fast phone chassis, notebook cover |
| `ink` | `32, 42, 45` | `#202A2D` | Desk cables, pendant lamp cord, CRT screen recess, phone bezel |
| `amber` | `236, 186, 111` | `#ECBA6F` | Door handle, drawer pulls, poster sun, desk lamp light tint |
| `linen` | `246, 236, 216` | `#F6ECD8` | Bed mattress, pillows, CRT keycaps, poster canvas |
| `metal` | `110, 119, 115` | `#6E7773` | Desk lamp stem, fast phone volume rocker, CRT bezel trim |
| `glass` | `150, 178, 177` | `#96B2B1` | Window pane (35% transparency) |
| `screen` | `39, 63, 62` | `#273F3E` | CRT cathode screen background, cheap phone simulated LCD |
| `phosphor` | `177, 206, 166` | `#B1CEA6` | CRT terminal text, blinking cursor, power indicator LED |
| `clay` | `166, 115, 88` | `#A67358` | Terracotta plant pot and rim |

---

## 4. Procedural Held Phone Palette (`src/client/PhoneEquipController.luau`)

To guarantee seamless visual continuity between the stationary desk props and the handheld models equipped to avatar rigs, the client controller uses exact color values:

| Held Device | Component | RGB Values | Hex Equivalent | Visual Target |
|---|---|---|---|---|
| **Cheap Phone** | Chassis Body | `180, 139, 96` | `#B48B60` | Matches `wood_light` desk phone body |
| **Cheap Phone** | Keypad Buttons | `242, 229, 213` | `#F2E5D5` | Matches `cream` physical keys |
| **Cheap Phone** | Monochrome Screen | `168, 182, 156` | `#A8B69C` | Matches `sage` LCD display |
| **Fast Phone** | Chassis Slate | `48, 52, 60` | `#30343C` | Matches `Charcoal` modern phone chassis |
| **Fast Phone** | Touchscreen Glass | `242, 229, 213` | `#F2E5D5` | Lit OLED display panel |
| **Fast Phone** | Camera & Accent | `242, 188, 121` | `#F2BC79` | Matches `Amber` camera bezel and screen glow |

---

## 5. Material Taxonomy & Usage Rules

Roblox built-in materials provide tactile differentiation without texture bloat:

```
+-------------------------------------------------------------------------------+
|                             MATERIAL TAXONOMY                                 |
+-------------------+---------------------------+-------------------------------+
| Material Enum     | Permitted Usage           | Strict Constraints            |
+-------------------+---------------------------+-------------------------------+
| Enum.Material.    | Furniture surfaces, legs, | Aligned grain direction;      |
| Wood              | door, trim, floorboards   | no high-contrast tiling       |
+-------------------+---------------------------+-------------------------------+
| Enum.Material.    | Wall plaster, electronics | Low specular shininess;       |
| SmoothPlastic     | shells, buttons, phones   | primary material for props    |
+-------------------+---------------------------+-------------------------------+
| Enum.Material.    | Bedding, pillows, rug,    | Limited to soft furnishings;  |
| Fabric            | storage box, curtains     | never used on hard furniture  |
+-------------------+---------------------------+-------------------------------+
| Enum.Material.    | Lamp stem, drawer pulls,  | Matte brushed metal;          |
| Metal             | hardware details, rocker  | no blinding mirror reflections|
+-------------------+---------------------------+-------------------------------+
| Enum.Material.    | North window pane only    | Transparency fixed at 0.35;   |
| Glass             |                           | no glassmorphism on UI panels |
+-------------------+---------------------------+-------------------------------+
| Enum.Material.    | CRT power LED indicator   | Maximum dimension: 0.1 studs; |
| Neon              | and phosphor cursor only  | forbidden for room lighting   |
+-------------------+---------------------------+-------------------------------+
```

---

## 6. Contrast Ratios & Accessibility Compliance (WCAG 2.2 AA)

All color pairings are mathematically calculated and verified against WCAG 2.2 Level AA requirements (minimum 4.5:1 for normal text, 3.0:1 for large text/graphical elements) using standard relative luminance ($L = 0.2126 R + 0.7152 G + 0.0722 B$ with sRGB gamma expansion):

| Foreground Color | Background Surface | Contrast Ratio | Evaluation | Context |
|---|---|---|---|---|
| `Cream` (`#F2E5D5`) | `Charcoal` (`#30343C`) | **10.07 : 1** | **PASS (AAA)** | Primary UI body text & headers |
| `CreamMuted` (`#C8BEB2`) | `Charcoal` (`#30343C`) | **6.82 : 1** | **PASS (AA)** | Secondary card subtitles & metadata |
| `Lime` (`#8CB369`) | `CharcoalDark` (`#24272E`) | **6.24 : 1** | **PASS (AA)** | Active purchase buttons & income rate on nav rail |
| `Lime` (`#8CB369`) | `Charcoal` (`#30343C`) | **5.21 : 1** | **PASS (AA)** | Active purchase CTA buttons & tags on cards |
| `Coral` (`#D97D64`) | `CharcoalDark` (`#24272E`) | **5.03 : 1** | **PASS (AA)** | Save blocked alerts & error banners |
| `Coral` (`#D97D64`) | `Charcoal` (`#30343C`) | **4.20 : 1** | **PASS (AA Large)** | Warning notices (large text / graphical boundary $\ge 3:1$) |
| `Amber` (`#F2BC79`) | `Navy` (`#34465A`) | **5.64 : 1** | **PASS (AA)** | BuzzerOS header highlights & equipped badge |
| `Phosphor` (`#B1CEA6`) | `Screen` (`#273F3E`) | **6.56 : 1** | **PASS (AA)** | Physical 3D CRT on-screen text |
| `DisabledText` (`#828892`)| `Disabled` (`#5A606A`) | **1.77 : 1** | **INTENTIONAL**| Non-interactive state (exempt from AA) |

---

## 7. Semantic Color Association Matrix

- **Green / Lime (`#8CB369`)**: Confirmed income, active server sync, high-yield post matches, affordable upgrades.
- **Red / Coral (`#D97D64`)**: Unsaved changes blocked, DataStore lease lock, network disconnection, weak post fit.
- **Gold / Amber (`#F2BC79`)**: Equipped hardware tag, active campaign contract, task lamp illumination, player tier.
- **Blue / Navy (`#34465A`)**: Fictional Buzzline social network brand, stable window title bars, structural anchors.
- **Cream (`#F2E5D5`)**: Human readable text, domestic comfort, clean unvarnished joinery.
