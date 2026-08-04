--!strict
--[[
	Server entry point: starts Knit.

	Knit requires ALL services to be registered before Start(). Adding one
	afterwards is not possible, which is why registration sits in a single
	script instead of being spread across modules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.AddServices(ServerScriptService.Server.Services)

Knit.Start()
	:andThen(function()
		print("[Knit] server started")
	end)
	:catch(function(err)
		-- A silently failed Knit looks like "the game just does not work",
		-- so the error must always surface
		warn(`[Knit] server failed to start: {err}`)
	end)
