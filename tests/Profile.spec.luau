--!strict
--[[
	Profile schema and migration tests.

	Migrations are the one piece of code that runs against data written by a
	build that no longer exists, on players who are not there to report a
	problem. They cannot be verified by playing the game -- by the time a
	broken migration is noticed, the original data is already overwritten.

	So the tests cover the awkward inputs first: old versions, missing keys,
	corrupt values, and a save from a NEWER build than the one loading it.
]]

local Profile = require("../src/server/Data/Profile")

local UPGRADE_IDS = { "Pickaxe", "Backpack", "Drill" }

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("default", function()
		it("is written at the current version", function()
			local profile = Profile.default(UPGRADE_IDS)
			expect(profile.version).toBe(Profile.CURRENT_VERSION)
		end)

		it("lists every known upgrade at level zero", function()
			local profile = Profile.default(UPGRADE_IDS)
			for _, id in UPGRADE_IDS do
				expect(profile.levels[id]).toBe(0)
			end
		end)

		it("starts a player with nothing earned", function()
			local profile = Profile.default(UPGRADE_IDS)
			expect(profile.coins).toBe(0)
			expect(profile.prestigeCount).toBe(0)
			expect(profile.lifetimeEarned).toBe(0)
		end)

		--[[
			A shared default table would let one player's session mutate what
			every later joiner receives.
		]]
		it("returns an independent table each call", function()
			local first = Profile.default(UPGRADE_IDS)
			local second = Profile.default(UPGRADE_IDS)

			first.coins = 999
			first.levels.Pickaxe = 42

			expect(second.coins).toBe(0)
			expect(second.levels.Pickaxe).toBe(0)
		end)
	end)

	describe("load: no usable data", function()
		it("creates a fresh profile from nil", function()
			local profile, report = Profile.load(nil, UPGRADE_IDS)

			expect(report.action).toBe("fresh")
			expect(profile.version).toBe(Profile.CURRENT_VERSION)
			expect(profile.coins).toBe(0)
		end)

		it("creates a fresh profile from a non-table", function()
			local _, report = Profile.load("garbage", UPGRADE_IDS)
			expect(report.action).toBe("fresh")
		end)

		it("creates a fresh profile from a number", function()
			local _, report = Profile.load(42, UPGRADE_IDS)
			expect(report.action).toBe("fresh")
		end)
	end)

	describe("load: already current", function()
		it("runs no migration steps", function()
			local current = Profile.default(UPGRADE_IDS)
			current.coins = 500

			local profile, report = Profile.load(current, UPGRADE_IDS)

			expect(report.action).toBe("current")
			expect(report.steps).toBe(0)
			expect(profile.coins).toBe(500)
		end)

		--[[
			Loading twice must be indistinguishable from loading once. If a
			migration were not idempotent, a rejoin would compound the damage.
		]]
		it("is idempotent across repeated loads", function()
			local v1 = { version = 1, coins = 250, pickaxeLevel = 4, backpackLevel = 2 }

			local once = Profile.load(v1, UPGRADE_IDS)
			local twice = Profile.load(once, UPGRADE_IDS)

			expect(twice).toEqual(once)
		end)

		it("fills in a key missing at the current version", function()
			local broken = {
				version = 3,
				coins = 100,
				levels = { Pickaxe = 1 },
				-- prestigeCount, lifetimeEarned and lastSeen absent
			}

			local profile = Profile.load(broken, UPGRADE_IDS)

			expect(profile.prestigeCount).toBe(0)
			expect(profile.lifetimeEarned).toBe(0)
			expect(profile.lastSeen).toBe(0)
			expect(profile.coins).toBe(100)
		end)
	end)

	describe("load: v1 -> v3", function()
		local function v1Profile()
			return { version = 1, coins = 1234, pickaxeLevel = 7, backpackLevel = 3 }
		end

		it("applies both migration steps", function()
			local _, report = Profile.load(v1Profile(), UPGRADE_IDS)

			expect(report.action).toBe("migrated")
			expect(report.fromVersion).toBe(1)
			expect(report.steps).toBe(2)
		end)

		it("moves the flat level fields into the levels table", function()
			local profile = Profile.load(v1Profile(), UPGRADE_IDS)

			expect(profile.levels.Pickaxe).toBe(7)
			expect(profile.levels.Backpack).toBe(3)
		end)

		it("adds upgrades that did not exist in v1", function()
			local profile = Profile.load(v1Profile(), UPGRADE_IDS)
			expect(profile.levels.Drill).toBe(0)
		end)

		it("keeps the coin balance", function()
			local profile = Profile.load(v1Profile(), UPGRADE_IDS)
			expect(profile.coins).toBe(1234)
		end)

		--[[
			Seeding lifetimeEarned from the balance under-counts (the player
			has spent some of it) but never over-counts, so it cannot hand out
			prestige progress that was not earned. Seeding zero would be
			worse: a veteran would find their prestige threshold reset.
		]]
		it("seeds lifetimeEarned from the balance", function()
			local profile = Profile.load(v1Profile(), UPGRADE_IDS)
			expect(profile.lifetimeEarned).toBe(1234)
		end)

		--[[
			lastSeen must stay 0 -- "unknown", not "just left". Stamping the
			migration time would hand the player an offline payout for time
			they never spent away.
		]]
		it("leaves lastSeen unknown rather than stamping the migration time", function()
			local profile = Profile.load(v1Profile(), UPGRADE_IDS)
			expect(profile.lastSeen).toBe(0)
		end)
	end)

	describe("load: v2 -> v3", function()
		local function v2Profile()
			return {
				version = 2,
				coins = 900,
				levels = { Pickaxe = 5, Backpack = 1, Drill = 2 },
				prestigeCount = 3,
			}
		end

		it("applies exactly one step", function()
			local _, report = Profile.load(v2Profile(), UPGRADE_IDS)

			expect(report.action).toBe("migrated")
			expect(report.steps).toBe(1)
		end)

		it("preserves levels and prestige", function()
			local profile = Profile.load(v2Profile(), UPGRADE_IDS)

			expect(profile.levels.Pickaxe).toBe(5)
			expect(profile.levels.Drill).toBe(2)
			expect(profile.prestigeCount).toBe(3)
		end)
	end)

	describe("load: missing version", function()
		--[[
			A save that lost its version field is not necessarily junk. Every
			step tolerates missing keys, so running the whole chain from the
			oldest known shape recovers whatever still matches -- far better
			than wiping a profile over one absent field.
		]]
		it("assumes v1 and migrates rather than wiping", function()
			local orphan = { coins = 777, pickaxeLevel = 2 }

			local profile, report = Profile.load(orphan, UPGRADE_IDS)

			expect(report.action).toBe("migrated")
			expect(report.reason).toBeTruthy()
			expect(profile.coins).toBe(777)
			expect(profile.levels.Pickaxe).toBe(2)
		end)

		it("treats a non-numeric version as missing", function()
			local weird = { version = "three", coins = 50 }

			local profile, report = Profile.load(weird, UPGRADE_IDS)

			expect(report.action).toBe("migrated")
			expect(profile.coins).toBe(50)
		end)
	end)

	describe("load: version from the future", function()
		--[[
			The rollback case, and the reason `action` exists at all. If a
			deploy is rolled back, the older build must never migrate a newer
			save downwards and write it back -- that destroys the data of
			everyone who played on the newer build.
		]]
		it("refuses a newer version instead of downgrading it", function()
			local future = { version = 99, coins = 5000, mysteryField = true }

			local _, report = Profile.load(future, UPGRADE_IDS)

			expect(report.action).toBe("refused")
			expect(report.fromVersion).toBe(99)
			expect(report.steps).toBe(0)
			expect(report.reason).toBeTruthy()
		end)

		it("refuses even one version ahead", function()
			local future = { version = Profile.CURRENT_VERSION + 1, coins = 10 }
			local _, report = Profile.load(future, UPGRADE_IDS)
			expect(report.action).toBe("refused")
		end)
	end)

	describe("load: corrupt values", function()
		it("repairs NaN and infinity", function()
			local broken = {
				version = 3,
				coins = 0 / 0,
				levels = { Pickaxe = math.huge },
				prestigeCount = -math.huge,
				lifetimeEarned = 0 / 0,
				lastSeen = math.huge,
			}

			local profile = Profile.load(broken, UPGRADE_IDS)

			expect(profile.coins).toBe(0)
			expect(profile.levels.Pickaxe).toBe(0)
			expect(profile.prestigeCount).toBe(0)
			expect(profile.lifetimeEarned).toBe(0)
			expect(profile.lastSeen).toBe(0)
		end)

		it("repairs negative values", function()
			local broken = { version = 3, coins = -500, levels = { Pickaxe = -3 } }
			local profile = Profile.load(broken, UPGRADE_IDS)

			expect(profile.coins).toBe(0)
			expect(profile.levels.Pickaxe).toBe(0)
		end)

		it("repairs values of the wrong type", function()
			local broken = { version = 3, coins = "lots", levels = "none" }
			local profile = Profile.load(broken, UPGRADE_IDS)

			expect(profile.coins).toBe(0)
			expect(profile.levels.Pickaxe).toBe(0)
		end)

		it("floors fractional levels", function()
			local broken = { version = 3, levels = { Pickaxe = 4.9 } }
			local profile = Profile.load(broken, UPGRADE_IDS)
			expect(profile.levels.Pickaxe).toBe(4)
		end)
	end)

	describe("consumeOfflineWindow", function()
		local function profileLastSeenAt(lastSeen: number)
			local p = Profile.default(UPGRADE_IDS)
			p.lastSeen = lastSeen
			return p
		end

		it("reports the time between the last exit and now", function()
			local elapsed = Profile.consumeOfflineWindow(profileLastSeenAt(1000), 4600)
			expect(elapsed).toBe(3600)
		end)

		it("stamps lastSeen with the current time", function()
			local _, updated = Profile.consumeOfflineWindow(profileLastSeenAt(1000), 4600)
			expect(updated.lastSeen).toBe(4600)
		end)

		--[[
			The reason this function exists. A rejoin, a retry or a duplicated
			load must not pay for the same stretch of time twice, whatever the
			economy config says that time is worth.
		]]
		it("pays nothing for a window already consumed", function()
			local first, afterFirst = Profile.consumeOfflineWindow(profileLastSeenAt(1000), 4600)
			local second = Profile.consumeOfflineWindow(afterFirst, 4600)

			expect(first).toBe(3600)
			expect(second).toBe(0)
		end)

		it("only pays for time accrued since the last consume", function()
			local _, afterFirst = Profile.consumeOfflineWindow(profileLastSeenAt(1000), 4600)
			local second = Profile.consumeOfflineWindow(afterFirst, 4900)

			expect(second).toBe(300)
		end)

		--[[
			lastSeen = 0 means "never seen", not "away since the epoch". A new
			or freshly migrated player would otherwise be handed a payout for
			fifty-odd years.
		]]
		it("pays nothing for a profile that was never seen", function()
			local elapsed, updated = Profile.consumeOfflineWindow(profileLastSeenAt(0), 1_700_000_000)

			expect(elapsed).toBe(0)
			expect(updated.lastSeen).toBe(1_700_000_000)
		end)

		it("pays nothing when the clock moved backwards", function()
			local elapsed, updated = Profile.consumeOfflineWindow(profileLastSeenAt(5000), 1000)

			expect(elapsed).toBe(0)
			-- and re-anchors, so the next window is measured from the new now
			expect(updated.lastSeen).toBe(1000)
		end)

		--[[
			A nonsense clock reading must not reach the save: stamping NaN
			would poison every window calculation that follows.
		]]
		it("refuses to stamp a NaN clock", function()
			local elapsed, updated = Profile.consumeOfflineWindow(profileLastSeenAt(1000), 0 / 0)

			expect(elapsed).toBe(0)
			expect(updated.lastSeen).toBe(1000)
		end)

		it("refuses to stamp an infinite clock", function()
			local _, updated = Profile.consumeOfflineWindow(profileLastSeenAt(1000), math.huge)
			expect(updated.lastSeen).toBe(1000)
		end)

		--[[
			The original is left untouched so a caller that fails partway
			through crediting does not leave a consumed window behind.
		]]
		it("does not mutate the profile it was given", function()
			local original = profileLastSeenAt(1000)
			Profile.consumeOfflineWindow(original, 4600)

			expect(original.lastSeen).toBe(1000)
		end)
	end)

	describe("load: unknown upgrades", function()
		--[[
			An upgrade can be pulled from the config temporarily. Deleting the
			player's progress on it would be irreversible, and
			Balance.totalIncomePerSecond already ignores unknown ids.
		]]
		it("keeps levels for upgrades no longer in the config", function()
			local retired = {
				version = 3,
				levels = { Pickaxe = 2, RetiredUpgrade = 15 },
			}

			local profile = Profile.load(retired, UPGRADE_IDS)

			expect(profile.levels.RetiredUpgrade).toBe(15)
			expect(profile.levels.Pickaxe).toBe(2)
		end)
	end)
end
