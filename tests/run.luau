--!strict
--[[
	Entry point for running the suite in Lune.

	    lune run tests/run

	Exit code: 0 -- everything passed, 1 -- there were failures. That matters:
	it is how CI tells a green build from a red one.
]]

local process = require("@lune/process")

local TestRunner = require("./lib/TestRunner")

local specs = {
	Balance = require("./Balance.spec"),
	Wallet = require("./Wallet.spec"),
	Validate = require("./Validate.spec"),
	RateLimiter = require("./RateLimiter.spec"),
	Profile = require("./Profile.spec"),
	PurchaseLedger = require("./PurchaseLedger.spec"),
	PurchaseAnalytics = require("./PurchaseAnalytics.spec"),
}

print("Economy test suite\n" .. string.rep("=", 50))

local passed, failed, failures = TestRunner.run(specs)

print("\n" .. string.rep("=", 50))

if failed > 0 then
	print(`\nFailures ({failed}):\n`)
	for _, failure in failures do
		print(`  {failure.path}`)
		print(`    {failure.message}\n`)
	end
end

print(`Total: {passed} passed, {failed} failed`)

process.exit(if failed > 0 then 1 else 0)
