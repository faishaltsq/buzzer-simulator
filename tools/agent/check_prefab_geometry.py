import re, subprocess

def strip_refs(text):
    text = re.sub(r'referent="RBX\d+"', 'REF', text)
    text = re.sub(r'<Ref name="[^"]*">RBX\d+</Ref>', '<Ref>REF</Ref>', text)
    return text

for f in ("Trainee1", "WorkerDesk1", "PCRumah", "Bedroom", "OldCRT", "PhoneCheap", "PhoneFast"):
    old = subprocess.run(["git", "show", f"HEAD:assets/world/{f}.rbxmx"], capture_output=True, text=True).stdout
    new = open(f"assets/world/{f}.rbxmx", encoding="utf-8").read()
    print(f, "geometry-identical:", strip_refs(old) == strip_refs(new))
