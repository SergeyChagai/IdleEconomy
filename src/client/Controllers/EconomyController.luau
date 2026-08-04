--!strict
--[[
	EconomyController -- the client side of the economy.

	The controller does NOT compute money and does NOT decide whether a
	purchase is affordable. It renders what the server sent and dispatches
	intent. The local affordability check exists purely for the UI (dimming a
	button); nothing depends on it, the server always has the final word.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local Economy = ReplicatedStorage.Shared.Economy
local Balance = require(Economy.Balance)
local EconomyConfig = require(Economy.EconomyConfig)
local MonetisationConfig = require(Economy.MonetisationConfig)

type PublicState = {
	coins: number,
	levels: { [string]: number },
	prestigeCount: number,
	prestigeMultiplier: number,
	prestigeRequirement: number,
	lifetimeEarned: number,
	incomePerSecond: number,
	gamepassIncomeMultiplier: number,
}

local EconomyController = Knit.CreateController({
	Name = "EconomyController",
	_state = nil :: PublicState?,
	_rows = {} :: { [string]: { button: TextButton, label: TextLabel } },
	_shopRows = {} :: { TextButton },
})

--[[ Formatting ]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

--[[ Short form for large numbers: 1234567 -> "1.23M".

     Without this, idle-game numbers quickly stop fitting on a button. ]]
local function short(value: number): string
	if value < 1000 then
		return string.format("%d", value)
	end

	local tier = math.min(math.floor(math.log(value, 1000)), #SUFFIXES - 1)
	local scaled = value / 1000 ^ tier

	return string.format("%.2f%s", scaled, SUFFIXES[tier + 1])
end

local function roundCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

--[[ Interface ]]

function EconomyController:_buildUi(): ScreenGui
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyHud"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local balance = Instance.new("TextLabel")
	balance.Name = "Balance"
	balance.Size = UDim2.fromOffset(320, 60)
	balance.Position = UDim2.new(0.5, 0, 0, 12)
	balance.AnchorPoint = Vector2.new(0.5, 0)
	balance.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	balance.BackgroundTransparency = 0.2
	balance.TextColor3 = Color3.fromRGB(255, 210, 60)
	balance.Font = Enum.Font.GothamBold
	balance.TextSize = 24
	balance.Text = "..."
	balance.Parent = gui
	roundCorner(balance, 10)

	-- Prestige: permanent multiplier in exchange for resetting upgrade levels
	local prestige = Instance.new("TextButton")
	prestige.Name = "Prestige"
	prestige.Size = UDim2.fromOffset(260, 72)
	prestige.Position = UDim2.new(1, -16, 0, 12)
	prestige.AnchorPoint = Vector2.new(1, 0)
	prestige.BackgroundColor3 = Color3.fromRGB(72, 42, 110)
	prestige.TextColor3 = Color3.fromRGB(235, 225, 255)
	prestige.Font = Enum.Font.GothamBold
	prestige.TextSize = 15
	prestige.Text = "Prestige"
	prestige.TextWrapped = true
	prestige.Parent = gui
	roundCorner(prestige, 10)

	local prestigeInfo = Instance.new("TextLabel")
	prestigeInfo.Name = "Info"
	prestigeInfo.Size = UDim2.new(1, -16, 0, 18)
	prestigeInfo.Position = UDim2.new(0, 8, 1, -22)
	prestigeInfo.BackgroundTransparency = 1
	prestigeInfo.TextColor3 = Color3.fromRGB(190, 175, 220)
	prestigeInfo.Font = Enum.Font.Gotham
	prestigeInfo.TextSize = 12
	prestigeInfo.TextXAlignment = Enum.TextXAlignment.Left
	prestigeInfo.Text = ""
	prestigeInfo.Parent = prestige

	-- Offline payout toast (hidden until the server fires OfflineCredited)
	local toast = Instance.new("TextLabel")
	toast.Name = "OfflineToast"
	toast.Size = UDim2.fromOffset(420, 48)
	toast.Position = UDim2.new(0.5, 0, 0, 84)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.BackgroundColor3 = Color3.fromRGB(24, 48, 36)
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(180, 240, 200)
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 16
	toast.Text = ""
	toast.Visible = false
	toast.Parent = gui
	roundCorner(toast, 8)

	-- The manual mining button: the game starts here, so it is large and
	-- centred rather than buried in the upgrade list
	local mine = Instance.new("TextButton")
	mine.Name = "Mine"
	mine.Size = UDim2.fromOffset(220, 220)
	mine.Position = UDim2.new(0.5, 0, 1, -32)
	mine.AnchorPoint = Vector2.new(0.5, 1)
	mine.BackgroundColor3 = Color3.fromRGB(196, 148, 32)
	mine.TextColor3 = Color3.fromRGB(28, 24, 10)
	mine.Font = Enum.Font.GothamBold
	mine.TextSize = 22
	mine.Text = "MINE"
	mine.Parent = gui
	roundCorner(mine, 110)

	-- Upgrade panel
	local panel = Instance.new("Frame")
	panel.Name = "Upgrades"
	panel.Size = UDim2.fromOffset(300, 240)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.Name
	layout.Parent = panel

	for id, upgrade in EconomyConfig.upgrades do
		local button = Instance.new("TextButton")
		button.Name = id
		button.Size = UDim2.new(1, 0, 0, 52)
		button.BackgroundColor3 = Color3.fromRGB(32, 34, 44)
		button.TextColor3 = Color3.fromRGB(235, 235, 240)
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 16
		button.Text = upgrade.displayName
		button.Parent = panel
		roundCorner(button, 8)

		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.Size = UDim2.new(1, -16, 0, 18)
		info.Position = UDim2.new(0, 8, 1, -20)
		info.BackgroundTransparency = 1
		info.TextColor3 = Color3.fromRGB(150, 155, 170)
		info.Font = Enum.Font.Gotham
		info.TextSize = 12
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.Text = ""
		info.Parent = button

		self._rows[id] = { button = button, label = info }
	end

	-- Shop: gamepasses + developer products (prompts only; server grants)
	local shop = Instance.new("Frame")
	shop.Name = "Shop"
	shop.Size = UDim2.fromOffset(260, 280)
	shop.Position = UDim2.new(1, -16, 1, -16)
	shop.AnchorPoint = Vector2.new(1, 1)
	shop.BackgroundTransparency = 1
	shop.Parent = gui

	local shopTitle = Instance.new("TextLabel")
	shopTitle.Name = "Title"
	shopTitle.Size = UDim2.new(1, 0, 0, 28)
	shopTitle.BackgroundTransparency = 1
	shopTitle.TextColor3 = Color3.fromRGB(200, 205, 220)
	shopTitle.Font = Enum.Font.GothamBold
	shopTitle.TextSize = 18
	shopTitle.TextXAlignment = Enum.TextXAlignment.Left
	shopTitle.Text = "Shop"
	shopTitle.Parent = shop

	local shopList = Instance.new("Frame")
	shopList.Name = "Items"
	shopList.Size = UDim2.new(1, 0, 1, -32)
	shopList.Position = UDim2.fromOffset(0, 32)
	shopList.BackgroundTransparency = 1
	shopList.Parent = shop

	local shopLayout = Instance.new("UIListLayout")
	shopLayout.Padding = UDim.new(0, 8)
	shopLayout.SortOrder = Enum.SortOrder.Name
	shopLayout.Parent = shopList

	local function shopButton(name: string, text: string): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.new(1, 0, 0, 44)
		button.BackgroundColor3 = Color3.fromRGB(36, 48, 72)
		button.TextColor3 = Color3.fromRGB(220, 230, 255)
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 14
		button.Text = text
		button.Parent = shopList
		roundCorner(button, 8)
		table.insert(self._shopRows, button)
		return button
	end

	for key, pass in MonetisationConfig.gamepasses do
		local label = if pass.id == 0
			then `{pass.displayName} (unconfigured)`
			else `{pass.displayName}  ×{pass.incomeMultiplier} income`
		local button = shopButton(`Pass_{key}`, label)
		button:SetAttribute("Kind", "gamepass")
		button:SetAttribute("Key", key)
	end

	for key, product in MonetisationConfig.products do
		local label = if product.productId == 0
			then `{product.displayName} (unconfigured)`
			else `{product.displayName}  +{short(product.coins)}`
		local button = shopButton(`Product_{key}`, label)
		button:SetAttribute("Kind", "product")
		button:SetAttribute("Key", key)
	end

	return gui
end

function EconomyController:_showOfflineToast(earned: number, creditedSeconds: number, elapsed: number)
	local toast = self._toast
	if not toast then
		return
	end

	local awayLabel = if elapsed < 120
		then `{math.floor(elapsed)}s`
		else `{math.floor(elapsed / 60)}m`
	toast.Text = `Welcome back — +{short(earned)} coins `
		.. `({math.floor(creditedSeconds)}s of {awayLabel} away)`
	toast.Visible = true
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.15

	task.delay(4, function()
		if not toast.Parent then
			return
		end
		local fade = TweenService:Create(
			toast,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1, BackgroundTransparency = 1 }
		)
		fade:Play()
		fade.Completed:Connect(function()
			toast.Visible = false
		end)
	end)
end

function EconomyController:_render()
	local state = self._state
	if not state then
		return
	end

	self._balance.Text = `{short(state.coins)}  (+{short(state.incomePerSecond)}/s)`

	local canPrestige = state.lifetimeEarned >= state.prestigeRequirement
	self._prestige.Text = `Prestige  ×{string.format("%.2f", state.prestigeMultiplier)}`
	self._prestigeInfo.Text = if canPrestige
		then "Ready — resets upgrades"
		else `Need {short(state.prestigeRequirement)} lifetime`
	self._prestige.BackgroundColor3 = if canPrestige
		then Color3.fromRGB(110, 70, 170)
		else Color3.fromRGB(48, 36, 64)

	for id, row in self._rows do
		local upgrade = EconomyConfig.upgrades[id]
		local level = state.levels[id] or 0
		local cost = Balance.upgradeCost(upgrade, level)

		row.button.Text = `{upgrade.displayName}  lv. {level}`
		row.label.Text = `{short(cost)} coins`

		-- Dim the button when it is unaffordable. This is ONLY a visual hint:
		-- the click still goes to the server and is re-checked there
		local affordable = state.coins >= cost and level < upgrade.maxLevel
		row.button.BackgroundColor3 = if affordable
			then Color3.fromRGB(45, 90, 60)
			else Color3.fromRGB(32, 34, 44)
	end
end

--[[ Knit lifecycle ]]

function EconomyController:KnitStart()
	local gui = self:_buildUi()
	self._balance = gui:WaitForChild("Balance") :: TextLabel
	self._toast = gui:WaitForChild("OfflineToast") :: TextLabel

	local prestigeButton = gui:WaitForChild("Prestige") :: TextButton
	self._prestige = prestigeButton
	self._prestigeInfo = prestigeButton:WaitForChild("Info") :: TextLabel

	local EconomyService = Knit.GetService("EconomyService")
	local MonetisationService = Knit.GetService("MonetisationService")

	-- The server pushes state on every change
	EconomyService.StateChanged:Connect(function(state: PublicState)
		self._state = state
		self:_render()
	end)

	EconomyService.OfflineCredited:Connect(function(
		earned: number,
		creditedSeconds: number,
		elapsed: number
	)
		self:_showOfflineToast(earned, creditedSeconds, elapsed)
	end)

	-- Initial state: the server may have pushed before we subscribed
	EconomyService:GetState():andThen(function(state: PublicState?)
		if state then
			self._state = state
			self:_render()
		end
	end)

	-- Mining. Rate-limit rejections are not logged: during fast clicking that
	-- is a normal server response, not an error, and it would flood Output
	local mine = gui:WaitForChild("Mine") :: TextButton
	mine.Activated:Connect(function()
		EconomyService:Collect()
	end)

	prestigeButton.Activated:Connect(function()
		EconomyService:Prestige():andThen(function(ok: boolean, err: string?)
			if not ok then
				warn(`prestige rejected: {err}`)
			end
		end)
	end)

	for id, row in self._rows do
		row.button.Activated:Connect(function()
			-- Send INTENT, not a price. The server works the cost out itself.
			EconomyService:BuyUpgrade(id, 1):andThen(function(ok: boolean, err: string?)
				if not ok then
					warn(`purchase rejected: {err}`)
				end
			end)
		end)
	end

	for _, button in self._shopRows do
		button.Activated:Connect(function()
			local kind = button:GetAttribute("Kind")
			local key = button:GetAttribute("Key")
			if type(key) ~= "string" then
				return
			end

			local promise = if kind == "gamepass"
				then MonetisationService:PromptGamepass(key)
				else MonetisationService:PromptProduct(key)

			promise:andThen(function(ok: boolean, err: string?)
				if not ok then
					warn(`shop prompt rejected: {err}`)
				end
			end)
		end)
	end
end

return EconomyController
