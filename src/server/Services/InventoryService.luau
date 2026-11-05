-- Owns every player's inventory. The server copy is the ONLY real one; the
-- client just receives snapshots and draws them. Clients send *requests*
-- ("move slot 3 to slot 9"), never state ("I now have 1000 wood").
--
-- Public API (used by later phases: gathering, crafting, death, persistence):
--   InventoryService.getSlots(player)              -> Slots?
--   InventoryService.addItem(player, id, count)    -> leftover count
--   InventoryService.addStacks(player, stacks)     -> leftover stacks
--   InventoryService.removeItem(player, id, count) -> removed count
--   InventoryService.countItem(player, id)         -> number
--   InventoryService.getEquipped(player)           -> (slotIndex, Stack | false)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemDefinitions = require(Shared.ItemDefinitions)
local InventoryLogic = require(Shared.InventoryLogic)
local Remotes = require(Shared.Remotes)

local Util = script.Parent.Parent.Util
local RateLimiter = require(Util.RateLimiter)
local Validate = require(Util.Validate)
local CharacterUtil = require(Util.CharacterUtil)

local WorldItemService = require(script.Parent.WorldItemService)

type Stack = InventoryLogic.Stack
type Slots = InventoryLogic.Slots

local HOTBAR = Config.Inventory.HotbarSize
local TOTAL = HOTBAR + Config.Inventory.MainSize

-- Fill orders for new stacks: tools/weapons prefer the hotbar, everything else the main grid.
local ORDER_HOTBAR_FIRST: { number } = {}
local ORDER_MAIN_FIRST: { number } = {}
for i = 1, TOTAL do
	table.insert(ORDER_HOTBAR_FIRST, i)
end
for i = HOTBAR + 1, TOTAL do
	table.insert(ORDER_MAIN_FIRST, i)
end
for i = 1, HOTBAR do
	table.insert(ORDER_MAIN_FIRST, i)
end

local function orderFor(id: string): { number }
	local def = ItemDefinitions.get(id)
	if def and (def.category == "Tool" or def.category == "Weapon") then
		return ORDER_HOTBAR_FIRST
	end
	return ORDER_MAIN_FIRST
end

local InventoryService = {}

local inventories: { [Player]: Slots } = {}
local equippedSlot: { [Player]: number } = {}

-- ===== Held item visual =====

local function findHand(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- Makes the character visibly hold the equipped item (a simple welded part
-- until we have real models). Built on the server so everyone sees it.
local function refreshHeld(player: Player)
	local slots = inventories[player]
	local character = player.Character
	if not slots or not character then
		return
	end

	local slot = equippedSlot[player] or 0
	local stack = if slot > 0 then slots[slot] else false
	local def = if stack then ItemDefinitions.get(stack.id) else nil
	local newId = if def and def.equippable then def.id else nil

	local existing = character:FindFirstChild("HeldItem")
	if existing and existing:GetAttribute("ItemId") == newId then
		return -- already holding the right thing
	end
	if existing then
		existing:Destroy()
	end
	character:SetAttribute("EquippedItem", newId)

	local hand = findHand(character)
	if not newId or not def or not def.held or not hand then
		return
	end

	local held = def.held
	local handle = Instance.new("Part")
	handle.Name = "HeldItem"
	handle:SetAttribute("ItemId", newId)
	handle.Size = held.size
	handle.Color = held.color
	handle.Material = held.material or Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true

	-- Grip at the bottom of the hand, item pointing forward.
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	weld.C1 = CFrame.new(0, -held.size.Y * 0.3, 0)
	weld.Parent = handle

	if held.light then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Range = 18
		light.Brightness = 1.6
		light.Shadows = true
		light.Parent = handle

		local fire = Instance.new("Fire")
		fire.Size = 2
		fire.Heat = 4
		fire.Parent = handle
	end

	handle.Parent = character
end

-- ===== Sync =====

function InventoryService.sync(player: Player)
	local slots = inventories[player]
	if slots then
		Remotes.get("InventoryUpdated"):FireClient(player, slots)
	end
end

local function changed(player: Player)
	InventoryService.sync(player)
	refreshHeld(player)
end

-- ===== Public API =====

function InventoryService.getSlots(player: Player): Slots?
	return inventories[player]
end

function InventoryService.addItem(player: Player, id: string, count: number): number
	local slots = inventories[player]
	if not slots or not ItemDefinitions.exists(id) or count <= 0 then
		return count
	end
	local leftover = InventoryLogic.add(slots, id, count, orderFor(id))
	if leftover < count then
		changed(player)
	end
	return leftover
end

function InventoryService.addStacks(player: Player, stacks: { Stack }): { Stack }
	local slots = inventories[player]
	if not slots then
		return stacks
	end
	local leftovers: { Stack } = {}
	local anyAdded = false
	for _, stack in stacks do
		local leftover = InventoryLogic.add(slots, stack.id, stack.count, orderFor(stack.id))
		if leftover < stack.count then
			anyAdded = true
		end
		if leftover > 0 then
			table.insert(leftovers, { id = stack.id, count = leftover })
		end
	end
	if anyAdded then
		changed(player)
	end
	return leftovers
end

function InventoryService.removeItem(player: Player, id: string, count: number): number
	local slots = inventories[player]
	if not slots then
		return 0
	end
	local removed = InventoryLogic.remove(slots, id, count)
	if removed > 0 then
		changed(player)
	end
	return removed
end

function InventoryService.countItem(player: Player, id: string): number
	local slots = inventories[player]
	return if slots then InventoryLogic.count(slots, id) else 0
end

function InventoryService.getEquipped(player: Player): (number, Stack | false)
	local slots = inventories[player]
	local slot = equippedSlot[player] or 0
	if not slots or slot == 0 then
		return 0, false
	end
	return slot, slots[slot]
end

-- ===== Remote handlers =====

-- Wraps a client->server remote with the checks every handler needs:
-- player has an inventory, and is within their rate limit.
local function bind(name: string, handler: (Player, Slots, ...any) -> ())
	local limiter = RateLimiter.fromConfig(Config.RateLimits[name])
	Remotes.get(name).OnServerEvent:Connect(function(player, ...)
		local slots = inventories[player]
		if not slots or not limiter:check(player) then
			return
		end
		handler(player, slots, ...)
	end)
end

local function onPlayerAdded(player: Player)
	local slots = InventoryLogic.new(TOTAL)
	for _, entry in Config.StarterKit do
		slots[entry.slot] = { id = entry.id, count = entry.count }
	end
	inventories[player] = slots
	equippedSlot[player] = 0
	player:SetAttribute("EquippedSlot", 0)

	player.CharacterAdded:Connect(function(character)
		-- Wait until the rig's hand exists, then re-create the held visual.
		character:WaitForChild("RightHand", 5)
		refreshHeld(player)
	end)
	if player.Character then
		task.spawn(refreshHeld, player)
	end

	InventoryService.sync(player)
end

function InventoryService.start()
	bind("InventoryMove", function(player, slots, from, to)
		if not Validate.int(from, 1, TOTAL) or not Validate.int(to, 1, TOTAL) then
			return
		end
		if InventoryLogic.move(slots, from, to) then
			changed(player)
		end
	end)

	bind("InventorySplit", function(player, slots, index, amount)
		if not Validate.int(index, 1, TOTAL) then
			return
		end
		local stack = slots[index]
		if not stack or not Validate.int(amount, 1, stack.count - 1) then
			return
		end
		if InventoryLogic.split(slots, index, amount, ORDER_MAIN_FIRST) then
			changed(player)
		else
			Remotes.get("Notify"):FireClient(player, "No empty slot to split into")
		end
	end)

	bind("InventoryDrop", function(player, slots, index, amount)
		if not Validate.int(index, 1, TOTAL) then
			return
		end
		local stack = slots[index]
		if not stack or not Validate.int(amount, 1, stack.count) then
			return
		end
		local root = CharacterUtil.getAliveRoot(player)
		if not root then
			return
		end
		-- take + spawn happen in the same synchronous step: no window for a dupe.
		local taken = InventoryLogic.take(slots, index, amount)
		if taken then
			WorldItemService.spawnDrop({ taken }, WorldItemService.dropPositionFor(root))
			changed(player)
		end
	end)

	bind("EquipSlot", function(player, _slots, index)
		if not Validate.int(index, 0, HOTBAR) then
			return
		end
		equippedSlot[player] = index
		player:SetAttribute("EquippedSlot", index)
		refreshHeld(player)
	end)

	bind("RequestSync", function(player)
		InventoryService.sync(player)
	end)

	WorldItemService.setPickupHandler(InventoryService.addStacks)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		equippedSlot[player] = nil
	end)
end

return InventoryService
