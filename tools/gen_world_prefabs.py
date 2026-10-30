"""Deterministic, original BS-05 Part kits. No downloaded assets or scripts."""
import math
import os
import xml.etree.ElementTree as ET
from xml.dom import minidom

_ref_counter = 0
PALETTE = {
    "cream": (233, 222, 199), "plaster": (219, 211, 190),
    "wood": (153, 112, 75), "wood_light": (180, 139, 96),
    "wood_dark": (101, 74, 55), "sage": (132, 151, 126),
    "sage_dark": (80, 108, 86), "navy": (52, 68, 81),
    "ink": (32, 42, 45), "amber": (236, 186, 111),
    "linen": (246, 236, 216), "metal": (110, 119, 115),
    "glass": (150, 178, 177), "screen": (39, 63, 62),
    "phosphor": (177, 206, 166), "clay": (166, 115, 88),
}
MATERIALS = {"SmoothPlastic": 256, "Wood": 512, "WoodPlanks": 528,
             "Metal": 1088, "Fabric": 1312, "Neon": 288, "Glass": 1568}


def item(cls, name, props=None, children=None):
    global _ref_counter
    _ref_counter += 1
    result = ET.Element("Item", {"class": cls, "referent": f"RBX{_ref_counter}"})
    properties = ET.SubElement(result, "Properties")
    ET.SubElement(properties, "string", {"name": "Name"}).text = name
    for key, value in (props or {}).items():
        if isinstance(value, ET.Element):
            properties.append(value)
        else:
            tag, text = value
            ET.SubElement(properties, tag, {"name": key}).text = str(text)
    result.extend(children or [])
    return result


def vector(name, values, tag="Vector3", keys=("X", "Y", "Z")):
    result = ET.Element(tag, {"name": name})
    for key, value in zip(keys, values):
        ET.SubElement(result, key).text = str(round(value, 6))
    return result


def color(name, value):
    rgb = PALETTE[value] if isinstance(value, str) else value
    return vector(name, [v / 255 for v in rgb], "Color3", ("R", "G", "B"))


def part(name, size, pos, tint, material="SmoothPlastic", collide=False,
         transparency=0, shape=1, rotation=(0, 0, 0)):
    # Euler XYZ, serialized as an orthonormal CFrame rather than Orientation.
    x, y, z = [math.radians(v) for v in rotation]
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    matrix = (cy*cz, -cy*sz, sy, cx*sz+sx*sy*cz, cx*cz-sx*sy*sz,
              -sx*cy, sx*sz-cx*sy*cz, sx*cz+cx*sy*sz, cx*cy)
    return item("Part", name, {
        "size": vector("size", size),
        "CFrame": vector("CFrame", (*pos, *matrix), "CoordinateFrame",
                         ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")),
        "Color": color("Color", tint), "Material": ("token", MATERIALS[material]),
        "shape": ("token", shape), "Anchored": ("bool", "true"),
        "CanCollide": ("bool", str(collide).lower()),
        "CanTouch": ("bool", "false"), "CanQuery": ("bool", str(collide).lower()),
        "CastShadow": ("bool", str(transparency == 0).lower()),
        "TopSurface": ("token", 0), "BottomSurface": ("token", 0),
        "Transparency": ("float", transparency),
    })


def model(name, children, primary=None):
    result = item("Model", name, children=children)
    if primary:
        target = next(c for c in children if c.find("Properties/string[@name='Name']").text == primary)
        ET.SubElement(result.find("Properties"), "Ref", {"name": "PrimaryPart"}).text = target.attrib["referent"]
    return result


def anchor(name, pos, size=(1, 1, 1)):
    return part(name, size, pos, "cream", transparency=1)


def light(parent, name, brightness, reach, tint="amber"):
    parent.append(item("PointLight", name, {
        "Color": color("Color", tint), "Brightness": ("float", brightness),
        "Range": ("float", reach), "Shadows": ("bool", "true"),
    }))
    return parent


def rounded(name, size, pos, tint, radius, material="SmoothPlastic", collide=False):
    """Six-part rounded XY silhouette; cylinder axes face Z."""
    w, h, d = size
    x, y, z = pos
    pieces = [part(name, (w-2*radius, h, d), pos, tint, material, collide=collide),
              part(name+"Cross", (w, h-2*radius, d), pos, tint, material, collide=collide)]
    for dx in (-1, 1):
        for dy in (-1, 1):
            pieces.append(part(name+"Corner", (d, 2*radius, 2*radius),
                               (x+dx*(w/2-radius), y+dy*(h/2-radius), z),
                               tint, material, shape=2, rotation=(0, 90, 0)))
    return pieces


def build_bedroom():
    c = []
    def add(name, size, pos, tint, material="SmoothPlastic", **kw):
        p = part(name, size, pos, tint, material, **kw)
        c.append(p)
        return p

    add("Floor", (24, 1, 24), (0, -.5, 0), "wood_dark", "Wood", collide=True)
    # Broad, low-contrast boards avoid a noisy checkerboard at phone resolution.
    for i in range(12):
        add("Floorboard", (1.98, .06, 23), (-11+i*2, .03, 0),
            (160, 119, 81) if i % 3 == 0 else (153, 112, 75), "Wood")
    # The north wall has an actual window opening, not glass over opaque plaster.
    for name, size, pos in [
        ("WallNorthLeft", (12, 10, .5), (-6, 5, -12)),
        ("WallNorthRight", (6, 10, .5), (9, 5, -12)),
        ("WindowWallBelow", (6, 3, .5), (3, 1.5, -12)),
        ("WindowWallAbove", (6, 2, .5), (3, 9, -12)),
        ("WallEast", (.5, 10, 24), (12, 5, 0)),
        ("WallWest", (.5, 10, 24), (-12, 5, 0)),
        ("WallSouth", (24, 10, .5), (0, 5, 12)),
    ]:
        # Solid lower walls, no ceiling lid: Roblox's normal camera can orbit above.
        add(name, size, pos, "plaster", collide=True)
    for name, size, pos in [
        ("TrimNorth", (23.5, .4, .15), (0, .2, -11.7)),
        ("TrimSouth", (23.5, .4, .15), (0, .2, 11.7)),
        ("TrimEast", (.15, .4, 23.5), (11.7, .2, 0)),
        ("TrimWest", (.15, .4, 23.5), (-11.7, .2, 0)),
        ("CorniceNorth", (24, .25, .35), (0, 9.75, -11.7)),
        ("CorniceEast", (.35, .25, 24), (11.7, 9.75, 0)),
        ("CorniceWest", (.35, .25, 24), (-11.7, 9.75, 0)),
        ("CorniceSouth", (24, .25, .35), (0, 9.75, 11.7)),
    ]:
        add(name, size, pos, "cream", "Wood")
    add("Door", (3.7, 7.3, .18), (-6, 3.65, 11.6), "sage", "Wood", collide=True)
    for x in (-8, -4):
        add("DoorJamb", (.18, 7.6, .28), (x, 3.8, 11.45), "cream", "Wood")
    add("DoorLintel", (4.2, .2, .28), (-6, 7.6, 11.45), "cream", "Wood")
    add("DoorInset", (3.1, 5.7, .05), (-6, 3.7, 11.48), "sage_dark", "Wood")
    add("DoorHandle", (.45, .1, .2), (-4.6, 3.5, 11.25), "amber", "Metal")

    add("WindowGlass", (5.8, 4.8, .08), (3, 5.5, -12.08), "glass", "Glass", transparency=.35)
    for x in (0, 3, 6):
        add("WindowMullion", (.16, 5.2, .24), (x, 5.5, -11.83), "cream", "Wood")
    for y in (3, 5.5, 8):
        add("WindowRail", (6.2, .16, .24), (3, y, -11.83), "cream", "Wood")
    add("WindowSill", (6.7, .2, .8), (3, 2.95, -11.65), "wood_light", "Wood")
    add("CurtainRail", (7.7, .1, .1), (3, 8.45, -11.4), "wood_dark", "Wood")
    for x in (-.55, 6.55):
        for dx in (-.26, 0, .26):
            add("CurtainFold", (.28, 5.3, .22), (x+dx, 5.6, -11.35),
                "sage" if dx else "sage_dark", "Fabric")

    # Exact desktop upper surface and slot positions are frozen.
    add("DeskTop", (7, .3, 3), (7, 3.2, -4), "wood_light", "Wood", collide=True)
    add("DeskFrontApron", (6.6, .4, .18), (7, 2.85, -2.68), "wood", "Wood")
    for x, z in ((3.85, -2.8), (3.85, -5.2), (10.15, -5.2)):
        add("DeskLeg", (.32, 3, .32), (x, 1.5, z), "wood_dark", "Wood", collide=True)
    add("DrawerCarcass", (1.5, 2.65, 2.55), (9.55, 1.65, -4.05), "wood_dark", "Wood", collide=True)
    for y in (.8, 1.65, 2.5):
        add("DrawerFront", (1.38, .75, .12), (9.55, y, -2.72), "wood", "Wood")
        add("DrawerPull", (.48, .08, .12), (9.55, y+.12, -2.6), "amber", "Metal")
    add("DeskRearRail", (6.2, .3, .18), (7, 1, -5.18), "wood", "Wood")

    # Raised frame with a visible under-bed shadow, rather than a solid plinth.
    for x in (-9.15, -4.85):
        for z in (1.8, 8.15):
            add("BedFoot", (.35, .85, .35), (x, .425, z), "wood_dark", "Wood", collide=True)
    add("BedFrame", (5, .5, 7.2), (-7, .95, 5), "wood", "Wood", collide=True)
    add("Headboard", (5.1, 2.65, .25), (-7, 1.85, 1.4), "wood_dark", "Wood", collide=True)
    add("HeadboardInset", (4.5, 1.4, .1), (-7, 2.2, 1.58), "sage")
    c.extend(rounded("Mattress", (4.65, .68, 6.8), (-7, 1.54, 5), "linen", .22, collide=True))
    add("MattressPiping", (4.7, .07, 6.85), (-7, 1.6, 5), "cream", "Fabric")
    add("Blanket", (4.72, .2, 4.6), (-7, 1.98, 6), "sage", "Fabric")
    for x in (-9.32, -4.68):
        add("BlanketDrape", (.12, .68, 4.6), (x, 1.68, 6), "sage", "Fabric")
    add("BlanketFold", (4.75, .16, .65), (-7, 2.13, 3.85), "sage_dark", "Fabric")
    add("BlanketHem", (4.72, .06, .14), (-7, 2.1, 8.1), "cream", "Fabric")
    for x, z in ((-8.05, 2.55), (-5.95, 2.65)):
        c.extend(rounded("Pillow", (1.95, .38, 1.25), (x, 2.02, z), "linen", .16))
    add("BedsideTable", (1.5, .16, 1.5), (-10.6, 1.9, 3), "wood_light", "Wood")
    for x in (-11.1, -10.1):
        add("BedsideLeg", (.15, 1.85, 1.15), (x, .925, 3), "wood_dark", "Wood")
    add("BedsideBook", (.7, .12, .9), (-10.6, 2.05, 3), "navy")
    add("RugBorder", (7.1, .035, 4.3), (-2, .08, 5), "cream", "Fabric")
    add("Rug", (6.8, .035, 4), (-2, .102, 5), "navy", "Fabric")
    for z in (3.25, 6.75):
        add("RugStripe", (6.7, .01, .12), (-2, .126, z), "sage", "Fabric")

    # Dressing concentrated at the north/east edges; west worker footprints stay empty.
    for x in (-3.8, -.2):
        add("BookcaseSide", (.18, 4.7, 1.15), (x, 2.35, -10.9), "wood", "Wood", collide=True)
    add("BookcaseBack", (3.7, 4.7, .12), (-2, 2.35, -11.45), "wood_dark", "Wood")
    for y in (.2, 1.7, 3.2, 4.7):
        add("Bookshelf", (3.8, .16, 1.2), (-2, y, -10.9), "wood_light", "Wood")
    for i in range(7):
        h = .7 + (i % 3)*.16
        add("BookSpine", (.25, h, .65), (-3.35+i*.4, 3.28+h/2, -10.8),
            ("sage", "cream", "navy")[i % 3])
    add("StorageBox", (2, .8, .95), (-2.3, .68, -10.9), "sage", "Fabric")
    add("BoxPull", (.4, .13, .04), (-2.3, .8, -10.4), "cream")
    # Original abstract sunset print, assembled from geometry; no image license.
    add("PosterFrame", (2.8, 3.4, .12), (8.6, 6.8, -11.65), "wood_dark", "Wood")
    add("PosterPaper", (2.5, 3.1, .03), (8.6, 6.8, -11.56), "linen")
    add("PosterSun", (.035, 1.1, 1.1), (8.6, 7.25, -11.53), "amber", shape=2, rotation=(0, 90, 0))
    add("PosterHorizon", (2.15, .7, .04), (8.6, 6.15, -11.51), "sage")
    add("PosterSea", (2.15, .25, .045), (8.6, 5.92, -11.5), "navy")
    add("PlantPot", (.9, .85, .9), (10.65, .485, -9.4), "clay")
    add("PotRim", (1, .12, 1), (10.65, .88, -9.4), "clay")
    add("Soil", (.78, .07, .78), (10.65, .92, -9.4), "wood_dark")
    for dx, dy, dz, tilt in ((-.35, 1.5, 0, -30), (.3, 1.65, .1, 30), (0, 1.9, -.1, 0), (.1, 1.5, .4, 45)):
        add("PlantLeaf", (.38, 1.15, .22), (10.65+dx, dy, -9.4+dz), "sage_dark", shape=0, rotation=(0, 0, tilt))
    add("Notebook", (.7, .08, .8), (10.05, 3.4, -4.65), "navy", rotation=(0, -8, 0))
    add("NotebookPages", (.65, .035, .75), (10.05, 3.445, -4.65), "linen", rotation=(0, -8, 0))
    add("Mug", (.33, .4, .33), (5.25, 3.55, -5), "cream")
    add("Coffee", (.27, .015, .27), (5.25, 3.755, -5), "wood_dark")
    add("MugHandle", (.14, .23, .12), (5.47, 3.56, -5), "cream")
    for name, size, pos in [("CableAcrossDesk", (1.25, .045, .045), (8.85, 3.39, -5.25)),
                            ("CableDownDesk", (.045, 2.95, .045), (9.45, 1.9, -5.3))]:
        add(name, size, pos, "ink")

    prompt = anchor("DashboardPromptAnchor", (7.4, 3.6, -2.4), (1.5, 1.5, .4))
    prompt.append(item("ProximityPrompt", "DashboardPrompt", {
        "ActionText": ("string", "Open BuzzerOS"), "ObjectText": ("string", "BuzzerOS Terminal"),
        "MaxActivationDistance": ("float", 10), "HoldDuration": ("float", 0),
        "RequiresLineOfSight": ("bool", "false"),
    }))
    c.append(prompt)
    for name, pos, size in [
        ("Spawn", (0, .6, 6), (4, 1, 4)), ("PlayerDesk", (7, 3.35, -4), (7, .3, 3)),
        ("TerminalSlot", (7.4, 3.35, -4), (3, .2, 2.6)),
        ("PhoneSlot", (4.6, 3.35, -3.8), (1.4, .2, 1.4)),
        ("WorkerDeskSlot1", (-8, 3.2, -8), (4, .4, 2.4)),
        ("WorkerSeat1", (-8, 1.6, -6.2), (2, 2, 2)),
        ("WorkerDeskSlot2", (-8, 3.2, -2), (4, .4, 2.4)),
        ("WorkerSeat2", (-8, 1.6, -.2), (2, 2, 2)),
        ("CameraFocus", (7, 5.5, 3), (1, 1, 1)),
    ]:
        c.append(anchor(name, pos, size))
    fixtures = [
        part("PendantCanopy", (.12, .5, .5), (1, 9.92, 0), "wood_dark", shape=2, rotation=(0, 0, 90)),
        part("PendantCord", (.055, .8, .055), (1, 9.5, 0), "ink"),
        part("PendantShade", (.45, 1.65, 1.65), (1, 8.9, 0), "cream", shape=2, rotation=(0, 0, 90)),
        light(part("PendantDiffuser", (.06, 1.4, 1.4), (1, 8.65, 0), "linen", shape=2, rotation=(0, 0, 90)), "RoomWarmth", .75, 23, (255, 232, 202)),
        part("LampBase", (.6, .1, .6), (10.05, 3.4, -3.4), "sage_dark"),
        part("LampStem", (.08, 1.25, .08), (10.05, 4.05, -3.4), "metal", "Metal"),
        part("LampShade", (.4, .8, .8), (10.05, 4.65, -3.4), "sage", shape=2, rotation=(0, 0, 90)),
        light(part("LampDiffuser", (.04, .65, .65), (10.05, 4.43, -3.4), "linen", shape=2, rotation=(0, 0, 90)), "DeskPool", .4, 8),
        light(anchor("WindowFill", (3, 6, -11)), "SoftDaylight", .65, 17, (208, 227, 224)),
    ]
    c.append(item("Folder", "LightGroup", children=fixtures))
    return model("Bedroom", c)


def build_old_crt():
    # PrimaryPart remains at (0, 1.4, 0): WorldService's frozen pivot offset.
    c = [part("MonitorBody", (3.1, 2.15, 1.65), (0, 1.4, 0), "cream"),
         part("UpperShell", (2.92, .18, 1.55), (0, 2.565, .02), "linen"),
         part("TubeHousing", (2.45, 1.7, .65), (0, 1.5, 1.1), "plaster"),
         part("TubeRear", (1.9, 1.3, .3), (0, 1.5, 1.52), "cream"),
         part("StandNeck", (.6, .35, .6), (0, .225, .25), "plaster"),
         part("StandBase", (2.15, .15, 1.3), (0, .075, .2), "cream"),
         part("Bezel", (2.78, 1.97, .12), (0, 1.42, -.87), "wood_light"),
         part("ScreenRecess", (2.52, 1.66, .06), (0, 1.52, -.96), "ink"),
         part("Screen", (2.32, 1.46, .045), (0, 1.52, -1.005), "screen"),
         part("ScreenHighlight", (2.15, .025, .01), (0, 2.19, -1.033), "metal"),
         part("PowerButton", (.16, .12, .06), (1.12, .59, -.97), "wood_dark"),
         part("PowerLED", (.055, .055, .02), (.93, .59, -.98), "phosphor"),
         part("ServiceSticker", (.35, .18, .015), (-1.1, .59, -.94), "linen"),
         part("Scuff", (.22, .035, .012), (1.3, 2.29, -.835), "wood_light"),
         part("KeyboardBase", (2.65, .14, .64), (0, .07, -1.07), "plaster"),
    ]
    for side in (-1, 1):
        for z in (.15, .4, .65, .9):
            c.append(part("Vent", (.018, .5, .065), (side*1.235, 1.55, z+.3), "wood_dark"))
    for row in range(3):
        for col in range(8):
            c.append(part("Keycap", (.25, .055, .125), (-1.08+col*.31, .1675, -1.26+row*.17), "linen"))
    c.append(part("Spacebar", (1.2, .055, .1), (0, .1675, -.79), "cream"))
    # Physical screen graphics, no floating billboard or fake interactive controls.
    for name, size, pos, tint in [
        ("ScreenRule", (1.8, .025, .012), (-.1, 1.8, -1.035), "sage"),
        ("ScreenLine", (1.2, .055, .012), (-.4, 1.62, -1.035), "sage"),
        ("ScreenLine", (1.55, .055, .012), (-.225, 1.48, -1.035), "sage"),
        ("ScreenCursor", (.09, .14, .012), (-.95, 1.17, -1.035), "phosphor"),
    ]:
        c.append(part(name, size, pos, tint))
    # Small on-screen, world-occluded title; no always-on-top scene label.
    screen = next(p for p in c if p.find("Properties/string[@name='Name']").text == "Screen")
    gui = item("SurfaceGui", "BuzzerOSScreen", {
        "Face": ("token", 5), "CanvasSize": vector("CanvasSize", (512, 320), "Vector2", ("X", "Y")),
        "AlwaysOnTop": ("bool", "false"), "LightInfluence": ("float", 1),
    })
    gui.append(item("TextLabel", "Title", {
        "Size": vector("Size", (1, 0, .3, 0), "UDim2", ("XS", "XO", "YS", "YO")),
        "BackgroundTransparency": ("float", 1), "Text": ("string", "BuzzerOS"),
        "TextColor3": color("TextColor3", "phosphor"), "TextSize": ("float", 42),
        "Font": ("token", 3),
    }))
    screen.append(gui)
    return model("OldCRT", c, "MonitorBody")


def build_phone_cheap():
    c = rounded("Body", (1.1, 2, .28), (0, 1, 0), "wood_light", .12)
    c += [part("BackPlate", (.88, 1.7, .055), (0, 1, .16), "wood_dark"),
          part("ScreenBezel", (.88, .88, .04), (0, 1.32, -.16), "ink"),
          part("Screen", (.73, .69, .025), (0, 1.32, -.195), "sage"),
          part("Earpiece", (.35, .045, .015), (0, 1.85, -.15), "ink"),
          part("NavigationKey", (.22, .13, .04), (0, .79, -.17), "cream"),
          part("ScreenLine", (.47, .04, .012), (-.04, 1.4, -.215), "screen"),
          part("ScreenLine", (.32, .04, .012), (-.115, 1.27, -.215), "screen"),
          part("CornerWear", (.13, .035, .015), (.34, .16, -.15), "cream"),
          part("Camera", (.16, .16, .02), (0, 1.7, .2), "ink")]
    for row in range(3):
        for col in range(3):
            c.append(part("Key", (.21, .115, .035), (-.28+col*.28, .22+row*.18, -.16), "cream"))
    # Small rear foot makes the upright display visibly supported.
    c.append(part("RestFoot", (.65, .09, .5), (0, .045, .08), "wood_dark"))
    return model("PhoneCheap", c, "Body")


def build_phone_fast():
    c = rounded("Body", (1, 2.2, .16), (0, 1.1, 0), "navy", .1)
    c += rounded("Screen", (.88, 1.96, .025), (0, 1.13, -.095), "ink", .07)
    c += [part("BackPlate", (.82, 1.95, .035), (0, 1.1, .0975), "sage_dark", "Metal"),
          part("Notch", (.22, .045, .012), (0, 2.03, -.115), "metal"),
          part("ScreenHeader", (.66, .16, .015), (0, 1.79, -.115), "sage"),
          part("ScreenCard", (.66, .62, .015), (0, 1.3, -.115), "navy"),
          part("ScreenAccent", (.4, .045, .015), (-.08, 1.4, -.13), "phosphor"),
          part("HomeIndicator", (.28, .025, .015), (0, .24, -.115), "cream"),
          part("CameraBump", (.38, .53, .055), (-.22, 1.76, .14), "navy"),
          part("VolumeRocker", (.035, .35, .09), (-.515, 1.45, 0), "metal", "Metal"),
          part("RestFoot", (.6, .08, .45), (0, .04, .08), "navy")]
    for y in (1.63, 1.87):
        c.append(part("CameraLens", (.14, .14, .025), (-.22, y, .18), "ink", shape=0))
    return model("PhoneFast", c, "Body")


def write_model(path, root):
    roblox = ET.Element("roblox", {"version": "4"})
    roblox.append(root)
    xml = minidom.parseString(ET.tostring(roblox)).toprettyxml(indent="  ")
    with open(path, "w", encoding="utf-8", newline="\n") as output:
        output.write("\n".join(line for line in xml.splitlines() if line.strip()) + "\n")
    print("wrote", path)


def main():
    output = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "world")
    os.makedirs(output, exist_ok=True)
    for name, builder in (("Bedroom", build_bedroom), ("OldCRT", build_old_crt),
                          ("PhoneCheap", build_phone_cheap), ("PhoneFast", build_phone_fast)):
        write_model(os.path.join(output, name + ".rbxmx"), builder())


if __name__ == "__main__":
    main()
