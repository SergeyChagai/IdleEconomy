--!strict
--[[
	PurchaseLedger unit tests.

	The cases that matter in production are retries and races: the same
	PurchaseId arriving twice must never grant twice, and a failed grant must
	not leave the id stamped.
]]

local PurchaseLedger = require("../src/shared/Economy/PurchaseLedger")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("contains", function()
		it("finds a recorded id", function()
			expect(PurchaseLedger.contains({ "a", "b" }, "b")).toBe(true)
		end)

		it("misses an unknown id", function()
			expect(PurchaseLedger.contains({ "a" }, "z")).toBe(false)
		end)

		it("rejects an empty id", function()
			expect(PurchaseLedger.contains({ "" }, "")).toBe(false)
		end)
	end)

	describe("record", function()
		it("appends a new PurchaseId", function()
			local wasNew, nextHistory = PurchaseLedger.record({}, "p-1", 100)

			expect(wasNew).toBe(true)
			expect(#nextHistory).toBe(1)
			expect(nextHistory[1]).toBe("p-1")
		end)

		it("refuses a duplicate without granting again", function()
			local _, once = PurchaseLedger.record({}, "p-1", 100)
			local wasNew, twice = PurchaseLedger.record(once, "p-1", 100)

			expect(wasNew).toBe(false)
			expect(#twice).toBe(1)
		end)

		--[[
			ProcessReceipt may fire again after a restart. The second delivery
			must look identical to the first acknowledgement: already granted.
		]]
		it("survives a replay after a restart between attempts", function()
			local _, saved = PurchaseLedger.record({}, "receipt-42", 100)
			-- pretend the save was reloaded
			local reloaded = table.clone(saved)
			local wasNew = PurchaseLedger.record(reloaded, "receipt-42", 100)

			expect(wasNew).toBe(false)
		end)

		it("does not mutate the input history", function()
			local original = { "old" }
			PurchaseLedger.record(original, "new", 100)
			expect(#original).toBe(1)
			expect(original[1]).toBe("old")
		end)

		it("drops the oldest entries past the limit", function()
			local history = { "a", "b", "c" }
			local wasNew, nextHistory = PurchaseLedger.record(history, "d", 3)

			expect(wasNew).toBe(true)
			expect(#nextHistory).toBe(3)
			expect(nextHistory[1]).toBe("b")
			expect(nextHistory[3]).toBe("d")
		end)

		it("rejects a blank PurchaseId", function()
			local wasNew, nextHistory = PurchaseLedger.record({ "x" }, "", 100)
			expect(wasNew).toBe(false)
			expect(#nextHistory).toBe(1)
		end)
	end)
end
