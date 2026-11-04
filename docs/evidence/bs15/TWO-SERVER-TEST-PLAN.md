# BS-15A — Published Two-Server Staging Test Plan (Layer D)

**Document Status:** Operational Test Protocol (Preflight Only — Awaiting Authorization)  
**Execution Context:** Real Published Roblox Staging Servers (Two Independent Server Instances)  
**Target Gate:** Gate G2 — Multi-Server Safety, Lease Concurrency, and Rejoin Resilience

---

## 1. Multi-Server Test Topology

Layer D tests cannot be executed within a single local Studio session. They require two independent server instances running on Roblox cloud infrastructure within the same Staging Universe.

```
                  +-----------------------------------+
                  |      Roblox Cloud DataStore       |
                  |     Key: Player_{testUserId}      |
                  +-----------------+-----------------+
                                    |
                    +---------------+---------------+
                    |                               |
          [Lease: Token A, Exp: T]                  |
                    |                               |
         +----------v----------+         +----------v----------+
         |   Staging Server    |         |   Staging Server    |
         |     Instance A      |         |     Instance B      |
         |   (JobId: job-aaa)  |         |   (JobId: job-bbb)  |
         +----------^----------+         +----------^----------+
                    |                               |
             [Client Session]                [Client Session]
```

### Server Allocation Methods:
1. **Reserved Servers:** Utilizing `TeleportService:ReserveServer(PlaceId)` to generate two guaranteed distinct private server instances (`AccessCodeA`, `AccessCodeB`).
2. **Standard Matchmaking Isolation:** Configuring place max player count = 1 or joining distinct server instances manually via game server browser.

---

## 2. Detailed Multi-Server Test Specifications

### Case D-01: Foreign Lease Conflict
- **Setup:** Candidate build published to Staging. Server A (JobId `A`) and Server B (JobId `B`) active.
- **Actor & Environment:** Test Player `UserId_T1` connected to Server A. Server B running empty or with another player.
- **Operation:**
  1. `UserId_T1` connects to Server A. `SessionService:Start()` acquires lease: `leaseToken = "token_A"`, `leaseExpiresAt = now + 240`.
  2. Test command on Server B invokes `SessionService:Start()` for `UserId_T1` while Server A holds the live lease.
- **Expected Result:** Server B `ProfileStore:Load()` reads envelope. Detects `leaseToken ~= token_B` and `now < leaseExpiresAt`. Server B immediately returns `code = "LOCKED"`, `ok = false`. Server B does NOT overwrite lease or load profile data into memory.
- **Exact Evidence:** Server B console log recording `code = "LOCKED"`; DataStore inspect showing `leaseToken` remains `token_A`.
- **Cleanup Procedure:** Disconnect player from Server A cleanly.
- **Recovery from Partial Execution:** If Server B inadvertently overwrites lease, inspect CAS logic in `ProfileStore.luau:710-740`.

---

### Case D-02: Cross-Server Write Exclusion
- **Setup:** Server A holds valid lease `token_A` for `UserId_T1` (rev 3).
- **Actor & Environment:** Server A and Server B both active on Staging.
- **Operation:**
  1. Server B attempts an unauthorized write via `UpdateAsync` on `Player_{UserId_T1}` using a synthetic mutation payload.
  2. The `UpdateAsync` transform callback in `ProfileStore` checks `stored.leaseToken == self._leaseToken`.
- **Expected Result:** Because Server B does not possess `token_A`, the transform callback rejects the update, returning `nil` (abort). Server B returns `code = "LOCKED"`. Stored cloud revision remains `3`. Server A session continues uninterrupted.
- **Exact Evidence:** Cloud revision check confirms rev remains `3`; Server A receives no corruption or disruption.
- **Cleanup Procedure:** None required; unauthorized write was rejected.
- **Recovery from Partial Execution:** If write succeeded, mark test as CRITICAL CAS FAILURE; halt testing immediately.

---

### Case D-03: Clean Server Exit and Lease Handoff
- **Setup:** `UserId_T1` actively playing on Server A with accumulated worker earnings (rev 4).
- **Actor & Environment:** `UserId_T1` on Server A, Server B standing by.
- **Operation:**
  1. `UserId_T1` initiates clean disconnect or teleport to Server B.
  2. Server A `PlayerRemoving` / `BindToClose` fires, invoking `SessionService:Stop()`.
  3. Server A performs final worker bank and clears lease: `leaseToken = nil`, `leaseExpiresAt = 0`.
  4. Immediately upon arrival on Server B (< 5 seconds after Server A exit), Server B calls `SessionService:Start()`.
- **Expected Result:** Server B loads profile successfully (`code = "OK"`). Because lease was cleanly cleared, Server B does not wait for 240s TTL; it acquires new lease `token_B` instantly. Confirmed balance on Server B includes the final bank from Server A.
- **Exact Evidence:** Timestamped logs from Server A showing `Stop() -> lease released` at `T_0`, and Server B showing `Start() -> lease acquired` at `T_0 + delta` without `LOCKED` retries.
- **Cleanup Procedure:** Clean exit from Server B.
- **Recovery from Partial Execution:** If lease handoff blocks, inspect `ProfileStore:Release()` implementation.

---

### Case D-04: Abnormal Disconnect Recovery (Crash / Force Kill)
- **Setup:** `UserId_T1` connected to Server A with confirmed profile.
- **Actor & Environment:** `UserId_T1` on Server A, Server B standing by.
- **Operation:**
  1. Server A is abruptly killed (simulated via task crash or instance termination) without executing `SessionService:Stop()`. The lease remains locked in cloud (`leaseToken = token_A`, `leaseExpiresAt = T_crash + 240`).
  2. `UserId_T1` immediately attempts to connect to Server B at `T_crash + 10s`. Observe result.
  3. Wait until `T_crash + 245s` (after lease expiration). `UserId_T1` attempts `SessionService:Start()` on Server B.
- **Expected Result:**
  - At `T_crash + 10s`: Server B receives `code = "LOCKED"` (lease still valid in cloud). Client UI shows appropriate retry/lock screen.
  - At `T_crash + 245s`: Server B detects expired lease (`now >= leaseExpiresAt`). Server B acquires lease `token_B` successfully with `code = "OK"`.
- **Exact Evidence:** Server B log at +10s showing `LOCKED`; Server B log at +245s showing `OK` with lease acquisition timestamp.
- **Cleanup Procedure:** Clean shutdown on Server B.
- **Recovery from Partial Execution:** Ensure clock drift between servers does not exceed 5 seconds.

---

### Case D-05: Concurrent Operation Safety (Race on Expired Lease)
- **Setup:** Profile lease on `Player_{UserId_T1}` has reached expiration timestamp in cloud.
- **Actor & Environment:** Server A and Server B both running simultaneously on Staging.
- **Operation:**
  1. Trigger simultaneous `SessionService:Start()` on Server A and Server B within a 100ms window.
  2. Both servers attempt conditional `UpdateAsync` to acquire the lease.
- **Expected Result:** Roblox `UpdateAsync` serializes the atomic transactions. Exactly one server successfully writes its `leaseToken` and acquires the profile (`ok = true`, code `OK`). The losing server receives the newly updated lease token, detects foreign ownership, and returns `ok = false`, code `LOCKED`. Zero split-brain states.
- **Exact Evidence:** Cloud log confirming exactly one token active; one server `OK`, one server `LOCKED`.
- **Cleanup Procedure:** The winning server executes clean `Stop()`.
- **Recovery from Partial Execution:** Re-verify backend key state via fresh read.

---

### Case D-06: Real Published-Server Rejoin
- **Setup:** Live published candidate game on Staging. Real test account logs in.
- **Actor & Environment:** Roblox Client connected to Live Staging Server.
- **Operation:**
  1. Player completes mission 1, buys `phone_fast`, unlocks desk 1, hires trainee 1.
  2. Player quits game via Roblox escape menu (triggering normal client leave).
  3. Player relaunches Roblox client and rejoins the game 60 seconds later.
- **Expected Result:** Player spawns into room. Room correctly loads `Bedroom` prefab with `PhoneFast` on desk, trainee seated at Desk 1. Wallet balance and lifetime earnings match pre-quit values exactly.
- **Exact Evidence:** Client screenshot of world state; snapshot dump confirming all assets.
- **Cleanup Procedure:** Keep account for server restart test.
- **Recovery from Partial Execution:** Check DataStore key for missing fields.

---

### Case D-07: Persistence After Server Restart
- **Setup:** Live staging server with active players and accumulated economy progression.
- **Actor & Environment:** Creator Dashboard / Studio management interface.
- **Operation:**
  1. Trigger "Shut Down All Servers" from the Roblox Creator Dashboard staging place page.
  2. All running servers execute `BindToClose` shutdown handlers, saving player data and releasing leases.
  3. Wait 30 seconds for server shutdown to complete.
  4. Player reconnects to a brand new staging server instance.
- **Expected Result:** `BindToClose` successfully saved all in-flight worker earnings and released leases before termination. Player joins new server cleanly without `LOCKED` delay. All data, workers, and cuan are intact.
- **Exact Evidence:** Creator Dashboard server shutdown log; client reconnect logs showing 0 data loss and clean startup.
- **Cleanup Procedure:** Normal session exit.
- **Recovery from Partial Execution:** If shutdown times out (exceeding Roblox 30s `BindToClose` limit), inspect shutdown flush order in `BootstrapRuntime.luau`.
