--!strict
--[[
	Remote validation tests.

	Written from the attacker's seat: what can be sent into a remote to crash
	the server, hang it, or extract extra money.
]]

local Validate = require("../src/shared/Economy/Validate")
local EconomyConfig = require("../src/shared/Economy/EconomyConfig")

local upgrades = EconomyConfig.upgrades

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("integerInRange", function()
		it("accepts an integer inside the range", function()
			expect(Validate.integerInRange(5, 1, 10)).toBeTruthy()
		end)

		it("accepts the range boundaries", function()
			expect(Validate.integerInRange(1, 1, 10)).toBeTruthy()
			expect(Validate.integerInRange(10, 1, 10)).toBeTruthy()
		end)

		it("rejects values outside the range", function()
			expect(Validate.integerInRange(0, 1, 10)).toBeFalsy()
			expect(Validate.integerInRange(11, 1, 10)).toBeFalsy()
		end)

		it("rejects a fractional value", function()
			-- 2.5 in a "buy N times" loop gives an unexpected iteration count
			expect(Validate.integerInRange(2.5, 1, 10)).toBeFalsy()
		end)

		it("rejects nil", function()
			expect(Validate.integerInRange(nil, 1, 10)).toBeFalsy()
		end)

		it("rejects a string", function()
			expect(Validate.integerInRange("5", 1, 10)).toBeFalsy()
		end)

		it("rejects a table", function()
			expect(Validate.integerInRange({}, 1, 10)).toBeFalsy()
		end)

		it("rejects a boolean", function()
			expect(Validate.integerInRange(true, 1, 10)).toBeFalsy()
		end)

		it("rejects NaN", function()
			expect(Validate.integerInRange(0 / 0, 1, 10)).toBeFalsy()
		end)

		--[[ math.huge % 1 yields NaN rather than 0, so the fractional check
		     does not catch it -- a dedicated check is required. A classic
		     hole. ]]
		it("rejects infinity", function()
			expect(Validate.integerInRange(math.huge, 1, 10)).toBeFalsy()
			expect(Validate.integerInRange(-math.huge, 1, 10)).toBeFalsy()
		end)

		it("returns an error message", function()
			local ok, err = Validate.integerInRange(99, 1, 10)
			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
		end)
	end)

	describe("identifier", function()
		it("accepts a normal string", function()
			expect(Validate.identifier("Pickaxe")).toBeTruthy()
		end)

		it("rejects an empty string", function()
			expect(Validate.identifier("")).toBeFalsy()
		end)

		it("rejects nil", function()
			expect(Validate.identifier(nil)).toBeFalsy()
		end)

		it("rejects a number", function()
			expect(Validate.identifier(42)).toBeFalsy()
		end)

		it("rejects a table", function()
			expect(Validate.identifier({})).toBeFalsy()
		end)

		--[[ An exploiter can send a megabyte-long string to inflate server
		     logs and memory ]]
		it("rejects an overly long string", function()
			expect(Validate.identifier(string.rep("a", 100_000))).toBeFalsy()
		end)
	end)

	describe("upgradeRequest", function()
		it("accepts a well-formed request", function()
			local ok, err, upgrade, count = Validate.upgradeRequest(upgrades, "Pickaxe", 5)

			expect(ok).toBeTruthy()
			expect(err).toBeNil()
			expect(upgrade).toBeTruthy()
			expect(count).toBe(5)
		end)

		it("returns the resolved upgrade config", function()
			local _, _, upgrade = Validate.upgradeRequest(upgrades, "Drill", 1)
			expect(upgrade.id).toBe("Drill")
		end)

		it("rejects an unknown upgrade", function()
			local ok, err = Validate.upgradeRequest(upgrades, "NoSuchUpgrade", 1)
			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
		end)

		it("rejects a zero count", function()
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", 0)).toBeFalsy()
		end)

		it("rejects a negative count", function()
			-- Without this check, buying -10 levels could CREDIT money
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", -10)).toBeFalsy()
		end)

		--[[ Without a cap, a call with count = 1e9 sends the server into a
		     billion-iteration loop and hangs everyone on it, not one player ]]
		it("rejects an absurd count", function()
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", 1e9)).toBeFalsy()
		end)

		it("accepts exactly the maximum batch size", function()
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", Validate.MAX_BATCH)).toBeTruthy()
		end)

		it("rejects missing arguments", function()
			expect(Validate.upgradeRequest(upgrades, nil, nil)).toBeFalsy()
		end)

		it("rejects arguments of the wrong type", function()
			expect(Validate.upgradeRequest(upgrades, {}, {})).toBeFalsy()
		end)

		--[[
			An attempt to reach table internals through a remote. The
			existence check must run after the type check, otherwise indexing
			with an arbitrary value produces surprising results.
		]]
		it("does not expose table internals", function()
			expect(Validate.upgradeRequest(upgrades, "__index", 1)).toBeFalsy()
			expect(Validate.upgradeRequest(upgrades, "__metatable", 1)).toBeFalsy()
		end)
	end)
end
