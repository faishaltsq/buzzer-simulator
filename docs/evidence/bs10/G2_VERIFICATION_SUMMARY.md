# BS-10 Gate G2 Live DataStore Verification Summary

**Milestone**: BS-10 V0 Recovery, Reliability, Persistence & Failure Hardening  
**Target Gate**: Gate G2 (Real Roblox DataStoreService in Isolated Development Universe)  
**Branch**: `agent/BS-10-recovery-reliability`  
**Overall Status**: `G2_PASS`  
**Execution Environment**:
- **Roblox Studio Instance**: PID 14912 (`RobloxStudioBeta.exe`), StudioMCP PID 6228
- **Isolated Development Experience**: `Buzzer Simulator [DEV - BS-10]`
- **Universe ID (GameId)**: `10774181892`
- **Place ID**: `100558697471228`
- **Studio Access to API Services**: Enabled (`DataStoreService:GetDataStore("PlayerData")` active, in-memory fallback inactive)

---

## 1. Environment Pre-Flight Audit

| Item | Expected | Observed | Status |
|---|---|---|---|
| **Git Branch** | `agent/BS-10-recovery-reliability` | `agent/BS-10-recovery-reliability` | **PASS** |
| **Roblox Studio Executable** | Installed locally in AppData | `RobloxStudioBeta.exe` (PID 14912) | **PASS** |
| **Studio MCP Connectivity** | Connected to active Studio instance | `StudioMCP.exe` (PID 6228) responsive | **PASS** |
| **Target Universe** | Isolated private development experience (`GameId > 0`) | `GameId: 10774181892`, `PlaceId: 100558697471228` | **PASS** |
| **Studio API Services** | Enabled in Game Settings > Security | Real DataStore operational (`dsOk: true`, storeType: `Instance`) | **PASS** |
| **Rojo Production Build** | Clean build of `default.project.json` | `build/BuzzerSimulator.rbxlx` built cleanly (Rojo 7.7.1) | **PASS** |
| **Rojo Test Build** | Clean build of `test.project.json` | `build/BuzzerTests.rbxlx` built cleanly (Rojo 7.7.1) | **PASS** |
| **Automated Test Suites** | 17 suites passing | 17 suites, 667/667 passing tests | **PASS** |

---

## 2. Real DataStore Connection Validation

In `src/server/ProfileStore.luau` (lines 121-139), DataStore connectivity is handled with a strict boundary:

```luau
local ok, store = pcall(function()
    return dataStoreService:GetDataStore(STORE_NAME)
end)
if ok and store ~= nil then
    return store :: any
end

if isStudio then
    warn(`[ProfileStore:DEV_FALLBACK] DataStore handle '{STORE_NAME}' unavailable in offline Studio ({tostring(store)}). Using ephemeral in-memory store for local Studio session only. Real DataStore G2 remains OPEN.`)
    return getInMemoryFallback()
end
```

- In the active development experience `Buzzer Simulator [DEV - BS-10]` (`GameId: 10774181892`, `PlaceId: 100558697471228`), `DataStoreService:GetDataStore("PlayerData")` returned an authentic `Instance` (GlobalDataStore).
- Pre-flight verification (`tools/agent/check_preflight.py` and `tools/agent/test_ps.py`) confirmed `isFallback: false`, verifying all writes and reads execute against real Roblox cloud infrastructure.
- Dedicated 8-digit dev user identities (`88005001`, `88005002`) were utilized to avoid collisions with production keys or operator accounts.

---

## 3. G2 Scenario-by-Scenario Verification Matrix

All nine Gate G2 verification scenarios executed end-to-end via `tools/agent/run_all_g2.py` against real Roblox DataStoreService.

| Scenario ID | Scenario Name | Target Test Conditions | Expected Balances & State | Observed Values | Execution Mode | Result |
|---|---|---|---|---|---|---|
| **G2-01** | Fresh Account | Connect fresh test identity (`88005001`), verify starter envelope, clean stop, rejoin | 0 Cuan, `phone_cheap`, revision >= 1. Rejoin preserves identity. | Initial: 0 Cuan, `phone_cheap`, rev 2. Rejoin: 0 Cuan, `phone_cheap`, rev 2. | Cloud DataStore | **PASS** |
| **G2-02** | Organic Pending Recovery | Publish organic post (`snack_meme`), disconnect before 18s reveal, wait 18s, rejoin | +15 Cuan (Balance: 15). Rejoin does not duplicate credit. | Settled: 15 Cuan, pendingPost cleared. Repeat rejoin: 15 Cuan, rev 4. | Cloud DataStore | **PASS** |
| **G2-03** | Campaign Pending Recovery | Accept Food Stall mission, publish mission post (`meal_meme`), disconnect before reveal, wait 18s, rejoin | Run ID consistent, single payout (+15 Cuan, Balance 30), status `readyToClaim`. | Balance: 30 Cuan, runId: `run-2`, status: `readyToClaim`, postCount: 1, rev 7. | Cloud DataStore | **PASS** |
| **G2-04** | Claim Persistence | Claim 80 Cuan mission reward, disconnect, rejoin, attempt duplicate claim | Balance: 110 (30 + 80). Claimed status persists. Duplicate claim refused. | Claimed: 110 Cuan. Rejoin: 110 Cuan, completedMissions: 1. Duplicate: 110 Cuan (`NO_ACTIVE_MISSION`), rev 8. | Cloud DataStore | **PASS** |
| **G2-05** | Fast Phone Purchase | Buy Fast Phone (50 Cuan), verify deviceId & catalog presentation, rejoin, attempt duplicate buy | Balance: 60, `phone_fast` equipped. Duplicate buy refused. | Bought: 60 Cuan, `phone_fast`. Rejoin: 60 Cuan, `phone_fast`. Duplicate: 60 Cuan (`ALREADY_DONE`), rev 9. | Cloud DataStore | **PASS** |
| **G2-06** | Post-Upgrade Payout | Publish organic post with Fast Phone (16s reveal), wait 18s, settle via Snapshot, rejoin | +24 Cuan payout (Balance: 84). Final balance persists across restart. | Settled: 84 Cuan (+24 yield). Rejoin: 84 Cuan, `phone_fast`, rev 11. | Cloud DataStore | **PASS** |
| **G2-07** | Lease Behavior | Server A holds lease, Server B attempts start (must fail LOCKED), Server A stops, Server B starts | Exclusive lease lock (240s), clean handoff on stop, no data overwrite. | Server B competing start: `LOCKED`. Server A stop: clean. Server B handoff start: `OK`, balance: 84, rev 11. | Cloud DataStore | **PASS** |
| **G2-08** | Failure Recovery | Idempotent replay with same reqId, spoofed payload rejected, insufficient funds rejected, read error safe | Replay no revision bump, tamper `INVALID_INPUT`, bad buy `INSUFFICIENT_FUNDS`, safe failure. | Replay no bump: `true`. Spoof: `INVALID_INPUT`. Bad buy: `INSUFFICIENT_FUNDS` (bal: 0). Store failure: `SAVE_UNAVAILABLE` (no profile overwrite). | Cloud DataStore | **PASS** |
| **G2-09** | Client & Device Recovery | BuzzerOS open/close lifecycle, character loss on death, 6s mutation timeout, responsive layout | Camera/controls restore, character death closes session, uncertain tracked, UI renders. | Lifecycle: `Opening->Open->Closing->Closed`. Death handled: `true`. Uncertain tracked: `true`. Desktop (1280x720): `true`. Mobile (390x844): `true`. | Cloud DataStore & Client | **PASS** |

---

## 4. Confirmed Balance & Revision History (Actual Live Execution)

The full live journey executed on player `88005001` against real Roblox cloud storage confirmed every step of the economic conservation model:

1. **G2-01 Starter Init**: 0 Cuan, Device: `phone_cheap`, Revision: 2
2. **G2-02 Organic Post**: +15 Cuan → Balance: 15 Cuan, Revision: 4
3. **G2-03 Food Stall Post**: +15 Cuan → Balance: 30 Cuan, Revision: 7
4. **G2-04 Mission Reward Claim**: +80 Cuan → Balance: 110 Cuan, Revision: 8
5. **G2-05 Fast Phone Purchase**: -50 Cuan → Balance: 60 Cuan, Device: `phone_fast`, Revision: 9
6. **G2-06 Upgraded Post**: +24 Cuan → Balance: 84 Cuan, Device: `phone_fast`, Revision: 11
7. **G2-07 Multi-Server Handoff**: Balance: 84 Cuan, Device: `phone_fast`, Revision: 11

$$\Delta\text{Balance} = (15 + 15 + 80 + 24) - 50 = 84\text{ Cuan}$$

Durable backend state confirmed: exactly 84 Cuan, 1 completed mission, `phone_fast` equipped, revision 11.

---

## 5. Evidence Artifacts

- **Automated Runner**: `tools/agent/run_all_g2.py`
- **Machine Evidence Record**: `docs/evidence/bs10/g2_live_results.json`
- **Pre-flight & Connection Scripts**: `tools/agent/check_preflight.py`, `tools/agent/test_ps.py`

---

## 6. Gate G2 Final Conclusion

- **Gate G2 Status**: **`G2_PASS`**
- All 9 real DataStore scenarios have passed on live Roblox cloud infrastructure with 0 fake adapters.
- Invariants verified: Zero phantom Cuan, zero lost balances, strictly serialized lease ownership, idempotent retries, safe failure preservation, and responsive client state machine recovery.
