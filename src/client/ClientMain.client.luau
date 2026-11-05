-- Client entry point: the only LocalScript. Starts every controller in order
-- and wires server events to the UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local ProfileState = require(Controllers:WaitForChild("ProfileState"))
local RagdollClient = require(Controllers:WaitForChild("RagdollClient"))
local EffectsController = require(Controllers:WaitForChild("EffectsController"))
local CombatController = require(Controllers:WaitForChild("CombatController"))
local HUD = require(UI:WaitForChild("HUD"))
local MenuUI = require(UI:WaitForChild("MenuUI"))

local player = Players.LocalPlayer

-- No tools in this game: hide the default backpack (it would also grab keys 1-4).
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local hud = HUD.new()
local menu = MenuUI.new()

RagdollClient.start()
EffectsController.start()
CombatController.start(hud, menu)

ProfileState.Changed:Connect(function(data)
	hud:render(data)
	menu:render(data)
end)

Remotes.get("Notify").OnClientEvent:Connect(function(text, kind)
	if type(text) == "string" then
		hud:toast(text, if type(kind) == "string" then kind else nil)
	end
end)

Remotes.get("LevelUp").OnClientEvent:Connect(function(level)
	if type(level) == "number" then
		hud:levelUp(level)
	end
end)

Remotes.get("KoFeed").OnClientEvent:Connect(function(attacker, victim)
	if type(attacker) == "string" and type(victim) == "string" then
		hud:koFeed(attacker, victim)
	end
end)

player:GetAttributeChangedSignal("Zone"):Connect(function()
	local zone = player:GetAttribute("Zone")
	hud:setZone(if type(zone) == "string" then zone else "")
end)

player:GetAttributeChangedSignal("Streak"):Connect(function()
	local streak = player:GetAttribute("Streak")
	if type(streak) == "number" then
		hud:setStreak(streak)
	end
end)

-- Start listening for profile pushes last, so every listener above is ready.
ProfileState.start()
