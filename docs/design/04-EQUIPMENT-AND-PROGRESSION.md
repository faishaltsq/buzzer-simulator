# 04 — EQUIPMENT SYSTEM & HARDWARE PROGRESSION

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Equipment Philosophy & Economic Separation

In *Buzzer Simulator*, hardware progression is physical and visible. Upgrades do not happen in an abstract inventory menu; they materialize directly in the 3D bedroom environment.

A foundational architectural rule governs all equipment:

$$\textbf{Strict Separation of Access Terminal vs. Productive Device}$$

```
+-----------------------------------------------------------------------------------+
| PHYSICAL HARDWARE ROLE SEPARATION                                                 |
+-------------------------------------------------+---------------------------------+
| ACCESS TERMINAL (OldCRT / Future PC Rumah)      | PRODUCTIVE DEVICE (Phones / PC) |
+-------------------------------------------------+---------------------------------+
| * Physical interaction target for player        | * Determines organic post yield |
| * Hosts ProximityPrompt ("Open BuzzerOS")       | * Determines reveal duration    |
| * Renders client BuzzerOS screen-space GUI      | * Swapped dynamically on desk   |
| * OldCRT has 0.0x yield and 0 Cuan output       | * Carried in hand as a tool     |
+-------------------------------------------------+---------------------------------+
```

---

## 2. Existing Shipped Equipment (Audited Implementation)

### 2.1. OldCRT (`assets/world/OldCRT.rbxmx`)
- **Gameplay Role**: Dashboard-only access terminal. Non-productive (0x yield).
- **Physical Footprint**: $3.1 \text{ studs (W)} \times 2.8 \text{ studs (H)} \times 2.8 \text{ studs (D)}$ (including keyboard).
- **PrimaryPart**: `MonitorBody` at local $(0, 1.4, 0)$. Pivot offset is frozen at $+1.4$ studs Y.
- **BasePart Count**: Exactly 52 BaseParts.
- **Silhouette & Visual Read**:
  - Bulging cathode-ray tube with stepped rear housing (`TubeHousing`, `TubeRear`).
  - Chamfered bezel framing an inset dark green phosphor display (`#273F3E`).
  - Four lateral heat dissipation vents per side.
  - Physical mechanical keyboard tray with 24 individual cream keycaps and a spacebar.
  - Mechanical power toggle button with a miniature green phosphor power LED (`#B1CEA6`).
  - Subtle scuff and yellowed service sticker detailing on the chassis.
- **On-Screen World Graphics**:
  - Embedded non-billboard `SurfaceGui` (`BuzzerOSScreen`, CanvasSize: $512 \times 320$, `LightInfluence = 1`, `AlwaysOnTop = false`).
  - Displays retro green phosphor text `"BuzzerOS"` (Contrast: 6.56:1 on screen background).
  - Physical 3D horizontal rules and a phosphor blinking cursor primitive.

### 2.2. Cheap Phone (`assets/world/PhoneCheap.rbxmx` & `HeldPhoneCheap`)
- **Gameplay Role**: Starter productive device (Default tier). Organic post yield: 15 / 9 Cuan; reveal time: 18s.
- **Physical Footprint (Desk)**: $1.1 \text{ studs (W)} \times 2.0 \text{ studs (H)} \times 0.28 \text{ studs (D)}$.
- **Physical Footprint (Handheld)**: $0.52 \times 1.02 \times 0.16 \text{ studs}$ (ergonomically scaled for avatar hands).
- **PrimaryPart**: `Body` at local $(0, 1.0, 0)$. Pivot offset is frozen at $+1.0$ studs Y.
- **BasePart Count**: Exactly 25 BaseParts (Desk prefab).
- **Silhouette & Visual Read**:
  - Chunky, curved candybar phone with a visible rear battery bulge.
  - Thick dark ink bezel framing a square sage monochrome LCD (`#A8B69C`).
  - Tactile 3×3 physical numeric keypad with cream buttons and a central navigation rocker.
  - Distinctive rear timber kickstand (`RestFoot`) holding the device upright on the desk at 80° tilt.
  - Single circular camera lens on rear backplate.

### 2.3. Fast Phone (`assets/world/PhoneFast.rbxmx` & `HeldPhoneFast`)
- **Gameplay Role**: Tier 1 upgraded productive device (Catalog cost: 50 Cuan). Organic post yield: 24 / 14 Cuan (1.6x multiplier); reveal time: 16s.
- **Physical Footprint (Desk)**: $1.0 \text{ studs (W)} \times 2.2 \text{ studs (H)} \times 0.16 \text{ studs (D)}$.
- **Physical Footprint (Handheld)**: $0.50 \times 1.04 \times 0.11 \text{ studs}$.
- **PrimaryPart**: `Body` at local $(0, 1.1, 0)$. Pivot offset is frozen at $+1.1$ studs Y.
- **BasePart Count**: Exactly 23 BaseParts (Desk prefab).
- **Silhouette & Visual Read**:
  - Slim, modern, rounded touchscreen slate in dark navy (`#34465A`).
  - Edge-to-edge dark glass display with a rounded top notch and horizontal screen card accents.
  - Dual vertical rear camera lenses encased in an elevated camera bump with amber metal trim.
  - Left-edge metallic volume rocker and bottom pill-shaped home indicator.
  - Clear visual progression: distinctly thinner and taller than PhoneCheap; no physical keypad buttons.

---

## 3. Planned Equipment Specifications (PROPOSED ONLY — NOT IMPLEMENTED)

The following specifications are blueprints for upcoming milestones. They must **not** be implemented during the visual design system milestone.

### 3.1. PC Rumah (`PCRumah.rbxmx` — Planned Milestone BS-11)
- **Status**: **NOT IMPLEMENTED (PROPOSED DESIGN SPECIFICATION)**
- **Gameplay Role**: Tier 2 upgraded hardware (Catalog cost: 120 Cuan). Replaces `OldCRT` at `TerminalSlot` and becomes the **sole productive device** (yield: 2.5x, strong payout 37 Cuan, reveal time: 13s). The phone becomes an inert desk prop.
- **Spatial Footprint Contract**:
  - Must fit strictly within the bounding box of `TerminalSlot`: $3.0 \text{ studs (W)} \times 2.6 \text{ studs (D)}$ on the desktop surface ($Y = 3.35$).
  - Must preserve unobstructed line-of-sight and activation radius for `DashboardPromptAnchor` at $(7.4, 3.6, -2.4)$.
  - Must maintain a minimum 0.5-stud gap from `PhoneSlot` $(4.6, 3.35, -3.8)$ to avoid prop interpenetration.
- **Silhouette & Industrial Design**:
  - **Monitor**: Slim-bezel 16:9 flat panel display (approx. 3.2 studs wide × 2.0 studs high) on an angled metal neck and weighted pedestal base.
  - **Screen Glow**: Soft amber/cyan desktop glow casting subtle light onto the desk surface.
  - **Computer Tower (Case)**: Mid-tower PC chassis resting beside or beneath the desk leg. Features dark charcoal casing, subtle front intake vents, and a faint amber internal LED glow (no chaotic RGB cycling).
  - **Peripherals**: Low-profile mechanical keyboard with dark navy keycaps, cream spacebar, and an accompanying optical mouse on a sage fabric desk mat.
- **Technical Standards**:
  - Maximum BasePart budget: **60 BaseParts**.
  - No client physics; all parts anchored.
  - Screen displays an embedded `SurfaceGui` with updated high-resolution BuzzerOS branding.

### 3.2. Worker Workstations & Trainee Rigs (Planned Milestones BS-12 & BS-13)
- **Status**: **NOT IMPLEMENTED (PROPOSED DESIGN SPECIFICATION)**
- **Gameplay Role**: Passive income expansion. Desk 1 (180 Cuan) enables Worker 1 (1.5 Cuan/s online); Desk 2 (250 Cuan) enables Worker 2 (3.0 Cuan/s total).
- **Spatial Footprint Contracts**:
  - Workstation 1 must fit within `WorkerDeskSlot1` $(-8.0, 3.2, -8.0)$ and `WorkerSeat1` $(-8.0, 1.6, -6.2)$.
  - Workstation 2 must fit within `WorkerDeskSlot2` $(-8.0, 3.2, -2.0)$ and `WorkerSeat2` $(-8.0, 1.6, -0.2)$.
- **Furniture Kit Language**:
  - Compact desks built with the same `wood_light` and `wood_dark` timber joinery as the player desk, maintaining architectural unity.
  - Wooden ergonomic swivel chairs scaled to standard Roblox avatars ($2 \times 2 \times 2 \text{ studs}$).
  - Simple budget desktop monitors and second-hand peripherals matching the humble home-studio aesthetic.
- **Trainee Character Rigs**:
  - Standard blocky R15 rigs dressed in casual domestic clothing (cream t-shirts, navy pants).
  - Seated ambient typing loop: gentle arm oscillations towards keyboard; occasional head nod.
  - Strict performance rule: Trainee animation runs purely client-side; server maintains zero AnimationControllers or physics instances.

---

## 4. Hardware Progression Comparison Matrix

```
+-------------------------------------------------------------------------------------------------------+
|                                    HARDWARE EVOLUTION SUMMARY                                         |
+-------------------+---------------+---------------+-------------------+---------------+---------------+
| Attribute         | OldCRT        | PhoneCheap    | PhoneFast         | PCRumah       | Worker Desks  |
+-------------------+---------------+---------------+-------------------+---------------+---------------+
| Shipped Status    | SHIPPED (V0)  | SHIPPED (V0)  | SHIPPED (BS-09)   | PLANNED(BS-11)| PLANNED(BS-12)|
| Role              | Access Only   | Starter Yield | Upgraded Yield    | Sole Primary  | Passive Staff |
| Economic Yield    | 0.0x (0 Cuan) | 1.0x (15 Cuan)| 1.6x (24 Cuan)    | 2.5x (37 Cuan)| 1.5 - 3 Cuan/s|
| Reveal Duration   | N/A           | 18 seconds    | 16 seconds        | 13 seconds    | Continuous    |
| BasePart Count    | 52            | 25            | 23                | <= 60 (budget)| <= 40 / desk  |
| Primary Material  | SmoothPlastic | Wood/Plastic  | Metal/Plastic     | Metal/Plastic | Wood / Fabric |
| Key Highlight     | CRT Tube Bulge| 3x3 Keypad    | Dual Camera Notch | 16:9 Monitor  | Reusable Kit  |
+-------------------+---------------+---------------+-------------------+---------------+---------------+
```
