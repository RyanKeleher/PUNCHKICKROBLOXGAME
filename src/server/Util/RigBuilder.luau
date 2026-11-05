-- Builds training-target models out of plain parts (no imported assets).
--
-- Dummies are R6-style rigs: parts joined to a HumanoidRootPart with Motor6Ds.
-- Only the root is anchored, so the whole rig stands still; when it's knocked
-- out, RagdollService turns the Motor6Ds into ball sockets and we unanchor it.

local RigBuilder = {}

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = true
	p.Parent = parent
	return p
end

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = p0
	return m
end

-- Returns (model, root). `groundCFrame` = point on the floor where the feet go.
function RigBuilder.dummy(scale: number, color: Color3, accent: Color3, groundCFrame: CFrame): (Model, BasePart)
	local s = scale
	local model = Instance.new("Model")
	model.Name = "Dummy"

	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1) * s, color, model)
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true

	local torso = part("Torso", Vector3.new(2, 2, 1) * s, color, model)
	local head = part("Head", Vector3.new(2, 1, 1) * s, accent, model)
	local larm = part("Left Arm", Vector3.new(1, 2, 1) * s, color, model)
	local rarm = part("Right Arm", Vector3.new(1, 2, 1) * s, color, model)
	local lleg = part("Left Leg", Vector3.new(1, 2, 1) * s, accent, model)
	local rleg = part("Right Leg", Vector3.new(1, 2, 1) * s, accent, model)

	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	-- Belt for a bit of visual interest.
	local belt = part("Belt", Vector3.new(2.05, 0.3, 1.05) * s, accent, model)
	belt.CanCollide = false
	belt.Massless = true

	motor("RootJoint", root, torso, CFrame.new(), CFrame.new())
	motor("Neck", torso, head, CFrame.new(0, 1 * s, 0), CFrame.new(0, -0.5 * s, 0))
	motor("Left Shoulder", torso, larm, CFrame.new(-1 * s, 0.5 * s, 0), CFrame.new(0.5 * s, 0.5 * s, 0))
	motor("Right Shoulder", torso, rarm, CFrame.new(1 * s, 0.5 * s, 0), CFrame.new(-0.5 * s, 0.5 * s, 0))
	motor("Left Hip", torso, lleg, CFrame.new(-0.5 * s, -1 * s, 0), CFrame.new(0, 1 * s, 0))
	motor("Right Hip", torso, rleg, CFrame.new(0.5 * s, -1 * s, 0), CFrame.new(0, 1 * s, 0))
	motor("BeltWeld", torso, belt, CFrame.new(0, -0.8 * s, 0), CFrame.new())

	model.PrimaryPart = root
	-- Root centre sits 3 * scale above the floor (2 for legs + 1 for half the torso).
	model:PivotTo(groundCFrame * CFrame.new(0, 3 * s, 0))
	return model, root
end

-- A hanging punching bag. Returns (model, bagPart). The stand is built
-- separately (RigBuilder.bagStand) so it stays put when the bag is knocked off.
function RigBuilder.bag(color: Color3, accent: Color3, groundCFrame: CFrame, sizeScale: number): (Model, BasePart)
	local s = sizeScale
	local model = Instance.new("Model")
	model.Name = "Bag"

	local bag = part("BagBody", Vector3.new(4.5 * s, 2.4 * s, 2.4 * s), color, model)
	bag.Shape = Enum.PartType.Cylinder
	bag.Material = Enum.Material.Leather
	bag.Anchored = true
	-- Cylinders run along X; rotate so the bag hangs vertically.
	bag.CFrame = groundCFrame * CFrame.new(0, 4.2, 0) * CFrame.Angles(0, 0, math.rad(90))

	local cap = part("Cap", Vector3.new(0.4, 2.5 * s, 2.5 * s), accent, model)
	cap.Shape = Enum.PartType.Cylinder
	cap.Anchored = true
	cap.CanCollide = false
	cap.CFrame = bag.CFrame * CFrame.new(2.25 * s, 0, 0)

	model.PrimaryPart = bag
	return model, bag
end

function RigBuilder.bagStand(groundCFrame: CFrame, color: Color3, parent: Instance)
	local stand = Instance.new("Model")
	stand.Name = "BagStand"
	local function beam(size: Vector3, offset: CFrame)
		local p = part("Beam", size, color, stand)
		p.Anchored = true
		p.Material = Enum.Material.Metal
		p.CFrame = groundCFrame * offset
	end
	beam(Vector3.new(0.5, 9, 0.5), CFrame.new(-2.5, 4.5, 0))
	beam(Vector3.new(0.5, 9, 0.5), CFrame.new(2.5, 4.5, 0))
	beam(Vector3.new(5.5, 0.5, 0.5), CFrame.new(0, 9, 0))
	beam(Vector3.new(0.15, 2.4, 0.15), CFrame.new(0, 7.7, 0)) -- chain
	beam(Vector3.new(6, 0.3, 2.5), CFrame.new(0, 0.15, 0)) -- base plate
	stand.Parent = parent
	return stand
end

return RigBuilder
