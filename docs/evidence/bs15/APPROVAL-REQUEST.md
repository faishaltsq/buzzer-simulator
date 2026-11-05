# BS-15A — Formal Approval Request for Cloud DataStore Verification (BS-15B)

**To:** Director of Engineering / Project Director  
**From:** Lead Roblox Infrastructure & Release Verification Engineer  
**Date:** 2026-11-05  
**Subject:** BS-15A Preflight Sign-Off & Request for Authorization to Execute BS-15B (Staging Cloud Verification)  
**Current Verdict:** **PREFLIGHT PREPARED — CLOUD MUTATION BLOCKED PENDING SIGN-OFF**

---

## 1. Executive Summary

BS-15A preflight planning and repository inspection are complete. All specifications, safety boundaries, test cases, and rehearsal protocols for real Roblox cloud DataStore verification have been drafted and audited against the candidate source baseline `fa55baa` (`09eb88d`).

**Authoritative BS-14 Gate Verdict Baseline:**
- **G0:** PASS (Static build, 20/20 suites, 748 tests, regression assertions)
- **G1:** PARTIAL (Automated journey passes; no human/client-variety evidence)
- **G2:** BLOCKED (No cloud DataStore access; offline Studio logs `DEV_FALLBACK`)
- **G3:** PARTIAL (Viewport checks pass at measured viewports; no device pixels; art review pending)
- **G4:** PASS (M1 economy, 2 desks, 2 workers, 1.5 Cuan/s verified live)
- **G5:** BLOCKED (No physical device, no participants, rollback unrehearsed)
- **Overall Verdict:** **BLOCKED — CLOSED BETA NOT AUTHORIZED**

**No cloud writes, place publishing, universe creations, or key modifications were performed during BS-15A.**

To proceed with live verification in **BS-15B**, explicit director authorization and environment parameters are required.

---

## 2. Environment Status & Readiness Matrix

| Verification Tier | Prerequisite Status | Technical Readiness |
| :--- | :--- | :--- |
| **Source & Artifact** | Pinned `fa55baa`, build SHA-256 verified | **READY** |
| **Safety Guardrails** | 10 threat vectors mitigated; assertions designed | **READY** |
| **Layer C (Studio Cloud)** | 15 executable test cases specified | **PREPARED — BLOCKED on Staging Universe & API Key** |
| **Layer D (Two-Server)** | 7 multi-server concurrency cases specified | **PREPARED — BLOCKED on Staging Publish & Accounts** |
| **Rollback Plan** | 7-step place version reversion protocol authored | **PREPARED — BLOCKED on Staging Version History** |

---

## 3. Missing Prerequisites Required from Director

Before any command in BS-15B can execute, the director must provide and authorize:

1. **Verified Production Universe ID:** Verified numeric Universe ID of production experience (mandatory for lockout guard; cannot default to 0).
2. **Staging Universe ID:** A verified numeric Universe ID created on the Roblox Creator Dashboard dedicated strictly to staging (must be distinct from production).
3. **Staging Place ID:** A verified numeric Place ID representing the root place of the staging universe (must match the approved staging place).
4. **API Access Confirmation:** Confirmation that *Studio Access to API Services* is enabled on the staging universe.
5. **Authorized Testing Identity:** UserIds or test account credentials for at least two authorized test accounts (to execute single-client and two-server lease tests).
6. **Publish Authorization:** Formal approval to publish `build/BuzzerSimulator.rbxlx` to the target Staging Place.
7. **DataStore Mutation Authorization:** Formal approval to create and mutate test keys under the `PlayerData` DataStore in the staging universe.

---

## 4. Director Sign-Off Block

Please indicate approval by confirming the parameters below:

```markdown
[ ] Verified Production Universe ID (Lockout): __________________ (mandatory, > 0)
[ ] Confirmed Staging Universe ID:             __________________ (mandatory, > 0, ~= Prod)
[ ] Confirmed Staging Place ID:                __________________ (mandatory, > 0)
[ ] Studio API Access verified:                [YES / NO]
[ ] Authorized Test Account(s):                __________________
[ ] Permission to publish candidate build to Staging: [APPROVED / DENIED]
[ ] Permission to execute G2 Cloud DataStore Test Matrix: [APPROVED / DENIED]

Director Signature: _______________________
Date:               _______________________
```

---

## 5. Next Steps Upon Approval

Upon receipt of the completed authorization block:
1. Transition to phase **BS-15B**.
2. Run safety assertions to lock execution to the confirmed staging universe.
3. Execute Layer C test suite (Studio Cloud APIs).
4. Execute Layer D multi-server concurrency suite.
5. Execute place rollback rehearsal on staging.
6. Assemble untruncated evidence bundle to evaluate whether Gate G2 can be promoted from BLOCKED to PASS.
