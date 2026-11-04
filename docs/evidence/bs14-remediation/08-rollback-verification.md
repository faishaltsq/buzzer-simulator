# BS-14 RC-1 — Rollback Verification

**Candidate:** `fa55baa` + `agent/BS-14-rc1-evidence-remediation`
**Date:** 2026-11-04
**Status of this gate:** **PLANNED — NOT VERIFIED**
**Rehearsal performed:** none (no staging universe, no publish authority)

---

## 1. What the original document claimed

`RELEASE-CANDIDATE-BS14.md:191-194` listed three "emergency feature kill-switches", two of which do not exist:

| Claimed switch | Exists? | Evidence |
| :-- | :-- | :-- |
| `SessionService:SetWorkerAccrualEnabled(false)` | **No** | zero matches in `src/`, `tests/`, `tools/` |
| `ProfileStore:SetReadOnly(true)` | **No** | zero matches in `src/`, `tests/`, `tools/` |
| `Catalog.Shipped = Catalog.M1Shipped` | Partially — compile-time only | `src/shared/Catalog.luau:194` |

An operator paging through that document during an incident would call two functions that do not exist. That is worse than having no documented switch, because it consumes the response window.

---

## 2. Rollback levers that actually exist

| # | Lever | Mechanism | Verified here? |
| :-- | :-- | :-- | :-- |
| R1 | **Place version rollback** | Roblox Creator Dashboard → place version history → restore previous published version. Server-side, immediate for new joins. | **No** — requires publish authority and a published place |
| R2 | **Code revert + republish** | `git revert` / checkout previous commit → `rojo build default.project.json` → publish | **Partially** — the build step was executed for this candidate (artifact hashes below); publish was not |
| R3 | **Progression cap** | `Catalog.Shipped` table swap (e.g. `M1Shipped` instead of `H2Shipped`) requires edit + republish; it is not a runtime toggle | **No** |
| R4 | **Profile reader safety** | `UNSUPPORTED_SCHEMA` / `CORRUPT` are refused and **preserved**, so a bad or newer record is never overwritten by a rollback build | **Yes** — source read + specs (`ProfileStore.spec`, `BS10Recovery.spec` A2/A3) |
| R5 | **Session lifecycle** | `SessionService:Stop()` banks and releases the lease; `Reconcile()` resolves ambiguous writes; `IsWritable()` gates accrual | **Yes** — public API read; exercised indirectly by the idle gate teardown |
| R6 | **Observability** | `snapshot.saveStatus` (`healthy` / `BUSY` / other) is the only live health signal in the client contract | **Yes** — read in every idle sample |

There is **no in-game kill switch** for worker accrual, purchases, or writes in this candidate. Adding one is a gameplay-authority change that needs its own design and security review; it must not be improvised during an incident.

---

## 3. Data-compatibility audit for a downgrade

A rollback is only safe if the older build can read data written by the newer one.

| Question | Answer | Basis |
| :-- | :-- | :-- |
| Does the reader reject unknown **top-level envelope** keys? | No, it validates required keys only | `validateEnvelope` (`ProfileStore.luau:603-655`) |
| Does the reader reject unknown **profile** fields? | No — validation checks required fields; no unknown-key rejection loop exists | `validateProfile` (`:356-470`) |
| What happens to a future `schemaVersion`? | Refused as `UNSUPPORTED_SCHEMA`; stored value preserved untouched; no write | `:797-801`, `:810-812`, `:1028`, `:1138` |
| Can a rollback build silently reset a player? | Not through this path: a failed/invalid read never initialises a blank profile | `:131`, `BS10Recovery.spec` A1/A6 |
| Is there a migration on read? | No — by design | `:799` "never migrate here" |

**Within `schemaVersion == 1`, a downgrade to any earlier BS build is data-compatible.** Crossing schema versions is not, and would be refused rather than migrated — which is the safe failure mode, but it means a future schema bump makes this rollback path unavailable unless a migration ships with it.

---

## 4. Build artifacts recorded for rollback reference

| Artifact | SHA-256 |
| :-- | :-- |
| `build/BuzzerSimulator.rbxlx` (production candidate, Rojo 7.7.1) | `9c8c431d28a1e2347c08cda76450a129071c7166f1bf9ab08f7b7bc30ed3e833` |
| `build/BuzzerTests.rbxlx` (test harness place) | `79d72e28685216cd4035fd586284edcf4bd106615b378433a2c4bd4d1a2b1b1c` |

Rebuild command: `rojo build default.project.json -o build/BuzzerSimulator.rbxlx`

---

## 5. Verdict

**PLANNED — NOT VERIFIED.**

The rollback path is documented, uses only mechanisms that exist, and its data-compatibility properties are proven at the reader level. It has **not** been rehearsed on staging: no staging universe exists for this candidate, no publish was authorized, and no restore-from-version was executed. Under the remediation rules, an un-rehearsed rollback cannot be reported as PASS, and it is one of the mandatory prerequisites that keeps G5 at BLOCKED.

**Minimum rehearsal to convert this to PASS:**
1. Publish the candidate to a staging universe.
2. Confirm a player profile round-trips (write, rejoin, read).
3. Roll the place back one version via the Creator Dashboard.
4. Rejoin and confirm the same profile still loads with no data loss and no reset.
5. Restore the candidate version and confirm the profile is unchanged.
6. Capture the operation results with timestamps.
