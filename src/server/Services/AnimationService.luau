-- Server side of character animation:
--   * Emote requests: validated (known id, alive, not ragdolled, rate limited)
--     and relayed to nearby players, who play the animation locally.
--   * Automatic celebrations: other services call AnimationService.celebrate
--     (level up -> flex, PvP KO -> victory) so everyone nearby sees them.
--   * Movement overrides: swaps the default Animate script's walk/run/idle/
--     jump/fall/climb ids for the ones in Config/Animations.Movement.
--
-- The server never animates anything itself; it only tells clients what to play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animations = require(Shared.Config.Animations)
local Remotes = require(Shared.Remotes)

local Util = script.Parent.Parent.Util
local RemoteGuard = require(Util.RemoteGuard)
local Validate = require(Util.Validate)

local FX_RADIUS = 200

local AnimationService = {}

local function broadcast(character: Model, emoteId: string, except: Player?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local remote = Remotes.get("PoseFx")
	for _, p in Players:GetPlayers() do
		if p ~= except then
			local otherRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") and (otherRoot.Position - root.Position).Magnitude <= FX_RADIUS then
				remote:FireClient(p, character, emoteId)
			end
		end
	end
end

local function canAnimate(player: Player): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") then
		return nil
	end
	return character
end

-- Plays an automatic emote ("LevelUp" / "PlayerKO" keys of Animations.Auto)
-- on a player's character for everyone nearby, including that player.
function AnimationService.celebrate(player: Player, reason: string)
	local emoteId = Animations.Auto[reason]
	local character = canAnimate(player)
	if emoteId and character then
		broadcast(character, emoteId, nil)
	end
end

-- ===== Movement animation overrides =====

-- Default Animate script layout: Animate/<state>/<AnimationName>
local MOVEMENT_SLOTS = {
	idle = { "idle", { "Animation1", "Animation2" } },
	walk = { "walk", { "WalkAnim" } },
	run = { "run", { "RunAnim" } },
	jump = { "jump", { "JumpAnim" } },
	fall = { "fall", { "FallAnim" } },
	climb = { "climb", { "ClimbAnim" } },
}

local function hasOverrides(): boolean
	for _, id in Animations.Movement do
		if id ~= "" then
			return true
		end
	end
	return false
end

local function applyMovement(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	if not animate then
		return
	end
	for key, id in Animations.Movement do
		local slot = MOVEMENT_SLOTS[key]
		if id ~= "" and slot then
			local folder = animate:WaitForChild(slot[1], 5)
			if folder then
				for _, animName in slot[2] do
					local anim = folder:FindFirstChild(animName)
					if anim and anim:IsA("Animation") then
						anim.AnimationId = id
					end
				end
			end
		end
	end
end

function AnimationService.start()
	RemoteGuard.connect("Emote", function(player, emoteId)
		if not Validate.str(emoteId, 32) or not Animations.EmotesById[emoteId] then
			return
		end
		local character = canAnimate(player)
		if character then
			-- The sender already played it locally for instant feedback.
			broadcast(character, emoteId, player)
		end
	end)

	if hasOverrides() then
		local function hook(player: Player)
			player.CharacterAdded:Connect(applyMovement)
			if player.Character then
				task.spawn(applyMovement, player.Character)
			end
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in Players:GetPlayers() do
			hook(player)
		end
	end
end

return AnimationService
