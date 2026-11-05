"""Drive the isolated M2A1CityReview Studio instance via StudioMCP.

    python tools/review/studio_review.py luau FILE [Edit|Server|Client]
    python tools/review/studio_review.py code "return 1" [Edit]
    python tools/review/studio_review.py shot ID OUT.png "x,y,z" "x,y,z"
Refuses to act unless the only target studio is the review place.
"""
import base64
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "agent"))
from client import StudioClient  # noqa: E402

REVIEW = "M2A1CityReview"


def target(c):
    studios = json.loads(c.call_tool("list_roblox_studios", {})["content"][0]["text"])["studios"]
    hits = [s for s in studios if REVIEW in s["name"]]
    if len(hits) != 1:
        raise SystemExit(f"refusing: review studio not uniquely open: {studios}")
    return hits[0]["id"]


def main():
    c = StudioClient()
    sid = target(c)
    mode = sys.argv[1]
    if mode in ("luau", "code"):
        code = open(sys.argv[2], encoding="utf-8").read() if mode == "luau" else sys.argv[2]
        dm = sys.argv[3] if len(sys.argv) > 3 else "Edit"
        r = c.call_tool("execute_luau", {"studio_id": sid, "code": code, "datamodel_type": dm})
        print("\n".join(x.get("text", "") for x in r.get("content", [])))
    elif mode == "shot":
        try:
            from capture_review import foreground
            foreground(REVIEW)
        except Exception as e:  # capture still attempted; blank frames are rejected below
            print("foreground:", e)
        vec = lambda s: [float(v) for v in s.split(",")]
        r = c.call_tool("screen_capture", {"studio_id": sid, "capture_id": sys.argv[2],
                                          "camera_position": vec(sys.argv[4]),
                                          "look_at_position": vec(sys.argv[5])})
        for item in r.get("content", []):
            if item.get("type") == "image":
                os.makedirs(os.path.dirname(os.path.abspath(sys.argv[3])), exist_ok=True)
                raw = base64.b64decode(item["data"])
                from io import BytesIO
                from PIL import Image
                tones = len(set(Image.open(BytesIO(raw)).convert("L").resize((64, 32)).tobytes()))
                if tones < 20:
                    raise SystemExit(f"refusing blank viewport frame ({tones} tones): {sys.argv[3]}")
                open(sys.argv[3], "wb").write(raw)
                print("SAVED", sys.argv[3])
                return
        print(json.dumps(r)[:800])
    else:
        r = c.call_tool(mode, dict({"studio_id": sid}, **json.loads(sys.argv[2] if len(sys.argv) > 2 else "{}")))
        print(json.dumps(r)[:3000])


if __name__ == "__main__":
    main()
