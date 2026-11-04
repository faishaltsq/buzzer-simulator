import sys
import os
import glob
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio

def mount_tests():
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    specs_dir = os.path.join(project_root, "tests", "Specs")
    runner_file = os.path.join(project_root, "tests", "Runner.server.luau")
    
    spec_files = glob.glob(os.path.join(specs_dir, "*.luau"))
    print(f"Found {len(spec_files)} spec files to mount.")
    
    # 1. Clean up existing Specs / Runner if any
    cleanup_code = """
    local sss = game:GetService("ServerScriptService")
    local existingSpecs = sss:FindFirstChild("Specs")
    if existingSpecs then existingSpecs:Destroy() end
    local existingRunner = sss:FindFirstChild("Runner")
    if existingRunner then existingRunner:Destroy() end
    return true
    """
    studio.luau(cleanup_code, "Edit")
    
    # 2. Create Specs folder in ServerScriptService
    create_specs_folder = """
    local sss = game:GetService("ServerScriptService")
    local folder = Instance.new("Folder")
    folder.Name = "Specs"
    folder.Parent = sss
    return folder.Name
    """
    studio.luau(create_specs_folder, "Edit")
    
    # 3. Mount each spec module
    for sf in sorted(spec_files):
        name = os.path.basename(sf).replace(".luau", "")
        with open(sf, "r", encoding="utf-8") as f:
            src = f.read()
        
        mount_spec_code = f"""
        local HttpService = game:GetService("HttpService")
        local sss = game:GetService("ServerScriptService")
        local specs = sss:WaitForChild("Specs")
        local mod = Instance.new("ModuleScript")
        mod.Name = "{name}"
        mod.Source = HttpService:JSONDecode({json.dumps(json.dumps(src))})
        mod.Parent = specs
        return mod.Name
        """
        res = studio.luau(mount_spec_code, "Edit")
        print(f"  Mounted spec: {res}")
        
    # 4. Clone / alias ServerScriptService modules into ServerStorage for spec require compatibility
    storage_sync_code = """
    local sss = game:GetService("ServerScriptService")
    local ss = game:GetService("ServerStorage")
    local modules = {
        "ProfileStore", "ScoringCatalog", "MissionService", "FeedService",
        "EconomyService", "SessionService", "WorldService", "NetRouter", "BootstrapRuntime"
    }
    for _, name in ipairs(modules) do
        local inSss = sss:FindFirstChild(name)
        if inSss then
            local existing = ss:FindFirstChild(name)
            if existing then existing:Destroy() end
            local clone = inSss:Clone()
            clone.Parent = ss
        end
    end
    return true
    """
    studio.luau(storage_sync_code, "Edit")
    
    # 5. Disable Bootstrap script in ServerScriptService during tests to prevent collision
    disable_bootstrap_code = """
    local sss = game:GetService("ServerScriptService")
    local bs = sss:FindFirstChild("Bootstrap")
    if bs and bs:IsA("Script") then
        bs.Enabled = false
    end
    return true
    """
    studio.luau(disable_bootstrap_code, "Edit")

    # 6. Mount Runner script
    with open(runner_file, "r", encoding="utf-8") as f:
        runner_src = f.read()
        
    mount_runner_code = f"""
    local HttpService = game:GetService("HttpService")
    local sss = game:GetService("ServerScriptService")
    local scriptInst = Instance.new("Script")
    scriptInst.Name = "Runner"
    scriptInst.Source = HttpService:JSONDecode({json.dumps(json.dumps(runner_src))})
    scriptInst.Parent = sss
    return scriptInst.Name
    """
    res = studio.luau(mount_runner_code, "Edit")
    print(f"Mounted Runner: {res}")
    print("Mount complete!")

def unmount_tests():
    cleanup_code = """
    local sss = game:GetService("ServerScriptService")
    local ss = game:GetService("ServerStorage")
    local existingSpecs = sss:FindFirstChild("Specs")
    if existingSpecs then existingSpecs:Destroy() end
    local existingRunner = sss:FindFirstChild("Runner")
    if existingRunner then existingRunner:Destroy() end
    local bs = sss:FindFirstChild("Bootstrap")
    if bs and bs:IsA("Script") then
        bs.Enabled = true
    end
    local modules = {
        "ProfileStore", "ScoringCatalog", "MissionService", "FeedService",
        "EconomyService", "SessionService", "WorldService", "NetRouter", "BootstrapRuntime"
    }
    for _, name in ipairs(modules) do
        local inSs = ss:FindFirstChild(name)
        if inSs then inSs:Destroy() end
    end
    return true
    """
    res = studio.luau(cleanup_code, "Edit")
    print(f"Unmounted tests: {res}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "unmount":
        unmount_tests()
    else:
        mount_tests()
