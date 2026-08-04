--!strict
--[[
	MonetisationService -- developer products and gamepasses.

	ProcessReceipt rules this module never breaks:

	  1. Record the PurchaseId in the profile BEFORE returning PurchaseGranted.
	  2. A PurchaseId already on the ledger is acknowledged without granting
	     again (Roblox retries; a restart between grant and ack is normal).
	  3. If the profile is not loaded yet, return NotProcessedYet so Roblox
	     retries -- never drop a paid receipt on the floor.

	Gamepass ownership is refreshed from MarketplaceService on join and
	mirrored into the profile / EconomyService runtime state.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local Economy = ReplicatedStorage.Shared.Economy
local MonetisationConfig = require(Economy.MonetisationConfig)
local PurchaseAnalytics = require(Economy.PurchaseAnalytics)
local PurchaseLedger = require(Economy.PurchaseLedger)

local MonetisationService = Knit.CreateService({
	Name = "MonetisationService",

	_dataService = nil :: any,
	_economyService = nil :: any,

	Client = {},
})

--[[ Catalog lookups ]]

local function productById(productId: number): (string?, MonetisationConfig.ProductConfig?)
	if productId == 0 then
		return nil, nil
	end

	for key, product in MonetisationConfig.products do
		if product.productId == productId then
			return key, product
		end
	end

	return nil, nil
end

local function warnIncompleteCatalog()
	local missing = {}
	for key, pass in MonetisationConfig.gamepasses do
		if pass.id == 0 then
			table.insert(missing, `gamepass:{key}`)
		end
	end
	for key, product in MonetisationConfig.products do
		if product.productId == 0 then
			table.insert(missing, `product:{key}`)
		end
	end
	if #missing > 0 then
		warn(
			"[Monetisation] catalog incomplete — paste Creator Dashboard ids into "
				.. "MonetisationConfig.luau (see docs/monetisation.md): "
				.. table.concat(missing, ", ")
		)
	else
		print("[Monetisation] catalog configured")
	end
end

local function emit(event: PurchaseAnalytics.ReceiptEvent)
	-- Studio-visible trail; swap for AnalyticsService when a live funnel exists
	print(
		`[Monetisation] {event.kind}`
			.. (if event.purchaseId then ` purchaseId={event.purchaseId}` else "")
			.. (if event.productKey then ` product={event.productKey}` else "")
			.. (if event.coins then ` coins={event.coins}` else "")
			.. (if event.reason then ` reason={event.reason}` else "")
	)
end

--[[ Gamepasses ]]

function MonetisationService:_refreshPasses(player: Player)
	local data = self._dataService:GetData(player)
	if not data then
		return
	end

	local owned: { [string]: boolean } = {}

	for key, pass in MonetisationConfig.gamepasses do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				owned[key] = true
			end
		end
	end

	data.ownedPasses = owned
	self._economyService:ApplyEntitlements(player, owned)
end

--[[ ProcessReceipt ]]

function MonetisationService:_processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		emit(PurchaseAnalytics.deferred(receiptInfo.PurchaseId, "player not in this server"))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = self._dataService:WaitForData(player)
	if not data then
		emit(PurchaseAnalytics.deferred(receiptInfo.PurchaseId, "profile not loaded"))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = receiptInfo.PurchaseId
	if PurchaseLedger.contains(data.processedPurchases, purchaseId) then
		emit(PurchaseAnalytics.duplicate(purchaseId, player.UserId))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey, product = productById(receiptInfo.ProductId)
	if not productKey or not product then
		emit(PurchaseAnalytics.unknownProduct(purchaseId, receiptInfo.ProductId))
		-- Unknown catalog entry: acknowledge so Roblox stops retrying forever.
		-- Coins are not granted.
		local _, recorded = PurchaseLedger.record(
			data.processedPurchases,
			purchaseId,
			MonetisationConfig.purchaseHistoryLimit
		)
		data.processedPurchases = recorded
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Stamp the ledger FIRST. If the grant below fails we still must not
	-- leave an unstamped id that could double-pay on retry after a partial
	-- credit -- GrantCoins is atomic on the wallet, so the failure modes are
	-- "player gone" / "no state", both of which NotProcessedYet would retry.
	-- Recording first + grant + acknowledge is the Roblox-recommended shape
	-- when the grant itself is idempotent against missing state (we check).
	local wasNew, recorded = PurchaseLedger.record(
		data.processedPurchases,
		purchaseId,
		MonetisationConfig.purchaseHistoryLimit
	)
	if not wasNew then
		emit(PurchaseAnalytics.duplicate(purchaseId, player.UserId))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	data.processedPurchases = recorded

	local granted, err = self._economyService:GrantCoins(player, product.coins)
	if not granted then
		-- Roll the stamp back so a later retry can try again once state exists
		local rolled: { string } = {}
		for _, id in data.processedPurchases do
			if id ~= purchaseId then
				table.insert(rolled, id)
			end
		end
		data.processedPurchases = rolled

		emit(PurchaseAnalytics.deferred(purchaseId, err or "grant failed"))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	emit(PurchaseAnalytics.granted(
		purchaseId,
		productKey,
		product.productId,
		player.UserId,
		product.coins
	))

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--[[ Client prompts — intent only; MarketplaceService owns the purchase UI ]]

function MonetisationService:PromptGamepass(player: Player, key: string): (boolean, string?)
	local pass = MonetisationConfig.gamepasses[key]
	if not pass then
		return false, "unknown gamepass"
	end
	if pass.id == 0 then
		return false, "gamepass id not configured (see docs/monetisation.md)"
	end

	MarketplaceService:PromptGamePassPurchase(player, pass.id)
	return true, nil
end

function MonetisationService:PromptProduct(player: Player, key: string): (boolean, string?)
	local product = MonetisationConfig.products[key]
	if not product then
		return false, "unknown product"
	end
	if product.productId == 0 then
		return false, "product id not configured (see docs/monetisation.md)"
	end

	MarketplaceService:PromptProductPurchase(player, product.productId)
	return true, nil
end

function MonetisationService.Client:PromptGamepass(player: Player, key: unknown)
	if type(key) ~= "string" then
		return false, "invalid gamepass key"
	end
	return self.Server:PromptGamepass(player, key)
end

function MonetisationService.Client:PromptProduct(player: Player, key: unknown)
	if type(key) ~= "string" then
		return false, "invalid product key"
	end
	return self.Server:PromptProduct(player, key)
end

--[[ Knit lifecycle ]]

function MonetisationService:KnitStart()
	self._dataService = Knit.GetService("DataService")
	self._economyService = Knit.GetService("EconomyService")

	warnIncompleteCatalog()

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local data = self._dataService:WaitForData(player)
			if not data or player.Parent ~= Players then
				return
			end
			self:_refreshPasses(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return MonetisationService
