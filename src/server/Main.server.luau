-- Server entry point. The only Script on the server; everything else is a
-- ModuleScript that this file starts in a known order. One entry point means
-- no race conditions between scripts that each assume the others ran first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

-- 1. Create all RemoteEvents before anything tries to use them.
Remotes.init()

-- 2. Start services (order matters only where one depends on another being ready).
local Services = script.Parent.Services
local InventoryService = require(Services.InventoryService)

InventoryService.start()

-- 3. Studio-only tests and test content.
if RunService:IsStudio() then
	require(script.Parent.Dev.InventoryLogicTests).run()
	if Config.Dev.SpawnTestItems then
		require(script.Parent.Dev.DevSpawner).run()
	end
end

print("[Driftwood] Server started")
