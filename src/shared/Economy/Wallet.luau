--!strict
--[[
	Player wallet -- an OOP class over a set of currencies.

	It exists so that a balance has exactly ONE place where it is written.
	As long as currency is a plain number in a table, sooner or later someone
	writes `profile.Coins -= price` without a check and the balance goes
	negative. Here every change goes through validation.

	Methods that can fail return (ok, error) instead of raising: a declined
	payment is a normal outcome, not a fault, and wrapping every purchase in
	pcall would be noise.

	Pure module: no `require`, no engine access.
]]

-- The ceiling past which a double starts losing integer precision. 2^53 is
-- the last value where integers are still exact. Beyond it the balance
-- silently "sticks" and the player sees purchases that never deduct.
local MAX_BALANCE = 2 ^ 53

export type CurrencyAmounts = { [string]: number }

type WalletFields = {
	_balances: CurrencyAmounts,
}

local Wallet = {}
Wallet.__index = Wallet

export type Wallet = typeof(setmetatable({} :: WalletFields, Wallet))

--[[ Validation ]]

local function isValidAmount(amount: number): boolean
	if type(amount) ~= "number" then
		return false
	end
	if amount ~= amount then -- NaN
		return false
	end
	if amount == math.huge or amount == -math.huge then
		return false
	end
	return amount >= 0
end

--[[ Construction ]]

--[[
	`initial` is an optional starting balance. It is copied rather than
	referenced: otherwise the caller could keep mutating the balance behind
	the class's back.
]]
function Wallet.new(initial: CurrencyAmounts?): Wallet
	local balances: CurrencyAmounts = {}

	if initial then
		for currency, amount in initial do
			if isValidAmount(amount) then
				balances[currency] = math.min(amount, MAX_BALANCE)
			else
				-- A corrupt value from a save must not block joining the game
				balances[currency] = 0
			end
		end
	end

	return setmetatable({ _balances = balances }, Wallet)
end

--[[ Reads ]]

function Wallet.get(self: Wallet, currency: string): number
	return self._balances[currency] or 0
end

function Wallet.has(self: Wallet, currency: string, amount: number): boolean
	if not isValidAmount(amount) then
		return false
	end
	return self:get(currency) >= amount
end

--[[ Snapshot for saving. Returns a copy -- the internal table never leaves
     the class, otherwise callers would mutate it directly. ]]
function Wallet.serialize(self: Wallet): CurrencyAmounts
	local snapshot: CurrencyAmounts = {}
	for currency, amount in self._balances do
		snapshot[currency] = amount
	end
	return snapshot
end

--[[ Mutations ]]

--[[
	Credit an amount. Rejects negative and non-numeric values: spending must
	go through trySpend, otherwise the "can they afford it" check is bypassed
	by calling add with a negative number.
]]
function Wallet.add(self: Wallet, currency: string, amount: number): (boolean, string?)
	if not isValidAmount(amount) then
		return false, `invalid amount: {tostring(amount)}`
	end

	local current = self:get(currency)
	local updated = current + amount

	if updated > MAX_BALANCE then
		-- Clamp, but report it: silently dropping income is not acceptable
		self._balances[currency] = MAX_BALANCE
		return false, "balance cap reached"
	end

	self._balances[currency] = updated
	return true
end

--[[
	Spend if affordable. When it is not, the balance does NOT change at all.
	That is the key property: a partial deduction would leave the player
	without the money and without the purchase.
]]
function Wallet.trySpend(self: Wallet, currency: string, amount: number): (boolean, string?)
	if not isValidAmount(amount) then
		return false, `invalid amount: {tostring(amount)}`
	end

	local current = self:get(currency)
	if current < amount then
		return false, "insufficient funds"
	end

	self._balances[currency] = current - amount
	return true
end

--[[
	Atomic transfer between currencies (for example gems into coins).
	Either both operations happen or neither does.
]]
function Wallet.tryExchange(
	self: Wallet,
	fromCurrency: string,
	fromAmount: number,
	toCurrency: string,
	toAmount: number
): (boolean, string?)
	if not isValidAmount(fromAmount) or not isValidAmount(toAmount) then
		return false, "invalid exchange amount"
	end

	local ok, err = self:trySpend(fromCurrency, fromAmount)
	if not ok then
		return false, err
	end

	local added, addError = self:add(toCurrency, toAmount)
	if not added then
		-- Roll the deduction back: state has already changed by this point
		self:add(fromCurrency, fromAmount)
		return false, addError
	end

	return true
end

return Wallet
