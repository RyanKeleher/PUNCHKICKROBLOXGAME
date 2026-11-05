-- Global tuning for Punch Kick. Every number that affects balance lives in a
-- Config module so you can rebalance without touching service code.

local GameConfig = {}

GameConfig.Progression = {
	MaxLevel = 150,
	-- XP needed to go from `level` to `level + 1` = floor(XpBase * level ^ XpExponent)
	XpBase = 40,
	XpExponent = 1.55,
	StatPointsPerLevel = 2,
	StatCap = 75, -- max points in any single stat

	Power = {
		DamagePerPoint = 0.06, -- +6% damage per point
		DamagePerLevel = 0.015, -- +1.5% damage per level (free scaling)
		KnockbackPerPoint = 0.015,
	},
	Agility = {
		WalkSpeedBase = 16,
		WalkSpeedPerPoint = 0.2,
		WalkSpeedMax = 30,
		CooldownReductionPerPoint = 0.008,
		CooldownMinMultiplier = 0.55, -- cooldowns never drop below 55%
	},
	Vitality = {
		HealthBase = 100,
		HealthPerPoint = 12,
		HealthPerLevel = 3,
	},
}

GameConfig.Rebirth = {
	MinLevel = 30,
	BaseCost = 5000, -- coins for the first rebirth
	CostGrowth = 1.6, -- each rebirth costs 1.6x the previous
	RewardBonusPerRebirth = 0.25, -- +25% XP and coins per rebirth
}

GameConfig.Streak = {
	WindowSeconds = 2.5, -- hits within this window keep the streak alive
	BonusPerHit = 0.02, -- +2% XP per hit in the streak
	MaxBonus = 0.5, -- capped at +50%
}

GameConfig.PvP = {
	DamageScale = 0.6, -- player-vs-player damage is softer than vs targets
	KnockbackScale = 1.0,
	KoCoinsBase = 25,
	KoCoinsPerVictimLevel = 4,
	KoXpBase = 40,
	KoXpPerVictimLevel = 6,
	CreditWindowSeconds = 10, -- last hitter within 10s gets the KO
	SpawnProtectionSeconds = 4,
}

GameConfig.Daily = {
	CooldownHours = 20,
	CoinsBase = 150,
	CoinsPerLevel = 15,
}

GameConfig.Data = {
	StoreName = "PunchKick_Profiles",
	KeyPrefix = "player_",
	SchemaVersion = 1,
	AutosaveSeconds = 120,
	-- A session lock older than this is considered abandoned (crashed server).
	LockTimeoutSeconds = 600,
	LoadRetries = 5,
}

GameConfig.Leaderboard = {
	StoreName = "PunchKick_TopFighters",
	RefreshSeconds = 120,
	Size = 10,
}

GameConfig.Starter = {
	Moves = { "punch", "kick" }, -- owned from the start
	Loadout = { "kick", "", "", "" }, -- 4 move slots; "" = empty
	Coins = 0,
}

GameConfig.LoadoutSize = 4

GameConfig.World = {
	Height = 100, -- floors float at this Y (sky gyms)
	FallLimit = 40, -- fall this far below and you're returned to your zone
	ZoneCheckSeconds = 0.5,
}

GameConfig.Targets = {
	KoDebrisSeconds = 3, -- how long a knocked-out dummy flops around before vanishing
}

-- Built-in Roblox sounds. Swap these for your own uploaded rbxassetid:// ids.
GameConfig.Sounds = {
	Swing = "rbxasset://sounds/swordlunge.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
	LevelUp = "rbxasset://sounds/electronicpingshort.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
}

-- Token buckets per player per remote: rate = requests/sec refill, burst = bucket size.
GameConfig.RateLimits = {
	Attack = { rate = 12, burst = 16 },
	SpendStat = { rate = 8, burst = 12 },
	UnlockMove = { rate = 3, burst = 5 },
	EquipMove = { rate = 6, burst = 10 },
	BuyCosmetic = { rate = 3, burst = 5 },
	EquipCosmetic = { rate = 6, burst = 10 },
	Rebirth = { rate = 0.5, burst = 2 },
	ClaimDaily = { rate = 0.5, burst = 2 },
	RequestSync = { rate = 0.5, burst = 3 },
}

GameConfig.Dev = {
	-- Chat commands like /coins 5000. Only ever active inside Roblox Studio.
	ChatCommands = true,
	RunTests = true,
}

return GameConfig
