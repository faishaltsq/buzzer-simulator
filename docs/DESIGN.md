# BUZZER SIMULATOR — AUTHORITATIVE VISUAL DESIGN SYSTEM

> **Document Status**: Authoritative / Living Design System  
> **Milestone Base**: Post-BS-10 Integration (`ba2b111516fd54d2df8acdea7ce02bec33f8f987`)  
> **Target Audience**: Technical Art Directors, UI/UX Designers, 3D Environment Artists, Luau Integration Engineers  
> **Implementation Baseline**: Zero source code changes; zero prefab alterations; strict design governance

---

## 1. Executive Summary & Core Identity

**BUZZER SIMULATOR** is a stylized, incremental tycoon experience centered around a solitary online buzzer operating from a humble bedroom. The core visual philosophy is:

$$\textbf{COZY RETRO TECH}$$

### Core Feelings
- **Humble Beginning**: An authentic, slightly worn, rented bedroom studio.
- **Warm Personal Space**: Lived-in warmth, honest timber joinery, soft linen bedding, domestic clutter.
- **Slightly Humorous Indie Simulator**: The ironic juxtaposition of an earnest hustle culture with bulky, outdated, second-hand hardware.
- **Nostalgic Technology**: Chunky cathode-ray tubes, tactile mechanical keycaps, clicky handsets, warm glowing LEDs.
- **Tangible Equipment Progression**: Visual, physical evolution where upgrades replace obsolete machinery directly in the 3D space.
- **Cozy, Not Childish**: Grounded, muted earthy tones rather than plastic primary toy colors.
- **Stylized, Not Photorealistic**: Bold, readable geometry, beveled contact shadows, and deliberate silhouette clarity.
- **Restrained Decorative Detail**: Every prop serves spatial grounding or gameplay orientation; no visual noise.

### Design Dials (Authoritative)
- **ENERGY: 1** — Calm, focused, domestic, methodical. No flashing neon billboards or chaotic particle fountains.
- **RHYTHM: 2** — Steady, predictable visual beats. Subtle terminal cursors, rhythmic typing flourishes, structured feed cards.
- **MOTION: 1** — Restrained, functional motion. Fluid transitions (0.2–0.35s), smooth camera dollies, zero disorienting screen shakes.

---

## 2. Master Specification Map

This master document serves as the single source of truth and root index for the entire visual design system. Specialized subsystems are detailed in dedicated modular specifications:

| Area | Authoritative Document | Scope |
|---|---|---|
| **Art Direction** | [`docs/design/01-ART-DIRECTION.md`](design/01-ART-DIRECTION.md) | Creative pillars, aesthetic boundaries, mood, storytelling, anti-patterns |
| **Color & Materials** | [`docs/design/02-COLOR-AND-MATERIALS.md`](design/02-COLOR-AND-MATERIALS.md) | Universal color tokens, surface mapping, material taxonomy, contrast ratios |
| **World Environment** | [`docs/design/03-WORLD-ENVIRONMENT.md`](design/03-WORLD-ENVIRONMENT.md) | 24×24 bedroom layout, 12 frozen anchor contracts, lighting model, camera rules |
| **Equipment & Progression** | [`docs/design/04-EQUIPMENT-AND-PROGRESSION.md`](design/04-EQUIPMENT-AND-PROGRESSION.md) | Shipped hardware (`OldCRT`, `PhoneCheap`, `PhoneFast`), planned hardware (`PCRumah`, Desks) |
| **Characters & Animation** | [`docs/design/05-CHARACTERS-AND-ANIMATION.md`](design/05-CHARACTERS-AND-ANIMATION.md) | Avatar rigs (R6/R15), procedural phone grip, shoulder tweens, IK fallback, staff standards |
| **UI/UX System** | [`docs/design/06-UI-UX-SYSTEM.md`](design/06-UI-UX-SYSTEM.md) | BuzzerOS shell, World HUD, typography, responsive breakpoints, state machines |
| **Asset Pipeline** | [`docs/design/07-ASSET-PRODUCTION-PIPELINE.md`](design/07-ASSET-PRODUCTION-PIPELINE.md) | Python prefab generation, Rojo mappings, part budgets, security, coordinate spaces |
| **Visual QA Checklist** | [`docs/design/08-VISUAL-QA-CHECKLIST.md`](design/08-VISUAL-QA-CHECKLIST.md) | 6-axis asset quality gates, visual audit findings (P0–P3), prioritized polish backlog |

### Folder-Level Conventions & Asset Specs
- **World Asset Guidelines**: [`assets/world/DESIGN.md`](../assets/world/DESIGN.md)
- **UI Asset & Evidence Guidelines**: [`assets/ui/DESIGN.md`](../assets/ui/DESIGN.md)
- **Detailed Asset Model Specs**:
  - `Bedroom` (155 BaseParts): [`assets/design/specs/Bedroom.md`](../assets/design/specs/Bedroom.md)
  - `OldCRT` (52 BaseParts): [`assets/design/specs/OldCRT.md`](../assets/design/specs/OldCRT.md)
  - `PhoneCheap` (25 BaseParts): [`assets/design/specs/PhoneCheap.md`](../assets/design/specs/PhoneCheap.md)
  - `PhoneFast` (23 BaseParts): [`assets/design/specs/PhoneFast.md`](../assets/design/specs/PhoneFast.md)
- **Asset Manifest**: [`assets/ASSET-MANIFEST.md`](../assets/ASSET-MANIFEST.md)

---

## 3. Universal System Invariants

All future engineering, asset authoring, and UI implementation must comply with the following mandatory system invariants:

1. **No External Asset Dependencies**: All 3D assets are composed exclusively of native Roblox `BasePart` primitives and built-in Roblox materials. No unauthorized third-party meshes, textures, decals, sound IDs, or Toolbox models are permitted without technical art review and manifest tracking.
2. **Strict Rojo Path Preservation**: Prefabs under `assets/world/` (`Bedroom.rbxmx`, `OldCRT.rbxmx`, `PhoneCheap.rbxmx`, `PhoneFast.rbxmx`) must never be moved or renamed; doing so breaks `default.project.json` and `test.project.json`.
3. **Frozen Anchor Contract**: The 12 named anchors in `Bedroom.rbxmx` (`Spawn`, `PlayerDesk`, `DashboardPromptAnchor`, `TerminalSlot`, `PhoneSlot`, `WorkerDeskSlot1`, `WorkerSeat1`, `WorkerDeskSlot2`, `WorkerSeat2`, `CameraFocus`, `Door`, `LightGroup`) are immutable server contracts. Their names, orientations, and pivot positions must never be altered.
4. **Separation of Terminal vs. Productive Device**:
   - `OldCRT` is a dashboard access terminal **only**. It has zero yield, zero economic multiplier, and produces no income.
   - `PhoneCheap` and `PhoneFast` are productive devices located at `PhoneSlot`. They determine post yields and countdown durations.
   - Upgrading to `PCRumah` (BS-11) replaces `OldCRT` at `TerminalSlot` and becomes the sole productive device, leaving the phone inert.
5. **Authoritative Palette Synchronization**: UI styling in `src/client/ui/Theme.luau`, procedural 3D styling in `src/client/PhoneEquipController.luau`, and 3D world prefabs in `tools/gen_world_prefabs.py` must adhere strictly to the shared Cozy Retro Tech color hierarchy.
6. **Touch Accessibility Target**: All interactive touch surfaces across mobile and desktop must maintain a minimum physical target size of **44 × 44 reference pixels** (`UISizeConstraint.MinSize = Vector2.new(44, 44)`).
7. **Performance & Part Budget**: The total placed decorative part budget for a single furnished player room in V0/M1 is strictly capped at **250 BaseParts**. No per-frame script scans or client physics simulations are permitted on world geometry.

---

## 4. Visual Identity Matrix

```
+-----------------------------------------------------------------------------------+
|                           BUZZER SIMULATOR VISUAL IDENTITY                         |
+-----------------------------------------+-----------------------------------------+
| DO PRESERVE                             | DO AVOID                                |
+-----------------------------------------+-----------------------------------------+
| * Stylized bevels & chunky primitives   | * Uncurated Roblox Toolbox asset mixing |
| * Warm domestic timber & cream plaster  | * Hyper-realistic PBR textures          |
| * Muted sage, walnut, navy & amber      | * Saturated neon glow & rainbow palettes|
| * Tactile CRT tubes & mechanical keys   | * Generic modern SaaS flat dashboards   |
| * Open-ceiling camera orbit clearance   | * Enclosing ceiling lids blocking camera|
| * Procedural handheld phone models      | * Cluttered floating 3D text/billboards |
| * Authentic retro OS interface feel     | * Unnecessary glassmorphism/drop shadows|
+-----------------------------------------+-----------------------------------------+
```

---

## 5. Governance & Lifecycle

This design system governs all production stages from BS-10 through M1. No new 3D assets, UI screens, or animation states may be committed to `master` without passing the verification criteria detailed in [`docs/design/08-VISUAL-QA-CHECKLIST.md`](design/08-VISUAL-QA-CHECKLIST.md).
