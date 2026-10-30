import os
import xml.etree.ElementTree as ET
from xml.dom import minidom

# ---------------------------------------------------------------- helpers

_ref_counter = 0

def next_ref():
    global _ref_counter
    _ref_counter += 1
    return f"RBX{_ref_counter}"

BRICK_COLORS = {
    "Cool grey": 1011,
    "Reddish brown": 217,
    "Institutional white": 24,
    "Bright yellow": 226,
    "Bright blue": 23,
    "Bright green": 37,
    "Bright orange": 106,
    "Bright violet": 1026,
    "Bright red": 21,
    "Medium stone grey": 194,
    "Lime green": 119,
    "Pastel blue": 11,
    "Really black": 1003,
    "Terracotta": 1012,
    "Cyan": 1028,
}

MATERIALS = {
    "SmoothPlastic": 256,
    "WoodPlanks": 512,
    "Wood": 512,
    "Slate": 800,
    "Metal": 1088,
    "Grass": 1280,
    "Fabric": 1344,
    "Neon": 288,
    "Glass": 1568,
}

SHAPES = {
    "Block": 1,
    "Ball": 0,
    "Cylinder": 2,
}

def item(cls, name, props=None, children=None):
    it = ET.Element("Item", {"class": cls, "referent": next_ref()})
    props_el = ET.SubElement(it, "Properties")
    if name is not None:
        str_el = ET.SubElement(props_el, "string", {"name": "Name"})
        str_el.text = name
    for k, v in (props or {}).items():
        if k == "Name":
            continue
        if isinstance(v, tuple) and len(v) == 2:
            tag, val = v
            el = ET.SubElement(props_el, tag, {"name": k})
            el.text = str(val)
        elif isinstance(v, ET.Element):
            props_el.append(v)
        else:
            str_el = ET.SubElement(props_el, "string", {"name": k})
            str_el.text = str(v)
    for c in (children or []):
        it.append(c)
    return it

def make_cframe(cf_str):
    nums = [float(x.strip()) for x in cf_str.split(",")]
    if len(nums) == 3:
        nums.extend([1, 0, 0, 0, 1, 0, 0, 0, 1])
    cf_el = ET.Element("CoordinateFrame", {"name": "CFrame"})
    keys = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]
    for k, num in zip(keys, nums):
        el = ET.SubElement(cf_el, k)
        el.text = str(int(num) if num.is_integer() else num)
    return cf_el

def make_vector3(name, size):
    v_el = ET.Element("Vector3", {"name": name})
    keys = ["X", "Y", "Z"]
    for k, num in zip(keys, size):
        el = ET.SubElement(v_el, k)
        el.text = str(int(num) if isinstance(num, (int, float)) and float(num).is_integer() else num)
    return v_el

def part(name, size, cframe, color, material="SmoothPlastic",
         transparency=0, shape="Block", anchored=True, can_collide=True,
         props=None):
    p = {
        "Name": name,
        "size": make_vector3("size", size),
        "CFrame": make_cframe(cframe),
        "BrickColor": ("int", BRICK_COLORS.get(color, 194)),
        "Material": ("token", MATERIALS.get(material, 256)),
        "shape": ("token", SHAPES.get(shape, 1)),
        "Anchored": ("bool", "true" if anchored else "false"),
        "CanCollide": ("bool", "true" if can_collide else "false"),
        "Transparency": ("float", str(transparency)),
    }
    if props:
        p.update(props)
    return item("Part", name, p)

def anchor(name, position, size=(1, 1, 1), color="Bright green",
           transparency=0.5, can_collide=False):
    cf = f"{position[0]}, {position[1]}, {position[2]}, 1, 0, 0, 0, 1, 0, 0, 0, 1"
    return part(name, size, cf, color, material="Neon",
                transparency=transparency, can_collide=can_collide)

def folder(name, children):
    return item("Folder", name, children=children)

def model(name, children, primary_part_name=None):
    it = item("Model", name, children=children)
    if primary_part_name is not None:
        props_el = it.find("Properties")
        for c in children:
            if c.tag == "Item":
                c_props = c.find("Properties")
                if c_props is not None:
                    name_el = c_props.find("string[@name='Name']")
                    if name_el is not None and name_el.text == primary_part_name:
                        ref_el = ET.SubElement(props_el, "Ref", {"name": "PrimaryPart"})
                        ref_el.text = c.attrib.get("referent", "null")
                        break
    return it

def write_model(path, root):
    roblox = ET.Element("roblox", {
        "xmlns:xmime": "http://www.w3.org/2005/05/xmlmime",
        "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
        "version": "4",
    })
    roblox.append(root)
    xml = ET.tostring(roblox, encoding="unicode")
    pretty = minidom.parseString(xml).toprettyxml(indent="  ")
    lines = [l for l in pretty.split("\n") if l.strip()]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
        f.write("\n")
    print("wrote", path)


def build_bedroom():
    """A cosy rented bedroom: floor, walls, door, desk, CRT slot, phone pad,
    two future worker stations, a camera focus and a light group."""

    children = []

    # ---- floor: 24 x 24 studs, centred on the origin
    children.append(part(
        "Floor", (24, 1, 24),
        "0, -0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cool grey", material="Slate",
    ))

    # ---- walls: four sides, 10 studs tall
    wall_h = 10
    wall_t = 1
    span = 24
    walls = [
        ("WallNorth", (span, wall_h, wall_t), "0, %d, -%d" % (wall_h / 2, span / 2)),
        ("WallSouth", (span, wall_h, wall_t), "0, %d, %d" % (wall_h / 2, span / 2)),
        ("WallEast", (wall_t, wall_h, span), "%d, %d, 0" % (span / 2, wall_h / 2)),
        ("WallWest", (wall_t, wall_h, span), "-%d, %d, 0" % (span / 2, wall_h / 2)),
    ]
    for name, size, pos in walls:
        cf = "%s, 1, 0, 0, 0, 1, 0, 0, 0, 1" % pos
        children.append(part(name, size, cf, "Cool grey", material="Slate"))

    # ---- ceiling (keeps the room feeling enclosed, cheap on overdraw)
    children.append(part(
        "Ceiling", (span, 1, span),
        "0, %d, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1" % wall_h,
        "Cool grey", material="Slate", can_collide=False,
    ))

    # ---- door on the south wall
    children.append(part(
        "Door", (4, 7, 0.4),
        "-6, 3.5, %d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (span / 2),
        "Reddish brown", material="WoodPlanks",
    ))
    children.append(part(
        "DoorFrame", (4.6, 7.6, 0.3),
        "-6, 3.8, %d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (span / 2 - 0.1),
        "Reddish brown", material="WoodPlanks", can_collide=False,
    ))

    # ---- baseboard trim for warmth
    for name, size, pos in [
        ("TrimNorth", (span, 0.8, 0.3), "0, 0.4, -%d" % (span / 2 - 0.3)),
        ("TrimSouth", (span, 0.8, 0.3), "0, 0.4, %d" % (span / 2 - 0.3)),
        ("TrimEast", (0.3, 0.8, span), "%d, 0.4, 0" % (span / 2 - 0.3)),
        ("TrimWest", (0.3, 0.8, span), "-%d, 0.4, 0" % (span / 2 - 0.3)),
    ]:
        cf = "%s, 1, 0, 0, 0, 1, 0, 0, 0, 1" % pos
        children.append(part(name, size, cf, "Reddish brown",
                             material="WoodPlanks", can_collide=False))

    # ---- player desk against the east wall, facing the room
    desk_z = -4
    children.append(part(
        "DeskTop", (7, 0.3, 3),
        "7, 3.2, %d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % desk_z,
        "Reddish brown", material="WoodPlanks",
    ))
    for lx, lz in [(4.2, -2.6), (9.8, -2.6), (4.2, -5.4), (9.8, -5.4)]:
        children.append(part(
            "DeskLeg", (0.4, 3, 0.4),
            "%s, 1.5, %s, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (lx, lz),
            "Reddish brown", material="WoodPlanks",
        ))
    # desk drawer unit for silhouette interest
    children.append(part(
        "DeskDrawers", (2.2, 2.2, 2.6),
        "9.4, 1.9, %d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % desk_z,
        "Reddish brown", material="WoodPlanks",
    ))

    # ---- a simple bed for the "rented bedroom" read
    children.append(part(
        "BedFrame", (5, 1.2, 7),
        "-7, 0.6, 5, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Reddish brown", material="WoodPlanks",
    ))
    children.append(part(
        "Mattress", (4.6, 0.8, 6.6),
        "-7, 1.6, 5, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cool grey", material="Fabric",
    ))
    children.append(part(
        "Pillow", (3.4, 0.5, 1.4),
        "-7, 2.2, 2.2, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Institutional white", material="Fabric",
    ))
    children.append(part(
        "Blanket", (4.7, 0.3, 4.2),
        "-7, 2.15, 6.2, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Bright blue", material="Fabric", can_collide=False,
    ))

    # ---- window on the north wall for warm light
    children.append(part(
        "Window", (5, 4, 0.3),
        "4, 5, -%d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (span / 2 - 0.2),
        "Pastel blue", material="Glass", transparency=0.55,
        can_collide=False,
    ))

    # ---- poster / shelf dressing
    children.append(part(
        "Shelf", (4, 0.2, 1),
        "-4, 5.5, -%d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (span / 2 - 0.6),
        "Reddish brown", material="WoodPlanks", can_collide=False,
    ))

    # ---- plant for life
    children.append(part(
        "PlantPot", (1.2, 1.2, 1.2),
        "10, 0.6, 8, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Reddish brown", material="Terracotta",
    ))
    children.append(part(
        "PlantLeaves", (1.6, 2.4, 1.6),
        "10, 2.2, 8, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Bright green", material="Grass", shape="Ball",
        can_collide=False,
    ))

    # ---- anchors (stable, server-owned references)
    prompt_anchor = part(
        "DashboardPromptAnchor", (1.5, 1.5, 0.4),
        "7.4, 3.6, -2.4, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Bright violet", material="Neon", transparency=0.5, can_collide=False,
    )
    prompt = item("ProximityPrompt", "DashboardPrompt", {
        "ActionText": ("string", "Open BuzzerOS"),
        "ObjectText": ("string", "BuzzerOS Terminal"),
        "MaxActivationDistance": ("float", "10"),
        "HoldDuration": ("float", "0"),
        "RequiresLineOfSight": ("bool", "false"),
    })
    prompt_anchor.append(prompt)

    anchors = [
        anchor("Spawn", (0, 0.6, 6), size=(4, 1, 4), color="Bright green"),
        anchor("PlayerDesk", (7, 3.35, desk_z), size=(7, 0.3, 3), color="Bright green"),
        prompt_anchor,
        anchor("TerminalSlot", (7.4, 3.35, -4.0), size=(3.0, 0.2, 2.6),
               color="Bright orange"),
        anchor("PhoneSlot", (4.6, 3.35, -3.8), size=(1.4, 0.2, 1.4),
               color="Bright yellow"),
        anchor("WorkerDeskSlot1", (-8, 3.2, -8), size=(4, 0.4, 2.4),
               color="Medium stone grey"),
        anchor("WorkerSeat1", (-8, 1.6, -6.2), size=(2, 2, 2),
               color="Medium stone grey"),
        anchor("WorkerDeskSlot2", (-8, 3.2, -2), size=(4, 0.4, 2.4),
               color="Medium stone grey"),
        anchor("WorkerSeat2", (-8, 1.6, -0.2), size=(2, 2, 2),
               color="Medium stone grey"),
        anchor("CameraFocus", (7, 5.5, desk_z + 7), size=(1, 1, 1),
               color="Cyan", transparency=0.8),
    ]
    children.extend(anchors)

    # ---- LightGroup: a warm ceiling light plus a desk lamp
    light_children = [
        part("CeilingLight", (6, 0.4, 6),
             "0, %d, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (wall_h - 0.4),
             "Institutional white", material="Neon", can_collide=False,
             props={"Name": "CeilingLight"}),
        part("DeskLamp", (0.8, 0.3, 0.8),
             "10.6, 3.4, %d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % desk_z,
             "Bright yellow", material="Neon", can_collide=False),
        part("LampStem", (0.15, 1.4, 0.15),
             "10.6, 4.1, %d, 1, 0, 0, 0, 1, 0, 0, 0, 1" % desk_z,
             "Really black", material="Metal", can_collide=False),
    ]
    children.append(folder("LightGroup", light_children))

    return model("Bedroom", children)


# ---------------------------------------------------------------- OldCRT

def build_old_crt():
    """A battered old CRT: beige tower, curved glass, chunky bezel.

    Dashboard access ONLY. It is never a productive device and carries no
    yield, multiplier or currency source.
    """
    children = []

    # monitor body
    children.append(part(
        "MonitorBody", (3.2, 2.8, 2.6),
        "0, 1.4, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Institutional white", material="SmoothPlastic",
    ))
    # chunky bezel
    children.append(part(
        "Bezel", (2.7, 2.3, 0.3),
        "0, 1.45, -1.3, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cool grey", material="SmoothPlastic",
    ))
    # screen (dim green, clearly obsolete)
    children.append(part(
        "Screen", (2.1, 1.7, 0.15),
        "0, 1.45, -1.42, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Lime green", material="Neon", transparency=0.25,
        can_collide=False,
    ))
    # back hump for the curved-tube silhouette
    children.append(part(
        "TubeHump", (2.0, 1.6, 1.4),
        "0, 1.5, 1.1, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Institutional white", material="SmoothPlastic",
    ))
    # stand
    children.append(part(
        "StandNeck", (0.6, 0.7, 0.6),
        "0, 0.35, 0.2, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cool grey", material="SmoothPlastic",
    ))
    children.append(part(
        "StandBase", (2.2, 0.2, 1.6),
        "0, 0.1, 0.2, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cool grey", material="SmoothPlastic",
    ))
    # worn details: a scuffed corner and a sticker
    children.append(part(
        "Scuff", (0.5, 0.5, 0.1),
        "1.2, 2.5, -1.35, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Reddish brown", material="CorrodedMetal", can_collide=False,
    ))
    children.append(part(
        "Sticker", (0.7, 0.7, 0.08),
        "-0.9, 0.5, -1.36, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Bright red", material="SmoothPlastic", can_collide=False,
    ))

    # a small dashboard label so the player can read the terminal's purpose
    gui_size = ET.Element("UDim2", {"name": "Size"})
    for k, v in [("XS", 4), ("XO", 0), ("YS", 1.4), ("YO", 0)]:
        ET.SubElement(gui_size, k).text = str(v)
    gui_offset = ET.Element("Vector3", {"name": "StudsOffset"})
    for k, v in [("X", 0), ("Y", 2.4), ("Z", 0)]:
        ET.SubElement(gui_offset, k).text = str(v)
    label = item("BillboardGui", "DashboardLabel", {
        "Size": gui_size,
        "StudsOffset": gui_offset,
        "AlwaysOnTop": ("bool", "true"),
    })
    txt_size = ET.Element("UDim2", {"name": "Size"})
    for k, v in [("XS", 1), ("XO", 0), ("YS", 1), ("YO", 0)]:
        ET.SubElement(txt_size, k).text = str(v)
    txt = item("TextLabel", "Label", {
        "Size": txt_size,
        "BackgroundTransparency": ("float", "1"),
        "Text": ("string", "BUZZEROS TERMINAL"),
        "TextColor3": ("Color3uint8", "4294967295"),
        "TextScaled": ("bool", "true"),
    })
    label.append(txt)
    children.append(label)

    return model("OldCRT", children, primary_part_name="MonitorBody")


# ---------------------------------------------------------------- PhoneCheap

def build_phone_cheap():
    """A battered cheap phone: chunky, worn, small dim screen."""
    children = []
    # body
    children.append(part(
        "Body", (1.1, 2.0, 0.22),
        "0, 1.0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Bright yellow", material="SmoothPlastic",
    ))
    # worn back plate
    children.append(part(
        "BackPlate", (1.0, 1.9, 0.1),
        "0, 1.0, 0.14, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cool grey", material="CorrodedMetal", can_collide=False,
    ))
    # small dim screen
    children.append(part(
        "Screen", (0.85, 1.35, 0.06),
        "0, 1.05, -0.13, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Pastel blue-green", material="Neon", transparency=0.35,
        can_collide=False,
    ))
    # cracked corner
    children.append(part(
        "Crack", (0.3, 0.3, 0.04),
        "0.28, 1.55, -0.16, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Institutional white", material="Glass", can_collide=False,
    ))
    # physical keypad (cheap phones have buttons)
    for i in range(3):
        for j in range(4):
            children.append(part(
                "Key", (0.16, 0.1, 0.05),
                "%s, %s, -0.15, 1, 0, 0, 0, 1, 0, 0, 0, 1" % (
                    -0.3 + j * 0.2, 0.35 + i * 0.18),
                "Cool grey", material="SmoothPlastic", can_collide=False,
            ))
    # rubber bumper
    children.append(part(
        "Bumper", (1.16, 0.2, 0.26),
        "0, 0.12, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Really black", material="SmoothPlastic",
    ))
    return model("PhoneCheap", children, primary_part_name="Body")


# ---------------------------------------------------------------- PhoneFast

def build_phone_fast():
    """A fast phone: slimmer, larger brighter screen, distinct silhouette."""
    children = []
    # slimmer body, different colour
    children.append(part(
        "Body", (1.0, 2.2, 0.16),
        "0, 1.1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Bright blue", material="SmoothPlastic",
    ))
    # metallic back
    children.append(part(
        "BackPlate", (0.92, 2.1, 0.06),
        "0, 1.1, 0.11, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Medium stone grey", material="Metal", can_collide=False,
    ))
    # large bright screen
    children.append(part(
        "Screen", (0.9, 1.9, 0.04),
        "0, 1.15, -0.11, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cyan", material="Neon", transparency=0.1,
        can_collide=False,
    ))
    # notch
    children.append(part(
        "Notch", (0.28, 0.08, 0.05),
        "0, 2.02, -0.13, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Really black", material="SmoothPlastic", can_collide=False,
    ))
    # camera bump (the fast phone has a visible camera)
    children.append(part(
        "CameraBump", (0.34, 0.34, 0.1),
        "-0.26, 1.82, 0.15, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Really black", material="SmoothPlastic",
    ))
    children.append(part(
        "CameraLens", (0.16, 0.16, 0.06),
        "-0.26, 1.82, 0.2, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Cyan", material="Glass", can_collide=False,
    ))
    # slim edge accent
    children.append(part(
        "EdgeAccent", (1.02, 0.08, 0.18),
        "0, 0.06, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
        "Institutional white", material="Metal", can_collide=False,
    ))
    return model("PhoneFast", children, primary_part_name="Body")


# ---------------------------------------------------------------- main

def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "assets", "world")
    out_dir = os.path.normpath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    write_model(os.path.join(out_dir, "Bedroom.rbxmx"), build_bedroom())
    write_model(os.path.join(out_dir, "OldCRT.rbxmx"), build_old_crt())
    write_model(os.path.join(out_dir, "PhoneCheap.rbxmx"), build_phone_cheap())
    write_model(os.path.join(out_dir, "PhoneFast.rbxmx"), build_phone_fast())


if __name__ == "__main__":
    main()
