--!strict
--[[
	Economy math tests.

	The focus is not "the function returned something" but the properties
	that actually break in production: the closed-form series drifting away
	from individual purchases, caps, negative time, the reconnect exploit.
]]

local Balance = require("../src/shared/Economy/Balance")
local EconomyConfig = require("../src/shared/Economy/EconomyConfig")

local Pickaxe = EconomyConfig.upgrades.Pickaxe
local Drill = EconomyConfig.upgrades.Drill

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("upgradeCost", function()
		it("level zero costs the base price", function()
			expect(Balance.upgradeCost(Pickaxe, 0)).toBe(Pickaxe.baseCost)
		end)

		it("grows geometrically", function()
			local level5 = Balance.upgradeCost(Pickaxe, 5)
			local expected = Pickaxe.baseCost * Pickaxe.costGrowth ^ 5
			expect(level5).toBeCloseTo(expected)
		end)

		it("every next level costs more than the previous one", function()
			for level = 0, 50 do
				local current = Balance.upgradeCost(Pickaxe, level)
				local next_ = Balance.upgradeCost(Pickaxe, level + 1)
				expect(next_).toBeGreaterThan(current)
			end
		end)

		it("a negative level does not break the calculation", function()
			expect(Balance.upgradeCost(Pickaxe, -1)).toBe(0)
		end)
	end)

	describe("totalUpgradeCost", function()
		--[[
			The central test of the whole module. The closed-form sum must
			match adding levels one by one -- otherwise a player who buys 10
			levels at once pays a different price than one who buys them
			separately. That discrepancy is found within an hour of release.
		]]
		it("matches summing level by level", function()
			for _, upgrade in { Pickaxe, Drill } do
				for fromLevel = 0, 20 do
					local naive = 0
					for offset = 0, 9 do
						naive += Balance.upgradeCost(upgrade, fromLevel + offset)
					end

					local closed = Balance.totalUpgradeCost(upgrade, fromLevel, 10)

					-- Relative tolerance: on large numbers the absolute gap
					-- grows, but the relative one must stay negligible
					expect(math.abs(closed - naive) / naive).toBeLessThan(1e-9)
				end
			end
		end)

		it("zero levels cost zero", function()
			expect(Balance.totalUpgradeCost(Pickaxe, 5, 0)).toBe(0)
		end)

		it("a negative count costs zero", function()
			expect(Balance.totalUpgradeCost(Pickaxe, 5, -3)).toBe(0)
		end)

		it("one level costs exactly upgradeCost", function()
			expect(Balance.totalUpgradeCost(Pickaxe, 7, 1)).toBeCloseTo(Balance.upgradeCost(Pickaxe, 7))
		end)

		it("works with a linear price (growth = 1)", function()
			-- Degenerate case: the closed form divides by (g - 1)
			local linear = {
				id = "Linear",
				displayName = "Linear",
				baseCost = 100,
				costGrowth = 1,
				incomePerLevel = 1,
				maxLevel = 999,
			}
			expect(Balance.totalUpgradeCost(linear, 0, 5)).toBe(500)
		end)
	end)

	describe("maxAffordableLevels", function()
		it("buys nothing below the price of the first level", function()
			local levels, cost = Balance.maxAffordableLevels(Pickaxe, 0, Pickaxe.baseCost - 1)
			expect(levels).toBe(0)
			expect(cost).toBe(0)
		end)

		it("buys exactly one level for the price of one level", function()
			local levels = Balance.maxAffordableLevels(Pickaxe, 0, Pickaxe.baseCost)
			expect(levels).toBe(1)
		end)

		--[[
			The property the function exists for: what was bought is always
			affordable, and one more level is not. Checked across a wide range
			of balances, including deliberately awkward numbers.
		]]
		it("returns the true maximum the player can afford", function()
			local balances = { 50, 137, 1000, 99_999, 1e6, 1.5e7, 1e9 }

			for _, balance in balances do
				for _, startLevel in { 0, 3, 17, 60 } do
					local levels, cost = Balance.maxAffordableLevels(Pickaxe, startLevel, balance)

					-- What was bought fits in the balance
					expect(cost).toBeLessThan(balance + 1e-6)

					-- And one more level does not (unless we hit the cap)
					if startLevel + levels < Pickaxe.maxLevel then
						local withOneMore = Balance.totalUpgradeCost(Pickaxe, startLevel, levels + 1)
						expect(withOneMore).toBeGreaterThan(balance)
					end
				end
			end
		end)

		it("never goes past the level cap", function()
			-- Far more money than the entire branch costs
			local levels = Balance.maxAffordableLevels(Pickaxe, 0, math.huge)
			expect(levels).toBe(Pickaxe.maxLevel)
		end)

		it("buys nothing at the level cap", function()
			local levels = Balance.maxAffordableLevels(Pickaxe, Pickaxe.maxLevel, 1e12)
			expect(levels).toBe(0)
		end)

		it("a negative balance yields no levels", function()
			local levels = Balance.maxAffordableLevels(Pickaxe, 0, -100)
			expect(levels).toBe(0)
		end)
	end)

	describe("incomePerSecond", function()
		it("level zero produces no income", function()
			expect(Balance.incomePerSecond(Pickaxe, 0, 1)).toBe(0)
		end)

		it("scales linearly with level", function()
			local one = Balance.incomePerSecond(Pickaxe, 1, 1)
			local ten = Balance.incomePerSecond(Pickaxe, 10, 1)
			expect(ten).toBeCloseTo(one * 10)
		end)

		it("applies the multiplier", function()
			local base = Balance.incomePerSecond(Pickaxe, 5, 1)
			local doubled = Balance.incomePerSecond(Pickaxe, 5, 2)
			expect(doubled).toBeCloseTo(base * 2)
		end)

		it("a level above the cap grants no extra income", function()
			local atCap = Balance.incomePerSecond(Pickaxe, Pickaxe.maxLevel, 1)
			local overCap = Balance.incomePerSecond(Pickaxe, Pickaxe.maxLevel + 500, 1)
			expect(overCap).toBe(atCap)
		end)
	end)

	describe("totalIncomePerSecond", function()
		it("sums income across all upgrades", function()
			local levels = { Pickaxe = 10, Drill = 3 }
			local total = Balance.totalIncomePerSecond(EconomyConfig.upgrades, levels, 1)

			local expected = Balance.incomePerSecond(Pickaxe, 10, 1)
				+ Balance.incomePerSecond(Drill, 3, 1)

			expect(total).toBeCloseTo(expected)
		end)

		it("ignores unknown keys left by an old save", function()
			local levels = { Pickaxe = 5, ["RemovedUpgrade"] = 999 }
			local total = Balance.totalIncomePerSecond(EconomyConfig.upgrades, levels, 1)
			expect(total).toBeCloseTo(Balance.incomePerSecond(Pickaxe, 5, 1))
		end)

		it("an empty level set produces zero income", function()
			expect(Balance.totalIncomePerSecond(EconomyConfig.upgrades, {}, 1)).toBe(0)
		end)
	end)

	describe("prestige", function()
		local prestige = EconomyConfig.prestige

		it("the first prestige requires the base threshold", function()
			expect(Balance.prestigeRequirement(prestige, 0)).toBe(prestige.baseRequirement)
		end)

		it("the threshold rises with every prestige", function()
			local first = Balance.prestigeRequirement(prestige, 0)
			local second = Balance.prestigeRequirement(prestige, 1)
			expect(second).toBeGreaterThan(first)
		end)

		it("the multiplier is one without any prestige", function()
			expect(Balance.prestigeMultiplier(prestige, 0)).toBe(1)
		end)

		it("the multiplier grows linearly", function()
			local four = Balance.prestigeMultiplier(prestige, 4)
			local expected = 1 + prestige.multiplierPerPrestige * 4
			expect(four).toBeCloseTo(expected)
		end)

		it("the multiplier stops at the prestige cap", function()
			local atCap = Balance.prestigeMultiplier(prestige, prestige.maxPrestige)
			local overCap = Balance.prestigeMultiplier(prestige, prestige.maxPrestige + 100)
			expect(overCap).toBe(atCap)
		end)

		it("blocks prestige below the required earnings", function()
			expect(Balance.canPrestige(prestige, prestige.baseRequirement - 1, 0)).toBeFalsy()
		end)

		it("allows prestige exactly at the threshold", function()
			expect(Balance.canPrestige(prestige, prestige.baseRequirement, 0)).toBeTruthy()
		end)

		it("blocks prestige once the cap is reached", function()
			expect(Balance.canPrestige(prestige, math.huge, prestige.maxPrestige)).toBeFalsy()
		end)
	end)

	describe("offlineEarnings", function()
		local offline = EconomyConfig.offline

		it("credits time away at the reduced rate", function()
			local rate = 100
			local elapsed = 3600
			local earned, credited = Balance.offlineEarnings(offline, rate, elapsed, false)

			expect(credited).toBe(elapsed)
			expect(earned).toBeCloseTo(rate * elapsed * offline.rateFactor)
		end)

		--[[
			The exploit every idle game has to catch: the player leaves and
			rejoins every few seconds, collecting an "offline" payout each
			time. The minSeconds threshold closes that hole.
		]]
		it("ignores an absence that is too short", function()
			local earned = Balance.offlineEarnings(offline, 100, offline.minSeconds - 1, false)
			expect(earned).toBe(0)
		end)

		it("clamps time to the cap", function()
			local rate = 100
			local wayTooLong = offline.maxSeconds * 10
			local earned, credited = Balance.offlineEarnings(offline, rate, wayTooLong, false)

			expect(credited).toBe(offline.maxSeconds)
			expect(earned).toBeCloseTo(rate * offline.maxSeconds * offline.rateFactor)
		end)

		it("a gamepass raises both the cap and the rate", function()
			local rate = 100
			local elapsed = offline.gamepassMaxSeconds

			local without = Balance.offlineEarnings(offline, rate, elapsed, false)
			local with = Balance.offlineEarnings(offline, rate, elapsed, true)

			expect(with).toBeGreaterThan(without)
		end)

		--[[
			Client and server clocks drift, and the save holds the time of the
			last exit. A negative difference must produce zero rather than a
			negative payout that would drive the balance below zero.
		]]
		it("negative time credits nothing", function()
			local earned = Balance.offlineEarnings(offline, 100, -5000, false)
			expect(earned).toBe(0)
		end)

		it("zero income credits nothing", function()
			local earned = Balance.offlineEarnings(offline, 0, 100_000, false)
			expect(earned).toBe(0)
		end)

		it("NaN time does not break the calculation", function()
			local earned = Balance.offlineEarnings(offline, 100, 0 / 0, false)
			expect(earned).toBe(0)
		end)

		it("infinite time does not break the calculation", function()
			local earned, credited = Balance.offlineEarnings(offline, 100, math.huge, false)
			expect(earned).toBe(0)
			expect(credited).toBe(0)
		end)
	end)
end
