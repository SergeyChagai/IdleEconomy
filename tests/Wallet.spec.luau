--!strict
--[[
	Wallet tests.

	The heart of it: a balance cannot be driven negative and cannot be
	changed behind the class's back. Atomicity is checked separately -- a
	failed operation must leave no trace.
]]

local Wallet = require("../src/shared/Economy/Wallet")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("construction", function()
		it("an empty wallet reports zeroes", function()
			local wallet = Wallet.new()
			expect(wallet:get("Coins")).toBe(0)
		end)

		it("accepts a starting balance", function()
			local wallet = Wallet.new({ Coins = 500, Gems = 10 })
			expect(wallet:get("Coins")).toBe(500)
			expect(wallet:get("Gems")).toBe(10)
		end)

		--[[
			A save may arrive corrupt -- NaN, a negative number, or junk left
			by a failed migration. Joining the game must not fail because of
			it: zeroing a currency beats locking the player out.
		]]
		it("repairs corrupt save values instead of failing", function()
			local wallet = Wallet.new({ Coins = -100, Gems = 0 / 0, Tickets = math.huge })
			expect(wallet:get("Coins")).toBe(0)
			expect(wallet:get("Gems")).toBe(0)
			expect(wallet:get("Tickets")).toBe(0)
		end)

		--[[
			Had the constructor kept a reference to the passed table, the
			caller could change the balance around every check.
		]]
		it("copies the initial table rather than referencing it", function()
			local initial = { Coins = 100 }
			local wallet = Wallet.new(initial)

			initial.Coins = 999_999

			expect(wallet:get("Coins")).toBe(100)
		end)
	end)

	describe("add", function()
		it("credits an amount", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:add("Coins", 50)

			expect(ok).toBeTruthy()
			expect(wallet:get("Coins")).toBe(150)
		end)

		it("creates a currency that did not exist yet", function()
			local wallet = Wallet.new()
			wallet:add("Gems", 7)
			expect(wallet:get("Gems")).toBe(7)
		end)

		--[[
			The key guard: if add accepted negatives, every "can they afford
			it" check could be bypassed by calling add(-amount).
		]]
		it("rejects a negative amount", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok, err = wallet:add("Coins", -50)

			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		it("rejects NaN", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:add("Coins", 0 / 0)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		it("rejects infinity", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:add("Coins", math.huge)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		--[[
			Past 2^53 a double stops distinguishing adjacent integers. Sliding
			there silently is not acceptable: the player would see purchases
			that never deduct.
		]]
		it("reports reaching the balance cap", function()
			local wallet = Wallet.new({ Coins = 2 ^ 53 })
			local ok, err = wallet:add("Coins", 1000)

			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
		end)
	end)

	describe("trySpend", function()
		it("spends when there is enough", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:trySpend("Coins", 30)

			expect(ok).toBeTruthy()
			expect(wallet:get("Coins")).toBe(70)
		end)

		it("spends the entire balance exactly", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:trySpend("Coins", 100)

			expect(ok).toBeTruthy()
			expect(wallet:get("Coins")).toBe(0)
		end)

		--[[
			The most important property of the class: when funds are short the
			balance does not change at all. A partial deduction would leave
			the player without the money and without the purchase.
		]]
		it("leaves the balance untouched when funds are short", function()
			local wallet = Wallet.new({ Coins = 50 })
			local ok, err = wallet:trySpend("Coins", 100)

			expect(ok).toBeFalsy()
			expect(err).toBe("insufficient funds")
			expect(wallet:get("Coins")).toBe(50)
		end)

		it("cannot spend from a currency that does not exist", function()
			local wallet = Wallet.new()
			local ok = wallet:trySpend("Coins", 1)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(0)
		end)

		it("rejects a negative amount", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:trySpend("Coins", -50)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		it("the balance never goes negative", function()
			local wallet = Wallet.new({ Coins = 10 })

			for _ = 1, 100 do
				wallet:trySpend("Coins", 3)
			end

			expect(wallet:get("Coins")).toBeGreaterThan(-1)
		end)
	end)

	describe("has", function()
		it("confirms a sufficient balance", function()
			local wallet = Wallet.new({ Coins = 100 })
			expect(wallet:has("Coins", 100)).toBeTruthy()
			expect(wallet:has("Coins", 99)).toBeTruthy()
		end)

		it("rejects an insufficient balance", function()
			local wallet = Wallet.new({ Coins = 100 })
			expect(wallet:has("Coins", 101)).toBeFalsy()
		end)

		it("rejects an invalid amount", function()
			local wallet = Wallet.new({ Coins = 100 })
			expect(wallet:has("Coins", 0 / 0)).toBeFalsy()
		end)
	end)

	describe("tryExchange", function()
		it("performs the whole exchange", function()
			local wallet = Wallet.new({ Gems = 10, Coins = 0 })
			local ok = wallet:tryExchange("Gems", 5, "Coins", 500)

			expect(ok).toBeTruthy()
			expect(wallet:get("Gems")).toBe(5)
			expect(wallet:get("Coins")).toBe(500)
		end)

		--[[
			Atomicity: if the deduction succeeds and the credit does not, the
			money vanishes. This checks that the rollback really happens.
		]]
		it("rolls the deduction back when the credit fails", function()
			local wallet = Wallet.new({ Gems = 10, Coins = 2 ^ 53 })
			local ok = wallet:tryExchange("Gems", 5, "Coins", 1000)

			expect(ok).toBeFalsy()
			expect(wallet:get("Gems")).toBe(10) -- gems still there
		end)

		it("does not exchange when there is nothing to deduct", function()
			local wallet = Wallet.new({ Gems = 1 })
			local ok = wallet:tryExchange("Gems", 5, "Coins", 500)

			expect(ok).toBeFalsy()
			expect(wallet:get("Gems")).toBe(1)
			expect(wallet:get("Coins")).toBe(0)
		end)
	end)

	describe("serialize", function()
		it("returns the current balance", function()
			local wallet = Wallet.new({ Coins = 100, Gems = 5 })
			expect(wallet:serialize()).toEqual({ Coins = 100, Gems = 5 })
		end)

		--[[
			The snapshot goes into saves and analytics. Were it the internal
			table, any consumer could change the balance.
		]]
		it("returns a copy, not the internal table", function()
			local wallet = Wallet.new({ Coins = 100 })
			local snapshot = wallet:serialize()

			snapshot.Coins = 999_999

			expect(wallet:get("Coins")).toBe(100)
		end)

		it("survives a save/load round trip", function()
			local original = Wallet.new({ Coins = 1234, Gems = 56 })
			local restored = Wallet.new(original:serialize())

			expect(restored:serialize()).toEqual(original:serialize())
		end)
	end)
end
