"""Small reproducible checks for the planning package, not a Roblox runtime suite."""
import hashlib
import importlib.util
import itertools
import json
import math
import re
import tempfile
from pathlib import Path
from xml.etree import ElementTree

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('board', HERE / 'gen_masterplan_board.py')
board = importlib.util.module_from_spec(spec)
spec.loader.exec_module(board)
checks = []


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    checks.append(name)
    print('PASS', name)


zones, anchors = board.load_contract()
check('baseline zones read from parent', len(zones) == 8)
check('17 positioned parts / 22 invisible including signposts',
      len(anchors) == 17 and len(anchors) - 1 + 6 == 22)
check('eight distinct zone IDs', len({z[0][:2] for z in zones}) == 8)
check('unique positioned identities', len({a[0] for a in anchors}) == 17)
check('full walkable envelope 216 x 200',
      max(z[2] for z in zones)-min(z[1] for z in zones) == 216
      and max(z[4] for z in zones)-min(z[3] for z in zones) == 200)
check('phase arithmetic 448 / 510 / 958 / 242',
      sum([90,80,140,40,30,8,60]) == 448
      and sum([80,120,100,160,50]) == 510
      and 448+510 == 958 and 1200-958 == 242)
visible = [7 + (x-7)*155/15 for x in (0,6)]
check('window reference slice independently derived',
      math.isclose(visible[0],-65.3333333333) and math.isclose(visible[1],-3.3333333333))
check('baseline backdrop misses reference plane window slice', visible[1] < 16)
check('route lower bound reproduces parent estimate',
      round(math.hypot(6,56.4)/16,2) == 3.54
      and round(math.hypot(6,100.4)/16,2) == 6.29)
scene = board.scene()
check('all scene coordinates finite', all(math.isfinite(p[k]) for p in scene for k in ('x','y','w','h')))
check('every primitive fits export canvas', all(
    min(p['x'],p['x']+p['w']) >= 0 and min(p['y'],p['y']+p['h']) >= 0
    and max(p['x'],p['x']+p['w']) <= board.WIDTH
    and max(p['y'],p['y']+p['h']) <= board.HEIGHT for p in scene))
texts = [p for p in scene if p['type'] == 'text']
def overlaps(a,b):
    return (max(a['x'],b['x']) < min(a['x']+a['w'],b['x']+b['w'])
            and max(a['y'],b['y']) < min(a['y']+a['h'],b['y']+b['h']))
collisions = [(a['text'],b['text']) for a,b in itertools.combinations(texts,2) if overlaps(a,b)]
check(f'no label bounding-box overlap ({len(texts)} labels)', not collisions)
outputs = ['CITY-MASTERPLAN-preview.png','CITY-MASTERPLAN-preview.svg','CITY-MASTERPLAN.excalidraw']
# Generate twice in an isolated scratch directory; compare both against published local outputs.
with tempfile.TemporaryDirectory(prefix='m2-plan-') as tmp:
    original = board.HERE
    board.HERE = Path(tmp)
    board.render(scene)
    first = {n: (board.HERE/n).read_bytes() for n in outputs}
    board.render(scene)
    check('three exports deterministic', all(first[n] == (board.HERE/n).read_bytes() for n in outputs))
    board.HERE = original
    check('published previews match current scene', all(first[n] == (HERE/n).read_bytes() for n in outputs))
svg = ElementTree.parse(HERE/outputs[1])
check('SVG XML parses', svg.getroot().tag.endswith('svg'))
from PIL import Image
with Image.open(HERE/outputs[0]) as im:
    im.load()
    check('PNG decodes at declared canvas', im.size == (board.WIDTH,board.HEIGHT))
doc = json.loads((HERE/outputs[2]).read_text(encoding='utf-8'))
elements = doc['elements']
check('native Excalidraw structure', doc['type'] == 'excalidraw' and doc['version'] == 2)
check('export parity: one element per primitive', len(elements) == len(scene))
check('unique native element IDs', len({e['id'] for e in elements}) == len(elements))
check('native line points begin at origin', all(e['points'][0] == [0,0] for e in elements if e['type'] == 'line'))
check('font sizes identical across scene and native export', all(
    e['fontSize'] == p['size'] for e,p in zip(elements,scene) if p['type'] == 'text'))
missing=[]
for p in HERE.glob('*.md'):
    text=p.read_text(encoding='utf-8')
    for link in re.findall(r'\]\(([^)]+)\)',text):
        if not link.startswith(('https:', 'http:', '#')) and not (p.parent/link.split('#')[0]).exists():
            missing.append((p.name,link))
check('local document links resolve', not missing)
print(f'\n{len(checks)} checks passed; not Studio, human art approval, or device performance proof.')
for name in outputs:
    print(hashlib.sha256((HERE/name).read_bytes()).hexdigest(), name)
