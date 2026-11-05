-- Server entry point: the only Script on the server. Every system is a
-- ModuleScript started here in a fixed order, so nothing races anything else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)

-- 1. Remotes first, so clients that WaitForChild them never hang.
Remotes.init()

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local PlayerSync = require(Services.PlayerSync)
local RagdollService = require(Services.RagdollService)
local CosmeticService = require(Services.CosmeticService)
local StatsService = require(Services.StatsService)
local ZoneService = require(Services.ZoneService)
local TargetService = require(Services.TargetService)
local CombatService = require(Services.CombatService)
local ShopService = require(Services.ShopService)
local LeaderboardService = require(Services.LeaderboardService)

-- 2. Tests (Studio only) before anything mutates state.
if RunService:IsStudio() and GameConfig.Dev.RunTests then
	require(script.Parent.Dev.ProgressionTests).run()
end

-- 3. World, then the systems that hook player events, then data loading
--    (DataService last so its ProfileLoaded listeners are all connected).
ZoneService.start()
TargetService.start(ZoneService.zones)
PlayerSync.start()
RagdollService.start()
CosmeticService.start()
StatsService.start()
CombatService.start()
ShopService.start()
LeaderboardService.start()
DataService.start()

if RunService:IsStudio() and GameConfig.Dev.ChatCommands then
	require(Services.DevService).start()
end

print("[PunchKick] Server started")
