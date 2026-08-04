--!strict
--[[
	EconomyService -- the server owns the economy end to end.

	Rules the whole module obeys:

	  1. State lives only here. The client receives numbers to display, but
	     no decision is ever made on the client.
	  2. Every remote argument goes through Validate. The client is hostile.
	  3. The client never sends a PRICE or a RESULT -- only intent ("buy N
	     levels of Pickaxe"). The server computes the cost.

	Rule three is where take-home tasks usually fail: if a remote accepts
	`cost` or `reward`, an exploiter simply sends their own values.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local Economy = ReplicatedStorage.Shared.Economy
local Balance = require(Economy.Balance)
local EconomyConfig = require(Economy.EconomyConfig)
local RateLimiter = require(Economy.RateLimiter)
local Validate = require(Economy.Validate)
local Wallet = require(Economy.Wallet)

local CURRENCY = "Coins"
local INCOME_TICK = 1 -- how often passive income is credited, in seconds

type PlayerState = {
	wallet: Wallet.Wallet,
	levels: { [string]: number },
	prestigeCount: number,
	lifetimeEarned: number,
	-- One limiter per player: a shared one would let a single exploiter
	-- lock mining for everyone on the server
	clickLimiter: RateLimiter.RateLimiter,
}

export type PublicState = {
	coins: number,
	levels: { [string]: number },
	prestigeCount: number,
	prestigeMultiplier: number,
	prestigeRequirement: number,
	lifetimeEarned: number,
	incomePerSecond: number,
}

local EconomyService = Knit.CreateService({
	Name = "EconomyService",

	-- The single place where player state lives
	_states = {} :: { [Player]: PlayerState },

	Client = {
		-- The server pushes new state; the client never polls
		StateChanged = Knit.CreateSignal(),
	},
})

--[[ Internals ]]

local function createState(): PlayerState
	local levels: { [string]: number } = {}
	for id in EconomyConfig.upgrades do
		levels[id] = 0
	end

	return {
		wallet = Wallet.new({ [CURRENCY] = 0 }),
		levels = levels,
		prestigeCount = 0,
		lifetimeEarned = 0,
		clickLimiter = RateLimiter.new(
			EconomyConfig.click.burstCapacity,
			EconomyConfig.click.refillPerSecond,
			os.clock()
		),
	}
end

function EconomyService:_getState(player: Player): PlayerState?
	return self._states[player]
end

--[[ Public snapshot of the state for the client.

     A snapshot rather than the internal table: otherwise server-side changes
     would leak to the client without us noticing, and -- more importantly --
     the client would receive fields it has no business knowing. ]]
function EconomyService:_publicState(state: PlayerState): PublicState
	local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)

	local levels: { [string]: number } = {}
	for id, level in state.levels do
		levels[id] = level
	end

	return {
		coins = state.wallet:get(CURRENCY),
		levels = levels,
		prestigeCount = state.prestigeCount,
		prestigeMultiplier = multiplier,
		prestigeRequirement = Balance.prestigeRequirement(
			EconomyConfig.prestige,
			state.prestigeCount
		),
		lifetimeEarned = state.lifetimeEarned,
		incomePerSecond = Balance.totalIncomePerSecond(
			EconomyConfig.upgrades,
			state.levels,
			multiplier
		),
	}
end

function EconomyService:_push(player: Player)
	local state = self:_getState(player)
	if state then
		self.Client.StateChanged:Fire(player, self:_publicState(state))
	end
end

--[[ Server API ]]

--[[
	Buy upgrade levels.

	Returns (ok, err). The error text is forwarded to the client verbatim --
	there is nothing secret in it, and it makes debugging meaningful.
]]
function EconomyService:BuyUpgrade(player: Player, upgradeId: string, count: number): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "player profile is not loaded"
	end

	local ok, err, upgrade, safeCount = Validate.upgradeRequest(
		EconomyConfig.upgrades,
		upgradeId,
		count
	)
	if not ok then
		return false, err
	end
	assert(upgrade and safeCount, "validator returned ok without data")

	local currentLevel = state.levels[upgrade.id] or 0

	-- Clamp to the level cap instead of refusing: the player pressed "buy 10"
	-- with 3 levels left to the cap, so sell 3 -- that is expected behaviour
	local available = upgrade.maxLevel - currentLevel
	if available <= 0 then
		return false, "max level reached"
	end

	local levelsToBuy = math.min(safeCount, available)

	-- The SERVER computes the price. The client only sent a quantity.
	local price = Balance.totalUpgradeCost(upgrade, currentLevel, levelsToBuy)

	local spent, spendError = state.wallet:trySpend(CURRENCY, price)
	if not spent then
		return false, spendError
	end

	state.levels[upgrade.id] = currentLevel + levelsToBuy
	self:_push(player)

	return true
end

--[[
	Manual mining on click.

	This is the only income source at the start: passive income comes from
	purchased levels, and there is no money to purchase them with yet.

	The server computes the reward and the client sends nothing at all -- the
	remote takes no arguments, so there is nothing to forge. The only guard
	needed here is call frequency.
]]
function EconomyService:Collect(player: Player): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "player profile is not loaded"
	end

	-- os.clock is monotonic and does not jump when system time is corrected
	if not state.clickLimiter:tryConsume(os.clock()) then
		return false, "too frequent"
	end

	local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)
	local reward = EconomyConfig.click.baseValue * multiplier

	local ok, err = state.wallet:add(CURRENCY, reward)
	if not ok then
		return false, err
	end

	state.lifetimeEarned += reward
	self:_push(player)

	return true
end

--[[ Buy as many levels as the player can currently afford ]]
function EconomyService:BuyMaxUpgrade(player: Player, upgradeId: string): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "player profile is not loaded"
	end

	local idOk, idError = Validate.identifier(upgradeId)
	if not idOk then
		return false, idError
	end

	local upgrade = EconomyConfig.upgrades[upgradeId]
	if not upgrade then
		return false, "unknown upgrade"
	end

	local currentLevel = state.levels[upgrade.id] or 0
	local levels = Balance.maxAffordableLevels(
		upgrade,
		currentLevel,
		state.wallet:get(CURRENCY)
	)

	if levels <= 0 then
		return false, "insufficient funds"
	end

	return self:BuyUpgrade(player, upgradeId, levels)
end

--[[
	Prestige: reset levels in exchange for a permanent multiplier.

	lifetimeEarned is NOT reset -- the next prestige threshold is measured
	against it. Resetting it would hand the player infinite prestige.
]]
function EconomyService:Prestige(player: Player): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "player profile is not loaded"
	end

	if not Balance.canPrestige(EconomyConfig.prestige, state.lifetimeEarned, state.prestigeCount) then
		return false, "prestige threshold not reached"
	end

	state.prestigeCount += 1
	state.wallet = Wallet.new({ [CURRENCY] = 0 })

	for id in EconomyConfig.upgrades do
		state.levels[id] = 0
	end

	self:_push(player)
	return true
end

--[[ Passive income ]]

function EconomyService:_tick(deltaTime: number)
	for player, state in self._states do
		local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)
		local rate = Balance.totalIncomePerSecond(EconomyConfig.upgrades, state.levels, multiplier)

		if rate > 0 then
			local earned = rate * deltaTime
			state.wallet:add(CURRENCY, earned)
			state.lifetimeEarned += earned
			self:_push(player)
		end
	end
end

--[[ Client API -- everything reachable from the client ]]

function EconomyService.Client:BuyUpgrade(player: Player, upgradeId: unknown, count: unknown)
	-- Types are only asserted after validation inside the service
	return self.Server:BuyUpgrade(player, upgradeId :: any, count :: any)
end

function EconomyService.Client:BuyMaxUpgrade(player: Player, upgradeId: unknown)
	return self.Server:BuyMaxUpgrade(player, upgradeId :: any)
end

function EconomyService.Client:Collect(player: Player)
	return self.Server:Collect(player)
end

function EconomyService.Client:Prestige(player: Player)
	return self.Server:Prestige(player)
end

function EconomyService.Client:GetState(player: Player): PublicState?
	local state = self.Server:_getState(player)
	return if state then self.Server:_publicState(state) else nil
end

--[[ Knit lifecycle ]]

function EconomyService:KnitStart()
	local function onPlayerAdded(player: Player)
		-- TODO: load the profile (ProfileStore) here and credit offline
		-- income via Balance.offlineEarnings. State is created from scratch
		-- for now -- persistence is a separate system.
		self._states[player] = createState()
		self:_push(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- TODO: save the profile here
		self._states[player] = nil
	end)

	task.spawn(function()
		while true do
			local deltaTime = task.wait(INCOME_TICK)
			self:_tick(deltaTime)
		end
	end)
end

return EconomyService
