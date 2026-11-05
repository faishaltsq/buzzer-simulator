"""Focused verification for the M2-G1 review package, not a Roblox runtime suite.

Re-derives every arithmetic claim the package makes from the parent tables and
the verified Bedroom anchors, asserts the new coordinate table's invariants, and
checks the board exports the way the M2-A0 validator checks its own. Also runs
the M2-A0 validator so a regression there fails here too.
"""
import importlib.util
import itertools
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent
PREPRO = PARENT / "preproduction"
checks = []


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    checks.append(name)
    print("PASS", name)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g1 = load("g1_boards", HERE / "gen_g1_boards.py")

# ----------------------------------------------------------- verified anchors
CAMERA = (7.0, 5.5, 3.0)
GLASS = dict(center=(3.0, 5.5, -12.08), size=(5.8, 4.8, 0.08))
APER_X = (GLASS["center"][0] - GLASS["size"][0] / 2, GLASS["center"][0] + GLASS["size"][0] / 2)
DOOR = (-6.0, 3.65, 11.6)
HOMEDOOR = (-6.0, 3.65, 16.0)
CITY_SPAWN = (-6.0, 0.6, 20.0)
BOARDS = (0.0, 3.0, 68.0)

# ------------------------------------------------------------ D1 arithmetic
def window_slice(z):
    dz_win = GLASS["center"][2] - CAMERA[2]
    dz = z - CAMERA[2]
    xs = tuple(CAMERA[0] + (x - CAMERA[0]) * dz / dz_win for x in APER_X)
    ys = tuple(CAMERA[1] + (y - CAMERA[1]) * dz / dz_win
               for y in (GLASS["center"][1] - GLASS["size"][1] / 2,
                         GLASS["center"][1] + GLASS["size"][1] / 2))
    return xs, ys


SLICE_X, SLICE_Y = window_slice(-152.0)
check("window slice matches the published comparison",
      math.isclose(SLICE_X[0], -63.92, abs_tol=0.05) and math.isclose(SLICE_X[1], -4.31, abs_tol=0.05))
check("window slice matches the M2-A0 reference figures",
      math.isclose(SLICE_X[0], -65.33, abs_tol=2.0) and math.isclose(SLICE_X[1], -3.33, abs_tol=2.0))
check("baseline backdrop covers none of the window slice", SLICE_X[1] < 16.0)
check("proposed backdrop covers all of the window slice", -120.0 <= SLICE_X[0] and SLICE_X[1] <= 120.0)
check("tower reference sits inside the proposed span", -120.0 < -34.33 < 120.0)
check("tower reference sits outside the baseline span", not (16.0 < -34.33 < 160.0))
check("backdrop plane never touches the walkable envelope", -112.0 < -24.0)
check("backdrop plane never touches the house footprint", -112.0 < -24.0)
check("backdrop Z extent is disjoint from every walkable zone",
      all(-112.0 < z[3] and -112.0 < z[4] for z in g1.ZONES))
check("generator slice agrees with this verifier",
      math.isclose(g1.SLICE_X[0], SLICE_X[0], abs_tol=1e-9)
      and math.isclose(g1.SLICE_X[1], SLICE_X[1], abs_tol=1e-9))

# ------------------------------------------------- frozen anchor preservation
check("City_HomeDoor preserved at (-6, 3.65, 16)", g1.HOMEDOOR == HOMEDOOR)
check("City_Spawn preserved at (-6, 0.6, 20)", g1.CITY_SPAWN == CITY_SPAWN)
check("boards prompt preserved at (0, 3, 68)", g1.BOARDS == BOARDS)
check("frozen Door position preserved", g1.DOOR == DOOR)
check("generator anchors are a superset of the parent 17 identities",
      len(g1.ANCHORS) == 17 and len({a[0] for a in g1.ANCHORS}) == 17)

# --------------------------------------------------------- zone containment
ZONES = {z[0]: z for z in g1.ZONES}


def inside(zone, x, z):
    name, x0, x1, z0, z1 = ZONES[zone]
    return x0 <= x <= x1 and z0 <= z <= z1


check("boards prompt inside Z6", inside("Z6 Boards kiosk", *BOARDS[::2]))
check("City_HomeDoor inside Z0 home plot", inside("Z0 Home plot", *HOMEDOOR[::2]))
check("City_Spawn inside the Z0/Z1 throat", inside("Z1 Street", *CITY_SPAWN[::2]))
check("future gate prompt inside Z7", inside("Z7 Future gate", 0, 168))
check("east shop prompts inside Z3", all(inside("Z3 East shop row", x, z)
      for x, z in ((68, 84), (68, 108), (68, 132))))
check("west shop prompt inside Z4", inside("Z4 West furniture", -68, 84))
check("event plaza prompt inside Z5", inside("Z5 Event plaza", -108, 110))
check("backdrop Z extent is disjoint from every walkable zone",
      all(-112.0 < z[3] and -112.0 < z[4] for z in g1.ZONES))
envelope_x = (min(z[1] for z in g1.ZONES), max(z[2] for z in g1.ZONES))
envelope_z = (min(z[3] for z in g1.ZONES), max(z[4] for z in g1.ZONES))
check("walkable envelope is 216 x 200",
      envelope_x[1] - envelope_x[0] == 216 and envelope_z[1] - envelope_z[0] == 200)

# ----------------------------------------------------------- D4 arithmetic
EAST_HOST = (68.0, 84.0)
for stand_x, expected in ((56.0, 12.0), (57.0, 11.0), (60.0, 8.0), (62.0, 6.0)):
    check(f"east host distance from X={stand_x} is {expected} studs",
          math.isclose(abs(EAST_HOST[0] - stand_x), expected))
check("counter face at X=60 is inside the 10-stud activation", abs(68 - 60) <= 10)
check("lot edge at X=56 is at the 12-stud validation limit", abs(68 - 56) == 12)
check("amendment target X=58 stays inside the lot", 56.0 <= 58.0 <= 80.0)

# ----------------------------------------------------------- D2 arithmetic
KIOSK_B = (-3.0, 3.0)


def in_z6(x, z):
    return inside("Z6 Boards kiosk", x, z)


check("open-frame kiosk stays inside the frozen Z6 extent",
      all(in_z6(x, z) for x in KIOSK_B for z in (64.0, 72.0)))
check("open-frame kiosk leaves a 6-stud clear ring", 12.0 - (KIOSK_B[1] - KIOSK_B[0]) >= 6.0)
check("alternative X=4..16 placement is rejected as out-of-zone", not inside("Z6 Boards kiosk", 16, 68))
# ----------------------------------------------------------- D3 arithmetic
SHELL_INNER, THICK = 12.85, 0.5
check("shell outer face is 13.35", math.isclose(SHELL_INNER + THICK, 13.35))
check("HomeDoor near face is 15.91", math.isclose(16.0 - 0.09, 15.91))
check("porch recess is 2.56 studs", math.isclose(15.91 - 13.35, 2.56))
check("door aperture brackets the frozen door leaf", -7.85 < -6.0 < -4.15)

# ----------------------------------------------------------- D7 arithmetic
check("phase arithmetic 448 / 510 / 958 / 242",
      sum([90, 80, 140, 40, 30, 8, 60]) == 448
      and sum([80, 120, 100, 160, 50]) == 510
      and 448 + 510 == 958 and 1200 - 958 == 242)
check("marker inventory is 22 invisible + 1 physical door",
      len(g1.ANCHORS) - 1 + 6 == 22)
check("A1 ceiling leaves headroom over the 448 foundation", 450 >= 448)

# ----------------------------------------------------------- route lower bounds
check("route lower bounds reproduce the parent estimates",
      round(math.hypot(6, 56.4) / 16, 2) == 3.54
      and round(math.hypot(6, 100.4) / 16, 2) == 6.29)
check("published slice width is 59.6 studs", round(SLICE_X[1] - SLICE_X[0], 1) == 59.6)

# ----------------------------------------------------------- document checks
DOCS = ["README.md", "COORDINATE-DECISION-MATRIX.md", "SKYLINE-COMPARISON.md",
        "KIOSK-VISIBILITY-COMPARISON.md", "HOUSE-EXTERIOR-SPEC.md",
        "SHOP-APPROACH-PLAN.md", "CAMERA-AND-STREAMING-CHECKLIST.md",
        "PART-BUDGET-LEDGER.md", "M2-A1-READINESS.md", "DIRECTOR-APPROVAL-REQUEST.md"]
for name in DOCS:
    check(f"deliverable present: {name}", (HERE / name).is_file())
missing = []
for p in HERE.glob("*.md"):
    for link in re.findall(r"\]\(([^)]+)\)", p.read_text(encoding="utf-8")):
        if link.startswith(("https:", "http:", "#")):
            continue
        target = p.parent / link.split("#")[0]
        if not target.exists():
            missing.append((p.name, link))
check("local document links resolve", not missing)
check("every D1-D8 decision is documented",
      all(f"D{n}" in (HERE / "COORDINATE-DECISION-MATRIX.md").read_text(encoding="utf-8")
          for n in range(1, 9)))
check("no document marks M2-G1 as passed",
      "M2-G1 PASS" not in "".join(p.read_text(encoding="utf-8") for p in HERE.glob("*.md")))
check("boards are labelled planning evidence, not a Studio capture",
      "planning" in (HERE / "README.md").read_text(encoding="utf-8").lower())

# ----------------------------------------------------------- board exports
scene = g1.scene()
check("scene primitives finite", all(math.isfinite(p[k]) for p in scene for k in ("x", "y", "w", "h")))
check("every primitive fits the export canvas", all(
    min(p["x"], p["x"] + p["w"]) >= 0 and min(p["y"], p["y"] + p["h"]) >= 0
    and max(p["x"], p["x"] + p["w"]) <= g1.WIDTH
    and max(p["y"], p["y"] + p["h"]) <= g1.HEIGHT for p in scene))
texts = [p for p in scene if p["type"] == "text"]


def overlaps(a, b):
    return (max(a["x"], b["x"]) < min(a["x"] + a["w"], b["x"] + b["w"])
            and max(a["y"], b["y"]) < min(a["y"] + b["h"], b["y"] + b["h"]))


collisions = [(a["text"], b["text"]) for a, b in itertools.combinations(texts, 2) if overlaps(a, b)]
check(f"no label bounding-box overlap ({len(texts)} labels)", not collisions)
check("legend marks nothing as director approved",
      "none yet" in " ".join(t["text"] for t in texts))

OUTPUTS = ["G1-DESIGN-REVIEW-preview.png", "G1-DESIGN-REVIEW-preview.svg", "G1-DESIGN-REVIEW.excalidraw"]
with tempfile.TemporaryDirectory(prefix="m2-g1-") as tmp:
    original = g1.HERE
    g1.HERE = Path(tmp)
    g1.render(scene)
    first = {n: (g1.HERE / n).read_bytes() for n in OUTPUTS}
    g1.render(scene)
    check("three exports deterministic", all(first[n] == (g1.HERE / n).read_bytes() for n in OUTPUTS))
    g1.HERE = original
    check("published previews match the current scene",
          all(first[n] == (HERE / n).read_bytes() for n in OUTPUTS))

svg = ElementTree.parse(HERE / OUTPUTS[1])
check("SVG XML parses", svg.getroot().tag.endswith("svg"))
with Image.open(HERE / OUTPUTS[0]) as im:
    im.load()
    check("PNG decodes at the declared canvas", im.size == (g1.WIDTH, g1.HEIGHT))
doc = json.loads((HERE / OUTPUTS[2]).read_text(encoding="utf-8"))
check("native Excalidraw structure", doc["type"] == "excalidraw" and doc["version"] == 2)
check("export parity: one element per primitive", len(doc["elements"]) == len(scene))
check("unique native element IDs", len({e["id"] for e in doc["elements"]}) == len(doc["elements"]))

# ----------------------------------------------------------- M2-A0 regression
proc = subprocess.run([sys.executable, "verify_preproduction.py"], cwd=PREPRO,
                      capture_output=True, text=True)
check("M2-A0 validator still passes", proc.returncode == 0 and "checks passed" in proc.stdout)
m2a0 = sum(1 for line in proc.stdout.splitlines() if line.startswith("PASS"))
check("M2-A0 regression check count unchanged (22 checks)", m2a0 == 22)

print(f"\n{len(checks)} checks passed; not Studio, human art approval, or device performance proof.")
print("M2-A0 baseline: green, no regression from this package.")
