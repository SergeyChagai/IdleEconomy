--!strict
--[[
	Economy math: prices, income, prestige, offline earnings.

	This module is deliberately PURE:
	  * no `require` -- loads both in Roblox and in Lune;
	  * no global state -- the config arrives as an argument;
	  * no side effects -- the same inputs always give the same output.

	That is precisely what makes all of it unit-testable without the engine.
]]

export type UpgradeConfig = {
	id: string,
	displayName: string,
	baseCost: number,
	costGrowth: number,
	incomePerLevel: number,
	maxLevel: number,
}

local Balance = {}

--[[ Helpers ]]

local function isFiniteNumber(value: number): boolean
	-- NaN never equals itself; infinities are ruled out by comparison
	return value == value and value ~= math.huge and value ~= -math.huge
end

--[[
	Price of ONE next level.

	Level 0 costs baseCost, and every purchased level multiplies it by
	costGrowth. The result is intentionally not rounded: rounding happens
	only on display. Rounding here would stop the closed-form series from
	matching the sum of individual purchases, and players notice that.
]]
function Balance.upgradeCost(upgrade: UpgradeConfig, level: number): number
	if level < 0 then
		return 0
	end
	return upgrade.baseCost * upgrade.costGrowth ^ level
end

--[[
	Total price of `count` levels starting at `fromLevel`.

	This is a geometric series:
	    S = a * (g^n - 1) / (g - 1),   where a = price of the first level

	Computed in closed form rather than with a loop: on "buy max" the count
	reaches hundreds of levels, and looping on every click is wasted work.
	The g = 1 case (linear price) is not covered by the formula -- it divides
	by zero -- so it gets its own branch.
]]
function Balance.totalUpgradeCost(upgrade: UpgradeConfig, fromLevel: number, count: number): number
	if count <= 0 then
		return 0
	end

	local first = Balance.upgradeCost(upgrade, fromLevel)
	local growth = upgrade.costGrowth

	if growth == 1 then
		return first * count
	end

	return first * (growth ^ count - 1) / (growth - 1)
end

--[[
	How many levels the player can afford, and what that costs.

	Inverting the series formula:
	    n = log(1 + balance * (g - 1) / a) / log(g)

	Closed form answers instantly, but it has a flaw: on large numbers the
	logarithm is off by one in the last digit, so the player either loses a
	level or goes negative. The result is therefore always corrected in both
	directions -- that costs one or two steps and removes the entire class of
	rounding bugs.
]]
function Balance.maxAffordableLevels(
	upgrade: UpgradeConfig,
	currentLevel: number,
	balance: number
): (number, number)
	if balance <= 0 or currentLevel >= upgrade.maxLevel then
		return 0, 0
	end

	local first = Balance.upgradeCost(upgrade, currentLevel)
	if balance < first then
		return 0, 0
	end

	local growth = upgrade.costGrowth
	local levels: number

	if growth == 1 then
		levels = math.floor(balance / first)
	else
		levels = math.floor(math.log(1 + (balance * (growth - 1)) / first) / math.log(growth))
	end

	-- Never buy past the level cap
	levels = math.min(levels, upgrade.maxLevel - currentLevel)
	levels = math.max(levels, 0)

	-- Correct downwards: the formula may have overshot
	while levels > 0 and Balance.totalUpgradeCost(upgrade, currentLevel, levels) > balance do
		levels -= 1
	end

	-- Correct upwards: the formula may have undershot
	while
		currentLevel + levels < upgrade.maxLevel
		and Balance.totalUpgradeCost(upgrade, currentLevel, levels + 1) <= balance
	do
		levels += 1
	end

	return levels, Balance.totalUpgradeCost(upgrade, currentLevel, levels)
end

--[[ Income ]]

--[[
	Income per second from a single upgrade, including the prestige
	multiplier. At level zero an upgrade produces nothing.
]]
function Balance.incomePerSecond(upgrade: UpgradeConfig, level: number, multiplier: number): number
	if level <= 0 then
		return 0
	end
	local effectiveLevel = math.min(level, upgrade.maxLevel)
	return effectiveLevel * upgrade.incomePerLevel * multiplier
end

--[[
	Total income across all of the player's upgrades.
	Unknown keys in `levels` are ignored -- an old save may still carry them.
]]
function Balance.totalIncomePerSecond(
	upgrades: { [string]: UpgradeConfig },
	levels: { [string]: number },
	multiplier: number
): number
	local total = 0

	for id, upgrade in upgrades do
		local level = levels[id]
		if level then
			total += Balance.incomePerSecond(upgrade, level, multiplier)
		end
	end

	return total
end

--[[ Prestige ]]

export type PrestigeConfig = {
	baseRequirement: number,
	requirementGrowth: number,
	multiplierPerPrestige: number,
	maxPrestige: number,
}

--[[ Lifetime earnings needed to enter prestige number prestigeCount + 1 ]]
function Balance.prestigeRequirement(config: PrestigeConfig, prestigeCount: number): number
	if prestigeCount >= config.maxPrestige then
		return math.huge -- cap reached, there is no further prestige
	end
	return config.baseRequirement * config.requirementGrowth ^ prestigeCount
end

--[[ Income multiplier from prestiges already earned. Linear, not
     exponential: an exponential curve here breaks balance within a dozen
     prestiges. ]]
function Balance.prestigeMultiplier(config: PrestigeConfig, prestigeCount: number): number
	local capped = math.min(prestigeCount, config.maxPrestige)
	return 1 + config.multiplierPerPrestige * capped
end

function Balance.canPrestige(
	config: PrestigeConfig,
	lifetimeEarned: number,
	prestigeCount: number
): boolean
	if prestigeCount >= config.maxPrestige then
		return false
	end
	return lifetimeEarned >= Balance.prestigeRequirement(config, prestigeCount)
end

--[[ Offline earnings ]]

export type OfflineConfig = {
	maxSeconds: number,
	rateFactor: number,
	gamepassMaxSeconds: number,
	gamepassRateFactor: number,
	minSeconds: number,
}

--[[
	Earnings for time spent away.

	Returns (amount, seconds actually credited). The second value exists so
	the UI can honestly say "credited 8h out of 30h away".

	Guards:
	  * negative elapsed (player or server clock drifted) => 0;
	  * absence too short => 0, otherwise reconnecting becomes a farm;
	  * a cap on time, otherwise someone returning after a year breaks the
	    economy.
]]
function Balance.offlineEarnings(
	config: OfflineConfig,
	ratePerSecond: number,
	elapsedSeconds: number,
	hasGamepass: boolean
): (number, number)
	if not isFiniteNumber(elapsedSeconds) or not isFiniteNumber(ratePerSecond) then
		return 0, 0
	end

	if elapsedSeconds < config.minSeconds or ratePerSecond <= 0 then
		return 0, 0
	end

	local maxSeconds = if hasGamepass then config.gamepassMaxSeconds else config.maxSeconds
	local factor = if hasGamepass then config.gamepassRateFactor else config.rateFactor

	local creditedSeconds = math.min(elapsedSeconds, maxSeconds)

	return ratePerSecond * creditedSeconds * factor, creditedSeconds
end

return Balance
