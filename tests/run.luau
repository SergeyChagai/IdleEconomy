--!strict
--[[
	Точка входа для прогона тестов в Lune.

	    lune run tests/run

	Код возврата: 0 — все тесты прошли, 1 — есть падения. Это важно:
	по нему CI отличает зелёную сборку от красной.
]]

local process = require("@lune/process")

local TestRunner = require("./lib/TestRunner")

local specs = {
	Balance = require("./Balance.spec"),
	Wallet = require("./Wallet.spec"),
	Validate = require("./Validate.spec"),
	RateLimiter = require("./RateLimiter.spec"),
}

print("Прогон тестов экономики\n" .. string.rep("=", 50))

local passed, failed, failures = TestRunner.run(specs)

print("\n" .. string.rep("=", 50))

if failed > 0 then
	print(`\nПадения ({failed}):\n`)
	for _, failure in failures do
		print(`  {failure.path}`)
		print(`    {failure.message}\n`)
	end
end

print(`Итого: {passed} прошло, {failed} упало`)

process.exit(if failed > 0 then 1 else 0)
