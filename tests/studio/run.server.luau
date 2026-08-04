--!strict
--[[
	Studio TestEZ runner (server).

	Waits for Knit, then discovers every `*.spec` under this script's sibling
	folder `server` (mapped by test.project.json). Only present in the test
	Rojo project -- production Play does not load this script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TestEZ = require(ReplicatedStorage.Packages.TestEZ)

Knit.OnStart()
	:andThen(function()
		-- Give DataService / EconomyService a beat to bind PlayerAdded
		task.wait(0.5)

		local roots = { ServerScriptService:WaitForChild("StudioTests") }
		print("[StudioTests] server suite starting")
		local results = TestEZ.TestBootstrap:run(roots)
		local failed = results.failureCount or 0
		if failed > 0 then
			warn(`[StudioTests] server suite FAILED ({failed})`)
		else
			print("[StudioTests] server suite passed")
		end
	end)
	:catch(function(err)
		warn(`[StudioTests] server runner failed: {err}`)
	end)
