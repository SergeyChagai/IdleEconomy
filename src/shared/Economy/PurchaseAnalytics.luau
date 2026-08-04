--!strict
--[[
	Purchase analytics events.

	Pure builders -- no engine, no `require`. The service layer decides how to
	emit (print in Studio, AnalyticsService in production). Keeping the event
	shape here means tests can assert on fields without mocking Roblox.
]]

local PurchaseAnalytics = {}

export type ReceiptEvent = {
	kind: string,
	purchaseId: string,
	productKey: string?,
	productId: number?,
	playerId: number?,
	coins: number?,
	reason: string?,
}

function PurchaseAnalytics.granted(
	purchaseId: string,
	productKey: string,
	productId: number,
	playerId: number,
	coins: number
): ReceiptEvent
	return {
		kind = "receipt_granted",
		purchaseId = purchaseId,
		productKey = productKey,
		productId = productId,
		playerId = playerId,
		coins = coins,
	}
end

function PurchaseAnalytics.duplicate(purchaseId: string, playerId: number): ReceiptEvent
	return {
		kind = "receipt_duplicate",
		purchaseId = purchaseId,
		playerId = playerId,
		reason = "PurchaseId already recorded",
	}
end

function PurchaseAnalytics.deferred(purchaseId: string, reason: string): ReceiptEvent
	return {
		kind = "receipt_deferred",
		purchaseId = purchaseId,
		reason = reason,
	}
end

function PurchaseAnalytics.unknownProduct(purchaseId: string, productId: number): ReceiptEvent
	return {
		kind = "receipt_unknown_product",
		purchaseId = purchaseId,
		productId = productId,
		reason = "no matching product in MonetisationConfig",
	}
end

return PurchaseAnalytics
