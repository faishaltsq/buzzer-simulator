import sys, json
sys.path.append('tools/agent')
import studio

res = studio.call('list_roblox_studios', {})
print(res)
