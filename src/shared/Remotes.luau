--!strict
-- Single source of truth for every RemoteEvent in the game.
-- The server creates them (Remotes.init) at startup; clients wait for them.
-- Having a fixed list means a typo is an error, not a silently-missing remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

Remotes.Names = {
	-- client -> server (every one is validated + rate limited on the server)
	"InventoryMove", -- (fromSlot: number, toSlot: number)
	"InventorySplit", -- (slot: number, amount: number)
	"InventoryDrop", -- (slot: number, amount: number)
	"EquipSlot", -- (hotbarSlot: number)  0 = unequip
	"RequestSync", -- ()

	-- server -> client
	"InventoryUpdated", -- (slots: {Stack | false})
	"Notify", -- (text: string)
}

local cache: { [string]: RemoteEvent } = {}

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
	end
	assert(folder)
	for _, name in Remotes.Names do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	assert(table.find(Remotes.Names, name), "Unknown remote: " .. name)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	local remote = folder:WaitForChild(name) :: RemoteEvent
	cache[name] = remote
	return remote
end

return Remotes
