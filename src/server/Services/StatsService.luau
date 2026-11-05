-- Levels, XP, coins, stat points, rebirths, and applying stats to characters.
--
-- Public API (used by CombatService, ShopService, DevService):
--   StatsService.addXp(player, amount)      -- applies rebirth multiplier, handles level ups
--   StatsService.addCoins(player, amount)   -- applies rebirth multiplier
--   StatsService.applyCharacter(player)     -- push MaxHealth / WalkSpeed to the humanoid

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local Util = script.Parent.Parent.Util
local RemoteGuard = require(Util.RemoteGuard)
local Validate = require(Util.Validate)

local DataService = require(script.Parent.DataService)
local PlayerSync = require(script.Parent.PlayerSync)
local CosmeticService = require(script.Parent.CosmeticService)

local StatsService = {}

local function notify(player: Player, text: string, kind: string?)
	Remotes.get("Notify"):FireClient(player, text, kind)
end

function StatsService.applyCharacter(player: Player, refill: boolean?)
	local data = DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not humanoid or humanoid.Health <= 0 then
		return
	end
	local maxHealth = Progression.maxHealth(data)
	local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = maxHealth
	humanoid.Health = if refill then maxHealth else math.clamp(ratio * maxHealth, 1, maxHealth)
	humanoid.WalkSpeed = Progression.walkSpeed(data)
end

local function updateLeaderstats(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local function set(name: string, value: number)
		local v = stats:FindFirstChild(name)
		if v and v:IsA("IntValue") then
			v.Value = value
		end
	end
	set("Level", data.level)
	set("Rebirths", data.rebirths)
	set("Coins", data.coins)
end

local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { "Level", "Rebirths", "Coins" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = folder
	end
	folder.Parent = player
end

function StatsService.addXp(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	local scaled = math.floor(amount * Progression.rewardMultiplier(data) + 0.5)
	local gained = Progression.addXp(data, scaled)
	if gained > 0 then
		Remotes.get("LevelUp"):FireClient(player, data.level)
		notify(player, `LEVEL {data.level}! +{gained * GameConfig.Progression.StatPointsPerLevel} stat points`, "level")
		StatsService.applyCharacter(player)
		CosmeticService.refreshTag(player)
	end
	PlayerSync.mark(player)
end

function StatsService.addCoins(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	data.coins += math.floor(amount * Progression.rewardMultiplier(data) + 0.5)
	PlayerSync.mark(player)
end

function StatsService.start()
	PlayerSync.onPush(updateLeaderstats)

	DataService.ProfileLoaded:Connect(function(player, data)
		createLeaderstats(player)
		updateLeaderstats(player, data)
		StatsService.applyCharacter(player, true)
		PlayerSync.pushNow(player)
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			StatsService.applyCharacter(player, true)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	RemoteGuard.connect("SpendStat", function(player, stat, amount)
		local data = DataService.get(player)
		if not data or not Validate.str(stat, 16) or data.stats[stat] == nil then
			return
		end
		if not Validate.int(amount, 1, 1000) then
			return
		end
		local room = GameConfig.Progression.StatCap - data.stats[stat]
		local spend = math.min(amount, data.statPoints, room)
		if spend <= 0 then
			notify(player, if room <= 0 then "That stat is maxed" else "No stat points left", "error")
			return
		end
		data.stats[stat] += spend
		data.statPoints -= spend
		StatsService.applyCharacter(player)
		PlayerSync.mark(player)
	end)

	RemoteGuard.connect("Rebirth", function(player)
		local data = DataService.get(player)
		if not data then
			return
		end
		local ok, reason = Progression.canRebirth(data)
		if not ok then
			notify(player, reason or "Can't rebirth yet", "error")
			return
		end
		Progression.applyRebirth(data)
		StatsService.applyCharacter(player, true)
		CosmeticService.refreshTag(player)
		PlayerSync.pushNow(player)
		for _, other in Players:GetPlayers() do
			notify(other, `{player.DisplayName} rebirthed! (★{data.rebirths})`, "rebirth")
		end
	end)

	RemoteGuard.connect("RequestSync", function(player)
		PlayerSync.pushNow(player)
	end)
end

return StatsService
