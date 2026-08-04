--!strict
--[[
	Тесты ограничителя частоты.

	Время подаётся вручную, поэтому вся проверка идёт мгновенно — ни одного
	ожидания в реальном времени. Именно ради этого время и вынесено
	в аргумент.
]]

local RateLimiter = require("../src/shared/Economy/RateLimiter")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("всплеск", function()
		it("пропускает запросы в пределах запаса", function()
			local limiter = RateLimiter.new(5, 1, 0)

			for _ = 1, 5 do
				expect(limiter:tryConsume(0)).toBeTruthy()
			end
		end)

		--[[ Главная проверка: сверх запаса в тот же момент времени
		     ничего не проходит. Это и отсекает автокликер. ]]
		it("отклоняет запрос сверх запаса", function()
			local limiter = RateLimiter.new(5, 1, 0)

			for _ = 1, 5 do
				limiter:tryConsume(0)
			end

			expect(limiter:tryConsume(0)).toBeFalsy()
		end)

		it("стартует с полным ведром", function()
			local limiter = RateLimiter.new(3, 1, 0)
			expect(limiter:available()).toBe(3)
		end)
	end)

	describe("восстановление", function()
		it("пополняется со временем", function()
			local limiter = RateLimiter.new(5, 2, 0)

			for _ = 1, 5 do
				limiter:tryConsume(0)
			end
			expect(limiter:tryConsume(0)).toBeFalsy()

			-- Прошла секунда, темп 2 в секунду -> 2 токена
			expect(limiter:tryConsume(1)).toBeTruthy()
			expect(limiter:tryConsume(1)).toBeTruthy()
			expect(limiter:tryConsume(1)).toBeFalsy()
		end)

		it("не копит сверх запаса", function()
			local limiter = RateLimiter.new(5, 10, 0)

			-- Прошёл час: при темпе 10/с накопилось бы 36000 токенов,
			-- и игрок получил бы право на огромный всплеск
			limiter:tryConsume(3600)

			expect(limiter:available()).toBeLessThan(5)
		end)

		it("устойчивый темп держится сколько угодно", function()
			local limiter = RateLimiter.new(5, 5, 0)
			local now = 0

			-- Ровно в темпе восстановления: должно проходить всегда
			for _ = 1, 100 do
				now += 0.2
				expect(limiter:tryConsume(now)).toBeTruthy()
			end
		end)

		it("темп выше разрешённого рано или поздно упирается", function()
			local limiter = RateLimiter.new(5, 5, 0)
			local now = 0
			local rejected = 0

			-- Втрое быстрее разрешённого
			for _ = 1, 100 do
				now += 0.066
				if not limiter:tryConsume(now) then
					rejected += 1
				end
			end

			expect(rejected).toBeGreaterThan(50)
		end)
	end)

	describe("устойчивость", function()
		--[[
			Часы сервера могут скорректироваться назад. Наивный расчёт
			даст отрицательное пополнение, ведро уйдёт в минус, и игрок
			окажется заблокирован надолго ни за что.
		]]
		it("время назад не загоняет ведро в минус", function()
			local limiter = RateLimiter.new(5, 1, 100)

			limiter:tryConsume(100)
			limiter:tryConsume(50) -- часы съехали назад

			expect(limiter:available()).toBeGreaterThan(-1)
			expect(limiter:tryConsume(50)).toBeTruthy()
		end)

		it("NaN во времени отклоняется", function()
			local limiter = RateLimiter.new(5, 1, 0)
			expect(limiter:tryConsume(0 / 0)).toBeFalsy()
		end)

		--[[ Без этой проверки бесконечное время дало бы бесконечное
		     пополнение и лимитер перестал бы что-либо ограничивать ]]
		it("бесконечное время отклоняется", function()
			local limiter = RateLimiter.new(5, 1, 0)
			expect(limiter:tryConsume(math.huge)).toBeFalsy()
		end)

		it("ведро не уходит ниже нуля при отказах", function()
			local limiter = RateLimiter.new(2, 1, 0)

			for _ = 1, 50 do
				limiter:tryConsume(0)
			end

			expect(limiter:available()).toBeGreaterThan(-0.001)
		end)
	end)
end
