# 05 — CHARACTER SYSTEM & ANIMATION LANGUAGE

> **Document Status**: Authoritative Technical Standard  
> **Parent Document**: [`docs/DESIGN.md`](../DESIGN.md)

---

## 1. Avatar-to-Equipment Interaction System (Audited BS-09 Implementation)

*Buzzer Simulator* implements a procedural, client-side handheld device system managed by `src/client/PhoneEquipController.luau`. It supports both modern Roblox **R15** avatar rigs and legacy **R6** rigs without requiring uploaded animation asset IDs or external asset dependencies.

### 1.1. Ergonomic Grip Positioning & Welding
Held phone models are welded dynamically to the avatar's right hand/arm:

```
+---------------------------------------------------------------------------------------+
|                               PROCEDURAL GRIP OFFSETS                                 |
+---------+--------------------+------------------------------------+-------------------+
| Rig     | Target Limb        | Grip CFrame Transform              | Screen Read       |
+---------+--------------------+------------------------------------+-------------------+
| **R15** | `RightHand`        | `CFrame.new(0, -0.25, 0.02) *`     | Faces outward     |
|         |                    | `CFrame.Angles(rad(15), 0, 0)`     | from open palm    |
+---------+--------------------+------------------------------------+-------------------+
| **R6**  | `Right Arm`        | `CFrame.new(0, -0.50, 0.05) *`     | Angled past the   |
|         |                    | `CFrame.Angles(rad(15), 0, 0)`     | lower forearm     |
+---------+--------------------+------------------------------------+-------------------+
```

- **Weld Construction**: A `WeldConstraint` locks the phone’s `PrimaryPart` (`Body`) to the avatar hand.
- **Physical Safety**: All parts of the cosmetic model enforce `Massless = true`, `CanCollide = false`, `CanTouch = false`, and `CanQuery = false` to guarantee that held items never exert torque on character physics, trigger touch events, or interfere with raycasts.

### 1.2. Procedural Arm Posing (Motor6D C0 vs. IKControl)
To position the phone before the player's chest without conflicting with running or walking animations:

1. **Primary Mechanism (Motor6D C0 Offset)**:
   - The controller caches the original `Motor6D.C0` of `RightShoulder` (or `Right Shoulder` in R6).
   - Equipping tweens the shoulder joint C0 additively by `CFrame.Angles(rad(-62), 0, rad(-10))`.
   - Because engine animation clips write to `Motor6D.Transform`, tweening `C0` elevates the arm while allowing native breathing and walking sways to layer naturally underneath.
2. **AvatarJointUpgrade & IKControl Fallback (Rule 25 Compliance)**:
   - In modern R15 rigs utilizing `AvatarJointUpgrade`, procedural `Motor6D.C0` offsets can be overridden each frame by `AnimationConstraint` solvers.
   - When detected, the system activates an `IKControl` solver targeting a chest-height attachment or modulates the `.Transform` property during `RenderStepped` at priority `Enum.RenderPriority.Character.Value + 2`.
   - On unequip, all temporary attachments and IK solvers are cleanly destroyed.

---

## 3. Handheld Equipment Lifecycle & State Machine

```
                   [Character Spawn / Join]
                              |
                              v
                      +---------------+
                      |    STOWED     | <-------------------------+
                      +---------------+                           |
                              |                                   |
                     Click "Equip Phone"                 Click "Stow Phone"
                              |                                   |
                              v                                   |
                      +---------------+                           |
                      |   EQUIPPED    | --------------------------+
                      +---------------+                           |
                       |             ^                            |
       Open CRT Terminal|             | Close CRT Terminal        |
                       v             |                            |
               +---------------+     |                            |
               | AUTO-STOWED   | ----+                            |
               | (Modal Active)|                                  |
               +---------------+                                  |
                       |                                          |
                Character Despawn / Death                         |
                       |                                          |
                       v                                          |
               +---------------+                                  |
               | CLEAN RESET   | ---------------------------------+
               +---------------+
```

### 3.1. Equip & Use Timings
- **Equip Transition**: $0.28\text{ seconds}$ `TweenInfo` (Quad Out). Smoothly raises arm and reveals handheld model.
- **Publish Action Flourish**: $0.70\text{ seconds}$ `TweenInfo`. Triggers a brief additive pose dip `CFrame.Angles(rad(-14), 0, 0)` when publishing a post, giving tactile feedback that the phone was tapped.
- **Docked Desk Phone Concealment**: When equipped, the stationary phone at `PhoneSlot` is hidden using `LocalTransparencyModifier = 1` on client descendants. Unequipping restores `LocalTransparencyModifier = 0`. Server prefabs are never touched.

### 3.2. Modal Stowing vs. Equip Intent Isolation
To prevent modal UI interactions from destroying player intent:
- The controller maintains two distinct boolean flags: `_preferEquipped` (player intent) and `_modalOpen` (terminal state).
- When approaching the CRT terminal and opening BuzzerOS:
  1. The controller immediately stows the handheld phone, restores shoulder C0, and unhides the docked phone.
  2. The player's camera smoothly pans to the terminal.
  3. When BuzzerOS is closed, the controller checks `_preferEquipped`. If true, the phone automatically re-equips without requiring a second manual keypress.

### 3.3. Respawn & Cleanup Hygiene
- A monotonic generation token (`_lifecycleGen += 1`) increments on every equip, unequip, respawn, or character removal.
- Any delayed tween callback checks `token == currentToken`. If the character died or re-equipped mid-tween, stale callbacks abort immediately, preventing orphaned models or permanent arm-pose locks.
- On character death, `_preferEquipped` is explicitly reset to `false`, ensuring fresh spawns always begin in a clean, stowed posture.

### 3.4. Accessibility & Reduced Motion
- The controller queries `GuiService.ReducedMotionEnabled`.
- When active, all joint tweens are bypassed; the arm snaps instantly to target poses without easing motion, preventing motion sickness.

---

## 4. Future Character Standards (Trainee Staff & NPCs — BS-12/13)

The upcoming trainee staff system must comply with the following character art guidelines:

1. **Stylized Proportions**: Trainees must use standard Roblox R15 proportions. Extreme character bundle scaling (e.g. gigantic heads or hyper-elongated limbs) is prohibited.
2. **Restrained Facial Detail**: Simple, friendly, stylized low-poly faces. Avoid uncanny realistic eyes or complex dynamic facial rigs.
3. **Posture & Silhouette**:
   - Upright, focused sitting posture at the trainee desks.
   - Arms positioned naturally above keyboards.
4. **Subtle Work Cycles**:
   - Short, readable ambient animation loops (3–5 seconds): rhythmic typing on keycaps, resting hand on mouse, occasional head glance toward the monitor.
   - No exaggerated cartoon jumps, flailing arms, or rapid fidgeting that distracts the player from their own workstation.
5. **Client-Side Simulation**: Trainee character rigs and animations must run 100% on the client. The server tracks only numeric worker counts and Cuan/second accrual rates. Server-side animation controllers or physics instances are strictly forbidden.
