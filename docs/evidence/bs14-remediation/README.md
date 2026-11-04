# BS-14 RC-1 — Evidence Remediation Bundle

**Candidate:** `fa55baa4a417097b6d4f8a032c602bcf1c1df19e` (PR #9 merge)
**Branch:** `agent/BS-14-rc1-evidence-remediation`
**Date:** 2026-11-04
**Verdict:** **BLOCKED — CLOSED BETA NOT AUTHORIZED** (see `09-release-gate-verdict.md`)

This bundle exists because the previous release report (`docs/evidence/bs14/RELEASE-CANDIDATE-BS14.md`) certified the build as RELEASE READY while several of its gates were mislabelled, unexecuted, or contradicted by the source it cited. The previous document is preserved in Git history and is not edited; this bundle supersedes it.

## Read in this order

| File | Answers |
| :-- | :-- |
| `09-release-gate-verdict.md` | What is the decision, and why |
| `01-source-evidence-reconciliation.md` | Which claims were wrong, and what the source actually says (17 items) |
| `02-idle-20min-analysis.md` | Did the connected idle economy behave, over real time |
| `03-datastore-g2-matrix.md` | What cloud persistence proof exists (none) and what would unblock it |
| `04-real-device-report.md` | What was measured on a device (nothing) vs in Studio (layout only) |
| `05-automated-journey-summary.md` | What the automated journey proves — and what it does not |
| `05-human-playtest-observations.md` | Human usability evidence: none, with the protocol to produce it |
| `06-regression-summary.md` | G0 rerun: 20 suites, 748 tests, 0 failures, untruncated |
| `07-security-results.md` | The ten probes that were actually executed |
| `08-rollback-verification.md` | Real rollback levers; the two documented switches that do not exist |
| `candidate-manifest.json` | Pinned source SHA, build hashes, schema, results, blocked gates |

## Raw artifacts

| File | Produced by |
| :-- | :-- |
| `02-idle-20min-raw.log` | `tools/agent/bs14_rc_idle.py` — 41 progressive samples, chronological |
| `02-idle-20min-metrics.json` | same run, per-sample snapshot series + derived deltas |
| `04-studio-viewport-audit.json` | `tools/agent/bs14_rc_viewports.py` — measured viewports, AbsoluteSize/Position, touch targets |
| `06-regression-console.log` | `tools/agent/check_all_suites.py` — full console, no truncation |
| `07-security-probe-output.txt` | `tools/agent/run_security_probes.py` — 10/10 |

## Reproduce

```bash
rojo build default.project.json -o build/BuzzerSimulator.rbxlx
rojo build test.project.json -o build/BuzzerTests.rbxlx

# G0 (open build/BuzzerTests.rbxlx in Studio first)
python tools/agent/check_all_suites.py --studio-id <id> --timeout 150

# Journey + 20-minute idle (open build/BuzzerSimulator.rbxlx in Studio first)
python tools/agent/bs14_rc_idle.py

# Server-boundary security probes (production place open)
python tools/agent/run_security_probes.py

# Studio viewport audit (production place open)
python tools/agent/bs14_rc_viewports.py

# Model-level economy invariants (no Studio needed)
python tools/economy_sim.py
```

## Rules this bundle follows

- A test that could not be executed is marked **BLOCKED** with the exact missing prerequisite; no raw log, metric, or observation is fabricated to fill a gap.
- Unit or adapter-level proof is never promoted to a real-world gate.
- Acceptance criteria were not rewritten to match a failing check.
- No production code was changed. Everything under `src/` is identical to `fa55baa`.
- Nothing was merged, published, or written to a cloud DataStore.

## Environment used

Roblox Studio `version-7062aec9dbe74b14`, Rojo 7.7.1, Python 3.14.7, Windows 11. Local place opened as a `.rbxlx` file, so `DataStoreService` is unavailable and `ProfileStore` logs `DEV_FALLBACK` — which is the code's own statement that real DataStore G2 remains open.
