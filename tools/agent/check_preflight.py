import sys
import os
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio

EXPECTED_UNIVERSE_ID = 10774181892
EXPECTED_PLACE_ID = 100558697471228

preflight_code = f"""
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local universeId = game.GameId
local placeId = game.PlaceId

local universeMatch = (universeId == {EXPECTED_UNIVERSE_ID})
local placeMatch = (placeId == {EXPECTED_PLACE_ID})

-- Fail closed if targeting an unintended experience
if not universeMatch or not placeMatch then
    return HttpService:JSONEncode({{
        ok = false,
        code = "EXPERIENCE_MISMATCH",
        universeId = universeId,
        placeId = placeId,
        expectedUniverse = {EXPECTED_UNIVERSE_ID},
        expectedPlace = {EXPECTED_PLACE_ID},
        detail = "Target experience does not match expected development universe!"
    }})
end

local dsOk, dsStore = pcall(function()
    return DataStoreService:GetDataStore("PlayerData")
end)

local isInstance = dsOk and (typeof(dsStore) == "Instance")
local isFallback = not isInstance

return HttpService:JSONEncode({{
    ok = universeMatch and placeMatch and isInstance,
    universeId = universeId,
    placeId = placeId,
    dsOk = dsOk,
    storeType = typeof(dsStore),
    isFallback = isFallback,
    ready = true
}})
"""

def run_preflight():
    res_str = studio.luau(preflight_code, "Edit")
    try:
        data = json.loads(res_str)
    except Exception as e:
        print(f"Preflight parse error: {e}, raw: {res_str}")
        sys.exit(1)
        
    print("Pre-flight check results:")
    print(f"  Universe ID: {data.get('universeId')} (Expected: {EXPECTED_UNIVERSE_ID})")
    print(f"  Place ID:    {data.get('placeId')} (Expected: {EXPECTED_PLACE_ID})")
    print(f"  DataStore:   {'ONLINE' if data.get('dsOk') and not data.get('isFallback') else 'OFFLINE/FALLBACK'}")
    print(f"  Status:      {'PASS' if data.get('ok') else 'FAIL'}")
    
    if not data.get("ok"):
        print("FAIL CLOSED: Pre-flight check failed!")
        sys.exit(1)
    return data

if __name__ == "__main__":
    run_preflight()
