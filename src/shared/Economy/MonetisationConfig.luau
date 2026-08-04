--!strict
--[[
	Monetisation configuration.

	Data only -- no logic and no `require` (ADR-0001). Product and gamepass
	numeric ids are placeholders (0): replace them with the ids from Creator
	Dashboard before going live. A zero id is treated as "not configured" by
	the service layer, so a mis-set catalog cannot accidentally grant.
]]

export type GamepassConfig = {
	-- Roblox gamepass asset id. 0 = not configured.
	id: number,
	-- Multiplies passive and click income while owned
	incomeMultiplier: number,
	-- When true, Balance.offlineEarnings uses the gamepass cap/rate
	boostsOffline: boolean,
}

export type ProductConfig = {
	-- Developer product id. 0 = not configured.
	productId: number,
	-- Coins granted on a successful, first-time ProcessReceipt
	coins: number,
}

export type MonetisationConfig = {
	gamepasses: { [string]: GamepassConfig },
	products: { [string]: ProductConfig },
	-- How many PurchaseIds to retain in the save
	purchaseHistoryLimit: number,
}

local MonetisationConfig: MonetisationConfig = {
	gamepasses = {
		-- Double income + full-rate offline window
		Vip = {
			id = 0,
			incomeMultiplier = 2,
			boostsOffline = true,
		},
	},

	products = {
		CoinsSmall = {
			productId = 0,
			coins = 5_000,
		},
		CoinsMedium = {
			productId = 0,
			coins = 30_000,
		},
		CoinsLarge = {
			productId = 0,
			coins = 150_000,
		},
	},

	purchaseHistoryLimit = 100,
}

return MonetisationConfig
