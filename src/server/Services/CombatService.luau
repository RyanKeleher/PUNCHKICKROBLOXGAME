-- Server-authoritative combat.
--
-- The client only says "I used move X, facing direction D". The server:
--   1. validates the move id, that the player owns it and has it equipped
--   2. enforces the cooldown (with Agility) using the SERVER clock
--   3. waits the move's wind-up (hitDelay), then builds the hitbox from the
--      SERVER's copy of the character's position
--   4. finds targets with a spatial query, applies damage/knockback/rewards
-- The client never reports what it hit, so "hit everything on the map"
-- exploits don't work. The facing direction is the only client input used,
-- and all it can do is aim your own attack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Moves = require(Shared.Config.Moves)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local Util = script.Parent.Parent.Util
local RemoteGuard = require(Util.RemoteGuard)
local Validate = require(Util.Validate)

local DataService = require(script.Parent.DataService)
local PlayerSync = require(script.Parent.PlayerSync)
local StatsService = require(script.Parent.StatsService)
local TargetService = require(script.Parent.TargetService)
local RagdollService = require(script.Parent.RagdollService)
local ZoneService = require(script.Parent.ZoneService)
local AnimationService = require(script.Parent.AnimationService)

local FX_RADIUS = 220 -- only send visual effects to players this close
local COOLDOWN_TOLERANCE = 0.85 -- accept slightly-early requests (network jitter)

local CombatService = {}

local lastUse: { [Player]: { [string]: number } } = {}
local streaks: { [Player]: { count: number, last: number } } = {}
local lastHitBy: { [Player]: { attacker: Player, time: number } } = {}
local protectedUntil: { [Player]: number } = {}
local punchVariant: { [Player]: number } = {}

local function aliveRoot(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, root, humanoid
end

local function nearbyPlayers(position: Vector3): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") and (r.Position - position).Magnitude <= FX_RADIUS then
			table.insert(out, p)
		end
	end
	return out
end

local function fireNearby(remoteName: string, position: Vector3, except: Player?, ...)
	local remote = Remotes.get(remoteName)
	for _, p in nearbyPlayers(position) do
		if p ~= except then
			remote:FireClient(p, ...)
		end
	end
end

-- Returns a list of hits: { kind = "target", model } or { kind = "player", player, root }
local function findTargets(attacker: Player, character: Model, root: BasePart, facing: Vector3, move)
	local include: { Instance } = { TargetService.folder }
	for _, p in Players:GetPlayers() do
		if p ~= attacker and p.Character then
			table.insert(include, p.Character)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include

	local parts
	if move.hitbox.kind == "radius" then
		parts = workspace:GetPartBoundsInRadius(root.Position, move.hitbox.radius, params)
	else
		local cf = CFrame.lookAt(root.Position, root.Position + facing) * CFrame.new(0, 0, -move.hitbox.forward)
		parts = workspace:GetPartBoundsInBox(cf, move.hitbox.size, params)
	end

	local hits = {}
	local seen = {}
	for _, part in parts do
		if #hits >= move.maxTargets then
			break
		end
		local target = TargetService.modelFromPart(part)
		if target then
			if not seen[target] then
				seen[target] = true
				table.insert(hits, { kind = "target", model = target })
			end
		else
			local model = part:FindFirstAncestorOfClass("Model")
			local victim = model and Players:GetPlayerFromCharacter(model)
			if victim and not seen[victim] and model ~= character then
				local _, victimRoot = aliveRoot(victim)
				if victimRoot then
					seen[victim] = true
					table.insert(hits, { kind = "player", player = victim, root = victimRoot })
				end
			end
		end
	end
	return hits
end

local function knockbackFor(move, data, fromPos: Vector3, toPos: Vector3, facing: Vector3): Vector3
	local dir = facing
	if move.hitbox.kind == "radius" then
		local flat = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
		dir = if flat.Magnitude > 0.1 then flat.Unit else facing
	end
	local mult = Progression.knockbackMultiplier(data)
	return dir * move.knockback.forward * mult + Vector3.new(0, move.knockback.up * mult, 0)
end

local function updateStreak(player: Player): number
	local now = os.clock()
	local s = streaks[player]
	if s and now - s.last <= GameConfig.Streak.WindowSeconds then
		s.count += 1
		s.last = now
	else
		s = { count = 1, last = now }
		streaks[player] = s
	end
	player:SetAttribute("Streak", s.count)
	return s.count
end

local function resolve(attacker: Player, move, facing: Vector3)
	local data = DataService.get(attacker)
	local character, root = aliveRoot(attacker)
	if not data or not character or not root or character:GetAttribute("Ragdolled") then
		return
	end

	local hits = findTargets(attacker, character, root, facing, move)
	if #hits == 0 then
		return
	end

	local damage = move.damage * Progression.damageMultiplier(data)
	local xpTotal, coinsTotal, landed = 0, 0, 0
	local attackerInPvP = ZoneService.isPvP(attacker)

	for _, hit in hits do
		if hit.kind == "target" then
			local targetPos = hit.model:GetPivot().Position
			local kb = knockbackFor(move, data, root.Position, targetPos, facing)
			local result = TargetService.damage(hit.model, damage, kb)
			if result then
				landed += 1
				xpTotal += result.xp
				coinsTotal += result.coins
				if result.ko then
					data.totalKOs += 1
				end
				fireNearby("HitFx", result.position, nil, result.position, result.damage, result.ko, move.id, hit.model)
			end
		elseif hit.kind == "player" then
			local victim = hit.player
			local victimChar, victimRoot, victimHumanoid = aliveRoot(victim)
			local allowed = attackerInPvP
				and ZoneService.isPvP(victim)
				and os.clock() >= (protectedUntil[victim] or 0)
				and victimChar ~= nil
			if allowed and victimRoot and victimHumanoid then
				local dealt = damage * GameConfig.PvP.DamageScale
				victimHumanoid:TakeDamage(dealt)
				lastHitBy[victim] = { attacker = attacker, time = os.clock() }
				landed += 1

				local kb = knockbackFor(move, data, root.Position, victimRoot.Position, facing) * GameConfig.PvP.KnockbackScale
				if move.ragdoll > 0 then
					RagdollService.ragdollPlayer(victim, kb, move.ragdoll)
				else
					RagdollService.pushPlayer(victim, kb)
				end
				fireNearby("HitFx", victimRoot.Position, nil, victimRoot.Position, dealt, false, move.id, victimChar)
			end
		end
	end

	if landed > 0 then
		local streak = updateStreak(attacker)
		local bonus = 1 + Progression.streakBonus(streak)
		StatsService.addXp(attacker, xpTotal * bonus)
		StatsService.addCoins(attacker, coinsTotal)
		PlayerSync.mark(attacker)
	end
end

local function onAttack(player: Player, moveId: any, facing: any)
	if not Validate.str(moveId, 32) then
		return
	end
	local move = Moves.byId[moveId]
	local data = DataService.get(player)
	if not move or not data then
		return
	end
	if not move.basic then
		if not data.unlockedMoves[moveId] or not table.find(data.loadout, moveId) then
			return
		end
	end

	local character, root = aliveRoot(player)
	if not character or not root or character:GetAttribute("Ragdolled") then
		return
	end

	-- Cooldown on the server clock.
	local now = os.clock()
	local uses = lastUse[player]
	if not uses then
		uses = {}
		lastUse[player] = uses
	end
	local cooldown = move.cooldown * Progression.cooldownMultiplier(data) * COOLDOWN_TOLERANCE
	if now - (uses[moveId] or -math.huge) < cooldown then
		return
	end
	uses[moveId] = now

	-- Facing: horizontal unit vector from the client, or the server's own facing.
	local dir = root.CFrame.LookVector
	if Validate.vector(facing) then
		local flat = Vector3.new(facing.X, 0, facing.Z)
		if flat.Magnitude > 0.1 then
			dir = flat.Unit
		end
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)

	-- Alternate left/right punches (purely visual, but everyone sees the same one).
	local variant = 1
	if move.basic then
		variant = if (punchVariant[player] or 1) == 1 then 2 else 1
		punchVariant[player] = variant
	end
	fireNearby("AttackFx", root.Position, player, character, move.id, variant)

	task.delay(move.hitDelay, resolve, player, move, dir)
end

local function onCharacterAdded(player: Player, character: Model)
	protectedUntil[player] = os.clock() + GameConfig.PvP.SpawnProtectionSeconds
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		local credit = lastHitBy[player]
		lastHitBy[player] = nil
		if not credit or os.clock() - credit.time > GameConfig.PvP.CreditWindowSeconds then
			return
		end
		local killer = credit.attacker
		local killerData = DataService.get(killer)
		local victimData = DataService.get(player)
		if not killerData or not killer.Parent then
			return
		end
		local victimLevel = if victimData then victimData.level else 1
		killerData.playerKOs += 1
		StatsService.addCoins(killer, GameConfig.PvP.KoCoinsBase + victimLevel * GameConfig.PvP.KoCoinsPerVictimLevel)
		StatsService.addXp(killer, GameConfig.PvP.KoXpBase + victimLevel * GameConfig.PvP.KoXpPerVictimLevel)
		for _, p in Players:GetPlayers() do
			Remotes.get("KoFeed"):FireClient(p, killer.DisplayName, player.DisplayName)
		end
		AnimationService.celebrate(killer, "PlayerKO")
	end)
end

function CombatService.start()
	RemoteGuard.connect("Attack", onAttack)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		streaks[player] = nil
		lastHitBy[player] = nil
		protectedUntil[player] = nil
		punchVariant[player] = nil
		-- Drop any KO credit this player held over others.
		for victim, credit in lastHitBy do
			if credit.attacker == player then
				lastHitBy[victim] = nil
			end
		end
	end)
end

return CombatService
