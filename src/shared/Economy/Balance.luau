--!strict
--[[
	Математика экономики: цены, доход, престиж, оффлайн-начисления.

	Модуль намеренно оставлен ЧИСТЫМ:
	  * нет require — грузится и в Roblox, и в Lune;
	  * нет глобального состояния — конфиг приходит аргументом;
	  * нет побочных эффектов — одни и те же входы дают один и тот же выход.

	Именно поэтому всё это покрывается юнит-тестами без запуска движка.
]]

export type UpgradeConfig = {
	id: string,
	displayName: string,
	baseCost: number,
	costGrowth: number,
	incomePerLevel: number,
	maxLevel: number,
}

local Balance = {}

--[[ Вспомогательное ]]

local function isFiniteNumber(value: number): boolean
	-- NaN не равен сам себе; бесконечности отсекаем сравнением
	return value == value and value ~= math.huge and value ~= -math.huge
end

--[[
	Цена ОДНОГО следующего уровня.

	Уровень 0 стоит baseCost, дальше умножается на costGrowth за каждый
	купленный уровень. Возвращаем нецелое число специально: округление
	делается только при показе. Если округлять здесь, сумма серии перестанет
	сходиться с суммой отдельных покупок, и игрок поймает расхождение.
]]
function Balance.upgradeCost(upgrade: UpgradeConfig, level: number): number
	if level < 0 then
		return 0
	end
	return upgrade.baseCost * upgrade.costGrowth ^ level
end

--[[
	Суммарная цена count уровней начиная с fromLevel.

	Это сумма геометрической прогрессии:
	    S = a * (g^n - 1) / (g - 1),   где a = цена первого уровня

	Считаем замкнутой формулой, а не циклом: при покупке "максимум за раз"
	count бывает в сотни уровней, и цикл на каждый клик — лишняя работа.
	Случай g = 1 (линейная цена) формулой не берётся, там деление на ноль.
]]
function Balance.totalUpgradeCost(upgrade: UpgradeConfig, fromLevel: number, count: number): number
	if count <= 0 then
		return 0
	end

	local first = Balance.upgradeCost(upgrade, fromLevel)
	local growth = upgrade.costGrowth

	if growth == 1 then
		return first * count
	end

	return first * (growth ^ count - 1) / (growth - 1)
end

--[[
	Сколько уровней игрок может купить на balance и сколько это будет стоить.

	Обращаем формулу суммы:
	    n = log(1 + balance * (g - 1) / a) / log(g)

	Замкнутая формула даёт ответ мгновенно, но у неё есть беда: на больших
	числах логарифм ошибается на единицу в последнем разряде, и игрок либо
	недополучит уровень, либо уйдёт в минус. Поэтому результат обязательно
	доводится проверкой в обе стороны — это дёшево (1-2 шага) и снимает
	весь класс ошибок округления.
]]
function Balance.maxAffordableLevels(
	upgrade: UpgradeConfig,
	currentLevel: number,
	balance: number
): (number, number)
	if balance <= 0 or currentLevel >= upgrade.maxLevel then
		return 0, 0
	end

	local first = Balance.upgradeCost(upgrade, currentLevel)
	if balance < first then
		return 0, 0
	end

	local growth = upgrade.costGrowth
	local levels: number

	if growth == 1 then
		levels = math.floor(balance / first)
	else
		levels = math.floor(math.log(1 + (balance * (growth - 1)) / first) / math.log(growth))
	end

	-- Больше, чем осталось до потолка, купить нельзя
	levels = math.min(levels, upgrade.maxLevel - currentLevel)
	levels = math.max(levels, 0)

	-- Доводка вниз: формула могла завысить
	while levels > 0 and Balance.totalUpgradeCost(upgrade, currentLevel, levels) > balance do
		levels -= 1
	end

	-- Доводка вверх: формула могла занизить
	while
		currentLevel + levels < upgrade.maxLevel
		and Balance.totalUpgradeCost(upgrade, currentLevel, levels + 1) <= balance
	do
		levels += 1
	end

	return levels, Balance.totalUpgradeCost(upgrade, currentLevel, levels)
end

--[[ Доход ]]

--[[
	Доход в секунду от одного апгрейда с учётом множителя престижа.
	На нулевом уровне апгрейд не приносит ничего.
]]
function Balance.incomePerSecond(upgrade: UpgradeConfig, level: number, multiplier: number): number
	if level <= 0 then
		return 0
	end
	local effectiveLevel = math.min(level, upgrade.maxLevel)
	return effectiveLevel * upgrade.incomePerLevel * multiplier
end

--[[
	Суммарный доход по всем апгрейдам игрока.
	Незнакомые ключи в levels игнорируются — их мог оставить старый сейв.
]]
function Balance.totalIncomePerSecond(
	upgrades: { [string]: UpgradeConfig },
	levels: { [string]: number },
	multiplier: number
): number
	local total = 0

	for id, upgrade in upgrades do
		local level = levels[id]
		if level then
			total += Balance.incomePerSecond(upgrade, level, multiplier)
		end
	end

	return total
end

--[[ Престиж ]]

export type PrestigeConfig = {
	baseRequirement: number,
	requirementGrowth: number,
	multiplierPerPrestige: number,
	maxPrestige: number,
}

--[[ Сколько всего нужно заработать, чтобы уйти в престиж номер prestigeCount + 1 ]]
function Balance.prestigeRequirement(config: PrestigeConfig, prestigeCount: number): number
	if prestigeCount >= config.maxPrestige then
		return math.huge -- потолок достигнут, дальше престижа нет
	end
	return config.baseRequirement * config.requirementGrowth ^ prestigeCount
end

--[[ Множитель дохода за уже набранные престижи. Линейный, не экспоненциальный:
     экспонента здесь ломает баланс через десяток престижей. ]]
function Balance.prestigeMultiplier(config: PrestigeConfig, prestigeCount: number): number
	local capped = math.min(prestigeCount, config.maxPrestige)
	return 1 + config.multiplierPerPrestige * capped
end

function Balance.canPrestige(
	config: PrestigeConfig,
	lifetimeEarned: number,
	prestigeCount: number
): boolean
	if prestigeCount >= config.maxPrestige then
		return false
	end
	return lifetimeEarned >= Balance.prestigeRequirement(config, prestigeCount)
end

--[[ Оффлайн-доход ]]

export type OfflineConfig = {
	maxSeconds: number,
	rateFactor: number,
	gamepassMaxSeconds: number,
	gamepassRateFactor: number,
	minSeconds: number,
}

--[[
	Начисление за время отсутствия.

	Возвращает (сумма, сколько секунд реально засчитано) — вторым значением,
	чтобы UI мог честно написать "начислено за 8 ч из 30 ч отсутствия".

	Защиты:
	  * отрицательный elapsed (часы игрока/сервера съехали) => 0;
	  * слишком короткое отсутствие => 0, иначе реконнект превращается
	    в фарм;
	  * потолок по времени, иначе вернувшийся через год ломает экономику.
]]
function Balance.offlineEarnings(
	config: OfflineConfig,
	ratePerSecond: number,
	elapsedSeconds: number,
	hasGamepass: boolean
): (number, number)
	if not isFiniteNumber(elapsedSeconds) or not isFiniteNumber(ratePerSecond) then
		return 0, 0
	end

	if elapsedSeconds < config.minSeconds or ratePerSecond <= 0 then
		return 0, 0
	end

	local maxSeconds = if hasGamepass then config.gamepassMaxSeconds else config.maxSeconds
	local factor = if hasGamepass then config.gamepassRateFactor else config.rateFactor

	local creditedSeconds = math.min(elapsedSeconds, maxSeconds)

	return ratePerSecond * creditedSeconds * factor, creditedSeconds
end

return Balance
