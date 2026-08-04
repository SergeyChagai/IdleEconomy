--!strict
--[[
	Studio TestEZ specs for EconomyService.

	These need the engine: Knit, Players, ProfileStore mock. They run only
	through tests/studio/run.server.luau under test.project.json.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local function waitForPlayer(): Player
	local existing = Players:GetPlayers()[1]
	if existing then
		return existing
	end
	return Players.PlayerAdded:Wait()
end

local function waitUntilGrantable(economy: any, player: Player): boolean
	for _ = 1, 100 do
		local ok = economy:GrantCoins(player, 1)
		if ok then
			return true
		end
		task.wait(0.1)
	end
	return false
end

return function()
	describe("EconomyService", function()
		local dataService
		local economy
		local player: Player

		beforeAll(function()
			Knit.OnStart():await()
			dataService = Knit.GetService("DataService")
			economy = Knit.GetService("EconomyService")
			player = waitForPlayer()
			expect(dataService:WaitForData(player)).to.be.ok()
			expect(waitUntilGrantable(economy, player)).to.equal(true)
		end)

		it("GrantCoins credits the synced profile", function()
			local data = dataService:GetData(player)
			expect(data).to.be.ok()
			assert(data, "profile")

			local before = data.coins
			local ok, err = economy:GrantCoins(player, 250)
			expect(ok).to.equal(true)
			expect(err).never.to.be.ok()
			expect(data.coins).to.be.near(before + 250, 0.001)
		end)

		it("GrantCoins rejects an invalid amount", function()
			local ok, err = economy:GrantCoins(player, -1)
			expect(ok).to.equal(false)
			expect(err).to.be.a("string")
		end)

		it("ApplyEntitlements writes Vip into the profile", function()
			economy:ApplyEntitlements(player, { Vip = true })

			local data = dataService:GetData(player)
			expect(data).to.be.ok()
			assert(data, "profile")
			expect(data.ownedPasses.Vip).to.equal(true)
		end)

		it("ApplyEntitlements can clear Vip again", function()
			economy:ApplyEntitlements(player, {})

			local data = dataService:GetData(player)
			expect(data).to.be.ok()
			assert(data, "profile")
			expect(data.ownedPasses.Vip).never.to.be.ok()
		end)
	end)
end
