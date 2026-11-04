import sys
sys.path.append('tools/agent')
import studio

code = """
local rep = game:GetService("ReplicatedStorage")
local tests = rep:FindFirstChild("Tests")
return {
    hasTestsInRep = tests ~= nil,
    repChildren = #rep:GetChildren(),
    testChildren = tests and #tests:GetChildren() or 0
}
"""
print(studio.luau(code, "Edit"))
