import sys
import time

sys.path.append("tools/agent")
import studio  # noqa: E402

print(studio.call("start_stop_play", {"is_start": True}))
time.sleep(8)

code = """
local sss = game:GetService("ServerScriptService")
local spec = sss:FindFirstChild("Specs"):FindFirstChild("BS10Recovery.spec")
local ok, err = pcall(require, spec)
return tostring(ok) .. " |||| " .. tostring(err)
"""
print("REQUIRE:", studio.call("execute_luau", {"code": code, "datamodel_type": "Server"}))
time.sleep(2)
console = studio.call("get_console_output", {})
if isinstance(console, dict):
    console = console.get("content", [{}])[0].get("text", str(console))
print("CONSOLE-TAIL:")
print(str(console)[-3000:])
print(studio.call("start_stop_play", {"is_start": False}))
