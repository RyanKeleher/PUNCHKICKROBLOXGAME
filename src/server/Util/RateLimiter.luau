-- Token-bucket rate limiter, one bucket per player.
-- Each request costs 1 token; tokens refill at `rate` per second up to `burst`.
-- This allows short bursts (fast drag-and-drop) but caps sustained spam.

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local allLimiters = {}

function RateLimiter.new(rate: number, burst: number)
	local self = setmetatable({
		rate = rate,
		burst = burst,
		buckets = {} :: { [Player]: { tokens: number, last: number } },
	}, RateLimiter)
	table.insert(allLimiters, self)
	return self
end

function RateLimiter.fromConfig(entry: { rate: number, burst: number })
	return RateLimiter.new(entry.rate, entry.burst)
end

function RateLimiter:check(player: Player): boolean
	local now = os.clock()
	local bucket = self.buckets[player]
	if not bucket then
		bucket = { tokens = self.burst, last = now }
		self.buckets[player] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (now - bucket.last) * self.rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Free memory when players leave (every limiter, automatically).
Players.PlayerRemoving:Connect(function(player)
	for _, limiter in allLimiters do
		limiter.buckets[player] = nil
	end
end)

return RateLimiter
