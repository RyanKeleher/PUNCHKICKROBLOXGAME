-- Always-on screen UI: level/XP/coins panel, move bar with cooldowns,
-- mobile attack buttons, toasts, level-up banner, zone banner, streak counter
-- and KO feed. Built entirely in code.
--
-- The HUD only DISPLAYS things and reports button presses through signals;
-- CombatController decides what a press does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Moves = require(Shared.Config.Moves)
local Zones = require(Shared.Config.Zones)
local Animations = require(Shared.Config.Animations)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)
local Signal = require(Shared.Util.Signal)

local UIKit = require(script.Parent.UIKit)
local C = UIKit.Colors

local player = Players.LocalPlayer

local HUD = {}
HUD.__index = HUD

local SLOT = 70
local SLOT_KEYS = { "CLICK", "1 / Q", "2 / E", "3 / R", "4 / F" }
local SLOT_KEYS_PAD = { "R2", "X", "Y", "B", "R1" }

local TOAST_COLORS = {
	error = C.Bad,
	success = C.Good,
	level = C.Accent,
	rebirth = Color3.fromRGB(255, 120, 220),
}

function HUD.new()
	local self = setmetatable({}, HUD)
	self.MoveSlotPressed = Signal.new() -- (slotIndex 0..4)
	self.PunchHold = Signal.new() -- (holding: boolean)
	self.MenuPressed = Signal.new()
	self.EmotePressed = Signal.new() -- (emoteId)
	self.cooldowns = {} :: { [number]: { finish: number, duration: number } }
	self.isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local gui = Instance.new("ScreenGui")
	gui.Name = "PK_HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui

	self:_buildStats()
	self:_buildMoveBar()
	self:_buildTopRight()
	self:_buildEmotes()
	self:_buildCenter()
	if UserInputService.TouchEnabled then
		self:_buildTouchButtons()
	end
	return self
end

-- ===== Builders =====

function HUD:_buildStats()
	local panel = UIKit.frame(self.gui, {
		Name = "Stats",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(300, 118),
		BackgroundTransparency = 0.2,
	})
	UIKit.corner(panel, 12)
	UIKit.stroke(panel, Color3.fromRGB(0, 0, 0), 2)
	UIKit.autoScale(panel, Vector2.new(1000, 700), 0.6, 1.1)

	local badge = UIKit.frame(panel, {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = C.Accent,
	})
	UIKit.corner(badge, 31)
	UIKit.label(badge, { Text = "LV", TextSize = 12, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 6), TextColor3 = Color3.fromRGB(40, 30, 0) })
	self.levelText = UIKit.label(badge, {
		Text = "1",
		Font = Enum.Font.GothamBlack,
		TextSize = 26,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 22),
		TextColor3 = Color3.fromRGB(40, 30, 0),
	})

	self.rebirthText = UIKit.label(panel, {
		Position = UDim2.fromOffset(84, 8),
		Size = UDim2.fromOffset(200, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 200, 90),
		TextSize = 15,
	})

	local xpBack = UIKit.frame(panel, {
		Position = UDim2.fromOffset(84, 32),
		Size = UDim2.fromOffset(204, 22),
		BackgroundColor3 = Color3.fromRGB(12, 12, 16),
	})
	UIKit.corner(xpBack, 6)
	self.xpFill = UIKit.frame(xpBack, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Xp })
	UIKit.corner(self.xpFill, 6)
	self.xpText = UIKit.label(xpBack, { Size = UDim2.fromScale(1, 1), TextSize = 13, ZIndex = 2, TextStrokeTransparency = 0.4 })

	local coinIcon = UIKit.frame(panel, {
		Position = UDim2.fromOffset(84, 62),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = C.Coin,
	})
	UIKit.corner(coinIcon, 10)
	UIKit.stroke(coinIcon, Color3.fromRGB(150, 110, 0), 2)
	self.coinText = UIKit.label(panel, {
		Position = UDim2.fromOffset(110, 60),
		Size = UDim2.fromOffset(180, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Coin,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
	})

	self.pointsText = UIKit.label(panel, {
		Position = UDim2.fromOffset(10, 88),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Good,
		TextSize = 14,
	})
end

function HUD:_buildMoveBar()
	local count = GameConfig.LoadoutSize + 1
	local width = count * SLOT + (count - 1) * 8
	local bar = UIKit.frame(self.gui, {
		Name = "MoveBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(width, SLOT + 18),
		BackgroundTransparency = 1,
	})
	UIKit.autoScale(bar, Vector2.new(900, 650), 0.6, 1.1)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = bar

	self.slots = {}
	for i = 0, GameConfig.LoadoutSize do
		local holder = UIKit.frame(bar, { Size = UDim2.fromOffset(SLOT, SLOT + 18), BackgroundTransparency = 1, LayoutOrder = i })
		local b = UIKit.button(holder, "", {
			Name = "Slot" .. i,
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.fromOffset(SLOT, SLOT),
			BackgroundColor3 = if i == 0 then Color3.fromRGB(70, 55, 20) else C.PanelLight,
			AutoButtonColor = false,
		})
		local stroke = UIKit.stroke(b, if i == 0 then C.Accent else Color3.fromRGB(90, 90, 110), 2)
		local name = UIKit.label(b, { Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 14), Font = Enum.Font.GothamBlack, TextSize = 18, TextScaled = false })
		local sub = UIKit.label(b, { Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 44), TextSize = 11, TextColor3 = C.Muted })
		local overlay = UIKit.frame(b, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 3,
		})
		UIKit.corner(overlay, 8)
		local cdText = UIKit.label(b, { Size = UDim2.fromScale(1, 1), TextSize = 20, Font = Enum.Font.GothamBlack, ZIndex = 4 })
		local key = UIKit.label(holder, {
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 12,
			TextColor3 = C.Muted,
			Text = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then SLOT_KEYS_PAD[i + 1] else SLOT_KEYS[i + 1],
		})
		if self.isTouch then
			key.Text = ""
		end
		b.Activated:Connect(function()
			if i > 0 then
				self.MoveSlotPressed:Fire(i)
			end
		end)
		self.slots[i] = { button = b, stroke = stroke, name = name, sub = sub, overlay = overlay, cdText = cdText }
	end
end

function HUD:_buildTopRight()
	local menu = UIKit.button(self.gui, "MENU", {
		Name = "MenuButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(110, 46),
		BackgroundColor3 = C.Accent,
		TextColor3 = Color3.fromRGB(40, 30, 0),
		TextSize = 20,
	})
	UIKit.stroke(menu, Color3.fromRGB(0, 0, 0), 2)
	UIKit.autoScale(menu, Vector2.new(1000, 700), 0.7, 1.1)
	menu.Activated:Connect(function()
		self.MenuPressed:Fire()
	end)
	self.menuBadge = UIKit.frame(menu, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = C.Bad,
		Visible = false,
	})
	UIKit.corner(self.menuBadge, 11)
	UIKit.label(self.menuBadge, { Text = "!", Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextSize = 16 })
	UIKit.label(menu, {
		Text = if UserInputService.KeyboardEnabled then "[M]" else "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(60, 14),
		TextSize = 11,
		TextColor3 = C.Muted,
	})

	local feed = UIKit.frame(self.gui, {
		Name = "KoFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 84),
		Size = UDim2.fromOffset(280, 150),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = feed
	self.feed = feed
	self.feedOrder = 0
end

function HUD:_buildEmotes()
	local toggle = UIKit.button(self.gui, "EMOTE", {
		Name = "EmoteButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -132, 0, 12),
		Size = UDim2.fromOffset(100, 46),
		BackgroundColor3 = Color3.fromRGB(120, 80, 200),
		TextSize = 18,
	})
	UIKit.stroke(toggle, Color3.fromRGB(0, 0, 0), 2)
	UIKit.autoScale(toggle, Vector2.new(1000, 700), 0.7, 1.1)

	local panel = UIKit.frame(self.gui, {
		Name = "EmotePanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -132, 0, 66),
		Size = UDim2.fromOffset(150, #Animations.Emotes * 44 + 10),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	UIKit.corner(panel, 10)
	UIKit.padding(panel, 5)
	UIKit.autoScale(panel, Vector2.new(1000, 700), 0.7, 1.1)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local showKeys = UserInputService.KeyboardEnabled
	local KEY_LABELS = { Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0" }
	for i, emote in Animations.Emotes do
		local keyName = ""
		if emote.key and showKeys then
			keyName = ` [{KEY_LABELS[emote.key.Name] or emote.key.Name}]`
		end
		local b = UIKit.button(panel, emote.name .. keyName, {
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
			TextSize = 15,
		})
		b.Activated:Connect(function()
			panel.Visible = false
			self.EmotePressed:Fire(emote.id)
		end)
	end

	toggle.Activated:Connect(function()
		self:toggleEmotes()
	end)
	self.emotePanel = panel
end

function HUD:toggleEmotes()
	local panel = self.emotePanel
	panel.Visible = not panel.Visible
	if panel.Visible and UserInputService.GamepadEnabled then
		local first = panel:FindFirstChildWhichIsA("TextButton")
		if first then
			GuiService.SelectedObject = first
		end
	end
end

function HUD:_buildCenter()
	-- Toasts (pooled: 4 labels reused)
	local toastHolder = UIKit.frame(self.gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(460, 160),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastHolder
	self.toasts = {}
	for i = 1, 4 do
		local t = UIKit.label(toastHolder, {
			Size = UDim2.fromOffset(440, 32),
			BackgroundColor3 = Color3.fromRGB(15, 15, 20),
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextSize = 17,
			Visible = false,
		})
		UIKit.corner(t, 8)
		self.toasts[i] = { label = t, tween = nil }
	end
	self.toastIndex = 0
	self.toastOrder = 0

	-- Zone banner
	self.zoneBanner = UIKit.label(self.gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(500, 44),
		Font = Enum.Font.GothamBlack,
		TextSize = 34,
		TextStrokeTransparency = 0.3,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})
	self.zoneSub = UIKit.label(self.gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(500, 24),
		TextSize = 18,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	-- Persistent PvP warning
	self.pvpTag = UIKit.label(self.gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(240, 26),
		Text = "⚔ PVP ZONE ⚔",
		TextColor3 = Color3.fromRGB(255, 80, 80),
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})

	-- Streak
	self.streakText = UIKit.label(self.gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.32, 0),
		Size = UDim2.fromOffset(300, 40),
		Font = Enum.Font.GothamBlack,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(255, 170, 60),
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})

	-- Level-up banner
	self.levelBanner = UIKit.label(self.gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 80),
		Font = Enum.Font.GothamBlack,
		TextSize = 60,
		TextColor3 = C.Accent,
		TextStrokeTransparency = 0,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.fromRGB(80, 40, 0),
	})
end

function HUD:_buildTouchButtons()
	local holder = UIKit.frame(self.gui, {
		Name = "TouchAttack",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -150),
		Size = UDim2.fromOffset(110, 110),
		BackgroundTransparency = 1,
	})
	local punch = UIKit.button(holder, "PUNCH", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(200, 60, 50),
		TextSize = 22,
		AutoButtonColor = false,
	})
	UIKit.corner(punch, 55)
	UIKit.stroke(punch, Color3.fromRGB(0, 0, 0), 3)
	punch.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			punch.BackgroundColor3 = Color3.fromRGB(255, 90, 70)
			self.PunchHold:Fire(true)
		end
	end)
	punch.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			punch.BackgroundColor3 = Color3.fromRGB(200, 60, 50)
			self.PunchHold:Fire(false)
		end
	end)
end

-- ===== Updates =====

function HUD:render(data)
	self.data = data
	self.levelText.Text = tostring(data.level)
	local need = Progression.xpToNext(data.level)
	local atMax = data.level >= GameConfig.Progression.MaxLevel
	local frac = if atMax then 1 else math.clamp(data.xp / need, 0, 1)
	TweenService:Create(self.xpFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(frac, 1) }):Play()
	self.xpText.Text = if atMax then "MAX LEVEL - rebirth!" else `{Format.commas(data.xp)} / {Format.commas(need)} XP`
	self.coinText.Text = Format.commas(data.coins)
	self.rebirthText.Text = if data.rebirths > 0
		then `★ {data.rebirths} rebirth{if data.rebirths == 1 then "" else "s"}  (x{Progression.rewardMultiplier(data)})`
		else player.DisplayName
	self.pointsText.Text = if data.statPoints > 0 then `+{data.statPoints} stat points! Open the menu to spend` else ""
	self.menuBadge.Visible = data.statPoints > 0 or self:_dailyReady(data)

	for i = 0, GameConfig.LoadoutSize do
		local slot = self.slots[i]
		local moveId = if i == 0 then Moves.BASIC_ID else data.loadout[i]
		local move = moveId and Moves.byId[moveId]
		if move then
			slot.name.Text = move.short
			slot.name.TextColor3 = move.color
			slot.sub.Text = move.name
		else
			slot.name.Text = "—"
			slot.name.TextColor3 = C.Muted
			slot.sub.Text = "empty"
		end
	end
end

function HUD:_dailyReady(data): boolean
	return workspace:GetServerTimeNow() >= data.lastDaily + GameConfig.Daily.CooldownHours * 3600
end

function HUD:startCooldown(slotIndex: number, seconds: number)
	if seconds < 0.5 then
		return -- don't flash an overlay for tiny cooldowns like the basic punch
	end
	self.cooldowns[slotIndex] = { finish = os.clock() + seconds, duration = seconds }
	if not self.cooldownLoop then
		self.cooldownLoop = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			local any = false
			for i, cd in self.cooldowns do
				local slot = self.slots[i]
				local left = cd.finish - now
				if left <= 0 then
					self.cooldowns[i] = nil
					slot.overlay.Size = UDim2.fromScale(1, 0)
					slot.cdText.Text = ""
				else
					any = true
					slot.overlay.Size = UDim2.fromScale(1, left / cd.duration)
					slot.cdText.Text = string.format("%.1f", left)
				end
			end
			if not any then
				self.cooldownLoop:Disconnect()
				self.cooldownLoop = nil
			end
		end)
	end
end

function HUD:flashSlot(slotIndex: number)
	local slot = self.slots[slotIndex]
	if not slot then
		return
	end
	slot.stroke.Thickness = 4
	task.delay(0.08, function()
		slot.stroke.Thickness = 2
	end)
end

function HUD:toast(text: string, kind: string?)
	self.toastIndex = self.toastIndex % #self.toasts + 1
	self.toastOrder += 1
	local entry = self.toasts[self.toastIndex]
	if entry.tween then
		entry.tween:Cancel()
	end
	local l = entry.label
	l.LayoutOrder = self.toastOrder
	l.Text = text
	l.TextColor3 = TOAST_COLORS[kind or ""] or C.Text
	l.Visible = true
	l.TextTransparency = 0
	l.BackgroundTransparency = 0.3
	local tween = TweenService:Create(l, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2.2), {
		TextTransparency = 1,
		BackgroundTransparency = 1,
	})
	entry.tween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			l.Visible = false
		end
	end)
	tween:Play()
end

function HUD:levelUp(level: number)
	local l = self.levelBanner
	l.Text = `LEVEL {level}!`
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0
	l.Size = UDim2.fromOffset(300, 40)
	TweenService:Create(l, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(600, 80) }):Play()
	TweenService:Create(l, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.2), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

function HUD:setZone(zoneId: string)
	local zone = Zones.byId[zoneId]
	self.pvpTag.Visible = zone ~= nil and zone.pvp == true
	if not zone then
		return
	end
	self.zoneBanner.Text = string.upper(zone.name)
	self.zoneBanner.TextColor3 = zone.theme.trim
	self.zoneSub.Text = if zone.pvp then "PvP enabled: anyone can hit you here" else "Safe zone"
	self.zoneSub.TextColor3 = if zone.pvp then C.Bad else C.Muted
	for _, l in { self.zoneBanner, self.zoneSub } do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.3
		TweenService:Create(l, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end
end

function HUD:setStreak(count: number)
	local l = self.streakText
	if count < 3 then
		return
	end
	local bonus = math.floor(Progression.streakBonus(count) * 100 + 0.5)
	l.Text = `{count} HIT STREAK  +{bonus}% XP`
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.2
	if self.streakTween then
		self.streakTween:Cancel()
	end
	self.streakTween = TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, GameConfig.Streak.WindowSeconds - 0.4), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	self.streakTween:Play()
end

function HUD:koFeed(attacker: string, victim: string)
	self.feedOrder += 1
	local entry = UIKit.label(self.feed, {
		LayoutOrder = -self.feedOrder, -- newest on top
		Size = UDim2.fromOffset(280, 26),
		BackgroundColor3 = Color3.fromRGB(15, 15, 20),
		BackgroundTransparency = 0.3,
		TextSize = 14,
		RichText = true,
		Text = `<font color="#ffcc44">{attacker}</font>  KO'd  <font color="#ff6666">{victim}</font>`,
	})
	UIKit.corner(entry, 6)
	local children = {}
	for _, c in self.feed:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(children, c)
		end
	end
	if #children > 5 then
		table.sort(children, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		children[1]:Destroy() -- oldest
	end
	task.delay(8, function()
		if entry.Parent then
			entry:Destroy()
		end
	end)
end

return HUD
