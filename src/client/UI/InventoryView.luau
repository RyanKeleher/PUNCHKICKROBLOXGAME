-- Builds and draws the inventory + hotbar UI entirely from code (no hand-made
-- ScreenGui to keep in sync). It knows nothing about remotes or input rules:
-- the controller owns state and calls view:render(state) whenever it changes.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared.ItemDefinitions)

local SLOT = 64
local GAP = 6
local COLS = 6
local PAD = 12
local HEADER = 32
local INFO_W = 220

local COLOR_BG = Color3.fromRGB(22, 22, 24)
local COLOR_SLOT = Color3.fromRGB(38, 38, 42)
local COLOR_STROKE = Color3.fromRGB(70, 70, 76)
local COLOR_SELECTED = Color3.fromRGB(255, 200, 60)
local COLOR_MOVE = Color3.fromRGB(80, 200, 255)
local COLOR_EQUIPPED = Color3.fromRGB(240, 240, 240)
local COLOR_TEXT = Color3.fromRGB(235, 235, 235)
local COLOR_MUTED = Color3.fromRGB(160, 160, 165)

local InventoryView = {}
InventoryView.__index = InventoryView

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = COLOR_TEXT
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 14
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
	b.TextColor3 = COLOR_TEXT
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.AutoButtonColor = true
	b.Selectable = true
	corner(b, 6)
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	b.Parent = parent
	return b
end

local function makeSlot(parent: Instance, index: number, keyText: string?)
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. index
	b.LayoutOrder = index
	b.Size = UDim2.fromOffset(SLOT, SLOT)
	b.BackgroundColor3 = COLOR_SLOT
	b.BackgroundTransparency = 0.1
	b.AutoButtonColor = false
	b.Text = ""
	b.Selectable = true
	corner(b, 6)

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = COLOR_STROKE
	stroke.Thickness = 1
	stroke.Parent = b

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.fromScale(0.5, 0.5)
	swatch.Size = UDim2.new(1, -16, 1, -16)
	swatch.BorderSizePixel = 0
	swatch.Visible = false
	corner(swatch, 4)
	swatch.Parent = b

	local short = label(swatch, {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
	})

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.new(1, -10, 1, -10)
	icon.Visible = false
	icon.Parent = b

	local count = label(b, {
		Size = UDim2.new(1, -6, 0, 16),
		Position = UDim2.new(0, 0, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.3,
		ZIndex = 3,
	})

	if keyText then
		label(b, {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromOffset(4, 2),
			Text = keyText,
			TextSize = 11,
			TextColor3 = COLOR_MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
	end

	b.Parent = parent
	return { button = b, stroke = stroke, swatch = swatch, short = short, icon = icon, count = count }
end

function InventoryView.new(playerGui: PlayerGui, totalSlots: number, hotbarSize: number)
	local self = setmetatable({}, InventoryView)
	self.hotbarSize = hotbarSize
	self.slots = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false -- keep the UI (and its connections) across deaths
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = false -- keeps AbsolutePosition in the same space as InputObject.Position
	self.gui = gui

	-- ===== Hotbar (always visible) =====
	local hotbarWidth = hotbarSize * SLOT + (hotbarSize - 1) * GAP
	local hotbar = Instance.new("Frame")
	hotbar.Name = "Hotbar"
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.new(0.5, 0, 1, -12)
	hotbar.Size = UDim2.fromOffset(hotbarWidth, SLOT)
	hotbar.BackgroundTransparency = 1
	hotbar.Parent = gui
	self.hotbar = hotbar
	self.hotbarScale = Instance.new("UIScale")
	self.hotbarScale.Parent = hotbar

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = hotbar

	for i = 1, hotbarSize do
		self.slots[i] = makeSlot(hotbar, i, tostring(i))
	end

	-- Mobile: a "Bag" button left of the hotbar opens the inventory.
	-- (Positioned in applyScale below so it tracks the scaled hotbar.)
	self.bagButton = button(gui, "BAG", {
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(SLOT, SLOT),
		Visible = UserInputService.TouchEnabled,
	})
	self.bagScale = Instance.new("UIScale")
	self.bagScale.Parent = self.bagButton

	-- ===== Inventory panel (toggled) =====
	local gridHeight = 4 * SLOT + 3 * GAP
	local panelWidth = PAD + hotbarWidth + PAD + INFO_W + PAD
	local panelHeight = HEADER + PAD + gridHeight + PAD

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	panel.BackgroundColor3 = COLOR_BG
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Active = true -- swallow clicks so they don't fall through to the world
	corner(panel, 10)
	panel.Parent = gui
	self.panel = panel
	self.panelScale = Instance.new("UIScale")
	self.panelScale.Parent = panel

	label(panel, {
		Text = "INVENTORY",
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(PAD, 6),
		Size = UDim2.fromOffset(200, HEADER - 6),
	})

	-- Modal = true frees the mouse even in first person while the panel is open.
	self.closeButton = button(panel, "X", {
		Size = UDim2.fromOffset(28, 24),
		Position = UDim2.new(1, -PAD - 28, 0, 6),
		Modal = true,
	})

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(PAD, HEADER + PAD)
	grid.Size = UDim2.fromOffset(hotbarWidth, gridHeight)
	grid.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(SLOT, SLOT)
	gridLayout.CellPadding = UDim2.fromOffset(GAP, GAP)
	gridLayout.FillDirectionMaxCells = COLS
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	for i = hotbarSize + 1, totalSlots do
		self.slots[i] = makeSlot(grid, i, nil)
	end

	-- ===== Info / actions panel =====
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	info.Position = UDim2.fromOffset(PAD + hotbarWidth + PAD, HEADER + PAD)
	info.Size = UDim2.fromOffset(INFO_W, gridHeight)
	corner(info, 8)
	info.Parent = panel

	self.infoName = label(info, {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 22),
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.infoAmount = label(info, {
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.new(1, -20, 0, 16),
		TextColor3 = COLOR_MUTED,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.infoDesc = label(info, {
		Position = UDim2.fromOffset(10, 52),
		Size = UDim2.new(1, -20, 0, 70),
		TextColor3 = COLOR_MUTED,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(0, 1)
	actions.Position = UDim2.new(0, 10, 1, -10)
	actions.Size = UDim2.new(1, -20, 0, 4 * 30 + 3 * 6)
	actions.Parent = info
	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.Padding = UDim.new(0, 6)
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	actionsLayout.Parent = actions

	local function action(text: string, order: number): TextButton
		return button(actions, text, { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order })
	end
	self.moveButton = action("MOVE", 1)
	self.splitButton = action("SPLIT HALF", 2)
	self.dropOneButton = action("DROP 1", 3)
	self.dropAllButton = action("DROP ALL", 4)

	-- ===== Drag ghost + toast (unscaled, positioned in raw screen pixels) =====
	local ghost = Instance.new("Frame")
	ghost.Name = "DragGhost"
	ghost.Visible = false
	ghost.BackgroundTransparency = 0.25
	ghost.ZIndex = 50
	corner(ghost, 6)
	ghost.Parent = gui
	self.ghost = ghost
	self.ghostLabel = label(ghost, {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextStrokeTransparency = 0.4,
		ZIndex = 51,
	})

	local toast = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(320, 34),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
	})
	corner(toast, 8)
	self.toastLabel = toast

	-- ===== Responsive scaling =====
	local camera = workspace.CurrentCamera
	local function applyScale()
		local vp = camera.ViewportSize
		local scale = math.clamp(math.min(vp.X / (panelWidth + 80), vp.Y / (panelHeight + SLOT + 80)), 0.5, 1.25)
		self.hotbarScale.Scale = scale
		self.panelScale.Scale = scale
		self.bagScale.Scale = scale
		self.bagButton.Position = UDim2.new(0.5, -(hotbarWidth / 2 + GAP * 2) * scale, 1, -12)
		-- Sit the panel just above the (scaled) hotbar.
		panel.Position = UDim2.new(0.5, 0, 1, -(12 + (SLOT + 14) * scale))
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	applyScale()

	gui.Parent = playerGui
	return self
end

function InventoryView:setOpen(open: boolean)
	self.panel.Visible = open
end

local function within(obj: GuiObject, pos: Vector2): boolean
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

-- Which slot index is under a screen position (InputObject.Position space)?
function InventoryView:slotAt(pos: Vector2): number?
	for i, ui in self.slots do
		local visible = i <= self.hotbarSize or self.panel.Visible
		if visible and within(ui.button, pos) then
			return i
		end
	end
	return nil
end

function InventoryView:isOverUi(pos: Vector2): boolean
	return (self.panel.Visible and within(self.panel, pos)) or within(self.hotbar, pos)
end

function InventoryView:slotButton(i: number): TextButton
	return self.slots[i].button
end

-- ===== Drag ghost =====

function InventoryView:showGhost(stack, pos: Vector2)
	local def = ItemDefinitions.get(stack.id)
	local size = self.slots[1].button.AbsoluteSize
	self.ghost.Size = UDim2.fromOffset(size.X, size.Y)
	self.ghost.BackgroundColor3 = if def then def.color else COLOR_SLOT
	self.ghostLabel.Text = if def then def.short else "?"
	self.ghost.Visible = true
	self:moveGhost(pos)
end

function InventoryView:moveGhost(pos: Vector2)
	-- Read the offset we set (AbsoluteSize may lag a frame behind a Size change).
	local size = self.ghost.Size
	self.ghost.Position = UDim2.fromOffset(pos.X - size.X.Offset / 2, pos.Y - size.Y.Offset / 2)
end

function InventoryView:hideGhost()
	self.ghost.Visible = false
end

-- ===== Toast (single pooled label, re-used for every message) =====

function InventoryView:toast(text: string)
	local l = self.toastLabel
	if self.toastTween then
		self.toastTween:Cancel()
	end
	l.Text = text
	l.TextTransparency = 0
	l.BackgroundTransparency = 0.35
	local tween = TweenService:Create(
		l,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.6),
		{ TextTransparency = 1, BackgroundTransparency = 1 }
	)
	self.toastTween = tween
	tween:Play()
end

-- ===== Render =====

function InventoryView:render(state)
	for i, ui in self.slots do
		local stack = state.slots[i]
		local def = if stack then ItemDefinitions.get(stack.id) else nil

		if stack and def then
			local hasIcon = def.icon ~= nil and def.icon ~= ""
			ui.icon.Visible = hasIcon
			ui.icon.Image = if hasIcon then def.icon else ""
			ui.swatch.Visible = not hasIcon
			ui.swatch.BackgroundColor3 = def.color
			ui.short.Text = def.short
			ui.count.Text = if stack.count > 1 then tostring(stack.count) else ""
		else
			ui.icon.Visible = false
			ui.swatch.Visible = false
			ui.count.Text = ""
		end

		local isSelected = state.open and state.selected == i
		local isEquipped = i <= self.hotbarSize and state.equipped == i
		if isSelected then
			ui.stroke.Color = if state.moveArmed then COLOR_MOVE else COLOR_SELECTED
			ui.stroke.Thickness = 2
		elseif isEquipped then
			ui.stroke.Color = COLOR_EQUIPPED
			ui.stroke.Thickness = 2
		else
			ui.stroke.Color = COLOR_STROKE
			ui.stroke.Thickness = 1
		end
		ui.button.BackgroundColor3 = if isEquipped then Color3.fromRGB(60, 60, 66) else COLOR_SLOT
	end

	-- Info panel
	local selectedStack = if state.selected then state.slots[state.selected] else nil
	local def = if selectedStack then ItemDefinitions.get(selectedStack.id) else nil
	if selectedStack and def then
		self.infoName.Text = def.name
		self.infoAmount.Text = `{def.category}  ·  {selectedStack.count} / {def.maxStack}`
		self.infoDesc.Text = def.description
		self.moveButton.Visible = true
		self.moveButton.Text = if state.moveArmed then "PICK A SLOT..." else "MOVE"
		self.splitButton.Visible = selectedStack.count > 1
		self.dropOneButton.Visible = true
		self.dropAllButton.Visible = selectedStack.count > 1
	else
		self.infoName.Text = "No item selected"
		self.infoAmount.Text = ""
		self.infoDesc.Text = "Click a slot to inspect it. Drag to move, right-click to split, drag outside to drop."
		self.moveButton.Visible = false
		self.splitButton.Visible = false
		self.dropOneButton.Visible = false
		self.dropAllButton.Visible = false
	end
end

return InventoryView
