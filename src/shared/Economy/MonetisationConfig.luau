--!strict
--[[
	Monetisation configuration.

	Data only -- no logic and no `require` (ADR-0001).

	HOW TO FILL IDS
	  1. Creator Dashboard → your experience → Monetization
	  2. Create the game pass / developer products listed below
	  3. Paste each numeric id over the matching `0`
	  4. See docs/monetisation.md for the Studio verification checklist

	A zero id means "not configured". MonetisationService ignores it so a
	clone of this repo cannot accidentally grant against a stranger's catalog.
]]

export type GamepassConfig = {
	-- Roblox gamepass asset id. 0 = not configured.
	id: number,
	displayName: string,
	-- Multiplies passive and click income while owned
	incomeMultiplier: number,
	-- When true, Balance.offlineEarnings uses the gamepass cap/rate
	boostsOffline: boolean,
}

export type ProductConfig = {
	-- Developer product id. 0 = not configured.
	productId: number,
	displayName: string,
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
			id = 0, -- TODO: paste Creator Dashboard game pass id
			displayName = "VIP",
			incomeMultiplier = 2,
			boostsOffline = true,
		},
	},

	products = {
		CoinsSmall = {
			productId = 0, -- TODO: paste developer product id
			displayName = "Coins Small",
			coins = 5_000,
		},
		CoinsMedium = {
			productId = 0, -- TODO: paste developer product id
			displayName = "Coins Medium",
			coins = 30_000,
		},
		CoinsLarge = {
			productId = 0, -- TODO: paste developer product id
			displayName = "Coins Large",
			coins = 150_000,
		},
	},

	purchaseHistoryLimit = 100,
}

return MonetisationConfig
