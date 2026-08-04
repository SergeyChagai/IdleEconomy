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
local MonetisationConfig = require(Economy.MonetisationConfig)
local RateLimiter = require(Economy.RateLimiter)
local Validate = require(Economy.Validate)
local Wallet = require(Economy.Wallet)

local Profile = require(script.Parent.Parent.Data.Profile)

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
	-- Logical gamepass keys currently owned
	ownedPasses: { [string]: boolean },
	-- Product of configured gamepass income multipliers (1 when none)
	gamepassIncomeMultiplier: number,
	-- Any owned pass with boostsOffline
	offlineBoosted: boolean,
}

export type PublicState = {
	coins: number,
	levels: { [string]: number },
	prestigeCount: number,
	prestigeMultiplier: number,
	prestigeRequirement: number,
	lifetimeEarned: number,
	incomePerSecond: number,
	gamepassIncomeMultiplier: number,
}

local EconomyService = Knit.CreateService({
	Name = "EconomyService",

	-- The single place where player state lives
	_states = {} :: { [Player]: PlayerState },

	-- Resolved in KnitStart; persistence is entirely DataService's business
	_dataService = nil :: any,

	Client = {
		-- The server pushes new state; the client never polls
		StateChanged = Knit.CreateSignal(),
	},
})

--[[ Internals ]]

--[[
	Build runtime state from a loaded profile.

	Only upgrades that exist in the current config make it into runtime state.
	Unknown ids stay untouched in the profile itself -- see the note in
	Data/Profile.luau on why removed upgrades are not deleted from a save.
]]
local function entitlementsFromPasses(ownedPasses: { [string]: boolean }): (number, boolean)
	local incomeMultiplier = 1
	local offlineBoosted = false

	for key, owned in ownedPasses do
		if owned then
			local pass = MonetisationConfig.gamepasses[key]
			if pass then
				if pass.incomeMultiplier > 0 then
					incomeMultiplier *= pass.incomeMultiplier
				end
				if pass.boostsOffline then
					offlineBoosted = true
				end
			end
		end
	end

	return incomeMultiplier, offlineBoosted
end

local function stateFromProfile(data: Profile.Profile): PlayerState
	local levels: { [string]: number } = {}
	for id in EconomyConfig.upgrades do
		levels[id] = data.levels[id] or 0
	end

	local ownedPasses: { [string]: boolean } = {}
	for key, value in data.ownedPasses do
		ownedPasses[key] = value
	end

	local incomeMultiplier, offlineBoosted = entitlementsFromPasses(ownedPasses)

	return {
		wallet = Wallet.new({ [CURRENCY] = data.coins }),
		levels = levels,
		prestigeCount = data.prestigeCount,
		lifetimeEarned = data.lifetimeEarned,
		clickLimiter = RateLimiter.new(
			EconomyConfig.click.burstCapacity,
			EconomyConfig.click.refillPerSecond,
			os.clock()
		),
		ownedPasses = ownedPasses,
		gamepassIncomeMultiplier = incomeMultiplier,
		offlineBoosted = offlineBoosted,
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
		* state.gamepassIncomeMultiplier

	local levels: { [string]: number } = {}
	for id, level in state.levels do
		levels[id] = level
	end

	return {
		coins = state.wallet:get(CURRENCY),
		levels = levels,
		prestigeCount = state.prestigeCount,
		prestigeMultiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount),
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
		gamepassIncomeMultiplier = state.gamepassIncomeMultiplier,
	}
end

--[[
	Mirror runtime state into the profile.

	ProfileStore autosaves whatever sits in the profile table, so persistence
	is simply a matter of keeping it current. This runs from `_push`, which
	already fires on every meaningful change -- one hook rather than a save
	call sprinkled through every mutation, which is how a save gets forgotten.

	Level keys are copied one by one rather than replacing the table: ids that
	are no longer in the config must survive in the save.
]]
function EconomyService:_syncToProfile(player: Player, state: PlayerState)
	local data = self._dataService:GetData(player)
	if not data then
		return
	end

	data.coins = state.wallet:get(CURRENCY)
	data.prestigeCount = state.prestigeCount
	data.lifetimeEarned = state.lifetimeEarned

	for id, level in state.levels do
		data.levels[id] = level
	end

	local ownedPasses: { [string]: boolean } = {}
	for key, value in state.ownedPasses do
		ownedPasses[key] = value
	end
	data.ownedPasses = ownedPasses
end

--[[
	Apply gamepass entitlements resolved by MonetisationService.

	Called on join (and whenever ownership is refreshed). Multipliers take
	effect on the next income tick and on any subsequent offline credit.
]]
function EconomyService:ApplyEntitlements(player: Player, ownedPasses: { [string]: boolean })
	local state = self:_getState(player)
	local incomeMultiplier, offlineBoosted = entitlementsFromPasses(ownedPasses)

	local copied: { [string]: boolean } = {}
	for key, value in ownedPasses do
		copied[key] = value
	end

	if state then
		state.ownedPasses = copied
		state.gamepassIncomeMultiplier = incomeMultiplier
		state.offlineBoosted = offlineBoosted
		self:_push(player)
	end

	-- Profile may already be loaded while economy state is still spinning up;
	-- keep the save current either way
	local data = self._dataService and self._dataService:GetData(player)
	if data then
		data.ownedPasses = copied
	end
end

--[[
	Credit coins from a developer product. Server-only; never exposed as a
	remote. Returns false when the player has no economy state yet so
	ProcessReceipt can retry with NotProcessedYet.
]]
function EconomyService:GrantCoins(player: Player, amount: number): (boolean, string?)
	local state = self:_getState(player)
	if not state then
		return false, "player economy is not loaded"
	end

	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, "invalid grant amount"
	end

	state.wallet:add(CURRENCY, amount)
	state.lifetimeEarned += amount
	self:_push(player)
	return true, nil
end

function EconomyService:_push(player: Player)
	local state = self:_getState(player)
	if state then
		self:_syncToProfile(player, state)
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
		* state.gamepassIncomeMultiplier
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
			* state.gamepassIncomeMultiplier
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

--[[
	Credit income earned while the player was away.

	The window is consumed FIRST, before any payout is computed. If crediting
	were to fail or the server were to die midway, the worst outcome is a
	forfeited payout -- never a window that pays out twice on the next join.

	The rate is taken from the profile as loaded, so offline income is paid
	at the rate the player actually left with.
]]
function EconomyService:_creditOffline(player: Player, data: Profile.Profile, state: PlayerState): number
	local elapsed, updated = Profile.consumeOfflineWindow(data, os.time())
	data.lastSeen = updated.lastSeen

	if elapsed <= 0 then
		return 0
	end

	local multiplier = Balance.prestigeMultiplier(EconomyConfig.prestige, state.prestigeCount)
		* state.gamepassIncomeMultiplier
	local rate = Balance.totalIncomePerSecond(EconomyConfig.upgrades, state.levels, multiplier)

	local earned, creditedSeconds = Balance.offlineEarnings(
		EconomyConfig.offline,
		rate,
		elapsed,
		state.offlineBoosted
	)

	if earned <= 0 then
		return 0
	end

	state.wallet:add(CURRENCY, earned)
	state.lifetimeEarned += earned

	print(
		`[Economy] {player.Name}: offline payout {math.floor(earned)} `
			.. `for {math.floor(creditedSeconds)}s of {math.floor(elapsed)}s away`
	)

	return earned
end

function EconomyService:KnitStart()
	self._dataService = Knit.GetService("DataService")

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local data = self._dataService:WaitForData(player)
			if not data or player.Parent ~= Players then
				-- DataService has already kicked them; there is nothing to run
				-- an economy against
				return
			end

			local state = stateFromProfile(data)
			self:_creditOffline(player, data, state)

			self._states[player] = state
			self:_push(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Registered rather than hooked to PlayerRemoving: DataService guarantees
	-- this runs before the session is ended, so the final write is not racing
	-- the release
	self._dataService:OnBeforeRelease(function(player: Player)
		local state = self._states[player]
		if state then
			self:_syncToProfile(player, state)

			local data = self._dataService:GetData(player)
			if data then
				-- The timestamp the next offline window is measured from
				data.lastSeen = os.time()
			end
		end

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
