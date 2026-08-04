--!strict
--[[
	Тесты кошелька.

	Смысловой центр — то, что баланс невозможно увести в минус и невозможно
	изменить в обход класса. Отдельно проверяется атомарность: неудачная
	операция обязана не оставлять следов.
]]

local Wallet = require("../src/shared/Economy/Wallet")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("создание", function()
		it("пустой кошелёк отдаёт нули", function()
			local wallet = Wallet.new()
			expect(wallet:get("Coins")).toBe(0)
		end)

		it("принимает стартовый баланс", function()
			local wallet = Wallet.new({ Coins = 500, Gems = 10 })
			expect(wallet:get("Coins")).toBe(500)
			expect(wallet:get("Gems")).toBe(10)
		end)

		--[[
			Сейв мог прийти битым — с NaN, отрицательным числом или мусором
			после неудачной миграции. Вход в игру от этого падать не должен:
			лучше обнулить валюту, чем не пустить игрока.
		]]
		it("чинит битые значения из сейва вместо падения", function()
			local wallet = Wallet.new({ Coins = -100, Gems = 0 / 0, Tickets = math.huge })
			expect(wallet:get("Coins")).toBe(0)
			expect(wallet:get("Gems")).toBe(0)
			expect(wallet:get("Tickets")).toBe(0)
		end)

		--[[
			Если бы конструктор взял ссылку на переданную таблицу, вызывающий
			код мог бы менять баланс мимо всех проверок.
		]]
		it("копирует стартовую таблицу, а не берёт ссылку", function()
			local initial = { Coins = 100 }
			local wallet = Wallet.new(initial)

			initial.Coins = 999_999

			expect(wallet:get("Coins")).toBe(100)
		end)
	end)

	describe("add", function()
		it("начисляет", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:add("Coins", 50)

			expect(ok).toBeTruthy()
			expect(wallet:get("Coins")).toBe(150)
		end)

		it("создаёт валюту, которой ещё не было", function()
			local wallet = Wallet.new()
			wallet:add("Gems", 7)
			expect(wallet:get("Gems")).toBe(7)
		end)

		--[[
			Ключевая защита: если бы add принимал минус, любая проверка
			"хватает ли денег" обходилась бы вызовом add(-amount).
		]]
		it("отказывает на отрицательной сумме", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok, err = wallet:add("Coins", -50)

			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		it("отказывает на NaN", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:add("Coins", 0 / 0)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		it("отказывает на бесконечности", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:add("Coins", math.huge)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		--[[
			За 2^53 double перестаёт различать соседние целые. Молча уехать
			туда нельзя: игрок увидит, что покупки не списываются.
		]]
		it("сообщает о достижении потолка", function()
			local wallet = Wallet.new({ Coins = 2 ^ 53 })
			local ok, err = wallet:add("Coins", 1000)

			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
		end)
	end)

	describe("trySpend", function()
		it("списывает, когда денег хватает", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:trySpend("Coins", 30)

			expect(ok).toBeTruthy()
			expect(wallet:get("Coins")).toBe(70)
		end)

		it("списывает ровно весь баланс", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:trySpend("Coins", 100)

			expect(ok).toBeTruthy()
			expect(wallet:get("Coins")).toBe(0)
		end)

		--[[
			Самое важное свойство класса: при нехватке денег баланс не
			меняется вообще. Частичное списание оставило бы игрока и без
			денег, и без покупки.
		]]
		it("при нехватке средств не трогает баланс", function()
			local wallet = Wallet.new({ Coins = 50 })
			local ok, err = wallet:trySpend("Coins", 100)

			expect(ok).toBeFalsy()
			expect(err).toBe("недостаточно средств")
			expect(wallet:get("Coins")).toBe(50)
		end)

		it("не даёт списать с несуществующей валюты", function()
			local wallet = Wallet.new()
			local ok = wallet:trySpend("Coins", 1)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(0)
		end)

		it("отказывает на отрицательной сумме", function()
			local wallet = Wallet.new({ Coins = 100 })
			local ok = wallet:trySpend("Coins", -50)

			expect(ok).toBeFalsy()
			expect(wallet:get("Coins")).toBe(100)
		end)

		it("баланс никогда не уходит в минус", function()
			local wallet = Wallet.new({ Coins = 10 })

			for _ = 1, 100 do
				wallet:trySpend("Coins", 3)
			end

			expect(wallet:get("Coins")).toBeGreaterThan(-1)
		end)
	end)

	describe("has", function()
		it("подтверждает достаточный баланс", function()
			local wallet = Wallet.new({ Coins = 100 })
			expect(wallet:has("Coins", 100)).toBeTruthy()
			expect(wallet:has("Coins", 99)).toBeTruthy()
		end)

		it("отклоняет недостаточный баланс", function()
			local wallet = Wallet.new({ Coins = 100 })
			expect(wallet:has("Coins", 101)).toBeFalsy()
		end)

		it("отклоняет некорректную сумму", function()
			local wallet = Wallet.new({ Coins = 100 })
			expect(wallet:has("Coins", 0 / 0)).toBeFalsy()
		end)
	end)

	describe("tryExchange", function()
		it("проводит обмен целиком", function()
			local wallet = Wallet.new({ Gems = 10, Coins = 0 })
			local ok = wallet:tryExchange("Gems", 5, "Coins", 500)

			expect(ok).toBeTruthy()
			expect(wallet:get("Gems")).toBe(5)
			expect(wallet:get("Coins")).toBe(500)
		end)

		--[[
			Атомарность: если списание прошло, а начисление нет, деньги
			исчезнут. Проверяем, что откат действительно происходит.
		]]
		it("откатывает списание, если начисление не прошло", function()
			local wallet = Wallet.new({ Gems = 10, Coins = 2 ^ 53 })
			local ok = wallet:tryExchange("Gems", 5, "Coins", 1000)

			expect(ok).toBeFalsy()
			expect(wallet:get("Gems")).toBe(10) -- гемы на месте
		end)

		it("не обменивает, когда нечего списывать", function()
			local wallet = Wallet.new({ Gems = 1 })
			local ok = wallet:tryExchange("Gems", 5, "Coins", 500)

			expect(ok).toBeFalsy()
			expect(wallet:get("Gems")).toBe(1)
			expect(wallet:get("Coins")).toBe(0)
		end)
	end)

	describe("serialize", function()
		it("отдаёт текущий баланс", function()
			local wallet = Wallet.new({ Coins = 100, Gems = 5 })
			expect(wallet:serialize()).toEqual({ Coins = 100, Gems = 5 })
		end)

		--[[
			Снимок уходит в сейв и в аналитику. Если бы это была внутренняя
			таблица, любой потребитель мог бы изменить баланс.
		]]
		it("отдаёт копию, а не внутреннюю таблицу", function()
			local wallet = Wallet.new({ Coins = 100 })
			local snapshot = wallet:serialize()

			snapshot.Coins = 999_999

			expect(wallet:get("Coins")).toBe(100)
		end)

		it("переживает цикл сохранения и загрузки", function()
			local original = Wallet.new({ Coins = 1234, Gems = 56 })
			local restored = Wallet.new(original:serialize())

			expect(restored:serialize()).toEqual(original:serialize())
		end)
	end)
end
