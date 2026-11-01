import sys
import os
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio

code = """
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local dsOk, dsStore = pcall(function()
    return DataStoreService:GetDataStore("PlayerData")
end)

return HttpService:JSONEncode({
    dsOk = dsOk,
    storeType = typeof(dsStore),
    isInstance = (typeof(dsStore) == "Instance"),
    isFallback = not (typeof(dsStore) == "Instance"),
    universeId = game.GameId,
    placeId = game.PlaceId
})
"""

res = studio.luau(code, "Edit")
data = json.loads(res)
print("ProfileStore connectivity:")
print(f"  Fallback store: {data['isFallback']}")
print(f"  Store type:     {data['storeType']}")
print(f"  Universe ID:    {data['universeId']}")
print(f"  Place ID:       {data['placeId']}")
