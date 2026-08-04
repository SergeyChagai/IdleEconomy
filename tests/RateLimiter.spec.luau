--!strict
--[[
	Rate limiter tests.

	Time is fed in by hand, so the whole suite runs instantly -- not a single
	real-time wait. That is exactly why time was made an argument.
]]

local RateLimiter = require("../src/shared/Economy/RateLimiter")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("burst", function()
		it("accepts requests within the capacity", function()
			local limiter = RateLimiter.new(5, 1, 0)

			for _ = 1, 5 do
				expect(limiter:tryConsume(0)).toBeTruthy()
			end
		end)

		--[[ The central check: nothing beyond the capacity gets through at
		     the same instant. This is what stops an autoclicker. ]]
		it("rejects a request past the capacity", function()
			local limiter = RateLimiter.new(5, 1, 0)

			for _ = 1, 5 do
				limiter:tryConsume(0)
			end

			expect(limiter:tryConsume(0)).toBeFalsy()
		end)

		it("starts with a full bucket", function()
			local limiter = RateLimiter.new(3, 1, 0)
			expect(limiter:available()).toBe(3)
		end)
	end)

	describe("refill", function()
		it("refills over time", function()
			local limiter = RateLimiter.new(5, 2, 0)

			for _ = 1, 5 do
				limiter:tryConsume(0)
			end
			expect(limiter:tryConsume(0)).toBeFalsy()

			-- One second passed at 2 per second -> 2 tokens
			expect(limiter:tryConsume(1)).toBeTruthy()
			expect(limiter:tryConsume(1)).toBeTruthy()
			expect(limiter:tryConsume(1)).toBeFalsy()
		end)

		it("never accumulates past the capacity", function()
			local limiter = RateLimiter.new(5, 10, 0)

			-- An hour passed: at 10/s that would be 36000 tokens, handing
			-- the player the right to an enormous burst
			limiter:tryConsume(3600)

			expect(limiter:available()).toBeLessThan(5)
		end)

		it("sustains the allowed rate indefinitely", function()
			local limiter = RateLimiter.new(5, 5, 0)
			local now = 0

			-- Exactly at the refill rate: must always pass
			for _ = 1, 100 do
				now += 0.2
				expect(limiter:tryConsume(now)).toBeTruthy()
			end
		end)

		it("throttles a rate above the allowance", function()
			local limiter = RateLimiter.new(5, 5, 0)
			local now = 0
			local rejected = 0

			-- Three times faster than allowed
			for _ = 1, 100 do
				now += 0.066
				if not limiter:tryConsume(now) then
					rejected += 1
				end
			end

			expect(rejected).toBeGreaterThan(50)
		end)
	end)

	describe("robustness", function()
		--[[
			A server clock can be adjusted backwards. A naive computation
			would produce a negative refill, the bucket would go below zero,
			and the player would be locked out for a long time for nothing.
		]]
		it("time moving backwards does not push the bucket negative", function()
			local limiter = RateLimiter.new(5, 1, 100)

			limiter:tryConsume(100)
			limiter:tryConsume(50) -- clock jumped backwards

			expect(limiter:available()).toBeGreaterThan(-1)
			expect(limiter:tryConsume(50)).toBeTruthy()
		end)

		it("rejects NaN time", function()
			local limiter = RateLimiter.new(5, 1, 0)
			expect(limiter:tryConsume(0 / 0)).toBeFalsy()
		end)

		--[[ Without this check an infinite timestamp would refill the bucket
		     forever and the limiter would stop limiting anything ]]
		it("rejects infinite time", function()
			local limiter = RateLimiter.new(5, 1, 0)
			expect(limiter:tryConsume(math.huge)).toBeFalsy()
		end)

		it("the bucket never drops below zero on rejections", function()
			local limiter = RateLimiter.new(2, 1, 0)

			for _ = 1, 50 do
				limiter:tryConsume(0)
			end

			expect(limiter:available()).toBeGreaterThan(-0.001)
		end)
	end)
end
