--!strict
-- Pure inventory operations on an array of slots. No networking, no Instances,
-- no yielding: every function finishes in one step. That makes them easy to unit
-- test and, more importantly, atomic on the server (nothing can interleave
-- between "remove from inventory" and "spawn in world", which is how dupes happen).
--
-- An inventory is a dense array where an empty slot is `false` (not nil).
-- Why false? Arrays with nil holes get truncated/mangled when sent through a
-- RemoteEvent, and `#slots` is undefined with holes. `false` keeps it dense.

local ItemDefinitions = require(script.Parent.ItemDefinitions)

export type Stack = { id: string, count: number }
export type Slot = Stack | false
export type Slots = { Slot }

local InventoryLogic = {}

local function maxStackOf(id: string): number
	local def = ItemDefinitions.get(id)
	return if def then def.maxStack else 1
end

function InventoryLogic.new(size: number): Slots
	local slots: Slots = {}
	for i = 1, size do
		slots[i] = false
	end
	return slots
end

-- Adds `count` of `id`. First tops up existing stacks of the same item anywhere,
-- then fills empty slots in `order`. Returns how many did NOT fit.
function InventoryLogic.add(slots: Slots, id: string, count: number, order: { number }): number
	local max = maxStackOf(id)
	local remaining = count

	for i = 1, #slots do
		if remaining <= 0 then
			break
		end
		local s = slots[i]
		if s and s.id == id and s.count < max then
			local n = math.min(max - s.count, remaining)
			s.count += n
			remaining -= n
		end
	end

	for _, i in order do
		if remaining <= 0 then
			break
		end
		if slots[i] == false then
			local n = math.min(max, remaining)
			slots[i] = { id = id, count = n }
			remaining -= n
		end
	end

	return remaining
end

-- Moves the stack at `from` onto `to`:
--   empty target          -> move
--   same item, has room   -> merge (remainder stays in `from`)
--   anything else         -> swap
function InventoryLogic.move(slots: Slots, from: number, to: number): boolean
	if from == to then
		return false
	end
	local a = slots[from]
	if not a then
		return false
	end
	local b = slots[to]

	if b and b.id == a.id then
		local max = maxStackOf(a.id)
		if b.count < max then
			local n = math.min(max - b.count, a.count)
			b.count += n
			a.count -= n
			if a.count <= 0 then
				slots[from] = false
			end
			return true
		end
	end

	slots[from] = b
	slots[to] = a
	return true
end

-- Splits `amount` off the stack at `index` into the first empty slot in `order`.
function InventoryLogic.split(slots: Slots, index: number, amount: number, order: { number }): boolean
	local s = slots[index]
	if not s or amount < 1 or amount >= s.count then
		return false
	end
	for _, i in order do
		if slots[i] == false then
			s.count -= amount
			slots[i] = { id = s.id, count = amount }
			return true
		end
	end
	return false
end

-- Removes up to `amount` from one slot and returns what was removed.
function InventoryLogic.take(slots: Slots, index: number, amount: number): Stack?
	local s = slots[index]
	if not s or amount < 1 then
		return nil
	end
	local n = math.min(amount, s.count)
	s.count -= n
	if s.count <= 0 then
		slots[index] = false
	end
	return { id = s.id, count = n }
end

-- Total count of an item across all slots (used by crafting in Phase 3).
function InventoryLogic.count(slots: Slots, id: string): number
	local total = 0
	for _, s in slots do
		if s and s.id == id then
			total += s.count
		end
	end
	return total
end

-- Removes `count` of an item across slots (last slots first). Returns amount removed.
function InventoryLogic.remove(slots: Slots, id: string, count: number): number
	local remaining = count
	for i = #slots, 1, -1 do
		if remaining <= 0 then
			break
		end
		local s = slots[i]
		if s and s.id == id then
			local n = math.min(s.count, remaining)
			s.count -= n
			remaining -= n
			if s.count <= 0 then
				slots[i] = false
			end
		end
	end
	return count - remaining
end

return InventoryLogic
