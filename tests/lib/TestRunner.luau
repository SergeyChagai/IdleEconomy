--!strict
--[[
	Минимальный тест-раннер в духе TestEZ/Jest.

	Написан руками, а не взят готовым, по одной причине: он должен работать
	в Lune без единой зависимости. Сорок строк логики против ещё одного
	пакета в проекте — размен в пользу сорока строк.

	Использование в spec-файле:

		return function(t)
			t.describe("группа", function()
				t.it("что-то делает", function()
					t.expect(2 + 2).toBe(4)
				end)
			end)
		end
]]

export type Matchers = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: number, tolerance: number?) -> (),
	toBeGreaterThan: (expected: number) -> (),
	toBeLessThan: (expected: number) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toThrow: () -> (),
}

export type Context = {
	describe: (name: string, body: () -> ()) -> (),
	it: (name: string, body: () -> ()) -> (),
	expect: (value: any) -> Matchers,
}

local TestRunner = {}

--[[ Сравнение ]]

local function describeValue(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

-- Рекурсивное сравнение таблиц по значению
local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end

	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end

	for key, valueA in a :: { [any]: any } do
		if not deepEqual(valueA, (b :: { [any]: any })[key]) then
			return false
		end
	end

	for key in b :: { [any]: any } do
		if (a :: { [any]: any })[key] == nil then
			return false
		end
	end

	return true
end

--[[ Запуск ]]

type Failure = {
	path: string,
	message: string,
}

function TestRunner.run(specs: { [string]: (Context) -> () }): (number, number, { Failure })
	local passed = 0
	local failed = 0
	local failures: { Failure } = {}

	-- Стек имён групп: нужен, чтобы в отчёте было видно полный путь до теста
	local groups: { string } = {}

	local function currentPath(name: string): string
		local parts = table.clone(groups)
		table.insert(parts, name)
		return table.concat(parts, " > ")
	end

	local context: Context

	local function expect(value: any): Matchers
		local function fail(message: string): ()
			error(message, 3)
		end

		return {
			toBe = function(expected: any)
				if value ~= expected then
					fail(`ожидалось {describeValue(expected)}, получено {describeValue(value)}`)
				end
			end,

			toEqual = function(expected: any)
				if not deepEqual(value, expected) then
					fail(`структуры не совпали: ожидалось {describeValue(expected)}, получено {describeValue(value)}`)
				end
			end,

			toBeCloseTo = function(expected: number, tolerance: number?)
				local eps = tolerance or 1e-9
				local diff = math.abs(value - expected)
				if diff > eps then
					fail(`ожидалось ~{expected} (допуск {eps}), получено {value}, расхождение {diff}`)
				end
			end,

			toBeGreaterThan = function(expected: number)
				if not (value > expected) then
					fail(`ожидалось значение больше {expected}, получено {value}`)
				end
			end,

			toBeLessThan = function(expected: number)
				if not (value < expected) then
					fail(`ожидалось значение меньше {expected}, получено {value}`)
				end
			end,

			toBeTruthy = function()
				if not value then
					fail(`ожидалось истинное значение, получено {describeValue(value)}`)
				end
			end,

			toBeFalsy = function()
				if value then
					fail(`ожидалось ложное значение, получено {describeValue(value)}`)
				end
			end,

			toBeNil = function()
				if value ~= nil then
					fail(`ожидался nil, получено {describeValue(value)}`)
				end
			end,

			toThrow = function()
				if type(value) ~= "function" then
					fail("toThrow применим только к функции")
				end
				local ok = pcall(value)
				if ok then
					fail("ожидалась ошибка, но вызов прошёл успешно")
				end
			end,
		}
	end

	local function describe(name: string, body: () -> ())
		table.insert(groups, name)
		body()
		table.remove(groups)
	end

	local function it(name: string, body: () -> ())
		local path = currentPath(name)
		local ok, err = pcall(body)

		if ok then
			passed += 1
			print(`  ok    {path}`)
		else
			failed += 1
			local message = tostring(err)
			table.insert(failures, { path = path, message = message })
			print(`  FAIL  {path}`)
		end
	end

	context = { describe = describe, it = it, expect = expect }

	for specName, spec in specs do
		print(`\n[{specName}]`)
		local ok, err = pcall(spec, context)
		if not ok then
			failed += 1
			table.insert(failures, {
				path = specName,
				message = `spec-файл упал целиком: {tostring(err)}`,
			})
			print(`  FAIL  {specName} (файл не выполнился)`)
		end
	end

	return passed, failed, failures
end

return TestRunner
