--!strict
--[[
	Economy configuration.

	Data only -- no logic and no `require`. That is what lets this module load
	both inside Roblox and inside Lune, where the tests run.

	Every curve lives here on purpose: balance is tuned by a designer, and
	tuning must not require reading code.
]]

export type UpgradeConfig = {
	id: string,
	displayName: string,
	-- Price of level N = baseCost * costGrowth ^ N
	baseCost: number,
	costGrowth: number,
	-- Income per second = level * incomePerLevel * (multipliers)
	incomePerLevel: number,
	maxLevel: number,
}

export type PrestigeConfig = {
	-- Threshold for prestige P = baseRequirement * requirementGrowth ^ P
	baseRequirement: number,
	requirementGrowth: number,
	-- Income multiplier = 1 + multiplierPerPrestige * P
	multiplierPerPrestige: number,
	maxPrestige: number,
}

export type OfflineConfig = {
	-- Upper bound on how much real time is ever credited
	maxSeconds: number,
	-- Fraction of normal income granted while offline
	rateFactor: number,
	-- The same two knobs for gamepass owners
	gamepassMaxSeconds: number,
	gamepassRateFactor: number,
	-- Absences shorter than this are ignored (reconnect-farming guard)
	minSeconds: number,
}

export type ClickConfig = {
	-- Base reward per click, scaled by the prestige multiplier
	baseValue: number,
	-- Burst allowance: how many clicks in a row are accepted
	burstCapacity: number,
	-- Sustained refill rate, clicks per second
	refillPerSecond: number,
}

export type EconomyConfig = {
	upgrades: { [string]: UpgradeConfig },
	prestige: PrestigeConfig,
	offline: OfflineConfig,
	click: ClickConfig,
}

local EconomyConfig: EconomyConfig = {
	upgrades = {
		Pickaxe = {
			id = "Pickaxe",
			displayName = "Pickaxe",
			baseCost = 50,
			costGrowth = 1.15,
			incomePerLevel = 1.5,
			maxLevel = 500,
		},

		Backpack = {
			id = "Backpack",
			displayName = "Backpack",
			baseCost = 250,
			costGrowth = 1.22,
			incomePerLevel = 6,
			maxLevel = 300,
		},

		Drill = {
			id = "Drill",
			displayName = "Drill",
			baseCost = 10_000,
			costGrowth = 1.35,
			incomePerLevel = 90,
			maxLevel = 150,
		},
	},

	prestige = {
		baseRequirement = 1_000_000,
		requirementGrowth = 5,
		multiplierPerPrestige = 0.25,
		maxPrestige = 50,
	},

	offline = {
		maxSeconds = 8 * 3600,
		rateFactor = 0.5,
		gamepassMaxSeconds = 24 * 3600,
		gamepassRateFactor = 1.0,
		minSeconds = 60,
	},

	-- Manual mining: the only income source before anything is bought.
	-- Tuned so a human (5-8 clicks/s) never hits the limit while an
	-- autoclicker hits it immediately.
	click = {
		baseValue = 5,
		burstCapacity = 12,
		refillPerSecond = 8,
	},
}

return EconomyConfig
