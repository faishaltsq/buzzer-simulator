"""Draw the M2-G1 director review boards: D1-D8 comparisons and contract overlays.

Planning evidence only — a drawing, never a Roblox Studio capture. One pixel-space
scene feeds PNG, SVG and native Excalidraw. Requires Pillow. No game asset or
runtime setting is modified; run from any working directory.

Every coordinate below is either read from the parent tables
(`02-WORLD-STRUCTURE.md`, `03-ZONE-SPECIFICATIONS.md`) or derived arithmetically
from verified `Bedroom.rbxmx` anchors. `verify_g1_review.py` re-derives the
arithmetic and asserts layout invariants.
"""
import json
import math
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
WIDTH, HEIGHT = 2600, 5260
BG, INK, RED, AMBER, GREEN, BLUE = "#FBF8F1", "#202A2D", "#AD3F35", "#99704B", "#506C56", "#3D5A80"
NAVY = "#344451"
FROZEN, PROPOSED, TESTREQ, APPROVED = GREEN, RED, AMBER, BLUE


def font(size):
    for name in ("C:/Windows/Fonts/arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    raise RuntimeError("Install Arial or DejaVu Sans for measurable board labels")


class Panel:
    """A world-space viewport at a fixed pixel origin and scale.

    Keeps each sub-diagram in its own band of the sheet so panels never overlap,
    unlike the single global frame used by the M2-A0 masterplan. `span` is the
    world extent the panel must contain; the origin is derived from it so no
    primitive can be pushed off the canvas, and `fit=True` centres the viewport
    in the band it owns.
    """

    def __init__(self, shapes, ox, oy, scale, span=None, fit=False, band=None):
        self.sh, self.ox, self.oy, self.s = shapes, ox, oy, scale
        if fit and span:
            x0, x1 = band or (60, WIDTH - 60)
            self.ox = x0 + ((x1 - x0) - (span[1] - span[0]) * scale) / 2

    def px(self, x, z):
        return self.ox + x * self.s, self.oy + z * self.s

    def rect(self, x0, z0, x1, z1, fill, stroke=INK, sw=1):
        ax, ay = self.px(x0, z0)
        self.sh.append(dict(type="rectangle", x=ax, y=ay, w=(x1 - x0) * self.s,
                            h=(z1 - z0) * self.s, fill=fill, stroke=stroke, sw=sw))

    def circle(self, x, z, r, fill, stroke=INK, sw=2):
        ax, ay = self.px(x - r, z - r)
        self.sh.append(dict(type="ellipse", x=ax, y=ay, w=2 * r * self.s,
                            h=2 * r * self.s, fill=fill, stroke=stroke, sw=sw))

    def line(self, a, b, color=INK, sw=2):
        ax, ay = self.px(*a)
        bx, by = self.px(*b)
        self.sh.append(dict(type="line", x=ax, y=ay, w=bx - ax, h=by - ay,
                            fill="transparent", stroke=color, sw=sw))

    def dashed(self, x0, z0, x1, z1, color=RED, sw=2):
        corners = [self.px(x0, z0), self.px(x1, z0), self.px(x1, z1), self.px(x0, z1)]
        for a, b in zip(corners, corners[1:] + corners[:1]):
            d = math.dist(a, b)
            for t in range(0, math.ceil(d), 18):
                u, v = t / d, min(t + 10, d) / d
                ax, ay = a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u
                bx, by = a[0] + (b[0] - a[0]) * v, a[1] + (b[1] - a[1]) * v
                self.sh.append(dict(type="line", x=ax, y=ay, w=bx - ax, h=by - ay,
                                    fill="transparent", stroke=color, sw=sw))


def text(sh, x, y, value, size=17, color=INK):
    sh.append(dict(type="text", x=x, y=y, w=math.ceil(font(size).getlength(value)) + 3,
                   h=math.ceil(size * 1.3), text=value, size=size, fill="transparent",
                   stroke=color, sw=1))


def rule(sh, y):
    sh.append(dict(type="line", x=60, y=y, w=2480, h=0, fill="transparent",
                   stroke=INK, sw=3))


def section(sh, y, heading, note=None):
    text(sh, 60, y, heading, 30)
    rule(sh, y + 38)
    if note:
        text(sh, 60, y + 52, note, 17, TESTREQ)


def block(sh, x, y, title, rows, color=INK, tsize=20, bsize=16, gap=24):
    text(sh, x, y, title, tsize, color)
    for i, row in enumerate(rows):
        text(sh, x, y + 32 + i * gap, row, bsize)


def legend(sh, x, y):
    for i, (name, color, note) in enumerate((
            ("FROZEN BASELINE", FROZEN, "merged, unchanged"),
            ("PROPOSED CHANGE", PROPOSED, "awaiting director"),
            ("TEST REQUIRED", TESTREQ, "not verifiable in 2D"),
            ("DIRECTOR APPROVED", APPROVED, "none yet in this package"))):
        yy = y + i * 30
        sh.append(dict(type="rectangle", x=x, y=yy + 5, w=26, h=18, fill=color,
                       stroke=INK, sw=1))
        text(sh, x + 38, yy, f"{name} — {note}", 17)


# ------------------------------------------------------------------ verified
# Read-only inspection of assets/world/Bedroom.rbxmx (never edited by this package).
CAMERA = (7.0, 5.5, 3.0)                                   # CameraFocus part
GLASS = dict(center=(3.0, 5.5, -12.08), size=(5.8, 4.8, 0.08))   # WindowGlass
APER_X = (GLASS["center"][0] - GLASS["size"][0] / 2, GLASS["center"][0] + GLASS["size"][0] / 2)
APER_Y = (GLASS["center"][1] - GLASS["size"][1] / 2, GLASS["center"][1] + GLASS["size"][1] / 2)
DOOR = (-6.0, 3.65, 11.6)                                  # frozen collidable Door part
HOMEDOOR = (-6.0, 3.65, 16.0)                              # City_HomeDoor (exterior face)
CITY_SPAWN = (-6.0, 0.6, 20.0)                             # City_Spawn
BOARDS = (0.0, 3.0, 68.0)                                  # City_Prompt_Boards

# Parent table values.
ZONES = [("Z0 Home plot", -24, 24, -24, 16), ("Z1 Street", -24, 24, 16, 64),
         ("Z2 Town center", -56, 56, 64, 160), ("Z3 East shop row", 56, 80, 72, 144),
         ("Z4 West furniture", -80, -56, 72, 96), ("Z5 Event plaza", -136, -80, 104, 164),
         ("Z6 Boards kiosk", -12, 12, 64, 72), ("Z7 Future gate", -8, 8, 160, 176)]
ANCHORS = [("City_Spawn", -6, 20), ("City_HomeDoor", -6, 16), ("City_DoorPromptInterior", -6, 8),
           ("City_Prompt_Boards", 0, 68), ("City_Prompt_ElectroMart", 68, 84),
           ("City_Prompt_RumahRapi", -68, 84), ("City_Prompt_Cosmetics", 68, 108),
           ("City_Prompt_Utility", 68, 132), ("City_Prompt_EventPlaza", -108, 110),
           ("City_Prompt_FutureGate", 0, 168), ("City_TransitStop", 24, 96),
           ("City_Zone_Street", 0, 40), ("City_Zone_TownCenter", 0, 112),
           ("City_Zone_ShopEast", 68, 108), ("City_Zone_ShopWest", -68, 84),
           ("City_Zone_EventPlaza", -108, 134), ("City_Zone_FutureGate", 0, 168)]
BACK_Z = -152.0                                            # midpoint of -192 .. -112
BASE_BACK = (16.0, 160.0)                                  # parent baseline backdrop X
PROP_BACK = (-120.0, 120.0)                                # proposed centred X


def window_slice(z=BACK_Z):
    """Project the window aperture from the desk camera onto a plane at depth z."""
    dz_win = GLASS["center"][2] - CAMERA[2]
    dz = z - CAMERA[2]
    xs = tuple(CAMERA[0] + (x - CAMERA[0]) * dz / dz_win for x in APER_X)
    ys = tuple(CAMERA[1] + (y - CAMERA[1]) * dz / dz_win for y in APER_Y)
    return xs, ys


SLICE_X, SLICE_Y = window_slice()


def coverage(span, ref):
    """Fraction of the reference slice covered by a backdrop X span."""
    return max(0.0, min(span[1], ref[1]) - max(span[0], ref[0])) / (ref[1] - ref[0])


# -------------------------------------------------------------------- scene
def scene():
    sh = []
    text(sh, 60, 28, "BUZZER SIMULATOR | M2-G1 CITY DESIGN ACCEPTANCE", 34)
    text(sh, 60, 76, "Coordinate freeze, visual decisions D1-D8, 3D blockout readiness — director review package.", 20)
    text(sh, 60, 110, "Planning evidence only: a drawing, never a Roblox Studio capture. Baseline master 09eb88d626d73057543fe419a2c0925063d1df09.", 17, TESTREQ)
    text(sh, 60, 142, "Values traced to parent tables and to verified Bedroom.rbxmx anchors. North = -Z, east = +X. No approval inferred from any view.", 17)
    legend(sh, 1660, 34)

    # ================================================== 1 | full city top-down
    section(sh, 200, "1 | FULL CITY TOP-DOWN — frozen baseline with overlays",
            "Scale 4 px/stud. Zones and anchors are the parent contract; dashed red items are proposals that are NOT adopted here.")
    p = Panel(sh, 140, 380, 4, span=(-136, 80), fit=True)
    fills = ["#E9DEC7", "#DBD3BE", "#EEE8DD", "#ECDBC3", "#D8C2A8", "#DCE5D9", "#F6ECD8", "#D1D6DA"]
    for (name, x0, x1, z0, z1), f in zip(ZONES, fills):
        p.rect(x0, z0, x1, z1, f)
    p.rect(-13.35, -13.35, 13.35, 13.35, "#DBD3BE")
    p.rect(-8.5, 13.35, -3.5, 16, "#99704B")
    p.rect(-16, 16, 16, 64, "#6E7773")
    p.circle(0, 112, 40, "#E9DEC7")
    p.circle(0, 112, 8, "#96B2B1")
    for x0, z0, x1, z1 in [(56, 72, 80, 96), (56, 120, 80, 144), (-80, 72, -56, 96)]:
        p.rect(x0 + 1, z0 + 1, x1 - 1, z1 - 1, "#B48B60")
    p.dashed(56, 96, 80, 120)
    p.dashed(-12.6, -12.6, 12.6, 12.6, FROZEN)
    p.rect(-6, 64, 6, 72, "#84977E")
    p.dashed(4, 65, 16, 71)
    p.rect(-8, 160, 8, 176, "#84977E")
    for path in [[(-6, 20), (-6, 40), (-4, 56), (-14, 64), (-16, 80), (0, 88)],
                 [(0, 88), (-18, 100), (-18, 124), (0, 140), (0, 158)],
                 [(0, 88), (28, 88), (54, 84)], [(0, 88), (-30, 88), (-54, 84)],
                 [(-18, 124), (-60, 128), (-104, 128)]]:
        for a, b in zip(path, path[1:]):
            p.line(a, b, AMBER, 4)
    for _, x, z in ANCHORS:
        p.circle(x, z, 0.65, RED)
    for x, z in [(14, 62), (-14, 72), (44, 106), (-44, 106), (-84, 140), (14, 136)]:
        p.circle(x, z, 0.5, FROZEN)
    for (name, *_), (x, z) in zip(ZONES, [(-38, -16), (-42, 32), (-54, 150), (85, 72),
                                          (-112, 78), (-134, 154), (-30, 58), (16, 165)]):
        text(sh, *p.px(x, z), name.split()[0], 16)
    block(sh, 1180, 300, "WALKABLE ENVELOPE", [
        "X -136 .. +80 | Z -24 .. +176",
        "216 x 200 studs, architecture-derived",
        "Grade Y = 0; no elevation change in A/B",
        "Frozen bedroom 24x24 at origin",
        "City grows south from the Door plane"], FROZEN)
    block(sh, 1180, 700, "PARENT ANCHOR CONTRACT (17 PARTS)", [
        "City_HomeDoor (-6, 3.65, 16)  physical",
        "City_Spawn (-6, 0.6, 20)",
        "City_DoorPromptInterior (-6, 3.65, 8)",
        "City_Prompt_Boards (0, 3, 68)",
        "City_Prompt_ElectroMart (68, 3, 84)",
        "City_Prompt_RumahRapi (-68, 3, 84)",
        "City_Prompt_Cosmetics (68, 3, 108)",
        "City_Prompt_Utility (68, 3, 132)",
        "City_Prompt_EventPlaza (-108, 3, 110)",
        "City_Prompt_FutureGate (0, 3, 168)",
        "City_TransitStop (24, 0, 96)",
        "5 zone roots + City_LightGroup (Folder)",
        "Never reuse the bedroom's 12 names"], INK)
    block(sh, 1180, 1140, "OVERLAYS SHOWN HERE", [
        "Amber: illustrative route; no passage",
        "  through the closed room wall",
        "Dashed green: 0.6-offset house shell",
        "Dashed red x 4..16 z 65..71: M2-A0",
        "  kiosk proposal — exceeds frozen Z6",
        "  x -12..+12; NOT adopted (view 3)",
        "Dashed red z 96..120: future cosmetics",
        "  lot, a later-phase reservation",
        "Red dots: baseline anchors (frozen)",
        "Green dots: 6 suggested signposts"], TESTREQ)

    # ==================================================== 2 | D1 skyline audit
    section(sh, 1870, "2 | D1 SKYLINE / BACKDROP ALIGNMENT — baseline X=16..160 versus proposed X=-120..120",
            "Same Z extent -192..-112 in both candidates. Rays are the true desk-camera projection of the frozen window aperture.")
    p = Panel(sh, 200, 1970, 2, span=(-120, 120), fit=True)
    p.rect(BASE_BACK[0], -192, BASE_BACK[1], -112, NAVY)
    p.dashed(PROP_BACK[0], -192, PROP_BACK[1], -112)
    p.line(CAMERA[:1] + (CAMERA[2],), (SLICE_X[0], BACK_Z), FROZEN, 2)
    p.line(CAMERA[:1] + (CAMERA[2],), (SLICE_X[1], BACK_Z), FROZEN, 2)
    p.line((SLICE_X[0], BACK_Z), (SLICE_X[1], BACK_Z), FROZEN, 5)
    p.circle((SLICE_X[0] + SLICE_X[1]) / 2, BACK_Z, 1.5, "#ECBA6F")
    p.circle(CAMERA[0], CAMERA[2], 1.5, FROZEN)
    p.dashed(SLICE_X[0], BACK_Z - 40, SLICE_X[1], BACK_Z + 40, TESTREQ)
    text(sh, 60, 1970, "CameraFocus", 16, FROZEN)
    block(sh, 1180, 1970, "WINDOW PROJECTION (recomputed)", [
        "CameraFocus part (7, 5.5, 3.0)",
        "WindowGlass aperture x 0.10 .. 5.90",
        "  at z = -12.08, y 3.10 .. 7.90",
        f"projects to x {SLICE_X[0]:.2f} .. {SLICE_X[1]:.2f}",
        f"  at the reference plane z = -152",
        "Green band = the only sky visible",
        "  from the desk; all else occluded"], FROZEN)
    block(sh, 1180, 2210, "COVERAGE AT z = -152", [
        "Baseline X=16..160 covers 0% of the slice",
        "Proposed X=-120..120 covers 100%",
        "Slice width 59.6 studs at that depth",
        "House shell z -12.6..+12.6 is 124.6 studs",
        "  clear of the backdrop: no intersection",
        "Proposed X stays inside the -136..+80",
        "  city envelope, so no background breach"], RED)
    block(sh, 60, 2180, "D1 RECOMMENDATION", [
        "Adopt the proposed centred extent X=-120..120 as the candidate for isolated Studio verification;",
        "keep X=16..160 as the frozen baseline until a real camera view confirms the candidate.",
        "Director guidance is explicit: do not freeze new coordinates on a 2D projection alone."], TESTREQ)

    # ================================================= 3 | D2 kiosk variants
    section(sh, 2380, "3 | D2 KIOSK — standard solid versus narrow open-frame, both inside frozen Z6",
            "Zone Z6 stays x -12..+12, z +64..+72. The prompt anchor (0, 3, 68) is not moved by either candidate.")
    for i, (name, note, color) in enumerate((
            ("A | STANDARD SOLID KIOSK", "Solid 10-stud panel blocks the plaza sightline from the stoop", TESTREQ),
            ("B | NARROW OPEN-FRAME KIOSK", "Two 1-stud posts and a 5-stud band; fountain stays visible", FROZEN))):
        ox = 60 + i * 1250
        p = Panel(sh, ox, 2500, 12, span=(-16, 16), fit=True,
                  band=(60 + i * 1250, 60 + i * 1250 + 1160))
        p.rect(-12, 64, 12, 72, "transparent", BLUE)
        p.rect(-16, 80, 16, 88, "transparent", TESTREQ)
        if i == 0:
            p.rect(-5, 65, 5, 71, "#84977E")
            p.rect(-1.5, 65, 1.5, 71, "#6E7773")
        else:
            p.rect(-2.5, 65, -1.5, 71, "#84977E")
            p.rect(1.5, 65, 2.5, 71, "#84977E")
            p.rect(-3, 69.5, 3, 70.5, "#84977E")
        p.circle(0, 68, 0.65, RED)
        p.line((0, 68), (0, 88), FROZEN, 2)
        p.line((0, 88), (0, 104), FROZEN, 2)
        p.circle(0, 112, 8, "#96B2B1")
        p.dashed(0, 104, 0, 120, TESTREQ)
        text(sh, ox, 2500, name, 22, color)
        text(sh, ox, 2532, note, 16, color)
        text(sh, ox, 2560, "Width 6 studs (B) vs 10 (A) | height 6.0 | posts 5 studs apart", 15)
        text(sh, ox, 2566 + 26, "Route clearance 6 studs each side | BaseParts ~10 | prompt at (0, 3, 68)", 15)
        text(sh, ox, 2566 + 52, "Fountain visible from the stoop: A NO / B YES", 15, FROZEN)
        text(sh, ox, 2566 + 78, "Sign readable on a 360x640 phone: A YES / B YES", 15, FROZEN)
        text(sh, ox, 2566 + 104, "Mobile camera obstruction: A HIGH / B LOW", 15, FROZEN)
    text(sh, 60, 2700, "Blue = frozen Z6 extent. Amber = 8-stud plaza edge band. Green rays = stoop -> kiosk -> fountain sightlines.", 16)
    text(sh, 60, 2730, "D2 RECOMMENDATION: build candidate B (narrow open-frame) first. It keeps fountain visibility, walking clearance and mobile", 17, FROZEN)
    text(sh, 60, 2760, "readability simultaneously; the solid panel only wins on sign area, which candidate B can recover with a taller band.", 17, FROZEN)

    # ================================================ 4 | D3 house exterior
    section(sh, 2820, "4 | D3 HOUSE EXTERIOR — front facade and side elevation",
            "Shell wraps the frozen 24x24 room at a 0.6-stud offset (x/z -12.6..+12.6). Grade begins at z=+16. No roof plane in A1.")
    p = Panel(sh, 200, 2950, 6, span=(-9, 9), fit=True, band=(120, 560))
    p.rect(-12, 0, 12, 12, "#E9DEC7")
    p.rect(-12, 11.9, 12, 12, "#DBD3BE")
    p.rect(-7.85, 0, -4.15, 7.3, "#99704B")
    p.rect(0.1, 3.1, 5.9, 7.9, "#96B2B1", FROZEN)
    text(sh, 200, 2950, "FRONT FACADE (from the street)", 18)
    p2 = Panel(sh, 620, 2950, 6, span=(-9, 9), fit=True, band=(560, 1000))
    p2.rect(-5, 0, 5, 12, "#E9DEC7")
    p2.rect(-5, 11.9, 5, 12, "#DBD3BE")
    p2.rect(-7.85, 0, -4.15, 7.3, "#99704B")
    p2.rect(-9, -2.6, 9, 0, "#99704B")
    text(sh, 620, 2950, "SIDE ELEVATION (stoop)", 18)
    block(sh, 1040, 2950, "D3 EXTERIOR CONTRACT", [
        "Doorway cut x -7.85..-4.15, y 0..7.3, aligned to the",
        "  frozen Door part (-6, 3.65, 11.6), never resized",
        "Window aperture (blue) is frozen glass; cladding",
        "  must never cover it (V-03 / window projection)",
        "Parapet at y = 11.9, no roof plane, no interior",
        "  ceiling; roof waits for a camera-collision test",
        "4-stud stoop between Door plane z=11.69 and grade",
        "  z=+16; City_HomeDoor on the exterior face",
        "City_DoorPromptInterior stays inside at z=+8",
        "City_Spawn (-6, 0.6, 20) is 4 studs clear of the shell",
        "Wall returns bridge HomeDoor to the shell",
        "No physical passage through the frozen Door"], FROZEN)

    # ============================================ 5 | main route clearances
    section(sh, 3260, "5 | MAIN ROUTE CLEARANCES — stoop to kiosk to fountain to gate",
            "Scale 2 px/stud. Blue guides mark the 6-stud corridor; the green ring is the 8-stud fountain clearance.")
    p = Panel(sh, 200, 3360, 2, span=(-56, 56), fit=True)
    p.rect(-24, 16, 24, 64, "transparent", BLUE)
    p.rect(-16, 16, 16, 64, "#6E7773")
    p.rect(-56, 64, 56, 160, "#E9DEC7")
    p.circle(0, 112, 48, "transparent", FROZEN)
    p.circle(0, 112, 8, "#96B2B1")
    p.rect(-6, 64, 6, 72, "#84977E")
    p.rect(-8, 160, 8, 176, "#84977E")
    p.dashed(-12.6, -12.6, 12.6, 12.6, FROZEN)
    for a, b in [((-6, 20), (-6, 40)), ((-6, 40), (-6, 60)), ((-6, 60), (-6, 68)),
                 ((-6, 68), (0, 80)), ((0, 80), (0, 104)), ((0, 104), (0, 120)),
                 ((0, 120), (0, 158))]:
        p.line(a, b, AMBER, 4)
    p.circle(0, 68, 0.65, RED)
    p.circle(-6, 20, 0.65, RED)
    block(sh, 1180, 3360, "CLEARANCE CONTRACT", [
        "Walkable clear width >= 6 studs on every path",
        ">= 8-stud ring around the fountain",
        "Road x -16..+16 (32) + 8-stud sidewalks",
        "Lane x -24..+24 is the walkable corridor",
        "Kiosk inside Z6 leaves both lanes open",
        "Door -> kiosk ~56 studs ~3.5 s (estimate)",
        "Door -> fountain ~100 studs ~6.3 s (estimate)",
        "Estimates only; A1 must measure on foot"], BLUE)
    text(sh, 60, 3760, "Red dots: City_Spawn and City_Prompt_Boards. Amber: the single spine route. Estimates, not measured walk times.", 16)

    # ============================================== 6 | D4 shop approach
    section(sh, 3820, "6 | D4 SHOP PROMPT APPROACH — baseline hosts, 10-stud activation, 12-stud validation",
            "Scale 2.5 px/stud. Hosts stay at baseline +/-68; relocation would be a documented amendment, never a silent edit.")
    p = Panel(sh, 200, 3930, 2.5, span=(-80, 80), fit=True)
    p.rect(56, 72, 80, 96, "#B48B60")
    p.rect(-80, 72, -56, 96, "#B48B60")
    p.rect(64, 80, 72, 84, "transparent", FROZEN)
    p.rect(-72, 80, -64, 84, "transparent", FROZEN)
    p.circle(68, 84, 0.65, RED)
    p.circle(-68, 84, 0.65, RED)
    p.dashed(58, 74, 78, 94, BLUE)
    p.circle(68, 84, 12, "transparent", AMBER)
    p.circle(-68, 84, 12, "transparent", AMBER)
    block(sh, 1180, 3930, "APPROACH CONTRACT", [
        "Blue square = 10-stud ProximityPrompt radius",
        "Amber circle = 12-stud server validation radius",
        "  (WorldService.MAX_PROMPT_DISTANCE = 12)",
        "Counter face 4 studs inside the lot edge",
        "Standing position ~6 studs from the host",
        "Avatar root clearance >= 4 studs required",
        "Open-front counter: no closed interior, so no",
        "  camera clipping and no interior lighting cost",
        "No prop may sit between lane and prompt host"], BLUE)
    text(sh, 60, 4150, "D4 CONCLUSION: baseline hosts are reachable inside the existing 10/12 constraints with an open-front counter. No coordinate amendment is", 17, FROZEN)
    text(sh, 60, 4180, "requested. All distances are pre-production estimates until measured in the A1 blockout.", 17, FROZEN)

    # ============================================== 7 | D6 camera sightlines
    section(sh, 4240, "7 | D6 CAMERA EXPERIENCE — nine compositions for M2-A1 Studio capture",
            "Existing camera controller only; no new controller is introduced by M2-G1. None of these is verified without a Studio capture.")
    views = [("1 Bedroom window -> skyline", "desk CameraFocus (7, 5.5, 3.0) looking -Z", FROZEN),
             ("2 Interior door approach", "room centre looking +Z at the Door", FROZEN),
             ("3 First exterior arrival", "City_Spawn (-6, 0.6, 20) facing +Z", TESTREQ),
             ("4 Residential lane", "street centre z ~40 looking +Z", TESTREQ),
             ("5 Mission kiosk", "z ~60 looking +Z at Z6", TESTREQ),
             ("6 Town centre fountain", "plaza edge z ~96 looking +Z", TESTREQ),
             ("7 Shops", "lane centre z ~84 looking east/west", TESTREQ),
             ("8 Future district gate", "z ~150 looking +Z at Z7", TESTREQ),
             ("9 Return home", "stoop z ~18 looking -Z", TESTREQ)]
    for i, (name, pose, color) in enumerate(views):
        x = 60 + (i % 2) * 1250
        y = 4340 + (i // 2) * 46
        text(sh, x, y, name, 19, color)
        text(sh, x + 480, y + 2, pose, 16)
    text(sh, 60, 4560, "Acceptance criteria per view are defined in M2-A1-READINESS.md; screenshot positions must be recorded with pose, aspect and mode.", 16)

    # ================================================= 8 | D7 part budget
    section(sh, 4620, "8 | D7 BASEPART ALLOCATION — allocation ledger, not a measured Studio count",
            "Counting contract: every BasePart once in assembled Workspace.City, invisible markers included inside the allocation.")
    rows = [("HouseExterior shell", 90, "M2-A"), ("StreetBlock", 80, "M2-A"),
            ("TownCenter shell", 140, "M2-A"), ("CityBoards", 40, "M2-A"),
            ("CityGate", 30, "M2-A"), ("North backdrop", 8, "M2-A"),
            ("Shared props instances", 60, "M2-A"), ("M2-A TOTAL", 448, "A"),
            ("TownCenter props", 80, "M2-B"), ("ElectroMart", 120, "M2-B"),
            ("Rumah Rapi (conditional)", 100, "M2-B"), ("Event plaza permanent", 160, "M2-B"),
            ("Utility", 50, "M2-B"), ("M2-B ADDITION", 510, "B"),
            ("Cumulative city", 958, "A+B"), ("City hard cap", 1200, "cap"),
            ("Unallocated headroom", 242, "cap")]
    y = 4740
    text(sh, 60, y - 30, "Pool", 18)
    text(sh, 520, y - 30, "BaseParts", 18)
    text(sh, 700, y - 30, "Phase", 18)
    for name, count, phase in rows:
        bold = name.isupper()
        c = RED if bold else INK
        text(sh, 60, y, name, 17, c)
        text(sh, 520, y, str(count), 17, c)
        text(sh, 700, y, phase, 17, c)
        sh.append(dict(type="rectangle", x=800, y=y + 3, w=int(300 * count / 510), h=14,
                       fill="#AD3F35" if bold else "#D8C2A8", stroke=INK, sw=1))
        y += 26
    block(sh, 1180, 4710, "COUNTING CONTRACT", [
        "Count each BasePart once in the assembled",
        "  Workspace.City, including invisible markers,",
        "  the physical HomeDoor, pivot parts and every",
        "  placed copy of a shared-kit prop",
        "Marker inventory: 22 invisible parts (17",
        "  positioned + 5 signpost positions); only the",
        "  authored subset is charged, enumerated",
        "Library prototypes reported separately",
        "Temporary review helpers removed before evidence",
        "A1 blockout ceiling 450; allocation 448",
        "Bedroom stays on its own <= 350 budget",
        "Bars are relative allocation, not measurements"], INK)
    text(sh, 60, HEIGHT - 76, "Bedroom (155 parts) is excluded here — it lives on its own budget. No exact Studio count exists until a generator produces one.", 16)
    text(sh, 60, HEIGHT - 50, "M2-G1 planning evidence | no approval, FPS, streaming or runtime behaviour is inferred from this drawing.", 17)
    return sh


def render(sh):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
           f'<rect width="100%" height="100%" fill="{BG}"/>']
    elements = []
    for i, p in enumerate(sh):
        x, y, w, h = p['x'], p['y'], p['w'], p['h']
        color, fill = p['stroke'], p['fill']
        if p['type'] == 'text':
            draw.text((x, y), p['text'], font=font(p['size']), fill=color, anchor='lt')
            svg.append(f'<text x="{x}" y="{y}" dominant-baseline="text-before-edge" font-family="Arial, sans-serif" font-size="{p["size"]}" fill="{color}">{escape(p["text"])}</text>')
        elif p['type'] == 'line':
            draw.line((x, y, x + w, y + h), fill=color, width=p['sw'])
            svg.append(f'<line x1="{x}" y1="{y}" x2="{x+w}" y2="{y+h}" stroke="{color}" stroke-width="{p["sw"]}"/>')
        else:
            shape = draw.rectangle if p['type'] == 'rectangle' else draw.ellipse
            shape((x, y, x + w, y + h), fill=fill if fill != "transparent" else None,
                  outline=color, width=p['sw'])
            if p['type'] == 'rectangle':
                svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{color}" stroke-width="{p["sw"]}"/>')
            else:
                svg.append(f'<ellipse cx="{x+w/2}" cy="{y+h/2}" rx="{w/2}" ry="{h/2}" fill="{fill}" stroke="{color}" stroke-width="{p["sw"]}"/>')
        e = dict(id=f'g1-{i:04}', type=p['type'], x=x, y=y, width=abs(w), height=abs(h), angle=0,
                 strokeColor=color, backgroundColor=fill, fillStyle='solid', strokeWidth=p['sw'],
                 strokeStyle='solid', roughness=0, opacity=100, groupIds=[], frameId=None,
                 roundness=None, seed=i + 1, version=1, versionNonce=i + 1, isDeleted=False,
                 boundElements=None, updated=0, link=None, locked=False)
        if p['type'] == 'text':
            e.update(text=p['text'], originalText=p['text'], fontSize=p['size'], fontFamily=2,
                     textAlign='left', verticalAlign='top', containerId=None, lineHeight=1.3, autoResize=True)
        if p['type'] == 'line':
            e.update(points=[[0, 0], [w, h]], startBinding=None, endBinding=None,
                     startArrowhead=None, endArrowhead=None, lastCommittedPoint=None)
        elements.append(e)
    svg.append('</svg>')
    (HERE / 'G1-DESIGN-REVIEW-preview.svg').write_text('\n'.join(svg) + '\n', encoding='utf-8')
    image.save(HERE / 'G1-DESIGN-REVIEW-preview.png', optimize=True)
    doc = dict(type='excalidraw', version=2, source='M2-G1 local planning generator', elements=elements,
               appState=dict(viewBackgroundColor=BG, gridSize=None, zoom=dict(value=0.5)), files={})
    (HERE / 'G1-DESIGN-REVIEW.excalidraw').write_text(json.dumps(doc, indent=1) + '\n', encoding='utf-8')
    print(f'Rendered {len(sh)} primitives: {WIDTH}x{HEIGHT}')


if __name__ == '__main__':
    render(scene())
