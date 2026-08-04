--!strict
--[[
	Кошелёк игрока — ООП-класс поверх набора валют.

	Существует ровно затем, чтобы у баланса было ОДНО место записи. Пока
	валюта лежит просто числом в таблице, рано или поздно кто-нибудь сделает
	`profile.Coins -= price` без проверки, и баланс уйдёт в минус. Здесь
	любое изменение проходит через валидацию.

	Все методы, которые могут отказать, возвращают (ok, error) вместо того
	чтобы бросать исключение: отказ в оплате — штатная ситуация, а не сбой,
	и оборачивать каждую покупку в pcall не хочется.

	Модуль чистый: без require и без обращений к движку.
]]

-- Потолок, за которым double начинает терять единицы. 2^53 — предел, где
-- целые числа ещё представимы точно. Дальше баланс молча "залипает",
-- и игрок видит, что покупки не списываются.
local MAX_BALANCE = 2 ^ 53

export type CurrencyAmounts = { [string]: number }

type WalletFields = {
	_balances: CurrencyAmounts,
}

local Wallet = {}
Wallet.__index = Wallet

export type Wallet = typeof(setmetatable({} :: WalletFields, Wallet))

--[[ Валидация ]]

local function isValidAmount(amount: number): boolean
	if type(amount) ~= "number" then
		return false
	end
	if amount ~= amount then -- NaN
		return false
	end
	if amount == math.huge or amount == -math.huge then
		return false
	end
	return amount >= 0
end

--[[ Создание ]]

--[[
	initial — необязательный стартовый баланс. Копируем его, а не берём
	ссылку: иначе вызывающий код сможет менять баланс в обход класса.
]]
function Wallet.new(initial: CurrencyAmounts?): Wallet
	local balances: CurrencyAmounts = {}

	if initial then
		for currency, amount in initial do
			if isValidAmount(amount) then
				balances[currency] = math.min(amount, MAX_BALANCE)
			else
				-- Битое значение из сейва не должно ронять вход в игру
				balances[currency] = 0
			end
		end
	end

	return setmetatable({ _balances = balances }, Wallet)
end

--[[ Чтение ]]

function Wallet.get(self: Wallet, currency: string): number
	return self._balances[currency] or 0
end

function Wallet.has(self: Wallet, currency: string, amount: number): boolean
	if not isValidAmount(amount) then
		return false
	end
	return self:get(currency) >= amount
end

--[[ Снимок для сохранения. Возвращаем копию — наружу внутренняя таблица
     не уходит, иначе её изменят мимо класса. ]]
function Wallet.serialize(self: Wallet): CurrencyAmounts
	local snapshot: CurrencyAmounts = {}
	for currency, amount in self._balances do
		snapshot[currency] = amount
	end
	return snapshot
end

--[[ Изменение ]]

--[[
	Начислить. Отказывает на отрицательных и нечисловых суммах: списание
	должно идти через spend, иначе проверка "хватает ли денег" обходится
	вызовом add с минусом.
]]
function Wallet.add(self: Wallet, currency: string, amount: number): (boolean, string?)
	if not isValidAmount(amount) then
		return false, `некорректная сумма: {tostring(amount)}`
	end

	local current = self:get(currency)
	local updated = current + amount

	if updated > MAX_BALANCE then
		-- Обрезаем, но сообщаем: молча терять начисления нельзя
		self._balances[currency] = MAX_BALANCE
		return false, "достигнут потолок баланса"
	end

	self._balances[currency] = updated
	return true
end

--[[
	Списать, если хватает. Если не хватает — баланс НЕ меняется совсем.
	Это ключевое свойство: частичное списание оставило бы игрока без денег
	и без покупки.
]]
function Wallet.trySpend(self: Wallet, currency: string, amount: number): (boolean, string?)
	if not isValidAmount(amount) then
		return false, `некорректная сумма: {tostring(amount)}`
	end

	local current = self:get(currency)
	if current < amount then
		return false, "недостаточно средств"
	end

	self._balances[currency] = current - amount
	return true
end

--[[
	Атомарный перевод между валютами (например, обмен гемов на монеты).
	Либо проходят обе операции, либо ни одной.
]]
function Wallet.tryExchange(
	self: Wallet,
	fromCurrency: string,
	fromAmount: number,
	toCurrency: string,
	toAmount: number
): (boolean, string?)
	if not isValidAmount(fromAmount) or not isValidAmount(toAmount) then
		return false, "некорректная сумма обмена"
	end

	local ok, err = self:trySpend(fromCurrency, fromAmount)
	if not ok then
		return false, err
	end

	local added, addError = self:add(toCurrency, toAmount)
	if not added then
		-- Откатываем списание: до этой строки состояние уже изменено
		self:add(fromCurrency, fromAmount)
		return false, addError
	end

	return true
end

return Wallet
