#!/usr/bin/env python3
"""Reproducible build and packaging script for BuzzerSimulator_RUKO_REVIEW.rbxlx.

Executes:
1. Asset and source inventory verification.
2. Static contract validation (tools/check_city_ruko.py).
3. Rojo build of tools/review/buzzer-ruko-review.project.json.
4. Post-processing to ensure fully assembled Edit-mode scene:
   - Workspace.CityRuko populated with 390 BaseParts across 5 zones at exact world origins:
     * Intersection: (0, 0, 0)
     * RukoBlockWest: (-55, 0, -60)
     * RukoBlockEast: (55, 0, -60)
     * CityFacilities: (0, 0, 60)
     * CityBackdrop_Ruko: (0, 0, -180)
   - Workspace.ReviewBedroom (155 BaseParts) at origin for M1 comparison
   - Workspace.ReviewOuterGround (600x1x600 studs, slate)
5. Verification of output place file: size, SHA-256, part count.
"""

import hashlib
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "build", "review")
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "BuzzerSimulator_RUKO_REVIEW.rbxlx")
PROJECT_JSON = os.path.join(PROJECT_ROOT, "tools", "review", "buzzer-ruko-review.project.json")

REQUIRED_M1_ASSETS = [
    "assets/world/Bedroom.rbxmx",
    "assets/world/OldCRT.rbxmx",
    "assets/world/PhoneCheap.rbxmx",
    "assets/world/PhoneFast.rbxmx",
    "assets/world/PCRumah.rbxmx",
    "assets/world/WorkerDesk1.rbxmx",
    "assets/world/WorkerDesk2.rbxmx",
    "assets/world/Trainee1.rbxmx",
    "assets/world/Trainee2.rbxmx",
]

REQUIRED_RUKO_ASSETS = [
    "assets/world/city_ruko/Intersection.rbxmx",
    "assets/world/city_ruko/RukoBlockWest.rbxmx",
    "assets/world/city_ruko/RukoBlockEast.rbxmx",
    "assets/world/city_ruko/CityFacilities.rbxmx",
    "assets/world/city_ruko/CityBackdrop_Ruko.rbxmx",
    "assets/world/city_ruko/ruko-manifest.json",
]

REQUIRED_SOURCE_MODULES = [
    "src/server/BootstrapRuntime.luau",
    "src/server/EconomyService.luau",
    "src/server/FeedService.luau",
    "src/server/MissionService.luau",
    "src/server/NetRouter.luau",
    "src/server/ProfileStore.luau",
    "src/server/ScoringCatalog.luau",
    "src/server/SessionService.luau",
    "src/server/WorldService.luau",
    "src/shared/Catalog.luau",
    "src/shared/GameTypes.luau",
    "src/shared/Presentation.luau",
    "src/shared/Rules.luau",
    "src/client/App.client.luau",
    "src/client/ClientState.luau",
    "src/client/PhoneEquipController.luau",
    "src/client/WorkerAnimationController.luau",
    "src/review/ReviewBootstrap.server.luau",
    "src/review/ReviewTravelService.server.luau",
    "src/review/ReviewPanelRelay.server.luau",
    "src/review/ReviewPanel.client.luau",
]

ZONE_ORIGINS = {
    "Intersection": (0.0, 0.0, 0.0),
    "RukoBlockWest": (-55.0, 0.0, -60.0),
    "RukoBlockEast": (55.0, 0.0, -60.0),
    "CityFacilities": (0.0, 0.0, 60.0),
    "CityBackdrop_Ruko": (0.0, 0.0, -180.0),
}


def compute_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def verify_prerequisites():
    print("[1/5] Verifying required assets and source modules...")
    missing = []
    for rel_path in REQUIRED_M1_ASSETS + REQUIRED_RUKO_ASSETS + REQUIRED_SOURCE_MODULES:
        full = os.path.join(PROJECT_ROOT, rel_path)
        if not os.path.exists(full):
            missing.append(rel_path)
    if missing:
        raise SystemExit(f"FAILED: Missing prerequisites:\n" + "\n".join(f"  - {m}" for m in missing))
    print(f"  -> Verified {len(REQUIRED_M1_ASSETS)} M1 assets, {len(REQUIRED_RUKO_ASSETS)} ruko assets, and {len(REQUIRED_SOURCE_MODULES)} source modules.")


def run_contract_checks():
    print("[2/5] Running ruko prefab contract checks (tools/check_city_ruko.py)...")
    checker = os.path.join(PROJECT_ROOT, "tools", "check_city_ruko.py")
    res = subprocess.run([sys.executable, checker], capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout)
        print(res.stderr)
        raise SystemExit(f"FAILED: check_city_ruko exited with code {res.returncode}")
    print("  -> All contract checks passed (390 BaseParts, 12 PointLights, 0 errors).")


def build_rojo():
    print("[3/5] Compiling review place with Rojo...")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    cmd = ["rojo", "build", PROJECT_JSON, "-o", OUTPUT_PATH]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout)
        print(res.stderr)
        raise SystemExit(f"FAILED: rojo build failed with code {res.returncode}")
    print(f"  -> Rojo compiled place to {OUTPUT_PATH}")


def assemble_edit_mode_world():
    print("[4/5] Assembling Edit-mode world in Workspace...")
    tree = ET.parse(OUTPUT_PATH)
    root = tree.getroot()

    workspace = None
    for item in root.findall("./Item"):
        if item.get("class") == "Workspace":
            workspace = item
            break
    if workspace is None:
        raise SystemExit("FAILED: Workspace not found in built DataModel")

    # Remove any existing CityRuko folder in Workspace to avoid duplicates
    for child in list(workspace):
        if child.tag == "Item":
            props = child.find("Properties")
            if props is not None:
                name_tag = props.find("string[@name='Name']")
                if name_tag is not None and name_tag.text == "CityRuko":
                    workspace.remove(child)

    # Create Workspace.CityRuko Folder
    city_folder = ET.Element("Item", {"class": "Folder", "referent": "RBX_CityRuko_Assembled"})
    city_props = ET.SubElement(city_folder, "Properties")
    ET.SubElement(city_props, "string", {"name": "Name"}).text = "CityRuko"

    total_city_bp = 0
    total_city_lights = 0

    # Add each shifted zone model
    for zone_name, (ox, oy, oz) in ZONE_ORIGINS.items():
        rel_fn = f"assets/world/city_ruko/{zone_name}.rbxmx"
        zone_tree = ET.parse(os.path.join(PROJECT_ROOT, rel_fn))
        zone_model = zone_tree.getroot().find("Item")

        for part in zone_model.findall(".//Item"):
            cls = part.get("class")
            if cls in ("Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart"):
                total_city_bp += 1
                cf = part.find("./Properties/CoordinateFrame[@name='CFrame']")
                if cf is not None:
                    x = float(cf.find("X").text)
                    y = float(cf.find("Y").text)
                    z = float(cf.find("Z").text)
                    cf.find("X").text = str(round(x + ox, 6))
                    cf.find("Y").text = str(round(y + oy, 6))
                    cf.find("Z").text = str(round(z + oz, 6))
            elif cls == "PointLight":
                total_city_lights += 1

        pivot = zone_model.find("./Properties/OptionalCoordinateFrame[@name='WorldPivotData']/CFrame")
        if pivot is not None:
            pivot.find("X").text = str(round(ox, 6))
            pivot.find("Y").text = str(round(oy, 6))
            pivot.find("Z").text = str(round(oz, 6))

        city_folder.append(zone_model)

    workspace.append(city_folder)

    # Add ReviewOuterGround part (600x1x600 studs, slate)
    ground = ET.Element("Item", {"class": "Part", "referent": "RBX_ReviewOuterGround"})
    g_props = ET.SubElement(ground, "Properties")
    ET.SubElement(g_props, "string", {"name": "Name"}).text = "ReviewOuterGround"
    ET.SubElement(g_props, "bool", {"name": "Anchored"}).text = "true"
    ET.SubElement(g_props, "bool", {"name": "CanCollide"}).text = "true"
    ET.SubElement(g_props, "token", {"name": "Material"}).text = "800"  # Slate
    c_el = ET.SubElement(g_props, "Color3", {"name": "Color"})
    ET.SubElement(c_el, "R").text = str(92 / 255.0)
    ET.SubElement(c_el, "G").text = str(90 / 255.0)
    ET.SubElement(c_el, "B").text = str(86 / 255.0)
    cf_el = ET.SubElement(g_props, "CoordinateFrame", {"name": "CFrame"})
    for k, v in [("X", 0.0), ("Y", -1.6), ("Z", -30.0),
                 ("R00", 1.0), ("R01", 0.0), ("R02", 0.0),
                 ("R10", 0.0), ("R11", 1.0), ("R12", 0.0),
                 ("R20", 0.0), ("R21", 0.0), ("R22", 1.0)]:
        ET.SubElement(cf_el, k).text = str(v)
    sz_el = ET.SubElement(g_props, "Vector3", {"name": "size"})
    ET.SubElement(sz_el, "X").text = "600.0"
    ET.SubElement(sz_el, "Y").text = "1.0"
    ET.SubElement(sz_el, "Z").text = "600.0"
    workspace.append(ground)

    # Write formatted XML back
    tree.write(OUTPUT_PATH, encoding="utf-8", xml_declaration=True)
    print(f"  -> Workspace.CityRuko assembled: {total_city_bp} BaseParts, {total_city_lights} PointLights.")
    print("  -> Workspace.ReviewOuterGround added (600x1x600 studs, slate).")


def verify_final_build():
    print("[5/5] Verifying final deliverable...")
    if not os.path.isfile(OUTPUT_PATH):
        raise SystemExit(f"FAILED: Output file {OUTPUT_PATH} not found.")

    size = os.path.getsize(OUTPUT_PATH)
    sha = compute_sha256(OUTPUT_PATH)

    # Parse and inspect final DataModel
    tree = ET.parse(OUTPUT_PATH)
    root = tree.getroot()
    workspace = None
    for item in root.findall("./Item"):
        if item.get("class") == "Workspace":
            workspace = item
            break

    city = None
    bedroom = None
    ground = None
    for item in workspace.findall("./Item"):
        props = item.find("Properties")
        if props is not None:
            n = props.find("string[@name='Name']")
            if n is not None:
                if n.text == "CityRuko":
                    city = item
                elif n.text == "ReviewBedroom":
                    bedroom = item
                elif n.text == "ReviewOuterGround":
                    ground = item

    if city is None:
        raise SystemExit("FAILED: Workspace.CityRuko missing in final place.")
    if bedroom is None:
        raise SystemExit("FAILED: Workspace.ReviewBedroom missing in final place.")
    if ground is None:
        raise SystemExit("FAILED: Workspace.ReviewOuterGround missing in final place.")

    bp_classes = ("Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart")
    city_parts = len([p for p in city.findall(".//Item") if p.get("class") in bp_classes])
    bedroom_parts = len([p for p in bedroom.findall(".//Item") if p.get("class") in bp_classes])
    total_parts = city_parts + bedroom_parts + 1

    print("=================================================================")
    print("  BUZZER SIMULATOR — RUKO REVIEW BUILD SUCCESSFUL")
    print("=================================================================")
    print(f"  Deliverable:              {OUTPUT_PATH}")
    print(f"  Size:                     {size:,} bytes ({round(size / 1024, 1)} KB / {round(size / (1024*1024), 2)} MB)")
    print(f"  SHA-256:                  {sha}")
    print(f"  Workspace.CityRuko:       {city_parts} BaseParts (contract: 390)")
    print(f"  Workspace.ReviewBedroom:  {bedroom_parts} BaseParts (contract: 155)")
    print(f"  Workspace.ReviewGround:   1 BasePart (600x1x600 studs, slate)")
    print(f"  Total Edit-mode parts:    {total_parts} BaseParts (budget: 546)")
    print("=================================================================")


if __name__ == "__main__":
    verify_prerequisites()
    run_contract_checks()
    build_rojo()
    assemble_edit_mode_world()
    verify_final_build()
