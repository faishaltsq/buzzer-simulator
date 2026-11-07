"""Deterministic M2-B Distrik Ruko & Persimpangan blockout prefabs.

Geometry is authored in world studs, then exported local to each zone origin.
Roblox Model pivots are placed at identity at each zone origin.

Outputs into assets/world/city_ruko/:
    - Intersection.rbxmx (Origin: (0, 0, 0))
    - RukoBlockWest.rbxmx (Origin: (-55, 0, -60))
    - RukoBlockEast.rbxmx (Origin: (55, 0, -60))
    - CityFacilities.rbxmx (Origin: (0, 0, 60))
    - CityBackdrop_Ruko.rbxmx (Origin: (0, 0, -180))
    - ruko-manifest.json

Usage:
    python tools/gen_city_ruko.py
    python tools/gen_city_ruko.py --out DIR
"""
import argparse
import json
import math
import os
import sys
import xml.etree.ElementTree as ET

PALETTE = {
    "cream": (233, 222, 199), "plaster": (219, 211, 190),
    "wood": (153, 112, 75), "wood_light": (180, 139, 96),
    "wood_dark": (101, 74, 55), "sage": (132, 151, 126),
    "sage_dark": (80, 108, 86), "navy": (52, 68, 81),
    "ink": (32, 42, 45), "amber": (236, 186, 111),
    "linen": (246, 236, 216), "metal": (110, 119, 115),
    "glass": (150, 178, 177), "screen": (39, 63, 62),
    "phosphor": (177, 206, 166), "clay": (166, 115, 88),
    "asphalt": (78, 74, 70), "concrete": (184, 176, 162),
    "gutter": (92, 90, 86), "paving": (206, 192, 168),
    "brick": (172, 106, 80), "grass": (112, 134, 88),
    "water": (92, 146, 156), "roof": (156, 86, 64),
    "shutter": (150, 154, 150), "pane": (64, 82, 86),
    "leaf": (86, 118, 78), "sky_hill": (122, 142, 124),
    "sky_ridge": (152, 164, 172), "sky_tower": (86, 100, 120),
    "sky_a": (124, 134, 150), "sky_b": (138, 146, 160),
    "sky_c": (112, 124, 142)
}

MATERIAL = {
    "SmoothPlastic": 272, "Wood": 512, "WoodPlanks": 528,
    "Slate": 800, "Concrete": 816, "Brick": 848,
    "Cobblestone": 880, "Metal": 1088, "Grass": 1280,
    "Fabric": 1312, "Glass": 1568
}

FACE = {"Right": 0, "Top": 1, "Back": 2, "Left": 3, "Bottom": 4, "Front": 5}
CF_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")

ORIGINS = {
    "Intersection": (0, 0, 0),
    "RukoBlockWest": (-55, 0, -60),
    "RukoBlockEast": (55, 0, -60),
    "CityFacilities": (0, 0, 60),
    "CityBackdrop_Ruko": (0, 0, -180)
}


def rotation(rx, ry, rz):
    """CFrame.Angles(rx, ry, rz) in degrees."""
    x, y, z = (math.radians(v) for v in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return (cy*cz, -cy*sz, sy, cx*sz+sx*sy*cz, cx*cz-sx*sy*sz, -sx*cy,
            sx*sz-cx*sy*cz, sx*cz+cx*sy*sz, cx*cy)


class Zone:
    def __init__(self, name, origin):
        self.name, self.origin, self.parts = name, origin, []

    def add(self, name, size, pos, tint, material="SmoothPlastic", collide=False,
            transparency=0, shape=1, rot=(0, 0, 0), shadow=True):
        p = {"name": name, "size": size, "pos": pos, "tint": tint, "material": material,
             "collide": collide, "transparency": transparency, "shape": shape,
             "rot": rot, "shadow": shadow and transparency == 0, "guis": [], "lights": []}
        self.parts.append(p)
        return p

    def box(self, name, x0, x1, y0, y1, z0, z1, tint, material="SmoothPlastic", **kw):
        return self.add(name, (x1-x0, y1-y0, z1-z0), ((x0+x1)/2, (y0+y1)/2, (z0+z1)/2),
                        tint, material, **kw)

    def disc(self, name, center, radius, y0, y1, tint, material="SmoothPlastic", **kw):
        return self.add(name, (y1-y0, 2*radius, 2*radius), (center[0], (y0+y1)/2, center[1]),
                        tint, material, shape=2, rot=(0, 0, 90), **kw)


def gui(p, face, text, size=48, tint="linen", inset=0.07):
    p["guis"].append((face, text, size, tint, inset))


def light(p, brightness=1.4, reach=18):
    p["lights"].append((brightness, reach))


# ------------------------------------------------------------------ Intersection
def build_intersection():
    z = Zone("Intersection", ORIGINS["Intersection"])

    # 4-way crossroad roads: -80..80 X and Z, width 16 studs asphalt
    z.box("RoadCenter", -8, 8, -0.8, 0, -8, 8, "asphalt", "Concrete", collide=True)
    z.box("RoadNorth", -8, 8, -0.8, 0, -80, -8, "asphalt", "Concrete", collide=True)
    z.box("RoadSouth", -8, 8, -0.8, 0, 8, 80, "asphalt", "Concrete", collide=True)
    z.box("RoadWest", -80, -8, -0.8, 0, -8, 8, "asphalt", "Concrete", collide=True)
    z.box("RoadEast", 8, 80, -0.8, 0, -8, 8, "asphalt", "Concrete", collide=True)

    # Sidewalks: 4 studs concrete border along roads
    z.box("SidewalkNW_EW", -80, -8, -0.8, 0.4, -12, -8, "concrete", "Concrete", collide=True)
    z.box("SidewalkNW_NS", -12, -8, -0.8, 0.4, -80, -12, "concrete", "Concrete", collide=True)
    z.box("SidewalkNE_EW", 8, 80, -0.8, 0.4, -12, -8, "concrete", "Concrete", collide=True)
    z.box("SidewalkNE_NS", 8, 12, -0.8, 0.4, -80, -12, "concrete", "Concrete", collide=True)
    z.box("SidewalkSW_EW", -80, -8, -0.8, 0.4, 8, 12, "concrete", "Concrete", collide=True)
    z.box("SidewalkSW_NS", -12, -8, -0.8, 0.4, 12, 80, "concrete", "Concrete", collide=True)
    z.box("SidewalkSE_EW", 8, 80, -0.8, 0.4, 8, 12, "concrete", "Concrete", collide=True)
    z.box("SidewalkSE_NS", 8, 12, -0.8, 0.4, 12, 80, "concrete", "Concrete", collide=True)

    # Crosswalk zebra stripes (2 stripes per crosswalk)
    for i, sx in enumerate((-3.0, 3.0)):
        z.box(f"ZebraNorth_{i+1}", sx-1.4, sx+1.4, 0, 0.02, -11.5, -8.5, "linen", shadow=False)
        z.box(f"ZebraSouth_{i+1}", sx-1.4, sx+1.4, 0, 0.02, 8.5, 11.5, "linen", shadow=False)
    for i, sz in enumerate((-3.0, 3.0)):
        z.box(f"ZebraWest_{i+1}", -11.5, -8.5, 0, 0.02, sz-1.4, sz+1.4, "linen", shadow=False)
        z.box(f"ZebraEast_{i+1}", 8.5, 11.5, 0, 0.02, sz-1.4, sz+1.4, "linen", shadow=False)

    # Road center dashes (1 per arm)
    z.box("RoadDashNorth", -0.25, 0.25, 0, 0.02, -45, -35, "linen", shadow=False)
    z.box("RoadDashSouth", -0.25, 0.25, 0, 0.02, 35, 45, "linen", shadow=False)
    z.box("RoadDashWest", -45, -35, 0, 0.02, -0.25, 0.25, "linen", shadow=False)
    z.box("RoadDashEast", 35, 45, 0, 0.02, -0.25, 0.25, "linen", shadow=False)

    # 4 Streetlights with amber PointLights at intersection corners
    for name, x, zz, dx, dz in (
        ("StreetlightNW", -10.5, -10.5, 2.0, 0),
        ("StreetlightNE", 10.5, -10.5, -2.0, 0),
        ("StreetlightSW", -10.5, 10.5, 2.0, 0),
        ("StreetlightSE", 10.5, 10.5, -2.0, 0),
    ):
        z.box(name+"Pole", x-0.3, x+0.3, 0.4, 11.0, zz-0.3, zz+0.3, "navy", "Metal", collide=True)
        ax0, ax1 = sorted((x, x+dx))
        az0, az1 = sorted((zz, zz+dz))
        z.box(name+"Arm", ax0, ax1, 10.6, 11.0, az0, az1, "navy", "Metal")
        hx, hz = x+dx, zz+dz
        h = z.box(name+"Head", hx-0.5, hx+0.5, 9.8, 10.6, hz-0.5, hz+0.5, "amber", shadow=False)
        light(h, brightness=1.6, reach=22)

    # Street signs
    z.box("SignPoleNW", -10.2, -9.8, 0.4, 5.5, -11.2, -10.8, "metal", "Metal", collide=True)
    p1 = z.box("SignPlateNW", -12.5, -8.5, 4.5, 5.5, -11.1, -10.9, "navy")
    gui(p1, "Back", "JL. RUKO UTAMA", 50)
    gui(p1, "Front", "JL. RUKO UTAMA", 50)

    z.box("SignPoleSE", 9.8, 10.2, 0.4, 5.5, 10.8, 11.2, "metal", "Metal", collide=True)
    p2 = z.box("SignPlateSE", 8.5, 12.5, 4.5, 5.5, 10.9, 11.1, "navy")
    gui(p2, "Front", "JL. PERSIMPANGAN", 50)
    gui(p2, "Back", "JL. PERSIMPANGAN", 50)

    return z


# ------------------------------------------------------------------ Ruko Blocks
def build_ruko_block(name, origin, bldg_left, bldg_right, x_left, x_mid_l, x_mid_r, x_right, stair_side, sign_left, sign_right):
    z = Zone(name, origin)

    z_back, z_front = -72.0, -48.0
    z_balcony_front = -44.0

    if stair_side == "east":
        stair_x0, stair_x1 = x_right, x_right + 8.0
        balcony_x0, balcony_x1 = x_left, stair_x1
        ramp_x = (stair_x0 + stair_x1) / 2
        lamp_x = stair_x1 - 1.0
    else:  # west
        stair_x0, stair_x1 = x_left - 8.0, x_left
        balcony_x0, balcony_x1 = stair_x0, x_right
        ramp_x = (stair_x0 + stair_x1) / 2
        lamp_x = stair_x0 + 1.0

    # 4 Slabs (ground floor, floor 2, floor 3, roof)
    z.box("FloorSlab1", x_left, x_right, -0.6, 0.0, z_back, z_front, "concrete", "Concrete", collide=True)
    z.box("FloorSlab2", x_left, x_right, 9.6, 10.0, z_back, z_front, "concrete", "Concrete", collide=True)
    z.box("FloorSlab3", x_left, x_right, 19.6, 20.0, z_back, z_front, "concrete", "Concrete", collide=True)
    z.box("RoofSlab", x_left, x_right, 29.6, 30.0, z_back, z_front, "concrete", "Concrete", collide=True)

    # 4 Perimeter solid walls
    z.box("WallNorth", x_left, x_right, 0.0, 30.0, z_back - 0.6, z_back, "plaster", "Concrete", collide=True)
    z.box("WallLeft", x_left - 0.6, x_left, 0.0, 30.0, z_back, z_front, "plaster", "Concrete", collide=True)
    z.box("WallRight", x_right, x_right + 0.6, 0.0, 30.0, z_back, z_front, "plaster", "Concrete", collide=True)
    z.box("WallDividing", x_mid_l, x_mid_r, 0.0, 30.0, z_back, z_front, "plaster", "Concrete", collide=True)

    # Front facade pillars (3)
    z.box("PillarLeft", x_left, x_left + 5.0, 0.0, 30.0, z_front - 0.6, z_front, "cream", "Concrete", collide=True)
    z.box("PillarMid", x_mid_l - 2.5, x_mid_r + 2.5, 0.0, 30.0, z_front - 0.6, z_front, "cream", "Concrete", collide=True)
    z.box("PillarRight", x_right - 5.0, x_right, 0.0, 30.0, z_front - 0.6, z_front, "cream", "Concrete", collide=True)

    # Door positions
    door_w = 3.4
    door_left_x0 = (x_left + 5.0 + x_mid_l - 2.5) / 2 - door_w / 2
    door_left_x1 = door_left_x0 + door_w
    door_right_x0 = (x_mid_r + 2.5 + x_right - 5.0) / 2 - door_w / 2
    door_right_x1 = door_right_x0 + door_w

    # Facade lintels and doors per floor
    for fl, y0 in ((1, 0.0), (2, 10.0), (3, 20.0)):
        z.box(f"Lintel_{fl}", x_left, x_right, y0 + 7.2, y0 + 10.0, z_front - 0.6, z_front, "cream", "Concrete", collide=True)

        d_left = z.box(f"Door_{bldg_left}{fl}", door_left_x0, door_left_x1, y0, y0 + 7.2, z_front - 0.4, z_front, "wood", "WoodPlanks", collide=True)
        gui(d_left, "Back", f"UNIT {bldg_left}{fl}", 44)

        d_right = z.box(f"Door_{bldg_right}{fl}", door_right_x0, door_right_x1, y0, y0 + 7.2, z_front - 0.4, z_front, "wood", "WoodPlanks", collide=True)
        gui(d_right, "Back", f"UNIT {bldg_right}{fl}", 44)

    # Facade window panels (1 display glass per building)
    z.box(f"FacadeWindow_{bldg_left}", x_left + 5.0, door_left_x0, 1.0, 27.2, z_front - 0.4, z_front - 0.2, "pane", "Glass", transparency=0.4, collide=True)
    z.box(f"FacadeWindow_{bldg_right}", door_right_x1, x_right - 5.0, 1.0, 27.2, z_front - 0.4, z_front - 0.2, "pane", "Glass", transparency=0.4, collide=True)

    # Stairwell & Balconies
    z.add("StairRamp1", (5.0, 0.5, 22.36), (ramp_x, 5.0, -54.0), "concrete", "Concrete", collide=True, rot=(26.56, 0, 0))
    z.box("Balcony2", balcony_x0, balcony_x1, 9.6, 10.0, z_front, z_balcony_front, "concrete", "Concrete", collide=True)
    z.box("Railing2", balcony_x0, balcony_x1, 10.0, 13.0, z_balcony_front - 0.3, z_balcony_front, "metal", "Metal", collide=True)

    z.add("StairRamp2", (5.0, 0.5, 22.36), (ramp_x, 15.0, -54.0), "concrete", "Concrete", collide=True, rot=(-26.56, 0, 0))
    z.box("Balcony3", balcony_x0, balcony_x1, 19.6, 20.0, z_front, z_balcony_front, "concrete", "Concrete", collide=True)
    z.box("Railing3", balcony_x0, balcony_x1, 20.0, 23.0, z_balcony_front - 0.3, z_balcony_front, "metal", "Metal", collide=True)

    z.add("StairRamp3", (5.0, 0.5, 22.36), (ramp_x, 25.0, -54.0), "concrete", "Concrete", collide=True, rot=(26.56, 0, 0))
    z.box("RoofLanding", stair_x0, stair_x1, 29.6, 30.0, -68.0, -62.0, "concrete", "Concrete", collide=True)

    # Rooftop Parapet, AC & Antenna
    z.box("ParapetNorth", x_left, x_right, 30.0, 32.5, z_back - 0.5, z_back, "cream", "Concrete", collide=True)
    z.box("ParapetSouth", x_left, x_right, 30.0, 32.5, z_front - 0.5, z_front, "cream", "Concrete", collide=True)

    ac_mid_x = (x_left + x_right) / 2
    z.box("AC_Condenser", ac_mid_x - 4.0, ac_mid_x + 4.0, 30.0, 33.0, -62.0, -58.0, "metal", "Metal", collide=True)
    z.box("AntennaMast", ac_mid_x - 0.3, ac_mid_x + 0.3, 30.0, 42.0, -68.3, -67.7, "ink", "Metal", collide=False)

    # Commercial signs
    s_left = z.box(f"SignGedung_{bldg_left}", x_left + 4.0, x_mid_l - 2.0, 27.5, 29.8, z_front - 0.3, z_front, "navy", "SmoothPlastic", collide=False)
    gui(s_left, "Back", sign_left, 48)
    s_right = z.box(f"SignGedung_{bldg_right}", x_mid_r + 2.0, x_right - 4.0, 27.5, 29.8, z_front - 0.3, z_front, "sage_dark", "SmoothPlastic", collide=False)
    gui(s_right, "Back", sign_right, 48)

    # Outdoor entrance lamp with PointLight
    lamp_part = z.box("EntranceLamp", lamp_x - 0.5, lamp_x + 0.5, 7.5, 8.5, z_balcony_front - 0.5, z_balcony_front, "amber", "Metal", collide=False)
    light(lamp_part, brightness=1.5, reach=20)

    # 48 PC Desks (6 units * 8 desks * 5 parts = 240 parts)
    for bldg, x_min_b, x_max_b in ((bldg_left, x_left + 1.0, x_mid_l - 1.0), (bldg_right, x_mid_r + 1.0, x_right - 1.0)):
        span = x_max_b - x_min_b
        dx = span / 4.0
        x_centers = [x_min_b + dx * (i + 0.5) for i in range(4)]

        for fl, y0 in ((1, 0.0), (2, 10.0), (3, 20.0)):
            # Row 1 (desks 1..4 at Z = -66.0)
            for i, xc in enumerate(x_centers):
                slot = i + 1
                zc = -66.0
                z.box(f"Table_{bldg}{fl}_{slot}", xc-1.8, xc+1.8, y0+2.3, y0+2.6, zc-1.0, zc+1.0, "wood_light", "Wood", collide=True)
                z.box(f"Monitor_{bldg}{fl}_{slot}", xc-0.8, xc+0.8, y0+2.6, y0+3.8, zc-0.8, zc-0.65, "screen", "SmoothPlastic", collide=False)
                z.box(f"Keyboard_{bldg}{fl}_{slot}", xc-0.6, xc+0.6, y0+2.6, y0+2.7, zc+0.1, zc+0.5, "ink", "SmoothPlastic", collide=False)
                z.box(f"Chair_{bldg}{fl}_{slot}", xc-0.75, xc+0.75, y0+0.4, y0+1.8, zc+1.2, zc+2.4, "navy", "Fabric", collide=True)
                z.add(f"WorkerAnchor_{bldg}{fl}_{slot}", (1, 1, 1), (xc, y0+1.2, zc+1.8), "cream", transparency=1, collide=False)

            # Row 2 (desks 5..8 at Z = -54.0)
            for i, xc in enumerate(x_centers):
                slot = i + 5
                zc = -54.0
                z.box(f"Table_{bldg}{fl}_{slot}", xc-1.8, xc+1.8, y0+2.3, y0+2.6, zc-1.0, zc+1.0, "wood_light", "Wood", collide=True)
                z.box(f"Monitor_{bldg}{fl}_{slot}", xc-0.8, xc+0.8, y0+2.6, y0+3.8, zc-0.8, zc-0.65, "screen", "SmoothPlastic", collide=False)
                z.box(f"Keyboard_{bldg}{fl}_{slot}", xc-0.6, xc+0.6, y0+2.6, y0+2.7, zc+0.1, zc+0.5, "ink", "SmoothPlastic", collide=False)
                z.box(f"Chair_{bldg}{fl}_{slot}", xc-0.75, xc+0.75, y0+0.4, y0+1.8, zc+1.2, zc+2.4, "navy", "Fabric", collide=True)
                z.add(f"WorkerAnchor_{bldg}{fl}_{slot}", (1, 1, 1), (xc, y0+1.2, zc+1.8), "cream", transparency=1, collide=False)

    return z


# ------------------------------------------------------------------ City Facilities
def build_city_facilities():
    z = Zone("CityFacilities", ORIGINS["CityFacilities"])

    # 1. Spawn Plaza (Anchor City_Spawn at (40, 2, 60))
    z.box("PlazaPaving", 28, 52, -0.6, 0.2, 48, 72, "paving", "Cobblestone", collide=True)
    z.disc("PlazaCenterDisc", (40, 60), 5.0, 0.2, 0.35, "cream", "Concrete")
    z.box("PlazaBenchN", 37, 43, 0.2, 1.4, 52, 53.5, "wood", "Wood", collide=True)
    z.box("PlazaBenchS", 37, 43, 0.2, 1.4, 66.5, 68, "wood", "Wood", collide=True)
    z.add("City_Spawn", (2, 1, 2), (40, 2, 60), "cream", transparency=1, collide=False)

    # 2. Toko Hardware ("BUZZER HARDWARE & TECH") with Prompt_HardwareShop
    z.box("ShopFloor", 14, 30, -0.6, 0.2, 20, 44, "concrete", "Concrete", collide=True)
    z.box("ShopWallNorth", 14, 30, 0.2, 11.0, 19.5, 20.2, "plaster", "Concrete", collide=True)
    z.box("ShopWallEast", 29.5, 30.2, 0.2, 11.0, 20, 44, "plaster", "Concrete", collide=True)
    z.box("ShopWallSouth", 14, 30, 0.2, 11.0, 43.8, 44.5, "plaster", "Concrete", collide=True)
    z.box("ShopRoof", 13.5, 30.5, 11.0, 11.8, 19.2, 44.8, "roof", "Slate", collide=True)
    z.box("ShopPillarL", 13.8, 14.5, 0.2, 11.0, 20, 24, "cream", "Concrete", collide=True)
    z.box("ShopPillarR", 13.8, 14.5, 0.2, 11.0, 40, 44, "cream", "Concrete", collide=True)
    z.box("ShopLintel", 13.8, 14.5, 8.5, 11.0, 24, 40, "cream", "Concrete", collide=True)
    z.box("ShopWindow", 14.0, 14.2, 1.5, 8.5, 24, 40, "glass", "Glass", transparency=0.5, collide=True)
    z.box("ShopShelf", 27.5, 29.2, 0.2, 6.0, 23, 41, "metal", "Metal", collide=True)
    z.box("ShopCounter", 21, 26, 0.2, 3.2, 28, 30, "wood_dark", "Wood", collide=True)
    s_shop = z.box("ShopSign", 13.4, 13.8, 9.0, 10.8, 23, 41, "navy", "SmoothPlastic", collide=False)
    gui(s_shop, "Left", "BUZZER HARDWARE & TECH", 46)
    lamp_shop = z.box("ShopCeilingLamp", 21.5, 22.5, 10.2, 10.8, 31.5, 32.5, "amber", shadow=False)
    light(lamp_shop, brightness=1.5, reach=22)
    z.add("Prompt_HardwareShop", (2, 2, 2), (16, 2, 32), "cream", transparency=1, collide=False)

    # 3. Warung Kopi ("WARKOP PAK JOKO") with Prompt_WarungKopi
    z.box("WarkopFloor", -34, -18, -0.6, 0.2, 42, 58, "paving", "Cobblestone", collide=True)
    z.box("WarkopBackWall", -34.0, -33.2, 0.2, 8.0, 44, 56, "wood_dark", "WoodPlanks", collide=True)
    z.box("WarkopWallS", -34, -22, 0.2, 8.0, 43.5, 44.2, "wood_dark", "WoodPlanks", collide=True)
    z.box("WarkopWallN", -34, -22, 0.2, 8.0, 55.8, 56.5, "wood_dark", "WoodPlanks", collide=True)
    z.box("WarkopCanopy", -35, -20, 7.8, 8.4, 43, 57, "roof", "Fabric", collide=True)
    z.box("WarkopCounter", -23.5, -21.8, 0.2, 3.2, 45, 55, "wood", "Wood", collide=True)
    z.box("WarkopBench", -20.5, -19.5, 0.2, 1.4, 46, 54, "wood_light", "Wood", collide=True)
    s_warkop = z.box("WarkopSign", -21.2, -20.9, 6.2, 7.6, 46, 54, "amber", "Wood", collide=False)
    gui(s_warkop, "Right", "WARKOP PAK JOKO", 48)
    lantern = z.box("WarkopLantern", -22.5, -21.5, 6.5, 7.2, 49.5, 50.5, "amber", shadow=False)
    light(lantern, brightness=1.4, reach=18)
    z.add("Prompt_WarungKopi", (2, 2, 2), (-20, 2, 50), "cream", transparency=1, collide=False)

    # 4. Papan Misi ("PAPAN MISI & CAMPAIGN") with Prompt_CityMissions
    z.box("MissionsBase", -16, -13, -0.6, 0.4, 24, 30, "concrete", "Concrete", collide=True)
    z.box("MissionsPostS", -14.8, -14.2, 0.4, 7.5, 25, 25.6, "metal", "Metal", collide=True)
    z.box("MissionsPostN", -14.8, -14.2, 0.4, 7.5, 28.4, 29, "metal", "Metal", collide=True)
    b_misi = z.box("MissionsBoard", -14.7, -14.3, 3.5, 7.5, 24.5, 29.5, "wood_dark", "Wood", collide=True)
    gui(b_misi, "Right", "PAPAN MISI & CAMPAIGN", 42)
    gui(b_misi, "Left", "PAPAN MISI & CAMPAIGN", 42)
    z.box("MissionsCap", -16.0, -13.0, 7.5, 8.0, 24.0, 30.0, "navy", "Slate", collide=True)
    z.add("Prompt_CityMissions", (2, 2, 2), (-13.5, 2.5, 27), "cream", transparency=1, collide=False)

    return z


# ------------------------------------------------------------------ Skyline Backdrop
def build_city_backdrop():
    z = Zone("CityBackdrop_Ruko", ORIGINS["CityBackdrop_Ruko"])
    z.box("SkylineRidgeBack", -140, 140, 0, 45, -195, -190, "sky_ridge", shadow=False)
    z.box("TowerWestFar", -120, -95, 0, 75, -185, -178, "sky_a", shadow=False)
    z.box("TowerWestNear", -90, -65, 0, 95, -182, -174, "sky_tower", shadow=False)
    z.box("AntennaWest", -78, -77, 95, 115, -179, -177, "ink", "Metal", shadow=False)
    z.box("TowerCenter", -30, 30, 0, 85, -186, -178, "sky_b", shadow=False)
    z.box("TowerEastNear", 40, 75, 0, 105, -184, -176, "sky_tower", shadow=False)
    z.box("AntennaEast", 57, 58, 105, 128, -181, -179, "ink", "Metal", shadow=False)
    z.box("TowerEastFar", 85, 125, 0, 70, -185, -178, "sky_c", shadow=False)
    return z


# ------------------------------------------------------------------ Serializer
_ref = 0


def _num(v):
    r = round(float(v), 4)
    return repr(0.0 if r == 0 else r)


def _p(tag, name, text):
    el = ET.Element(tag, {"name": name})
    el.text = str(text)
    return el


def _v(tag, name, keys, values):
    el = ET.Element(tag, {"name": name} if name else {})
    for k, v in zip(keys, values):
        ET.SubElement(el, k).text = _num(v)
    return el


def _udim2(name, xs, xo, ys, yo):
    el = ET.Element("UDim2", {"name": name})
    for k, v in (("XS", _num(xs)), ("XO", str(int(xo))), ("YS", _num(ys)), ("YO", str(int(yo)))):
        ET.SubElement(el, k).text = v
    return el


def _color(name, tint):
    rgb = PALETTE[tint] if isinstance(tint, str) else tint
    return _v("Color3", name, "RGB", [c/255 for c in rgb])


def _item(cls, name, props=(), children=()):
    global _ref
    _ref += 1
    el = ET.Element("Item", {"class": cls, "referent": f"RBX{_ref}"})
    pr = ET.SubElement(el, "Properties")
    ET.SubElement(pr, "string", {"name": "Name"}).text = name
    pr.extend(props)
    el.extend(children)
    return el


def _part(p, origin):
    pos = [p["pos"][i] - origin[i] for i in range(3)]
    marker = p["transparency"] == 1
    collide = "true" if p["collide"] else "false"
    kids = []
    for face, text, size, tint, inset in p["guis"]:
        label = _item("TextLabel", "Text", [
            _udim2("Size", 1 - 2*inset, 0, 0.8, 0), _udim2("Position", inset, 0, 0.1, 0),
            _p("float", "BackgroundTransparency", 1), _p("string", "Text", text),
            _color("TextColor3", tint), _p("bool", "TextScaled", "true"),
            _p("bool", "TextWrapped", "true"), _p("float", "TextSize", size),
            _p("token", "Font", 4)])
        kids.append(_item("SurfaceGui", f"Sign{face}", [
            _p("token", "Face", FACE[face]), _p("bool", "AlwaysOnTop", "false"),
            _p("token", "SizingMode", 1), _p("float", "PixelsPerStud", 40),
            _p("float", "LightInfluence", 1)], [label]))
    for brightness, reach in p["lights"]:
        kids.append(_item("PointLight", "Light", [
            _color("Color", "amber"), _p("float", "Brightness", brightness),
            _p("float", "Range", reach), _p("bool", "Shadows", "false")]))
    return _item("Part", p["name"], [
        _v("Vector3", "size", "XYZ", p["size"]),
        _v("CoordinateFrame", "CFrame", CF_KEYS, (*pos, *rotation(*p["rot"]))),
        _color("Color", p["tint"]), _p("token", "Material", MATERIAL[p["material"]]),
        _p("token", "shape", p["shape"]), _p("bool", "Anchored", "true"),
        _p("bool", "CanCollide", collide), _p("bool", "CanTouch", "false"),
        _p("bool", "CanQuery", "false" if marker else collide),
        _p("bool", "CastShadow", "true" if p["shadow"] else "false"),
        _p("token", "TopSurface", 0), _p("token", "BottomSurface", 0),
        _p("float", "Transparency", p["transparency"])], kids)


def streaming(name):
    return 2 if name.startswith("CityBackdrop") else 1  # Persistent / Atomic


def to_xml(zone, root_class="Model"):
    global _ref
    _ref = 0
    props = []
    if root_class == "Model":
        pivot = ET.Element("OptionalCoordinateFrame", {"name": "WorldPivotData"})
        pivot.append(_v("CFrame", None, CF_KEYS, (0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)))
        props = [pivot, _p("token", "ModelStreamingMode", streaming(zone.name))]
    root_el = _item(root_class, zone.name, props)
    root_el.extend(_part(p, zone.origin) for p in zone.parts)
    doc = ET.Element("roblox", {"version": "4"})
    doc.append(root_el)
    ET.indent(doc, "  ")
    return ET.tostring(doc, encoding="unicode") + "\n"


PREFABS = [
    ("Intersection", build_intersection, "Model"),
    ("RukoBlockWest",
     lambda: build_ruko_block("RukoBlockWest", ORIGINS["RukoBlockWest"], "A", "B", -79.0, -57.0, -55.0, -33.0, "east", "GEDUNG A / TECH LAB", "GEDUNG B / BUZZER AGENCY"),
     "Model"),
    ("RukoBlockEast",
     lambda: build_ruko_block("RukoBlockEast", ORIGINS["RukoBlockEast"], "C", "D", 33.0, 55.0, 57.0, 79.0, "west", "GEDUNG C / DATA HUB", "GEDUNG D / CLOUD MINER"),
     "Model"),
    ("CityFacilities", build_city_facilities, "Model"),
    ("CityBackdrop_Ruko", build_city_backdrop, "Model"),
]


def zones():
    return {name: builder() for name, builder, _ in PREFABS}


def manifest(zs):
    rows = {}
    for name, z in zs.items():
        rows[name] = {
            "origin": list(z.origin),
            "baseparts": len(z.parts),
            "markers": [p["name"] for p in z.parts if p["name"].startswith("City_") or p["name"].startswith("Prompt_") or p["name"].startswith("Door_") or p["name"].startswith("WorkerAnchor_")],
            "surface_guis": sum(len(p["guis"]) for p in z.parts),
            "point_lights": sum(len(p["lights"]) for p in z.parts),
            "scripts": 0,
            "root": {1: "Model/Atomic", 2: "Model/Persistent"}[streaming(name)]
        }
    assembled = [name for name, _, _ in PREFABS]
    return {
        "generator": "tools/gen_city_ruko.py",
        "status": "M2-B Ruko Blockout",
        "prefabs": rows,
        "assembled": assembled,
        "total_baseparts": sum(rows[n]["baseparts"] for n in assembled),
        "total_point_lights": sum(rows[n]["point_lights"] for n in assembled),
        "door_anchors": [f"Door_{b}{fl}" for b in ("A", "B", "C", "D") for fl in (1, 2, 3)],
        "prompt_markers": ["Prompt_HardwareShop", "Prompt_WarungKopi", "Prompt_CityMissions", "City_Spawn"]
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "..", "assets", "world", "city_ruko"))
    out = ap.parse_args().out
    os.makedirs(out, exist_ok=True)
    zs = zones()
    for name, _, cls in PREFABS:
        with open(os.path.join(out, name + ".rbxmx"), "w", encoding="utf-8", newline="\n") as f:
            f.write(to_xml(zs[name], cls))
    m = manifest(zs)
    with open(os.path.join(out, "ruko-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(m, indent=2, sort_keys=True) + "\n")
    for n, r in m["prefabs"].items():
        print(f"{n:22} {r['baseparts']:4} parts {len(r['markers']):3} markers {r['point_lights']} lights")
    print("Total BaseParts:", m["total_baseparts"], "| PointLights:", m["total_point_lights"])


if __name__ == "__main__":
    main()
