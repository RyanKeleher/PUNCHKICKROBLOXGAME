-- Type guards for data arriving from clients. A client can send ANY value
-- (strings, tables, NaN, inf, huge numbers), so every remote argument passes
-- through one of these before it is used.

local Validate = {}

-- Integer in [min, max]. Rejects non-numbers, NaN (v ~= v), inf, and fractions.
function Validate.int(v: any, min: number, max: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= min and v <= max
end

return Validate
