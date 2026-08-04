--!strict
--[[
	Ограничитель частоты запросов — алгоритм "дырявое ведро с токенами".

	Нужен для ремоутов, которые вызывает сам игрок. Клик по кнопке добычи
	человек делает 5-8 раз в секунду, автокликер — 200, а скрипт-эксплойт
	вызывает ремоут напрямую тысячи раз. Без лимита это прямой путь
	к бесконечным деньгам.

	Почему ведро, а не "не чаще раза в N мс": человек кликает неровно —
	пачкой, потом пауза. Жёсткий интервал наказывает живого игрока и
	никак не мешает ровному автокликеру. Ведро наоборот: короткий всплеск
	разрешён (на то и запас), а вот держать высокий темп долго не выйдет.

	Время НЕ берётся внутри модуля, а приходит аргументом. Из-за этого
	класс остаётся чистым и тестируется без ожиданий в реальном времени.
]]

type RateLimiterFields = {
	_capacity: number,
	_refillPerSecond: number,
	_tokens: number,
	_lastRefill: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: RateLimiterFields, RateLimiter))

--[[
	capacity        — запас на всплеск (сколько кликов подряд разрешено)
	refillPerSecond — устойчивый темп восстановления
	now             — текущее время в секундах
]]
function RateLimiter.new(capacity: number, refillPerSecond: number, now: number): RateLimiter
	return setmetatable({
		_capacity = capacity,
		_refillPerSecond = refillPerSecond,
		_tokens = capacity, -- стартуем с полным ведром: первый клик не ждёт
		_lastRefill = now,
	}, RateLimiter)
end

--[[
	Попытка потратить один токен.

	Возвращает true, если запрос разрешён.

	Отдельно обрабатывается время, идущее назад: на сервере такое бывает
	при коррекции часов. Если просто посчитать elapsed, получится
	отрицательное пополнение и ведро уйдёт в минус — игрок окажется
	заблокирован надолго без всякой вины.
]]
function RateLimiter.tryConsume(self: RateLimiter, now: number): boolean
	-- NaN не равен сам себе; бесконечность даст бесконечное пополнение
	if now ~= now or now == math.huge or now == -math.huge then
		return false
	end

	local elapsed = now - self._lastRefill

	if elapsed < 0 then
		-- Часы съехали назад: не пополняем, но и не наказываем
		self._lastRefill = now
	else
		self._tokens = math.min(self._capacity, self._tokens + elapsed * self._refillPerSecond)
		self._lastRefill = now
	end

	if self._tokens < 1 then
		return false
	end

	self._tokens -= 1
	return true
end

--[[ Сколько токенов доступно сейчас. Для тестов и отладки. ]]
function RateLimiter.available(self: RateLimiter): number
	return self._tokens
end

return RateLimiter
