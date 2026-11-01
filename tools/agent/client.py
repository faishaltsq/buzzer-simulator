import subprocess
import json
import os
import sys

import glob
import shutil

def find_studiomcp_exe() -> str:
    env_path = os.environ.get("STUDIOMCP_PATH")
    if env_path and os.path.exists(env_path):
        return env_path

    which_path = shutil.which("StudioMCP") or shutil.which("StudioMCP.exe")
    if which_path and os.path.exists(which_path):
        return which_path

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        pattern = os.path.join(local_app_data, "Roblox", "Versions", "*", "StudioMCP.exe")
        candidates = glob.glob(pattern)
        if candidates:
            candidates.sort(key=os.path.getmtime, reverse=True)
            return candidates[0]

    raise FileNotFoundError(
        "StudioMCP executable not found. Set the STUDIOMCP_PATH environment variable."
    )

EXE = find_studiomcp_exe()

class StudioClient:
    def __init__(self):
        self.proc = subprocess.Popen(
            [EXE, "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0
        )
        self.req_id = 0
        self._init()

    def send(self, msg):
        s = json.dumps(msg) + "\n"
        self.proc.stdin.write(s)
        self.proc.stdin.flush()

    def recv(self):
        while True:
            line = self.proc.stdout.readline()
            if not line:
                err = self.proc.stderr.read()
                raise EOFError(f"Process ended: {err}")
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if "id" in data:
                    return data
            except json.JSONDecodeError:
                continue

    def _init(self):
        self.req_id += 1
        self.send({
            "jsonrpc": "2.0",
            "id": self.req_id,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "agent", "version": "1.0"}
            }
        })
        resp = self.recv()
        self.send({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        })

    def call_tool(self, name, args):
        self.req_id += 1
        self.send({
            "jsonrpc": "2.0",
            "id": self.req_id,
            "method": "tools/call",
            "params": {
                "name": name,
                "arguments": args
            }
        })
        resp = self.recv()
        if "error" in resp:
            raise RuntimeError(resp["error"])
        return resp.get("result", {})

    def close(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=2)
        except Exception:
            self.proc.kill()

if __name__ == "__main__":
    c = StudioClient()
    res = c.call_tool("list_roblox_studios", {})
    print(json.dumps(res))
    c.close()
