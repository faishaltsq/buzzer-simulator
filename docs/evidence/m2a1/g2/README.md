# M2-G2 final Studio acceptance review

**M2-G2 PARTIAL — SPECIFIC EVIDENCE MISSING**

Review scope: existing isolated `M2A1CityReview.rbxlx`, real avatar, normal Roblox Custom camera. No production geometry, gameplay services, prompts, economy, DataStore, or parent blueprint changed. No M2-A2 work and no automatic merge.

## 1. Normal player camera

Six-stop orbit/zoom pass: porch, lane, arch, kiosk, plaza, return. The harness uses character navigation, held arrow keys and scroll input; it does not assign camera CFrame. Follow distance is reset between stops; zoom-in/out are requested scroll steps, not proof the minimum/maximum distance was reached.

**Verdict: unresolved overlap concern, not an unconditional PASS.** Retained desktop captures show navigable views, but camera-centre bounds overlap occurs near the house and kiosk during orbit. `player-camera/cam-log.txt` contains measurements. The corrected logger transforms positions into each part's local axes. Bounds overlap is not a substitute for visual confirmation of a see-through wall or a trapped camera.

A focused smoke run of the corrected logger observed 6 overlap frames in 116 frames, maximum local bounds depth 0.0762 studs near the porch. It recorded wall and door positions rather than silently discarding sample errors. The full six-stop log records the longer pass separately. No millimetre conversion or arbitrary harmless-depth threshold is asserted.

The previous draft incorrectly dismissed all overlap as an artifact. It also cited a 120-sample yaw matrix whose ad-hoc script did not actually turn the camera between its labelled samples. That draft and those conclusions are withdrawn. `clip-probe.txt` is historical diagnostic output, **not acceptance evidence**. Its faulty throwaway generators were removed.

## 2. Genuine Studio mobile simulation

API: `StudioDeviceSimulatorService`; dynamically discovered iPhone 7 preset, native resolution override 640×360, ActualResolution scaling. Landscape screenshot and camera viewport both measured 640×360. Portrait screenshot and camera viewport both measured 360×640. No image resizing.

The isolated place's default orientation is LandscapeSensor. Portrait was explicitly forced on the review client's `PlayerGui.ScreenOrientation`; this does not change production orientation support.

| Checkpoint | Landscape | Portrait | Visual observation |
|---|---|---|---|
| First exterior arrival | `mobile-landscape-arrival.jpg` | `mobile-portrait-arrival.jpg` | Real avatar, street and arch visible |
| Residential lane | `mobile-landscape-lane.jpg` | `mobile-portrait-lane.jpg` | Arch and onward route visible; portrait naturally narrows lateral coverage |
| Mission kiosk | `mobile-landscape-kiosk.jpg` | `mobile-portrait-kiosk.jpg` | Kiosk stands beside avatar; portrait approach crops part of the left-side sign, so full sign readability is not a PASS from this angle |
| Plaza fountain | `mobile-landscape-plaza.jpg` | `mobile-portrait-plaza.jpg` | Fountain and approach ground visible |
| House return | `mobile-landscape-return.jpg` | `mobile-portrait-return.jpg` | House door visible after ordinary camera rotation |

These are blockout views, not functional city-interaction tests: functional prompts remain outside M2-A1 scope. An initial navigation request to the already occupied landscape spawn returned no route; arrival was captured from the actual fresh spawn. The subsequent navigation requests succeeded. Blank intermediate captures were replaced after foreground activation; only inspected captures are cited above.

## 3. Actual client frame performance

Foreground Studio Play client, Automatic quality, StreamingEnabled=true. Sampling was installed on the client RenderStepped loop, while the external driver navigated four route checkpoints and rotated the normal camera using keyboard input. The probe did not write camera CFrame. It also sampled `Stats.FrameTime`, converting seconds to milliseconds correctly.

Source: `simulator-runtime.json`. Sample duration includes route navigation and a final approximately eight-second foreground hold. Results are Studio simulator results, **not physical Android/iOS measurements or GPU-only timings**.

| Metric | Landscape 640×360 | Portrait 360×640 |
|---|---:|---:|
| Duration (s) | 26.03 | 25.61 |
| Render samples | 1559 | 1534 |
| Average FPS | 59.89 | 59.89 |
| p50 frame time (ms) | 16.67 | 16.68 |
| p95 frame time (ms) | 17.89 | 17.75 |
| p99 frame time (ms) | 18.26 | 18.40 |
| Worst render interval (ms) | 82.06 | 59.23 |
| Intervals longer than 1/30 s | 1 | 4 |
| Intervals longer than 100 ms | 0 | 0 |
| Worst Stats.FrameTime (ms) | 82.17 | 59.28 |

The worst observed **timed interval** is reported; subjective visual severity was not independently measured with video. Earlier unfocused runs near 15 Hz are not used to establish city cost or a performance failure. There is no physical-device evidence and no claim that city rendering has zero cost.

## 4. Cold-start streaming review

StreamingEnabled was set in **Edit before Play**, in the isolated review instance only. The mobile sessions then started with streaming enabled, rather than relying on a live server toggle of already-resident geometry.

| Model | Authored ModelStreamingMode | Client BaseParts observed |
|---|---|---:|
| HouseExterior | Atomic | 73 |
| StreetBlock | Atomic | 62 |
| TownCenter | Atomic | 96 |
| CityBoards | Atomic | 21 |
| CityGate | Atomic | 19 |
| CityBackdrop / centered review variant | Persistent | 8 |

The landscape route observed the full per-zone counts at all five checkpoints. The centered variant was separately cold-started with streaming enabled and its complete 8-part Persistent model was observed in the bedroom client. Anchor folder contributes 10 parts outside these six models, for 289 total. The inspected mobile views did not show partial-zone geometry.

**Limit:** default streaming target radius is 1024, larger than this city route. This is a cold-start/local traversal observation, not a forced stream-out/re-entry or adverse-network stress test. The earlier claim that streaming mode APIs were absent was wrong: the correct property is `Model.ModelStreamingMode`.

## 5. D1 skyline decision

The default-camera centered observation (`d1-centered-default-camera.jpg`) was made after a fresh Play start: Custom camera, Humanoid subject, untouched 0.5…400 zoom range, avatar positioned at bedroom floor centre (3,0,0). Camera observed near (3,6.51,11.83). Streaming was enabled and the centered Persistent backdrop was resident.

**Verdict: natural skyline readability through the bedroom window is NOT CONFIRMED.** The image shows a largely flat dark window region, not an unambiguous skyline silhouette. A tower above the roofline is not proof of visibility through the window. Earlier adjusted-zoom captures (`d1-*-window-player.png`) remain historical comparisons only, not proof of the required natural-camera criterion.

Static checker result: baseline 0%, centered 93% analytic aperture coverage. The checker explicitly labels that a 2D estimate, not Studio visual evidence. Raycast misses alone also do not prove visibility; nonqueryable decorative parts and intervening walls must be considered.

### Minimal D1 amendment proposal (not applied)

If the director accepts a clear natural-camera comparison, amend only the backdrop coordinate/extent contract from baseline X 16…160 (origin 88,0,-152) to the existing centered candidate X -120…120 (origin 0,0,-152). This is both a recentering and width increase, not just an 88-stud translation. Preserve `CityBackdrop` and `CityBackdrop_CenteredReview` as separate review variants until approval. Do not alter the parent blueprint, geometry budget, or production mappings in this QA pass. **Recommendation: keep centered as the preferred proposal, but do not approve D1 solely on the current images.**

## 6. Focused fixes and verification

Only review tooling changed:

- StudioMCP subprocess streams explicitly use UTF-8. Native skill documentation otherwise failed with a Windows cp1252 UnicodeDecodeError.
- Camera logger uses part-local axes and retains sample positions/depth instead of asserting harmless clipping.
- Frame probe no longer writes camera CFrame; engine frame times are converted to ms.
- Capture helper supports live player-camera capture without fixed pose overrides.

Verification exercised:

- `python tools/check_city_prefabs.py`: **1467 passed, 0 failed**, 289 BaseParts, 7 PointLights.
- `rojo build tools/review/m2a1-city-review.project.json -o .../M2G2Verified.rbxlx`: success.
- `rojo build default.project.json -o .../M2G2ProductionBuild.rbxlx`: success.
- Corrected camera logger installed and executed in a fresh real Play client; six-stop pass exercised.
- Corrected frame probe executed on both actual simulator orientations; results in `simulator-runtime.json`.
- Existing 748 gameplay regression results belong to the prior M2-A1 evidence and were **not rerun or re-claimed** in this continuation; no gameplay source changed.

The 36 `player-camera/*-*.png` files contain JPEG payloads under the inherited capture harness's legacy extension; the new mobile and D1 images use `.jpg`. All 36 desktop frames were inspected as a contact sheet. Their sampled views are not a video of every overlap frame, so they do not close the visual-severity question.

Streaming observations are retained in `streaming-runtime.json`. After capture, Play was stopped, the device simulator returned to its default viewport, and the isolated editor was restored to baseline backdrop with StreamingEnabled=false.

No city geometry fix was made because a critical visual defect has not been established by the retained images. A small numerical overlap alone is not sufficient justification for changing the accepted blockout.

## 7. Delivery and outstanding acceptance evidence

1. Commit SHA: supplied in the PR update and final handoff.
2. Mobile: actual 640×360 and 360×640 evidence captured at all five requested checkpoints.
3. Player camera: six-stop pass executed; overlap severity needs visual resolution before unconditional acceptance.
4. Performance: foreground Studio client data above; physical-device performance not claimed.
5. Streaming: cold-start enabled, Atomic/Persistent inspected, route counts stable; large-radius limitation documented.
6. D1: conditional centered-coordinate proposal, natural through-window skyline readability still unconfirmed.
7. Remaining issues: orbit overlap visual severity; natural D1 skyline proof; portrait kiosk sign partly cropped from this approach. No critical runtime failure was established.
8. Additional API credit usage: unavailable from this runtime; no invented cost figure.

Final gate remains **M2-G2 PARTIAL — SPECIFIC EVIDENCE MISSING**. Do not merge PR #15 or begin M2-A2 on the basis of this report.
