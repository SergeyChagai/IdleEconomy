--!strict
--[[
	EconomyController — клиентская сторона экономики.

	Контроллер НЕ считает деньги и НЕ решает, хватает ли на покупку. Он
	показывает то, что прислал сервер, и отправляет намерения. Локальная
	проверка "хватает ли" тут только ради UI (гасим кнопку), и на неё
	ничего не завязано: последнее слово всегда за сервером.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit.Knit)

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
}

local EconomyController = Knit.CreateController({
	Name = "EconomyController",
	_state = nil :: PublicState?,
	_rows = {} :: { [string]: { button: TextButton, label: TextLabel } },
})

--[[ Форматирование ]]

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

--[[ Короткая запись больших чисел: 1234567 -> "1.23M".

     В idle-играх без этого числа быстро перестают помещаться на кнопку. ]]
local function short(value: number): string
	if value < 1000 then
		return string.format("%d", value)
	end

	local tier = math.min(math.floor(math.log(value, 1000)), #SUFFIXES - 1)
	local scaled = value / 1000 ^ tier

	return string.format("%.2f%s", scaled, SUFFIXES[tier + 1])
end

--[[ Интерфейс ]]

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

	-- Кнопка ручной добычи: с неё начинается игра, поэтому она крупная
	-- и лежит по центру, а не в общем списке
	local mine = Instance.new("TextButton")
	mine.Name = "Mine"
	mine.Size = UDim2.fromOffset(220, 220)
	mine.Position = UDim2.new(0.5, 0, 1, -32)
	mine.AnchorPoint = Vector2.new(0.5, 1)
	mine.BackgroundColor3 = Color3.fromRGB(196, 148, 32)
	mine.TextColor3 = Color3.fromRGB(28, 24, 10)
	mine.Font = Enum.Font.GothamBold
	mine.TextSize = 22
	mine.Text = "ДОБЫТЬ"
	mine.Parent = gui

	local mineCorner = Instance.new("UICorner")
	mineCorner.CornerRadius = UDim.new(1, 0)
	mineCorner.Parent = mine

	-- Панель апгрейдов
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

	self._balance.Text = `{short(state.coins)}  (+{short(state.incomePerSecond)}/с)`

	for id, row in self._rows do
		local upgrade = EconomyConfig.upgrades[id]
		local level = state.levels[id] or 0
		local cost = Balance.upgradeCost(upgrade, level)

		row.button.Text = `{upgrade.displayName}  ур. {level}`
		row.label.Text = `{short(cost)} монет`

		-- Гасим кнопку, когда не хватает. Это ТОЛЬКО подсказка для глаза:
		-- нажатие всё равно уйдёт на сервер и там будет проверено заново
		local affordable = state.coins >= cost and level < upgrade.maxLevel
		row.button.BackgroundColor3 = if affordable
			then Color3.fromRGB(45, 90, 60)
			else Color3.fromRGB(32, 34, 44)
	end
end

--[[ Жизненный цикл Knit ]]

function EconomyController:KnitStart()
	local gui = self:_buildUi()
	self._balance = gui:WaitForChild("Balance") :: TextLabel

	local EconomyService = Knit.GetService("EconomyService")

	-- Сервер сам присылает состояние при каждом изменении
	EconomyService.StateChanged:Connect(function(state: PublicState)
		self._state = state
		self:_render()
	end)

	-- Стартовое состояние: на момент подписки сервер мог уже всё отправить
	EconomyService:GetState():andThen(function(state: PublicState?)
		if state then
			self._state = state
			self:_render()
		end
	end)

	-- Добыча. Отказ по лимиту частоты в лог не пишем: при быстрых кликах
	-- это штатный ответ сервера, а не ошибка, и он бы засорил Output
	local mine = gui:WaitForChild("Mine") :: TextButton
	mine.Activated:Connect(function()
		EconomyService:Collect()
	end)

	for id, row in self._rows do
		row.button.Activated:Connect(function()
			-- Отправляем НАМЕРЕНИЕ, а не стоимость. Сервер посчитает цену сам.
			EconomyService:BuyUpgrade(id, 1):andThen(function(ok: boolean, err: string?)
				if not ok then
					warn(`покупка отклонена: {err}`)
				end
			end)
		end)
	end
end

return EconomyController
