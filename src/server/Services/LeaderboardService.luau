-- Global "Top Fighters" board in the Starter Gym, backed by an OrderedDataStore.
-- Score = rebirths * 1000 + level, written whenever a profile saves, and the
-- board refreshes every RefreshSeconds. All DataStore calls are pcall'd: if
-- they fail (e.g. Studio without API access) the board just says so.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)

local DataService = require(script.Parent.DataService)

local CFG = GameConfig.Leaderboard
local H = GameConfig.World.Height

local LeaderboardService = {}

local ordered: OrderedDataStore? = nil
local nameCache: { [number]: string } = {}
local rows: { TextLabel } = {}
local status: TextLabel? = nil

local function score(data): number
	return data.rebirths * 1000 + data.level
end

local function describe(value: number): string
	local rebirths = math.floor(value / 1000)
	local level = value % 1000
	return if rebirths > 0 then `★{rebirths}  Lv {level}` else `Lv {level}`
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and name then name else `User {userId}`
	nameCache[userId] = result
	return result
end

local function buildBoard()
	local gym = Zones.list[1]
	local board = Instance.new("Part")
	board.Name = "TopFightersBoard"
	board.Anchored = true
	board.Size = Vector3.new(20, 14, 1)
	board.Color = Color3.fromRGB(20, 20, 26)
	board.Material = Enum.Material.SmoothPlastic
	local pos = Vector3.new(gym.center.X, H + 9, gym.center.Z - gym.size.Z / 2 + 6) -- back wall, away from the arena bridge
	board.CFrame = CFrame.lookAt(pos, Vector3.new(gym.center.X, H + 9, gym.center.Z))
	board.Parent = workspace

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(600, 420)
	gui.LightInfluence = 0
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 40
	title.TextColor3 = Color3.fromRGB(255, 200, 60)
	title.Text = "TOP FIGHTERS"
	title.Parent = gui

	for i = 1, CFG.Size do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(30, 60 + (i - 1) * 32)
		row.Size = UDim2.new(1, -60, 0, 30)
		row.Font = Enum.Font.GothamBold
		row.TextSize = 24
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1 then Color3.fromRGB(255, 215, 0) elseif i <= 3 then Color3.fromRGB(220, 220, 230) else Color3.fromRGB(170, 170, 180)
		row.Text = ""
		row.Parent = gui
		rows[i] = row
	end

	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.new(0, 0, 1, -36)
	s.Size = UDim2.new(1, 0, 0, 30)
	s.Font = Enum.Font.Gotham
	s.TextSize = 18
	s.TextColor3 = Color3.fromRGB(140, 140, 150)
	s.Text = "Loading..."
	s.Parent = gui
	status = s
end

local function refresh()
	if not ordered then
		return
	end
	local ok, pages = pcall(function()
		return ordered:GetSortedAsync(false, CFG.Size)
	end)
	if not ok or not pages then
		if status then
			status.Text = "Leaderboard unavailable"
		end
		return
	end
	local entries = pages:GetCurrentPage()
	for i = 1, CFG.Size do
		local entry = entries[i]
		if entry then
			local userId = tonumber(entry.key) or 0
			rows[i].Text = `#{i}   {nameFor(userId)}   —   {describe(entry.value)}`
		else
			rows[i].Text = ""
		end
	end
	if status then
		status.Text = `Updates every {CFG.RefreshSeconds}s`
	end
end

function LeaderboardService.start()
	buildBoard()

	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(CFG.StoreName)
	end)
	if ok then
		ordered = result
	elseif status then
		status.Text = "Leaderboard unavailable"
	end

	DataService.Saved:Connect(function(player, data)
		if ordered and not DataService.isTemporary(player) then
			pcall(function()
				ordered:SetAsync(tostring(player.UserId), score(data))
			end)
		end
	end)

	task.spawn(function()
		while true do
			refresh()
			task.wait(CFG.RefreshSeconds)
		end
	end)
end

return LeaderboardService
