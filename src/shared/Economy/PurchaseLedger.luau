--!strict
--[[
	PurchaseId history for developer-product receipts.

	Pure module -- no `require`, no engine. Roblox may deliver the same
	ProcessReceipt more than once (retry after a timeout, server restart
	between Grant and the acknowledgement). The only safe answer is: record
	the PurchaseId in the save BEFORE acknowledging, and treat a repeat as
	already granted.

	History is an ordered list rather than a set table so it serialises
	cleanly in DataStore and so the oldest entries can be dropped when the
	list hits a configured limit. Lookup is linear; a few hundred ids is
	fine for a receipt handler that runs a handful of times per session.
]]

local PurchaseLedger = {}

export type History = { string }

local function isUsableId(purchaseId: unknown): boolean
	return type(purchaseId) == "string" and purchaseId ~= ""
end

--[[ True when this PurchaseId is already on the ledger. ]]
function PurchaseLedger.contains(history: History, purchaseId: string): boolean
	if not isUsableId(purchaseId) then
		return false
	end

	for _, id in history do
		if id == purchaseId then
			return true
		end
	end

	return false
end

--[[
	Record a PurchaseId.

	Returns (wasNew, newHistory). `wasNew` is false when the id was already
	present -- the caller must NOT grant again. The input history is never
	mutated: a half-applied grant must not leave an id stamped with no coins
	credited.

	When `limit` is exceeded the oldest entries are dropped. Roblox PurchaseIds
	are unique for practical purposes; keeping a bounded window is enough to
	survive retries measured in minutes or hours, not years.
]]
function PurchaseLedger.record(
	history: History,
	purchaseId: string,
	limit: number
): (boolean, History)
	if not isUsableId(purchaseId) then
		local copy: History = table.clone(history)
		return false, copy
	end

	if PurchaseLedger.contains(history, purchaseId) then
		return false, table.clone(history)
	end

	local safeLimit = if type(limit) == "number" and limit == limit and limit > 0
		then math.floor(limit)
		else 100

	local nextHistory: History = table.clone(history)
	table.insert(nextHistory, purchaseId)

	while #nextHistory > safeLimit do
		table.remove(nextHistory, 1)
	end

	return true, nextHistory
end

return PurchaseLedger
