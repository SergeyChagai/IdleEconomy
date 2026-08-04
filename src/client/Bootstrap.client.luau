--!strict
--[[
	Точка входа клиента: поднимает Knit.

	Knit.Start() на клиенте дожидается, пока сервер поднимет свои сервисы,
	поэтому GetService внутри контроллеров уже безопасен.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit.Knit)

local player = Players.LocalPlayer
local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")

Knit.AddControllers(controllers)

Knit.Start()
	:andThen(function()
		print("[Knit] клиент запущен")
	end)
	:catch(function(err)
		warn(`[Knit] клиент не стартовал: {err}`)
	end)
