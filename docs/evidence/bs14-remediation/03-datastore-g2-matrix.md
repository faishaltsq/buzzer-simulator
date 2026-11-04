# BS-14 RC-1 — DataStore G2 Matrix

**Candidate:** `fa55baa` + remediation branch `agent/BS-14-rc1-evidence-remediation`
**Date:** 2026-11-04
**Verdict for this gate:** **BLOCKED** — no cloud DataStore operation was executed against this candidate.

---

## 1. Why this gate is blocked

| Prerequisite | Required | Actual |
| :-- | :-- | :-- |
| Published staging universe, isolated from production | yes | **none available to this session** |
| `studioAccessToApisAllowed` on that universe | true | public lookup for the documented universe `10774181892` returns no game record; the opened place is a local `.rbxlx` file |
| Authorized testing identity | yes | not supplied |
| Director authorization to publish/modify a place | yes | **not granted** — publishing is explicitly out of scope for this task |
| Destruction of test-only keys (never production keys) | required | not reached |

`ProfileStore.luau:120-138` resolves a real `DataStoreService` handle and otherwise logs:

```
[ProfileStore:DEV_FALLBACK] DataStore handle 'PlayerData' unavailable in offline Studio (...).
Using ephemeral in-memory store for local Studio session only. Real DataStore G2 remains OPEN.
```

That warning is what a local Studio session produces. It is visible in the console history for this session, and it is the code's own statement that cloud G2 is open. Nothing in this remediation may pass G2 on the strength of a local run.

**No data was read, written, or deleted in any cloud DataStore during this audit.**

---

## 2. Evidence layers

| Layer | Meaning | Status in this remediation |
| :-- | :-- | :-- |
| **A** | Unit / spec tests of store logic with a fake transport | **PASS** — `ProfileStore.spec` 59/59, `BS10Recovery.spec` 42/42 |
| **B** | Injected adapter with latency, throttle and ambiguous-success injection | **PASS** — `tools/agent/run_persistence_audit.py` (7 cases) |
| **C** | Local Studio with actual cloud access | **BLOCKED** — no published place with API access |
| **D** | Published staging servers, server-to-server | **BLOCKED** — no authorized staging universe |
| **E** | Production validation | **NOT AUTHORIZED** — out of scope |

Only C and D can satisfy G2. A and B are necessary but not sufficient.

---

## 3. Verification matrix

Legend: **A/B** = proven by spec or injected adapter; **C** = local Studio with cloud access; **D** = published staging servers.

| # | Case | A/B coverage (executed) | C | D | Gate status |
| :-- | :-- | :-- | :-- | :-- | :-- |
| 1 | Fresh profile created and durably saved | `ProfileStore.spec`: "Load on a fresh key acquires a 240s lease and no profile"; `BS10Recovery.spec` A6 | BLOCKED | BLOCKED | **BLOCKED** |
| 2 | Real server exit and new server join | `BS10Recovery.spec` E1/E2 (two sessions, same key) | BLOCKED | BLOCKED | **BLOCKED** |
| 3 | Currency survives rejoin | `BS10Recovery.spec` B1/B4/C1 | BLOCKED | BLOCKED | **BLOCKED** |
| 4 | Mission claims survive rejoin | `BS10Recovery.spec` B4 | BLOCKED | BLOCKED | **BLOCKED** |
| 5 | PC Rumah survives rejoin | `BS10Recovery.spec` C1/C2/C3 | BLOCKED | BLOCKED | **BLOCKED** |
| 6 | Both desks survive rejoin | `BS13HomeStudio.spec` (44/44) covers desk ownership persistence in service space | BLOCKED | BLOCKED | **BLOCKED** |
| 7 | Both workers survive rejoin | `BS12WorkerEconomy.spec` (21/21) + `BS13HomeStudio.spec` | BLOCKED | BLOCKED | **BLOCKED** |
| 8 | Worker rate recomputed after rejoin | `BS12WorkerEconomy.spec`; rate derived, not stored (`EconomyService.incomePerSecond`) | BLOCKED | BLOCKED | **BLOCKED** |
| 9 | Confirmed banking survives rejoin | `BS12WorkerEconomy.spec`; `_applyWorkerAccrual` commits only after durable save | BLOCKED | BLOCKED | **BLOCKED** |
| 10 | No income earned while offline | source contract: `SessionService.luau:686-702` (accrual only while `IsWritable()`); `BS10Recovery.spec` A1 | BLOCKED | BLOCKED | **BLOCKED** |
| 11 | Lease conflicts handled safely | `ProfileStore.spec`: live foreign lease LOCKED, expired acquirable; `BS10Recovery.spec` A4/A5/E1 | BLOCKED | BLOCKED | **BLOCKED** |
| 12 | Stale revisions rejected | `ProfileStore.spec`: "A stale snapshot revision aborts instead of overwriting"; `BS10Recovery.spec` E3 | BLOCKED | BLOCKED | **BLOCKED** |
| 13 | Ambiguous writes reconciled | `ProfileStore.spec`: "An ambiguous write resolves through the same operation ID"; `BS10Recovery.spec` C3/B5 | BLOCKED | BLOCKED | **BLOCKED** |
| 14 | Duplicate operation IDs never double-credit | `ProfileStore.spec`: "An identical operation ID is idempotent"; B6 settlement-cache guard | BLOCKED | BLOCKED | **BLOCKED** |
| 15 | Failed read never overwrites with starter data | `BS10Recovery.spec` A1, A2, A6 | BLOCKED | BLOCKED | **BLOCKED** |
| 16 | Corrupt / future-schema envelopes preserved | `ProfileStore.spec`: "Load preserves an unsupported future schema without migrating"; `BS10Recovery.spec` A2/A3 | BLOCKED | BLOCKED | **BLOCKED** |
| 17 | Shutdown and reconnect lose no confirmed transactions | `BS10Recovery.spec` E1/E2/E3 | BLOCKED | BLOCKED | **BLOCKED** |

**Gate result: 0 / 17 at layer C or D. G2 = BLOCKED.**

---

## 4. What the A/B evidence does establish

It would be wrong to read this as "nothing is known". The executed layers prove, in-service and under injected failure:

- Conditional writes only (`UpdateAsync`), never blind `SetAsync` (`ProfileStore.luau:7-8`).
- Lease CAS on token + expiry, renewal at 90 s, expiry at 240 s.
- Revision monotonicity; stale revisions abort rather than overwrite.
- Ambiguous outcomes resolved by re-reading the backend with a no-cache option, not by trusting local cache.
- Unknown/future `schemaVersion` preserved byte-for-byte; corrupt payloads rejected and preserved.
- Save-path failures (`SAVE_UNAVAILABLE`, `BUSY`) leave the mutation `UNKNOWN`, never cached as a rejection — this is the BS-14 B6 fix.

What they cannot prove: real timeout distribution, real 301 throttling under player load, cross-server propagation latency, DataStore outage behaviour, or region/replication effects. Those are precisely the G2 risks.

---

## 5. Minimum unblocking procedure (for the director)

1. Create or confirm a **staging universe** separate from production; record UniverseId and PlaceId from the Creator Dashboard (not from documentation).
2. Publish the candidate build to that universe; enable *Studio Access to API Services*.
3. Authorize a testing identity and a disposable user id range.
4. Run the matrix rows 1–17 at layer C, then at layer D with two live servers.
5. Sanitize identifiers in the captured evidence; never include player keys or `Player_{userId}` values verbatim.
6. Record the operation results per row; only then can G2 be marked PASS.

Until step 6 completes, any G2 PASS claim is unsupported by construction.
