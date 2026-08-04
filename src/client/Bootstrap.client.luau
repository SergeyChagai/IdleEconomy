--!strict
--[[
	Client entry point: starts Knit.

	Knit.Start() on the client waits until the server has brought its services
	up, so GetService inside controllers is already safe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)

local player = Players.LocalPlayer
local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")

Knit.AddControllers(controllers)

Knit.Start()
	:andThen(function()
		print("[Knit] client started")
	end)
	:catch(function(err)
		warn(`[Knit] client failed to start: {err}`)
	end)
