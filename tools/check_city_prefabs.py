"""Static M2-A1 checks for assets/world/city. Exit 1 on any failure.

    python tools/check_city_prefabs.py
Regenerates into two scratch dirs (determinism), compares with committed bytes,
then parses the committed XML and asserts the M2 contracts.
"""
import hashlib
import math
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CITY = os.path.join(ROOT, "assets", "world", "city")
GEN = os.path.join(ROOT, "tools", "gen_city_prefabs.py")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_city_prefabs as g  # noqa: E402

FAILS = []
PASSES = 0


def check(cond, label):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(label)
        print("FAIL", label)


def load(name):
    """World-space parts: (name, center, size, rot, props) with the zone origin applied once."""
    tree = ET.parse(os.path.join(CITY, name + ".rbxmx"))
    root = tree.getroot()[0]
    origin = g.ORIGINS.get(name) or {"CityBackdrop_CenteredReview": (0, 0, -152)}.get(name, (0, 0, 0))
    parts = []
    for it in root.iter("Item"):
        if it.get("class") != "Part":
            continue
        pr = it.find("Properties")
        get = lambda tag, n: pr.find(f"{tag}[@name='{n}']")
        cf = get("CoordinateFrame", "CFrame")
        vals = [float(cf.find(k).text) for k in g.CF_KEYS]
        size = tuple(float(get("Vector3", "size").find(k).text) for k in "XYZ")
        props = {e.get("name"): e.text for e in pr if e.text is not None}
        center = tuple(vals[i] + origin[i] for i in range(3))
        parts.append((props["Name"], center, size, tuple(vals[3:]), props))
    return root, parts


def aabb(center, size, rot):
    """World AABB of an oriented box."""
    r = [rot[0:3], rot[3:6], rot[6:9]]
    half = [sum(abs(r[i][j]) * size[j] / 2 for j in range(3)) for i in range(3)]
    return [(center[i] - half[i], center[i] + half[i]) for i in range(3)]


def ray_hits(o, d, box, tmax):
    t0, t1 = 0.0, tmax
    for i in range(3):
        lo, hi = box[i]
        if abs(d[i]) < 1e-12:
            if o[i] < lo or o[i] > hi:
                return False
            continue
        a, b = (lo - o[i]) / d[i], (hi - o[i]) / d[i]
        t0, t1 = max(t0, min(a, b)), min(t1, max(a, b))
        if t0 > t1:
            return False
    return True


def overlap(a, b, eps=1e-3):
    return all(a[i][0] < b[i][1] - eps and b[i][0] < a[i][1] - eps for i in range(3))


def main():
    # 1. Determinism + committed bytes.
    digests = []
    with tempfile.TemporaryDirectory() as t1, tempfile.TemporaryDirectory() as t2:
        for t in (t1, t2):
            subprocess.run([sys.executable, GEN, "--out", t], check=True, capture_output=True)
        for f in sorted(os.listdir(t1)):
            a, b = open(os.path.join(t1, f), "rb").read(), open(os.path.join(t2, f), "rb").read()
            check(a == b, f"deterministic {f}")
            committed = os.path.join(CITY, f)
            # Git stores LF; core.autocrlf may check out CRLF on Windows.
            check(os.path.exists(committed) and
                  open(committed, "rb").read().replace(b"
", b"
") == a,
                  f"committed bytes match regeneration (EOL-normalized) {f}")
            digests.append((f, hashlib.sha256(a).hexdigest()[:16]))

    names = [n for n, _, _ in g.PREFABS]
    data = {n: load(n) for n in names}
    world = {n: p for n, (_, p) in data.items()}

    # 2. Hygiene: no executables, no external content, valid root classes.
    for n, (root, parts) in data.items():
        text = open(os.path.join(CITY, n + ".rbxmx"), encoding="utf-8").read()
        classes = {it.get("class") for it in root.iter("Item")}
        check(classes <= {"Model", "Folder", "Part", "SurfaceGui", "TextLabel", "PointLight"},
              f"{n} classes {sorted(classes)}")
        check(not any(s in text for s in ("rbxassetid", "http", "Content name", "Script")),
              f"{n} has no scripts/asset refs")
        check(root.get("class") == ("Folder" if n == "CityAnchors" else "Model"), f"{n} root class")
        for pn, c, s, r, pr in parts:
            check(pr["Anchored"] == "true", f"{n}.{pn} anchored")
            check(pr["CanTouch"] == "false", f"{n}.{pn} CanTouch false")
        if root.get("class") == "Model":
            mode = root.find("Properties/token[@name='ModelStreamingMode']").text
            check(mode == ("2" if n.startswith("CityBackdrop") else "1"), f"{n} streaming mode")
            piv = root.find("Properties/OptionalCoordinateFrame/CFrame")
            check([float(piv.find(k).text) for k in g.CF_KEYS] ==
                  [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1], f"{n} identity pivot")

    # 3. Budget.
    assembled = [n for n in names if n not in g.REVIEW_ONLY]
    total = sum(len(world[n]) for n in assembled)
    check(total <= 450, f"assembled BaseParts {total} <= 450")
    check(len(world["CityBackdrop"]) <= 8 and len(world["CityBackdrop_CenteredReview"]) <= 8,
          "backdrop <= 8 parts")
    lights = sum(len([1 for it in data[n][0].iter("Item") if it.get("class") == "PointLight"])
                 for n in assembled)
    check(lights <= 8, f"PointLights {lights} <= 8")

    # 4. Anchors: exact identity, unique, invisible, not bedroom names.
    markers = [(n, pn, c, pr) for n in assembled for pn, c, s, r, pr in world[n] if pn.startswith("City_")]
    mnames = [m[1] for m in markers]
    check(len(mnames) == len(set(mnames)), "no duplicate City_ markers across prefabs")
    expected = dict(g.ANCHORS, City_HomeDoor=(-6, 3.65, 16))
    check(set(mnames) == set(expected), f"marker subset {sorted(set(mnames) ^ set(expected))}")
    for n, pn, c, pr in markers:
        check(all(abs(c[i] - expected[pn][i]) < 1e-6 for i in range(3)), f"{pn} world position {c}")
        if pn != "City_HomeDoor":
            check(n == "CityAnchors" and pr["Transparency"] == "1" and pr["CanCollide"] == "false"
                  and pr["CanQuery"] == "false", f"{pn} invisible non-query marker in City_Anchors")
    check(not set(mnames) & set(g.DEFERRED), "deferred markers not emitted")
    check(len(set(mnames) | set(g.DEFERRED)) == 23, "A1 subset + deferred = 23-part design inventory")
    bedroom = {"Spawn", "PlayerDesk", "DashboardPromptAnchor", "TerminalSlot", "PhoneSlot",
               "WorkerDeskSlot1", "WorkerDeskSlot2", "WorkerSeat1", "WorkerSeat2", "CameraFocus",
               "Door", "LightGroup"}
    allnames = {pn for n in names for pn, *_ in world[n]}
    check(not allnames & bedroom, f"no frozen bedroom names reused {allnames & bedroom}")
    hd = next(p for p in world["HouseExterior"] if p[0] == "City_HomeDoor")
    check(hd[2] == (3.7, 7.3, 0.18) and hd[4]["CanCollide"] == "true", "City_HomeDoor echo size, physical")

    # 5. Containment.
    for n in assembled:
        for pn, c, s, r, pr in world[n]:
            b = aabb(c, s, r)
            if n.startswith("CityBackdrop"):
                check(b[0][0] >= 16 - 1e-6 and b[0][1] <= 160 + 1e-6 and b[2][0] >= -192 - 1e-6
                      and b[2][1] <= -112 + 1e-6 and b[1][1] <= 120 and pr["CanCollide"] == "false"
                      and pr["CanQuery"] == "false", f"backdrop {pn} in baseline extent, non-collide")
            else:
                check(b[0][0] >= -136 and b[0][1] <= 80 and b[2][0] >= -24 and b[2][1] <= 176,
                      f"{n}.{pn} inside walkable envelope")
    for pn, c, s, r, pr in world["CityBackdrop_CenteredReview"]:
        b = aabb(c, s, r)
        check(b[0][0] >= -120 - 1e-6 and b[0][1] <= 120 + 1e-6 and b[1][1] <= 120,
              f"centered backdrop {pn} in proposed extent")
    for pn, c, s, r, pr in world["CityBoards"]:
        b = aabb(c, s, r)
        check(b[0][0] >= -12 and b[0][1] <= 12 and b[2][0] >= 64 and b[2][1] <= 72 and b[1][1] <= 9 + 1e-6,
              f"kiosk {pn} inside Z6, height <= 9")
    for pn, c, s, r, pr in world["CityGate"]:
        b = aabb(c, s, r)
        check(b[0][0] >= -8 and b[0][1] <= 8 and b[2][0] >= 160 and b[2][1] <= 176, f"gate {pn} in Z7")
    house_top = max(aabb(c, s, r)[1][1] for pn, c, s, r, pr in world["HouseExterior"]
                    if -13.6 <= c[0] <= 13.6 and -13.6 <= c[2] <= 13.6 and not pn.startswith("Dish"))
    check(house_top <= 12.5 + 1e-6, f"house shell height {house_top} <= 12.5")

    # 6. Frozen room volume untouched; walkable tops at Y=0.
    room = [(-12.25, 12.25), (-0.0, 10.0), (-12.25, 12.25)]
    for pn, c, s, r, pr in world["HouseExterior"]:
        check(not overlap(aabb(c, s, r), room), f"house {pn} outside frozen room volume")
    for n in assembled:
        for pn, c, s, r, pr in world[n]:
            b = aabb(c, s, r)
            if pr["CanCollide"] == "true" and s[1] <= 1.0001 and b[1][0] < 0 < b[1][1] + 1e-6:
                check(abs(b[1][1]) < 1e-6, f"{n}.{pn} walkable top at Y=0")
    bedroom_sha = hashlib.sha256(open(os.path.join(ROOT, "assets", "world", "Bedroom.rbxmx"), "rb").read()).hexdigest()
    check(bedroom_sha == "60b3e6d1d6b721d0316d199a509da05f6ecc5b77c0b53ac853d357b4d28ef977",
          "frozen Bedroom.rbxmx byte-identical")

    collidables = [(n, pn, aabb(c, s, r)) for n in assembled for pn, c, s, r, pr in world[n]
                   if pr["CanCollide"] == "true" and aabb(c, s, r)[1][1] > 0.05]

    # 7. Window aperture: rays CameraFocus -> aperture grid are not blocked by the city.
    eye = (7.0, 5.5, 3.0)
    every = [aabb(c, s, r) for n in assembled for pn, c, s, r, pr in world[n] if not n.startswith("CityBackdrop")]
    blocked, total_rays = 0, 0
    hits = {"CityBackdrop": 0, "CityBackdrop_CenteredReview": 0}
    for i in range(13):
        for j in range(9):
            tgt = (0.1 + 5.8 * i / 12, 3.1 + 4.8 * j / 8, -12.08)
            d = [tgt[k] - eye[k] for k in range(3)]
            total_rays += 1
            blocked += any(ray_hits(eye, d, b, 50) for b in every)
            for bn in hits:
                hits[bn] += any(ray_hits(eye, d, aabb(c, s, r), 50) for _, c, s, r, _ in world[bn])
    check(blocked == 0, f"north window aperture clear of city geometry ({blocked}/{total_rays} rays blocked)")
    cov = {k: round(100 * v / total_rays) for k, v in hits.items()}
    print(f"C1 analytic backdrop coverage through aperture: baseline {cov['CityBackdrop']}%, "
          f"centered {cov['CityBackdrop_CenteredReview']}% (2D ray estimate, not Studio evidence)")

    # 8. Spawn throat, route and fountain clearance.
    sp = expected["City_Spawn"]
    for n, pn, b in collidables:
        dx = max(b[0][0] - sp[0], 0, sp[0] - b[0][1])
        dz = max(b[2][0] - sp[2], 0, sp[2] - b[2][1])
        if pn != "City_HomeDoor":
            check(math.hypot(dx, dz) >= 4 - 1e-6 or b[1][0] > 7, f"spawn >= 4 studs from {n}.{pn}")
    route = [(-12, -4), (0.05, 7), (16.1, 100)]  # 8-wide lane: stoop to fountain apron
    for n, pn, b in collidables:
        check(not overlap(b, route), f"route lane clear of {n}.{pn}")
    for n in assembled:
        for pn, c, s, r, pr in world[n]:
            if n == "TownCenter" and pn.startswith(("Plaza", "Fountain", "Basin")):
                continue
            b = aabb(c, s, r)
            if b[1][1] <= 0.05:
                continue
            near = math.hypot(max(b[0][0], min(0, b[0][1])), max(b[2][0] - 112, min(0, b[2][1] - 112)))
            far = max(math.hypot(x, z - 112) for x in b[0] for z in b[2])
            ring_hit = far > 8.5 and near < 16
            check(not ring_hit, f"fountain 8-stud clearance ring free of {n}.{pn}")

    print("digests:", ", ".join(f"{f}={h}" for f, h in digests))
    print(f"{PASSES} passed, {len(FAILS)} failed; assembled BaseParts {total}, PointLights {lights}")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
