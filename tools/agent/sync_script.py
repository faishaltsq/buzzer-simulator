import sys
import os
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio

def sync_file(file_path, datamodel_path):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    code = f"""
    local HttpService = game:GetService("HttpService")
    local target = {datamodel_path}
    if target then
        target.Source = HttpService:JSONDecode({json.dumps(json.dumps(content))})
        return "SYNCED: " .. target:GetFullName()
    else
        return "NOT_FOUND: {datamodel_path}"
    end
    """
    res = studio.call("execute_luau", {"code": code, "datamodel_type": "Edit"})
    print(res)

if __name__ == "__main__":
    if len(sys.argv) >= 3:
        sync_file(sys.argv[1], sys.argv[2])
    else:
        print("Usage: python sync_script.py <file_path> <datamodel_path>")
