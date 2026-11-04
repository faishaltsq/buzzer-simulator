# BS-14 RC-1 — Human Uncoached Playtest

**Date:** 2026-11-04
**Gate status:** **BLOCKED — no human participants, no authorized playable build.**

---

## 1. Why this gate is blocked

| Requirement | Status |
| :-- | :-- |
| Authorized, joinable candidate build | **absent** — candidate exists only as a local `.rbxlx`; publishing is out of scope |
| External participants (3–5, exploratory sample) | **none recruited** |
| Consent / anonymity process for recording observations | **not established** |
| Session capture tooling for human sessions | **not available** (no published place to join) |

No human playtest was conducted for this remediation. Nothing in this document reports a participant observation, because none exists.

---

## 2. What is explicitly *not* human evidence

`05-automated-journey-summary.md` describes an **automated** run driven through `StudioClientBridge` with a scripted mission/template sequence. It exercises the real client action path and produces genuine server-confirmed state, but it cannot answer any usability question: discoverability, confusion, pacing, or intent to return.

The previous release report presented an equivalent automated run as an "Unguided Player Journey" gate with "17/17 Milestones Validated" (`RELEASE-CANDIDATE-BS14.md:134-157, 217`). That conflation is the reason this gate is now called out separately and marked BLOCKED instead of inheriting a PASS.

---

## 3. Protocol to run when unblocked

Sample: 3–5 external players, exploratory usability sample only — explicitly not statistical evidence. Neutral instruction: "Try the game; think aloud if you like." No tutorial, no hints, no mission guidance from the facilitator.

Record per participant:

| Field | Type |
| :-- | :-- |
| Anonymous tester id (T1…Tn) | string |
| Device type (phone model / emulator / desktop) | string |
| Prior Roblox experience (none / some / heavy) | enum |
| First interaction (what they tapped first) | observation |
| Time to first successful post | seconds |
| Time to first mission claim | seconds |
| Time to first device upgrade | seconds |
| Did they articulate active vs passive earnings? | yes/no + quote |
| Confusion around worker purchase / hire | notes |
| Reaction to progression pacing | notes |
| Did they complete the Home Studio chapter? | yes/no + elapsed |
| Did they notice the visual upgrades (desk, trainee, room)? | yes/no |
| Did they spontaneously ask about leaving the bedroom / a city? | yes/no + quote |
| Session end reason and return intention | notes |

Analysis rules:
- Report per-participant rows plus a plain summary; do not aggregate into a percentage score with n ≤ 5.
- Separate observation from interpretation in every row.
- Any quote must be verbatim from the session; paraphrases must be labelled as such.

---

## 4. Gate verdict

**BLOCKED.** Human usability evidence is a mandatory prerequisite for a closed-beta release decision, and it does not exist for this candidate. This is one of the reasons the overall verdict in `09-release-gate-verdict.md` is **BLOCKED — CLOSED BETA NOT AUTHORIZED**, not READY.
