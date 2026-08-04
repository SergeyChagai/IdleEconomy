--!strict
--[[
	Точка входа сервера: поднимает Knit.

	Knit требует, чтобы ВСЕ сервисы были зарегистрированы до Start().
	После старта добавить сервис уже нельзя — поэтому регистрация собрана
	в одном скрипте, а не размазана по модулям.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Knit.Knit, а не просто Knit: релизный Knit.rbxm содержит папку-обёртку,
-- внутри которой лежит собственно ModuleScript. При установке через Wally
-- обёртки нет и путь был бы короче на одно звено.
local Knit = require(ReplicatedStorage.Packages.Knit.Knit)

Knit.AddServices(ServerScriptService.Server.Services)

Knit.Start()
	:andThen(function()
		print("[Knit] сервер запущен")
	end)
	:catch(function(err)
		-- Молча упавший Knit выглядит как "игра просто не работает",
		-- поэтому ошибку обязательно наверх
		warn(`[Knit] сервер не стартовал: {err}`)
	end)
