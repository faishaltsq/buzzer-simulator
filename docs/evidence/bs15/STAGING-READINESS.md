# BS-15A — Staging Environment Readiness Audit

**Audit Date:** 2026-11-05  
**Candidate Source:** `fa55baa4a417097b6d4f8a032c602bcf1c1df19e`  
**Auditor:** Lead Roblox Infrastructure & Release Verification Engineer  
**Status:** **NOT READY FOR EXECUTION — MANDATORY STAGING PREREQUISITES UNVERIFIED**

---

## 1. Readiness Audit Summary

To execute real cloud DataStore verification (Gate G2) safely without risking production data or generating invalid test results, nine staging environment prerequisites were audited.

| # | Prerequisite Property | Required Condition | Current Audit Finding | Status |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Staging Universe Isolation** | Dedicated universe separate from production experience | Historical documentation cited Universe `10774181892`. Public Roblox API query (`https://games.roblox.com/v1/games?universeIds=10774181892`) returns `[TITLE UNAVAILABLE]` with `id: 0`. No active staging universe is currently accessible or bound. | **BLOCKED** |
| **2** | **Confirmed UniverseId & PlaceId** | Verified numeric UniverseId and PlaceId from Creator Dashboard | Cannot be verified without Creator Dashboard or authenticated Open Cloud access. Documented Place `100558697471228` is unconfirmed. | **UNKNOWN** |
| **3** | **Authorized Test Identity** | At least one authorized Roblox test account (two accounts for multi-server) | Current test runner operates in local Studio mode using mock player identities. Genuine Roblox UserIds tied to real test accounts have not been provisioned. | **BLOCKED** |
| **4** | **Publisher Permissions** | Active Open Cloud API key or Studio publishing rights on staging place | The current agent workspace has no publishing credentials, OAuth tokens, or write scopes configured. Publishing is strictly prohibited without authorization. | **BLOCKED** |
| **5** | **Studio API Services Configuration** | `studioAccessToApisAllowed = true` on the staging universe | Cannot be verified or toggled without Creator Dashboard access to the target universe settings. | **UNKNOWN** |
| **6** | **Namespace Isolation** | Staging universe must not share DataStore partitions with production | By Roblox DataModel architecture, DataStores are scoped per UniverseId. If UniverseId is strictly distinct from production, `PlayerData` partition isolation is guaranteed by Roblox backend. | **VERIFIED (Architectural)** |
| **7** | **Disposable Test Profile Plan** | Key partitioning and cleanup lifecycle to prevent data residue | Plan designed: test identities will use isolated test keys with run UUID tags and explicit pre-test / post-test sanitization protocol. | **VERIFIED (Planned)** |
| **8** | **Reproducible Candidate Artifact** | Deterministic place file built from approved source | `build/BuzzerSimulator.rbxlx` built via Rojo 7.7.1 from `default.project.json`, SHA-256 `9c8c431d28a1e2347c08cda76450a129071c7166f1bf9ab08f7b7bc30ed3e833`. | **VERIFIED** |
| **9** | **Rollback Recovery Path** | Documented and verifiable procedure to restore place versions | Rehearsal plan authored in `ROLLBACK-REHEARSAL-PLAN.md` utilizing Roblox Version History. | **VERIFIED (Planned)** |

---

## 2. Detailed Findings

### 2.1 Universe & Place Identity (Items 1 & 2)
In BS-10 and early BS-14 documents, Universe ID `10774181892` and Place ID `100558697471228` were referenced. During BS-14 evidence reconciliation (`01-source-evidence-reconciliation.md`), an external API check against `https://games.roblox.com/v1/games?universeIds=10774181892` returned:
```json
{"data": [{"id": 0, "name": "[TITLE UNAVAILABLE]", "studioAccessToApisAllowed": false}]}
```
This confirms that the universe is either deleted, non-public, invalid, or misattributed. **Operating against an unverified universe ID is forbidden.** The director must provide verified Universe and Place IDs directly from the Creator Dashboard URL.

### 2.2 Account Identities & Credentials (Items 3 & 4)
- Automated local test suites (`check_all_suites.py`) and journey scripts (`bs14_rc_idle.py`) operate in Studio with mock player objects (`player.UserId = 1234` or local player in Studio).
- When `studioAccessToApisAllowed` is enabled in Studio, `DataStoreService:GetDataStore("PlayerData")` interacts with the cloud backend using the Studio user's identity or key partition.
- Genuine multi-server Layer D verification requires two distinct physical test players connected via the Roblox client to a published staging place. Inventing mock UserIds on a live published server will fail or violate Roblox authentication contracts. Genuine test accounts must be designated.

### 2.3 Studio API Access (Item 5)
In local Studio sessions without cloud API enablement, `ProfileStore.luau` encounters:
```
[ProfileStore:DEV_FALLBACK] DataStore handle 'PlayerData' unavailable in offline Studio.
Using ephemeral in-memory store for local Studio session only. Real DataStore G2 remains OPEN.
```
Before Layer C tests can run, the staging experience settings must have:
`Home > Game Settings > Security > Enable Studio Access to API Services = ON`.

### 2.4 DataStore Boundary & Namespace (Item 6)
Roblox `DataStoreService` partitions data strictly by Universe ID:
`Universe(Staging) -> DataStore("PlayerData")` is physically segregated by Roblox infrastructure from `Universe(Production) -> DataStore("PlayerData")`.
Therefore, as long as `Staging UniverseId ~= Production UniverseId`, writes to `PlayerData` in staging cannot overwrite, mutate, or throttle production data.

---

## 3. Environment Boundary Matrix

| Boundary Zone | Target | Access Level | Permitted Actions in Preflight |
| :--- | :--- | :--- | :--- |
| **Local Workspace** | Local repository files, `build/*.rbxlx` | Full Read / Write | Source inspection, static artifact compilation, documentation authoring |
| **Local Studio (Offline)** | Studio session without cloud APIs | Local Mock Execution | Unit regression, syntax check, layout check (`DEV_FALLBACK` active) |
| **Staging Universe (Cloud)** | Dedicated Staging Experience | Pending Approval | **STRICTLY BLOCKED** (No publish, no cloud reads/writes) |
| **Production Universe** | Live Public Game | Zero Access Permitted | **STRICTLY BLOCKED & OUT OF SCOPE** |

---

## 4. Minimum Unblocking Checklist for Director

To transition from BS-15A (Preflight) to BS-15B (Live Execution), the director must provide:

- [ ] **Universe ID:** Verified numeric ID of the dedicated Staging Universe.
- [ ] **Place ID:** Verified numeric ID of the root Staging Place.
- [ ] **API Security Status:** Confirmation that *Studio Access to API Services* is enabled on the Staging Universe.
- [ ] **Testing Account(s):** Username / UserId of authorized test account(s) for Layer C & D.
- [ ] **Publish Authorization:** Formal sign-off allowing `build/BuzzerSimulator.rbxlx` to be published to the Staging Place.
