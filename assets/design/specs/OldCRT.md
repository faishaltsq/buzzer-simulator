# ASSET SPECIFICATION: OLD CRT TERMINAL

> **Asset File**: `assets/world/OldCRT.rbxmx`  
> **Generator Script**: `tools/gen_world_prefabs.py` (`build_old_crt`)  
> **Parent Document**: [`docs/DESIGN.md`](../../../docs/DESIGN.md)

---

## 1. Asset Metadata & Purpose

- **Asset Name**: `OldCRT`
- **File Path**: `assets/world/OldCRT.rbxmx`
- **Gameplay Purpose**: Physical access terminal for BuzzerOS. Houses no production multiplier and awards zero currency (0.0x yield). Serves as the primary focal point of the player's workspace until replaced by `PCRumah` in BS-11.
- **Ownership**: Server-owned. Cloned per player into `Workspace.BuzzerRoom_<UserId>` and mounted at `TerminalSlot` with a 180° rotation around Y.
- **Parent Hierarchy in Studio**:
  ```
  Workspace
  └── BuzzerRoom_<UserId> (Folder)
      └── OldCRT (Model)
          ├── MonitorBody (Part, PrimaryPart)
          ├── UpperShell, TubeHousing, TubeRear
          ├── StandNeck, StandBase, Bezel
          ├── ScreenRecess, Screen, ScreenHighlight
          ├── PowerButton, PowerLED, ServiceSticker, Scuff
          ├── KeyboardBase, Spacebar, Keycap (x24)
          ├── Vent (x8: 4 per side)
          ├── ScreenRule, ScreenLine (x2), ScreenCursor
          └── Screen
              └── BuzzerOSScreen (SurfaceGui)
                  └── Title (TextLabel: "BuzzerOS")
  ```

---

## 2. Geometric & Physical Properties

- **Overall Dimensions**: $3.10\text{ studs (W)} \times 2.80\text{ studs (H)} \times 2.80\text{ studs (D)}$ (including keyboard).
- **Model Pivot**: Positioned at local $(0, 1.40, 0)$. In room space, placed at $Y = 3.35 + 1.40 = 4.75$ studs.
- **PrimaryPart**: `MonitorBody` (`referent = "RBX156"`).
- **Total BasePart Count**: **Exactly 52 BaseParts**.
- **Embedded Scripts / Remotes**: **Exactly 0**.
- **Physical Collision Profile**:
  - `MonitorBody`, `StandBase`, and `KeyboardBase` enforce `CanCollide = true`.
  - Keys, screen face, bezel, vents, and detail decals enforce `CanCollide = false`.
  - All parts enforce `Anchored = true`.

---

## 3. Materials, Palette & Typography

- **Roblox Materials Used**:
  - `SmoothPlastic`: Primary material for monitor casing, bezel, screen glass, keyboard base, and keycaps.
  - `Metal`: Screen highlight and bezel trim.
- **Color Palette Breakdown**:
  - Monitor Chassis & Bezel: `cream` (`#E9DEC7`), `linen` (`#F6ECD8`), `plaster` (`#DBD3BE`).
  - Cathode Ray Tube Recess: `ink` (`#202A2D`).
  - Cathode Screen Face: `screen` (`#273F3E`).
  - Terminal Graphics & Text: `phosphor` (`#B1CEA6`).
  - Keyboard Base & Keycaps: `plaster` (`#DBD3BE`), `linen` (`#F6ECD8`), `cream` (`#E9DEC7`).
  - Accents & Vents: `wood_dark` (`#654A37`), `sage` (`#84977E`).
- **Embedded SurfaceGui Specification**:
  - Name: `BuzzerOSScreen` on Face `Enum.NormalId.Back` (Faces local $-Z$).
  - `CanvasSize`: $512 \times 320$ pixels.
  - `LightInfluence`: `1.0` (smoothly responds to room lighting).
  - `AlwaysOnTop`: `false` (properly occluded by character or obstacles in world space).
  - Text Label: `"BuzzerOS"`, Font `Enum.Font.GothamMedium`, TextColor3 `phosphor` (`#B1CEA6`), TextSize 42. Contrast ratio: 6.56:1 (WCAG AA Pass).

---

## 4. Interaction & Boundary Contracts

- **ProximityPrompt Isolation**: `OldCRT.rbxmx` contains **no ProximityPrompt**. The interactive prompt lives on the room-owned `DashboardPromptAnchor` at $(7.4, 3.6, -2.4)$. This guarantees that when OldCRT is replaced by PC Rumah in BS-11, the prompt instance and server event connections remain undisturbed.
- **Screen Readability**: The 180° Y rotation applied by `WorldService.luau` ensures the screen faces directly toward $+Z$ (the approaching player).
- **Desktop Footprint**: Fits cleanly within `TerminalSlot` bounding box $(3.0 \times 0.2 \times 2.6\text{ studs})$ without overlapping `PhoneSlot` $(4.6, 3.35, -3.8)$.

---

## 5. Visual Quality Assessment & Acceptance Criteria

- **Current Visual Quality**: High nostalgic authenticity. The bulging rear tube housing and separated mechanical keyboard provide an unmistakable silhouette that reads clearly from spawn.
- **Identified Inconsistencies**: At long distances (12+ studs), the on-screen `"BuzzerOS"` text resolution drops, but the physical prompt provides immediate gameplay clarity (finding V-05).
- **Recommended Adjustments**: None required for V0/M1 baseline; model satisfies all technical and aesthetic acceptance criteria.
- **Visual Acceptance Status**: **ACCEPTED (Technical & Architectural)**; Commercial human art sign-off pending.
