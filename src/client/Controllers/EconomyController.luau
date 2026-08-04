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

local Knit = require(ReplicatedStorage.Packages.Knit)

local Economy = ReplicatedStorage.Shared.Economy
local Balance = require(Economy.Balance)
local EconomyConfig = require(Economy.EconomyConfig)

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

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = balance

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

	local mineCorner = Instance.new("UICorner")
	mineCorner.CornerRadius = UDim.new(1, 0)
	mineCorner.Parent = mine

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

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

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

	return gui
end

function EconomyController:_render()
	local state = self._state
	if not state then
		return
	end

	self._balance.Text = `{short(state.coins)}  (+{short(state.incomePerSecond)}/s)`

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

	local EconomyService = Knit.GetService("EconomyService")

	-- The server pushes state on every change
	EconomyService.StateChanged:Connect(function(state: PublicState)
		self._state = state
		self:_render()
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
end

return EconomyController
