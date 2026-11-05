-- All client-side juice: other players' attack animations, damage numbers,
-- hit sparks, shockwave rings, sounds, camera shake, target wobble, and the
-- local collision on level gates.
--
-- Performance: every effect object is POOLED (created once, reused), so a
-- busy fight doesn't create and destroy hundreds of Instances per second.
-- Effects far from the camera are skipped entirely.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Moves = require(Shared.Config.Moves)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local PoseAnimator = require(script.Parent.PoseAnimator)
local ProfileState = require(script.Parent.ProfileState)
local RagdollClient = require(script.Parent.RagdollClient)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local EffectsController = {}

local MAX_FX_DISTANCE = 160

local function nearCamera(position: Vector3): boolean
	return (camera.CFrame.Position - position).Magnitude <= MAX_FX_DISTANCE
end

-- ===== Pools =====

local function newAttachment(): Attachment
	local a = Instance.new("Attachment")
	a.Parent = workspace.Terrain -- attachments on Terrain = free-floating world points
	return a
end

-- Damage numbers
local NUMBER_POOL = 40
local numbers = {}
local numberIndex = 0

-- Sparks
local SPARK_POOL = 6
local sparks = {}
local sparkIndex = 0

-- Sounds
local SOUND_POOL = 12
local sounds = {}
local soundIndex = 0

-- Shockwave rings
local RING_POOL = 6
local rings = {}
local ringIndex = 0

local function buildPools(playerGui: PlayerGui)
	for i = 1, NUMBER_POOL do
		local att = newAttachment()
		local gui = Instance.new("BillboardGui")
		gui.Name = "PK_DamageNumber"
		gui.ResetOnSpawn = false -- survive respawns (lives directly in PlayerGui)
		gui.Adornee = att
		gui.Size = UDim2.fromOffset(120, 40)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Enabled = false
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = playerGui
		numbers[i] = { att = att, gui = gui, label = label, tween = nil :: Tween? }
	end

	for i = 1, SPARK_POOL do
		local att = newAttachment()
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.LightEmission = 1
		emitter.Lifetime = NumberRange.new(0.2, 0.45)
		emitter.Speed = NumberRange.new(18, 34)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 6
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Parent = att
		sparks[i] = { att = att, emitter = emitter }
	end

	for i = 1, SOUND_POOL do
		local att = newAttachment()
		local sound = Instance.new("Sound")
		sound.RollOffMaxDistance = 120
		sound.Parent = att
		sounds[i] = { att = att, sound = sound }
	end

	for i = 1, RING_POOL do
		local ring = Instance.new("Part")
		ring.Name = "PK_Shockwave"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Transparency = 1
		ring.Size = Vector3.new(0.3, 1, 1)
		ring.Parent = workspace
		rings[i] = ring
	end
end

-- ===== Primitive effects =====

function EffectsController.playSound(soundId: string, position: Vector3, volume: number?, pitch: number?)
	if not nearCamera(position) then
		return
	end
	soundIndex = soundIndex % SOUND_POOL + 1
	local entry = sounds[soundIndex]
	entry.att.WorldPosition = position
	entry.sound.SoundId = soundId
	entry.sound.Volume = volume or 0.6
	entry.sound.PlaybackSpeed = (pitch or 1) * (0.92 + math.random() * 0.16)
	entry.sound:Play()
end

function EffectsController.spark(position: Vector3, color: Color3, amount: number)
	if not nearCamera(position) then
		return
	end
	sparkIndex = sparkIndex % SPARK_POOL + 1
	local entry = sparks[sparkIndex]
	entry.att.WorldPosition = position
	entry.emitter.Color = ColorSequence.new(color)
	entry.emitter:Emit(amount)
end

function EffectsController.damageNumber(position: Vector3, amount: number, isKo: boolean, color: Color3)
	if not nearCamera(position) then
		return
	end
	numberIndex = numberIndex % NUMBER_POOL + 1
	local entry = numbers[numberIndex]
	if entry.tween then
		entry.tween:Cancel()
	end
	local jitter = Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
	entry.att.WorldPosition = position + jitter
	entry.gui.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	entry.gui.Size = if isKo then UDim2.fromOffset(200, 60) else UDim2.fromOffset(110, 36)
	entry.label.Text = if isKo then `KO! {Format.short(amount)}` else Format.short(math.max(1, math.floor(amount + 0.5)))
	entry.label.TextColor3 = if isKo then Color3.fromRGB(255, 80, 80) else color
	entry.label.TextTransparency = 0
	entry.label.TextStrokeTransparency = 0.2
	entry.gui.Enabled = true

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }):Play()
	local fade = TweenService:Create(entry.label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	entry.tween = fade
	fade.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			entry.gui.Enabled = false
		end
	end)
	fade:Play()
end

function EffectsController.shockwave(position: Vector3, radius: number, color: Color3)
	if not nearCamera(position) then
		return
	end
	ringIndex = ringIndex % RING_POOL + 1
	local ring = rings[ringIndex]
	ring.Color = color
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
end

-- ===== Camera shake =====

local shakeStrength = 0
function EffectsController.shake(strength: number)
	shakeStrength = math.max(shakeStrength, strength)
end

local function bindShake()
	RunService:BindToRenderStep("PK_CameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shakeStrength <= 0.001 then
			return
		end
		local s = shakeStrength
		camera.CFrame *= CFrame.Angles(
			math.rad((math.random() - 0.5) * 3 * s),
			math.rad((math.random() - 0.5) * 3 * s),
			math.rad((math.random() - 0.5) * 2 * s)
		)
		shakeStrength = math.max(0, shakeStrength - dt * 3)
	end)
end

-- ===== Target wobble (purely local; the server never moves a standing target) =====

local wobbling: { [Model]: any } = {}

local function wobble(model: Model, strength: number)
	if not model:GetAttribute("Standing") then
		return
	end
	local token = {}
	local base = if wobbling[model] then wobbling[model].base else model:GetPivot()
	wobbling[model] = { token = token, base = base }
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local entry = wobbling[model]
		if not entry or entry.token ~= token or not model.Parent then
			conn:Disconnect()
			return
		end
		if not model:GetAttribute("Standing") then
			-- Knocked out mid-wobble: the server now owns its motion; let go.
			wobbling[model] = nil
			conn:Disconnect()
			return
		end
		local t = os.clock() - start
		if t > 0.45 then
			model:PivotTo(base)
			wobbling[model] = nil
			conn:Disconnect()
			return
		end
		local angle = math.sin(t * 28) * math.exp(-t * 7) * strength
		model:PivotTo(base * CFrame.Angles(math.rad(angle), 0, math.rad(angle * 0.4)))
	end)
end

-- ===== Gates: solid locally for players below the required level =====

local function updateGate(barrier: Instance)
	if not barrier:IsA("BasePart") then
		return
	end
	local minLevel = barrier:GetAttribute("MinLevel")
	local data = ProfileState.data
	if type(minLevel) ~= "number" or not data then
		return
	end
	local locked = data.level < minLevel
	barrier.CanCollide = locked
	barrier.Transparency = if locked then 0.3 else 0.85
end

local function hookGates()
	local world = workspace:WaitForChild("PK_World", 30)
	local gates = world and world:WaitForChild("Gates", 30)
	if not gates then
		return
	end
	gates.ChildAdded:Connect(updateGate) -- StreamingEnabled: parts arrive as you approach
	for _, child in gates:GetChildren() do
		updateGate(child)
	end
	ProfileState.Changed:Connect(function(data, previous)
		if previous and previous.level == data.level then
			return
		end
		for _, child in gates:GetChildren() do
			updateGate(child)
		end
	end)
end

-- ===== Level up burst =====

local function levelUpBurst()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	EffectsController.spark(root.Position, Color3.fromRGB(255, 220, 80), 60)
	EffectsController.shockwave(root.Position, 14, Color3.fromRGB(255, 220, 80))
	EffectsController.playSound(GameConfig.Sounds.LevelUp, root.Position, 0.8, 1.2)
end

-- ===== Public: called by CombatController for the local player's own moves =====

function EffectsController.onLocalAttack(character: Model, move, variant: number)
	PoseAnimator.playMove(character, move, variant)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		EffectsController.playSound(GameConfig.Sounds.Swing, root.Position, 0.35, 1.1)
		if move.shockwave and move.hitbox.kind == "radius" then
			task.delay(move.hitDelay, function()
				EffectsController.shockwave(root.Position, move.hitbox.radius, move.color)
			end)
		end
	end
	if move.shake > 0 then
		task.delay(move.hitDelay, EffectsController.shake, move.shake * 0.6)
	end
end

function EffectsController.start()
	buildPools(player:WaitForChild("PlayerGui") :: PlayerGui)
	bindShake()
	task.spawn(hookGates)

	-- Other players' attacks: animate them and play their swing.
	Remotes.get("AttackFx").OnClientEvent:Connect(function(character, moveId, variant)
		if typeof(character) ~= "Instance" or not character:IsA("Model") or character == player.Character then
			return
		end
		local move = Moves.byId[moveId]
		local root = character:FindFirstChild("HumanoidRootPart")
		if not move or not root or not root:IsA("BasePart") or not nearCamera(root.Position) then
			return
		end
		PoseAnimator.playMove(character, move, variant)
		EffectsController.playSound(GameConfig.Sounds.Swing, root.Position, 0.3, 1.1)
		if move.shockwave and move.hitbox.kind == "radius" then
			task.delay(move.hitDelay, function()
				EffectsController.shockwave(root.Position, move.hitbox.radius, move.color)
			end)
		end
	end)

	Remotes.get("HitFx").OnClientEvent:Connect(function(position, damage, isKo, moveId, target)
		if typeof(position) ~= "Vector3" or type(damage) ~= "number" then
			return
		end
		local move = Moves.byId[moveId]
		local color = if move then move.color else Color3.new(1, 1, 1)
		EffectsController.damageNumber(position, damage, isKo == true, color)
		EffectsController.spark(position, color, if isKo then 40 else 14)
		EffectsController.playSound(GameConfig.Sounds.Hit, position, if isKo then 0.9 else 0.5, if isKo then 0.8 else 1.15)
		if typeof(target) == "Instance" and target:IsA("Model") and target:GetAttribute("TargetId") and not isKo then
			wobble(target, math.clamp(4 + damage / 12, 4, 14))
		end
	end)

	Remotes.get("LevelUp").OnClientEvent:Connect(levelUpBurst)

	RagdollClient.KnockedBack:Connect(function(strength)
		EffectsController.shake(strength)
	end)
end

return EffectsController
