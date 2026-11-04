# BS-15A — Staging Place Rollback Rehearsal Plan

**Document Status:** Operational Procedure Plan (Preflight Only — Awaiting Authorization)  
**Target Gate:** Gate G5 (Rollback Verification & Resilience)  
**Scope:** Rehearsing place version reversion on Staging without risking data loss or production stability.

---

## 1. Objective and Preconditions

Previous BS-14 documentation cited non-existent runtime kill switches (`DisablePurchases`, `DisableAccrual`). As audited in `docs/evidence/bs14-remediation/08-rollback-verification.md`, the only real, functional rollback lever available in the Roblox engine is **Place Version Reversion** via the Creator Dashboard.

This document defines the 7-step procedure to rehearse place rollback on the dedicated Staging Universe to prove:
1. Reverting place version does not wipe or corrupt persistent DataStore profiles.
2. An older server version gracefully loads or preserves profiles created by the candidate version.
3. Restoring the candidate version resumes normal operations with zero data loss.

*Rule: This is a planning specification only. Do not execute this rehearsal during preflight.*

---

## 2. Seven-Step Rehearsal Protocol

```
[Step 1: Baseline] ---> [Step 2: Publish Candidate] ---> [Step 3: Seed Profile]
                                                                |
[Step 6: Re-Restore] <-- [Step 5: Verify Old Version] <-- [Step 4: Rollback]
        |
[Step 7: Final Invariance Check]
```

### Step 1: Record Staging Baseline Identity
- Navigate to Roblox Creator Dashboard > Staging Experience > Places > Version History.
- Record the current active place version number (e.g., `Version N_base`).
- Record Git commit hash and build artifact hash (`build/BuzzerSimulator.rbxlx`, SHA-256 `9c8c431d...`).

### Step 2: Publish Approved Candidate Build
- Publish `build/BuzzerSimulator.rbxlx` to the Staging Place using Roblox Studio or Open Cloud Publish API.
- Verify that Version History reflects new version: `Version N_candidate = N_base + 1`.
- Restart staging servers to ensure the new version is serving incoming connections.

### Step 3: Establish and Verify Durable Profile State
- Connect authorized test player `Tester_A` (`Player_{testUserId}`) to the candidate server.
- Execute standard gameplay progression:
  - Acquire `phone_fast` (60 Cuan).
  - Unlock Desk 1 and hire Trainee 1.
  - Complete 2 missions, reaching confirmed balance `B_checkpoint`.
- Trigger clean session stop (`SessionService:Stop()`) to flush final worker bank and release lease.
- Perform fresh cloud verification read (`GetAsync(..., UseCache=false)`):
  - Record revision `R_checkpoint`.
  - Confirm `wallet.balance == B_checkpoint`.
  - Confirm `profile.devices` and `profile.studio` assets.

### Step 4: Execute Place Version Rollback in Creator Dashboard
- In Creator Dashboard > Version History, select `Version N_base` (the previous pre-candidate version).
- Click **"Restore this version"**.
- This creates `Version N_rollback = N_candidate + 1`, with contents identical to `Version N_base`.
- Click **"Shut Down All Servers"** on the staging place to terminate running candidate servers.

### Step 5: Connect to Rolled-Back Version and Verify Integrity
- Launch Roblox client and connect `Tester_A` to the newly spun-up rolled-back server instance.
- Observe startup behavior:
  - Case A (Prior version had identical Schema v1): Profile loads successfully; confirmed balance and devices are intact.
  - Case B (Prior version lacked new assets or had different schema): ProfileStore preserves unknown fields or fails closed (`UNSUPPORTED_SCHEMA`) without data destruction.
- Player disconnects cleanly.

### Step 6: Restore Candidate Place Version
- In Creator Dashboard > Version History, select `Version N_candidate`.
- Click **"Restore this version"**.
- This creates `Version N_restored = N_rollback + 1`, with contents matching the approved candidate build.
- Shut down all staging servers.

### Step 7: Final Data Invariance Verification
- Launch Roblox client and connect `Tester_A` to the restored candidate server.
- Call `SessionService:Start()`.
- Query profile snapshot:
  - Assert `wallet.balance == B_checkpoint`.
  - Assert `profile.revision >= R_checkpoint`.
  - Assert all devices, desks, and trainees remain owned and configured.
- Assert zero data truncation, corruption, or loss occurred across the dual rollback cycle.

---

## 3. Success Criteria and Artifact Outputs

| Step | Verification Check | Success Standard | Evidence Artifact |
| :--- | :--- | :--- | :--- |
| **Publish** | Place Version Increment | Version increments monotonically | Dashboard screenshot / API response |
| **Seed** | Cloud Write Confirmation | Balance & assets confirmed in cloud | Raw JSON snapshot `pre-rollback-state.json` |
| **Rollback** | Server Code Reversion | Place runs older code | Server console log showing baseline version |
| **Compatibility** | Schema Preservation | No starter reset; zero field deletion | Cloud DataStore inspect `rolled-back-inspect.json` |
| **Restore** | Candidate Reinstatement | Candidate logic active | Server console log showing candidate build |
| **Invariance** | Bit-for-bit Data Continuity | Final state strictly matches seed | Diff comparison: `final-vs-seed.diff == 0` |
