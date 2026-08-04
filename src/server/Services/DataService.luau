--!strict
--[[
	DataService -- owns the lifecycle of a player's saved profile.

	It does exactly three things: acquire a session, hand the migrated data to
	whoever needs it, and end the session cleanly. Nothing about the economy
	lives here; nothing about storage leaks out.

	Migration is NOT delegated to ProfileStore. `Profile:Reconcile()` only
	fills in missing keys from a template -- it cannot rename a field, fold
	two fields into a table, or refuse a save written by a newer build. All of
	that is in `Data/Profile.luau`, which is pure and unit-tested (ADR-0001).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileStoreModule = require(ServerScriptService.ServerPackages.ProfileStore)

local Profile = require(script.Parent.Parent.Data.Profile)
local EconomyConfig = require(ReplicatedStorage.Shared.Economy.EconomyConfig)

-- The DataStore name is deliberately stable and carries no schema version:
-- versioning is the migration chain's job. Encoding it here would strand
-- every existing player on the old key the moment the schema changed.
local STORE_NAME = "PlayerData"
local KEY_PREFIX = "Player_"

-- How long WaitForData will hold before giving up. Generous, because the
-- alternative -- a player who joined and got no economy -- is worse than a
-- slow join.
local WAIT_TIMEOUT = 30

local DataService = Knit.CreateService({
	Name = "DataService",

	_store = nil :: any,
	_sessions = {} :: { [Player]: any },
	_data = {} :: { [Player]: Profile.Profile },
	-- Set when loading finished and failed, so WaitForData stops early
	-- instead of holding until the timeout
	_failed = {} :: { [Player]: boolean },

	-- Callbacks run just before a session is released. See OnBeforeRelease.
	_beforeRelease = {} :: { (Player) -> () },
})

local function keyFor(player: Player): string
	return KEY_PREFIX .. player.UserId
end

local function upgradeIds(): { string }
	local ids: { string } = {}
	for id in EconomyConfig.upgrades do
		table.insert(ids, id)
	end
	return ids
end

--[[ Loading ]]

function DataService:_load(player: Player)
	local session = self._store:StartSessionAsync(keyFor(player), {
		-- Without a cancel condition, a player who leaves while another
		-- server still holds the lock leaves this call yielding for as long
		-- as ProfileStore keeps retrying
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if session == nil then
		-- Either the player left mid-load, or the lock could not be taken.
		-- Both mean there is nothing to play with.
		self._failed[player] = true
		if player.Parent == Players then
			player:Kick("Could not load your data. Please rejoin.")
		end
		return
	end

	session:AddUserId(player.UserId) -- GDPR: ties the data to its owner

	-- Another server took the session over, or this one is shutting down.
	-- Continuing to play would mean writing into a profile we no longer own.
	session.OnSessionEnd:Connect(function()
		self._sessions[player] = nil
		self._data[player] = nil
		if player.Parent == Players then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		-- Left while we were loading; release the lock immediately so the
		-- next server is not blocked
		session:EndSession()
		return
	end

	local data, report = Profile.load(session.Data, upgradeIds())

	if report.action == "refused" then
		-- A save from a newer build. Do NOT write to session.Data -- the
		-- autosave would then overwrite newer data with our downgrade.
		warn(`[DataService] {player.Name}: {report.reason}`)
		self._failed[player] = true
		session:EndSession()
		player:Kick("Your data was saved by a newer version of the game.")
		return
	end

	if report.action ~= "current" then
		print(`[DataService] {player.Name}: {report.action} ({report.steps} step(s))`)
	end

	-- From here on this table IS the save: ProfileStore autosaves whatever
	-- lives in session.Data, so callers mutate it directly
	session.Data = data

	self._sessions[player] = session
	self._data[player] = data
end

--[[ Public API (server-side; not exposed to clients) ]]

--[[
	The player's saved data, or nil if it is not loaded (yet or at all).
	Non-yielding -- use WaitForData when the caller can afford to wait.
]]
function DataService:GetData(player: Player): Profile.Profile?
	return self._data[player]
end

--[[
	Yields until the player's data is loaded.

	Returns nil if loading failed, the player left, or the timeout elapsed.
	Callers must handle nil: joining without data is a normal failure mode,
	not an exception.
]]
function DataService:WaitForData(player: Player): Profile.Profile?
	local deadline = os.clock() + WAIT_TIMEOUT

	while os.clock() < deadline do
		local data = self._data[player]
		if data then
			return data
		end
		if self._failed[player] or player.Parent ~= Players then
			return nil
		end
		task.wait(0.1)
	end

	warn(`[DataService] timed out waiting for {player.Name}'s data`)
	return nil
end

--[[
	Register a callback to run just before a player's session is released.

	This exists to remove a race. Every service that keeps runtime state needs
	to flush it into the profile before the session ends, but if each one
	simply connects to `PlayerRemoving`, the order is whatever the connections
	happened to be made in -- and a flush that lands after `EndSession` is
	silently thrown away. Registering here makes the ordering explicit.
]]
function DataService:OnBeforeRelease(callback: (Player) -> ())
	table.insert(self._beforeRelease, callback)
end

--[[ Ends the session and releases the lock. Safe to call more than once. ]]
function DataService:Release(player: Player)
	local session = self._sessions[player]

	if session then
		for _, callback in self._beforeRelease do
			-- One failing callback must not stop the release: a session that
			-- is never ended leaves the player locked out of their own data
			-- on every other server until it times out
			local ok, err = pcall(callback, player)
			if not ok then
				warn(`[DataService] before-release callback failed for {player.Name}: {err}`)
			end
		end
	end

	self._sessions[player] = nil
	self._data[player] = nil
	self._failed[player] = nil

	if session and session:IsActive() then
		session:EndSession()
	end
end

--[[ Knit lifecycle ]]

function DataService:KnitInit()
	local template = Profile.default(upgradeIds())
	local store = ProfileStoreModule.New(STORE_NAME, template)

	-- In Studio, use the mock store. Real DataStore access from Studio is
	-- either unavailable or -- worse, when API access is enabled -- writes
	-- test data straight into the live game.
	self._store = if RunService:IsStudio() then store.Mock else store

	if RunService:IsStudio() then
		print("[DataService] Studio detected: using the mock DataStore")
	end
end

function DataService:KnitStart()
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			self:_load(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:Release(player)
	end)
end

return DataService
