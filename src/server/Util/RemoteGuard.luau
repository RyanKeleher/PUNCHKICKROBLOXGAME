-- One place that wires a client->server remote with the protections every
-- handler needs: a per-player rate limit (from GameConfig.RateLimits) and
-- error isolation, so a bad request logs a warning instead of a silent failure.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.RateLimiter)

local RemoteGuard = {}

function RemoteGuard.connect(name: string, handler: (Player, ...any) -> ())
	local limits = GameConfig.RateLimits[name] or { rate = 5, burst = 10 }
	local limiter = RateLimiter.new(limits.rate, limits.burst)
	Remotes.get(name).OnServerEvent:Connect(function(player, ...)
		if not limiter:check(player) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[RemoteGuard] {name} from {player.Name} errored: {err}`)
		end
	end)
end

return RemoteGuard
