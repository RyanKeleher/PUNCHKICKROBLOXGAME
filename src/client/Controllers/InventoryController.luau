-- Client-side inventory: holds the latest server snapshot, turns player input
-- into *requests* to the server, and asks the view to redraw.
--
-- Input map
--   PC:         Tab / I toggle inventory · 1-6 or mouse wheel select hotbar
--               drag = move/merge/swap · right-click = split half
--               drag outside the UI = drop the stack · E = pick up (ProximityPrompt)
--   Controller: Y toggle inventory · LB/RB cycle hotbar · B close
--               A on a slot = select · MOVE button then A on target = move
--   Mobile:     BAG button toggles · tap hotbar slot = equip
--               drag works with touch · tap slot + MOVE/SPLIT/DROP buttons
--
-- Nothing here is trusted by the server. If the client lies, the server's
-- validation rejects it and the next snapshot corrects the UI.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local InventoryView = require(script.Parent.Parent.UI.InventoryView)

local player = Players.LocalPlayer
local HOTBAR = Config.Inventory.HotbarSize
local TOTAL = HOTBAR + Config.Inventory.MainSize
local DRAG_THRESHOLD = 8 -- pixels of movement before a press becomes a drag

local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
}

local InventoryController = {}

local state = {
	slots = {} :: { any },
	selected = nil :: number?,
	moveArmed = false,
	open = false,
	equipped = 0,
}

local view
local drag: { slot: number, start: Vector2, active: boolean, input: InputObject }? = nil
local lastDragEnd = 0

local function render()
	view:render(state)
end

local function fire(name: string, ...)
	Remotes.get(name):FireServer(...)
end

local function clearSelection()
	state.selected = nil
	state.moveArmed = false
end

-- ===== Hotbar =====

local function equip(index: number)
	-- Optimistic update so the highlight feels instant; the server's
	-- EquippedSlot attribute is the final word.
	state.equipped = index
	fire("EquipSlot", index)
	render()
end

local function toggleEquip(index: number)
	equip(if state.equipped == index then 0 else index)
end

local function cycleHotbar(direction: number)
	local current = if state.equipped == 0 then (if direction > 0 then 0 else 1) else state.equipped
	equip((current - 1 + direction) % HOTBAR + 1)
end

-- ===== Open / close =====

local function setOpen(open: boolean)
	state.open = open
	if not open then
		clearSelection()
		if drag then
			drag = nil
			view:hideGhost()
		end
	end
	view:setOpen(open)

	-- Controller: put gamepad selection on the first grid slot when opening.
	if open and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = view:slotButton(HOTBAR + 1)
	elseif not open then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.gui) then
			GuiService.SelectedObject = nil
		end
	end
	render()
end

-- ===== Slot clicks (mouse click, touch tap, gamepad A all fire Activated) =====

local function onSlotActivated(index: number)
	-- Ignore the click that ends a drag.
	if (drag and drag.active) or os.clock() - lastDragEnd < 0.15 then
		return
	end

	if not state.open then
		if index <= HOTBAR then
			toggleEquip(index)
		end
		return
	end

	if state.moveArmed and state.selected then
		if state.selected ~= index then
			fire("InventoryMove", state.selected, index)
		end
		clearSelection()
	elseif state.selected == index then
		clearSelection()
	elseif state.slots[index] then
		state.selected = index
	end
	render()
end

-- ===== Drag and drop (mouse + touch) =====

local function onSlotInputBegan(index: number, input: InputObject)
	if not state.open then
		return
	end
	local stack = state.slots[index]
	if not stack then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if stack.count > 1 then
			fire("InventorySplit", index, math.floor(stack.count / 2))
		end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		drag = {
			slot = index,
			start = Vector2.new(input.Position.X, input.Position.Y),
			active = false,
			input = input,
		}
	end
end

local function isDragInput(input: InputObject, current): boolean
	if input.UserInputType == Enum.UserInputType.Touch then
		return input == current.input -- the same finger that started the drag
	end
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function onInputChanged(input: InputObject)
	local current = drag
	if not current or not isDragInput(input, current) then
		return
	end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if not current.active and (pos - current.start).Magnitude > DRAG_THRESHOLD then
		local stack = state.slots[current.slot]
		if not stack then
			drag = nil
			return
		end
		current.active = true
		view:showGhost(stack, pos)
	end
	if current.active then
		view:moveGhost(pos)
	end
end

local function onInputEnded(input: InputObject)
	local current = drag
	if not current or not isDragInput(input, current) then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		return
	end
	drag = nil
	if not current.active then
		return -- it was a click/tap; Activated handles it
	end

	view:hideGhost()
	lastDragEnd = os.clock()

	local pos = Vector2.new(input.Position.X, input.Position.Y)
	local target = view:slotAt(pos)
	local stack = state.slots[current.slot]
	if target then
		if target ~= current.slot then
			fire("InventoryMove", current.slot, target)
		end
	elseif stack and not view:isOverUi(pos) then
		fire("InventoryDrop", current.slot, stack.count)
	end
	clearSelection()
	render()
end

-- ===== Keyboard / gamepad =====

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	local key = input.KeyCode

	-- Gamepad buttons: gameProcessed is true whenever a GUI is selected, so
	-- we handle these regardless.
	if key == Enum.KeyCode.ButtonY then
		setOpen(not state.open)
		return
	elseif key == Enum.KeyCode.ButtonB and state.open then
		setOpen(false)
		return
	elseif (key == Enum.KeyCode.ButtonL1 or key == Enum.KeyCode.ButtonR1) and not state.open then
		cycleHotbar(if key == Enum.KeyCode.ButtonR1 then 1 else -1)
		return
	end

	if gameProcessed then
		return -- typing in chat, etc.
	end

	if key == Enum.KeyCode.Tab or key == Enum.KeyCode.I then
		setOpen(not state.open)
	elseif NUMBER_KEYS[key] then
		toggleEquip(NUMBER_KEYS[key])
	end
end

local function onWheel(input: InputObject, gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or gameProcessed or state.open then
		return
	end
	-- Wheel down (negative Z) moves right, like most games.
	cycleHotbar(if input.Position.Z < 0 then 1 else -1)
end

-- ===== Start =====

function InventoryController.start()
	view = InventoryView.new(player:WaitForChild("PlayerGui") :: PlayerGui, TOTAL, HOTBAR)

	for i = 1, TOTAL do
		state.slots[i] = false
		local b = view:slotButton(i)
		b.Activated:Connect(function()
			onSlotActivated(i)
		end)
		b.InputBegan:Connect(function(input)
			onSlotInputBegan(i, input)
		end)
	end

	view.closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	view.bagButton.Activated:Connect(function()
		setOpen(not state.open)
	end)

	view.moveButton.Activated:Connect(function()
		if state.selected then
			state.moveArmed = not state.moveArmed
			render()
		end
	end)
	view.splitButton.Activated:Connect(function()
		local stack = state.selected and state.slots[state.selected]
		if stack and stack.count > 1 then
			fire("InventorySplit", state.selected, math.floor(stack.count / 2))
			clearSelection()
			render()
		end
	end)
	view.dropOneButton.Activated:Connect(function()
		if state.selected and state.slots[state.selected] then
			fire("InventoryDrop", state.selected, 1)
		end
	end)
	view.dropAllButton.Activated:Connect(function()
		local stack = state.selected and state.slots[state.selected]
		if stack then
			fire("InventoryDrop", state.selected, stack.count)
			clearSelection()
			render()
		end
	end)

	Remotes.get("InventoryUpdated").OnClientEvent:Connect(function(slots)
		if type(slots) ~= "table" then
			return
		end
		state.slots = slots
		if state.selected and not slots[state.selected] then
			clearSelection()
		end
		render()
	end)

	Remotes.get("Notify").OnClientEvent:Connect(function(text)
		if type(text) == "string" then
			view:toast(text)
		end
	end)

	local function readEquipped()
		local value = player:GetAttribute("EquippedSlot")
		state.equipped = if type(value) == "number" then value else 0
		render()
	end
	player:GetAttributeChangedSignal("EquippedSlot"):Connect(readEquipped)
	readEquipped()

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		onInputChanged(input)
		onWheel(input, gameProcessed)
	end)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- Ask for a snapshot in case the server's first one arrived before we listened.
	fire("RequestSync")
end

return InventoryController
