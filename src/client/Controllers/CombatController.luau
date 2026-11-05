-- Turns input into attack requests.
--
--   PC          hold Left Click = punch · 1-4 or Q/E/R/F = move slots · M = menu · 5-8 = emotes
--   Controller  hold R2 = punch · X / Y / B / R1 = move slots · Select or DPad Up = menu
--               DPad Down = emote panel
--   Mobile      hold the PUNCH button · tap a move slot · MENU / EMOTE buttons
--
-- Client-side we check the cooldown too, but only to avoid sending requests
-- that would be rejected and to drive the HUD overlay. The server keeps its
-- own clock and is the real authority.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Moves = require(Shared.Config.Moves)
local Animations = require(Shared.Config.Animations)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local ProfileState = require(script.Parent.ProfileState)
local EffectsController = require(script.Parent.EffectsController)
local PoseAnimator = require(script.Parent.PoseAnimator)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CombatController = {}

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Q] = 1,
	[Enum.KeyCode.E] = 2,
	[Enum.KeyCode.R] = 3,
	[Enum.KeyCode.F] = 4,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
	[Enum.KeyCode.ButtonR1] = 4,
}
local MENU_KEYS = {
	[Enum.KeyCode.M] = true,
	[Enum.KeyCode.ButtonSelect] = true,
	[Enum.KeyCode.DPadUp] = true,
}

local hud
local menu
local lastUse: { [string]: number } = {}
local holding = { mouse = false, touch = false, pad = false }
local punchVariant = 1
local busyUntil = 0 -- small global lock so a big move's animation isn't cut by spam
local lastEmote = 0
local EMOTE_COOLDOWN = 1.5 -- matches the server's rate limit closely enough

local EMOTE_KEYS: { [Enum.KeyCode]: string } = {}
for _, emote in Animations.Emotes do
	if emote.key then
		EMOTE_KEYS[emote.key] = emote.id
	end
end

local function getCharacter(): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, root, humanoid
end

local function facingDirection(root: BasePart): Vector3
	-- Attack where the camera looks (flattened), so mouse/thumbstick aim works.
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	return flat.Unit
end

local function dash(root: BasePart, direction: Vector3, speed: number, duration: number)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(1e6, 0, 1e6) -- horizontal only; gravity still works
	velocity.VectorVelocity = direction * speed
	velocity.Parent = root
	task.delay(duration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

local function tryMove(moveId: string?, slotIndex: number): boolean
	local data = ProfileState.data
	local move = moveId and Moves.byId[moveId]
	if not data or not move then
		return false
	end
	if not move.basic and not data.unlockedMoves[move.id] then
		return false
	end
	local character, root = getCharacter()
	if not character or not root or character:GetAttribute("Ragdolled") then
		return false
	end

	local now = os.clock()
	if now < busyUntil then
		return false
	end
	local cooldown = move.cooldown * Progression.cooldownMultiplier(data)
	if now - (lastUse[move.id] or -math.huge) < cooldown then
		return false
	end
	lastUse[move.id] = now
	busyUntil = now + (if move.basic then 0 else math.min(move.pose.duration * 0.6, 0.4))

	-- Turn to face the attack direction (our own character: replicates).
	local dir = facingDirection(root)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)

	Remotes.get("Attack"):FireServer(move.id, dir)

	local variant = 1
	if move.basic then
		punchVariant = if punchVariant == 1 then 2 else 1
		variant = punchVariant
	end
	EffectsController.onLocalAttack(character, move, variant)
	if move.dash then
		dash(root, dir, move.dash.speed, move.dash.duration)
	end

	hud:startCooldown(slotIndex, cooldown)
	hud:flashSlot(slotIndex)
	return true
end

local function emote(emoteId: string)
	local character = getCharacter()
	local now = os.clock()
	if not character or character:GetAttribute("Ragdolled") or now - lastEmote < EMOTE_COOLDOWN then
		return
	end
	lastEmote = now
	-- Play it ourselves right away, then let the server show everyone else.
	if PoseAnimator.playEmote(character, emoteId) then
		Remotes.get("Emote"):FireServer(emoteId)
	end
end

local function useSlot(slotIndex: number)
	local data = ProfileState.data
	if not data then
		return
	end
	local moveId = data.loadout[slotIndex]
	if moveId == nil or moveId == "" then
		hud:toast("Empty slot: unlock moves in the menu", "error")
		return
	end
	tryMove(moveId, slotIndex)
end

function CombatController.start(hudInstance, menuInstance)
	hud = hudInstance
	menu = menuInstance

	hud.MoveSlotPressed:Connect(useSlot)
	hud.PunchHold:Connect(function(isHolding)
		holding.touch = isHolding
	end)
	hud.MenuPressed:Connect(function()
		menu:toggle()
	end)
	hud.EmotePressed:Connect(emote)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not gameProcessed and not menu.open then
				holding.mouse = true
			end
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding.pad = not menu.open
			return
		end
		if MENU_KEYS[input.KeyCode] then
			local isGamepad = string.sub(input.UserInputType.Name, 1, 7) == "Gamepad"
			if not gameProcessed or isGamepad then
				menu:toggle()
			end
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadDown then
			hud:toggleEmotes()
			return
		end
		if gameProcessed or menu.open then
			return -- typing in chat, or navigating the menu
		end
		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			useSlot(slot)
			return
		end
		local emoteId = EMOTE_KEYS[input.KeyCode]
		if emoteId then
			emote(emoteId)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding.mouse = false
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			holding.pad = false
		end
	end)

	-- Hold-to-punch: one cheap check per frame; the cooldown gate does the pacing.
	RunService.Heartbeat:Connect(function()
		if (holding.mouse or holding.touch or holding.pad) and not menu.open then
			tryMove(Moves.BASIC_ID, 0)
		end
	end)

	-- Release holds if the window loses focus (otherwise you'd punch forever).
	UserInputService.WindowFocusReleased:Connect(function()
		holding.mouse, holding.touch, holding.pad = false, false, false
	end)
end

return CombatController
