--!strict
--[[
	Studio TestEZ runner (client).

	Same idea as the server runner: only synced via test.project.json.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local TestEZ = require(ReplicatedStorage.Packages.TestEZ)

local player = Players.LocalPlayer
local studioTests = player:WaitForChild("PlayerScripts"):WaitForChild("StudioTests")

Knit.OnStart()
	:andThen(function()
		task.wait(0.5)

		print("[StudioTests] client suite starting")
		local results = TestEZ.TestBootstrap:run({ studioTests })
		local failed = results.failureCount or 0
		if failed > 0 then
			warn(`[StudioTests] client suite FAILED ({failed})`)
		else
			print("[StudioTests] client suite passed")
		end
	end)
	:catch(function(err)
		warn(`[StudioTests] client runner failed: {err}`)
	end)
