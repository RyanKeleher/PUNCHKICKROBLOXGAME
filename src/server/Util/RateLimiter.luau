-- Token-bucket rate limiter, one bucket per player.
-- Each request costs 1 token; tokens refill at `rate`/sec up to `burst`.
-- Short bursts are fine (fast clicking), sustained spam gets dropped.

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local all = {}

function RateLimiter.new(rate: number, burst: number)
	local self = setmetatable({ rate = rate, burst = burst, buckets = {} }, RateLimiter)
	table.insert(all, self)
	return self
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

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in all do
		limiter.buckets[player] = nil
	end
end)

return RateLimiter
