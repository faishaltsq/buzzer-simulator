# BS-15A — Real Cloud DataStore Verification Preflight

**Candidate Source Baseline:** `fa55baa4a417097b6d4f8a032c602bcf1c1df19e` (`src/` identical on `09eb88d626d73057543fe419a2c0925063d1df09`)  
**Branch:** `agent/BS-15A-staging-preflight`  
**Date:** 2026-11-05  
**Verdict:** **PREFLIGHT PREPARED — CLOUD EXECUTION BLOCKED PENDING DIRECTOR APPROVAL**

---

## 1. Context and Objective

BS-14 remediation closed with an authoritative verdict of **BLOCKED — CLOSED BETA NOT AUTHORIZED** (`docs/evidence/bs14-remediation/09-release-gate-verdict.md`). The primary technical blocker for release readiness is Gate **G2 (Real Cloud DataStore Safety and Rejoin)**. Prior certifications relied upon local in-memory mock adapters (`DEV_FALLBACK`) and unit test doubles, which cannot prove:
- Roblox cloud service latency and timeout distribution.
- Real DataStore `UpdateAsync` throttling (Request Budget 301).
- Multi-server lease CAS handoff and foreign lease lockouts across real network boundaries.
- Engine cache invalidation behavior (`DataStoreGetOptions.UseCache = false`).
- Cloud place rollback and forward schema resilience.

**BS-15A covers preflight and test planning only.** No publish, place creation, cloud setting modification, DataStore write, key deletion, or cloud mutation tests have been or will be executed in this phase.

---

## 2. Pinned Build and Candidate Identity

| Attribute | Value | Verification |
| :--- | :--- | :--- |
| **Repository Master Baseline** | `09eb88d626d73057543fe419a2c0925063d1df09` | PR #10, #11, #12 merged |
| **Candidate Source Baseline** | `fa55baa4a417097b6d4f8a032c602bcf1c1df19e` | Verified byte-for-byte identical in `src/` |
| **Production Place Artifact** | `build/BuzzerSimulator.rbxlx` | SHA-256: `9c8c431d28a1e2347c08cda76450a129071c7166f1bf9ab08f7b7bc30ed3e833` (1,071,852 bytes) |
| **Test Place Artifact** | `build/BuzzerTests.rbxlx` | SHA-256: `79d72e28685216cd4035fd586284edcf4bd106615b378433a2c4bd4d1a2b1b1c` (1,721,756 bytes) |
| **Tooling & Runtime** | Rojo 7.7.1, Python 3.14.7, Windows 11 | Authoritative local toolchain |

---

## 3. Authoritative Persistence Contract (v1)

Source inspection of `src/server/ProfileStore.luau` and `src/server/SessionService.luau` confirms:

- **DataStore Name:** `PlayerData` (never versioned in store name; schema versioned inside envelope).
- **Key Namespace:** `Player_{UserId}` (strictly ASCII alphanumeric, fail-closed validation).
- **Schema Version:** `1` (envelopes with `schemaVersion ~= 1` fail closed as `UNSUPPORTED_SCHEMA` and are preserved byte-for-byte).
- **Lease Duration:** `240` seconds (`LEASE_DURATION = 240`).
- **Lease Renewal Interval:** `90` seconds (`LEASE_RENEW = 90`).
- **Worker Banking Interval:** `30` seconds (`WORKER_BANK_INTERVAL = 30`).
- **Offline Accrual:** Explicitly disabled (`No offline worker income is awarded here.`, `SessionService.luau:363-364`). Accrual requires an active, connected, writable session.
- **Write Policy:** Strict conditional `UpdateAsync` with compare-and-swap (CAS) on `(leaseToken, expectedRevision)`. No blind `SetAsync` anywhere in codebase.
- **Ambiguous Write Reconciliation:** Bounded retry (max 3 attempts, exponential backoff `{1, 2}`s) reusing identical `operationId`, verifying against backend with `UseCache = false`.

---

## 4. Documentation Index

The BS-15A preflight package contains six operational planning artifacts:

1. [`STAGING-READINESS.md`](STAGING-READINESS.md)  
   Comprehensive audit of 9 mandatory staging environment properties (Verified vs. Unknown vs. Blocked).
2. [`G2-CLOUD-TEST-MATRIX.md`](G2-CLOUD-TEST-MATRIX.md)  
   Complete 22 executable test scenarios across Layer C (15 scenarios in Studio with Real Cloud APIs) and Layer D (7 scenarios in Published Two-Server Staging), with bidirectional traceability mapping to the 17 G2 requirements.
3. [`TWO-SERVER-TEST-PLAN.md`](TWO-SERVER-TEST-PLAN.md)  
   Operational topology, orchestration protocol, and failure injection scenarios for multi-server concurrency verification.
4. [`DATASTORE-SAFETY-PLAN.md`](DATASTORE-SAFETY-PLAN.md)  
   Guardrails against production contamination, namespace bleed, key collisions, data corruption, and throttle exhaustion.
5. [`ROLLBACK-REHEARSAL-PLAN.md`](ROLLBACK-REHEARSAL-PLAN.md)  
   Step-by-step non-destructive rehearsal protocol for place version rollback and schema preservation.
6. [`APPROVAL-REQUEST.md`](APPROVAL-REQUEST.md)  
   Formal director review and sign-off checklist required prior to any staging publish or cloud write.

---

## 5. Preflight Rules and Guardrails

1. **No Cloud Writes in Preflight:** This phase generates plans and documentation only.
2. **Zero Fabrication:** Unverified cloud properties are declared `BLOCKED` or `UNKNOWN`.
3. **No Account Credential Leakage:** Git history and artifacts must never contain API keys, cookies, or real player authentication tokens.
4. **Isolated Test Identities:** Real test executions in BS-15B must use explicit, authorized test accounts on disposable keys.
