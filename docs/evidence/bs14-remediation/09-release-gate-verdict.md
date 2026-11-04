# BS-14 RC-1 — Release Gate Verdict

**Document ID:** REL-BS14-RC1-REMEDIATION-20261104
**Supersedes:** `docs/evidence/bs14/RELEASE-CANDIDATE-BS14.md` (kept in Git history for audit)
**Candidate:** `fa55baa4a417097b6d4f8a032c602bcf1c1df19e` + branch `agent/BS-14-rc1-evidence-remediation`
**Build under review:** `build/BuzzerSimulator.rbxlx` sha256 `9c8c431d28a1e2347c08cda76450a129071c7166f1bf9ab08f7b7bc30ed3e833`
**Reviewed:** 2026-11-04

---

## 1. Verdict

# BLOCKED — CLOSED BETA NOT AUTHORIZED

The candidate is not released, published, or merged. Three mandatory release proofs do not exist: cloud DataStore behaviour, physical-device behaviour, and human usability. A fourth — rollback — is documented but has never been rehearsed. No release authority is delegated to the agent that produced this report.

What *is* true: the code is stable on its own terms. The full Luau suite passes untruncated (20 suites, 748 runtime tests, 0 failures), the connected economy behaves exactly as specified over a real 20 minutes (3.0 Cuan/s, 40 banking commits, no save failures), and the server-boundary security probes pass 10/10. That is a solid foundation — it is simply not the same thing as a closed-beta green light.

---

## 2. Gate matrix

| Gate | Required proof | Status | Basis |
| :-- | :-- | :-- | :-- |
| **G0** | Static build, regression, executable assertions | **PASS** | 20/20 suites, 748 tests, runId `1fbf063e-…`, untruncated console (511 lines) |
| **G1** | Connected client/server gameplay | **PASS** | automated journey through `StudioClientBridge → NetRouter → SessionService`: 0 → tier 2, 2 desks, 2 trainees in 15 min, plus the 20-minute idle session |
| **G2** | Real cloud DataStore safety and rejoin | **BLOCKED** | no published staging universe, no API access, no authorization to publish; local Studio logs `DEV_FALLBACK` and states "Real DataStore G2 remains OPEN" |
| **G3** | UI/art and Studio viewport checks | **BLOCKED** | Studio viewport checks pass at measured viewports (0 touch-target failures across 6 profiles), but no row matched its labelled resolution and no device pixels exist. `assets/ASSET-MANIFEST.md:199-203` independently records that human art approval is still pending |
| **G4** | M1 economy, workers, chapter completion | **PASS** | desk/hire prices and 1.5 Cuan/s per worker verified live; 3.0 Cuan/s at two workers measured over 1,201.8 s |
| **G5** | Real device, human playtest, reliability, rollback | **BLOCKED** | no physical Android device, no participants, rollback unrehearsed |

The previous document reported G0–G5 all green, including "DataStore Resilience 7/7" (an injected adapter) and "Mobile Usability 5/5" (server Heartbeat FPS at mislabeled viewports). Those classifications were wrong; see `01-source-evidence-reconciliation.md` for all 17 corrected claims.

---

## 3. Independent classifications

| Area | Status | Detail |
| :-- | :-- | :-- |
| 20-minute connected idle | **PASS** | 3,615 Cuan vs 3,600 expected; 40 commits; `healthy` 41/41; memory **not measured** |
| DataStore write-pressure | **NOT TESTED** | requires cloud; the earlier "stress simulation" was an in-memory adapter |
| Security (server boundary) | **PASS** | 10/10 probes; settlement/lease/concurrency cases rest on the spec suite |
| Physical mobile | **BLOCKED** | no device, no ADB, no published build |
| Human uncoached testing | **BLOCKED** | no participants |
| Rollback rehearsal | **BLOCKED (PLANNED — NOT VERIFIED)** | levers audited; none rehearsed; two previously documented levers do not exist |

---

## 4. Defects found and their disposition

| # | Finding | Type | Action |
| :-- | :-- | :-- | :-- |
| D1 | Release report claimed schema v2, DataStore `BuzzerProfile_v1`, offline accrual, two nonexistent kill switches, and a security probe set that was never executed | **Evidence/reporting** | corrected in `01-…`, `07-…`, `08-…`; no product change |
| D2 | `g0-regression-raw.txt` began with a truncation marker | **Evidence** | superseded by an untruncated rerun |
| D3 | `idle-live-console.txt` ended in a traceback; no idle gate ever ran | **Evidence** | new 20-minute run executed; harness rebuilt |
| D4 | `playtest-journey.json` milestones 0–10 carried hardcoded timestamps and payouts | **Evidence** | re-derived from live snapshots |
| D5 | "59.9 FPS" was a server Heartbeat estimate | **Evidence** | reclassified; device FPS remains unmeasured |
| D6 | Old idle harness raised on the first `sent:false`, with no retry or diagnosis | **Harness** | rebuilt with retry/backoff and refusal diagnosis; root cause is the client's own anti-double-submit gate |
| D7 | Buy-device order is enforced (`phone_fast` before `pc_rumah`); a skipped device is refused `NOT_READY` | **Product rule, correct** | harness corrected; rule documented |
| D8 | Economy sim agrees with `docs/04` on 25/33 pacing targets (8 deltas, all slightly earlier) | **Docs drift** | reported, not reconciled; acceptance criteria untouched |

**No production defect was confirmed.** No file under `src/` was modified in this remediation. The only code written is verification tooling under `tools/agent/`.

---

## 5. Remaining release risks

| Rank | Risk | Impact | Mitigation now | Required before release |
| :-- | :-- | :-- | :-- | :-- |
| **P0** | Zero cloud persistence evidence for this exact candidate | Profile loss or duplication on first real players; the failure mode is silent and mass-affecting | none possible locally | run the 17-case G2 matrix on a staging universe (layer C then D) |
| **P0** | The previous certification was false and could have been acted on | Releasing on fabricated green gates | this report + corrections | director must formally withdraw the prior GO |
| **P1** | No kill switch for accrual/purchases | An economy exploit cannot be stopped without a full rebuild + republish | place-version rollback (unrehearsed) | either rehearse rollback or design a reviewed runtime control |
| **P1** | Small-height layout unproven (dashboard overflows top at 296×156 viewport) | Possible unreachable controls on landscape phones | none | 640×360 real-device check |
| **P1** | Camera open/close/death recovery not re-run (Phase 6 item 9) | Player stuck with wrong camera after closing the desktop | none | scripted camera assertions in Play mode |
| **P2** | `docs/04` pacing targets drift from the model (8 deltas) | Design conversations use slightly stale numbers | reported | reconcile design doc deliberately |
| **P2** | Memory growth unmeasured during idle | Unknown leak risk | none | 20-minute memory sampling on device/staging |

---

## 6. Recommended director action

1. **Do not open closed beta** on this candidate.
2. Withdraw the previous "RELEASE READY" certification formally, referencing this document.
3. Authorize a staging universe and a publish, then commission the G2 matrix (`03-datastore-g2-matrix.md` §5) — this is the single highest-value unblock, because persistence is the only failure mode here that can hurt real players at scale.
4. Authorize one physical Android device and 3–5 uncoached testers; run `04-real-device-report.md` §5 and `05-human-playtest-observations.md` §3.
5. Rehearse place-version rollback once, on staging, before any public exposure.
6. Re-review G2/G3/G5 only after 3–5 pass; G0/G1/G4 need no further work.

Re-run commands are recorded in each artifact; `candidate-manifest.json` pins the artifact hashes so a later run can prove it tested the same build.

---

## 7. Sign-off

Prepared by: verification agent (no release authority)
Date: 2026-11-04
Decision: **BLOCKED — CLOSED BETA NOT AUTHORIZED**
