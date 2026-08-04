--!strict
--[[
	PurchaseAnalytics unit tests.
]]

local PurchaseAnalytics = require("../src/shared/Economy/PurchaseAnalytics")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("event builders", function()
		it("builds a granted event", function()
			local event = PurchaseAnalytics.granted("pid", "CoinsSmall", 123, 456, 5000)
			expect(event.kind).toBe("receipt_granted")
			expect(event.purchaseId).toBe("pid")
			expect(event.productKey).toBe("CoinsSmall")
			expect(event.coins).toBe(5000)
		end)

		it("builds a duplicate event", function()
			local event = PurchaseAnalytics.duplicate("pid", 1)
			expect(event.kind).toBe("receipt_duplicate")
		end)

		it("builds a deferred event", function()
			local event = PurchaseAnalytics.deferred("pid", "profile not loaded")
			expect(event.kind).toBe("receipt_deferred")
			expect(event.reason).toBe("profile not loaded")
		end)

		it("builds an unknown-product event", function()
			local event = PurchaseAnalytics.unknownProduct("pid", 99)
			expect(event.kind).toBe("receipt_unknown_product")
			expect(event.productId).toBe(99)
		end)
	end)
end
