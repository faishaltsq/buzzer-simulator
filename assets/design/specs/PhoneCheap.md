# ASSET SPECIFICATION: CHEAP PHONE

> **Asset File**: `assets/world/PhoneCheap.rbxmx`  
> **Generator Script**: `tools/gen_world_prefabs.py` (`build_phone_cheap`)  
> **Handheld Implementation**: `src/client/PhoneEquipController.luau` (`HeldPhoneCheap`)  
> **Parent Document**: [`docs/DESIGN.md`](../../../docs/DESIGN.md)

---

## 1. Asset Metadata & Purpose

- **Asset Name**: `PhoneCheap`
- **File Path**: `assets/world/PhoneCheap.rbxmx`
- **Gameplay Purpose**: Default starter productive hardware assigned on fresh player join. Determines baseline organic post payout (15 strong / 9 weak Cuan) and 18-second reveal duration.
- **Ownership**: Server-owned desk prop; cloned per player into `Workspace.BuzzerRoom_<UserId>` and mounted at `PhoneSlot`. Client-owned procedural model (`HeldPhoneCheap`) welded to avatar hand when equipped.
- **Parent Hierarchy in Studio**:
  ```
  Workspace
  └── BuzzerRoom_<UserId> (Folder)
      └── PhoneCheap (Model)
          ├── Body (Part, PrimaryPart)
          ├── BodyCross, BodyCorner (x4) [Rounded 6-part bevel]
          ├── BackPlate, ScreenBezel, Screen, Earpiece
          ├── NavigationKey, ScreenLine (x2), CornerWear, Camera
          ├── Key (x9: 3x3 numeric grid)
          └── RestFoot (Part, rear kickstand)
  ```

---

## 2. Geometric & Physical Properties

- **Dimensions (Desk Prop)**: $1.10\text{ studs (W)} \times 2.00\text{ studs (H)} \times 0.28\text{ studs (D)}$.
- **Dimensions (Handheld Tool)**: $0.52\text{ studs (W)} \times 1.02\text{ studs (H)} \times 0.16\text{ studs (D)}$.
- **Model Pivot**: Positioned at local $(0, 1.00, 0)$. In room space, placed at $Y = 3.35 + 1.00 = 4.35$ studs.
- **PrimaryPart**: `Body` (`referent = "RBX211"`).
- **Total BasePart Count**: **Exactly 25 BaseParts** (Desk prefab) / 11 BaseParts (Handheld procedural model).
- **Embedded Scripts / Remotes**: **Exactly 0**.
- **Physical Collision Profile**:
  - `Body` and bevels enforce `CanCollide = false`.
  - All parts enforce `Anchored = true`, `CanTouch = false`, `CanQuery = false`.

---

## 3. Materials, Palette & Ergonomics

- **Roblox Materials Used**:
  - `SmoothPlastic`: All body parts, buttons, and screen.
- **Color Palette Breakdown**:
  - Phone Chassis Body: `wood_light` (`#B48B60`).
  - Screen Bezel & Earpiece: `ink` (`#202A2D`).
  - Monochrome LCD Display: `sage` (`#84977E`).
  - Physical Keycaps (3×3 grid): `cream` (`#E9DEC7`).
  - Backplate & Rest Foot: `wood_dark` (`#654A37`).
  - Simulated Text Lines: `screen` (`#273F3E`).
- **Ergonomics & Presentation**:
  - **Desk Presentation**: Resting on `RestFoot` at an 80° upright incline, facing the player (+Z).
  - **Handheld Grip**: Welded to `RightHand` (R15) or `Right Arm` (R6) with screen facing outward from the palm.
  - **Concealment**: When held, desk model is client-locally hidden with `LocalTransparencyModifier = 1`.

---

## 4. Interaction & Boundary Contracts

- **Economic Authority**: The presence of `PhoneCheap` at `PhoneSlot` is a visual reflection of `profile.deviceId == "phone_cheap"`. The 3D model itself holds no scripts or currency logic.
- **Shop Upgrade Path**: When the player purchases `PhoneFast` (50 Cuan) in BuzzerOS, `WorldService.luau` destroys `PhoneCheap` and spawns `PhoneFast` at `PhoneSlot` without interrupting active player sessions.

---

## 5. Visual Quality Assessment & Acceptance Criteria

- **Current Visual Quality**: Authentic retro brick phone aesthetic. The chunky keypad and muted sage screen immediately communicate a budget, starter-tier device.
- **Identified Inconsistencies**: Sizing difference between desk prop (2.0 studs) and held prop (1.02 studs) (finding V-01).
- **Recommended Adjustments**: Retain current dimensions; add smooth scale-blend tween on equip in future polish passes.
- **Visual Acceptance Status**: **ACCEPTED (Technical & Architectural)**; Commercial human art sign-off pending.
