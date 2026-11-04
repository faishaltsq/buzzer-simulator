import json
import sys
import time

sys.path.append("tools/agent")
import studio  # noqa: E402

BR = """
local lp = game:GetService('Players').LocalPlayer
local bridge = lp:WaitForChild('PlayerGui'):WaitForChild('BuzzerOSDesktop', 5):WaitForChild('StudioClientBridge', 5)
local HttpService = game:GetService('HttpService')
local function snap() return bridge:Invoke('GetState').snapshot end
return HttpService:JSONEncode({ b = snap().balance, t = snap().tier, w = #(snap().workers or {}), save = snap().saveStatus })
"""

c = studio.get_client()
sid = studio.get_studio_id()


def cluau(code):
    r = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Client", "code": code})
    return json.loads(r["content"][0]["text"])


try:
    print("current-session:", cluau(BR))
except Exception as e:
    print("current-session error:", str(e)[:200])

print("restarting Play Solo...")
c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
time.sleep(6)
c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
time.sleep(12)
try:
    print("after-restart:", cluau(BR))
except Exception as e:
    print("after-restart error:", str(e)[:300])
