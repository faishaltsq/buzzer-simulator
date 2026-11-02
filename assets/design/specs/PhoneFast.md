# ASSET SPECIFICATION: FAST PHONE

> **Asset File**: `assets/world/PhoneFast.rbxmx`  
> **Generator Script**: `tools/gen_world_prefabs.py` (`build_phone_fast`)  
> **Handheld Implementation**: `src/client/PhoneEquipController.luau` (`HeldPhoneFast`)  
> **Parent Document**: [`docs/DESIGN.md`](../../../docs/DESIGN.md)

---

## 1. Asset Metadata & Purpose

- **Asset Name**: `PhoneFast`
- **File Path**: `assets/world/PhoneFast.rbxmx`
- **Gameplay Purpose**: Tier 1 upgraded productive hardware purchased for 50 Cuan in BuzzerOS. Increases organic post payouts to 24 strong / 14 weak Cuan (1.6x multiplier) and reduces reveal countdown to 16 seconds.
- **Ownership**: Server-owned desk prop; cloned per player into `Workspace.BuzzerRoom_<UserId>` and mounted at `PhoneSlot`. Client-owned procedural model (`HeldPhoneFast`) welded to avatar hand when equipped.
- **Parent Hierarchy in Studio**:
  ```
  Workspace
  └── BuzzerRoom_<UserId> (Folder)
      └── PhoneFast (Model)
          ├── Body (Part, PrimaryPart)
          ├── BodyCross, BodyCorner (x4) [Rounded 6-part bevel]
          ├── Screen, ScreenCross, ScreenCorner (x4) [Rounded OLED panel]
          ├── BackPlate, Notch, ScreenHeader, ScreenCard, ScreenAccent
          ├── HomeIndicator, CameraBump, VolumeRocker, RestFoot
          └── CameraLens (x2: vertical dual camera)
  ```

---

## 2. Geometric & Physical Properties

- **Dimensions (Desk Prop)**: $1.00\text{ studs (W)} \times 2.20\text{ studs (H)} \times 0.16\text{ studs (D)}$.
- **Dimensions (Handheld Tool)**: $0.50\text{ studs (W)} \times 1.04\text{ studs (H)} \times 0.11\text{ studs (D)}$.
- **Model Pivot**: Positioned at local $(0, 1.10, 0)$. In room space, placed at $Y = 3.35 + 1.10 = 4.45$ studs.
- **PrimaryPart**: `Body` (`referent = "RBX246"`).
- **Total BasePart Count**: **Exactly 23 BaseParts** (Desk prefab) / 4 BaseParts (Handheld procedural model).
- **Embedded Scripts / Remotes**: **Exactly 0**.
- **Physical Collision Profile**:
  - `Body` and screen components enforce `CanCollide = false`.
  - All parts enforce `Anchored = true`, `CanTouch = false`, `CanQuery = false`.

---

## 3. Materials, Palette & Industrial Design

- **Roblox Materials Used**:
  - `SmoothPlastic`: Chassis body, glass screen, camera bump, and rest foot.
  - `Metal`: Backplate, notch, and volume rocker.
- **Color Palette Breakdown**:
  - Slate Chassis Body: `navy` (`#344451`).
  - Edge-to-Edge OLED Display: `ink` (`#202A2D`).
  - Rear Backplate & Volume Rocker: `sage_dark` (`#506C56`), `metal` (`#6E7773`).
  - Screen Header & Accent Cards: `sage` (`#84977E`), `navy` (`#344451`), `phosphor` (`#B1CEA6`).
  - Home Indicator & Bevels: `cream` (`#E9DEC7`).
  - Dual Camera Lenses: `ink` (`#202A2D`).
- **Ergonomics & Presentation**:
  - **Desk Presentation**: Stands upright at 80° tilt on `RestFoot` beside the CRT terminal. Thinner, taller, and sleeker than `PhoneCheap`.
  - **Handheld Grip**: Welded to `RightHand` (R15) or `Right Arm` (R6). Displays illuminated touchscreen face and golden rear camera bump.
  - **Concealment**: When equipped, desk model is client-locally hidden with `LocalTransparencyModifier = 1`.

---

## 4. Interaction & Boundary Contracts

- **Economic Authority**: Swapped dynamically into `PhoneSlot` when the server confirms `profile.deviceId == "phone_fast"`. The 3D model itself contains zero economic or networking scripts.
- **Visual Progression**: Provides immediate, unambiguous physical confirmation that the player has advanced past starter hardware.
- **Future PC Replacement Compatibility**: When `PCRumah` is purchased in BS-11, `PhoneFast` remains on the desk as an inert decorative keepsake, while `PCRumah` takes over all productive post generation.

---

## 5. Visual Quality Assessment & Acceptance Criteria

- **Current Visual Quality**: High modern smartphone aesthetic that cleanly contrasts with the bulky, obsolete OldCRT terminal.
- **Identified Inconsistencies**: Handheld scale is proportionally smaller than desk prop (finding V-01); addressed via documented ergonomic rationale.
- **Recommended Adjustments**: None required for V0/M1 baseline.
- **Visual Acceptance Status**: **ACCEPTED (Technical & Architectural)**; Commercial human art sign-off pending.
