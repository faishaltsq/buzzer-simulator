# 08 — VISUAL QA CHECKLIST & ASSET QUALITY GATES

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Six-Axis Asset Quality Gates

Every current and planned asset in *Buzzer Simulator* must satisfy all six quality axes before entering a release-candidate branch:

```
+-----------------------------------------------------------------------------------+
|                            SIX-AXIS ASSET QUALITY GATES                           |
+-------------------+---------------------------------------------------------------+
| Axis              | Mandatory Acceptance Criteria                                 |
+-------------------+---------------------------------------------------------------+
| **1. Geometry**   | * Correct model scale relative to standard Roblox avatar.     |
|                   | * PrimaryPart assigned with verified vertical pivot offset.   |
|                   | * Expected orientation (screens face local -Z).               |
|                   | * Zero floating parts; exact surface contact on desk/floor.   |
|                   | * Zero unintended geometry clipping or z-fighting.            |
+-------------------+---------------------------------------------------------------+
| **2. Structure**  | * Stable model identity and approved hierarchy.               |
|                   | * 12 named bedroom anchors preserved with immutable names.    |
|                   | * Zero embedded Script, LocalScript, or ModuleScript instances|
|                   | * Zero unauthorized Network Remotes or external dependencies. |
|                   | * All structural parts anchored (Anchored = true).            |
+-------------------+---------------------------------------------------------------+
| **3. Art & Style**| * 100% compliant with Cozy Retro Tech palette and Theme.luau. |
|                   | * Built-in materials only (SmoothPlastic, Wood, Metal, Fabric)|
|                   | * Distinct, readable silhouette at 15+ studs camera distance. |
|                   | * Controlled detail density; no noisy micro-patterns.         |
|                   | * WCAG 2.2 AA contrast compliance on all readable surfaces.   |
+-------------------+---------------------------------------------------------------+
| **4. Performance**| * Strict part budget compliance (Room <= 250 BaseParts).      |
|                   | * Max 4 light sources per room; no unshielded neon slabs.     |
|                   | * Minimal transparent overdraw (Glass transparency = 0.35).   |
|                   | * 60 FPS target maintained on mobile emulator devices.        |
+-------------------+---------------------------------------------------------------+
| **5. Interaction**| * ProximityPrompt reachable and non-obstructed (10-stud range)|
|                   | * Held equipment synchronized with server-confirmed profile.  |
|                   | * Clear 3.5+ stud walking corridors; zero physics snagging.   |
|                   | * Joint poses and animations interruptible; respawn-safe.     |
+-------------------+---------------------------------------------------------------+
| **6. Evidence**   | * Authentic Roblox Studio Play screenshot archived in repo.   |
|                   | * Desktop wide layout (1280x720) evidence captured.           |
|                   | * Mobile portrait (390x844) touch layout evidence captured.   |
|                   | * Rojo production and test builds compile cleanly.            |
|                   | * Documented in assets/ASSET-MANIFEST.md with SHA-256 hash.   |
+-------------------+---------------------------------------------------------------+
```

---

## 2. Issue Severity Classification

- **P0 — Critical Defect**: Functional failure, physics softlock, camera trap, or severe illegibility that halts gameplay progression.
- **P1 — Major Inconsistency**: Noticeable aesthetic contradiction, broken material hierarchy, clipped prompt, or severe mobile layout distortion.
- **P2 — Polish Gap**: Subtle geometric overlap, minor edge shimmering, slight typography imbalance, or non-optimal touch padding.
- **P3 — Optional Enhancement**: Minor atmospheric flourish, secondary decorative accessory, or purely aesthetic polish.

---

## 3. Grounded Visual Audit of Existing Assets

Based on an exhaustive inspection of the actual repository assets (`assets/world/`, `assets/ui/`), code implementations (`src/client/`, `tools/`), and archived Studio screenshots (`assets/world/review/`, `assets/ui/review/`, `assets/ui/bs08-review/`, `assets/ui/bs09-review/`, `docs/evidence/bs10/`), the following findings are documented:

| ID | Category | Asset / Screen | Evidence Source | Severity | Summary & Visual Impact | Recommended Correction |
|---|---|---|---|---|---|---|
| **V-01** | Geometry / Scaling | `PhoneCheap` & `PhoneFast` | `assets/world/review/desk-cheap.jpg` vs `assets/ui/bs09-review/cheap-phone-hand.jpg` | **P2** | **Scale Discrepancy Between Desk & Handheld**: Desk phone is 2.0 studs tall; held phone is 1.02 studs tall. This was an intentional ergonomic choice (desk phone needs third-person visibility; held phone must fit avatar palm), but creates a slight perceptual pop on equip. | Retain current sizing for ergonomic safety, but add a 0.15s scale-blend tween during equip to visually smooth the volume transition. |
| **V-02** | Shimmering / Geometry | `Bedroom` (Rug & Bed) | `assets/world/Bedroom.rbxmx` (`RugStripe` Y=0.01, `BlanketHem` Y=0.06) | **P2** | **Potential Coplanar Shimmering at Distance**: Rug stripes (0.01 stud thick) and mattress piping (0.07 stud thick) sit very close to base surfaces. On mobile devices without anti-aliasing, extreme camera grazing angles can produce subtle specular shimmering. | In a future asset polish pass, increase vertical thickness of decorative fabric stripes from 0.01 to 0.035 studs to ensure robust depth-buffer separation. |
| **V-03** | Lighting / Atmosphere | `Bedroom` (North Window) | `assets/world/review/room-interior.jpg` | **P2** | **Unshielded Window Exterior Space**: The north window looks out directly into the empty default Roblox baseplate/skybox. While `SoftDaylight` provides an effective cool fill (17-stud range), looking directly through the glass reveals raw engine sky. | Introduce a lightweight exterior window backdrop card (a simple night/day city silhouette or tree trellis, ~4 BaseParts) outside the wall in a future environment update. |
| **V-04** | UI / Responsive | `Desktop.luau` (Mobile Nav) | `assets/ui/review/mobile-portrait-home.jpg` & `docs/evidence/bs10/mobile_portrait_390x844.png` | **P2** | **Mobile Bottom Nav Density on Narrow Screens**: On narrow 360px portrait devices, the 5-tab bottom navigation rail (Home, Feed, Create, Missions, More) approaches the 44px minimum tap target boundary with tight horizontal margins. | Increase bottom rail icon padding and ensure the "More..." dropdown modal has generous touch targets ($\ge 48\text{px}$) on compact viewports. |
| **V-05** | Surface Contrast | `OldCRT` (SurfaceGui Title) | `assets/world/review/crt-close-up.jpg` | **P3** | **Small Font Size on Physical Screen at Distance**: The green phosphor title `"BuzzerOS"` on the CRT screen is sharp at desk approach (6.56:1 contrast), but shrinks below legible threshold when standing at spawn ($Z = 6$). | The primary prompt text (`"Open BuzzerOS"`) on `DashboardPrompt` correctly handles distant orientation; the physical screen title is secondary flavor. No code change needed; behavior is working as designed. |

---

## 4. Prioritized Visual Polish Backlog

The following sequenced roadmap outlines visual enhancements for upcoming milestones. **None of these items are executed in this milestone**; this roadmap provides clear direction for future work.

### Phase 1: High-Priority Inconsistencies & Alignment
- **Item 1.1**: *Depth-Buffer Separation for Fine World Trims*
  - **Scope**: Increase minimum part thickness on rug stripes and blanket piping in `tools/gen_world_prefabs.py` from 0.01 to 0.035 studs.
  - **Files**: `tools/gen_world_prefabs.py`, `assets/world/Bedroom.rbxmx`.
  - **Dependencies**: None.
  - **Risk**: Low (cosmetic geometry only).
  - **Acceptance Criteria**: Zero z-fighting visible under low-end mobile camera sweep.
  - **Screenshot Requirement**: Desktop camera orbit video/capture at grazing angle.

### Phase 2: Mobile Touch & UI Polish
- **Item 2.1**: *Mobile Navigation Touch Target Hardening*
  - **Scope**: Enforce 48px minimum height on mobile bottom navigation tabs and More modal rows.
  - **Files**: `src/client/ui/Desktop.luau`.
  - **Dependencies**: None.
  - **Risk**: Low.
  - **Acceptance Criteria**: All touch targets exceed 48×48 reference pixels; verified on 360×640 emulator.
  - **Screenshot Requirement**: iPhone 14 portrait screenshot with touch bounding boxes visible.

### Phase 3: Environmental Atmosphere
- **Item 3.1**: *Exterior Window Sill Dressing*
  - **Scope**: Add a subtle, low-part exterior wall sill and stylized horizon silhouette outside the north window opening.
  - **Files**: `tools/gen_world_prefabs.py`, `assets/world/Bedroom.rbxmx`.
  - **Dependencies**: Item 1.1.
  - **Risk**: Low (stays within 250-part budget; adds <= 6 BaseParts).
  - **Acceptance Criteria**: Camera facing north window sees stylized domestic backdrop instead of empty void.
  - **Screenshot Requirement**: Studio capture facing window from bed headboard.

### Phase 4: Equipment Progression Integration (BS-11)
- **Item 4.1**: *PC Rumah Asset Production & Swap Verification*
  - **Scope**: Model `PCRumah.rbxmx` according to [`docs/design/04-EQUIPMENT-AND-PROGRESSION.md`](04-EQUIPMENT-AND-PROGRESSION.md), integrate into `WorldService`, and verify clean swap at `TerminalSlot`.
  - **Files**: `tools/gen_world_prefabs.py`, `assets/world/PCRumah.rbxmx`, `src/server/WorldService.luau`.
  - **Dependencies**: BS-11 milestone kickoff.
  - **Risk**: Medium (dynamic server model swap).
  - **Acceptance Criteria**: Seamless replacement of OldCRT; prompt remains accessible; yield increases to 2.5x.
  - **Screenshot Requirement**: Studio captures before and after PC purchase.
