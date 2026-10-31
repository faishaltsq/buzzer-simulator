--!strict
-- Buzzer Simulator — BS-01 test runner entry (test.project.json only).
-- Aggregates all spec modules under tests/Specs and fails the server script
-- (nonzero Studio output marker) if any test fails.

local runnerRoot = script.Parent

-- Require every spec module in this folder. Each spec registers its own tests
-- via Aggregator and runs them immediately; failures propagate as errors.
local specsFolder = runnerRoot:WaitForChild("Specs")

local results = {}
for _, spec in ipairs(specsFolder:GetChildren()) do
	if spec:IsA("ModuleScript") then
		local ok, summary = pcall(require, spec)
		table.insert(results, {
			name = spec.Name,
			ok = ok,
			detail = if ok then tostring(summary) else ("ERROR: " .. tostring(summary)),
		})
	end
end

local total = 0
local failed = 0
for _, r in ipairs(results) do
	total += 1
	if not r.ok then
		failed += 1
	end
	print(`[{if r.ok then "SUITE PASS" else "SUITE FAIL"}] {r.name}: {r.detail}`)
end

print(`==============================================`)
print(`BS-01 suites: {total - failed}/{total} passed, {failed} failed`)
if failed > 0 then
	print("BS01_TESTS_FAILED")
	error(`BS-01 runner: {failed} spec suite(s) failed`, 0)
else
	print("BS01_TESTS_PASSED")
end