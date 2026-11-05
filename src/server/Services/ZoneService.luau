-- Builds the world from Config/Zones (floating platforms, bridges, level
-- gates, decor) and tracks which zone every player is in.
--
-- Level gates are enforced by the SERVER: twice a second it checks each
-- player's position, and anyone inside a zone they're too low-level for is
-- sent back. (The client also makes the gate solid locally for a nicer feel,
-- but that's cosmetic; exploiters can remove client-side walls.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local H = GameConfig.World.Height

local ZoneService = {}
ZoneService.zones = Zones.list
ZoneService.world = nil :: Folder?

local playerZone: { [Player]: string } = {}
local lastWarn: { [Player]: number } = {}

-- ===== Geometry helpers =====

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, lines: { { text: string, color: Color3, size: number } }, maxDistance: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(400, #lines * 40)
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	for i, line in lines do
		local l = Instance.new("TextLabel")
		l.LayoutOrder = i
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, line.size + 10)
		l.Font = Enum.Font.GothamBlack
		l.Text = line.text
		l.TextColor3 = line.color
		l.TextSize = line.size
		l.TextStrokeTransparency = 0.3
		l.Parent = gui
	end
	gui.Parent = adornee
	return gui
end

-- Half the platform's extent along an axis-aligned direction.
local function halfExtent(zone, dir: Vector3): number
	return math.abs(dir.X) * zone.size.X / 2 + math.abs(dir.Z) * zone.size.Z / 2
end

local function zonePos(zone, y: number?): Vector3
	return Vector3.new(zone.center.X, y or H, zone.center.Z)
end

-- ===== Decor per zone =====

local function decorate(zone, folder: Folder)
	local trim = zone.theme.trim
	local hx, hz = zone.size.X / 2, zone.size.Z / 2
	local c = zonePos(zone)

	-- Neon edge strips
	for _, edge in {
		{ Vector3.new(0, 0.3, hz - 0.5), Vector3.new(zone.size.X, 0.6, 1) },
		{ Vector3.new(0, 0.3, -hz + 0.5), Vector3.new(zone.size.X, 0.6, 1) },
		{ Vector3.new(hx - 0.5, 0.3, 0), Vector3.new(1, 0.6, zone.size.Z) },
		{ Vector3.new(-hx + 0.5, 0.3, 0), Vector3.new(1, 0.6, zone.size.Z) },
	} do
		part({ Name = "Trim", Size = edge[2], Position = c + edge[1], Color = trim, Material = Enum.Material.Neon, CanCollide = false }, folder)
	end

	-- Corner pillars with glowing caps
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local base = c + Vector3.new(sx * (hx - 4), 0, sz * (hz - 4))
			part({ Name = "Pillar", Size = Vector3.new(4, 16, 4), Position = base + Vector3.new(0, 8, 0), Color = zone.theme.floor:Lerp(Color3.new(1, 1, 1), 0.25) }, folder)
			part({ Name = "PillarCap", Size = Vector3.new(4.6, 1.2, 4.6), Position = base + Vector3.new(0, 16.6, 0), Color = trim, Material = Enum.Material.Neon }, folder)
		end
	end

	if zone.id == "gym" then
		-- Weight benches + dumbbell racks around the centre.
		for i = 0, 3 do
			local angle = i * math.pi / 2 + math.pi / 4
			local pos = c + Vector3.new(math.cos(angle) * 22, 0, math.sin(angle) * 22)
			local cf = CFrame.lookAt(pos, c)
			part({ Name = "Bench", Size = Vector3.new(2, 1.5, 6), CFrame = cf * CFrame.new(0, 0.75, 0), Color = Color3.fromRGB(30, 30, 30) }, folder)
			part({ Name = "BarbellBar", Size = Vector3.new(8, 0.3, 0.3), CFrame = cf * CFrame.new(0, 3, -2), Color = Color3.fromRGB(180, 180, 190), Material = Enum.Material.Metal }, folder)
			for _, side in { -3.6, 3.6 } do
				part({ Name = "Plate", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2.4, 2.4), CFrame = cf * CFrame.new(side, 3, -2), Color = Color3.fromRGB(40, 40, 40) }, folder)
			end
		end
	elseif zone.id == "arena" then
		-- A raised boxing ring with corner posts and neon ropes.
		local ring = 60
		part({ Name = "Ring", Size = Vector3.new(ring, 1.5, ring), Position = c + Vector3.new(0, 0.75, 0), Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.Fabric }, folder)
		local top = 1.5
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				part({ Name = "RingPost", Size = Vector3.new(1.5, 7, 1.5), Position = c + Vector3.new(sx * ring / 2, top + 3.5, sz * ring / 2), Color = trim, Material = Enum.Material.Neon }, folder)
			end
		end
		for _, height in { 2.5, 4.5, 6.5 } do
			for _, edge in {
				{ Vector3.new(0, 0, ring / 2), Vector3.new(ring, 0.25, 0.25) },
				{ Vector3.new(0, 0, -ring / 2), Vector3.new(ring, 0.25, 0.25) },
				{ Vector3.new(ring / 2, 0, 0), Vector3.new(0.25, 0.25, ring) },
				{ Vector3.new(-ring / 2, 0, 0), Vector3.new(0.25, 0.25, ring) },
			} do
				part({ Name = "Rope", Size = edge[2], Position = c + edge[1] + Vector3.new(0, top + height - 1.5, 0), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, CanCollide = false }, folder)
			end
		end
	elseif zone.id == "dojo" then
		-- Paper lanterns and a big gate arch at the back.
		for i = 0, 7 do
			local angle = i * math.pi / 4
			local pos = c + Vector3.new(math.cos(angle) * 30, 0, math.sin(angle) * 30)
			part({ Name = "LanternPost", Size = Vector3.new(0.6, 6, 0.6), Position = pos + Vector3.new(0, 3, 0), Color = Color3.fromRGB(60, 40, 30) }, folder)
			local lantern = part({ Name = "Lantern", Size = Vector3.new(1.8, 2.2, 1.8), Position = pos + Vector3.new(0, 7, 0), Color = Color3.fromRGB(255, 120, 80), Material = Enum.Material.Neon }, folder)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 150, 90)
			light.Range = 14
			light.Parent = lantern
		end
		local back = c + Vector3.new(hx - 12, 0, 0)
		for _, sz in { -10, 10 } do
			part({ Name = "ArchPost", Size = Vector3.new(2, 18, 2), Position = back + Vector3.new(0, 9, sz), Color = trim }, folder)
		end
		part({ Name = "ArchTop", Size = Vector3.new(3, 2, 28), Position = back + Vector3.new(0, 18, 0), Color = trim }, folder)
		part({ Name = "ArchTop2", Size = Vector3.new(2, 1.5, 24), Position = back + Vector3.new(0, 15, 0), Color = Color3.fromRGB(40, 25, 20) }, folder)
	elseif zone.id == "rooftop" then
		-- AC units and glowing signs.
		for i = 0, 5 do
			local angle = i * math.pi / 3 + 0.4
			local pos = c + Vector3.new(math.cos(angle) * 20, 0, math.sin(angle) * 20)
			part({ Name = "ACUnit", Size = Vector3.new(5, 4, 5), Position = pos + Vector3.new(0, 2, 0), Color = Color3.fromRGB(120, 125, 135), Material = Enum.Material.DiamondPlate }, folder)
		end
		for _, sz in { -1, 1 } do
			part({ Name = "NeonSign", Size = Vector3.new(30, 8, 0.6), Position = c + Vector3.new(0, 14, sz * (hz - 2)), Color = if sz > 0 then Color3.fromRGB(255, 60, 200) else trim, Material = Enum.Material.Neon, CanCollide = false }, folder)
		end
	elseif zone.id == "volcano" then
		-- Lava pools (decor only) and jagged rocks.
		local rng = Random.new(7)
		for _ = 1, 10 do
			local pos = c + Vector3.new(rng:NextNumber(-hx + 10, hx - 10), 0, rng:NextNumber(-hz + 10, hz - 10))
			if (pos - c).Magnitude > 25 then
				part({ Name = "Lava", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, rng:NextNumber(8, 16), rng:NextNumber(8, 16)), CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 90, 10), Material = Enum.Material.Neon, CanCollide = false }, folder)
			end
		end
		for _ = 1, 14 do
			local pos = c + Vector3.new(rng:NextNumber(-hx + 6, hx - 6), 0, rng:NextNumber(-hz + 6, hz - 6))
			if (pos - c).Magnitude > 30 then
				local h = rng:NextNumber(4, 12)
				part({ Name = "Rock", Size = Vector3.new(rng:NextNumber(3, 7), h, rng:NextNumber(3, 7)), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(35, 25, 25), Material = Enum.Material.Basalt }, folder)
			end
		end
	end
end

-- ===== World build =====

local function buildZone(zone, parent: Folder)
	local folder = Instance.new("Folder")
	folder.Name = zone.id
	folder.Parent = parent

	part({
		Name = "Floor",
		Size = Vector3.new(zone.size.X, 4, zone.size.Z),
		Position = zonePos(zone, H - 2),
		Color = zone.theme.floor,
		Material = zone.theme.material,
	}, folder)
	-- Underside "island" rock so platforms look grounded in the sky.
	part({
		Name = "Underside",
		Size = Vector3.new(zone.size.X * 0.8, 18, zone.size.Z * 0.8),
		Position = zonePos(zone, H - 13),
		Color = Color3.fromRGB(80, 70, 65),
		Material = Enum.Material.Slate,
	}, folder)

	-- Floating title sign above the platform.
	local signAnchor = part({ Name = "Sign", Size = Vector3.new(1, 1, 1), Position = zonePos(zone, H + 30), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	local lines = {
		{ text = string.upper(zone.name), color = zone.theme.trim, size = 34 },
		{ text = if zone.minLevel > 1 then `Level {zone.minLevel}+` else "All levels", color = Color3.new(1, 1, 1), size = 20 },
	}
	if zone.pvp then
		table.insert(lines, { text = "⚔ PVP ZONE ⚔", color = Color3.fromRGB(255, 70, 70), size = 22 })
	end
	billboard(signAnchor, lines, 350)

	decorate(zone, folder)
end

local function buildBridge(a, b, bridges: Folder, gates: Folder)
	local delta = Vector3.new(b.center.X - a.center.X, 0, b.center.Z - a.center.Z)
	local dir = delta.Unit
	local startPoint = zonePos(a) + dir * halfExtent(a, dir)
	local endPoint = zonePos(b) - dir * halfExtent(b, dir)
	local length = (endPoint - startPoint).Magnitude
	if length <= 0.5 then
		return
	end
	local mid = (startPoint + endPoint) / 2
	local cf = CFrame.lookAt(mid, mid + dir)
	local width = 18

	part({ Name = "Bridge", Size = Vector3.new(width, 2, length + 2), CFrame = cf * CFrame.new(0, -1, 0), Color = Color3.fromRGB(110, 100, 95), Material = Enum.Material.Cobblestone }, bridges)
	for _, side in { -1, 1 } do
		part({ Name = "Rail", Size = Vector3.new(1, 3, length + 2), CFrame = cf * CFrame.new(side * (width / 2 - 0.5), 1.5, 0), Color = Color3.fromRGB(70, 60, 55) }, bridges)
	end

	-- Gate where the bridge meets the higher-level zone.
	local locked, edge, facing = b, endPoint, dir
	if a.minLevel > b.minLevel then
		locked, edge, facing = a, startPoint, -dir
	end
	if locked.minLevel <= 1 then
		return
	end
	local gateCf = CFrame.lookAt(edge - facing * 2, edge + facing)
	local trim = locked.theme.trim
	for _, side in { -1, 1 } do
		part({ Name = "GatePost", Size = Vector3.new(2, 14, 2), CFrame = gateCf * CFrame.new(side * (width / 2 + 1), 7, 0), Color = trim, Material = Enum.Material.Neon }, gates)
	end
	part({ Name = "GateTop", Size = Vector3.new(width + 4, 2, 2), CFrame = gateCf * CFrame.new(0, 14, 0), Color = trim, Material = Enum.Material.Neon }, gates)
	local barrier = part({
		Name = "GateBarrier",
		Size = Vector3.new(width, 13, 0.5),
		CFrame = gateCf * CFrame.new(0, 6.5, 0),
		Color = trim,
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
		CanCollide = false, -- the client makes it solid locally for locked players
	}, gates)
	barrier:SetAttribute("MinLevel", locked.minLevel)
	barrier:SetAttribute("ZoneId", locked.id)
	billboard(barrier, {
		{ text = `🔒 {locked.name}`, color = trim, size = 22 },
		{ text = `Requires level {locked.minLevel}`, color = Color3.new(1, 1, 1), size = 18 },
	}, 120)
end

-- Where you appear in a zone: just inside the edge you arrive from.
local function computeSpawns()
	for _, zone in Zones.list do
		zone.spawnCFrame = CFrame.new(zonePos(zone, H + 3))
	end
	for _, pair in Zones.connections do
		local a, b = Zones.byId[pair[1]], Zones.byId[pair[2]]
		local dir = Vector3.new(a.center.X - b.center.X, 0, a.center.Z - b.center.Z).Unit -- from b toward a
		local pos = zonePos(b, H + 3) + dir * (halfExtent(b, dir) - 14)
		b.spawnCFrame = CFrame.lookAt(pos, zonePos(b, H + 3))
	end
end

function ZoneService.build()
	local world = Instance.new("Folder")
	world.Name = "PK_World"
	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = world
	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = world
	local gates = Instance.new("Folder")
	gates.Name = "Gates"
	gates.Parent = world

	for _, zone in Zones.list do
		buildZone(zone, zonesFolder)
	end
	for _, pair in Zones.connections do
		buildBridge(Zones.byId[pair[1]], Zones.byId[pair[2]], bridges, gates)
	end
	computeSpawns()

	local gym = Zones.list[1]
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PK_Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(zonePos(gym, H + 0.5))
	spawn.Material = Enum.Material.Neon
	spawn.Color = gym.theme.trim
	spawn.Duration = 0 -- we handle spawn protection ourselves
	spawn.Neutral = true
	spawn.Parent = world

	world.Parent = workspace
	ZoneService.world = world
end

-- ===== Queries =====

function ZoneService.zoneAt(position: Vector3)
	for _, zone in Zones.list do
		local dx = math.abs(position.X - zone.center.X)
		local dz = math.abs(position.Z - zone.center.Z)
		if dx <= zone.size.X / 2 + 1 and dz <= zone.size.Z / 2 + 1 and position.Y > H - 15 and position.Y < H + 80 then
			return zone
		end
	end
	return nil
end

function ZoneService.zoneIdOf(player: Player): string
	return playerZone[player] or ""
end

function ZoneService.isPvP(player: Player): boolean
	local zone = Zones.byId[playerZone[player] or ""]
	return zone ~= nil and zone.pvp == true
end

-- Highest non-PvP zone the player has unlocked.
function ZoneService.bestSpawnFor(player: Player): CFrame
	local data = DataService.get(player)
	local level = if data then data.level else 1
	local best = Zones.list[1]
	for _, zone in Zones.list do
		if not zone.pvp and zone.minLevel <= level and zone.minLevel >= best.minLevel then
			best = zone
		end
	end
	local jitter = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	return best.spawnCFrame + jitter
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character then
		character:PivotTo(cf)
	end
end

local function warnPlayer(player: Player, text: string)
	local now = os.clock()
	if now - (lastWarn[player] or 0) > 2 then
		lastWarn[player] = now
		Remotes.get("Notify"):FireClient(player, text, "error")
	end
end

local function check(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position

	if position.Y < H - GameConfig.World.FallLimit then
		teleport(player, ZoneService.bestSpawnFor(player))
		return
	end

	local zone = ZoneService.zoneAt(position)
	local data = DataService.get(player)
	local level = if data then data.level else 1
	if zone and zone.minLevel > level then
		teleport(player, ZoneService.bestSpawnFor(player))
		warnPlayer(player, `Reach level {zone.minLevel} to enter {zone.name}`)
		return
	end

	local id = if zone then zone.id else ""
	if playerZone[player] ~= id then
		playerZone[player] = id
		player:SetAttribute("Zone", id)
	end
end

function ZoneService.start()
	ZoneService.build()

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait() -- let the default spawn finish first
			teleport(player, ZoneService.bestSpawnFor(player))
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		playerZone[player] = nil
		lastWarn[player] = nil
	end)

	-- The first spawn can happen before the profile finishes loading (level
	-- unknown, so they land in the gym). Once it loads, move them up.
	DataService.ProfileLoaded:Connect(function(player)
		if player.Character then
			teleport(player, ZoneService.bestSpawnFor(player))
		end
	end)

	-- One cheap loop for all players instead of per-frame Touched spam.
	task.spawn(function()
		while true do
			task.wait(GameConfig.World.ZoneCheckSeconds)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return ZoneService
