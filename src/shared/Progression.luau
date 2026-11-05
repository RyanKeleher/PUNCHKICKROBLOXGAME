-- Pure progression math shared by server and client. The server uses it to
-- decide real outcomes; the client uses the SAME functions to display values
-- (cooldowns, damage multipliers), so the UI can never disagree with the server.
-- No Instances, no yielding: everything here is unit-testable.

local GameConfig = require(script.Parent.Config.GameConfig)

local P = GameConfig.Progression

local Progression = {}

Progression.STATS = { "power", "agility", "vitality" }

function Progression.xpToNext(level: number): number
	return math.floor(P.XpBase * level ^ P.XpExponent)
end

function Progression.damageMultiplier(data): number
	return 1 + data.stats.power * P.Power.DamagePerPoint + (data.level - 1) * P.Power.DamagePerLevel
end

function Progression.knockbackMultiplier(data): number
	return 1 + data.stats.power * P.Power.KnockbackPerPoint
end

function Progression.walkSpeed(data): number
	return math.min(P.Agility.WalkSpeedMax, P.Agility.WalkSpeedBase + data.stats.agility * P.Agility.WalkSpeedPerPoint)
end

function Progression.cooldownMultiplier(data): number
	return math.max(P.Agility.CooldownMinMultiplier, 1 - data.stats.agility * P.Agility.CooldownReductionPerPoint)
end

function Progression.maxHealth(data): number
	return P.Vitality.HealthBase + data.stats.vitality * P.Vitality.HealthPerPoint + (data.level - 1) * P.Vitality.HealthPerLevel
end

function Progression.rewardMultiplier(data): number
	return 1 + data.rebirths * GameConfig.Rebirth.RewardBonusPerRebirth
end

function Progression.rebirthCost(rebirths: number): number
	return math.floor(GameConfig.Rebirth.BaseCost * GameConfig.Rebirth.CostGrowth ^ rebirths)
end

function Progression.canRebirth(data): (boolean, string?)
	if data.level < GameConfig.Rebirth.MinLevel then
		return false, `Reach level {GameConfig.Rebirth.MinLevel} to rebirth`
	end
	if data.coins < Progression.rebirthCost(data.rebirths) then
		return false, "Not enough coins"
	end
	return true, nil
end

function Progression.streakBonus(streak: number): number
	return math.min(GameConfig.Streak.MaxBonus, math.max(0, streak - 1) * GameConfig.Streak.BonusPerHit)
end

-- Adds XP and levels up as many times as needed. Mutates `data`.
-- Returns the number of levels gained.
function Progression.addXp(data, amount: number): number
	if amount <= 0 then
		return 0
	end
	data.xp += amount
	local gained = 0
	while data.level < P.MaxLevel do
		local need = Progression.xpToNext(data.level)
		if data.xp < need then
			break
		end
		data.xp -= need
		data.level += 1
		data.statPoints += P.StatPointsPerLevel
		gained += 1
	end
	if data.level >= P.MaxLevel then
		data.xp = 0 -- nothing more to earn; rebirth instead
	end
	return gained
end

-- Applies a rebirth: resets level/stats, keeps moves and cosmetics. Mutates `data`.
function Progression.applyRebirth(data)
	data.coins -= Progression.rebirthCost(data.rebirths)
	data.rebirths += 1
	data.level = 1
	data.xp = 0
	data.statPoints = 0
	for _, stat in Progression.STATS do
		data.stats[stat] = 0
	end
end

return Progression
