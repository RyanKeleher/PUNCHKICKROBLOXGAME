-- Spawns and manages training targets (bags, dummies, the boss).
--
-- HP lives in a server-only table, not in an attribute the client could read
-- as authoritative. The overhead HP bar is a replicated visual of that value.
-- On a knockout the model is unanchored and ragdolled so it flies off with
-- the hit's knockback, then it's cleaned up and a fresh one respawns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Targets = require(Shared.Config.Targets)
local Format = require(Shared.Util.Format)

local RigBuilder = require(script.Parent.Parent.Util.RigBuilder)
local RagdollService = require(script.Parent.RagdollService)

local H = GameConfig.World.Height

local TargetService = {}

type Record = {
	def: any,
	hp: number,
	maxHp: number,
	ground: CFrame,
	model: Model,
	body: BasePart, -- the part the HP bar sits on / position reference
	bar: Frame,
	hpText: TextLabel,
}

local alive: { [Model]: Record } = {}
local folder = Instance.new("Folder")
folder.Name = "PK_Targets"
TargetService.folder = folder

local nextId = 0

local function makeHealthBar(adornee: BasePart, def, height: number): (Frame, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(160, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = def.name
	name.Parent = gui

	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(10, 22)
	back.Size = UDim2.new(1, -20, 0, 16)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 230, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local corner2 = corner:Clone()
	corner2.Parent = fill

	local hpText = Instance.new("TextLabel")
	hpText.BackgroundTransparency = 1
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 12
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.TextStrokeTransparency = 0.3
	hpText.ZIndex = 2
	hpText.Text = Format.short(def.hp)
	hpText.Parent = back

	gui.Parent = adornee
	return fill, hpText
end

local function spawnTarget(def, ground: CFrame)
	nextId += 1
	local model, body, barHeight
	if def.model == "bag" then
		model, body = RigBuilder.bag(def.color, def.accent, ground, def.scale)
		barHeight = 4
	else
		model = RigBuilder.dummy(def.scale, def.color, def.accent, ground)
		body = model:FindFirstChild("Head") :: BasePart
		barHeight = 1.5 * def.scale + 0.8
	end
	model.Name = def.name
	model:SetAttribute("TargetId", nextId)
	model:SetAttribute("TargetType", def.id)
	model:SetAttribute("Standing", true)

	local fill, hpText = makeHealthBar(body, def, barHeight)
	model.Parent = folder

	alive[model] = {
		def = def,
		hp = def.hp,
		maxHp = def.hp,
		ground = ground,
		model = model,
		body = body,
		bar = fill,
		hpText = hpText,
	}
end

local function knockOut(record: Record, knockback: Vector3)
	local model = record.model
	model:SetAttribute("Standing", false)
	local bar = record.body:FindFirstChild("HealthBar")
	if bar then
		bar:Destroy()
	end

	if record.def.model == "dummy" then
		RagdollService.set(model, true, true)
	end
	local fling = knockback * 1.4 + Vector3.new(0, 25, 0)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanQuery = false -- no longer hittable
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			-- Server simulates the flying body so no client can tamper with it.
			pcall(p.SetNetworkOwner, p, nil)
			p.AssemblyLinearVelocity = fling
			p.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		end
	end

	task.delay(GameConfig.Targets.KoDebrisSeconds, function()
		model:Destroy()
	end)
	task.delay(record.def.respawn, spawnTarget, record.def, record.ground)
end

-- ===== Public API =====

-- Given any part that was hit, return the live target model it belongs to.
function TargetService.modelFromPart(part: BasePart): Model?
	local node: Instance? = part
	while node and node.Parent ~= folder do
		node = node.Parent
	end
	if node and node:IsA("Model") and alive[node] then
		return node
	end
	return nil
end

-- Applies damage. Returns nil if the target isn't alive, otherwise a result:
--   { ko, xp, coins, position, damage }
function TargetService.damage(model: Model, amount: number, knockback: Vector3)
	local record = alive[model]
	if not record then
		return nil
	end
	local dealt = math.min(amount, record.hp)
	record.hp -= amount
	local result = {
		ko = false,
		xp = record.def.xpPerHit,
		coins = 0,
		position = record.body.Position,
		damage = dealt,
	}

	if record.hp <= 0 then
		alive[model] = nil
		result.ko = true
		result.xp += record.def.koXp
		result.coins = record.def.koCoins
		knockOut(record, knockback)
	else
		local frac = record.hp / record.maxHp
		record.bar.Size = UDim2.fromScale(frac, 1)
		record.bar.BackgroundColor3 = Color3.fromRGB(230, 70, 60):Lerp(Color3.fromRGB(90, 230, 90), frac)
		record.hpText.Text = `{Format.short(math.ceil(record.hp))} / {Format.short(record.maxHp)}`
	end
	return result
end

-- Lays out every zone's targets in rings around the platform centre.
function TargetService.start(zones)
	for _, zone in zones do
		local center = Vector3.new(zone.center.X, H, zone.center.Z)
		local width = math.min(zone.size.X, zone.size.Z)
		for groupIndex, group in zone.targets do
			local def = Targets[group.type]
			assert(def, `Zone {zone.id} references unknown target type {group.type}`)
			for i = 1, group.count do
				local angle = (i / group.count) * math.pi * 2 + groupIndex * 0.35
				local radius = group.ring * width
				local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local ground = if radius < 1
					then CFrame.new(center) * CFrame.Angles(0, math.rad(-90), 0)
					else CFrame.lookAt(pos, center)
				if def.model == "bag" then
					RigBuilder.bagStand(ground, Color3.fromRGB(70, 70, 75), folder)
				end
				spawnTarget(def, ground)
			end
		end
	end
	folder.Parent = workspace
end

return TargetService
