--!strict
--[[
	Тесты математики экономики.

	Упор не на "функция что-то вернула", а на свойства, которые реально
	ломаются в проде: расхождение замкнутой формулы с поштучной покупкой,
	потолки, отрицательное время, эксплойт с реконнектом.
]]

local Balance = require("../src/shared/Economy/Balance")
local EconomyConfig = require("../src/shared/Economy/EconomyConfig")

local Pickaxe = EconomyConfig.upgrades.Pickaxe
local Drill = EconomyConfig.upgrades.Drill

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("upgradeCost", function()
		it("нулевой уровень стоит базовую цену", function()
			expect(Balance.upgradeCost(Pickaxe, 0)).toBe(Pickaxe.baseCost)
		end)

		it("растёт по геометрической прогрессии", function()
			local level5 = Balance.upgradeCost(Pickaxe, 5)
			local expected = Pickaxe.baseCost * Pickaxe.costGrowth ^ 5
			expect(level5).toBeCloseTo(expected)
		end)

		it("каждый следующий уровень дороже предыдущего", function()
			for level = 0, 50 do
				local current = Balance.upgradeCost(Pickaxe, level)
				local next_ = Balance.upgradeCost(Pickaxe, level + 1)
				expect(next_).toBeGreaterThan(current)
			end
		end)

		it("отрицательный уровень не роняет расчёт", function()
			expect(Balance.upgradeCost(Pickaxe, -1)).toBe(0)
		end)
	end)

	describe("totalUpgradeCost", function()
		--[[
			Главный тест всего модуля. Замкнутая формула суммы обязана
			совпадать с поштучным сложением — иначе игрок, купивший 10
			уровней разом, заплатит не столько же, сколько купивший их по
			одному. Такое расхождение находят за час после релиза.
		]]
		it("совпадает с поштучным суммированием", function()
			for _, upgrade in { Pickaxe, Drill } do
				for fromLevel = 0, 20 do
					local naive = 0
					for offset = 0, 9 do
						naive += Balance.upgradeCost(upgrade, fromLevel + offset)
					end

					local closed = Balance.totalUpgradeCost(upgrade, fromLevel, 10)

					-- Допуск относительный: на больших числах абсолютная
					-- разница растёт, а вот относительная обязана быть мизерной
					expect(math.abs(closed - naive) / naive).toBeLessThan(1e-9)
				end
			end
		end)

		it("ноль уровней стоит ноль", function()
			expect(Balance.totalUpgradeCost(Pickaxe, 5, 0)).toBe(0)
		end)

		it("отрицательное количество стоит ноль", function()
			expect(Balance.totalUpgradeCost(Pickaxe, 5, -3)).toBe(0)
		end)

		it("один уровень стоит ровно как upgradeCost", function()
			expect(Balance.totalUpgradeCost(Pickaxe, 7, 1)).toBeCloseTo(Balance.upgradeCost(Pickaxe, 7))
		end)

		it("работает при линейной цене (growth = 1)", function()
			-- Вырожденный случай: замкнутая формула делит на (g - 1)
			local linear = {
				id = "Linear",
				displayName = "Линейный",
				baseCost = 100,
				costGrowth = 1,
				incomePerLevel = 1,
				maxLevel = 999,
			}
			expect(Balance.totalUpgradeCost(linear, 0, 5)).toBe(500)
		end)
	end)

	describe("maxAffordableLevels", function()
		it("не покупает ничего, когда денег меньше первой цены", function()
			local levels, cost = Balance.maxAffordableLevels(Pickaxe, 0, Pickaxe.baseCost - 1)
			expect(levels).toBe(0)
			expect(cost).toBe(0)
		end)

		it("покупает ровно один уровень на цену одного уровня", function()
			local levels = Balance.maxAffordableLevels(Pickaxe, 0, Pickaxe.baseCost)
			expect(levels).toBe(1)
		end)

		--[[
			Свойство, ради которого функция и написана: купленное всегда
			по карману, а ещё один уровень — уже нет. Проверяем на широком
			диапазоне балансов, включая заведомо неудобные числа.
		]]
		it("возвращает максимум, который действительно по карману", function()
			local balances = { 50, 137, 1000, 99_999, 1e6, 1.5e7, 1e9 }

			for _, balance in balances do
				for _, startLevel in { 0, 3, 17, 60 } do
					local levels, cost = Balance.maxAffordableLevels(Pickaxe, startLevel, balance)

					-- Купленное укладывается в баланс
					expect(cost).toBeLessThan(balance + 1e-6)

					-- А ещё один уровень — уже нет (если не упёрлись в потолок)
					if startLevel + levels < Pickaxe.maxLevel then
						local withOneMore = Balance.totalUpgradeCost(Pickaxe, startLevel, levels + 1)
						expect(withOneMore).toBeGreaterThan(balance)
					end
				end
			end
		end)

		it("не даёт перепрыгнуть максимальный уровень", function()
			-- Денег заведомо больше, чем стоит вся ветка
			local levels = Balance.maxAffordableLevels(Pickaxe, 0, math.huge)
			expect(levels).toBe(Pickaxe.maxLevel)
		end)

		it("на максимальном уровне покупок нет", function()
			local levels = Balance.maxAffordableLevels(Pickaxe, Pickaxe.maxLevel, 1e12)
			expect(levels).toBe(0)
		end)

		it("отрицательный баланс не выдаёт уровней", function()
			local levels = Balance.maxAffordableLevels(Pickaxe, 0, -100)
			expect(levels).toBe(0)
		end)
	end)

	describe("incomePerSecond", function()
		it("нулевой уровень не приносит дохода", function()
			expect(Balance.incomePerSecond(Pickaxe, 0, 1)).toBe(0)
		end)

		it("линейно зависит от уровня", function()
			local one = Balance.incomePerSecond(Pickaxe, 1, 1)
			local ten = Balance.incomePerSecond(Pickaxe, 10, 1)
			expect(ten).toBeCloseTo(one * 10)
		end)

		it("учитывает множитель", function()
			local base = Balance.incomePerSecond(Pickaxe, 5, 1)
			local doubled = Balance.incomePerSecond(Pickaxe, 5, 2)
			expect(doubled).toBeCloseTo(base * 2)
		end)

		it("уровень выше потолка не даёт лишнего дохода", function()
			local atCap = Balance.incomePerSecond(Pickaxe, Pickaxe.maxLevel, 1)
			local overCap = Balance.incomePerSecond(Pickaxe, Pickaxe.maxLevel + 500, 1)
			expect(overCap).toBe(atCap)
		end)
	end)

	describe("totalIncomePerSecond", function()
		it("складывает доход всех апгрейдов", function()
			local levels = { Pickaxe = 10, Drill = 3 }
			local total = Balance.totalIncomePerSecond(EconomyConfig.upgrades, levels, 1)

			local expected = Balance.incomePerSecond(Pickaxe, 10, 1)
				+ Balance.incomePerSecond(Drill, 3, 1)

			expect(total).toBeCloseTo(expected)
		end)

		it("игнорирует неизвестные ключи из старого сейва", function()
			local levels = { Pickaxe = 5, ["RemovedUpgrade"] = 999 }
			local total = Balance.totalIncomePerSecond(EconomyConfig.upgrades, levels, 1)
			expect(total).toBeCloseTo(Balance.incomePerSecond(Pickaxe, 5, 1))
		end)

		it("пустой набор уровней даёт нулевой доход", function()
			expect(Balance.totalIncomePerSecond(EconomyConfig.upgrades, {}, 1)).toBe(0)
		end)
	end)

	describe("prestige", function()
		local prestige = EconomyConfig.prestige

		it("первый престиж требует базовый порог", function()
			expect(Balance.prestigeRequirement(prestige, 0)).toBe(prestige.baseRequirement)
		end)

		it("порог растёт с каждым престижем", function()
			local first = Balance.prestigeRequirement(prestige, 0)
			local second = Balance.prestigeRequirement(prestige, 1)
			expect(second).toBeGreaterThan(first)
		end)

		it("множитель без престижей равен единице", function()
			expect(Balance.prestigeMultiplier(prestige, 0)).toBe(1)
		end)

		it("множитель растёт линейно", function()
			local four = Balance.prestigeMultiplier(prestige, 4)
			local expected = 1 + prestige.multiplierPerPrestige * 4
			expect(four).toBeCloseTo(expected)
		end)

		it("множитель упирается в потолок престижа", function()
			local atCap = Balance.prestigeMultiplier(prestige, prestige.maxPrestige)
			local overCap = Balance.prestigeMultiplier(prestige, prestige.maxPrestige + 100)
			expect(overCap).toBe(atCap)
		end)

		it("не пускает в престиж без нужного заработка", function()
			expect(Balance.canPrestige(prestige, prestige.baseRequirement - 1, 0)).toBeFalsy()
		end)

		it("пускает ровно на пороге", function()
			expect(Balance.canPrestige(prestige, prestige.baseRequirement, 0)).toBeTruthy()
		end)

		it("на максимальном престиже больше не пускает", function()
			expect(Balance.canPrestige(prestige, math.huge, prestige.maxPrestige)).toBeFalsy()
		end)
	end)

	describe("offlineEarnings", function()
		local offline = EconomyConfig.offline

		it("начисляет за время отсутствия с понижающим коэффициентом", function()
			local rate = 100
			local elapsed = 3600
			local earned, credited = Balance.offlineEarnings(offline, rate, elapsed, false)

			expect(credited).toBe(elapsed)
			expect(earned).toBeCloseTo(rate * elapsed * offline.rateFactor)
		end)

		--[[
			Эксплойт, который ловят все idle-игры: игрок выходит и заходит
			раз в несколько секунд, каждый раз получая "оффлайн"-начисление.
			Порог minSeconds закрывает эту дыру.
		]]
		it("игнорирует слишком короткое отсутствие", function()
			local earned = Balance.offlineEarnings(offline, 100, offline.minSeconds - 1, false)
			expect(earned).toBe(0)
		end)

		it("обрезает время по потолку", function()
			local rate = 100
			local wayTooLong = offline.maxSeconds * 10
			local earned, credited = Balance.offlineEarnings(offline, rate, wayTooLong, false)

			expect(credited).toBe(offline.maxSeconds)
			expect(earned).toBeCloseTo(rate * offline.maxSeconds * offline.rateFactor)
		end)

		it("геймпасс поднимает и потолок, и коэффициент", function()
			local rate = 100
			local elapsed = offline.gamepassMaxSeconds

			local without = Balance.offlineEarnings(offline, rate, elapsed, false)
			local with = Balance.offlineEarnings(offline, rate, elapsed, true)

			expect(with).toBeGreaterThan(without)
		end)

		--[[
			Часы клиента и сервера расходятся, а в сейве лежит время
			последнего выхода. Отрицательная разница обязана давать ноль,
			а не отрицательное начисление, которое уведёт баланс в минус.
		]]
		it("отрицательное время не начисляет ничего", function()
			local earned = Balance.offlineEarnings(offline, 100, -5000, false)
			expect(earned).toBe(0)
		end)

		it("нулевой доход не начисляет ничего", function()
			local earned = Balance.offlineEarnings(offline, 0, 100_000, false)
			expect(earned).toBe(0)
		end)

		it("NaN во времени не ломает расчёт", function()
			local earned = Balance.offlineEarnings(offline, 100, 0 / 0, false)
			expect(earned).toBe(0)
		end)

		it("бесконечное время не ломает расчёт", function()
			local earned, credited = Balance.offlineEarnings(offline, 100, math.huge, false)
			expect(earned).toBe(0)
			expect(credited).toBe(0)
		end)
	end)
end
