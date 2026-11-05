-- Items lying in the world: single dropped stacks now, death loot bags in Phase 4.
--
-- Security model: the Part in Workspace is only a visual + a ProximityPrompt.
-- The real contents live in the server-only `records` table, keyed by id.
-- Clients can't edit server state, so they can't change what a bag contains.
--
-- ProximityPrompt gives us pickup input on PC (E), controller (X) and mobile (tap)
-- for free, and its Triggered event fires on the SERVER. We still re-check range
-- and rate-limit, because exploiters can fire prompts from far away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemDefinitions = require(Shared.ItemDefinitions)
local Remotes = require(Shared.Remotes)

local Util = script.Parent.Parent.Util
local RateLimiter = require(Util.RateLimiter)
local CharacterUtil = require(Util.CharacterUtil)

type Stack = { id: string, count: number }
type Record = {
	id: number,
	stacks: { Stack },
	part: BasePart,
	prompt: ProximityPrompt,
}

local WorldItemService = {}

local records: { [number]: Record } = {}
local spawnOrder: { number } = {} -- oldest first, for the MaxActive cap
local nextId = 0
local pickupHandler: ((Player, { Stack }) -> { Stack })? = nil
local pickupLimiter = RateLimiter.fromConfig(Config.RateLimits.Pickup)

local folder = Instance.new("Folder")
folder.Name = "WorldItems"
folder.Parent = workspace

local function describe(stacks: { Stack }): string
	if #stacks == 1 then
		local def = ItemDefinitions.get(stacks[1].id)
		local name = if def then def.name else stacks[1].id
		return if stacks[1].count > 1 then `{name} x{stacks[1].count}` else name
	end
	return `Loot Bag ({#stacks} stacks)`
end

local function remove(id: number)
	local record = records[id]
	if not record then
		return
	end
	records[id] = nil
	local index = table.find(spawnOrder, id)
	if index then
		table.remove(spawnOrder, index)
	end
	record.part:Destroy()
end

-- Who provides the "put these stacks into this player's inventory" logic.
-- InventoryService registers itself here; this avoids a circular require.
function WorldItemService.setPickupHandler(handler: (Player, { Stack }) -> { Stack })
	pickupHandler = handler
end

-- Finds a spot on the ground in front of a character.
function WorldItemService.dropPositionFor(root: BasePart): Vector3
	local origin = root.Position + root.CFrame.LookVector * 3 + Vector3.new(0, 2, 0)

	local exclude: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	local result = workspace:Raycast(origin, Vector3.new(0, -30, 0), params)
	return if result then result.Position else origin - Vector3.new(0, 2, 0)
end

-- Spawns a container holding `stacks` at `position`. Returns its id.
function WorldItemService.spawnDrop(stacks: { Stack }, position: Vector3): number
	nextId += 1
	local id = nextId

	local isBag = #stacks > 1
	local part = Instance.new("Part")
	part.Name = if isBag then "LootBag" else "DroppedItem"
	part.Size = if isBag then Vector3.new(1.6, 1.2, 1.6) else Vector3.new(1, 1, 1)
	part.Anchored = true -- no physics simulation cost
	part.CanCollide = false
	part.CanTouch = false
	part.Material = Enum.Material.Fabric
	local firstDef = ItemDefinitions.get(stacks[1].id)
	part.Color = if isBag or not firstDef then Color3.fromRGB(95, 70, 45) else firstDef.color
	part.CFrame = CFrame.new(position + Vector3.new(0, part.Size.Y / 2, 0))
		* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	part:SetAttribute("WorldItemId", id)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = describe(stacks)
	prompt.MaxActivationDistance = Config.WorldItems.PickupRange
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = part

	local record: Record = { id = id, stacks = stacks, part = part, prompt = prompt }
	records[id] = record
	table.insert(spawnOrder, id)

	prompt.Triggered:Connect(function(player)
		local current = records[id]
		if not current or not pickupHandler then
			return
		end
		if not pickupLimiter:check(player) then
			return
		end
		local root = CharacterUtil.getAliveRoot(player)
		if not root then
			return
		end
		-- +3 studs of slack for latency/character size.
		if (root.Position - current.part.Position).Magnitude > Config.WorldItems.PickupRange + 3 then
			return
		end

		-- IMPORTANT: no yields between reading and writing state below. Lua on the
		-- server runs one handler at a time, so two players grabbing the same bag
		-- in the same frame can't both get the items.
		local leftovers = pickupHandler(player, current.stacks)
		if #leftovers == 0 then
			remove(id)
		else
			current.stacks = leftovers
			current.prompt.ObjectText = describe(leftovers)
			Remotes.get("Notify"):FireClient(player, "Inventory full")
		end
	end)

	part.Parent = folder

	-- Enforce the server-wide cap by evicting the oldest drops.
	while #spawnOrder > Config.WorldItems.MaxActive do
		local oldest = table.remove(spawnOrder, 1) :: number
		remove(oldest)
	end

	-- Despawn timer. One task.delay per drop: no per-frame loop needed.
	task.delay(Config.WorldItems.DespawnSeconds, remove, id)

	return id
end

return WorldItemService
