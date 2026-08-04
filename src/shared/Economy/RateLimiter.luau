--!strict
--[[
	Request rate limiter -- token bucket.

	Needed for any remote the player triggers directly. A human clicks the
	mine button 5-8 times per second, an autoclicker 200, and an exploit
	script calls the remote thousands of times. Without a limit that is a
	direct path to unlimited currency.

	Why a bucket rather than "no more than once every N ms": humans click
	unevenly -- a burst, then a pause. A hard interval punishes the real
	player and does nothing against a steady autoclicker. A bucket is the
	other way round: a short burst is fine (that is what the capacity is
	for), but a sustained high rate is not.

	Time is NOT read inside the module, it arrives as an argument. That keeps
	the class pure and lets the tests run without any real-time waiting.
]]

type RateLimiterFields = {
	_capacity: number,
	_refillPerSecond: number,
	_tokens: number,
	_lastRefill: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: RateLimiterFields, RateLimiter))

--[[
	capacity        -- burst allowance (clicks accepted back to back)
	refillPerSecond -- sustained refill rate
	now             -- current time in seconds
]]
function RateLimiter.new(capacity: number, refillPerSecond: number, now: number): RateLimiter
	return setmetatable({
		_capacity = capacity,
		_refillPerSecond = refillPerSecond,
		_tokens = capacity, -- start full so the very first click never waits
		_lastRefill = now,
	}, RateLimiter)
end

--[[
	Try to spend a single token. Returns true when the request is allowed.

	Time moving backwards is handled explicitly: servers do adjust their
	clocks. Computing elapsed naively would produce a negative refill, the
	bucket would go below zero, and the player would be locked out for a
	long time through no fault of their own.
]]
function RateLimiter.tryConsume(self: RateLimiter, now: number): boolean
	-- NaN never equals itself; infinity would refill the bucket forever
	if now ~= now or now == math.huge or now == -math.huge then
		return false
	end

	local elapsed = now - self._lastRefill

	if elapsed < 0 then
		-- Clock went backwards: do not refill, but do not punish either
		self._lastRefill = now
	else
		self._tokens = math.min(self._capacity, self._tokens + elapsed * self._refillPerSecond)
		self._lastRefill = now
	end

	if self._tokens < 1 then
		return false
	end

	self._tokens -= 1
	return true
end

--[[ Tokens currently available. For tests and debugging. ]]
function RateLimiter.available(self: RateLimiter): number
	return self._tokens
end

return RateLimiter
