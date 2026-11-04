# BS-14 RC-1 — Real Device Report

**Candidate:** `fa55baa` + `agent/BS-14-rc1-evidence-remediation`
**Date:** 2026-11-04
**Gate status:** **BLOCKED** — no physical Android device, no authorized playable build.

---

## 1. Environment inventory (measured, not assumed)

| Item | Value | How checked |
| :-- | :-- | :-- |
| Physical Android device attached | **none** | no ADB bridge present (`adb` not installed), no Android PnP device enumerated |
| Android emulator available | AVD `Pixel_10_Pro` exists | `emulator.exe -list-avds` |
| Roblox Android client on that AVD | unknown / not verified | no ADB, cannot inspect packages |
| Published build joinable by a device | **none** | publishing is out of scope for this task |
| Roblox Studio | `version-7062aec9dbe74b14` | `$LOCALAPPDATA/Roblox/Versions` |

A viewport audit inside Studio is **emulator evidence about layout**, not device evidence about performance. The two must not be conflated, which is exactly the defect this report corrects.

---

## 2. Correction: the 59.9 FPS figure is not a client measurement

The previous report listed "Average Frame Rate: 59.9 FPS" under mobile performance (`RELEASE-CANDIDATE-BS14.md:129`).

`tools/agent/run_mobile_profiling.py:238-267` computes it as:

```lua
local startClock = os.clock()
for i = 1, 60 do
    local dt = RunService.Heartbeat:Wait()
    table.insert(frameTimes, dt)
end
local totalTime = os.clock() - startClock
local avgFps = 60 / totalTime
```

executed with `datamodel_type: "Server"`. That is a **server Heartbeat scheduling estimate inside Studio Play mode**. It cannot observe GPU frame time, thermals, or the Android client's renderer.

**Correct classification:** "Studio simulation heartbeat estimate — 59.9 FPS avg / 49.7 min over 60 heartbeats (server-side, not client rendering)." It is a weak signal that the Studio simulation was not starved; it is not a mobile performance result and must not gate a mobile release claim.

---

## 3. Correction: the tablet row

Previous claim (`:113`): "Tablet Portrait 768×1024 — Native Floating Window, 0 violations."

Recorded artifact (`docs/evidence/bs14/mobile-profiling.json`):

| Field | Value |
| :-- | :-- |
| Row name | `Tablet Landscape (768x1024)` — portrait resolution, landscape label |
| Measured `viewport` | **724 × 544** |
| `target_mode` | `wide` |
| Actual mode | compact |
| `modeMatch` | **false** |

Two separate problems:

1. **Label vs measurement.** The harness resizes the Studio *window* via `win32gui.MoveWindow` (`:129-137`) and then reads `workspace.CurrentCamera.ViewportSize`. On this host a 768×1024 window yielded a 724×544 viewport, so the row never represented a 768-wide screen.
2. **Mode decision input.** Compact/wide is decided from the dashboard window's `AbsoluteSize` (`:157`), not from the screen. A 651×427 floating window is therefore *correctly* compact — the `false` is not proof of a UI defect.

**What is actually unproven:** behaviour at a true 768 px-wide viewport in portrait. The fresh audit (`04-studio-viewport-audit.json`) records the viewport that was actually measured for every profile and flags where the label did not match reality, instead of asserting the requested resolution.

---

## 3a. Fresh Studio viewport audit (measured 2026-11-04)

`tools/agent/bs14_rc_viewports.py` resized the Studio window and read `Camera.ViewportSize`, the dashboard's `AbsoluteSize`/`AbsolutePosition`, and every visible `GuiButton`'s real size.

| Requested window | Actual window | Measured viewport | Dashboard size | Dashboard pos | Mode | Nav | Targets (fails) | Label matched? |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| 360×640 | 656×640 | **296×234** | 280×240 | (8, **−32**) | compact | MobileNav | 8 (0) | no |
| 390×844 | 656×844 | **296×438** | 280×334 | (8, 23) | compact | MobileNav | 8 (0) | no |
| 640×360 | 656×559 | **296×156** | 280×240 | (8, **−71**) | compact | MobileNav | 8 (0) | no |
| 768×1024 | 768×1024 | **342×618** | 308×493 | (17, 34) | compact | MobileNav | 8 (0) | no |
| 1280×720 | 1280×720 | **854×314** | 769×240 | (43, 8) | compact | MobileNav | 8 (0) | no |
| 1920×1080 | 1920×1080 | **1494×674** | 1100×542 | (197, 37) | wide | NavRail | 10 (0) | no |

Findings:

1. **Window resizing cannot reach phone widths on this host.** Studio enforces a ~656 px minimum outer width, and docked panels consume the rest, so a 360–640 px request produced 296 px viewports. No row matched its label — the same defect class as the old tablet row, now measured instead of asserted.
2. **Layout behaves consistently across 296→1494 px viewports:** compact mode shows `MobileNav`, wide mode shows `NavRail`, and **no touch target fell below 40×40 in any profile** (0 failures across 52 evaluated buttons).
3. **Risk flag, not a proven defect:** at the two smallest viewports (296×234 and 296×156) the dashboard window's `AbsolutePosition.Y` is **negative** (−32, −71), i.e. it is laid out taller than the viewport and clipped at the top. Those viewports are smaller than any real phone, so this cannot be called a device bug — but it means small-height clamping is not proven, and a real 640×360 landscape phone is exactly the case that must be tested on hardware.

The audit cannot substitute for device testing: it measures Studio pixels, not device pixels, and it never sends a touch.


---

## 4. What the Studio viewport audit can and cannot establish

| Question | Studio audit | Real device |
| :-- | :-- | :-- |
| Does the layout switch compact/wide at the right threshold? | yes, at measured viewports | only at the device's real DPI |
| Do touch targets reach 40–44 px in real pixels? | yes, in Studio pixels | **no** — DPI scaling differs on device |
| Safe-area / notch handling | no | required |
| Posting, claiming, buying, hiring by touch | no (programmatic bridge only) | required |
| Frame time, memory trend, thermals | no | required |
| Orientation change and camera restoration | partially | required |
| Two trainee rigs visible and animated | partially (scene inspection) | required |

---

## 5. Required real-device matrix — status

| Test | Status | Prerequisite |
| :-- | :-- | :-- |
| Launch through the real Roblox Android client | **BLOCKED** | published build + signed-in device/emulator |
| Record phone model, OS build, graphics quality | **BLOCKED** | above |
| Client-side FPS / frame-time over 10 minutes | **BLOCKED** | above |
| Memory trend under sustained play | **BLOCKED** | above |
| Navigation, posting, claiming, buying, hiring by touch | **BLOCKED** | above |
| Two trainee rigs render and animate | **BLOCKED** | above |
| Camera restore after desktop close and after death | **BLOCKED** | above |
| Orientation change / safe-area on a notched device | **BLOCKED** | above |
| Genuine device screen capture | **BLOCKED** | above |

No screenshot, frame rate, memory figure, or device observation in this repository was produced on a physical device, and none may be presented as if it were.

---

## 6. Minimum unblocking procedure

1. Publish the candidate to a staging universe (see `03-datastore-g2-matrix.md` §5).
2. Install the Roblox Android client on a physical device and sign in with an authorized account.
3. Record: device model, OS version, RAM, Roblox graphics quality level, and build identity.
4. Run the matrix in §5, capturing a real screen recording per interaction class.
5. Capture client FPS with the Roblox in-experience performance overlay or an equivalent client-side measurement — never a server Heartbeat estimate.

Until steps 1–5 exist, G5 cannot pass on mobile grounds and the physical-device gate stays BLOCKED.
