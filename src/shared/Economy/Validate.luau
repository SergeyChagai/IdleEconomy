--!strict
--[[
	Валидация всего, что приходит от клиента.

	Базовое допущение: клиент враждебен. Любой аргумент ремоута может
	оказаться nil, таблицей, NaN, отрицательным, дробным или строкой длиной
	в мегабайт — эксплойтеру ничего не стоит вызвать ремоут напрямую.

	Логика вынесена из сервиса в чистый модуль сознательно: так её видно
	целиком в одном месте и можно прогнать тестами без запуска Roblox.
	Проверки безопасности — последнее, что стоит тестировать вручную.
]]

-- Потолок на пакетную покупку. Нужен не ради баланса, а чтобы вызов
-- с count = 1e9 не увёл сервер в долгий цикл.
local MAX_BATCH = 1000

-- Длиннее любого осмысленного id; отсекает попытки прислать мегабайтную строку
local MAX_ID_LENGTH = 64

export type UpgradeConfig = {
	id: string,
	displayName: string,
	baseCost: number,
	costGrowth: number,
	incomePerLevel: number,
	maxLevel: number,
}

local Validate = {}

Validate.MAX_BATCH = MAX_BATCH

--[[
	Целое число в заданных границах.

	Отдельно проверяем NaN (не равен сам себе) и дробную часть: `count`
	вроде 2.5 при использовании в цикле даст неожиданное поведение,
	а `math.huge` подвесит сервер.
]]
function Validate.integerInRange(value: unknown, min: number, max: number): (boolean, string?)
	if type(value) ~= "number" then
		return false, `ожидалось число, пришло {typeof(value)}`
	end

	if value ~= value then
		return false, "значение NaN"
	end

	if value == math.huge or value == -math.huge then
		return false, "значение бесконечно"
	end

	if value % 1 ~= 0 then
		return false, `ожидалось целое, пришло {value}`
	end

	if value < min or value > max then
		return false, `значение {value} вне диапазона [{min}, {max}]`
	end

	return true
end

--[[ Строковый идентификатор: тип, непустота, разумная длина ]]
function Validate.identifier(value: unknown): (boolean, string?)
	if type(value) ~= "string" then
		return false, `ожидалась строка, пришло {typeof(value)}`
	end

	if #value == 0 then
		return false, "пустой идентификатор"
	end

	if #value > MAX_ID_LENGTH then
		return false, `идентификатор длиннее {MAX_ID_LENGTH} символов`
	end

	return true
end

--[[
	Полная проверка запроса на покупку апгрейда.

	Возвращает (ok, err, upgrade, count) — при успехе отдаём уже найденный
	конфиг апгрейда, чтобы сервис не искал его второй раз.
]]
function Validate.upgradeRequest(
	upgrades: { [string]: UpgradeConfig },
	upgradeId: unknown,
	count: unknown
): (boolean, string?, UpgradeConfig?, number?)
	local idOk, idError = Validate.identifier(upgradeId)
	if not idOk then
		return false, `upgradeId: {idError}`
	end

	-- Проверка существования идёт ПОСЛЕ проверки типа: индексировать
	-- таблицу произвольным значением от клиента нельзя
	local upgrade = upgrades[upgradeId :: string]
	if not upgrade then
		return false, `неизвестный апгрейд: {upgradeId :: string}`
	end

	local countOk, countError = Validate.integerInRange(count, 1, MAX_BATCH)
	if not countOk then
		return false, `count: {countError}`
	end

	return true, nil, upgrade, count :: number
end

return Validate
