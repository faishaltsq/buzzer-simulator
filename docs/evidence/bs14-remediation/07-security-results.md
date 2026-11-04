# BS-14 RC-1 — Security Results

**Candidate:** `fa55baa` (source unchanged)
**Run:** 2026-11-04 07:31:10 UTC, Roblox Studio Play session, production build `build/BuzzerSimulator.rbxlx`
**Runner:** `python tools/agent/run_security_probes.py`
**Raw output:** `07-security-probe-output.txt`
**Result:** **10 / 10 probes passed, 0 failed**

---

## 1. What kind of test this is

The probes execute **inside a live Play server** but drive `SessionService` / `NetRouter` / `WorldService` through constructed fixtures and synthetic actors (`run_security_probes.py:20-60`), not through a connected client's input path. They are therefore **server-side boundary tests**, one layer above the pure specs and one layer below a real client.

They are not penetration testing against a live client, and they are not a substitute for the client-admission checks that run in `ClientState` (covered by `ClientState.spec`, 30/30).

The previous release document described a different set of probes (SQL-injection strings, `spoofed-run-999` runIds, 4 KB payloads, a 120-call burst) that are **not** what this runner executes. That mismatch is recorded as C9 in `01-source-evidence-reconciliation.md`; this file replaces it with the executed set.

---

## 2. Executed probes

| Probe | What it asserts | Observed detail | Layer | Result |
| :-- | :-- | :-- | :-- | :-- |
| SEC-01 Unknown action forgery rejected | An unregistered action name is refused, and the dashboard stays usable | `dashboard=true code=UNKNOWN_ACTION` | server boundary | **PASS** |
| SEC-02 Client price injection rejected | Extra/unexpected payload fields are refused rather than honoured | `code=INVALID_INPUT` | server boundary | **PASS** |
| SEC-03 Invalid slot numerics rejected | Non-integer / negative / out-of-range slot indices are refused | `codes=INVALID_INPUT,INVALID_INPUT,INVALID_INPUT` | server boundary | **PASS** |
| SEC-04 Prompt beyond 12 studs rejected | Interaction range is enforced on a real spawned room | `far=false err=player is 40 studs away; the limit is 12 near=true` | server boundary (world) | **PASS** |
| SEC-05 Cloned prompt rejected | A prompt instance not owned by the player's room cannot open the dashboard | `valid=false err=prompt does not belong to this player's room` | server boundary (world) | **PASS** |
| SEC-06 Command flood throttled | A 20-call burst is mostly rejected | `admitted=1 throttled=19` | server boundary | **PASS** |
| SEC-07 Conflicting replay refused | Reusing a request identity with different content is refused | `code=INVALID_INPUT` | server boundary | **PASS** |
| SEC-08 Insufficient funds purchase refused | A purchase beyond the confirmed balance is refused | `code=INSUFFICIENT_FUNDS` | server boundary | **PASS** |
| SEC-09 Premature desk 2 blocked | Desk 2 cannot be bought before its prerequisite | `code=NOT_READY` | server boundary | **PASS** |
| SEC-10 Expired dashboard refuses mutation | A stale dashboard session cannot mutate | `code=SESSION_EXPIRED` | server boundary | **PASS** |

---

## 3. Required negative-case coverage

| Required case | Covered by | Layer | Status |
| :-- | :-- | :-- | :-- |
| Forged payouts | `SEC-02` (payload strictness) + `EconomyService.spec` | server | **PASS** |
| Invalid action type | `SEC-01` | server | **PASS** |
| Invalid request payload | `SEC-02`, `SEC-03` | server | **PASS** |
| Wrong player / room prompt | `SEC-05` | server | **PASS** |
| Out-of-range interaction | `SEC-04` | server | **PASS** |
| Replay conflicts | `SEC-07` | server | **PASS** |
| Expired session | `SEC-10` | server | **PASS** |
| Duplicate settlement | `BS10Recovery.spec` B2/B5 (single stable identity, credits once) | spec | **PASS (spec)** |
| Double claim | `MissionService.spec` (85/85) + durable outcome ring D4 | spec | **PASS (spec)** |
| Invalid worker slot | `SEC-03` + `EconomyService` slot validation | server | **PASS** |
| Failed save with unknown outcome | `BS10Recovery.spec` B6 + `ProfileStore.spec` ambiguous-write cases | spec | **PASS (spec)** |
| Concurrent mutation | `ClientState` `BUSY` gate (D9) + `ProfileStore.spec` lease CAS | spec + client gate | **PASS (spec)** |
| Lease loss | `ProfileStore.spec`: "Save is denied after the lease is lost" | spec | **PASS (spec)** |
| Excessive requests | `SEC-06` (20-call burst) | server | **PASS** |

No required case is unaddressed, but note the **layer split**: only nine of the fourteen are proven against a running server here; the settlement/lease/concurrency cases rest on the spec suite (all green: 748 runtime tests, 0 failures).

## 4. What is still not proven

| Gap | Why it matters |
| :-- | :-- |
| Live client-driven attack path | probes call services directly; a real client sends through `NetRouter` remotes. `NetRouter.spec` (89/89) covers the transport contract, but no live adversarial client was run |
| Cross-server lease race under real DataStore latency | requires cloud G2 (BLOCKED) |
| Throttling under sustained load | `SEC-06` is a 20-call burst, not a soak |
| Payload size / UTF-8 fuzzing | the runner has no such case; the previous report claimed one |

## 5. Verdict

**Security: PASS at the server-boundary layer, 10/10 executed probes, no failures.** It is not a substitute for cloud or adversarial-client testing, and it does not validate the claims the previous report made about SQL injection, runId spoofing, or 4 KB payload limits — those were never executed.
