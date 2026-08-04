--!strict
--[[
	Player profile: schema, version history and migrations.

	Pure module -- no `require`, no engine access, no storage backend. The
	shape of saved data does not depend on what stores it, so this loads in
	Lune and is fully unit-tested (see ADR-0001).

	Schema and migrations live in ONE file deliberately. They are inseparable
	in practice, and splitting them would force a cross-module `require`,
	which is exactly what ADR-0001 forbids: Roblox spells it
	`require(script.Parent.X)` and Lune spells it `require("./X")`, and one
	file cannot do both.

	VERSION HISTORY -- every past shape is documented here on purpose. A
	migration cannot be written, reviewed or tested without knowing what it
	migrates from, and that knowledge leaves the codebase the moment the old
	shape is deleted.

	  v1  first release. Upgrade levels were separate fields: there were two
	      upgrades and a table looked like overkill.
	          { version, coins, pickaxeLevel, backpackLevel }

	  v2  upgrades became data-driven -- levels moved into a table keyed by
	      upgrade id -- and prestige was introduced.
	          { version, coins, levels, prestigeCount }

	  v3  offline income arrived, which needs two new facts: how much the
	      player has ever earned (the prestige threshold is measured against
	      it) and when they were last seen.
	          { version, coins, levels, prestigeCount, lifetimeEarned, lastSeen }
]]

local Profile = {}

-- The version this build writes. Bump it together with a new migration step.
Profile.CURRENT_VERSION = 3

export type Profile = {
	version: number,
	coins: number,
	levels: { [string]: number },
	prestigeCount: number,
	-- Total ever earned. Never reset by prestige -- the next threshold is
	-- measured against it.
	lifetimeEarned: number,
	-- Unix time of the last exit. 0 means "never seen", which must NOT be
	-- read as "away since 1970".
	lastSeen: number,
}

export type Action = "fresh" | "current" | "migrated" | "refused"

export type Report = {
	action: Action,
	-- Version found in the raw data, when there was a usable one
	fromVersion: number?,
	-- How many migration steps ran
	steps: number,
	-- Set when action is "refused" or the input was unusable
	reason: string?,
}

--[[ Value repair ]]

--[[
	Coerce a numeric field into something safe.

	DataStore round-trips, half-finished migrations and outright tampering all
	produce values of the right type but the wrong kind: NaN, infinity,
	negatives. Refusing to load the profile would lock the player out of their
	own save, so the value is repaired instead.
]]
local function safeNumber(value: unknown, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end
	if value ~= value then -- NaN
		return fallback
	end
	if value == math.huge or value == -math.huge then
		return fallback
	end
	if value < 0 then
		return fallback
	end
	return value
end

--[[ Levels are counts, so a fractional value is always wrong. ]]
local function safeLevel(value: unknown): number
	return math.floor(safeNumber(value, 0))
end

--[[ Construction ]]

--[[
	A fresh profile for a new player.

	Returns a new table every call: handing out a shared constant would let
	one session mutate the defaults for everyone joining afterwards.
]]
function Profile.default(upgradeIds: { string }): Profile
	local levels: { [string]: number } = {}
	for _, id in upgradeIds do
		levels[id] = 0
	end

	return {
		version = Profile.CURRENT_VERSION,
		coins = 0,
		levels = levels,
		prestigeCount = 0,
		lifetimeEarned = 0,
		lastSeen = 0,
	}
end

--[[ Migration steps ]]

--[[
	v1 -> v2: fold the per-upgrade fields into a levels table.

	Upgrades absent from v1 simply do not appear; `finalize` fills them in
	afterwards, so this step does not need to know the full upgrade list.
]]
local function migrate1to2(raw: { [string]: any }): { [string]: any }
	local levels: { [string]: number } = {}

	if raw.pickaxeLevel ~= nil then
		levels.Pickaxe = safeLevel(raw.pickaxeLevel)
	end
	if raw.backpackLevel ~= nil then
		levels.Backpack = safeLevel(raw.backpackLevel)
	end

	raw.levels = levels
	raw.pickaxeLevel = nil
	raw.backpackLevel = nil
	raw.prestigeCount = 0
	raw.version = 2

	return raw
end

--[[
	v2 -> v3: add lifetimeEarned and lastSeen.

	lifetimeEarned is seeded from the current coin balance. That is an
	approximation -- the player has already spent some of what they earned --
	but it errs in the safe direction: it can only UNDER-count, never grant
	prestige progress that was not earned. Seeding it with zero would be worse:
	a veteran player would suddenly find their prestige threshold reset.

	lastSeen is deliberately 0 rather than "now". Callers must read 0 as
	"unknown" and credit no offline income; stamping the migration time here
	would look like the player had just left and hand them a payout for time
	they never spent away.
]]
local function migrate2to3(raw: { [string]: any }): { [string]: any }
	raw.lifetimeEarned = safeNumber(raw.coins, 0)
	raw.lastSeen = 0
	raw.version = 3

	return raw
end

-- Indexed by the version being migrated FROM
local STEPS: { [number]: ({ [string]: any }) -> { [string]: any } } = {
	[1] = migrate1to2,
	[2] = migrate2to3,
}

--[[ Finalisation ]]

--[[
	Bring a profile at the current version into a guaranteed-valid state:
	every field present, every number sane, every known upgrade listed.

	Unknown keys in `levels` are KEPT rather than dropped. An upgrade may be
	pulled from the config temporarily, and deleting the player's progress on
	it would be irreversible. `Balance.totalIncomePerSecond` already ignores
	ids it does not recognise (there is a test for it), so keeping them is
	free apart from a few bytes of storage.
]]
local function finalize(raw: { [string]: any }, upgradeIds: { string }): Profile
	local levels: { [string]: number } = {}

	if type(raw.levels) == "table" then
		for id, value in raw.levels :: { [string]: any } do
			if type(id) == "string" then
				levels[id] = safeLevel(value)
			end
		end
	end

	for _, id in upgradeIds do
		if levels[id] == nil then
			levels[id] = 0
		end
	end

	return {
		version = Profile.CURRENT_VERSION,
		coins = safeNumber(raw.coins, 0),
		levels = levels,
		prestigeCount = math.floor(safeNumber(raw.prestigeCount, 0)),
		lifetimeEarned = safeNumber(raw.lifetimeEarned, 0),
		lastSeen = safeNumber(raw.lastSeen, 0),
	}
end

--[[ Offline window ]]

--[[
	Consume the offline window: report how long the player was away and stamp
	`lastSeen`, so the same stretch of time can never be paid out twice.

	Splitting "how long were they away" from "what is that worth" is
	deliberate. The payout amount is `Balance.offlineEarnings`, which depends
	on rates, caps and gamepasses. The double-credit guard depends on none of
	that -- it is purely about consuming the window -- so it lives here and is
	tested on its own. A retry, a rejoin or a duplicated load then cannot pay
	twice, whatever the economy config happens to be.

	Returns (elapsedSeconds, updatedProfile). The profile is copied rather
	than mutated: the caller decides when to adopt the new state, and a
	half-applied credit must not leave a stamped `lastSeen` behind.

	Zero elapsed is returned, and no payout is due, when:
	  * lastSeen is 0 -- a new or freshly migrated profile. "Unknown" must not
	    be read as "away since 1970";
	  * `now` is before lastSeen -- the clock moved backwards. The window is
	    re-anchored to `now` instead of producing a negative duration.
]]
function Profile.consumeOfflineWindow(profile: Profile, now: number): (number, Profile)
	local updated: Profile = {
		version = profile.version,
		coins = profile.coins,
		levels = profile.levels,
		prestigeCount = profile.prestigeCount,
		lifetimeEarned = profile.lifetimeEarned,
		lastSeen = profile.lastSeen,
	}

	-- A nonsense clock reading must not be written into the save: stamping it
	-- would corrupt every future window calculation
	if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then
		return 0, updated
	end

	local lastSeen = profile.lastSeen
	updated.lastSeen = now

	if lastSeen <= 0 or now <= lastSeen then
		return 0, updated
	end

	return now - lastSeen, updated
end

--[[ Entry point ]]

--[[
	Turn whatever came out of storage into a valid current-version profile.

	Returns (profile, report). The report exists so the caller can decide
	whether saving is safe -- see the "refused" case below.

	Handling of the awkward inputs:

	  * nil or not a table -> a fresh profile. Nothing to recover.

	  * missing or invalid version -> treated as v1 and run through the whole
	    chain. This recovers the most: every step tolerates missing keys, so
	    running from the oldest known shape preserves whatever fields do
	    match, instead of wiping a save that merely lost one field.

	  * version NEWER than this build -> REFUSED. The profile is not migrated
	    down and the caller is told not to save. This is the rollback case: an
	    older server must never overwrite a save written by a newer one, or a
	    deploy rollback silently destroys the data of everyone who played in
	    between.
]]
function Profile.load(raw: unknown, upgradeIds: { string }): (Profile, Report)
	if type(raw) ~= "table" then
		return Profile.default(upgradeIds), {
			action = "fresh",
			steps = 0,
			reason = if raw == nil then "no saved data" else `unusable data: {typeof(raw)}`,
		}
	end

	local data = raw :: { [string]: any }
	local rawVersion = data.version

	if type(rawVersion) == "number" and rawVersion > Profile.CURRENT_VERSION then
		return Profile.default(upgradeIds), {
			action = "refused",
			fromVersion = rawVersion,
			steps = 0,
			reason = `profile version {rawVersion} is newer than this build ({Profile.CURRENT_VERSION}); refusing to downgrade`,
		}
	end

	local version: number
	local unversioned = false

	if type(rawVersion) == "number" and rawVersion >= 1 then
		version = math.floor(rawVersion)
	else
		version = 1
		unversioned = true
	end

	local steps = 0
	while version < Profile.CURRENT_VERSION do
		local step = STEPS[version]
		if not step then
			-- A gap in the chain is a programming error, not bad data.
			-- Falling through would silently write a half-migrated profile.
			return Profile.default(upgradeIds), {
				action = "refused",
				fromVersion = version,
				steps = steps,
				reason = `no migration step from version {version}`,
			}
		end

		data = step(data)
		version += 1
		steps += 1
	end

	return finalize(data, upgradeIds), {
		action = if steps > 0 then "migrated" else "current",
		fromVersion = if unversioned then nil else math.floor(rawVersion :: number),
		steps = steps,
		reason = if unversioned then "no version field; assumed v1" else nil,
	}
end

return Profile
