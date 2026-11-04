# 09 — Future-Proof Expansion Hooks

> **Covers**: §L Future-Proof Expansion Hooks.
> **Status**: Planning. Nothing here is authorized for implementation.

Each hook must be **visible, cheap, and reversible** in M2. "Planned, not
overbuilt" means: a silhouette, a locked prompt, a named anchor, or a folder —
never a half-built system.

---

## Hook index

| Hook | Anchor in M2 | Visible from | Cost now | Cost later | Gate |
|---|---|---|---|---|---|
| Office District | `City_Prompt_FutureGate` | gate, skyline | 0 (gate exists) | 3–5 dev-days | schema v2 |
| Influencer District | east skyline silhouette | window, plaza | 0 (backdrop) | 4–6 dev-days | M2-C+ |
| Agency Tower | backdrop shape | bedroom window | 8 parts (backdrop) | high (interior) | future chapter |
| Transport Gate | `City_TransitStop` | town center | 10 parts | 1–2 dev-days | Office District |
| Rooftop Venue | stair stub on shop row | shop row | 0–6 parts | 2–3 dev-days | all 6 stamps |
| Seasonal Festival Zone | `EventPlaza` | plaza | 0 (reuses Z5) | 2–4 dev-days/festival | director |

---

## 1. Office District

**Fantasy:** the player's studio gets an office address. Desks, a meeting room,
a reception, and a view of the plaza.

**Hook shipped in M2:** the locked gate at Z7, a district map poster, a visible
road continuing past the gate, and the anchor `City_Zone_FutureGate`.

**When it opens:** after a three-brief city quest chain (authored later) and a
schema v2 `cityUnlocks.office = true` flag.

**Cost now:** zero beyond the gate (already in M2-A/B).

**Cost later:** new district shell (~400 parts), interior camera plan, office
desk slots, a second room-like space. This is **not** a bedroom replacement.

**What not to build now:** no interior, no elevator, no NPC receptionist, no
office furniture catalog.

**Risk:** an office interior reintroduces the closed-room camera problem the
open-front shops avoid. Budget a camera/spatial prototype before art.

---

## 2. Influencer District

**Fantasy:** the loud part of the city — studios, backdrops, a ring light, a
"collab" corner. Satire target, not a real influencer economy.

**Hook shipped in M2:** one east-side skyline silhouette and a poster on the
ElectroMart wall ("Distrik Kreator — segera").

**When it opens:** M2-C+ or a later chapter; no date promised.

**Cost now:** zero (backdrop + poster).

**Cost later:** 300–500 parts, one new cosmetic category, possibly a photo-spot
interaction (cosmetic only).

**What not to build now:** no photo mode, no follower count, no brand deals, no
new currency.

**Risk:** scope explosion around "content creator" mechanics. Keep it a place,
not a system.

---

## 3. Agency Tower

**Fantasy:** the horizon. The tower the player looks at from the bedroom window
and eventually enters.

**Hook shipped in M2:** the backdrop silhouette at `z -192…-112`, with two
blinking antenna lights. It is `Persistent`, ≤ 8 parts, non-collidable,
non-reachable.

**When it opens:** a future chapter, after measured M1/M2 retention. Not in any
M2 phase.

**Cost now:** 8 parts.

**Cost later:** very high (interior floors, elevator, staff systems). Requires a
separate architecture decision and probably a new chapter economy.

**What not to build now:** no interior, no lobby, no "agency" button anywhere in
the UI (explicitly forbidden by `docs/06`).

**Risk:** promising an agency the game cannot deliver. The tower is a painting
until a chapter is approved.

---

## 4. Transport Gate (bus stop)

**Fantasy:** the city is connected. Fast travel between districts.

**Hook shipped in M2:** `City_TransitStop` at `(24, 0, 96)`, a dressed shelter
with a "Belum beroperasi" sign. Inert in M2-A/B.

**When it opens:** when a second walkable district exists (M2-C at the
earliest).

**Cost now:** 10 parts.

**Cost later:** 1–2 dev-days (district stop list, fade teleport, one prompt).

**What not to build now:** no route map, no schedule timer, no vehicle, no
loading screen.

**Risk:** fast travel can erase the compact-city pacing. Only add it once the
map is genuinely larger than a 12-second walk.

---

## 5. Rooftop Venue

**Fantasy:** a small event stage above the shop row — the "special" event
location that isn't the plaza.

**Hook shipped in M2:** a closed stair door on the east shop row with a
`City_Signpost_06` stamp anchor nearby and a "naik ke atap" sign with no
interaction.

**When it opens:** after all 6 landmark stamps are collected (cosmetic-only
unlock), or a director-approved event window.

**Cost now:** 0–6 parts (stair door + sign).

**Cost later:** 2–3 dev-days (roof shell, railings, one event stage, camera
test).

**What not to build now:** no stairs the player can climb, no roof geometry
above the shops (it would change the silhouette and the streaming budget).

**Risk:** vertical traversal breaks the flat-grade contract and the camera
assumptions. Prototype it separately before committing.

---

## 6. Seasonal Festival Zone

**Fantasy:** the plaza changes for a week — banners, stalls, lights, a stage.

**Hook shipped in M2:** the event plaza permanent shell with an empty-lot
fallback and a "Jadwal minggu ini" board.

**When it opens:** director-scheduled windows (F5).

**Cost now:** zero (plaza already exists).

**Cost later:** 2–4 dev-days per festival, art-dominated; reuse
`EventPlaza_PopUp.rbxmx` variants.

**What not to build now:** no festival-specific currency, no limited cosmetic
FOMO copy, no automatic seasonal calendar.

**Risk:** art cost with no retention return. Fund only after the base city is
live and measured.

---

## 7. Hook discipline

A hook is allowed in M2 only if it satisfies **all** of these:

1. It costs ≤ 10 BaseParts or ≤ 1 anchor.
2. It is visibly distinct from finished content (locked, dim, signed "segera").
3. It does not accept input beyond a single honest locked prompt.
4. It does not imply a price, date, or feature that is not approved.
5. It can be deleted without touching another system.

Hooks that fail these are not hooks — they are promises the team cannot keep.

---

## 8. What the horizon should feel like

```text
        ┌───────────────┐
        │ AGENCY TOWER  │  ← visible from the desk, not reachable
        │  (painting)   │
        └───────────────┘
              ▲
              │ someday
        ┌─────┴─────┐
        │  OFFICE   │  ← locked gate, no date
        │  DISTRICT │
        └─────┬─────┘
              ▲
              │ M2-C
        ┌─────┴─────┐
        │   CITY    │  ← M2-A/B, fully playable
        │   HUB     │
        └───────────┘
```

The player should finish M2 thinking *"there is more out there"*, not
*"there is a button I can't press."*
