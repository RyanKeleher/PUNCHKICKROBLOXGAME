-- The main menu: Stats / Moves / Shop / Rebirth tabs.
--
-- Rows are created ONCE from the config tables and then only their text and
-- colours are updated on each profile change. Rebuilding 30 rows on every
-- XP tick would churn memory for no reason.
--
-- Every button sends a request; the server decides. The UI greys things out
-- as a hint, but it never assumes a purchase worked: it waits for the next
-- profile push.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Moves = require(Shared.Config.Moves)
local Cosmetics = require(Shared.Config.Cosmetics)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local UIKit = require(script.Parent.UIKit)
local C = UIKit.Colors

local player = Players.LocalPlayer

local MenuUI = {}
MenuUI.__index = MenuUI

local W, H = 720, 470
local TABS = { "Stats", "Moves", "Shop", "Rebirth" }

local STAT_INFO = {
	power = { name = "POWER", color = Color3.fromRGB(255, 110, 80), blurb = "More damage and knockback" },
	agility = { name = "AGILITY", color = Color3.fromRGB(90, 220, 255), blurb = "Faster movement and shorter cooldowns" },
	vitality = { name = "VITALITY", color = Color3.fromRGB(110, 230, 120), blurb = "More max health" },
}

local function fire(name: string, ...)
	Remotes.get(name):FireServer(...)
end

local function scrolling(parent: Instance): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = UDim2.fromScale(1, 1)
	s.ScrollBarThickness = 6
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	UIKit.padding(s, 4)
	s.Parent = parent
	return s
end

local function row(parent: Instance, order: number, height: number): Frame
	local r = UIKit.frame(parent, {
		Size = UDim2.new(1, -12, 0, height),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = order,
	})
	UIKit.corner(r, 8)
	return r
end

local function setButton(b: TextButton, text: string, enabled: boolean, color: Color3?)
	b.Text = text
	b.Active = enabled
	b.AutoButtonColor = enabled
	b.BackgroundColor3 = if enabled then (color or C.Good) else Color3.fromRGB(70, 70, 80)
	b.TextColor3 = if enabled then C.Text else C.Muted
end

function MenuUI.new()
	local self = setmetatable({}, MenuUI)
	self.open = false
	self.data = nil
	self.shopCategory = "gloves"

	local gui = Instance.new("ScreenGui")
	gui.Name = "PK_Menu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui

	local panel = UIKit.frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 0.05,
		Active = true,
	})
	UIKit.corner(panel, 14)
	UIKit.stroke(panel, Color3.fromRGB(0, 0, 0), 3)
	UIKit.autoScale(panel, Vector2.new(W + 60, H + 60), 0.45, 1.15)
	self.panel = panel

	UIKit.label(panel, {
		Text = "PUNCH KICK",
		Font = Enum.Font.GothamBlack,
		TextSize = 24,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.fromOffset(200, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local close = UIKit.button(panel, "X", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(36, 32),
		BackgroundColor3 = C.Bad,
		Modal = true, -- frees the mouse in first person while the menu is open
	})
	close.Activated:Connect(function()
		self:setOpen(false)
	end)

	-- Tabs
	self.tabButtons = {}
	self.pages = {}
	local tabBar = UIKit.frame(panel, {
		Position = UDim2.fromOffset(14, 52),
		Size = UDim2.new(0, 130, 1, -66),
		BackgroundTransparency = 1,
	})
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local content = UIKit.frame(panel, {
		Position = UDim2.fromOffset(156, 52),
		Size = UDim2.new(1, -170, 1, -66),
		BackgroundColor3 = Color3.fromRGB(16, 16, 20),
	})
	UIKit.corner(content, 10)
	UIKit.padding(content, 8)

	for i, tab in TABS do
		local b = UIKit.button(tabBar, string.upper(tab), {
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = i,
			TextSize = 17,
		})
		b.Activated:Connect(function()
			self:showTab(tab)
		end)
		self.tabButtons[tab] = b
		local page = UIKit.frame(content, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
		self.pages[tab] = page
	end

	self:_buildStats(self.pages.Stats)
	self:_buildMoves(self.pages.Moves)
	self:_buildShop(self.pages.Shop)
	self:_buildRebirth(self.pages.Rebirth)
	self:showTab("Stats")
	return self
end

-- ===== Tabs =====

function MenuUI:showTab(name: string)
	self.tab = name
	for tab, page in self.pages do
		page.Visible = tab == name
		self.tabButtons[tab].BackgroundColor3 = if tab == name then C.Accent else C.Button
		self.tabButtons[tab].TextColor3 = if tab == name then Color3.fromRGB(40, 30, 0) else C.Text
	end
end

function MenuUI:setOpen(open: boolean)
	self.open = open
	self.gui.Enabled = open
	if open then
		if self.data then
			self:render(self.data)
		end
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.tabButtons[self.tab]
		end
		-- Tick once a second while open so countdowns (daily reward) stay live.
		local token = {}
		self.tickToken = token
		task.spawn(function()
			while self.open and self.tickToken == token do
				task.wait(1)
				if self.open and self.tickToken == token and self.data then
					self:_renderRebirth(self.data)
				end
			end
		end)
	else
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(self.gui) then
			GuiService.SelectedObject = nil
		end
	end
end

function MenuUI:toggle()
	self:setOpen(not self.open)
end

-- ===== Stats tab =====

function MenuUI:_buildStats(page: Frame)
	self.pointsLabel = UIKit.label(page, {
		Size = UDim2.new(1, 0, 0, 30),
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local list = UIKit.frame(page, { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38), BackgroundTransparency = 1 })
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	self.statRows = {}
	for i, stat in Progression.STATS do
		local info = STAT_INFO[stat]
		local r = row(list, i, 100)
		r.Size = UDim2.new(1, 0, 0, 100)
		UIKit.label(r, { Text = info.name, TextColor3 = info.color, Font = Enum.Font.GothamBlack, TextSize = 20, Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(200, 24), TextXAlignment = Enum.TextXAlignment.Left })
		UIKit.label(r, { Text = info.blurb, TextColor3 = C.Muted, TextSize = 13, Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(300, 18), TextXAlignment = Enum.TextXAlignment.Left })
		local value = UIKit.label(r, { TextSize = 15, Position = UDim2.fromOffset(12, 54), Size = UDim2.fromOffset(330, 18), TextXAlignment = Enum.TextXAlignment.Left })
		local effect = UIKit.label(r, { TextSize = 14, TextColor3 = info.color, Position = UDim2.fromOffset(12, 74), Size = UDim2.fromOffset(330, 18), TextXAlignment = Enum.TextXAlignment.Left })

		local buttons = {}
		for j, amount in { 1, 5, 25 } do
			local b = UIKit.button(r, `+{amount}`, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - (3 - j) * 62, 0.5, 0),
				Size = UDim2.fromOffset(56, 40),
			})
			b.Activated:Connect(function()
				fire("SpendStat", stat, amount)
			end)
			buttons[j] = b
		end
		self.statRows[stat] = { value = value, effect = effect, buttons = buttons }
	end
end

function MenuUI:_renderStats(data)
	self.pointsLabel.Text = `Stat points: {data.statPoints}`
	self.pointsLabel.TextColor3 = if data.statPoints > 0 then C.Good else C.Muted
	local cap = GameConfig.Progression.StatCap
	for stat, r in self.statRows do
		local v = data.stats[stat]
		r.value.Text = `{v} / {cap} points`
		if stat == "power" then
			r.effect.Text = string.format("Damage x%.2f   Knockback x%.2f", Progression.damageMultiplier(data), Progression.knockbackMultiplier(data))
		elseif stat == "agility" then
			r.effect.Text = string.format("Speed %.1f   Cooldowns x%.2f", Progression.walkSpeed(data), Progression.cooldownMultiplier(data))
		else
			r.effect.Text = string.format("Max health %d", Progression.maxHealth(data))
		end
		local canSpend = data.statPoints > 0 and v < cap
		for _, b in r.buttons do
			setButton(b, b.Text, canSpend, Color3.fromRGB(60, 150, 80))
		end
	end
end

-- ===== Moves tab =====

function MenuUI:_buildMoves(page: Frame)
	UIKit.label(page, {
		Text = "Unlock moves with coins, then put them in slots 1-4.",
		TextColor3 = C.Muted,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local holder = UIKit.frame(page, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26), BackgroundTransparency = 1 })
	local list = scrolling(holder)

	self.moveRows = {}
	for i, move in Moves.list do
		local r = row(list, i, 92)
		local swatch = UIKit.frame(r, { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = move.color })
		UIKit.corner(swatch, 8)
		UIKit.label(swatch, { Text = move.short, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = Color3.fromRGB(20, 20, 20) })

		UIKit.label(r, { Text = move.name, Font = Enum.Font.GothamBlack, TextSize = 17, Position = UDim2.fromOffset(76, 6), Size = UDim2.fromOffset(240, 20), TextXAlignment = Enum.TextXAlignment.Left })
		UIKit.label(r, {
			Text = move.description,
			TextColor3 = C.Muted,
			TextSize = 12,
			TextWrapped = true,
			Position = UDim2.fromOffset(76, 26),
			Size = UDim2.fromOffset(250, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local area = if move.hitbox.kind == "radius" then `AoE {move.hitbox.radius}` else "Front"
		UIKit.label(r, {
			Text = `DMG {move.damage}  ·  CD {move.cooldown}s  ·  {area}`,
			TextColor3 = move.color,
			TextSize = 12,
			Position = UDim2.fromOffset(76, 60),
			Size = UDim2.fromOffset(250, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local unlock = UIKit.button(r, "", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(150, 44),
			TextSize = 14,
		})
		unlock.Activated:Connect(function()
			fire("UnlockMove", move.id)
		end)

		local slotButtons = {}
		for s = 1, GameConfig.LoadoutSize do
			local b = UIKit.button(r, tostring(s), {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - (GameConfig.LoadoutSize - s) * 38, 0.5, 0),
				Size = UDim2.fromOffset(34, 40),
				Visible = false,
			})
			b.Activated:Connect(function()
				local data = self.data
				-- Clicking the slot it's already in removes it from that slot.
				if data and data.loadout[s] == move.id then
					fire("EquipMove", s, "")
				else
					fire("EquipMove", s, move.id)
				end
			end)
			slotButtons[s] = b
		end
		local basicTag = UIKit.label(r, {
			Text = "Always ready (click)",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(160, 20),
			TextColor3 = C.Accent,
			TextSize = 13,
			Visible = false,
		})
		self.moveRows[move.id] = { unlock = unlock, slots = slotButtons, basicTag = basicTag }
	end
end

function MenuUI:_renderMoves(data)
	for _, move in Moves.list do
		local r = self.moveRows[move.id]
		local owned = data.unlockedMoves[move.id] == true
		r.basicTag.Visible = move.basic == true
		if move.basic then
			r.unlock.Visible = false
			for _, b in r.slots do
				b.Visible = false
			end
		elseif owned then
			r.unlock.Visible = false
			for s, b in r.slots do
				b.Visible = true
				local here = data.loadout[s] == move.id
				b.BackgroundColor3 = if here then C.Accent else C.Button
				b.TextColor3 = if here then Color3.fromRGB(40, 30, 0) else C.Text
			end
		else
			for _, b in r.slots do
				b.Visible = false
			end
			r.unlock.Visible = true
			if data.level < move.unlockLevel then
				setButton(r.unlock, `🔒 Level {move.unlockLevel}`, false)
			elseif data.coins < move.price then
				setButton(r.unlock, `{Format.short(move.price)} coins`, false)
			else
				setButton(r.unlock, `UNLOCK  {Format.short(move.price)}`, true)
			end
		end
	end
end

-- ===== Shop tab (cosmetics) =====

function MenuUI:_buildShop(page: Frame)
	local cats = UIKit.frame(page, { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 })
	local catLayout = Instance.new("UIListLayout")
	catLayout.FillDirection = Enum.FillDirection.Horizontal
	catLayout.Padding = UDim.new(0, 6)
	catLayout.SortOrder = Enum.SortOrder.LayoutOrder
	catLayout.Parent = cats

	self.catButtons = {}
	for i, category in Cosmetics.Categories do
		local b = UIKit.button(cats, string.upper(Cosmetics.CategoryNames[category]), {
			Size = UDim2.fromOffset(100, 34),
			LayoutOrder = i,
			TextSize = 13,
		})
		b.Activated:Connect(function()
			self.shopCategory = category
			if self.data then
				self:_renderShop(self.data)
			end
		end)
		self.catButtons[category] = b
	end

	local holder = UIKit.frame(page, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1 })
	local list = scrolling(holder)
	self.shopRows = {}
	for _, item in Cosmetics.list do
		local r = row(list, item.order, 64)
		local swatch = UIKit.frame(r, { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = item.color })
		UIKit.corner(swatch, 24)
		if item.color2 then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(item.color, item.color2)
			g.Rotation = 45
			g.Parent = swatch
		end
		UIKit.label(r, { Text = item.name, Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = if item.category == "title" then item.color else C.Text, Position = UDim2.fromOffset(68, 10), Size = UDim2.fromOffset(240, 20), TextXAlignment = Enum.TextXAlignment.Left })
		local sub = UIKit.label(r, { TextColor3 = C.Muted, TextSize = 12, Position = UDim2.fromOffset(68, 32), Size = UDim2.fromOffset(240, 18), TextXAlignment = Enum.TextXAlignment.Left })
		local b = UIKit.button(r, "", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(140, 40),
			TextSize = 14,
		})
		b.Activated:Connect(function()
			local data = self.data
			if not data then
				return
			end
			if not data.ownedCosmetics[item.id] then
				fire("BuyCosmetic", item.id)
			elseif data.equipped[item.category] == item.id then
				fire("EquipCosmetic", item.category, "")
			else
				fire("EquipCosmetic", item.category, item.id)
			end
		end)
		self.shopRows[item.id] = { frame = r, button = b, sub = sub, item = item }
	end
end

function MenuUI:_renderShop(data)
	for category, b in self.catButtons do
		b.BackgroundColor3 = if category == self.shopCategory then C.Accent else C.Button
		b.TextColor3 = if category == self.shopCategory then Color3.fromRGB(40, 30, 0) else C.Text
	end
	for id, r in self.shopRows do
		local item = r.item
		r.frame.Visible = item.category == self.shopCategory
		local owned = data.ownedCosmetics[id] == true
		if owned then
			r.sub.Text = "Owned"
			local equipped = data.equipped[item.category] == id
			setButton(r.button, if equipped then "UNEQUIP" else "EQUIP", true, if equipped then Color3.fromRGB(150, 90, 40) else C.Good)
		else
			local needRebirths = item.requiresRebirths > data.rebirths
			r.sub.Text = if item.requiresRebirths > 0 then `Requires ★{item.requiresRebirths}` else "Cosmetic"
			if needRebirths then
				setButton(r.button, `🔒 ★{item.requiresRebirths}`, false)
			else
				setButton(r.button, `BUY  {Format.short(item.price)}`, data.coins >= item.price, Color3.fromRGB(200, 150, 30))
			end
		end
	end
end

-- ===== Rebirth tab =====

function MenuUI:_buildRebirth(page: Frame)
	local r = row(page, 1, 220)
	r.Size = UDim2.new(1, 0, 0, 220)
	UIKit.label(r, { Text = "REBIRTH", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(255, 120, 220), Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(300, 28), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.label(r, {
		Text = `Reset to level 1 and lose your stat points, but keep your moves and cosmetics and earn +{math.floor(GameConfig.Rebirth.RewardBonusPerRebirth * 100)}% XP and coins forever. Requires level {GameConfig.Rebirth.MinLevel}.`,
		TextWrapped = true,
		TextColor3 = C.Muted,
		TextSize = 14,
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -28, 0, 56),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	self.rebirthInfo = UIKit.label(r, { TextSize = 15, Position = UDim2.fromOffset(14, 106), Size = UDim2.new(1, -28, 0, 44), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, RichText = true })
	self.rebirthButton = UIKit.button(r, "REBIRTH", {
		Position = UDim2.fromOffset(14, 160),
		Size = UDim2.fromOffset(220, 46),
		TextSize = 18,
	})
	self.rebirthButton.Activated:Connect(function()
		if self.rebirthButton.Active then
			fire("Rebirth")
		end
	end)

	local d = row(page, 2, 120)
	d.Position = UDim2.fromOffset(0, 232)
	d.Size = UDim2.new(1, 0, 0, 120)
	UIKit.label(d, { Text = "DAILY REWARD", Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = C.Coin, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(300, 26), TextXAlignment = Enum.TextXAlignment.Left })
	self.dailyInfo = UIKit.label(d, { TextSize = 14, TextColor3 = C.Muted, Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
	self.dailyButton = UIKit.button(d, "CLAIM", { Position = UDim2.fromOffset(14, 64), Size = UDim2.fromOffset(220, 44), TextSize = 18 })
	self.dailyButton.Activated:Connect(function()
		if self.dailyButton.Active then
			fire("ClaimDaily")
		end
	end)
end

function MenuUI:_renderRebirth(data)
	local cost = Progression.rebirthCost(data.rebirths)
	local ok, reason = Progression.canRebirth(data)
	local nextMult = 1 + (data.rebirths + 1) * GameConfig.Rebirth.RewardBonusPerRebirth
	self.rebirthInfo.Text = `Rebirths: <b>{data.rebirths}</b>   ·   Cost: <b>{Format.commas(cost)}</b> coins   ·   Next bonus: <b>x{nextMult}</b>`
	setButton(self.rebirthButton, if ok then "REBIRTH NOW" else (reason or "LOCKED"), ok, Color3.fromRGB(200, 70, 170))

	local cooldown = GameConfig.Daily.CooldownHours * 3600
	local remaining = data.lastDaily + cooldown - workspace:GetServerTimeNow()
	local reward = math.floor((GameConfig.Daily.CoinsBase + data.level * GameConfig.Daily.CoinsPerLevel) * Progression.rewardMultiplier(data))
	if remaining <= 0 then
		self.dailyInfo.Text = `Ready! +{Format.commas(reward)} coins`
		setButton(self.dailyButton, "CLAIM", true, Color3.fromRGB(200, 150, 30))
	else
		self.dailyInfo.Text = `Come back in {Format.duration(remaining)}`
		setButton(self.dailyButton, "CLAIMED", false)
	end
end

-- ===== Render =====

function MenuUI:render(data)
	self.data = data
	if not self.open then
		return -- cheap: only redraw while visible (setOpen re-renders)
	end
	self:_renderStats(data)
	self:_renderMoves(data)
	self:_renderShop(data)
	self:_renderRebirth(data)
end

return MenuUI
