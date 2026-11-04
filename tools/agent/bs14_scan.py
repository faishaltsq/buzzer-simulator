import sys
sys.path.append('tools/agent')
import studio

code = """
local out = {}
local function scan(root, name)
    local kids = root:GetChildren()
    out[#out+1] = name .. ": " .. #kids
    for _, c in ipairs(kids) do
        if #c:GetChildren() > 0 then
            scan(c, name .. "/" .. c.Name .. "(" .. c.ClassName .. ")")
        else
            out[#out+1] = "  " .. name .. "/" .. c.Name .. " [" .. c.ClassName .. "]"
        end
    end
end
scan(game.ReplicatedStorage, "RS")
out[#out+1] = "SSS: " .. #game.ServerScriptService:GetChildren()
out[#out+1] = "StarterPlayerScripts: " .. #game.StarterPlayer.StarterPlayerScripts:GetChildren()
return table.concat(out, "\\n")
"""
print(studio.luau(code, 'Edit'))
