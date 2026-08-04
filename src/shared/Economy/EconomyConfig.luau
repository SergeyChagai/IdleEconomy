--!strict
--[[
	Конфигурация экономики.

	Здесь только данные — никакой логики и никаких require. Благодаря этому
	модуль одинаково грузится и в Roblox, и в Lune (тесты из консоли).

	Все кривые собраны в одном месте намеренно: баланс правится дизайнером,
	и правки не должны требовать чтения кода.
]]

export type UpgradeConfig = {
	id: string,
	displayName: string,
	-- Цена уровня N = baseCost * costGrowth ^ N
	baseCost: number,
	costGrowth: number,
	-- Доход в секунду = level * incomePerLevel * (множители)
	incomePerLevel: number,
	maxLevel: number,
}

export type PrestigeConfig = {
	-- Порог престижа P = baseRequirement * requirementGrowth ^ P
	baseRequirement: number,
	requirementGrowth: number,
	-- Множитель дохода = 1 + multiplierPerPrestige * P
	multiplierPerPrestige: number,
	maxPrestige: number,
}

export type OfflineConfig = {
	-- Сколько реального времени максимум засчитываем
	maxSeconds: number,
	-- Какую долю обычного дохода начисляем за оффлайн
	rateFactor: number,
	-- То же самое для владельцев геймпасса
	gamepassMaxSeconds: number,
	gamepassRateFactor: number,
	-- Меньше этого времени вообще игнорируем (защита от спама реконнектом)
	minSeconds: number,
}

export type ClickConfig = {
	-- Базовая награда за клик, умножается на множитель престижа
	baseValue: number,
	-- Запас на всплеск: столько кликов подряд разрешено
	burstCapacity: number,
	-- Устойчивый темп восстановления, кликов в секунду
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
			displayName = "Кирка",
			baseCost = 50,
			costGrowth = 1.15,
			incomePerLevel = 1.5,
			maxLevel = 500,
		},

		Backpack = {
			id = "Backpack",
			displayName = "Рюкзак",
			baseCost = 250,
			costGrowth = 1.22,
			incomePerLevel = 6,
			maxLevel = 300,
		},

		Drill = {
			id = "Drill",
			displayName = "Бур",
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

	-- Ручная добыча: то, с чего игрок начинает, пока нет пассивного дохода.
	-- Темп подобран так, чтобы живой человек (5-8 кликов/с) не упирался
	-- в лимит, а автокликер упирался сразу.
	click = {
		baseValue = 5,
		burstCapacity = 12,
		refillPerSecond = 8,
	},
}

return EconomyConfig
