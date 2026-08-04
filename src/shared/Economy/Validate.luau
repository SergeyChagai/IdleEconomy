--!strict
--[[
	Validation of everything that arrives from the client.

	Baseline assumption: the client is hostile. Any remote argument may turn
	out to be nil, a table, NaN, negative, fractional, or a megabyte-long
	string -- calling a remote directly costs an exploiter nothing.

	This logic is deliberately pulled out of the service into a pure module:
	it is visible in one place and it can be exercised by tests without
	launching Roblox. Security checks are the last thing that should be
	verified by hand.
]]

-- Cap on a batch purchase. Not a balance knob: it exists so a call with
-- count = 1e9 cannot drag the server into a very long loop.
local MAX_BATCH = 1000

-- Longer than any meaningful id; blocks attempts to send a huge string
local MAX_ID_LENGTH = 64

export type UpgradeConfig = {
	id: string,
	displayName: string,
	baseCost: number,
	costGrowth: number,
	incomePerLevel: number,
	maxLevel: number,
}

local Validate = {}

Validate.MAX_BATCH = MAX_BATCH

--[[
	An integer within the given bounds.

	NaN (never equal to itself) and the fractional part are checked
	separately: a `count` like 2.5 makes a loop behave unexpectedly, and
	`math.huge` would hang the server.
]]
function Validate.integerInRange(value: unknown, min: number, max: number): (boolean, string?)
	if type(value) ~= "number" then
		return false, `expected a number, got {typeof(value)}`
	end

	if value ~= value then
		return false, "value is NaN"
	end

	if value == math.huge or value == -math.huge then
		return false, "value is infinite"
	end

	if value % 1 ~= 0 then
		return false, `expected an integer, got {value}`
	end

	if value < min or value > max then
		return false, `value {value} is outside [{min}, {max}]`
	end

	return true
end

--[[ String identifier: type, non-empty, sane length ]]
function Validate.identifier(value: unknown): (boolean, string?)
	if type(value) ~= "string" then
		return false, `expected a string, got {typeof(value)}`
	end

	if #value == 0 then
		return false, "empty identifier"
	end

	if #value > MAX_ID_LENGTH then
		return false, `identifier longer than {MAX_ID_LENGTH} characters`
	end

	return true
end

--[[
	Full check of an upgrade purchase request.

	Returns (ok, err, upgrade, count) -- on success the resolved upgrade
	config comes back too, so the service does not look it up twice.
]]
function Validate.upgradeRequest(
	upgrades: { [string]: UpgradeConfig },
	upgradeId: unknown,
	count: unknown
): (boolean, string?, UpgradeConfig?, number?)
	local idOk, idError = Validate.identifier(upgradeId)
	if not idOk then
		return false, `upgradeId: {idError}`
	end

	-- The existence check runs AFTER the type check: indexing a table with
	-- an arbitrary client-supplied value is not acceptable
	local upgrade = upgrades[upgradeId :: string]
	if not upgrade then
		return false, `unknown upgrade: {upgradeId :: string}`
	end

	local countOk, countError = Validate.integerInRange(count, 1, MAX_BATCH)
	if not countOk then
		return false, `count: {countError}`
	end

	return true, nil, upgrade, count :: number
end

return Validate
