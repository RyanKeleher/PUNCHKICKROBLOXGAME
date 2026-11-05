-- Type guards for data coming from clients. Exploiters can send ANY value:
-- wrong types, NaN, inf, giant strings, tables. Check everything.

local Validate = {}

-- Whole number in [min, max]. Rejects NaN (v ~= v), inf and fractions.
function Validate.int(v: any, min: number, max: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= min and v <= max
end

-- Short string (stops megabyte-long ids being used as table keys).
function Validate.str(v: any, maxLen: number?): boolean
	return type(v) == "string" and #v <= (maxLen or 64)
end

-- A finite Vector3 (no NaN/inf components).
function Validate.vector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local m = v.Magnitude
	return m == m and m < math.huge
end

return Validate
