import json
import sys
import time

sys.path.append("tools/agent")
import studio  # noqa: E402

OPEN_PROMPT = """
local sss = game:GetService('ServerScriptService')
local pBridge = sss:WaitForChild('StudioPromptBridge')
local player = game:GetService('Players'):GetPlayers()[1]
local prompt = workspace:FindFirstChild('DashboardPrompt', true)
if prompt == nil then
  for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA('ProximityPrompt') then prompt = d break end
  end
end
if prompt == nil then return 'no-prompt' end
local okR, r = pcall(function() return pBridge:Invoke(prompt, player) end)
task.wait(2)
return 'invoked-' .. tostring(okR) .. ':' .. tostring(r)
"""

BRIDGE = """
local lp = game:GetService('Players').LocalPlayer
local bridge = lp:WaitForChild('PlayerGui'):WaitForChild('BuzzerOSDesktop'):WaitForChild('StudioClientBridge')
local HttpService = game:GetService('HttpService')
local function snap() return bridge:Invoke('GetState').snapshot end
"""


def cluau(c, sid, code):
    res = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Client", "code": code})
    if isinstance(res, dict) and res.get("isError"):
        raise RuntimeError(res["content"][0]["text"][:400])
    txt = res["content"][0]["text"]
    try:
        return json.loads(txt)
    except Exception:
        return txt


def slserver(c, sid, code):
    res = c.call_tool("execute_luau", {"studio_id": sid, "datamodel_type": "Server", "code": code})
    if isinstance(res, dict) and res.get("isError"):
        raise RuntimeError(res["content"][0]["text"][:400])
    return res["content"][0]["text"]


c = studio.get_client()
sid = studio.get_studio_id()

print("prompt:", slserver(c, sid, OPEN_PROMPT))

for tpl in ("weekend_vlog_text", "chill_spot_recs", "local_roundup", "snack_meme"):
    code = BRIDGE + f"""
local sent = bridge:Invoke('Action', {{ action = 'PublishOrganic', payload = {{ templateId = '{tpl}' }} }})
task.wait(0.3)
local st = bridge:Invoke('GetState')
return HttpService:JSONEncode({{ sent = sent, state = st.state or st.snapshot and st.snapshot.dashboardState, recent = st.snapshot and st.snapshot.recentMutationOutcomes }})
"""
    r = cluau(c, sid, code)
    print(tpl, "->", json.dumps(r)[:500])
    time.sleep(3)
