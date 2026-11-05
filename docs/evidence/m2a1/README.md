# M2-A1 Gang Melati blockout: review evidence

Isolated review only. Nothing here is published, mapped into `default.project.json`,
or connected to services, prompts, DataStore or economy.

## How it was produced

```
python tools/gen_city_prefabs.py                 # assets/world/city/*.rbxmx + city-manifest.json
python tools/check_city_prefabs.py               # static contract checks (determinism, anchors, bounds)
rojo build tools/review/m2a1-city-review.project.json -o %TEMP%\M2A1CityReview.rbxlx
# open that file in Studio, then:
python tools/review/studio_review.py luau tools/review/assemble_city_review.luau Edit
python tools/review/studio_review.py luau tools/review/integrity_probe.luau Edit
python tools/review/studio_review.py start_stop_play "{\"is_start\": true}"
python tools/review/studio_review.py luau tools/review/walk_probe.luau Server
python tools/review/studio_review.py shot <id> <out.png> "<camera xyz>" "<look-at xyz>"
```

`studio_review.py` refuses to act unless exactly one open Studio is `M2A1CityReview`.
Each zone is cloned once and placed with `PivotTo(CFrame.new(origin))`. Prefab geometry
is local to that origin. `ReviewSpawn` and `ReviewOuterGround` are review scaffolding
created by the assembler. They are not in any prefab or count.

## Measured in Studio (review place, 2026-11-05)

| Item | Value | Source |
|---|---|---|
| Assembled city BaseParts | **289** (cap 450) | assembler + integrity probe |
| Per zone | House 73, Street 62, TownCenter 96, Boards 21, Gate 19, Backdrop 8, City_Anchors 10 | integrity probe |
| Anchored | 289 / 289 | assembler |
| Scripts in city | 0 | assembler |
| PointLights | 7 (cap 8), all `Shadows = false` | manifest |
| Anchor identities | 11 expected, each present once at exact position, 0 issues | integrity probe |
| Spawn box (8×5×8 at `City_Spawn`) | only collidable: `City_HomeDoor` (4 studs north, by contract) | integrity probe |
| Ground probe | 192 rays, x ∈ {-10,-6,0,6}, z 17…158 (kiosk pad and fountain body excluded): 0 gaps or off-grade hits | integrity probe |
| Walk, `City_Spawn` → fountain apron (r 16), real avatar, `WalkSpeed 16` | **5.65 s** over 4 MoveTo legs, all reached; + 0.25 s door→spawn | walk probe |
| `StreamingEnabled` | `false` (review place built by Rojo; read, not inferred) | integrity probe |
| Lighting | `ClockTime 14`, `Brightness 1` (Studio defaults; no lighting change) | integrity probe |
| Frame rate | **NOT MEASURED** | — |

## Captures (desktop Studio viewport, fixed camera poses via `screen_capture`)

| File | Pose (camera → look-at) | Observation |
|---|---|---|
| `overview-aerial.png` | (-90,120,-40) → (0,0,90) | full layout, house → lane → plaza → gate |
| `C1-window-skyline-baseline.png` | `CameraFocus` (7,5.5,3) → window | **FAIL**: window shows ground/horizon, no skyline (baseline X 16…160) |
| `C1-window-skyline-centered-PROPOSED.png` | same | skyline blocks visible inside the aperture (X -120…120 review copy) |
| `C1-wide-centered-PROPOSED.png` | (0,10,30) → (0,20,-152) | tower/blocks rise above the house parapet |
| `C2-interior-door-approach.png` | (0,5.5,6) → frozen `Door` | interior unchanged; host marker invisible as specified |
| `C3-first-exterior-arrival.png` | `City_Spawn` (-6,4.5,20) → plaza | gapura, kiosk, plaza and lamps read down the lane |
| `C4-residential-lane.png` | (0,5,44) → plaza | fountain visible through the kiosk bay below the sign band |
| `C5-mission-kiosk.png` | (0,5,58) → kiosk | "PAPAN MISI" legible; fountain visible through the 4-stud opening |
| `C6-town-centre-fountain.png` | (0,5,84) → (0,0,112) | basin ring, apron, benches, warnet and warung frame the plaza |
| `C7-east-lot-reserved.png` | (50,5,108) → (68,0,108) | hedge reservation only; shops are M2-B. P5 **NOT TESTABLE** in A1 |
| `C8-future-gate.png` | (0,5,150) → gate | closed shutter, "DISTRIK BARU / Belum dibuka", no opening |
| `C9-return-home.png` | (-6,4.5,24) → `City_HomeDoor` | sage exterior leaf, B1 returns, canopy, house number |
| `house-exterior-oblique.png` | (14,9,34) → house | shell, parapet, AC unit, dish, yard tree |

## Fixed during Studio review

- Sign text clipped behind kiosk posts and the house-number plate: text is now inset per sign.
- UDim2 offsets were serialized as floats, which Rojo rejected. They are now int32.
- The relaunched Studio returned blank frames when its window was not in the foreground.
  The capture helper now brings the window forward and rejects frames with fewer than 20 grey tones.
- The anchors folder reached `Workspace.City` as `CityAnchors`. The assembler now names it `City_Anchors`.

## Not run or blocked

- **Mobile 640×360 / 360×640.** I tried by resizing the Studio window. `screen_capture` still
  returned 1226×642 frames, so those files were deleted and are not claimed. Use the
  Device Emulator during M2-G2 review.
- **Stock orbit-camera clipping** at the door, roof and plaza. The captures use fixed camera poses, not the
  character camera. Needs a manual Play-mode check.
- **Streaming toggle (T7).** The review place has `StreamingEnabled = false`. Atomic/Persistent are
  authored, but streaming behaviour is not observed.
- **Frame rate**, device performance and P5 shop reachability.
