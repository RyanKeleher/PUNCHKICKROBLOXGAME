-- Sends each player their profile, throttled.
--
-- Punching a bag 3x a second changes XP 3x a second. Instead of firing a
-- remote on every change, services call PlayerSync.mark(player) and one loop
-- flushes dirty players every FLUSH_SECONDS. Many changes -> one network send.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local FLUSH_SECONDS = 0.15

local PlayerSync = {}

local dirty: { [Player]: boolean } = {}
local pushHooks: { (Player, any) -> () } = {}

-- Run `fn(player, data)` every time a profile is pushed (e.g. leaderstats).
function PlayerSync.onPush(fn: (Player, any) -> ())
	table.insert(pushHooks, fn)
end

function PlayerSync.mark(player: Player)
	dirty[player] = true
end

function PlayerSync.pushNow(player: Player)
	dirty[player] = nil
	local data = DataService.get(player)
	if not data or not player.Parent then
		return
	end
	Remotes.get("ProfileUpdated"):FireClient(player, data)
	for _, hook in pushHooks do
		task.spawn(hook, player, data)
	end
end

function PlayerSync.start()
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			for player in dirty do
				PlayerSync.pushNow(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

return PlayerSync
