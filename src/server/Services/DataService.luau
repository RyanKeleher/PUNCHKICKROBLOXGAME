-- Player profiles persisted with DataStoreService.
--
-- Stored value per player:  { schema = n, lock = { jobId, time }?, data = {...} }
--
-- * Session locking: while a server has a player loaded it writes its JobId into
--   `lock`. Another server (e.g. the player rejoined fast into a new server)
--   waits for the lock to clear instead of loading stale data and later
--   overwriting newer progress. A lock older than LockTimeoutSeconds is treated
--   as abandoned (crashed server) and taken over.
-- * Every read-modify-write goes through UpdateAsync (atomic per key), never
--   SetAsync, so two servers can't silently clobber each other.
-- * Retries with exponential backoff, autosave, save on leave, BindToClose.
-- * If DataStores are unavailable (Studio without API access) the player gets a
--   temporary profile that is never saved, and a warning is printed.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Remotes = require(Shared.Remotes)

local CFG = GameConfig.Data

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- (player, data)
DataService.Saved = Signal.new() -- (player, data)

local profiles: { [Player]: { data: any, temporary: boolean } } = {}
local jobId = if RunService:IsStudio() then "studio-" .. HttpService:GenerateGUID(false) else game.JobId

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CFG.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable, progress will NOT save:", result)
	end
end

-- ===== Schema =====

local function template()
	return {
		level = 1,
		xp = 0,
		coins = GameConfig.Starter.Coins,
		statPoints = 0,
		stats = { power = 0, agility = 0, vitality = 0 },
		rebirths = 0,
		unlockedMoves = {},
		loadout = table.clone(GameConfig.Starter.Loadout),
		ownedCosmetics = {},
		equipped = { aura = "", trail = "", gloves = "", title = "" },
		totalKOs = 0,
		playerKOs = 0,
		lastDaily = 0,
		firstJoin = os.time(),
	}
end

local function deepCopy(t)
	local copy = {}
	for k, v in t do
		copy[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return copy
end

-- Fills any missing fields from the template (new fields added in updates),
-- recursively, without overwriting existing values.
local function reconcile(data, defaults)
	for k, v in defaults do
		if data[k] == nil then
			data[k] = if type(v) == "table" then deepCopy(v) else v
		elseif type(v) == "table" and type(data[k]) == "table" and #v == 0 then
			reconcile(data[k], v)
		end
	end
end

-- Version migrations. Bump GameConfig.Data.SchemaVersion and add a step here
-- whenever the shape of saved data changes in a way reconcile can't handle.
local function migrate(stored)
	local schema = stored.schema or 1
	-- if schema < 2 then ... ; schema = 2 end
	stored.schema = schema
	return stored
end

local function finalize(data)
	reconcile(data, template())
	for _, id in GameConfig.Starter.Moves do
		data.unlockedMoves[id] = true
	end
	-- Loadout must always be exactly LoadoutSize strings.
	for i = 1, GameConfig.LoadoutSize do
		if type(data.loadout[i]) ~= "string" then
			data.loadout[i] = ""
		end
	end
	return data
end

-- ===== Store access =====

local function keyFor(player: Player): string
	return CFG.KeyPrefix .. player.UserId
end

local function isAccessError(err: any): boolean
	local text = tostring(err)
	return string.find(text, "403", 1, true) ~= nil or string.find(text, "Studio access", 1, true) ~= nil
end

-- Loads (and locks) a profile. Returns (data, temporary).
local function loadProfile(player: Player)
	if not store then
		return finalize(template()), true
	end
	local key = keyFor(player)

	for attempt = 1, CFG.LoadRetries do
		local lastAttempt = attempt == CFG.LoadRetries
		local lockedElsewhere = false

		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(stored)
				lockedElsewhere = false
				stored = stored or { schema = CFG.SchemaVersion, data = template() }
				local lock = stored.lock
				local fresh = lock and lock.jobId ~= jobId and os.time() - (lock.time or 0) < CFG.LockTimeoutSeconds
				if fresh and not lastAttempt then
					lockedElsewhere = true
					return nil -- cancel this write, retry shortly
				end
				stored = migrate(stored)
				stored.lock = { jobId = jobId, time = os.time() }
				return stored
			end)
		end)

		if ok and result and not lockedElsewhere then
			return finalize(result.data or template()), false
		end
		if not ok then
			warn(`[DataService] Load attempt {attempt} for {player.Name} failed: {result}`)
			if isAccessError(result) then
				warn("[DataService] DataStore access denied. In Studio: Game Settings > Security > Enable Studio Access to API Services.")
				return finalize(template()), true
			end
		end
		task.wait(2 ^ attempt) -- 2, 4, 8, 16s backoff
		if not player.Parent then
			return nil, true
		end
	end

	warn(`[DataService] Could not load {player.Name}; using a temporary profile`)
	return finalize(template()), true
end

local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or profile.temporary or not store then
		return true
	end
	local snapshot = deepCopy(profile.data)

	for attempt = 1, 4 do
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(stored)
				if stored and stored.lock and stored.lock.jobId ~= jobId then
					-- Another server took this profile over; never overwrite it.
					warn(`[DataService] Lock for {player.Name} is held elsewhere; skipping save`)
					return nil
				end
				return {
					schema = CFG.SchemaVersion,
					lock = if release then nil else { jobId = jobId, time = os.time() },
					data = snapshot,
				}
			end)
		end)
		if ok then
			DataService.Saved:Fire(player, snapshot)
			return true
		end
		warn(`[DataService] Save attempt {attempt} for {player.Name} failed: {err}`)
		task.wait(2 ^ attempt)
	end
	return false
end

-- ===== Public API =====

-- Returns the live profile data table, or nil while loading.
-- Services mutate it directly, then call PlayerSync.mark(player).
function DataService.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.isTemporary(player: Player): boolean
	local profile = profiles[player]
	return profile == nil or profile.temporary
end

function DataService.save(player: Player)
	return saveProfile(player, false)
end

-- Dev helper: wipe one player's progress in this session (Studio only).
function DataService.resetForDev(player: Player)
	local profile = profiles[player]
	if profile then
		profile.data = finalize(template())
		DataService.ProfileLoaded:Fire(player, profile.data)
	end
end

local function onPlayerAdded(player: Player)
	local data, temporary = loadProfile(player)
	if not data then
		return -- left while loading
	end
	if not player.Parent then
		-- Left during the load: release the lock we just took.
		profiles[player] = { data = data, temporary = temporary }
		saveProfile(player, true)
		profiles[player] = nil
		return
	end
	profiles[player] = { data = data, temporary = temporary }
	if temporary then
		task.delay(3, function()
			if player.Parent then
				Remotes.get("Notify"):FireClient(player, "Data couldn't load: progress this session won't save", "error")
			end
		end)
	end
	DataService.ProfileLoaded:Fire(player, data)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if not profile then
			return
		end
		saveProfile(player, true)
		profiles[player] = nil
	end)

	-- Autosave: one loop for everyone (not one per player).
	task.spawn(function()
		while true do
			task.wait(CFG.AutosaveSeconds)
			for player in profiles do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	-- Server shutting down: save everyone in parallel and wait (max ~25s).
	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
