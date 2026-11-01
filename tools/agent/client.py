import subprocess
import json
import os
import sys

EXE = r"C:/Users/cubeb/AppData/Local/Roblox/Versions/version-7062aec9dbe74b14/StudioMCP.exe"

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
