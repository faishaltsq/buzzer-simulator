# 01 — ART DIRECTION & VISUAL IDENTITY

> **Document Status**: Authoritative Art Direction Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Aesthetic Premise & Philosophy

*Buzzer Simulator* captures the cozy, slightly comical reality of an amateur internet influencer / political buzzer operating out of a cramped, rented bedroom. The player is not an elite cyber operative in a high-tech bunker; they are an ordinary person sitting at a secondhand timber desk with an outdated CRT monitor and a cheap cell phone, grinding online campaigns for Cuan.

The aesthetic philosophy is codified as:

$$\textbf{COZY RETRO TECH}$$

It balances domestic comfort with obsolete digital hardware. The environment feels safe, personal, and nostalgic, while the technology feels tactile, mechanical, and slightly stubborn.

---

## 2. The Core Creative Pillars

### 1. Humble Beginning
The journey starts in an unpretentious space. The plaster has minor scuffs; the desk is simple joined timber; the books are mismatched; an original abstract sunset print hangs on the wall. The player's enterprise is small, scrappy, and grounded in reality.

### 2. Warm Personal Bedroom
The room is a sanctuary. Warm timber floorboards, a low wooden bed with folded sage blankets, a comfortable bedside table, and soft lighting pool across the desk. It feels inhabited, not staged.

### 3. Tactile Retro Technology
Technology in this world is heavy, physical, and nostalgic:
- The **OldCRT** has a bulging cathode-ray tube housing, deep cooling vents, a mechanical power toggle, and a separate keyboard with chunky keycaps.
- The **Cheap Phone** has physical push-buttons, a tiny monochrome/sage screen, and an upright resting foot.
- The **BuzzerOS Interface** evokes late-90s/early-2000s desktop operating systems with structured frames, Gotham typography, clear tabular data, and functional status bars.

### 4. Tangible Equipment Progression
Upgrades are not invisible stat bumps; they are visible events in the physical room:
- Swapping the **Cheap Phone** for the **Fast Phone** transforms the desk prop from a chunky keypad brick into a sleek touchscreen device with dual rear camera lenses and an accent glow.
- In BS-11, purchasing **PC Rumah** replaces the bulky CRT terminal with a modern monitor, desktop tower, and gaming-grade peripherals directly at `TerminalSlot`.

### 5. Cozy, Not Childish
The aesthetic avoids cartoonish hyperactivity. Saturated primary colors (bright red, yellow, electric blue) are forbidden. Instead, the world is rendered in warm charcoal, cream, walnut, muted sage, navy, and soft amber.

### 6. Stylized, Handcrafted Geometry
Models are constructed with intentional polygonal bevels, clean silhouettes, and controlled contact shadows. There are no noisy photorealistic textures, bump maps, or uncurated Toolbox meshes. Everything looks like it was shaped by the same hand.

---

## 3. Strict Anti-Patterns (What to Avoid)

| Forbidden Element | Why It Breaks the Vision | Approved Alternative |
|---|---|---|
| **Roblox Toolbox Mixing** | Inconsistent mesh scales, conflicting material shaders, unknown embedded scripts. | 100% native Roblox `BasePart` kits generated via deterministic scripts. |
| **Photorealistic PBR Textures** | Clashes with stylized avatars and creates distracting surface visual noise. | Built-in Roblox procedural materials (`Wood`, `SmoothPlastic`, `Fabric`, `Glass`). |
| **Excessive Neon & Glow** | Looks like a generic sci-fi arcade or rave; destroys domestic warmth. | Soft `PointLight` illumination (`RoomWarmth`, `DeskPool`) and muted `SmoothPlastic`. |
| **AI-Slop Interface Decoration** | Random floating gradients, generic glassmorphism, decorative glyph clutter. | Structured retro desktop OS layout inspired by functional classic software. |
| **Excessive Border Radii** | "Squircle" overload looks like a generic mobile toy app. | Restrained corner radii: 4px for buttons, 8px for cards, 12px for primary windows. |
| **Floating 3D Billboards** | Destroys spatial immersion and clutters third-person camera sightlines. | Surface-mounted `SurfaceGui` occluded in-world + screen-space `ProximityPrompt`. |
| **Gameplay-Obstructing Clutter** | Blocks walking paths or hides interactable prompt anchors. | Perimeter dressing only (north/east walls); clear 3.5+ stud central corridor. |

---

## 4. Environmental Storytelling Principles

Decorative elements are deliberately placed to tell a silent story without distracting from gameplay:
- **The Desk Area**: An unfinished mug of dark coffee sits to the left; an angled navy notebook with paper pages sits to the right; a pair of dark ink cables run along the rear apron to suggest real physical wiring.
- **The North Wall**: An original abstract geometric sunset print (framed timber, linen canvas, amber sun, sage horizon, navy sea) gives the room character without infringing on copyright or requiring external images.
- **The Bookshelf**: A built-in shelf holds seven stylized books with sage, cream, and navy spines, plus a fabric storage box.
- **The Plant**: A warm terracotta clay pot with a rim and four angular dark sage leaves sits in the corner, introducing organic softness.
- **The Bed**: A timber headboard with a sage fabric inset, soft linen mattress, and neatly folded sage blanket with a drape edge conveys a tidy, lived-in personal space.

---

## 5. Visual Hierarchy & Spatial Composition

The bedroom environment establishes a clear focal hierarchy:

```
+-------------------------------------------------------------------------+
| [PRIMARY FOCAL POINT] Player Desk + OldCRT + PhoneSlot                  |
| - High geometric density, high contrast, warm task lighting (DeskPool)  |
| - Direct gameplay interaction: Dashboard ProximityPrompt                |
+-------------------------------------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------+
| [SECONDARY MASS] Bed + Bedside Table + Rug                              |
| - Soft, broad horizontal masses, domestic linen & fabric textures       |
| - Balances the room mass opposite the workspace                         |
+-------------------------------------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------+
| [TERTIARY DRESSING] Bookcase, Window, Plant, Wall Art                   |
| - Perimeter architectural interest, daylight fill (SoftDaylight)        |
| - Framed within room boundary; zero walking obstruction                |
+-------------------------------------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------+
| [RESERVED CAPACITY] Worker Stations (West Wall)                         |
| - Visually quiet, empty floor space reserved for BS-12/13 desks         |
| - Prevents future expansion from feeling crowded or retrofitted         |
+-------------------------------------------------------------------------+
```

---

## 6. Lighting Philosophy

Lighting in *Buzzer Simulator* is atmospheric and narrative:
1. **No Flat Ambient Lighting**: The room is not uniformly washed in blinding ambient white.
2. **Warm Pendant Pool (`RoomWarmth`)**: A soft cream drum pendant suspended from the ceiling (Color: `#FFE8CA`, Brightness: 0.75, Range: 23 studs) provides ambient golden warmth across the room.
3. **Focused Task Lamp (`DeskPool`)**: A metal gooseneck desk lamp with an amber bulb (Color: `#F2BC79`, Brightness: 0.4, Range: 8 studs) casts a dedicated pool of light onto the CRT keyboard and phone pad.
4. **Cool Window Contrast (`SoftDaylight`)**: A diffused daylight fill through the north window (Color: `#D0E3E0`, Brightness: 0.65, Range: 17 studs) introduces subtle temperature contrast against the warm interior lamps.
5. **Contact Shadow Anchoring**: Every furniture piece has defined feet or aprons, ensuring visible contact shadows on the timber floorboards. No furniture appears to float.
