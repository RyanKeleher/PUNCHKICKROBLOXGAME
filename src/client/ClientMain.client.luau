-- Client entry point: the only LocalScript. Starts controllers in order.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- Our hotbar replaces Roblox's default Backpack (which would also grab keys 1-9).
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
if Config.UI.HidePlayerList then
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end

local Controllers = script.Parent:WaitForChild("Controllers")
local InventoryController = require(Controllers:WaitForChild("InventoryController"))

InventoryController.start()
