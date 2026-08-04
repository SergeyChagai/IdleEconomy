--!strict
--[[
	Studio TestEZ specs for EconomyController.

	Runs on the client after Knit starts (tests/studio/run.client.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local function waitForState(controller: any): boolean
	for _ = 1, 100 do
		if controller._state ~= nil then
			return true
		end
		task.wait(0.1)
	end
	return false
end

return function()
	describe("EconomyController", function()
		local controller

		beforeAll(function()
			Knit.OnStart():await()
			controller = Knit.GetController("EconomyController")
			expect(controller).to.be.ok()
			expect(waitForState(controller)).to.equal(true)
		end)

		it("receives a public state snapshot from the server", function()
			local state = controller._state
			expect(state).to.be.ok()
			assert(state, "state")
			expect(state.coins).to.be.a("number")
			expect(state.levels).to.be.a("table")
			expect(state.incomePerSecond).to.be.a("number")
			expect(state.gamepassIncomeMultiplier).to.be.a("number")
		end)

		it("builds the EconomyHud under PlayerGui", function()
			local gui = Players.LocalPlayer.PlayerGui:FindFirstChild("EconomyHud")
			expect(gui).to.be.ok()
			assert(gui, "hud")
			expect(gui:FindFirstChild("Balance")).to.be.ok()
			expect(gui:FindFirstChild("Mine")).to.be.ok()
			expect(gui:FindFirstChild("Upgrades")).to.be.ok()
		end)

		it("keeps upgrade rows for every configured upgrade", function()
			local EconomyConfig = require(ReplicatedStorage.Shared.Economy.EconomyConfig)
			for id in EconomyConfig.upgrades do
				expect(controller._rows[id]).to.be.ok()
			end
		end)
	end)
end
