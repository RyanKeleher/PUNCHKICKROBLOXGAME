-- Puts equipped cosmetics (aura, trail, gloves, title) and the overhead name tag
-- on a player's character. Everything is built on the server so all players see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Config.Cosmetics)
local DataService = require(script.Parent.DataService)

local CosmeticService = {}

local FOLDER = "PK_Cosmetics"

local function clear(character: Model)
	local folder = character:FindFirstChild(FOLDER)
	if folder then
		folder:Destroy()
	end
	for _, d in character:GetDescendants() do
		if d:GetAttribute("PKCosmetic") then
			d:Destroy()
		end
	end
end

local function tag(instance: Instance)
	instance:SetAttribute("PKCosmetic", true)
end

local function getPart(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function addAura(character: Model, item)
	local root = getPart(character, "HumanoidRootPart")
	if not root then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "AuraAttachment"
	tag(att)
	att.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(item.color, item.color2 or item.color)
	emitter.LightEmission = 0.8
	emitter.Rate = 25
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	emitter.Acceleration = Vector3.new(0, 3, 0)
	emitter.Parent = att

	local light = Instance.new("PointLight")
	light.Color = item.color
	light.Range = 8
	light.Brightness = 0.8
	light.Parent = att
end

local function addTrail(character: Model, item)
	local root = getPart(character, "HumanoidRootPart")
	if not root then
		return
	end
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1, 0.4)
	tag(top)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -1.5, 0.4)
	tag(bottom)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(item.color, item.color2 or item.color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.MinLength = 0.1
	tag(trail)
	trail.Parent = root
end

local function addGloves(character: Model, item)
	for _, names in { { "RightHand", "Right Arm" }, { "LeftHand", "Left Arm" } } do
		local hand = getPart(character, names[1], names[2])
		if hand then
			local glove = Instance.new("Part")
			glove.Name = "Glove"
			local isR6 = hand.Name == "Right Arm" or hand.Name == "Left Arm"
			glove.Size = if isR6 then Vector3.new(1.15, 0.8, 1.15) else hand.Size * 1.25
			glove.Color = item.color
			glove.Material = item.material or Enum.Material.SmoothPlastic
			glove.CanCollide = false
			glove.CanQuery = false
			glove.CanTouch = false
			glove.Massless = true
			tag(glove)

			local weld = Instance.new("Weld")
			weld.Part0 = hand
			weld.Part1 = glove
			-- On R6 the "hand" is the bottom of the arm.
			weld.C0 = if isR6 then CFrame.new(0, -0.65, 0) else CFrame.new()
			weld.Parent = glove
			glove.Parent = character
		end
	end
end

-- Overhead tag: name, level, rebirth stars, and the equipped title.
function CosmeticService.refreshTag(player: Player)
	local character = player.Character
	local data = DataService.get(player)
	local head = character and getPart(character, "Head")
	if not head or not data then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local gui = head:FindFirstChild("PK_NameTag")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "PK_NameTag"
		gui.Size = UDim2.fromOffset(220, 64)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 120
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0

		local function label(name: string, y: number, h: number, size: number)
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.Size = UDim2.new(1, 0, 0, h)
			l.Position = UDim2.fromOffset(0, y)
			l.Font = Enum.Font.GothamBlack
			l.TextSize = size
			l.TextColor3 = Color3.new(1, 1, 1)
			l.TextStrokeTransparency = 0.4
			l.Parent = gui
			return l
		end
		label("Title", 0, 18, 14)
		label("Name", 18, 24, 18)
		label("Level", 42, 20, 14)
		gui.Parent = head
	end

	local title = gui:FindFirstChild("Title") :: TextLabel
	local nameLabel = gui:FindFirstChild("Name") :: TextLabel
	local levelLabel = gui:FindFirstChild("Level") :: TextLabel

	local item = Cosmetics.byId[data.equipped.title]
	title.Text = if item then item.text else ""
	title.TextColor3 = if item then item.color else Color3.new(1, 1, 1)
	nameLabel.Text = player.DisplayName
	local stars = if data.rebirths > 0 then `  ★{data.rebirths}` else ""
	levelLabel.Text = `Lv {data.level}{stars}`
	levelLabel.TextColor3 = if data.rebirths > 0 then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(200, 230, 255)
end

function CosmeticService.apply(player: Player)
	local character = player.Character
	local data = DataService.get(player)
	if not character or not data then
		return
	end
	clear(character)
	for category, id in data.equipped do
		local item = Cosmetics.byId[id]
		if item and data.ownedCosmetics[id] then
			if category == "aura" then
				addAura(character, item)
			elseif category == "trail" then
				addTrail(character, item)
			elseif category == "gloves" then
				addGloves(character, item)
			end
		end
	end
	CosmeticService.refreshTag(player)
end

function CosmeticService.start()
	local function hook(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			-- After the avatar's parts are final, so gloves weld to the right hands.
			CosmeticService.apply(player)
		end)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			CosmeticService.apply(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	DataService.ProfileLoaded:Connect(function(player)
		CosmeticService.apply(player)
	end)
end

return CosmeticService
