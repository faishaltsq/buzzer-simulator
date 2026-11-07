"""Deterministic M2-A1 Gang Melati blockout prefabs (isolated review only).

Geometry is authored in world studs, then exported local to each zone origin so
the review assembler places every zone exactly once with PivotTo(origin).
No scripts, remotes, prompts, meshes, decals or asset IDs are emitted.

    python tools/gen_city_prefabs.py              # writes assets/world/city/
    python tools/gen_city_prefabs.py --out DIR    # scratch export for checks
"""
import argparse
import json
import math
import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_world_prefabs as frozen  # read-only reuse of palette + serializer

PALETTE = dict(frozen.PALETTE,
               asphalt=(78, 74, 70), concrete=(184, 176, 162), gutter=(92, 90, 86),
               paving=(206, 192, 168), brick=(172, 106, 80), grass=(112, 134, 88),
               water=(92, 146, 156), roof=(156, 86, 64), shutter=(150, 154, 150),
               pane=(64, 82, 86), leaf=(86, 118, 78), sky_hill=(122, 142, 124),
               sky_ridge=(152, 164, 172), sky_tower=(86, 100, 120),
               sky_a=(124, 134, 150), sky_b=(138, 146, 160), sky_c=(112, 124, 142))
# Enum.Material values (the frozen generator's private map is not reused).
MATERIAL = {"SmoothPlastic": 272, "Wood": 512, "WoodPlanks": 528, "Slate": 800,
            "Concrete": 816, "Brick": 848, "Cobblestone": 880, "Metal": 1088,
            "Grass": 1280, "Fabric": 1312}
FACE = {"Right": 0, "Top": 1, "Back": 2, "Left": 3, "Bottom": 4, "Front": 5}

# Zone origins: parent 02 §3/§7 and handoff transform contract.
ORIGINS = {"HouseExterior": (0, 0, 0), "StreetBlock": (0, 0, 40),
           "TownCenter": (0, 0, 112), "CityBoards": (0, 0, 68),
           "CityGate": (0, 0, 168), "CityBackdrop": (88, 0, -152)}
# Same backdrop prefab, two review placements. Baseline is FROZEN canonical;
# centered is the M2-G1 D1 PROPOSED candidate (review copy only).
BACKDROP_VARIANTS = {"baseline": (88, 0, -152), "centered": (0, 0, -152)}
STREAMING = {"CityBackdrop": 2}  # Persistent; all other zone models Atomic (1)

# A1 marker subset (world). Full inventory is listed in the manifest.
ANCHORS = [("City_Spawn", (-6, 0.6, 20)), ("City_DoorPromptInterior", (-6, 3.65, 8)),
           ("City_Zone_Street", (0, 0, 40)), ("City_Zone_TownCenter", (0, 0, 112)),
           ("City_Zone_FutureGate", (0, 0, 168)), ("City_Prompt_Boards", (0, 3, 68)),
           ("City_Prompt_FutureGate", (0, 3, 168)), ("City_TransitStop", (24, 0, 96)),
           # Signpost positions are A1 proposals (street sign, gapura).
           ("City_Signpost_01", (-21, 0, 18)), ("City_Signpost_02", (0, 0, 58))]
DEFERRED = ["City_Zone_ShopEast", "City_Zone_ShopWest", "City_Zone_EventPlaza",
            "City_Prompt_ElectroMart", "City_Prompt_RumahRapi", "City_Prompt_Cosmetics",
            "City_Prompt_Utility", "City_Prompt_EventPlaza",
            "City_Signpost_03", "City_Signpost_04", "City_Signpost_05", "City_Signpost_06"]
MAX_LIGHTS = 8


def rotation(rx, ry, rz):
    """CFrame.Angles(rx, ry, rz) in degrees, same convention as the frozen kit."""
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
        """Vertical-axis cylinder (Roblox cylinders run along X, so roll 90)."""
        return self.add(name, (y1-y0, 2*radius, 2*radius), (center[0], (y0+y1)/2, center[1]),
                        tint, material, shape=2, rot=(0, 0, 90), **kw)

    def yawed(self, name, size, center, yaw, offset, tint, material="SmoothPlastic", **kw):
        """Part at `offset` in a frame yawed `yaw` degrees around `center`."""
        a = math.radians(yaw)
        ox, oy, oz = offset
        pos = (center[0] + ox*math.cos(a) + oz*math.sin(a), center[1] + oy,
               center[2] - ox*math.sin(a) + oz*math.cos(a))
        return self.add(name, size, pos, tint, material, rot=(0, yaw, 0), **kw)


def gui(p, face, text, size=48, tint="linen", inset=0.07):
    """inset: horizontal margin as a fraction of the face (keeps text off occluded edges)."""
    p["guis"].append((face, text, size, tint, inset))


def light(p, brightness=1.4, reach=18):
    p["lights"].append((brightness, reach))


# ---------------------------------------------------------------- HouseExterior
def build_house():
    z = Zone("HouseExterior", ORIGINS["HouseExterior"])
    I, O, TOP = 12.85, 13.35, 11.9  # shell inner/outer face (room 12.25 + 0.6 gap)
    W = ("cream", "Concrete")
    # North wall keeps an opening wider than the desk-camera ray cone (x -0.48..5.81,
    # y 2.90..8.10 at the outer face) so the frozen window aperture stays clear.
    z.box("WallNorthLeft", -O, -0.7, -0.2, TOP, -O, -I, *W, collide=True)
    z.box("WallNorthRight", 6.1, O, -0.2, TOP, -O, -I, *W, collide=True)
    z.box("WallNorthBelow", -0.7, 6.1, -0.2, 2.7, -O, -I, *W, collide=True)
    z.box("WallNorthAbove", -0.7, 6.1, 8.3, TOP, -O, -I, *W, collide=True)
    z.box("WallEast", I, O, -0.2, TOP, -I, I, *W, collide=True)
    z.box("WallWest", -O, -I, -0.2, TOP, -I, I, *W, collide=True)
    z.box("WallSouthLeft", -O, -8.35, -0.2, TOP, I, O, *W, collide=True)
    z.box("WallSouthRight", -3.65, O, -0.2, TOP, I, O, *W, collide=True)
    z.box("WallSouthAbove", -8.35, -3.65, 8.1, TOP, I, O, *W, collide=True)
    # Porch B1: return walls close the recess (and the 0.6 cavity) to the leaf.
    z.box("DoorReturnWest", -8.35, -7.85, -0.2, 7.3, 12.25, 15.91, "cream", "Concrete", collide=True)
    z.box("DoorReturnEast", -4.15, -3.65, -0.2, 7.3, 12.25, 15.91, "cream", "Concrete", collide=True)
    z.box("DoorLintel", -8.35, -3.65, 7.3, 8.1, 12.25, 16.3, "wood_dark", "Wood", collide=True)
    z.add("City_HomeDoor", (3.7, 7.3, 0.18), (-6, 3.65, 16), "sage", "Wood", collide=True)
    z.box("DoorFrameWest", -8.35, -7.85, 0, 7.3, 15.91, 16.3, "sage_dark", "Wood")
    z.box("DoorFrameEast", -4.15, -3.65, 0, 7.3, 15.91, 16.3, "sage_dark", "Wood")
    z.box("DoorHandle", -4.85, -4.65, 3.2, 3.9, 16.09, 16.2, "metal", "Metal")
    plate = z.box("HouseNumber", -2.6, -0.8, 5.9, 6.9, O, O+0.1, "navy")
    gui(plate, "Back", "No. 7", 60)
    z.add("PorchCanopy", (7.2, 0.3, 3.3), (-6, 8.62, 14.92), "roof", "Slate", rot=(15, 0, 0))
    lamp = z.box("PorchLamp", -9.6, -9.0, 5.8, 6.6, O, O+0.5, "amber")
    light(lamp, 1.2, 14)
    z.box("PorchLampBracket", -9.45, -9.15, 6.6, 7.0, O, O+0.35, "ink", "Metal")
    # Z0 grade: six tiles, all tops at Y=0, none under the frozen room floor, so
    # no coplanar overlap (the stoop is a tile, not a slab laid on the yard).
    G, R = ("grass", "Grass"), 12.25
    z.box("YardNorth", -24, 24, -1, 0, -24, -R, *G, collide=True)
    z.box("YardWest", -24, -R, -1, 0, -R, R, *G, collide=True)
    z.box("YardEast", R, 24, -1, 0, -R, R, *G, collide=True)
    z.box("YardSouthWest", -24, -10.5, -1, 0, R, 16, *G, collide=True)
    z.box("Stoop", -10.5, -1.5, -1, 0, R, 16, "paving", "Concrete", collide=True)
    z.box("YardSouthEast", -1.5, 24, -1, 0, R, 16, *G, collide=True)
    # Plinth, frieze, parapet and corner timbers give the cube a residential read.
    PL = ("sage_dark", "Slate")
    z.box("PlinthNorth", -13.5, 13.5, -0.2, 0.9, -13.5, -O, *PL)
    z.box("PlinthEast", O, 13.5, -0.2, 0.9, -O, O, *PL)
    z.box("PlinthWest", -13.5, -O, -0.2, 0.9, -O, O, *PL)
    z.box("PlinthSouthWest", -13.5, -10.5, -0.2, 0.9, O, 13.5, *PL)
    z.box("PlinthSouthEast", -1.5, 13.5, -0.2, 0.9, O, 13.5, *PL)
    FR = ("sage", "Wood")
    z.box("FriezeNorth", -13.45, 13.45, 8.6, 9.0, -13.45, -O, *FR)
    z.box("FriezeEast", O, 13.45, 8.6, 9.0, -O, O, *FR)
    z.box("FriezeWest", -13.45, -O, 8.6, 9.0, -O, O, *FR)
    z.box("FriezeSouthWest", -13.45, -9.8, 8.6, 9.0, O, 13.45, *FR)
    z.box("FriezeSouthEast", -2.2, 13.45, 8.6, 9.0, O, 13.45, *FR)
    PA = ("linen", "Concrete")
    z.box("ParapetNorth", -13.6, 13.6, TOP, 12.5, -13.6, -12.25, *PA, collide=True)
    z.box("ParapetSouth", -13.6, 13.6, TOP, 12.5, 12.25, 13.6, *PA, collide=True)
    z.box("ParapetEast", 12.25, 13.6, TOP, 12.5, -12.25, 12.25, *PA, collide=True)
    z.box("ParapetWest", -13.6, -12.25, TOP, 12.5, -12.25, 12.25, *PA, collide=True)
    for sx in (-1, 1):
        for sz in (-1, 1):
            z.box("CornerTimber", *sorted((sx*O, sx*13.6)), -0.2, TOP,
                  *sorted((sz*O, sz*13.6)), "wood", "Wood")
    # South street window: closed pane, shutters, sill and flower box.
    z.box("FrontWindowPane", 2, 8, 3, 7, O, O+0.1, "pane", "SmoothPlastic")
    z.box("FrontWindowMullion", 4.9, 5.1, 3, 7, O+0.1, O+0.2, "wood", "Wood")
    z.box("FrontWindowSill", 1.6, 8.4, 2.7, 3.0, O, O+0.35, "wood", "Wood")
    z.box("FrontWindowHead", 1.6, 8.4, 7.0, 7.3, O, O+0.3, "wood", "Wood")
    z.box("FrontShutterWest", 0.6, 1.9, 3, 7, O, O+0.15, "sage", "WoodPlanks")
    z.box("FrontShutterEast", 8.1, 9.4, 3, 7, O, O+0.15, "sage", "WoodPlanks")
    z.box("FlowerBox", 2, 8, 2.1, 2.7, O, O+0.55, "clay", "Brick")
    z.box("FlowerBoxLeaves", 2.2, 7.8, 2.7, 3.2, O+0.1, O+0.5, "leaf", "Grass")
    # North window: frame outside the ray cone; the aperture itself stays open.
    z.box("NorthWindowSill", -1.1, 6.5, 2.4, 2.7, -13.65, -O, "wood", "Wood")
    z.box("NorthWindowHead", -1.1, 6.5, 8.3, 8.6, -13.6, -O, "wood", "Wood")
    z.box("NorthShutterWest", -2.0, -0.7, 2.7, 8.3, -13.5, -O, "sage", "WoodPlanks")
    z.box("NorthShutterEast", 6.1, 7.4, 2.7, 8.3, -13.5, -O, "sage", "WoodPlanks")
    # Retro-tech dressing: AC unit, dish on the parapet, meter box.
    z.box("ACUnit", O, 14.4, 7.0, 8.4, 2, 5, "linen", "Metal")
    z.box("ACGrille", 14.4, 14.5, 7.2, 8.2, 2.3, 4.7, "metal", "Metal")
    z.box("ACBracket", O, 14.3, 6.8, 7.0, 2.2, 4.8, "ink", "Metal")
    z.box("DishMast", 12.8, 13.1, 12.5, 14.4, 10.6, 10.9, "metal", "Metal")
    z.add("Dish", (0.25, 2.4, 2.4), (12.95, 14.9, 10.75), "linen", "Metal", shape=2, rot=(0, 60, 20))
    z.box("MeterBox", -12.2, -10.9, 4, 5.6, O, O+0.3, "metal", "Metal")
    # Front-yard pagar with an 11-stud opening around the stoop.
    z.box("FenceWest", -24, -11.5, -0.2, 1.6, 15.4, 16, "cream", "Concrete", collide=True)
    z.box("FenceWestCap", -24, -11.5, 1.6, 1.85, 15.3, 16, "sage_dark", "Slate")
    z.box("FenceEast", -0.5, 24, -0.2, 1.6, 15.4, 16, "cream", "Concrete", collide=True)
    z.box("FenceEastCap", -0.5, 24, 1.6, 1.85, 15.3, 16, "sage_dark", "Slate")
    for i, x in enumerate((-11.0, -1.0)):
        z.box("StoopPot", x-0.6, x+0.6, -0.2, 1.0, 14.0, 15.2, "clay", "Brick")
        z.box("StoopPlant", x-0.8, x+0.8, 1.0, 2.4, 13.8, 15.4, "leaf", "Grass")
    z.box("YardTreeTrunk", 17.4, 18.6, -0.2, 6, 4.4, 5.6, "wood_dark", "Wood", collide=True)
    z.box("YardTreeCanopy", 14.5, 21.5, 6, 10, 1.5, 8.5, "leaf", "Grass")
    z.add("YardTreeTop", (4.5, 3, 4.5), (18, 11.5, 5), "sage_dark", "Grass", rot=(0, 45, 0))
    return z


def lamp(z, name, x, zz, facing_x, height=9):
    """Base, pole, arm and head; the head carries the PointLight."""
    z.box(name+"Base", x-0.6, x+0.6, -0.2, 0.6, zz-0.6, zz+0.6, "ink", "Metal")
    z.box(name+"Pole", x-0.25, x+0.25, 0.6, height, zz-0.25, zz+0.25, "navy", "Metal")
    ax0, ax1 = sorted((x, x+facing_x*2.2))
    z.box(name+"Arm", ax0, ax1, height-0.4, height-0.1, zz-0.15, zz+0.15, "navy", "Metal")
    hx = x+facing_x*2.0
    light(z.box(name+"Head", hx-0.5, hx+0.5, height-1.0, height-0.4, zz-0.4, zz+0.4,
                "amber", shadow=False), 1.6, 22)


def neighbour(z, name, x0, x1, z0, z1, wall, roof, side):
    """Solid non-walkable house mass edging the lane; door/window face the road (side = +-1)."""
    face = x1 if side > 0 else x0
    def slab(t):  # thin slab on the road-facing plane, t studs proud
        return sorted((face, face + side*t))
    zc = (z0+z1)/2
    z.box(name, x0, x1, -0.2, 11, z0, z1, wall, "Concrete", collide=True)
    z.box(name+"Roof", x0-0.6, x1+0.6, 11, 11.8, z0-0.6, z1+0.6, roof, "Slate")
    z.box(name+"Plinth", *slab(0.3), -0.2, 1.0, z0, z1, "sage_dark", "Slate")
    z.box(name+"Door", *slab(0.15), 0, 7, zc-5, zc-1.5, "wood", "WoodPlanks")
    z.box(name+"Window", *slab(0.15), 3.5, 7, zc+1, zc+5, "pane")
    z.box(name+"Awning", *slab(2.2), 7.6, 8.0, zc-5.5, zc+5.5, "sage", "Fabric")


def build_street():
    z = Zone("StreetBlock", ORIGINS["StreetBlock"])
    z.box("Road", -16, 16, -1, 0, 16, 64, "asphalt", "Concrete", collide=True)
    z.box("SidewalkWest", -24, -16, -1, 0, 16, 64, "concrete", "Concrete", collide=True)
    z.box("SidewalkEast", 16, 24, -1, 0, 16, 64, "concrete", "Concrete", collide=True)
    # Flush paint/gutter inlays; 0.02 visual lift avoids coplanar z-fighting.
    for zz in (22, 32, 42, 52):
        z.box("CentreDash", -0.25, 0.25, 0, 0.02, zz, zz+5, "linen", shadow=False)
    z.box("GutterWest", -16.8, -15.6, 0, 0.02, 16, 64, "gutter", "Slate", shadow=False)
    z.box("GutterEast", 15.6, 16.8, 0, 0.02, 16, 64, "gutter", "Slate", shadow=False)
    # Gapura: neighbourhood entrance arch framing kiosk + fountain from the stoop.
    for sx in (-1, 1):
        x = sx*19
        z.box("GapuraPillar", x-1.2, x+1.2, -0.2, 13, 57, 59.4, "cream", "Concrete", collide=True)
        z.box("GapuraPillarCap", x-1.6, x+1.6, 13, 13.8, 56.6, 59.8, "roof", "Slate")
        z.box("GapuraPillarBand", x-1.3, x+1.3, 1.5, 2.3, 56.9, 59.5, "sage_dark", "Slate")
    beam = z.box("GapuraBeam", -17.8, 17.8, 10.4, 12.6, 57.4, 59.0, "sage", "Wood")
    gui(beam, "Front", "GANG MELATI", 80)  # NormalId Front = -Z, faces the house
    gui(beam, "Back", "GANG MELATI", 80)
    z.box("GapuraCrown", -6, 6, 12.6, 14.2, 57.6, 58.8, "cream", "Concrete")
    z.box("GapuraCrownCap", -6.6, 6.6, 14.2, 14.8, 57.3, 59.1, "roof", "Slate")
    lamp(z, "LampWest", -20, 30, 1)
    lamp(z, "LampEast", 20, 46, -1)
    # Tiang listrik with a cable pair across the lane.
    for name, x in (("UtilityPoleWest", -21.5), ("UtilityPoleEast", 21.5)):
        z.box(name, x-0.35, x+0.35, -0.2, 14, 39.65, 40.35, "wood_dark", "Wood")
        z.box(name+"Crossbar", x-1.6, x+1.6, 12.8, 13.1, 39.8, 40.2, "wood_dark", "Wood")
    z.add("CableA", (43, 0.1, 0.1), (0, 12.6, 39.9), "ink", shadow=False)
    z.add("CableB", (43, 0.1, 0.1), (0, 12.3, 40.1), "ink", shadow=False)
    # Street-name sign at the spawn throat (west sidewalk, outside the route).
    z.box("StreetSignPole", -21.2, -20.8, -0.2, 4.5, 17.8, 18.2, "metal", "Metal")
    sign = z.box("StreetSignPlate", -23.0, -19.0, 4.5, 5.6, 17.9, 18.1, "navy")
    gui(sign, "Front", "Jl. Melati", 60)
    gui(sign, "Back", "Jl. Melati", 60)
    # Delivery bike: one storytelling prop on the east sidewalk.
    z.box("BikeFrame", 21.6, 22.0, 1.2, 1.6, 26, 29, "sage_dark", "Metal")
    z.box("BikeCrate", 21.2, 22.4, 1.6, 2.6, 28, 29.4, "amber", "WoodPlanks")
    for zz in (26.2, 28.8):
        z.add("BikeWheel", (0.3, 1.2, 1.2), (21.8, 0.6, zz), "ink", "Metal", shape=2)
    neighbour(z, "NeighbourWestA", -36, -24, 18, 38, "plaster", "roof", 1)
    neighbour(z, "NeighbourWestB", -36, -24, 40, 56, "brick", "sage_dark", 1)
    neighbour(z, "NeighbourEastA", 24, 36, 18, 34, "linen", "sage_dark", -1)
    neighbour(z, "NeighbourEastB", 24, 36, 36, 56, "plaster", "roof", -1)
    return z


def build_town():
    z = Zone("TownCenter", ORIGINS["TownCenter"])
    c = (0, 112)
    z.box("PlazaGround", -56, 56, -1, 0, 64, 160, "concrete", "Concrete", collide=True)
    z.disc("PlazaDisc", c, 40, -0.5, 0.02, "paving", "Cobblestone", shadow=False)
    z.disc("FountainApron", c, 16, -0.4, 0.04, "brick", "Brick", shadow=False)
    # Basin r=8 from 12 wall segments (a Roblox Cylinder cannot be hollow).
    seg = 2*8*math.tan(math.radians(15))
    for i in range(12):
        z.yawed("BasinWall", (seg, 2.2, 1.0), (0, 0, 112), i*30, (0, 1.1, 7.5),
                "cream", "Concrete", collide=True)
    z.disc("BasinWater", c, 7.05, 0, 1.6, "water", shadow=False)
    z.disc("FountainPedestal", c, 1.4, 0, 4.2, "cream", "Concrete", collide=True)
    z.disc("FountainBowl", c, 3.2, 4.2, 4.9, "sage", "Concrete")
    z.disc("FountainFinial", c, 0.7, 4.9, 6.6, "cream", "Concrete")
    z.disc("FountainJet", c, 0.35, 6.6, 7.6, "water", shadow=False)
    # Lamps on the plaza ring, outside the fountain clearance ring (r 8..16).
    for i, (x, zz, fx) in enumerate(((-20, 92, 1), (20, 92, -1), (-20, 132, 1), (20, 132, -1))):
        lamp(z, f"PlazaLamp{i+1}", x, zz, fx)
    # Benches at r=22 facing the fountain; non-colliding decoration.
    for x, zz, yaw in ((-22, 112, -90), (22, 112, 90), (0, 134, 0), (-15.6, 127.6, -45)):
        for name, size, off, tint, mat in (
                ("BenchSeat", (5, 0.4, 1.6), (0, 1.4, 0), "wood_light", "Wood"),
                ("BenchBack", (5, 1.4, 0.3), (0, 2.3, 0.75), "wood", "Wood"),
                ("BenchBase", (4, 1.2, 1.0), (0, 0.6, 0), "ink", "Metal")):
            z.yawed(name, size, (x, 0, zz), yaw, off, tint, mat)
    for x, zz in ((-30, 100), (30, 100), (-30, 124), (30, 124)):
        z.box("Planter", x-1.2, x+1.2, -0.2, 1.4, zz-1.2, zz+1.2, "clay", "Brick")
        z.box("PlanterLeaves", x-1.5, x+1.5, 1.4, 3.0, zz-1.5, zz+1.5, "leaf", "Grass")
    for x, zz in ((-44, 76), (44, 76)):
        z.box("ShadeTreeTrunk", x-0.8, x+0.8, -0.2, 7, zz-0.8, zz+0.8, "wood_dark", "Wood", collide=True)
        z.box("ShadeTreeCanopy", x-5, x+5, 7, 12, zz-5, zz+5, "leaf", "Grass")
        z.add("ShadeTreeTop", (6, 3.5, 6), (x, 13.5, zz), "sage_dark", "Grass", rot=(0, 45, 0))
    # Inert bus stop at City_TransitStop (24,0,96) with an honest sign.
    z.box("BusShelterRoof", 21, 29, 8, 8.5, 93, 99, "sage", "Metal")
    z.box("BusShelterPostA", 28.3, 28.8, -0.2, 8, 93.3, 93.8, "metal", "Metal")
    z.box("BusShelterPostB", 28.3, 28.8, -0.2, 8, 98.2, 98.7, "metal", "Metal")
    z.box("BusShelterBack", 28.4, 28.7, 2, 6.5, 93.8, 98.2, "pane")
    z.box("BusShelterBench", 26.5, 28.3, 1.2, 1.6, 94, 98, "wood_light", "Wood")
    bus = z.box("BusStopSign", 22.6, 23.0, 3.5, 6.5, 99.5, 102.5, "navy")
    z.box("BusStopPole", 22.65, 22.95, -0.2, 3.5, 100.85, 101.15, "metal", "Metal")
    gui(bus, "Left", "HALTE\nBelum beroperasi", 40)
    gui(bus, "Right", "HALTE\nBelum beroperasi", 40)
    # Warnet (retro internet cafe), SW corner, open front toward the plaza.
    W = ("plaster", "Concrete")
    z.box("WarnetBack", -56, -55, -0.2, 13, 138, 158, *W, collide=True)
    z.box("WarnetSideNorth", -56, -42, -0.2, 13, 138, 139, *W, collide=True)
    z.box("WarnetSideSouth", -56, -42, -0.2, 13, 157, 158, *W, collide=True)
    z.box("WarnetRoof", -57, -41, 13, 13.8, 137, 159, "navy", "Slate")
    sign = z.box("WarnetSign", -42.4, -41.8, 9.6, 12.4, 139, 157, "navy")
    gui(sign, "Right", "WARNET  ·  Net 24 Jam", 70, "amber")
    z.box("WarnetCounter", -46, -43, -0.2, 3.4, 141, 155, "wood", "Wood", collide=True)
    z.box("WarnetCounterTop", -46.3, -42.7, 3.4, 3.7, 140.8, 155.2, "wood_light", "Wood")
    for zz in (143.5, 148, 152.5):
        z.box("WarnetCRT", -46, -44.4, 3.7, 5.3, zz-0.9, zz+0.9, "linen")
        z.box("WarnetScreen", -44.4, -44.3, 4.0, 5.0, zz-0.6, zz+0.6, "phosphor", shadow=False)
    z.box("WarnetAwning", -42, -38.5, 8.6, 9.0, 139, 157, "sage", "Fabric")
    # Warung kopi, SE corner (east shop row Z3 ends at z 144).
    z.box("WarungCounter", 42, 52, -0.2, 3.2, 150, 152, "wood", "WoodPlanks", collide=True)
    z.box("WarungCounterTop", 41.8, 52.2, 3.2, 3.5, 149.8, 152.2, "wood_light", "Wood")
    z.box("WarungBack", 41, 54, -0.2, 10, 157, 158, "brick", "Brick", collide=True)
    for x in (41.5, 53.5):
        z.box("WarungPost", x-0.3, x+0.3, -0.2, 9, 149.4, 150.0, "wood_dark", "Wood")
    z.add("WarungAwning", (14, 0.4, 9.4), (47.5, 9.4, 153.6), "amber", "Fabric", rot=(-12, 0, 0))
    wsign = z.box("WarungSign", 43, 52, 6.2, 8.2, 149.3, 149.5, "linen", "WoodPlanks")
    gui(wsign, "Front", "Warung Kopi Bu Sri", 56, "wood_dark")
    # Zone edges. East/west hedges reserve the M2-B shop lots; removed when shops land.
    H = ("sage_dark", "Grass")
    z.box("HedgeNorthWest", -56, -24, -0.2, 2.6, 64, 65.4, *H, collide=True)
    z.box("HedgeNorthEast", 24, 56, -0.2, 2.6, 64, 65.4, *H, collide=True)
    z.box("BoundarySouthWest", -56, -8, -0.2, 3.4, 159, 160, "cream", "Concrete", collide=True)
    z.box("BoundarySouthEast", 8, 56, -0.2, 3.4, 159, 160, "cream", "Concrete", collide=True)
    z.box("LotReserveWest", -56, -55, -0.2, 2.6, 65.4, 138, *H, collide=True)
    z.box("LotReserveEast", 55, 56, -0.2, 2.6, 65.4, 149, *H, collide=True)
    return z


def build_boards():
    """D2 option B: 6x6x9 open frame, X -3..3, Z 65..71; boards edge-on to the axis."""
    z = Zone("CityBoards", ORIGINS["CityBoards"])
    z.box("KioskPad", -4, 4, 0, 0.06, 64.4, 71.6, "brick", "Brick", shadow=False)
    for x0, x1 in ((-3, -2), (2, 3)):
        for z0, z1 in ((65, 66), (70, 71)):
            z.box("KioskPost", x0, x1, 0, 9, z0, z1, "wood_dark", "Wood", collide=True)
        z.box("KioskPostFoot", x0-0.15, x1+0.15, 0.06, 0.6, 64.85, 71.15, "ink", "Metal")
        # Board panel spans between the two posts of one side, facing outward (+-X).
        xs = x0 if x0 < 0 else x1
        side = -1 if x0 < 0 else 1
        z.box("BoardBacking", x0, x1, 2.6, 6.4, 66, 70, "wood", "Wood")
        cork = z.box("BoardCork", *sorted((xs, xs+side*0.1)), 2.9, 6.1, 66.3, 69.7, "clay", "Fabric")
        gui(cork, "Left" if side < 0 else "Right", "MISI HARIAN", 48, "linen")
        for yy, zz, tint in ((5.2, 67.2, "linen"), (4.6, 68.6, "amber"), (3.7, 67.6, "sage")):
            z.box("BoardNote", *sorted((xs+side*0.1, xs+side*0.14)), yy-0.4, yy+0.4,
                  zz-0.5, zz+0.5, tint, shadow=False)
    # Rear sign band (Z 69.5..70.5, Y 6..9 per canonical spec) faces the stoop (-Z).
    band = z.box("SignBand", -3, 3, 6.4, 8.6, 69.5, 70.5, "navy")
    # Front posts hide the band's outer stud each side; keep text inside the 4-stud bay.
    gui(band, "Front", "PAPAN MISI", 64, "amber", inset=0.2)
    gui(band, "Back", "PAPAN MISI", 64, "amber", inset=0.2)
    z.box("SignBandTrim", -3.1, 3.1, 6.2, 6.4, 69.4, 70.6, "amber", "Wood")
    z.box("KioskRoof", -3.7, 3.7, 8.6, 9.0, 64.3, 71.7, "roof", "Slate")
    z.box("KioskLamp", -0.4, 0.4, 8.0, 8.6, 66.4, 67.2, "amber", shadow=False)
    return z


def build_gate():
    """Z7 teaser: closed rolling shutter under a lintel. No opening, no timer."""
    z = Zone("CityGate", ORIGINS["CityGate"])
    z.box("GatePad", -8, 8, -1, 0, 160, 176, "concrete", "Concrete", collide=True)
    z.box("GateApron", -5, 5, 0, 0.04, 160, 165.4, "brick", "Brick", shadow=False)
    for x0, x1 in ((-7.7, -4.7), (4.7, 7.7)):
        z.box("GatePillar", x0, x1, 0, 15, 163, 169, "cream", "Concrete", collide=True)
        z.box("GatePillarBand", x0-0.1, x1+0.1, 1.2, 2.0, 162.9, 169.1, "sage_dark", "Slate")
        z.box("GatePillarCap", x0-0.3, x1+0.3, 15, 15.8, 162.7, 169.3, "roof", "Slate")
        z.box("GateSideWall", x0, x1, 0, 6, 160, 163, "cream", "Concrete", collide=True)
    z.box("GateLintel", -4.7, 4.7, 12, 15, 164, 168, "sage", "Wood", collide=True)
    sign = z.box("GateSign", -4.6, 4.6, 12.4, 14.6, 163.8, 164, "navy")
    gui(sign, "Front", "DISTRIK BARU\nBelum dibuka", 56, "amber")
    z.box("GateShutter", -4.7, 4.7, 0, 12, 165.6, 166.4, "shutter", "Metal", collide=True)
    for y in (3, 6, 9):
        z.box("GateShutterRib", -4.7, 4.7, y-0.12, y+0.12, 165.45, 165.6, "metal", "Metal")
    z.box("GateShutterHandle", -1, 1, 0.8, 1.2, 165.3, 165.45, "ink", "Metal")
    z.box("GateRearWall", -8, 8, 0, 15, 175, 176, "plaster", "Concrete", collide=True)
    z.box("GateTowerHint", -3, 3, 15.8, 22, 170, 174, "sky_tower", "Concrete")
    return z


def build_backdrop(x0, x1, name="CityBackdrop"):
    """Eight opaque, non-colliding slabs; layout scales with the X extent.
    Ridge/hills extend below grade so downward window rays never see void."""
    z = Zone(name, ((x0+x1)/2, 0, -152))
    w = x1 - x0
    def at(f):
        return x0 + f*w
    z.box("Ridge", x0, x1, -40, 34, -192, -186, "sky_ridge", shadow=False)
    z.box("Hills", x0, x1, -24, 16, -122, -112, "sky_hill", "Grass", shadow=False)
    for i, (f0, f1, h, tint) in enumerate(((0.06, 0.2, 38, "sky_a"), (0.5, 0.62, 46, "sky_b"),
                                           (0.66, 0.8, 30, "sky_c"), (0.84, 0.96, 52, "sky_a"))):
        z.box(f"Block{i+1}", at(f0), at(f1), 0, h, -170, -156, tint, "Concrete", shadow=False)
    t = at(0.36)
    z.box("AgencyTower", t-7, t+7, 0, 78, -166, -152, "sky_tower", "Concrete", shadow=False)
    z.box("AgencyAntenna", t-0.6, t+0.6, 78, 96, -159.6, -158.4, "ink", "Metal", shadow=False)
    return z


def build_anchors():
    z = Zone("City_Anchors", (0, 0, 0))
    for name, pos in ANCHORS:
        z.add(name, (1, 1, 1), pos, "cream", transparency=1)
    return z


# ------------------------------------------------------------------ serializer
CF_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
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
    """UDim2 offsets are int32 in rbxmx; scales are floats."""
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
    """Geometry local to the zone origin; model pivot = identity at that origin."""
    global _ref
    _ref = 0
    props = []
    if root_class == "Model":
        pivot = ET.Element("OptionalCoordinateFrame", {"name": "WorldPivotData"})
        pivot.append(_v("CFrame", None, CF_KEYS, (0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)))
        props = [pivot, _p("token", "ModelStreamingMode", streaming(zone.name))]
    root_el = _item(root_class, zone.name, props)  # parent referent first: stable order
    root_el.extend(_part(p, zone.origin) for p in zone.parts)
    doc = ET.Element("roblox", {"version": "4"})
    doc.append(root_el)
    ET.indent(doc, "  ")
    return ET.tostring(doc, encoding="unicode") + "\n"


# --------------------------------------------------------------------- outputs
PREFABS = [("HouseExterior", build_house, "Model"), ("StreetBlock", build_street, "Model"),
           ("TownCenter", build_town, "Model"), ("CityBoards", build_boards, "Model"),
           ("CityGate", build_gate, "Model"),
           ("CityBackdrop", lambda: build_backdrop(16, 160), "Model"),
           ("CityBackdrop_CenteredReview",
            lambda: build_backdrop(-120, 120, "CityBackdrop_CenteredReview"), "Model"),
           ("CityAnchors", build_anchors, "Folder")]
REVIEW_ONLY = {"CityBackdrop_CenteredReview"}  # never assembled with the baseline


def zones():
    return {name: build() for name, build, _ in PREFABS}


def manifest(zs):
    rows = {}
    for name, z in zs.items():
        rows[name] = {
            "origin": list(z.origin), "baseparts": len(z.parts),
            "markers": [p["name"] for p in z.parts if p["name"].startswith("City_")],
            "surface_guis": sum(len(p["guis"]) for p in z.parts),
            "point_lights": sum(len(p["lights"]) for p in z.parts),
            "scripts": 0,
            "root": "Folder" if name == "CityAnchors" else
                    {1: "Model/Atomic", 2: "Model/Persistent"}[streaming(name)]}
    assembled = [n for n in rows if n not in REVIEW_ONLY]
    return {"generator": "tools/gen_city_prefabs.py", "status": "M2-A1 isolated review blockout",
            "prefabs": rows, "assembled": assembled,
            "assembled_city_baseparts": sum(rows[n]["baseparts"] for n in assembled),
            "assembled_point_lights": sum(rows[n]["point_lights"] for n in assembled),
            "marker_subset_a1": ["City_HomeDoor"] + [n for n, _ in ANCHORS],
            "marker_deferred": DEFERRED,
            "backdrop_variants": {"CityBackdrop": "FROZEN baseline X 16..160",
                                  "CityBackdrop_CenteredReview": "PROPOSED D1 X -120..120, review copy"}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "..", "assets", "world", "city"))
    out = ap.parse_args().out
    os.makedirs(out, exist_ok=True)
    zs = zones()
    for name, _, cls in PREFABS:
        with open(os.path.join(out, name + ".rbxmx"), "w", encoding="utf-8", newline="\n") as f:
            f.write(to_xml(zs[name], cls))
    m = manifest(zs)
    with open(os.path.join(out, "city-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(m, indent=2, sort_keys=True) + "\n")
    for n, r in m["prefabs"].items():
        print(f"{n:28} {r['baseparts']:4} parts {len(r['markers']):3} markers {r['point_lights']} lights")
    print("assembled city BaseParts:", m["assembled_city_baseparts"],
          "| PointLights:", m["assembled_point_lights"])


if __name__ == "__main__":
    main()

