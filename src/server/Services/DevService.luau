-- Studio-only chat commands for testing. Main.server only starts this when
-- RunService:IsStudio() is true, so none of it exists in a live server.
--
-- Prefix with ! (or / or ;). "!" is safest: the new chat may treat unknown
-- "/" messages as commands and not send them.
--   !coins 5000     add coins
--   !level 30       set level (stat points granted for the levels skipped)
--   !xp 1000        add XP (goes through normal level-up logic)
--   !points 20      add stat points
--   !rebirths 2     set rebirth count
--   !unlockall      own every move and cosmetic
--   !reset          wipe your profile for this session

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Moves = require(Shared.Config.Moves)
local Cosmetics = require(Shared.Config.Cosmetics)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local PlayerSync = require(script.Parent.PlayerSync)
local StatsService = require(script.Parent.StatsService)
local CosmeticService = require(script.Parent.CosmeticService)

local DevService = {}

local function handle(player: Player, message: string)
	local command, arg = string.match(message, "^[!/;](%a+)%s*(%S*)")
	if not command then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local n = tonumber(arg) or 0
	command = string.lower(command)

	if command == "coins" then
		data.coins += math.max(0, math.floor(n))
	elseif command == "level" then
		local target = math.clamp(math.floor(n), 1, GameConfig.Progression.MaxLevel)
		if target > data.level then
			data.statPoints += (target - data.level) * GameConfig.Progression.StatPointsPerLevel
		end
		data.level = target
		data.xp = 0
	elseif command == "xp" then
		StatsService.addXp(player, math.max(0, n))
	elseif command == "points" then
		data.statPoints += math.max(0, math.floor(n))
	elseif command == "rebirths" then
		data.rebirths = math.max(0, math.floor(n))
	elseif command == "unlockall" then
		for _, move in Moves.list do
			data.unlockedMoves[move.id] = true
		end
		for _, item in Cosmetics.list do
			data.ownedCosmetics[item.id] = true
		end
	elseif command == "reset" then
		DataService.resetForDev(player)
	else
		return
	end

	StatsService.applyCharacter(player)
	CosmeticService.apply(player)
	PlayerSync.pushNow(player)
	Remotes.get("Notify"):FireClient(player, `[dev] {message}`, "success")
end

function DevService.start()
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			handle(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	print("[DevService] Studio chat commands enabled: !coins !level !xp !points !rebirths !unlockall !reset")
end

return DevService
