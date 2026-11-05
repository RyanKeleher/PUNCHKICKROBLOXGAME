-- Self-tests for the pure Progression module and the config tables.
-- Runs automatically when you press Play in Studio; check the Output window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Progression)
local Moves = require(Shared.Config.Moves)
local Targets = require(Shared.Config.Targets)
local Zones = require(Shared.Config.Zones)
local Cosmetics = require(Shared.Config.Cosmetics)
local Format = require(Shared.Util.Format)
local Animations = require(Shared.Config.Animations)
local PoseMath = require(Shared.PoseMath)

local Tests = {}

local function newData()
	return {
		level = 1,
		xp = 0,
		coins = 0,
		statPoints = 0,
		rebirths = 0,
		stats = { power = 0, agility = 0, vitality = 0 },
	}
end

local cases = {
	{
		"xpToNext grows with level",
		function()
			assert(Progression.xpToNext(2) > Progression.xpToNext(1))
			assert(Progression.xpToNext(1) == GameConfig.Progression.XpBase)
		end,
	},
	{
		"addXp levels up and grants stat points",
		function()
			local d = newData()
			local gained = Progression.addXp(d, Progression.xpToNext(1) + Progression.xpToNext(2) + 5)
			assert(gained == 2, "gained " .. gained)
			assert(d.level == 3 and d.xp == 5)
			assert(d.statPoints == 2 * GameConfig.Progression.StatPointsPerLevel)
		end,
	},
	{
		"addXp stops at max level",
		function()
			local d = newData()
			Progression.addXp(d, 1e15)
			assert(d.level == GameConfig.Progression.MaxLevel and d.xp == 0)
		end,
	},
	{
		"stats change multipliers in the right direction",
		function()
			local d = newData()
			local dmg, cd, hp, ws = Progression.damageMultiplier(d), Progression.cooldownMultiplier(d), Progression.maxHealth(d), Progression.walkSpeed(d)
			d.stats.power, d.stats.agility, d.stats.vitality = 10, 10, 10
			assert(Progression.damageMultiplier(d) > dmg)
			assert(Progression.cooldownMultiplier(d) < cd)
			assert(Progression.maxHealth(d) > hp)
			assert(Progression.walkSpeed(d) > ws)
			d.stats.agility = 1000
			assert(Progression.cooldownMultiplier(d) == GameConfig.Progression.Agility.CooldownMinMultiplier)
			assert(Progression.walkSpeed(d) == GameConfig.Progression.Agility.WalkSpeedMax)
		end,
	},
	{
		"rebirth requires level and coins, then resets",
		function()
			local d = newData()
			assert(not Progression.canRebirth(d))
			d.level = GameConfig.Rebirth.MinLevel
			assert(not Progression.canRebirth(d))
			d.coins = Progression.rebirthCost(0) + 7
			d.stats.power = 5
			assert(Progression.canRebirth(d))
			Progression.applyRebirth(d)
			assert(d.level == 1 and d.rebirths == 1 and d.coins == 7 and d.stats.power == 0)
			assert(Progression.rewardMultiplier(d) > 1)
			assert(Progression.rebirthCost(1) > Progression.rebirthCost(0))
		end,
	},
	{
		"streak bonus is capped",
		function()
			assert(Progression.streakBonus(1) == 0)
			assert(Progression.streakBonus(1000) == GameConfig.Streak.MaxBonus)
		end,
	},
	{
		"format helpers",
		function()
			assert(Format.commas(1234567) == "1,234,567", Format.commas(1234567))
			assert(Format.commas(999) == "999")
			assert(Format.short(1500) == "1.5K", Format.short(1500))
			assert(Format.short(2000000) == "2M", Format.short(2000000))
			assert(Format.short(42) == "42")
		end,
	},
	{
		"config tables are consistent",
		function()
			assert(Moves.byId[Moves.BASIC_ID] and Moves.byId[Moves.BASIC_ID].basic)
			for _, id in GameConfig.Starter.Moves do
				assert(Moves.byId[id], "starter move missing: " .. id)
			end
			for _, id in GameConfig.Starter.Loadout do
				assert(id == "" or Moves.byId[id], "starter loadout move missing: " .. id)
			end
			for _, move in Moves.list do
				assert(move.pose and move.pose.duration > 0, move.id .. " has no pose")
				assert(move.hitbox.kind == "box" or move.hitbox.kind == "radius", move.id .. " bad hitbox")
			end
			for _, zone in Zones.list do
				for _, group in zone.targets do
					assert(Targets[group.type], `zone {zone.id} uses unknown target {group.type}`)
				end
			end
			for _, pair in Zones.connections do
				local a, b = Zones.byId[pair[1]], Zones.byId[pair[2]]
				assert(a and b, "bad connection")
				assert(a.center.X == b.center.X or a.center.Z == b.center.Z, `bridge {pair[1]}-{pair[2]} must be axis-aligned`)
			end
			assert(#Cosmetics.list > 0)
		end,
	},
	{
		"animation poses only use known joints and valid timings",
		function()
			local function checkPose(name: string, pose)
				assert(pose.duration > 0, name .. ": duration must be > 0")
				local last = -1
				for _, frame in pose.frames do
					assert(frame.t >= last, name .. ": keyframes must be in time order")
					assert(frame.t <= pose.duration + 1e-6, name .. ": keyframe after the end")
					last = frame.t
				end
				for joint in PoseMath.jointSet(pose) do
					assert(PoseMath.R15_PARTS[joint], `{name}: unknown joint {joint}`)
				end
			end
			for _, move in Moves.list do
				checkPose(move.id, move.pose)
				if move.poseAlt then
					checkPose(move.id .. " (alt)", move.poseAlt)
				end
			end
			checkPose("HitReact", Animations.HitReact.pose)
			local keys = {}
			for _, emote in Animations.Emotes do
				checkPose("emote " .. emote.id, emote.pose)
				if emote.key then
					assert(not keys[emote.key], "two emotes share key " .. emote.key.Name)
					keys[emote.key] = true
				end
			end
			for joint in Animations.Stance.joints do
				assert(PoseMath.R15_PARTS[joint], "stance: unknown joint " .. joint)
			end
			for reason, emoteId in Animations.Auto do
				assert(Animations.EmotesById[emoteId], `Auto.{reason} uses unknown emote {emoteId}`)
			end
			-- Sampling: start of a pose is its first frame, and it ends at rest.
			local punch = Moves.byId.punch.pose
			assert(PoseMath.sample(punch, 0, "RightShoulder") == Vector3.zero)
			assert(PoseMath.sample(punch, punch.duration, "RightShoulder") == Vector3.zero)
			assert(PoseMath.sample(punch, 0.07, "RightShoulder").X > 90)
		end,
	},
}

function Tests.run()
	local passed = 0
	for _, case in cases do
		local ok, err = pcall(case[2])
		if ok then
			passed += 1
		else
			warn("[ProgressionTests] FAIL:", case[1], "-", err)
		end
	end
	print(`[ProgressionTests] {passed}/{#cases} passed`)
end

return Tests
