import sys
import os
import json
import base64
from client import StudioClient

_client = None

def get_client():
    global _client
    if _client is None:
        _client = StudioClient()
    return _client

def get_studio_id():
    c = get_client()
    res = c.call_tool("list_roblox_studios", {})
    text = res["content"][0]["text"]
    data = json.loads(text)
    if data.get("studios"):
        return data["studios"][0]["id"]
    return None

def call(name, args):
    c = get_client()
    if "studio_id" not in args:
        sid = get_studio_id()
        if sid:
            args["studio_id"] = sid
    res = c.call_tool(name, args)
    if res.get("content"):
        return res["content"][0]["text"]
    return str(res)

def luau(code, dm="Client"):
    return call("execute_luau", {
        "code": code,
        "datamodel_type": dm
    })

def screen_capture(capture_id, out_path, camera_position=None, look_at_position=None):
    c = get_client()
    sid = get_studio_id()
    args = {
        "studio_id": sid,
        "capture_id": capture_id
    }
    if camera_position is not None:
        args["camera_position"] = camera_position
    if look_at_position is not None:
        args["look_at_position"] = look_at_position
    res = c.call_tool("screen_capture", args)
    content = res.get("content", [])
    for item in content:
        if item.get("type") == "image":
            b64 = item.get("data")
            os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
            with open(out_path, "wb") as f:
                f.write(base64.b64decode(b64))
            return f"SAVED:{out_path}"
    return f"FAILED:{res}"

if __name__ == "__main__":
    print(call("get_studio_state", {}))
