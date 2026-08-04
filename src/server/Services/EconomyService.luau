--!strict
--[[
	EconomyService — сервер владеет экономикой целиком.

	Правила, которым подчинён весь модуль:

	  1. Состояние живёт только здесь. Клиенту уходят числа для показа,
	     но ни одно решение не принимается на клиенте.
	  2. Каждый аргумент из ремоута проходит Validate. Клиент враждебен.
	  3. Клиент никогда не присылает СТОИМОСТЬ или РЕЗУЛЬТАТ — только
	     намерение ("хочу купить N уровней Pickaxe"). Цену считает сервер.

	Третий пункт — тот, на котором чаще всего валятся тестовые: если
	ремоут принимает `cost` или `reward`, эксплойтер пришлёт свои значения.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit.Knit)

local Economy = ReplicatedStorage.Shared.Economy
local Balance = require(Economy.Balance)
local EconomyConfig = require(Economy.EconomyConfig)
local RateLimiter = require(Economy.RateLimiter)
local Validate = require(Economy.Validate)
local Wallet = require(Economy.Wallet)

local CURRENCY = "Coins"
local INCOME_TICK = 1 -- как часто начисляем пассивный доход, секунд

type PlayerState = {
	wallet: Wallet.Wallet,
	levels: { [string]: number },
	prestigeCount: number,
	lifetimeEarned: number,
	-- Свой лимитер на каждого игрока: общий позволил бы одному
	-- эксплойтеру заблокировать добычу всему серверу
	clickLimiter: RateLimiter.RateLimiter,
}

export type PublicState = {
	coins: number,
	levels: { [string]: number },
	prestigeCount: number,
	prestigeMultiplier: number,
	prestigeRequirement: number,
	lifetimeEarned: number,
	incomePerSecond: number,
}

local EconomyService = Knit.CreateService({
	Name = "EconomyService",

	-- Единственное место, где живёт состояние игроков
	_states = {} :: { [Player]: PlayerState },

	Client = {
		-- Сервер сам сообщает клиенту новое состояние; клиент не опрашивает
		StateChanged = Knit.CreateSignal(),
	},
})

--[[ Внутреннее ]]

local function createState(): PlayerState
	local levels: { [string]: number } = {}
	for id in EconomyConfig.upgrades do
		levels[id] = 0
	end

	return {
		wallet = Wallet.new({ [CURRENCY] = 0 }),
		levels = levels,
		prestigeCount = 0,
		lifetimeEarned = 0,
		clickLimiter = RateLimiter.new(
			EconomyConfig.click.burstCapacity,
			EconomyConfig.click.refillPerSecond,
			os.clock()
		),
	}
end

function EconomyService:_getState(player: Player): PlayerState?
	return self._states[player]
end

--[[ Публичный снимок состояния для клиента.

     Отдаём именно снимок, а не внутреннюю таблицу: иначе изменения
     на сервере утекали бы клиенту незаметно для нас, а главное — клиент
     получил бы поля, которые ему знать незачем. ]]
function EconomyService:_publicState(state: PlayerState): PublicState
	local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)

	local levels: { [string]: number } = {}
	for id, level in state.levels do
		levels[id] = level
	end

	return {
		coins = state.wallet:get(CURRENCY),
		levels = levels,
		prestigeCount = state.prestigeCount,
		prestigeMultiplier = multiplier,
		prestigeRequirement = Balance.prestigeRequirement(
			EconomyConfig.prestige,
			state.prestigeCount
		),
		lifetimeEarned = state.lifetimeEarned,
		incomePerSecond = Balance.totalIncomePerSecond(
			EconomyConfig.upgrades,
			state.levels,
			multiplier
		),
	}
end

function EconomyService:_push(player: Player)
	local state = self:_getState(player)
	if state then
		self.Client.StateChanged:Fire(player, self:_publicState(state))
	end
end

--[[ Серверный API ]]

--[[
	Покупка уровней апгрейда.

	Возвращает (ok, err) — текст ошибки уходит клиенту как есть, ничего
	секретного в нём нет, зато отладка становится осмысленной.
]]
function EconomyService:BuyUpgrade(player: Player, upgradeId: string, count: number): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "профиль игрока не загружен"
	end

	local ok, err, upgrade, safeCount = Validate.upgradeRequest(
		EconomyConfig.upgrades,
		upgradeId,
		count
	)
	if not ok then
		return false, err
	end
	assert(upgrade and safeCount, "валидатор вернул ok без данных")

	local currentLevel = state.levels[upgrade.id] or 0

	-- Обрезаем по потолку уровня, а не отказываем: игрок нажал "купить 10",
	-- а до максимума осталось 3 — продаём 3, это ожидаемое поведение
	local available = upgrade.maxLevel - currentLevel
	if available <= 0 then
		return false, "достигнут максимальный уровень"
	end

	local levelsToBuy = math.min(safeCount, available)

	-- Цену считает СЕРВЕР. Клиент прислал только количество.
	local price = Balance.totalUpgradeCost(upgrade, currentLevel, levelsToBuy)

	local spent, spendError = state.wallet:trySpend(CURRENCY, price)
	if not spent then
		return false, spendError
	end

	state.levels[upgrade.id] = currentLevel + levelsToBuy
	self:_push(player)

	return true
end

--[[
	Ручная добыча по клику.

	Это единственный источник дохода на старте: пассивный доход идёт только
	с купленных уровней, а купить их не на что, пока нет денег.

	Награду считает сервер, клиент не присылает ничего вообще — у ремоута
	нет аргументов, подделывать нечего. Единственная защита, которая тут
	нужна, — частота вызовов.
]]
function EconomyService:Collect(player: Player): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "профиль игрока не загружен"
	end

	-- os.clock монотонен и не прыгает при коррекции системных часов
	if not state.clickLimiter:tryConsume(os.clock()) then
		return false, "слишком часто"
	end

	local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)
	local reward = EconomyConfig.click.baseValue * multiplier

	local ok, err = state.wallet:add(CURRENCY, reward)
	if not ok then
		return false, err
	end

	state.lifetimeEarned += reward
	self:_push(player)

	return true
end

--[[ Покупка максимума, который игрок может себе позволить ]]
function EconomyService:BuyMaxUpgrade(player: Player, upgradeId: string): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "профиль игрока не загружен"
	end

	local idOk, idError = Validate.identifier(upgradeId)
	if not idOk then
		return false, idError
	end

	local upgrade = EconomyConfig.upgrades[upgradeId]
	if not upgrade then
		return false, "неизвестный апгрейд"
	end

	local currentLevel = state.levels[upgrade.id] or 0
	local levels = Balance.maxAffordableLevels(
		upgrade,
		currentLevel,
		state.wallet:get(CURRENCY)
	)

	if levels <= 0 then
		return false, "недостаточно средств"
	end

	return self:BuyUpgrade(player, upgradeId, levels)
end

--[[
	Престиж: сброс уровней в обмен на постоянный множитель.

	lifetimeEarned НЕ сбрасывается — по нему считается порог следующего
	престижа. Сбросить его значит выдать игроку бесконечный престиж.
]]
function EconomyService:Prestige(player: Player): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "профиль игрока не загружен"
	end

	if not Balance.canPrestige(EconomyConfig.prestige, state.lifetimeEarned, state.prestigeCount) then
		return false, "порог престижа не достигнут"
	end

	state.prestigeCount += 1
	state.wallet = Wallet.new({ [CURRENCY] = 0 })

	for id in EconomyConfig.upgrades do
		state.levels[id] = 0
	end

	self:_push(player)
	return true
end

--[[ Пассивный доход ]]

function EconomyService:_tick(deltaTime: number)
	for player, state in self._states do
		local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)
		local rate = Balance.totalIncomePerSecond(EconomyConfig.upgrades, state.levels, multiplier)

		if rate > 0 then
			local earned = rate * deltaTime
			state.wallet:add(CURRENCY, earned)
			state.lifetimeEarned += earned
			self:_push(player)
		end
	end
end

--[[ Клиентский API — всё, что доступно с клиента ]]

function EconomyService.Client:BuyUpgrade(player: Player, upgradeId: unknown, count: unknown)
	-- Типы приводим только после валидации внутри сервиса
	return self.Server:BuyUpgrade(player, upgradeId :: any, count :: any)
end

function EconomyService.Client:BuyMaxUpgrade(player: Player, upgradeId: unknown)
	return self.Server:BuyMaxUpgrade(player, upgradeId :: any)
end

function EconomyService.Client:Collect(player: Player)
	return self.Server:Collect(player)
end

function EconomyService.Client:Prestige(player: Player)
	return self.Server:Prestige(player)
end

function EconomyService.Client:GetState(player: Player): PublicState?
	local state = self.Server:_getState(player)
	return if state then self.Server:_publicState(state) else nil
end

--[[ Жизненный цикл Knit ]]

function EconomyService:KnitStart()
	local function onPlayerAdded(player: Player)
		-- ТУТ будет загрузка профиля (ProfileStore) и начисление
		-- оффлайн-дохода через Balance.offlineEarnings. Пока состояние
		-- создаётся с нуля — персистентность это отдельная система.
		self._states[player] = createState()
		self:_push(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- ТУТ будет сохранение профиля
		self._states[player] = nil
	end)

	task.spawn(function()
		while true do
			local deltaTime = task.wait(INCOME_TICK)
			self:_tick(deltaTime)
		end
	end)
end

return EconomyService
