--!strict
--[[
	Тесты валидации ремоутов.

	Пишутся с позиции атакующего: что можно прислать в ремоут, чтобы
	уронить сервер, подвесить его или получить лишние деньги.
]]

local Validate = require("../src/shared/Economy/Validate")
local EconomyConfig = require("../src/shared/Economy/EconomyConfig")

local upgrades = EconomyConfig.upgrades

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("integerInRange", function()
		it("принимает целое внутри диапазона", function()
			expect(Validate.integerInRange(5, 1, 10)).toBeTruthy()
		end)

		it("принимает границы диапазона", function()
			expect(Validate.integerInRange(1, 1, 10)).toBeTruthy()
			expect(Validate.integerInRange(10, 1, 10)).toBeTruthy()
		end)

		it("отклоняет выход за границы", function()
			expect(Validate.integerInRange(0, 1, 10)).toBeFalsy()
			expect(Validate.integerInRange(11, 1, 10)).toBeFalsy()
		end)

		it("отклоняет дробное", function()
			-- 2.5 в цикле "купить N раз" даёт неожиданное число итераций
			expect(Validate.integerInRange(2.5, 1, 10)).toBeFalsy()
		end)

		it("отклоняет nil", function()
			expect(Validate.integerInRange(nil, 1, 10)).toBeFalsy()
		end)

		it("отклоняет строку", function()
			expect(Validate.integerInRange("5", 1, 10)).toBeFalsy()
		end)

		it("отклоняет таблицу", function()
			expect(Validate.integerInRange({}, 1, 10)).toBeFalsy()
		end)

		it("отклоняет булево", function()
			expect(Validate.integerInRange(true, 1, 10)).toBeFalsy()
		end)

		it("отклоняет NaN", function()
			expect(Validate.integerInRange(0 / 0, 1, 10)).toBeFalsy()
		end)

		--[[ math.huge % 1 даёт NaN, а не 0 — проверка на дробность его
		     не поймает, нужна отдельная. Классическая дыра. ]]
		it("отклоняет бесконечность", function()
			expect(Validate.integerInRange(math.huge, 1, 10)).toBeFalsy()
			expect(Validate.integerInRange(-math.huge, 1, 10)).toBeFalsy()
		end)

		it("возвращает текст ошибки", function()
			local ok, err = Validate.integerInRange(99, 1, 10)
			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
		end)
	end)

	describe("identifier", function()
		it("принимает нормальную строку", function()
			expect(Validate.identifier("Pickaxe")).toBeTruthy()
		end)

		it("отклоняет пустую строку", function()
			expect(Validate.identifier("")).toBeFalsy()
		end)

		it("отклоняет nil", function()
			expect(Validate.identifier(nil)).toBeFalsy()
		end)

		it("отклоняет число", function()
			expect(Validate.identifier(42)).toBeFalsy()
		end)

		it("отклоняет таблицу", function()
			expect(Validate.identifier({})).toBeFalsy()
		end)

		--[[ Эксплойтер может прислать строку в мегабайт, чтобы раздуть
		     логи и память сервера ]]
		it("отклоняет слишком длинную строку", function()
			expect(Validate.identifier(string.rep("a", 100_000))).toBeFalsy()
		end)
	end)

	describe("upgradeRequest", function()
		it("пропускает корректный запрос", function()
			local ok, err, upgrade, count = Validate.upgradeRequest(upgrades, "Pickaxe", 5)

			expect(ok).toBeTruthy()
			expect(err).toBeNil()
			expect(upgrade).toBeTruthy()
			expect(count).toBe(5)
		end)

		it("возвращает найденный конфиг апгрейда", function()
			local _, _, upgrade = Validate.upgradeRequest(upgrades, "Drill", 1)
			expect(upgrade.id).toBe("Drill")
		end)

		it("отклоняет неизвестный апгрейд", function()
			local ok, err = Validate.upgradeRequest(upgrades, "НесуществующийАпгрейд", 1)
			expect(ok).toBeFalsy()
			expect(err).toBeTruthy()
		end)

		it("отклоняет нулевое количество", function()
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", 0)).toBeFalsy()
		end)

		it("отклоняет отрицательное количество", function()
			-- Без этой проверки покупка -10 уровней могла бы НАЧИСЛИТЬ денег
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", -10)).toBeFalsy()
		end)

		--[[ Без потолка вызов с count = 1e9 отправит сервер в цикл
		     на миллиард итераций и подвесит весь сервер, а не одного игрока ]]
		it("отклоняет запредельное количество", function()
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", 1e9)).toBeFalsy()
		end)

		it("принимает ровно максимальный размер пакета", function()
			expect(Validate.upgradeRequest(upgrades, "Pickaxe", Validate.MAX_BATCH)).toBeTruthy()
		end)

		it("отклоняет пропущенные аргументы", function()
			expect(Validate.upgradeRequest(upgrades, nil, nil)).toBeFalsy()
		end)

		it("отклоняет аргументы не того типа", function()
			expect(Validate.upgradeRequest(upgrades, {}, {})).toBeFalsy()
		end)

		--[[
			Попытка достучаться до служебных полей таблицы через ремоут.
			Проверка существования обязана идти после проверки типа, иначе
			индексация произвольным значением даст неожиданный результат.
		]]
		it("не даёт вытащить служебные поля таблицы", function()
			expect(Validate.upgradeRequest(upgrades, "__index", 1)).toBeFalsy()
			expect(Validate.upgradeRequest(upgrades, "__metatable", 1)).toBeFalsy()
		end)
	end)
end
