import sys
import os
import time
import json

sys.path.append(os.path.abspath("tools/agent"))
import studio

AUDIT_CODE = r"""
local HttpService = game:GetService("HttpService")
local sss = game:GetService("ServerScriptService")
local ProfileStore = require(sss:WaitForChild("ProfileStore"))

local results = {}
local function record(name, pass, detail)
	table.insert(results, { name = name, pass = pass == true, detail = tostring(detail) })
end

local function newProfile(balance, lifetime)
	return {
		balance = balance or 0, lifetimeEarned = lifetime or 0, completedMissions = 0,
		deviceId = "phone_cheap", propertyId = "bedroom",
		ownedDesks = {}, workers = {}, fractionalIncome = 0,
		claimedRunIdsWindow = {}, recentMutationOutcomes = {},
		missionVariantCounters = {}, nextOrganicSequence = 0,
		ownPosts = {}, nextPostSequence = 1,
	}
end

local function newAdapter()
	local adapter = { data = {}, writes = 0, reads = 0, failNext = 0, delay = 0 }
	function adapter:GetAsync(key)
		self.reads += 1
		return self.data[key]
	end
	function adapter:UpdateAsync(key, transform)
		if self.delay > 0 then task.wait(self.delay) end
		if self.failNext > 0 then
			self.failNext -= 1
			error("injected transport failure", 0)
		end
		self.writes += 1
		local proposed = transform(self.data[key])
		if proposed ~= nil then self.data[key] = proposed end
		return proposed
	end
	return adapter
end

local tokenCounter = 0
local function newStore(adapter, userId, clock)
	return ProfileStore.new(userId, {
		store = adapter,
		jobId = "bs14-audit",
		now = function() return clock.now end,
		wait = function() end,
		httpService = { GenerateGUID = function(_braces)
			tokenCounter += 1
			return string.format("audit-guid-%06d", tokenCounter)
		end },
		noCacheOptions = function() return { UseCache = false } end,
	})
end

local function seed(adapter, userId, revision, profile, extra)
	local envelope = {
		schemaVersion = 1, revision = revision, lastSaveOpId = "seed", updatedAt = 1000,
		profile = profile, lease = { token = "", jobId = "seed", expiresAt = 0 },
	}
	for key, value in next, (extra or {}) do envelope[key] = value end
	adapter.data["Player_" .. userId] = envelope
end

-- A: byte-compatible load of a v1 envelope carrying an unknown extra field -----
do
	local adapter = newAdapter()
	local clock = { now = 1000 }
	seed(adapter, 92001, 4, newProfile(750, 900), { legacyFlags = { migrated = true } })
	local store = newStore(adapter, 92001, clock)
	local loaded = store:Load()
	local ok = loaded.ok and loaded.envelope ~= nil and loaded.envelope.profile ~= nil
		and loaded.envelope.profile.balance == 750 and loaded.envelope.revision == 4
	record("PERSIST-01 Unknown extra envelope field tolerated, balance preserved", ok,
		`ok={tostring(loaded.ok)} code={tostring(loaded.code)} balance={tostring(loaded.envelope and loaded.envelope.profile and loaded.envelope.profile.balance)}`)
end

-- B: foreign schemaVersion is fail-closed -------------------------------------
do
	local adapter = newAdapter()
	local clock = { now = 1000 }
	seed(adapter, 92002, 9, newProfile(100, 100), { schemaVersion = 99 })
	local store = newStore(adapter, 92002, clock)
	local loaded = store:Load()
	local usable = loaded.ok and loaded.envelope ~= nil and loaded.envelope.profile ~= nil
	record("PERSIST-02 Foreign schemaVersion refused (never migrated blindly)",
		not usable, `ok={tostring(loaded.ok)} code={tostring(loaded.code)}`)
end

-- C: stale expected revision never clobbers a newer durable state -------------
do
	local adapter = newAdapter()
	local clock = { now = 1000 }
	seed(adapter, 92003, 5, newProfile(300, 300))
	local store = newStore(adapter, 92003, clock)
	local first = store:Load()
	local token = store:GetLeaseToken()
	-- A newer writer (another session) advances the durable revision to 7 while
	-- this reader still believes it holds revision 5.
	adapter.data["Player_92003"].revision = 7
	adapter.data["Player_92003"].lastSaveOpId = "newer-writer"
	adapter.data["Player_92003"].profile = newProfile(3000, 3000)
	local save = store:Save(newProfile(1, 1), "stale-write-0001", "publish:stale")
	local durable = adapter.data["Player_92003"]
	record("PERSIST-03 Stale revision write aborted, newer durable state intact",
		first.ok and token ~= nil and save.ok == false and durable.revision == 7
			and durable.profile.balance == 3000,
		`saveCode={tostring(save.code)} durableRevision={tostring(durable.revision)} durableBalance={tostring(durable.profile.balance)}`)
end

-- D: second server cannot steal a live lease ----------------------------------
do
	local adapter = newAdapter()
	local clock = { now = 1000 }
	seed(adapter, 92004, 1, newProfile(50, 50))
	local first = newStore(adapter, 92004, clock)
	local second = newStore(adapter, 92004, clock)
	local firstLoad = first:Load()
	local secondLoad = second:Load()
	record("PERSIST-04 Concurrent second server denied the live lease",
		firstLoad.ok and secondLoad.ok == false,
		`first={tostring(firstLoad.ok)} second={tostring(secondLoad.code)}`)
end

-- E: sustained single-key write pressure, serialized and lossless -------------
do
	local adapter = newAdapter()
	adapter.delay = 0.04 -- injected single-key service latency (docs/03 model)
	local clock = { now = 1000 }
	seed(adapter, 92005, 1, newProfile(0, 0))
	local store = newStore(adapter, 92005, clock)
	local loaded = store:Load()
	local writes = 0
	local monotone = true
	local lastRevision = store:GetLastConfirmedRevision()
	local latencies = {}
	for index = 1, 30 do
		clock.now += 2
		local started = os.clock()
		local result = store:Save(newProfile(index * 10, index * 10), string.format("pressure-write-%04d", index),
			`publish:{index}`)
		table.insert(latencies, (os.clock() - started) * 1000)
		if result.ok then
			writes += 1
			if result.revision <= lastRevision then monotone = false end
			lastRevision = result.revision
		end
	end
	table.sort(latencies)
	local function pct(p) return latencies[math.max(1, math.ceil(p * #latencies))] end
	local durable = adapter.data["Player_92005"]
	record("PERSIST-05 30 sustained writes serialized without loss",
		loaded.ok and writes == 30 and monotone and durable.profile.balance == 300 and durable.revision == 31,
		`writes={writes} backendWrites={adapter.writes} revision={tostring(durable.revision)} balance={tostring(durable.profile.balance)} `
			.. `latencyMs p50={string.format('%.1f', pct(0.5))} p95={string.format('%.1f', pct(0.95))} max={string.format('%.1f', latencies[#latencies])}`)
end

-- F: ambiguous transport failure retried under the same operation ID ----------
do
	local adapter = newAdapter()
	local clock = { now = 1000 }
	seed(adapter, 92006, 1, newProfile(0, 0))
	local store = newStore(adapter, 92006, clock)
	local loaded = store:Load()
	adapter.failNext = 2
	local result = store:Save(newProfile(400, 400), "retry-write-0001", "publish:retry")
	local durable = adapter.data["Player_92006"]
	record("PERSIST-06 Ambiguous failures retried to exactly one durable write",
		loaded.ok and result.ok and durable.lastSaveOpId == "retry-write-0001"
			and durable.profile.balance == 400 and durable.revision == 2,
		`ok={tostring(result.ok)} code={tostring(result.code)} revision={tostring(durable.revision)} backendWrites={adapter.writes}`)
end

-- G: replayed operation ID with different payload is refused ------------------
do
	local adapter = newAdapter()
	local clock = { now = 1000 }
	seed(adapter, 92007, 1, newProfile(0, 0))
	local store = newStore(adapter, 92007, clock)
	local loaded = store:Load()
	local firstSave = store:Save(newProfile(100, 100), "replay-write-0001", "publish:a")
	local replay = store:Save(newProfile(200, 200), "replay-write-0001", "publish:a")
	record("PERSIST-07 Reused operation ID with different payload refused",
		loaded.ok and firstSave.ok and replay.ok == false and replay.code == "INVALID_PROFILE",
		`first={tostring(firstSave.code)} replay={tostring(replay.code)}`)
end

local passed = 0
for _, entry in ipairs(results) do if entry.pass then passed += 1 end end
return HttpService:JSONEncode({
	totalProbes = #results, passedProbes = passed, results = results,
})


"""


def run():
    c = studio.get_client()
    sid = studio.get_studio_id()
    print(f"Play Solo persistence audit (studio {sid})...")
    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": True})
    time.sleep(3)

    raw = studio.luau(AUDIT_CODE, "Server")
    print("Raw:", raw)

    try:
        data = json.loads(raw) if isinstance(raw, str) else raw
    except Exception as exc:
        print(f"parse error: {exc}")
        c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})
        return {"error": str(exc), "raw": raw}

    print(f"\n=== Persistence Audit: {data.get('passedProbes')}/{data.get('totalProbes')} ===")
    for entry in data.get("results", []):
        print(f"  [{'PASS' if entry.get('pass') else 'FAIL'}] {entry.get('name')}: {entry.get('detail')}")

    c.call_tool("start_stop_play", {"studio_id": sid, "is_start": False})

    os.makedirs(os.path.join("docs", "evidence", "bs14"), exist_ok=True)
    report = os.path.join("docs", "evidence", "bs14", "datastore-pressure.txt")
    with open(report, "w", encoding="utf-8") as handle:
        handle.write("=== BS-14 DataStore Schema, Rollback Reader & Write-Pressure Audit ===\n")
        handle.write(f"Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}\n")
        handle.write("Tier: 2 (offline Studio, real ProfileStore code + injected store adapter)\n")
        handle.write(f"Total: {data.get('totalProbes')}, Passed: {data.get('passedProbes')}\n\n")
        for entry in data.get("results", []):
            handle.write(f"[{'PASS' if entry.get('pass') else 'FAIL'}] {entry.get('name')}\n")
            handle.write(f"  Details: {entry.get('detail')}\n\n")
    print(f"Saved {report}")
    return data


if __name__ == "__main__":
    run()
