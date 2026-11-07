"""Validation suite for M2-B Distrik Ruko & Persimpangan prefabs.

Validates:
    - Deterministic generation (generates twice into temp dirs and asserts identical bytes)
    - Valid XML parsing and schema for all generated .rbxmx files
    - 100% of BaseParts are Anchored (Anchored = true)
    - Part count within [350, 650] and PointLights <= 12
    - Required door anchors (Door_A1..A3, Door_B1..B3, Door_C1..C3, Door_D1..D3)
    - Required prompt markers (Prompt_HardwareShop, Prompt_WarungKopi, Prompt_CityMissions, City_Spawn)
    - 8 PC desk slots per floor unit (table, monitor, keyboard, chair, worker anchor)
    - Manifest integrity

Usage:
    python tools/check_city_ruko.py
"""
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RUKO_DIR = os.path.join(ROOT, "assets", "world", "city_ruko")
GEN = os.path.join(ROOT, "tools", "gen_city_ruko.py")

sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_city_ruko as g  # noqa: E402

FAILS = []
PASSES = 0


def check(cond, label):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(label)
        print("FAIL:", label)


def load(name):
    """Load world-space parts: (name, center, size, rot, props, lights, guis)."""
    tree = ET.parse(os.path.join(RUKO_DIR, name + ".rbxmx"))
    root = tree.getroot()[0]
    origin = g.ORIGINS[name]
    parts = []
    for it in root.iter("Item"):
        if it.get("class") != "Part":
            continue
        pr = it.find("Properties")
        get = lambda tag, n: pr.find(f"{tag}[@name='{n}']")  # noqa: E731
        cf = get("CoordinateFrame", "CFrame")
        vals = [float(cf.find(k).text) for k in g.CF_KEYS]
        size = tuple(float(get("Vector3", "size").find(k).text) for k in "XYZ")
        props = {e.get("name"): e.text for e in pr if e.text is not None}
        center = tuple(vals[i] + origin[i] for i in range(3))
        lights = it.findall(".//Item[@class='PointLight']")
        guis = it.findall(".//Item[@class='SurfaceGui']")
        parts.append((props["Name"], center, size, tuple(vals[3:]), props, len(lights), len(guis)))
    return root, parts


def main():
    print("=== M2-B Distrik Ruko & Persimpangan Verification ===")

    # 1. Determinism and committed bytes check
    with tempfile.TemporaryDirectory() as t1, tempfile.TemporaryDirectory() as t2:
        for t in (t1, t2):
            subprocess.run([sys.executable, GEN, "--out", t], check=True, capture_output=True)
        files = sorted(os.listdir(t1))
        for f in files:
            b1 = open(os.path.join(t1, f), "rb").read()
            b2 = open(os.path.join(t2, f), "rb").read()
            check(b1 == b2, f"Deterministic generation across runs: {f}")
            committed = os.path.join(RUKO_DIR, f)
            check(os.path.exists(committed), f"Committed file exists: {f}")
            if os.path.exists(committed):
                c_bytes = open(committed, "rb").read().replace(b"\r\n", b"\n")
                check(c_bytes == b1, f"Committed bytes match regeneration: {f}")

    # 2. XML parsing and hygiene
    expected_prefabs = [name for name, _, _ in g.PREFABS]
    data = {}
    for name in expected_prefabs:
        root, parts = load(name)
        data[name] = (root, parts)
        text = open(os.path.join(RUKO_DIR, name + ".rbxmx"), encoding="utf-8").read()

        # Class whitelist
        classes = {it.get("class") for it in root.iter("Item")}
        check(classes <= {"Model", "Part", "SurfaceGui", "TextLabel", "PointLight"},
              f"{name} uses only authorized classes: {sorted(classes)}")

        # No scripts, external web links, or binary assets
        check(not any(s in text for s in ("rbxassetid", "http", "Content name", "Script")),
              f"{name} has no scripts or external asset references")

        # Root class and model properties
        check(root.get("class") == "Model", f"{name} root class is Model")
        mode = root.find("Properties/token[@name='ModelStreamingMode']").text
        expected_mode = "2" if name.startswith("CityBackdrop") else "1"
        check(mode == expected_mode, f"{name} streaming mode is {expected_mode}")
        piv = root.find("Properties/OptionalCoordinateFrame/CFrame")
        piv_vals = [float(piv.find(k).text) for k in g.CF_KEYS]
        check(piv_vals == [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1], f"{name} pivot is identity")

        # 100% BaseParts Anchored and CanTouch=false
        for pn, c, s, r, pr, nl, ng in parts:
            check(pr.get("Anchored") == "true", f"{name}.{pn} Anchored is true")
            check(pr.get("CanTouch") == "false", f"{name}.{pn} CanTouch is false")
            if pr.get("Transparency") == "1":
                check(pr.get("CanCollide") == "false", f"Marker {name}.{pn} CanCollide is false")

    # 3. Budget checks
    total_parts = sum(len(parts) for _, parts in data.values())
    total_lights = sum(sum(nl for _, _, _, _, _, nl, _ in parts) for _, parts in data.values())
    check(350 <= total_parts <= 650, f"Total BaseParts {total_parts} is within [350, 650]")
    check(total_lights <= 12, f"Total PointLights {total_lights} <= 12")

    # 4. Required Door Anchors (Door_A1..A3, Door_B1..B3, Door_C1..C3, Door_D1..D3)
    all_parts_by_name = {pn: (c, s, pr) for _, parts in data.values() for pn, c, s, _, pr, _, _ in parts}
    req_doors = [f"Door_{b}{fl}" for b in ("A", "B", "C", "D") for fl in (1, 2, 3)]
    for d in req_doors:
        check(d in all_parts_by_name, f"Door anchor exists: {d}")
        if d in all_parts_by_name:
            _, _, pr = all_parts_by_name[d]
            check(pr.get("CanCollide") == "true", f"Door {d} CanCollide is true")

    # 5. Required Prompt Markers
    req_prompts = ["Prompt_HardwareShop", "Prompt_WarungKopi", "Prompt_CityMissions", "City_Spawn"]
    for p in req_prompts:
        check(p in all_parts_by_name, f"Prompt marker exists: {p}")
        if p in all_parts_by_name:
            _, _, pr = all_parts_by_name[p]
            check(pr.get("Transparency") == "1", f"Prompt marker {p} Transparency is 1")
            check(pr.get("CanCollide") == "false", f"Prompt marker {p} CanCollide is false")

    # City_Spawn location check around (40, 2, 60)
    if "City_Spawn" in all_parts_by_name:
        sc, _, _ = all_parts_by_name["City_Spawn"]
        dist = math.dist(sc, (40, 2, 60))
        check(dist < 1.0, f"City_Spawn position {sc} is within 1 stud of (40, 2, 60)")

    # 6. PC Desk Slots: 8 desks per floor unit across all 4 buildings (96 total)
    for b in ("A", "B", "C", "D"):
        for fl in (1, 2, 3):
            for slot in range(1, 9):
                t_name = f"Table_{b}{fl}_{slot}"
                m_name = f"Monitor_{b}{fl}_{slot}"
                k_name = f"Keyboard_{b}{fl}_{slot}"
                c_name = f"Chair_{b}{fl}_{slot}"
                w_name = f"WorkerAnchor_{b}{fl}_{slot}"

                check(t_name in all_parts_by_name, f"{t_name} exists")
                check(m_name in all_parts_by_name, f"{m_name} exists")
                check(k_name in all_parts_by_name, f"{k_name} exists")
                check(c_name in all_parts_by_name, f"{c_name} exists")
                check(w_name in all_parts_by_name, f"{w_name} exists")

    # 7. Manifest validation
    manifest_path = os.path.join(RUKO_DIR, "ruko-manifest.json")
    check(os.path.exists(manifest_path), "ruko-manifest.json exists")
    if os.path.exists(manifest_path):
        m = json.load(open(manifest_path, encoding="utf-8"))
        check(m["total_baseparts"] == total_parts, f"Manifest total_baseparts matches: {m['total_baseparts']} == {total_parts}")
        check(m["total_point_lights"] == total_lights, f"Manifest total_point_lights matches: {m['total_point_lights']} == {total_lights}")
        for name in expected_prefabs:
            check(name in m["prefabs"], f"Manifest records prefab {name}")
            check(m["prefabs"][name]["baseparts"] == len(data[name][1]),
                  f"Manifest baseparts for {name} matches XML ({m['prefabs'][name]['baseparts']} == {len(data[name][1])})")

    # Summary
    print(f"\nResults: {PASSES} checks passed, {len(FAILS)} failures.")
    if FAILS:
        print("\nFailed checks:")
        for f in FAILS:
            print(" -", f)
        return 1

    print("\nAll checks passed successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
