-- Spending coins: unlocking moves, managing the 4-slot loadout, buying and
-- equipping cosmetics, and the daily reward. Every purchase is checked
-- against the server's copy of the profile (level, coins, ownership).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Moves = require(Shared.Config.Moves)
local Cosmetics = require(Shared.Config.Cosmetics)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local Util = script.Parent.Parent.Util
local RemoteGuard = require(Util.RemoteGuard)
local Validate = require(Util.Validate)

local DataService = require(script.Parent.DataService)
local PlayerSync = require(script.Parent.PlayerSync)
local CosmeticService = require(script.Parent.CosmeticService)

local ShopService = {}

local function notify(player: Player, text: string, kind: string?)
	Remotes.get("Notify"):FireClient(player, text, kind)
end

local function equipMove(data, slot: number, moveId: string)
	-- A move can only sit in one slot: clear it from any other slot first.
	if moveId ~= "" then
		for i = 1, GameConfig.LoadoutSize do
			if data.loadout[i] == moveId then
				data.loadout[i] = ""
			end
		end
	end
	data.loadout[slot] = moveId
end

function ShopService.start()
	RemoteGuard.connect("UnlockMove", function(player, moveId)
		local data = DataService.get(player)
		if not data or not Validate.str(moveId, 32) then
			return
		end
		local move = Moves.byId[moveId]
		if not move or move.basic or data.unlockedMoves[moveId] then
			return
		end
		if data.level < move.unlockLevel then
			notify(player, `{move.name} unlocks at level {move.unlockLevel}`, "error")
			return
		end
		if data.coins < move.price then
			notify(player, `Need {Format.commas(move.price - data.coins)} more coins`, "error")
			return
		end
		data.coins -= move.price
		data.unlockedMoves[moveId] = true
		-- Drop it into the first empty slot, if any.
		local empty = table.find(data.loadout, "")
		if empty then
			equipMove(data, empty, moveId)
		end
		notify(player, `Unlocked {move.name}!`, "success")
		PlayerSync.pushNow(player)
	end)

	RemoteGuard.connect("EquipMove", function(player, slot, moveId)
		local data = DataService.get(player)
		if not data or not Validate.int(slot, 1, GameConfig.LoadoutSize) or not Validate.str(moveId, 32) then
			return
		end
		if moveId ~= "" then
			local move = Moves.byId[moveId]
			if not move or move.basic or not data.unlockedMoves[moveId] then
				return
			end
		end
		equipMove(data, slot, moveId)
		PlayerSync.pushNow(player)
	end)

	RemoteGuard.connect("BuyCosmetic", function(player, id)
		local data = DataService.get(player)
		if not data or not Validate.str(id, 48) then
			return
		end
		local item = Cosmetics.byId[id]
		if not item or data.ownedCosmetics[id] then
			return
		end
		if data.rebirths < item.requiresRebirths then
			notify(player, `Requires {item.requiresRebirths} rebirth(s)`, "error")
			return
		end
		if data.coins < item.price then
			notify(player, `Need {Format.commas(item.price - data.coins)} more coins`, "error")
			return
		end
		data.coins -= item.price
		data.ownedCosmetics[id] = true
		data.equipped[item.category] = id
		CosmeticService.apply(player)
		notify(player, `Bought {item.name}!`, "success")
		PlayerSync.pushNow(player)
	end)

	RemoteGuard.connect("EquipCosmetic", function(player, category, id)
		local data = DataService.get(player)
		if not data or not Validate.str(category, 16) or not Validate.str(id, 48) then
			return
		end
		if data.equipped[category] == nil then
			return -- unknown category
		end
		if id ~= "" then
			local item = Cosmetics.byId[id]
			if not item or item.category ~= category or not data.ownedCosmetics[id] then
				return
			end
		end
		data.equipped[category] = id
		CosmeticService.apply(player)
		PlayerSync.pushNow(player)
	end)

	RemoteGuard.connect("ClaimDaily", function(player)
		local data = DataService.get(player)
		if not data then
			return
		end
		local cooldown = GameConfig.Daily.CooldownHours * 3600
		local now = os.time()
		local remaining = data.lastDaily + cooldown - now
		if remaining > 0 then
			notify(player, `Next reward in {Format.duration(remaining)}`, "error")
			return
		end
		local base = GameConfig.Daily.CoinsBase + data.level * GameConfig.Daily.CoinsPerLevel
		local coins = math.floor(base * Progression.rewardMultiplier(data))
		data.lastDaily = now
		data.coins += coins
		notify(player, `Daily reward: +{Format.commas(coins)} coins!`, "success")
		PlayerSync.pushNow(player)
	end)

end

return ShopService
