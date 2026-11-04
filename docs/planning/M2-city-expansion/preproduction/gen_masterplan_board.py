"""M2-A0 city masterplan board generator.

One scene model -> three renderers: editable Excalidraw, SVG preview, PNG preview.
Coordinates come from docs/planning/M2-city-expansion/02-WORLD-STRUCTURE.md and are
never re-derived here; the board is a drawing of that table, not a second source.

Run from the repo root:
    python docs/planning/M2-city-expansion/preproduction/gen_masterplan_board.py

Stdlib only, plus Pillow for the PNG. No network, no external assets.
"""

import json
import math
import os

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# --- world -> board transform ------------------------------------------------
# World: +X east, +Z south, grade Y=0. Board: +x right, +y down (north at top).
SCALE = 6.0
PAD_X = 96
PAD_Y = 96
PAD_Y_BOTTOM = 120
WORLD_X_MIN, WORLD_X_MAX = -136.0, 80.0
# The board is to scale, so it must include the non-walkable north backdrop (z -192..-112)
# and the ground apron that keeps it from reading as a floating billboard.
WORLD_Z_MIN, WORLD_Z_MAX = -200.0, 176.0

BOARD_W = (WORLD_X_MAX - WORLD_X_MIN) * SCALE + PAD_X * 2
BOARD_H = (WORLD_Z_MAX - WORLD_Z_MIN) * SCALE + PAD_Y + PAD_Y_BOTTOM


def bx(x):
    return PAD_X + (x - WORLD_X_MIN) * SCALE


def by(z):
    return PAD_Y + (z - WORLD_Z_MIN) * SCALE


# --- palette (docs/design/02-COLOR-AND-MATERIALS.md, 3D tokens) --------------
INK = "#202A2D"
NAVY = "#344451"
PLASTER = "#DBD3BE"
CREAM = "#E9DEC7"
WOOD_DARK = "#654A37"
WOOD = "#99704B"
SAGE = "#84977E"
SAGE_DARK = "#506C56"
AMBER = "#ECBA6F"
CLAY = "#A67358"
METAL = "#6E7773"

ZONES = [
    ("Z0", "Z0  Home & Threshold", -24, -24, 24, 16, CREAM, "48 x 40"),
    ("Z1", "Z1  Gang Melati", -24, 16, 24, 64, "#D9D3C5", "48 x 48"),
    ("Z2", "Z2  Alun-Alun", -56, 64, 56, 160, "#E5DDCA", "112 x 96"),
    ("Z3", "Z3  East shop row", 56, 72, 80, 144, "#EBDCC4", "24 x 72"),
    ("Z4", "Z4  West shop row", -80, 72, -56, 96, "#E8DBC7", "24 x 24"),
    ("Z5", "Z5  Event Plaza", -136, 104, -80, 164, "#DEE4D3", "56 x 60"),
    ("Z6", "Z6  Boards kiosk", -12, 64, 12, 72, "#F6ECD8", "24 x 8"),
    ("Z7", "Z7  Future Gate", -8, 160, 8, 176, "#D6DADD", "16 x 16"),
]

# name, x0, z0, x1, z1, fill, label, label side
BUILDINGS = [
    ("House shell 24x24", -12.85, -12.85, 12.85, 12.85, PLASTER, "", ""),
    ("Stoop", -8.5, 12.85, -3.5, 16.0, CREAM, "stoop", "right"),
    ("ElectroMart", 56, 72, 80, 96, "#E7C79A", "ElectroMart", "right"),
    ("Gaya Depan", 56, 96, 80, 120, "#E8C4B4", "Cosmetics (M2-C)", "right"),
    ("Warung Serba Ada", 56, 120, 80, 144, "#C9D2DC", "Utility (M2-B)", "right"),
    ("Rumah Rapi", -80, 72, -56, 96, WOOD, "Rumah Rapi", "left"),
    ("Boards kiosk", -6, 65, 6, 71, CREAM, "Boards", "left"),
    ("Stage", -120, 146, -96, 156, SAGE_DARK, "stage", "left"),
    ("Gate piers + shutter", -8, 160, 8, 176, METAL, "Future gate", "left"),
    ("Transit shelter", 21, 93, 27, 99, NAVY, "transit", "right"),
]

# Route: (x, z) polyline in studs, drawn as the primary player path.
ROUTE = [
    (0, 6), (-6, 11.6), (-6, 20), (-6, 40), (-4, 56), (0, 68),
    (0, 88), (0, 104),
]
ROUTE_GATE = [(0, 104), (0, 130), (0, 158)]
ROUTE_EAST = [(0, 88), (28, 88), (52, 84), (58, 84)]
ROUTE_WEST = [(0, 88), (-28, 84), (-52, 84), (-58, 84)]
ROUTE_EVENT = [(0, 104), (-30, 112), (-62, 122), (-80, 128), (-104, 128)]

# Anchor table: id, name, x, z, kind. kind: spawn | prompt | zone | sign | transit
ANCHORS = [
    ("A1", "City_Spawn", -6, 20, "spawn"),
    ("A2", "City_HomeDoor", -6, 16, "door"),
    ("A3", "City_DoorPromptInterior", -6, 8, "door"),
    ("A4", "City_Zone_Street", 0, 40, "zone"),
    ("A5", "City_Zone_TownCenter", 0, 112, "zone"),
    ("A6", "City_Zone_ShopEast", 68, 108, "zone"),
    ("A7", "City_Zone_ShopWest", -68, 84, "zone"),
    ("A8", "City_Zone_EventPlaza", -108, 134, "zone"),
    ("A9", "City_Zone_FutureGate", 0, 168, "zone"),
    ("A10", "City_Prompt_Boards", 0, 68, "prompt"),
    ("A11", "City_Prompt_ElectroMart", 68, 84, "prompt"),
    ("A12", "City_Prompt_RumahRapi", -68, 84, "prompt"),
    ("A13", "City_Prompt_Cosmetics", 68, 108, "prompt"),
    ("A14", "City_Prompt_Utility", 68, 132, "prompt"),
    ("A15", "City_Prompt_EventPlaza", -108, 110, "prompt"),
    ("A16", "City_Prompt_FutureGate", 0, 168, "prompt"),
    ("A17", "City_TransitStop", 24, 96, "transit"),
    ("A18", "City_Signpost_01..06", 0, 0, "sign"),
]

SIGNPOSTS = [(14, 62), (-14, 72), (44, 106), (-44, 106), (-84, 140), (14, 136)]

# Sightlines: (x0, z0, x1, z1, dashed, label)
SIGHTLINES = [
    (-6, 16, 0, 68, False, "S1 stoop -> boards  57 studs"),
    (-6, 16, 0, 112, False, "S2 stoop -> fountain  100 studs"),
    (7, 3, -65.3, -152, True, "S3 window aperture, west edge"),
    (7, 3, -3.3, -152, True, "S3 window aperture, east edge"),
    (0, 112, 56, 84, True, "S5 plaza -> ElectroMart front"),
    (0, 112, -56, 84, True, "S6 plaza -> Rumah Rapi front"),
    (0, 112, -80, 128, True, "S7 plaza -> event connector"),
]


def rects():
    out = []
    for zid, label, x0, z0, x1, z1, fill, size in ZONES:
        out.append(("zone", zid, label, x0, z0, x1, z1, fill, size))
    out.append(("zone", "BD", "Backdrop (proposed x -120..+120)", -120, -192, 120, -112, INK, "240 x 80"))
    return out


def scene():
    """Return an ordered primitive list consumed by every renderer."""
    prims = []

    # 0. horizon apron: ground continues north so the skyline cannot read as a
    #    floating billboard. Non-walkable, 1 part in CityBackdrop.
    prims.append({"t": "rect", "x0": -150, "z0": -200, "x1": 130, "z1": -24,
                  "fill": "#D6D8CC", "stroke": None, "opacity": 0.35, "sw": 0})
    prims.append({"t": "text", "x": -148, "z": -60,
                  "s": "rear yard + horizon apron (non-walkable, ground plane only)",
                  "color": "#6B7268", "size": 10, "bold": False})
    prims.append({"t": "text", "x": -148, "z": -46,
                  "s": "no prop, no prompt, no collision - it exists so the skyline has a floor",
                  "color": "#7C837A", "size": 9, "bold": False})

    # 1. backdrop band + horizon note
    prims.append({"t": "rect", "x0": -120, "z0": -192, "x1": 120, "z1": -112,
                  "fill": INK, "stroke": INK, "opacity": 0.92, "sw": 2})
    prims.append({"t": "text", "x": -118, "z": -186,
                  "s": "NORTH SKYLINE BACKDROP  (non-walkable, Persistent, <= 9 parts)",
                  "color": CREAM, "size": 15, "bold": True})
    prims.append({"t": "text", "x": -118, "z": -176,
                  "s": "4 silhouette slabs + Agency Tower + 2 antenna tips + haze plane + ground apron",
                  "color": "#B9C4BD", "size": 10, "bold": False})

    # 2. zone bands
    for zid, label, x0, z0, x1, z1, fill, size in ZONES:
        prims.append({"t": "rect", "x0": x0, "z0": z0, "x1": x1, "z1": z1,
                      "fill": fill, "stroke": INK, "opacity": 0.55, "sw": 1.5})
        prims.append({"t": "text", "x": x0 + 2, "z": z0 + 3, "s": label,
                      "color": INK, "size": 12, "bold": True})
        prims.append({"t": "text", "x": x0 + 2, "z": z0 + 10, "s": size + " studs",
                      "color": "#5A606A", "size": 9, "bold": False})

    # 3. plaza disc + fountain ring
    prims.append({"t": "ellipse", "cx": 0, "cz": 112, "r": 40,
                  "fill": "#E9E1CE", "stroke": WOOD, "opacity": 0.5, "sw": 2})
    prims.append({"t": "ellipse", "cx": 0, "cz": 112, "r": 8,
                  "fill": "#96B2B1", "stroke": NAVY, "opacity": 0.9, "sw": 2})

    # 4. buildings
    for name, x0, z0, x1, z1, fill, label, side in BUILDINGS:
        prims.append({"t": "rect", "x0": x0, "z0": z0, "x1": x1, "z1": z1,
                      "fill": fill, "stroke": INK, "opacity": 0.95, "sw": 2})
        if label:
            if side == "left":
                prims.append({"t": "text", "x": x0 - 2, "z": (z0 + z1) / 2 - 4, "s": label,
                              "color": INK, "size": 10, "bold": True, "align": "right"})
            else:
                prims.append({"t": "text", "x": x1 + 2, "z": (z0 + z1) / 2 - 4, "s": label,
                              "color": INK, "size": 10, "bold": True})

    # 5. road surface inside the gang
    prims.append({"t": "rect", "x0": -16, "z0": 16, "x1": 16, "z1": 64,
                  "fill": "#9AA0A0", "stroke": None, "opacity": 0.45, "sw": 0})
    prims.append({"t": "text", "x": 1, "z": 44, "s": "32-stud lane", "color": "#2F3A3C",
                  "size": 9, "bold": False, "align": "left"})

    # 6. route
    for path, style in ((ROUTE, "solid"), (ROUTE_GATE, "solid"), (ROUTE_EAST, "solid"),
                        (ROUTE_WEST, "solid"), (ROUTE_EVENT, "solid")):
        prims.append({"t": "poly", "pts": path, "color": AMBER, "opacity": 1.0,
                      "sw": 4, "style": style})

    # 7. sightlines
    for x0, z0, x1, z1, dashed, label in SIGHTLINES:
        prims.append({"t": "line", "x0": x0, "z0": z0, "x1": x1, "z1": z1,
                      "color": SAGE_DARK, "opacity": 0.9, "sw": 1.5,
                      "style": "dashed" if dashed else "solid", "arrow": True})
    prims.append({"t": "text", "x": -6, "z": 30, "s": "S1 57 studs / 3.5 s",
                  "color": SAGE_DARK, "size": 9, "bold": False})

    # 7b. two plan-level findings drawn where they matter.
    #     (a) the approved backdrop (x 16..160) covers 0.0 deg of the window
    #         aperture seen from CameraFocus; the tower only lands in frame at
    #         x = -34 on the z = -152 plane.
    prims.append({"t": "dot", "x": -34.3, "z": -152, "r": 2.6, "fill": AMBER})
    prims.append({"t": "text", "x": -31, "z": -150, "s": "Agency Tower  (proposed x = -34)",
                  "color": AMBER, "size": 9, "bold": True})
    #     (b) a 12-stud kiosk centred on x = 0 occludes 100% of the fountain from
    #         the stoop; shifting it +10 studs east clears the S2 line.
    prims.append({"t": "rect", "x0": 4, "z0": 65, "x1": 16, "z1": 71,
                  "fill": "#F6ECD8", "stroke": "#B4553C", "opacity": 0.55, "sw": 2})
    prims.append({"t": "text", "x": 17, "z": 66,
                  "s": "proposed kiosk shift +10 studs east (clears S2)",
                  "color": "#B4553C", "size": 9, "bold": True})
    prims.append({"t": "text", "x": -134, "z": 96,
                  "s": "S3/S4 audit: approved backdrop covers 0.0 deg of the window",
                  "color": SAGE_DARK, "size": 9, "bold": True})
    prims.append({"t": "text", "x": -134, "z": 101,
                  "s": "aperture from CameraFocus (7, 5.5, 3) - see WORLD-LAYOUT 4.2",
                  "color": SAGE_DARK, "size": 9, "bold": False})

    # 8. anchors. Zone roots are rings, prompts are dots: three anchors share an
    #    XZ with a zone root (different Y in world), so the ring/dot pairing keeps
    #    both readable instead of stacking two labels on one point.
    for aid, name, x, z, kind in ANCHORS:
        if kind == "sign":
            continue
        color = {"spawn": AMBER, "door": WOOD_DARK, "zone": NAVY,
                 "prompt": "#B4553C", "transit": METAL}[kind]
        if kind == "zone":
            prims.append({"t": "ring", "x": x, "z": z, "r": 3.4, "stroke": color, "sw": 1.8})
            prims.append({"t": "text", "x": x + 4.4, "z": z + 1, "s": aid,
                          "color": color, "size": 8, "bold": True})
        else:
            prims.append({"t": "dot", "x": x, "z": z, "r": 1.6, "fill": color})
            prims.append({"t": "text", "x": x + 2.4, "z": z + 4, "s": aid,
                          "color": color, "size": 8, "bold": True})
    for x, z in SIGNPOSTS:
        prims.append({"t": "dot", "x": x, "z": z, "r": 1.3, "fill": "#B4553C"})
    prims.append({"t": "text", "x": -134, "z": 168, "s": "A18 signposts x6",
                  "color": "#B4553C", "size": 8, "bold": True})

    # 9. fixed frame
    prims.append({"t": "text", "x": 0, "z": -30, "s": "-Z  NORTH  (skyline / window direction)",
                  "color": INK, "size": 12, "bold": True, "align": "center"})
    prims.append({"t": "text", "x": 0, "z": 182, "s": "+Z  SOUTH  (future district)",
                  "color": INK, "size": 12, "bold": True, "align": "center"})
    prims.append({"t": "text", "x": -140, "z": -30, "s": "WEST  -X",
                  "color": INK, "size": 11, "bold": True})
    prims.append({"t": "text", "x": 84, "z": -30, "s": "EAST  +X",
                  "color": INK, "size": 11, "bold": True, "align": "right"})

    # 10. title block + scale bar (drawn last so it sits on top)
    prims.append({"t": "text", "x": -136, "z": 179,
                  "s": "BUZZER SIMULATOR  -  M2-A0 CITY MASTERPLAN",
                  "color": INK, "size": 18, "bold": True})
    prims.append({"t": "text", "x": -136, "z": 184,
                  "s": "to scale, 1:1 studs | 216 x 200 walkable | 8-stud module, 16-stud major lines | "
                       "coordinates from 02-WORLD-STRUCTURE.md, not re-derived here",
                  "color": "#5A606A", "size": 10, "bold": False})
    for i in range(5):
        prims.append({"t": "line", "x0": -136 + i * 20, "z0": 188, "x1": -136 + i * 20, "z1": 190,
                      "color": INK, "opacity": 1.0, "sw": 1.5, "style": "solid"})
    prims.append({"t": "line", "x0": -136, "z0": 189, "x1": -56, "z1": 189,
                  "color": INK, "opacity": 1.0, "sw": 2, "style": "solid"})
    prims.append({"t": "text", "x": -136, "z": 192, "s": "0", "color": INK, "size": 9, "bold": False})
    prims.append({"t": "text", "x": -56, "z": 192, "s": "80 studs", "color": INK,
                  "size": 9, "bold": False, "align": "right"})
    return prims


# --- SVG ---------------------------------------------------------------------
def svg_escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def render_svg(prims, path):
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{BOARD_W:.0f}" '
        f'height="{BOARD_H:.0f}" viewBox="0 0 {BOARD_W:.0f} {BOARD_H:.0f}">',
        f'<rect width="100%" height="100%" fill="#FBF8F1"/>',
        '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
        'markerHeight="6" orient="auto-start-reverse">'
        f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{SAGE_DARK}"/></marker></defs>',
    ]
    for p in prims:
        if p["t"] == "rect":
            x0, z0 = bx(p["x0"]), by(p["z0"])
            w, h = (p["x1"] - p["x0"]) * SCALE, (p["z1"] - p["z0"]) * SCALE
            stroke = p["stroke"] or "none"
            parts.append(f'<rect x="{x0:.1f}" y="{z0:.1f}" width="{w:.1f}" height="{h:.1f}" '
                         f'fill="{p["fill"]}" fill-opacity="{p["opacity"]}" stroke="{stroke}" '
                         f'stroke-width="{p["sw"]}"/>')
        elif p["t"] == "ellipse":
            parts.append(f'<circle cx="{bx(p["cx"]):.1f}" cy="{by(p["cz"]):.1f}" '
                         f'r="{p["r"] * SCALE:.1f}" fill="{p["fill"]}" '
                         f'fill-opacity="{p["opacity"]}" stroke="{p["stroke"]}" '
                         f'stroke-width="{p["sw"]}"/>')
        elif p["t"] == "line":
            dash = ' stroke-dasharray="10 7"' if p.get("style") == "dashed" else ""
            marker = ' marker-end="url(#a)"' if p.get("arrow") else ""
            parts.append(f'<line x1="{bx(p["x0"]):.1f}" y1="{by(p["z0"]):.1f}" '
                         f'x2="{bx(p["x1"]):.1f}" y2="{by(p["z1"]):.1f}" '
                         f'stroke="{p["color"]}" stroke-opacity="{p["opacity"]}" '
                         f'stroke-width="{p["sw"]}"{dash}{marker}/>')
        elif p["t"] == "poly":
            pts = " ".join(f"{bx(x):.1f},{by(z):.1f}" for x, z in p["pts"])
            parts.append(f'<polyline points="{pts}" fill="none" stroke="{p["color"]}" '
                         f'stroke-opacity="{p["opacity"]}" stroke-width="{p["sw"]}" '
                         f'stroke-linecap="round" stroke-linejoin="round"/>')
        elif p["t"] == "dot":
            parts.append(f'<circle cx="{bx(p["x"]):.1f}" cy="{by(p["z"]):.1f}" '
                         f'r="{max(3.0, p["r"] * 1.6):.1f}" fill="{p["fill"]}"/>')
        elif p["t"] == "ring":
            parts.append(f'<circle cx="{bx(p["x"]):.1f}" cy="{by(p["z"]):.1f}" '
                         f'r="{p["r"] * 1.6:.1f}" fill="none" stroke="{p["stroke"]}" '
                         f'stroke-width="{p["sw"]}"/>')
        elif p["t"] == "text":
            anchor = {"center": "middle", "right": "end"}.get(p.get("align"), "start")
            weight = "700" if p.get("bold") else "400"
            parts.append(f'<text x="{bx(p["x"]):.1f}" y="{by(p["z"]):.1f}" '
                         f'font-family="Segoe UI, Arial, sans-serif" font-size="{p["size"]}" '
                         f'font-weight="{weight}" fill="{p["color"]}" '
                         f'text-anchor="{anchor}">{svg_escape(p["s"])}</text>')
    parts.append("</svg>")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(parts) + "\n")


# --- PNG (Pillow) ------------------------------------------------------------
def render_png(prims, path, factor=1.6):
    from PIL import Image, ImageDraw, ImageFont

    font_path = None
    for candidate in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"):
        if os.path.exists(candidate):
            font_path = candidate
            break
    cache = {}

    def font(size, bold):
        key = (size, bold)
        if key not in cache:
            px = max(8, int(round(size * factor)))
            if font_path:
                cache[key] = ImageFont.truetype(font_path, px)
            else:
                cache[key] = ImageFont.load_default()
        return cache[key]

    W = int(BOARD_W * factor)
    H = int(BOARD_H * factor)
    img = Image.new("RGB", (W, H), "#FBF8F1")
    draw = ImageDraw.Draw(img, "RGBA")

    def f(x, y):
        return (x * factor, y * factor)

    def mix(color, opacity, bg=(251, 248, 241)):
        c = color.lstrip("#")
        rgb = tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
        return tuple(int(bg[i] + (rgb[i] - bg[i]) * opacity) for i in range(3))

    for p in prims:
        if p["t"] == "rect":
            x0, z0 = bx(p["x0"]) * factor, by(p["z0"]) * factor
            x1, z1 = bx(p["x1"]) * factor, by(p["z1"]) * factor
            draw.rectangle([x0, z0, x1, z1], fill=mix(p["fill"], p["opacity"]),
                           outline=mix(p["stroke"], 1.0) if p["stroke"] else None,
                           width=max(1, int(round(p["sw"] * factor * 0.8))))
        elif p["t"] == "ellipse":
            cx, cy = bx(p["cx"]) * factor, by(p["cz"]) * factor
            r = p["r"] * SCALE * factor
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=mix(p["fill"], p["opacity"]),
                         outline=mix(p["stroke"], 1.0), width=max(1, int(2 * factor * 0.8)))
        elif p["t"] == "line":
            draw.line([f(bx(p["x0"]), by(p["z0"])), f(bx(p["x1"]), by(p["z1"]))],
                      fill=mix(p["color"], p["opacity"]), width=max(1, int(p["sw"] * factor)))
            if p.get("arrow"):
                ax, ay = bx(p["x1"]) * factor, by(p["z1"]) * factor
                px, py = bx(p["x0"]) * factor, by(p["z0"]) * factor
                ang = math.atan2(ay - py, ax - px)
                for delta in (0.42, -0.42):
                    draw.line([(ax, ay),
                               (ax - 9 * factor * math.cos(ang - delta),
                                ay - 9 * factor * math.sin(ang - delta))],
                              fill=mix(p["color"], p["opacity"]), width=max(1, int(1.6 * factor)))
        elif p["t"] == "poly":
            draw.line([f(bx(x), by(z)) for x, z in p["pts"]], fill=mix(p["color"], p["opacity"]),
                      width=max(1, int(p["sw"] * factor)), joint="curve")
        elif p["t"] == "dot":
            cx, cy = bx(p["x"]) * factor, by(p["z"]) * factor
            r = max(3.0, p["r"] * 1.6) * factor
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=mix(p["fill"], 1.0))
        elif p["t"] == "ring":
            cx, cy = bx(p["x"]) * factor, by(p["z"]) * factor
            r = p["r"] * 1.6 * factor
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=mix(p["stroke"], 1.0),
                         width=max(1, int(p["sw"] * factor)))
        elif p["t"] == "text":
            draw.text(f(bx(p["x"]), by(p["z"])), p["s"], font=font(p["size"], p.get("bold")),
                      fill=mix(p["color"], 1.0), anchor={
                          "center": "ma", "right": "ra"}.get(p.get("align"), "la"))

    # legend, bottom-right of the canvas
    lx, ly = BOARD_W - 470, 40
    draw.rectangle([lx - 12, ly - 12, BOARD_W - 24, ly + 176], fill=(255, 255, 255),
                   outline=(210, 205, 195))
    rows = [
        ("#B4553C", "prompt anchor (A10-A16)"),
        (AMBER, "spawn / route"),
        (NAVY, "zone root anchor"),
        (SAGE_DARK, "sightline"),
        (WOOD_DARK, "home door"),
    ]
    for i, (color, label) in enumerate(rows):
        yy = ly + i * 22
        draw.ellipse([lx, yy, lx + 11, yy + 11], fill=color)
        draw.text((lx + 20, yy - 1), label, font=font(10, False), fill=(40, 44, 50))
    draw.text((lx, ly + 118), "world 216 x 200 studs @ 6 px/stud",
              font=font(10, True), fill=(40, 44, 50))
    draw.text((lx, ly + 136), "M2-A0 masterplan - not a build",
              font=font(10, False), fill=(90, 96, 106))

    img.save(path, "PNG", optimize=True)
    return W, H


# --- Excalidraw --------------------------------------------------------------
def render_excalidraw(prims, path):
    elements = []
    counter = [0]

    def nid():
        counter[0] += 1
        return "el%04d" % counter[0]

    def base(kind, x, y, w, h, stroke, fill, width, dashed=False, opacity=100):
        eid = nid()
        return {
            "id": eid, "type": kind, "x": round(x, 2), "y": round(y, 2),
            "width": round(w, 2), "height": round(h, 2), "angle": 0,
            "strokeColor": stroke, "backgroundColor": fill, "fillStyle": "solid",
            "strokeWidth": width, "strokeStyle": "dashed" if dashed else "solid",
            "roughness": 0, "opacity": opacity, "groupIds": [], "frameId": None,
            "roundness": {"type": 3}, "seed": 1000 + counter[0] * 37,
            "version": 1, "versionNonce": 1000 + counter[0] * 11,
            "isDeleted": False, "boundElements": [], "updated": 0, "link": None,
            "locked": False,
        }

    for p in prims:
        if p["t"] == "rect":
            e = base("rectangle", bx(p["x0"]), by(p["z0"]),
                     (p["x1"] - p["x0"]) * SCALE, (p["z1"] - p["z0"]) * SCALE,
                     p["stroke"] or "transparent", p["fill"],
                     max(1, int(round(p["sw"]))), opacity=int(p["opacity"] * 100))
            elements.append(e)
        elif p["t"] == "ellipse":
            e = base("ellipse", bx(p["cx"]) - p["r"] * SCALE, by(p["cz"]) - p["r"] * SCALE,
                     p["r"] * SCALE * 2, p["r"] * SCALE * 2, p["stroke"], p["fill"],
                     max(1, int(round(p["sw"]))), opacity=int(p["opacity"] * 100))
            elements.append(e)
        elif p["t"] in ("line", "poly"):
            pts = ([(p["x0"], p["z0"]), (p["x1"], p["z1"])] if p["t"] == "line"
                   else p["pts"])
            e = base("line", bx(pts[0][0]), by(pts[0][1]), 0, 0, p["color"], "transparent",
                     max(1, int(round(p["sw"]))), p.get("style") == "dashed")
            xs = [bx(x) for x, _ in pts]
            ys = [by(z) for _, z in pts]
            e["x"] = round(min(xs), 2)
            e["y"] = round(min(ys), 2)
            e["width"] = round(max(xs) - min(xs), 2)
            e["height"] = round(max(ys) - min(ys), 2)
            e["points"] = [[round(bx(x) - e["x"], 2), round(by(z) - e["y"], 2)]
                           for x, z in pts]
            if p["t"] == "line" and p.get("arrow") and "arrowhead" not in p:
                e["type"] = "arrow"
                e["endArrowhead"] = "arrow"
            elements.append(e)
        elif p["t"] == "dot":
            r = max(3.0, p["r"] * 1.6)
            elements.append(base("ellipse", bx(p["x"]) - r, by(p["z"]) - r, r * 2, r * 2,
                                 p["fill"], p["fill"], 1))
        elif p["t"] == "ring":
            r = p["r"] * 1.6
            elements.append(base("ellipse", bx(p["x"]) - r, by(p["z"]) - r, r * 2, r * 2,
                                 p["stroke"], "transparent", 1))
        elif p["t"] == "text":
            px = bx(p["x"])
            py = by(p["z"]) - p["size"]
            e = base("text", px, py, len(p["s"]) * p["size"] * 0.55, p["size"] * 1.25,
                     p["color"], "transparent", 1)
            e["text"] = p["s"]
            e["fontSize"] = p["size"] + 2
            e["fontFamily"] = 2
            e["textAlign"] = {"center": "center", "right": "right"}.get(p.get("align"), "left")
            e["verticalAlign"] = "top"
            e["containerId"] = None
            e["originalText"] = p["s"]
            e["lineHeight"] = 1.25
            e["roundness"] = None
            elements.append(e)

    doc = {
        "type": "excalidraw",
        "version": 2,
        "source": "https://github.com/faishaltsq/buzzer-simulator",
        "elements": elements,
        "appState": {
            "gridSize": 16,
            "viewBackgroundColor": "#FBF8F1",
            "scrollX": 0,
            "scrollY": 0,
            "zoom": {"value": 0.55},
        },
        "files": {},
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, indent=1, ensure_ascii=False)
        handle.write("\n")
    return len(elements)


def main():
    prims = scene()
    svg_path = os.path.join(OUT_DIR, "CITY-MASTERPLAN-preview.svg")
    png_path = os.path.join(OUT_DIR, "CITY-MASTERPLAN-preview.png")
    exc_path = os.path.join(OUT_DIR, "CITY-MASTERPLAN.excalidraw")

    render_svg(prims, svg_path)
    w, h = render_png(prims, png_path)
    count = render_excalidraw(prims, exc_path)

    print("board canvas   : %.0f x %.0f px" % (BOARD_W, BOARD_H))
    print("svg            : %s" % svg_path)
    print("png            : %s (%d x %d)" % (png_path, w, h))
    print("excalidraw     : %s (%d elements)" % (exc_path, count))
    print("zones          : %d  (walkable %.0f x %.0f studs, board spans %.0f x %.0f)"
          % (len(ZONES), 216, 200, WORLD_X_MAX - WORLD_X_MIN, WORLD_Z_MAX - WORLD_Z_MIN))


if __name__ == "__main__":
    main()
