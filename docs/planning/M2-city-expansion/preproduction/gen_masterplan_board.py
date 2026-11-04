"""Draw the baseline masterplan and explicitly labelled proposals from parent tables.

One pixel-space scene feeds PNG, SVG and native Excalidraw. Requires Pillow.
No game assets or runtime settings are modified. Run from any working directory.
"""
import json
import math
import re
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "02-WORLD-STRUCTURE.md"
SCALE = 5
WIDTH, HEIGHT = 2380, 2240
BG, INK, RED, AMBER, GREEN = "#FBF8F1", "#202A2D", "#AD3F35", "#99704B", "#506C56"


def font(size):
    for name in ("C:/Windows/Fonts/arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    raise RuntimeError("Install Arial or DejaVu Sans for measurable board labels")


def point(x, z):
    return 100 + (x + 136) * SCALE, 160 + (z + 192) * SCALE


def load_contract():
    text = SOURCE.read_text(encoding="utf-8")
    zones, anchors = [], []
    for line in text.splitlines():
        cells = [s.strip() for s in line.strip().strip("|").split("|")]
        if len(cells) == 4 and re.match(r"Z[0-7] ", cells[0]):
            spans = [re.findall(r"[+-]?\d+", c) for c in cells[1:3]]
            if all(len(s) == 2 for s in spans):
                zones.append((cells[0], *[int(n) for s in spans for n in s]))
        if len(cells) == 3 and cells[0].startswith("`City_"):
            coords = re.fullmatch(r"`\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)`", cells[1])
            if coords:
                anchors.append((cells[0].strip("`"), *map(float, coords.groups())))
    if len(zones) != 8 or len(anchors) != 17:
        raise ValueError(f"Parent table changed: got {len(zones)} zones, {len(anchors)} anchors")
    return zones, anchors


def scene():
    zones, anchors = load_contract()
    shapes = []

    def rect(x, y, w, h, fill, stroke=INK, sw=1):
        shapes.append(dict(type="rectangle", x=x, y=y, w=w, h=h, fill=fill, stroke=stroke, sw=sw))

    def text(x, y, value, size=17, color=INK):
        w = math.ceil(font(size).getlength(value)) + 3
        shapes.append(dict(type="text", x=x, y=y, w=w, h=math.ceil(size*1.3),
                           text=value, size=size, fill="transparent", stroke=color, sw=1))

    def line(a, b, color=INK, sw=2):
        shapes.append(dict(type="line", x=a[0], y=a[1], w=b[0]-a[0], h=b[1]-a[1],
                           fill="transparent", stroke=color, sw=sw))

    def box(x0, z0, x1, z1, fill, stroke=INK):
        x, y = point(x0, z0)
        rect(x,y,(x1-x0)*SCALE,(z1-z0)*SCALE,fill,stroke)

    def dashed_box(x0,z0,x1,z1):
        corners = [point(x0,z0),point(x1,z0),point(x1,z1),point(x0,z1)]
        for a,b in zip(corners,corners[1:]+corners[:1]):
            distance=math.dist(a,b)
            for t in range(0,math.ceil(distance),18):
                u,v=t/distance,min(t+10,distance)/distance
                line(tuple(a[i]+(b[i]-a[i])*u for i in (0,1)),
                     tuple(a[i]+(b[i]-a[i])*v for i in (0,1)),RED,2)

    def circle(x,z,r,fill,stroke=INK):
        px,py=point(x-r,z-r)
        shapes.append(dict(type="ellipse",x=px,y=py,w=r*10,h=r*10,fill=fill,stroke=stroke,sw=2))

    text(60,28,"BUZZER SIMULATOR | M2-A0 MASTERPLAN",30)
    text(60,74,"Baseline from parent coordinate tables. Dashed red = proposal, NOT approved.",20)
    text(60,106,"Scale: 5 pixels per stud. North = -Z, east = +X. Drawing only, not a Studio capture.",17)
    # Baseline backdrop and proposed alternative are both visible, never conflated.
    box(16,-192,160,-112,"#344451")
    dashed_box(-120,-192,120,-112)
    text(1650,165,"BACKDROP / WINDOW AUDIT",22)
    text(1650,205,"Solid navy: baseline X=16..160",17)
    text(1650,233,"Dashed red: proposed X=-120..120",17,RED)
    text(1650,261,"Both use Z=-192..-112; not two assets.",17)
    for x in (-65.333333,-3.333333):
        line(point(7,3),point(x,-152),GREEN,2)
    circle(-34.333333,-152,1,"#ECBA6F")
    text(1650,305,"Green rays: CameraFocus aperture",17,GREEN)
    text(1650,333,"at Z=-152: X=-65.33..-3.33",17,GREEN)
    text(1650,361,"Candidate tower centre: X=-34.33",17,RED)
    text(1650,389,"2D reference only; inspect actual camera.",17)

    fills=["#E9DEC7","#DBD3BE","#EEE8DD","#ECDBC3","#D8C2A8","#DCE5D9","#F6ECD8","#D1D6DA"]
    for i,(name,x0,x1,z0,z1) in enumerate(zones):
        box(x0,z0,x1,z1,fills[i])
        # Labels outside narrow zones are owned by the legend, not squeezed into the map.
    box(-13.35,-13.35,13.35,13.35,"#DBD3BE")
    box(-8.5,13.35,-3.5,16,"#99704B")
    box(-16,16,16,64,"#6E7773")
    circle(0,112,40,"#E9DEC7")
    circle(0,112,8,"#96B2B1")
    box(-6,65,6,71,"#84977E")  # illustrative baseline kiosk
    for x0,z0,x1,z1 in [(56,72,80,96),(56,120,80,144),(-80,72,-56,96)]:
        # Inset massing retains space for path/zone lines and marker inspection.
        box(x0+1,z0+1,x1-1,z1-1,"#B48B60")
    dashed_box(56,96,80,120)  # future cosmetics lot, not a shipped shop
    # Outline proposal is separate from the baseline Z6 extent and marker.
    dashed_box(4,65,16,71)
    paths=[ [(-6,20),(-6,40),(-4,56),(-14,64),(-16,80),(0,88)],
            [(0,88),(-18,100),(-18,124),(0,140),(0,158)],
            [(0,88),(28,88),(54,84)],[(0,88),(-30,88),(-54,84)],
            [(-18,124),(-60,128),(-104,128)] ]
    for path in paths:
        for a,b in zip(path,path[1:]): line(point(*a),point(*b),AMBER,4)
    # One marker per explicitly positioned parent part; IDs go in a right-side register.
    for i,(name,x,y,z) in enumerate(anchors,1):
        circle(x,z,0.65,"#AD3F35")
        # Co-located zone/prompt identities retain separate register rows.
    suggested=[(14,62),(-14,72),(44,106),(-44,106),(-84,140),(14,136)]
    for x,z in suggested: circle(x,z,0.5,"#506C56")
    # Zone labels in the map's empty margins, leaders avoid crowded board/door markers.
    label_spots=[(-38,-20),(-42,28),(-54,150),(85,72),(-112,78),(-134,154),(-30,58),(16,165)]
    for (name,*_),pos in zip(zones,label_spots):
        x,y=point(*pos); text(x,y,name.split()[0],16)
    for i,(name,x0,x1,z0,z1) in enumerate(zones):
        text(1650,470+i*47,f"{name.split()[0]}  {name[3:]}",19)
        text(1650,497+i*47,f"X {x0}..{x1}, Z {z0}..{z1} | {x1-x0} x {z1-z0}",15)
    text(1650,880,"PARENT ANCHORS (XYZ, STUDS)",20)
    for i,(name,x,y,z) in enumerate(anchors):
        text(1650,917+i*52,name,16)
        text(1650,939+i*52,f"({x:g}, {y:g}, {z:g})",15)
    text(60,2060,"Amber: illustrative outdoor path (no passage through closed room wall).",18,AMBER)
    text(60,2090,"Red dots: baseline anchors. Green dots: six suggested signpost locations, not frozen.",18)
    text(60,2120,"Z6 shift X=4..16 exceeds current X=12 extent; decision required. Shops shown only as later-phase massing.",18,RED)
    line((60,2175),(260,2175),INK,3)
    for x in (60,160,260): line((x,2168),(x,2182))
    text(60,2188,"0                         20                        40 studs",15)
    text(550,2188,"No approval, FPS, streaming or runtime behaviour inferred from this drawing.",16)
    return shapes


def render(shapes):
    image=Image.new("RGB",(WIDTH,HEIGHT),BG)
    draw=ImageDraw.Draw(image)
    svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
         f'<rect width="100%" height="100%" fill="{BG}"/>']
    elements=[]
    for i,p in enumerate(shapes):
        x,y,w,h=p['x'],p['y'],p['w'],p['h']
        color,fill=p['stroke'],p['fill']
        if p['type']=='text':
            draw.text((x,y),p['text'],font=font(p['size']),fill=color,anchor='lt')
            svg.append(f'<text x="{x}" y="{y}" dominant-baseline="text-before-edge" font-family="Arial, sans-serif" font-size="{p["size"]}" fill="{color}">{escape(p["text"])}</text>')
        elif p['type']=='line':
            draw.line((x,y,x+w,y+h),fill=color,width=p['sw'])
            svg.append(f'<line x1="{x}" y1="{y}" x2="{x+w}" y2="{y+h}" stroke="{color}" stroke-width="{p["sw"]}"/>')
        else:
            shape=draw.rectangle if p['type']=='rectangle' else draw.ellipse
            shape((x,y,x+w,y+h),fill=fill,outline=color,width=p['sw'])
            if p['type']=='rectangle':
                svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{color}"/>')
            else:
                svg.append(f'<ellipse cx="{x+w/2}" cy="{y+h/2}" rx="{w/2}" ry="{h/2}" fill="{fill}" stroke="{color}" stroke-width="{p["sw"]}"/>')
        e=dict(id=f'city-{i:04}',type=p['type'],x=x,y=y,width=abs(w),height=abs(h),angle=0,
               strokeColor=color,backgroundColor=fill,fillStyle='solid',strokeWidth=p['sw'],
               strokeStyle='solid',roughness=0,opacity=100,groupIds=[],frameId=None,
               roundness=None,seed=i+1,version=1,versionNonce=i+1,isDeleted=False,
               boundElements=None,updated=0,link=None,locked=False)
        if p['type']=='text':
            e.update(text=p['text'],originalText=p['text'],fontSize=p['size'],fontFamily=2,
                     textAlign='left',verticalAlign='top',containerId=None,lineHeight=1.3,autoResize=True)
        if p['type']=='line':
            e.update(points=[[0,0],[w,h]],startBinding=None,endBinding=None,
                     startArrowhead=None,endArrowhead=None,lastCommittedPoint=None)
        elements.append(e)
    svg.append('</svg>')
    (HERE/'CITY-MASTERPLAN-preview.svg').write_text('\n'.join(svg)+'\n',encoding='utf-8')
    image.save(HERE/'CITY-MASTERPLAN-preview.png',optimize=True)
    doc=dict(type='excalidraw',version=2,source='M2-A0 local planning generator',elements=elements,
             appState=dict(viewBackgroundColor=BG,gridSize=None,zoom=dict(value=0.5)),files={})
    (HERE/'CITY-MASTERPLAN.excalidraw').write_text(json.dumps(doc,indent=1)+'\n',encoding='utf-8')
    print(f'Rendered {len(shapes)} primitives: {WIDTH}x{HEIGHT}; 8 zones, 17 positioned anchors')


if __name__=='__main__':
    render(scene())
