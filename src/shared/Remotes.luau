-- Every RemoteEvent in the game, created by the server at startup.
-- A fixed list means a typo is an error instead of a silently missing remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

Remotes.Names = {
	-- client -> server (each one is rate limited and validated on the server)
	"Attack", -- (moveId: string, facing: Vector3)
	"SpendStat", -- (stat: string, amount: number)
	"UnlockMove", -- (moveId: string)
	"EquipMove", -- (slot: number, moveId: string)  "" clears the slot
	"BuyCosmetic", -- (cosmeticId: string)
	"EquipCosmetic", -- (category: string, cosmeticId: string)  "" unequips
	"Rebirth", -- ()
	"ClaimDaily", -- ()
	"Emote", -- (emoteId: string)
	"RequestSync", -- ()

	-- server -> client
	"ProfileUpdated", -- (data)
	"AttackFx", -- (character: Model, moveId: string, variant: number)
	"HitFx", -- (position: Vector3, damage: number, isKo: boolean, moveId: string, target: Model?)
	"Knockback", -- (velocity: Vector3, ragdollSeconds: number)
	"Notify", -- (text: string, kind: string?)
	"LevelUp", -- (newLevel: number)
	"KoFeed", -- (attackerName: string, victimName: string)
	"PoseFx", -- (character: Model, emoteId: string)
}

local cache: { [string]: RemoteEvent } = {}

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
	end
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
	local remote = ReplicatedStorage:WaitForChild(FOLDER_NAME):WaitForChild(name) :: RemoteEvent
	cache[name] = remote
	return remote
end

return Remotes
