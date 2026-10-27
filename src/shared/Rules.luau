--!strict
-- Buzzer Simulator — Rules (BS-01, pure deterministic; formula source: docs/02, docs/04).
-- No randomness, no yielding, no service access. Invalid/nonfinite inputs error:
-- callers are trusted server code; garbage must fail loudly, never pay.

local Catalog = require(script.Parent.Catalog)
local GameTypes = require(script.Parent.GameTypes)

local Rules = {}

local FIT_MULTIPLIER = {
	strong = 1.25,
	weak = 0.75,
} :: { [GameTypes.FitKind]: number }

-- Validates a positive finite device yield multiplier.
local function validateYield(deviceYield: number): number
	if typeof(deviceYield) ~= "number" or deviceYield ~= deviceYield or deviceYield == math.huge or deviceYield == -math.huge then
		error(`postImpact: deviceYield must be finite, got {tostring(deviceYield)}`, 0)
	end
	if deviceYield <= 0 then
		error(`postImpact: deviceYield must be > 0, got {tostring(deviceYield)}`, 0)
	end
	return deviceYield
end

local function validateFit(fit: GameTypes.FitKind): GameTypes.FitKind
	if fit ~= "strong" and fit ~= "weak" then
		error(`fit must be "strong" or "weak", got {tostring(fit)}`, 0)
	end
	return fit
end

local function validatePositiveInteger(name: string, value: number): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error(`{name} must be finite, got {tostring(value)}`, 0)
	end
	if value % 1 ~= 0 or value < 0 then
		error(`{name} must be a nonnegative integer, got {tostring(value)}`, 0)
	end
	return value
end

-- Post impact on settle (04): strong floor(B * 1.20 * yield);
-- weak min(floor(B * 0.75 * yield), ceil(B * 0.94), B - 1).
-- Weak is capped strictly below B: a weak first post never clears the goal,
-- two weak starter posts (B=100) always do (75*2 >= 100).
function Rules.postImpact(B: number, fit: GameTypes.FitKind, deviceYield: number): number
	validatePositiveInteger("B", B)
	if B < 1 then
		error(`B must be >= 1, got {tostring(B)}`, 0)
	end
	validateFit(fit)
	validateYield(deviceYield)

	if fit == "strong" then
		return math.floor(B * 1.20 * deviceYield)
	end
	local weakFloor = math.floor(B * 0.75 * deviceYield)
	local capCeil = math.ceil(B * 0.94)
	local underB = B - 1
	return math.min(weakFloor, capCeil, underB)
end

-- Organic Cuan payout per settled post, either publishing mode (04):
-- floor(12 * fitMultiplier * yield); strong 1.25, weak 0.75.
function Rules.organicCuan(fit: GameTypes.FitKind, deviceYield: number): number
	validateFit(fit)
	validateYield(deviceYield)
	return math.floor(12 * FIT_MULTIPLIER[fit] * deviceYield)
end

-- Highest shipped tier reachable now (02 career table): requires BOTH
-- lifetimeEarned >= threshold and completedMissions >= claimsThreshold,
-- clamped to maxShippedTier. Wallet/purchases never demote (monotone inputs).
function Rules.eligibleTier(lifetimeEarned: number, completedMissions: number, maxShippedTier: number): number
	validatePositiveInteger("lifetimeEarned", lifetimeEarned)
	validatePositiveInteger("completedMissions", completedMissions)
	validatePositiveInteger("maxShippedTier", maxShippedTier)

	local capped = math.min(maxShippedTier, #Catalog.Tiers - 1)
	for tier = capped, 0, -1 do
		local def = Catalog.Tiers[tier + 1] -- catalog array is 1-indexed by tier+1
		if def and lifetimeEarned >= def.lifetimeRequired and completedMissions >= def.claimsRequired then
			return tier
		end
	end
	return 0
end

return Rules